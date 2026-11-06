pragma Singleton

// Ar-condicionado Midea — controle LOCAL (protocolo V3), sem nuvem.
// O midea_rpc.py (mesmo padrão do discord_rpc.py) mantém a conexão com o
// aparelho: comandos JSON por stdin, status JSON por stdout. O token/key ficam
// em ~/.config/skye/midea.json (extraídos uma vez; depois é 100% local).
// IPC: qs -c skye ipc call midea status|refresh|power <bool>|mode <str>|
//      temp <n>|fan <str>|swing <str>|eco <bool>|turbo <bool>|display <bool>

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string pythonBin: Quickshell.env("HOME") + "/.local/share/skye/midea-venv/bin/python"
    readonly property string configFile: Quickshell.env("HOME") + "/.config/skye/midea.json"

    property bool configured: false
    property bool online: false
    // Estado do painel do ar (AcPanel) — aberto pelo ícone na ilha
    property bool panelOpen: false
    property bool panelHovered: false

    // Só consulta o aparelho enquanto o painel está aberto: fechado, a ponte
    // fica bloqueada no stdin (zero consultas/CPU). Ao abrir, atualiza na hora.
    onPanelOpenChanged: send({ "watch": root.panelOpen })
    onOnlineChanged: if (root.online && root.panelOpen) send({ "watch": true })
    property bool power: false
    property string mode: ""
    property string fan: ""
    property string swing: ""
    property real target: 0
    property real indoor: 0
    property real outdoor: 0
    property bool eco: false
    property bool turbo: false
    property bool display: true
    property bool sound: false
    property bool sleep: false
    property bool freeze: false
    property bool ieco: false
    property bool purifier: false
    property bool flash: false
    property bool breezeAway: false
    property bool selfClean: false
    property real energyToday: 0
    property real energyTotal: 0
    property real powerW: 0
    // Capacidades do aparelho (vêm do bridge; false = opção escondida)
    property bool capIeco: false
    property bool capTurbo: false
    property bool capDisplay: false
    property bool capPurifier: false
    property bool capFlash: false
    property bool capBreeze: false
    property bool capSelfClean: false
    property var modes: []
    property var fans: []
    property var swings: []

    function send(msg) {
        if (rpc.running)
            rpc.write(JSON.stringify(msg) + "\n");
    }

    // Temperatura em rajada: o visual atualiza a cada clique, mas o comando só
    // é enviado quando o usuário para de clicar (debounce).
    property real _pendingTarget: 0
    property bool _targetPending: false

    Timer {
        id: targetDebounce

        interval: 500
        onTriggered: {
            root._targetPending = false;
            root.send({ "set": { "target": root._pendingTarget } });
        }
    }

    function refresh(): void { send({ "refresh": true }); }
    function setPower(v): void { root.power = v; send({ "set": { "power": v } }); }
    function setMode(m): void { root.mode = m; send({ "set": { "mode": m } }); }
    function setTarget(t): void {
        const v = Math.max(16, Math.min(30, Math.round(t)));
        root.target = v; // otimista: o painel atualiza na hora
        root._pendingTarget = v;
        root._targetPending = true;
        targetDebounce.restart();
    }
    function setFan(f): void { root.fan = f; send({ "set": { "fan": f } }); }
    function setSwing(s): void { root.swing = s; send({ "set": { "swing": s } }); }
    function setEco(v): void { root.eco = v; send({ "set": { "eco": v } }); }
    function setTurbo(v): void { root.turbo = v; send({ "set": { "turbo": v } }); }
    function setDisplay(v): void { root.display = v; send({ "set": { "display": v } }); }
    function setSleep(v): void { root.sleep = v; send({ "set": { "sleep": v } }); }
    function setSound(v): void { root.sound = v; send({ "set": { "sound": v } }); }
    function setFreeze(v): void { root.freeze = v; send({ "set": { "freeze": v } }); }
    function setIeco(v): void { root.ieco = v; send({ "set": { "ieco": v } }); }
    function setPurifier(v): void { root.purifier = v; send({ "set": { "purifier": v } }); }
    function setFlash(v): void { root.flash = v; send({ "set": { "flash": v } }); }
    function setBreezeAway(v): void { root.breezeAway = v; send({ "set": { "breezeAway": v } }); }
    function startSelfClean(): void { send({ "action": "self_clean" }); }

    // Só inicia o bridge se o token já foi extraído
    Process {
        id: check

        command: ["test", "-f", root.configFile]
        running: true

        onExited: (code) => {
            if (code === 0) {
                root.configured = true;
                rpc.running = true;
            } else {
                console.warn("[skye] midea: falta " + root.configFile + " (extraia o token primeiro)");
            }
        }
    }

    Process {
        id: rpc

        command: [root.pythonBin, Quickshell.shellDir + "/midea_rpc.py"]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: (line) => {
                let s;
                try {
                    s = JSON.parse(line);
                } catch (e) {
                    console.warn("[skye] midea: resposta inválida:", line);
                    return;
                }
                if (s.error !== undefined)
                    console.warn("[skye] midea:", s.error);
                if (s.online !== undefined)
                    root.online = s.online;
                if (!s.online)
                    return;
                if (s.power !== undefined)
                    root.power = s.power;
                if (s.mode !== undefined)
                    root.mode = s.mode;
                if (s.fan !== undefined)
                    root.fan = s.fan;
                if (s.swing !== undefined)
                    root.swing = s.swing;
                if (s.target !== null && s.target !== undefined && !root._targetPending)
                    root.target = s.target;
                if (s.indoor !== null && s.indoor !== undefined)
                    root.indoor = s.indoor;
                if (s.outdoor !== null && s.outdoor !== undefined)
                    root.outdoor = s.outdoor;
                if (s.eco !== undefined)
                    root.eco = s.eco;
                if (s.turbo !== undefined)
                    root.turbo = s.turbo;
                if (s.display !== undefined)
                    root.display = s.display;
                if (s.sound !== undefined)
                    root.sound = s.sound;
                if (s.sleep !== undefined)
                    root.sleep = s.sleep;
                if (s.freeze !== undefined)
                    root.freeze = s.freeze;
                if (s.ieco !== undefined)
                    root.ieco = s.ieco;
                if (s.purifier !== undefined)
                    root.purifier = s.purifier;
                if (s.flash !== undefined)
                    root.flash = s.flash;
                if (s.breezeAway !== undefined)
                    root.breezeAway = s.breezeAway;
                if (s.selfClean !== undefined)
                    root.selfClean = s.selfClean;
                if (s.energyToday !== null && s.energyToday !== undefined)
                    root.energyToday = s.energyToday;
                if (s.energyTotal !== null && s.energyTotal !== undefined)
                    root.energyTotal = s.energyTotal;
                if (s.powerW !== null && s.powerW !== undefined)
                    root.powerW = s.powerW;
                if (s.caps !== undefined) {
                    root.capIeco = s.caps.ieco === true;
                    root.capTurbo = s.caps.turbo === true;
                    root.capDisplay = s.caps.display === true;
                    root.capPurifier = s.caps.purifier === true;
                    root.capFlash = s.caps.flash === true;
                    root.capBreeze = s.caps.breezeAway === true;
                    root.capSelfClean = s.caps.selfClean === true;
                }
                if (s.modes !== undefined)
                    root.modes = s.modes;
                if (s.fans !== undefined)
                    root.fans = s.fans;
                if (s.swings !== undefined)
                    root.swings = s.swings;
            }
        }

        stderr: SplitParser {
            onRead: (line) => console.warn("[skye] midea:", line)
        }

        onExited: (code) => {
            root.online = false;
            restart.restart();
        }
    }

    Timer {
        id: restart

        interval: 10000
        onTriggered: if (root.configured && !rpc.running) rpc.running = true
    }

    IpcHandler {
        target: "midea"

        function status(): string {
            return JSON.stringify({
                configured: root.configured, online: root.online,
                power: root.power, mode: root.mode, target: root.target,
                indoor: root.indoor, outdoor: root.outdoor, fan: root.fan,
                swing: root.swing, eco: root.eco, turbo: root.turbo,
                display: root.display, ieco: root.ieco, purifier: root.purifier,
                flash: root.flash, breezeAway: root.breezeAway,
                selfClean: root.selfClean, sleep: root.sleep,
                energyToday: root.energyToday, energyTotal: root.energyTotal,
                powerW: root.powerW,
                caps: {
                    ieco: root.capIeco, turbo: root.capTurbo,
                    display: root.capDisplay, purifier: root.capPurifier,
                    flash: root.capFlash, breezeAway: root.capBreeze,
                    selfClean: root.capSelfClean
                }
            });
        }
        function refresh(): void { root.refresh(); }
        function power(on: bool): void { root.setPower(on); }
        function mode(m: string): void { root.setMode(m); }
        function temp(t: string): void { root.setTarget(parseFloat(t)); }
        function fan(f: string): void { root.setFan(f); }
        function swing(s: string): void { root.setSwing(s); }
        function eco(v: bool): void { root.setEco(v); }
        function turbo(v: bool): void { root.setTurbo(v); }
        function display(v: bool): void { root.setDisplay(v); }
        function ieco(v: bool): void { root.setIeco(v); }
        function purifier(v: bool): void { root.setPurifier(v); }
        function flash(v: bool): void { root.setFlash(v); }
        function breeze(v: bool): void { root.setBreezeAway(v); }
        function selfclean(): void { root.startSelfClean(); }
        function sleep(v: bool): void { root.setSleep(v); }
    }
}
