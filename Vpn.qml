pragma Singleton

// Estado e perfis de VPN via NetworkManager.
// O Quickshell.Networking só expõe dispositivos Wifi/Wired — conexões VPN não
// aparecem lá. Então consultamos o nmcli, mas só quando algo muda:
// - `ip monitor link` fica dormindo (0% CPU) e emite uma linha a cada evento
//   de link do kernel — uma VPN cria/remove um tun/wg/ppp, então isso cobre
//   conectar/desconectar (inclusive ativações feitas fora do shell);
// - ao chegar evento, uma consulta ao nmcli (com debounce) atualiza o estado;
// - fallback de 5min garante o estado mesmo se o watcher falhar.
// Usado pelo ícone de rede do Control Center (muda com VPN ativa) e pelo menu
// de VPNs (VpnMenu.qml).
//
// IPC: qs -c skye ipc call vpn get|refresh|up <nome>|down <nome>

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Perfis de VPN/WireGuard: [{ name, type, state }, ...]
    property var profiles: []
    // true enquanto houver VPN ativando/ativada
    property bool active: false
    // Nome do perfil com connect/disconnect em andamento ("" = nenhum)
    property string busy: ""

    // Dispara uma consulta (se não houver uma em andamento)
    function query() {
        if (!vpnProc.running)
            vpnProc.running = true;
    }

    // Conecta/desconecta um perfil (assíncrono; ignora se já houver ação)
    function setConnected(name, on) {
        if (toggleProc.running)
            return;
        root.busy = name;
        toggleProc.command = ["nmcli", "connection", on ? "up" : "down", name];
        toggleProc.running = true;
    }

    // Watcher dormente: imprime uma linha por evento de link do kernel.
    Process {
        id: linkWatch

        command: ["ip", "monitor", "link"]
        running: true

        stdout: SplitParser {
            onRead: line => refresh.restart()
        }

        onExited: watcherRestart.restart()
    }

    // Se o watcher morrer, tenta de novo
    Timer {
        id: watcherRestart

        interval: 10000
        onTriggered: if (!linkWatch.running) linkWatch.running = true
    }

    // Agrupa rajadas de eventos (conectar gera vários) numa consulta só
    Timer {
        id: refresh

        interval: 400
        onTriggered: root.query()
    }

    // Fallback: auto-recuperação se o watcher falhar
    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: root.query()
    }

    // Todas as conexões (não só as ativas): precisamos dos perfis de VPN
    // mesmo quando desligados, para listá-los no menu.
    Process {
        id: vpnProc

        // Saída (terse): uma linha "tipo:nome:estado" por conexão, ex.:
        //   vpn:minha-vpn:activated
        //   802-3-ethernet:Wired connection 2:activated
        command: ["nmcli", "-t", "-f", "TYPE,NAME,STATE", "connection", "show"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const out = [];
                let active = false;
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (line === "")
                        continue;
                    // tipo não tem ":", o estado é o último campo (vazio
                    // quando a conexão está inativa) e o nome é o miolo
                    // (guloso) — colons no nome vêm escapados pelo nmcli
                    const m = line.match(/^([^:]+):(.*):(.*)$/);
                    if (m === null || (m[1] !== "vpn" && m[1] !== "wireguard"))
                        continue;
                    const name = m[2].replace(/\\:/g, ":").replace(/\\\\/g, "\\");
                    out.push({ name: name, type: m[1], state: m[3] });
                    if (m[3] === "activating" || m[3] === "activated")
                        active = true;
                }
                root.profiles = out;
                root.active = active;
            }
        }
    }

    // Ação de conectar/desconectar disparada pelo menu
    Process {
        id: toggleProc

        onExited: {
            root.busy = "";
            root.query();
        }
    }

    // Estado inicial
    Component.onCompleted: query()

    IpcHandler {
        target: "vpn"

        function get(): bool { return root.active; }
        function refresh(): void { root.query(); }
        function up(connection: string): void { root.setConnected(connection, true); }
        function down(connection: string): void { root.setConnected(connection, false); }
    }
}
