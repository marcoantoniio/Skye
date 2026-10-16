pragma Singleton

// Rich Presence do Discord com a faixa do Deezer. Título, artista, álbum, capa
// e link vêm do MPRIS (Music.qml e player.metadata). O discord_rpc.py mantém a
// conexão com o Discord. Só mandamos atualização quando a faixa ou o play/pause
// mudam. Timestamps em segundos. Na linha de cima, o crédito "Made by Cormano"
// acompanha o nome, com um coração roxo no meio; o ícone do app (coração
// branco) é configurado no Portal do Discord. Sobre a capa vai um selo animado
// (equalizador em webp animado de 120 quadros, assets/deezer-eq.webp), sem
// texto no hover.
// Setup: crie um app no Discord Developer Portal e salve o Application ID em
// ~/.config/skye/discord_client_id.txt (veja o README).

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Application ID do Discord, lido de ~/.config/skye/discord_client_id.txt
    property string clientId: ""
    readonly property string idFile: Quickshell.env("HOME") + "/.config/skye/discord_client_id.txt"
    property var lastKey: null

    Process {
        id: loadProc

        command: ["cat", root.idFile]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (/^\d+$/.test(v)) {
                    root.clientId = v;
                    rpc.command = ["python3", Quickshell.shellDir + "/discord_rpc.py", v];
                    rpc.running = true;
                } else {
                    console.warn("[skye] discord: sem Application ID em " + root.idFile + "; Rich Presence desligado");
                }
            }
        }
    }

    readonly property bool deezerPlaying: Music.playing && Music.player.identity.toLowerCase().indexOf("deezer") >= 0

    readonly property string trackUrl: Music.player && Music.player.metadata
        ? String(Music.player.metadata["xesam:url"] || "") : ""

    function refresh() {
        const key = root.deezerPlaying ? [Music.title, Music.artist, Music.album, Music.artUrl, root.trackUrl].join("\n") : "";
        if (key === root.lastKey)
            return;
        root.lastKey = key;

        let state = null;
        if (root.deezerPlaying) {
            const start = Math.floor(Date.now() / 1000 - Music.livePosition);
            state = {
                title: Music.title,
                artist: Music.artist,
                album: Music.album,
                artUrl: Music.artUrl,
                url: root.trackUrl,
                start: start,
                end: Music.length > 0 ? start + Math.floor(Music.length) : 0
            };
        }
        rpc.write(JSON.stringify(state) + "\n");
    }

    Timer {
        id: debounce

        interval: 700
        onTriggered: root.refresh()
    }

    Connections {
        target: Music

        function onTitleChanged() { debounce.restart(); }
        function onArtistChanged() { debounce.restart(); }
        function onAlbumChanged() { debounce.restart(); }
        function onArtUrlChanged() { debounce.restart(); }
        function onPlayingChanged() { debounce.restart(); }
        function onPlayerChanged() { debounce.restart(); }
    }

    Process {
        id: rpc

        // O command e o start vêm do loadProc, quando o Application ID é lido.
        command: []
        running: false
        stdinEnabled: true

        stderr: SplitParser {
            onRead: (line) => console.warn("[skye] discord:", line)
        }

        onExited: (code) => console.warn("[skye] discord: processo saiu, código", code)
    }

    IpcHandler {
        target: "discord"

        function refresh(): void { root.lastKey = null; debounce.restart(); }
        function status(): string {
            return "rodando=" + rpc.running + " pid=" + rpc.processId
                 + " deezer=" + root.deezerPlaying + " cliente=" + (root.clientId || "(nao definido)");
        }
    }

    Component.onCompleted: debounce.restart()
}
