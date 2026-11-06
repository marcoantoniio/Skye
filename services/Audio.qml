pragma Singleton

// Áudio (PipeWire): saída/entrada padrão, OSD de volume da ilha e streams de
// aplicativos (para o mixer do painel de música).
//
// O OSD aparece na ilha quando o volume/mute muda (teclas de mídia, apps),
// exceto enquanto o Control Center está aberto (lá já tem o slider).
//
// IPC:
//   qs -c skye ipc call audio getVolume|setVolume|getMuted|toggleMute

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool available: sink !== null

    // ---------- OSD ----------
    property bool osdVisible: false
    property real osdVolume: 0
    property bool osdMuted: false
    property bool _ready: false

    // Evita mostrar o OSD no carregamento inicial (volume chega do PipeWire)
    Timer {
        interval: 3000
        running: true
        onTriggered: root._ready = true
    }

    Timer {
        id: osdTimer
        interval: 1600
        onTriggered: root.osdVisible = false
    }

    function showOsd(): void {
        root.osdVolume = root.volume;
        root.osdMuted = root.muted;
        root.osdVisible = true;
        osdTimer.restart();
    }

    function toggleMute(): void {
        if (root.sink && root.sink.audio)
            root.sink.audio.muted = !root.sink.audio.muted;
    }

    function setVolume(v): void {
        if (root.sink && root.sink.audio)
            root.sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null

        function onVolumeChanged() {
            if (root._ready && !ControlCenter.open)
                root.showOsd();
        }

        function onMutedChanged() {
            if (root._ready && !ControlCenter.open)
                root.showOsd();
        }
    }

    // ---------- mixer: streams de aplicativos ----------
    readonly property var streams: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (n.isStream && n.audio !== null)
                out.push(n);
        }
        return out;
    }

    PwObjectTracker {
        objects: root.streams
    }

    // streams de reprodução (apps tocando som) — mixer de aplicativos
    readonly property var playbackStreams: {
        const out = [];
        for (let i = 0; i < root.streams.length; ++i) {
            const n = root.streams[i];
            const props = n.properties || ({});
            if (props["media.class"] === "Stream/Output/Audio")
                out.push(n);
        }
        return out;
    }

    function streamName(node) {
        if (!node)
            return "";
        const props = node.properties || ({});
        // Electron (ex.: Deezer) se identifica como "Chromium": usa o nome do player
        if (props["application.process.binary"] === "electron" && Music.active && Music.player.identity !== "")
            return Music.player.identity;
        return props["application.name"] || node.description || node.nickname || node.name;
    }

    function streamIcon(node) {
        if (!node)
            return "";
        const props = node.properties || ({});
        const icon = props["application.icon-name"];
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    IpcHandler {
        target: "audio"

        function getVolume(): real { return root.volume; }
        function setVolume(v: real): void { root.setVolume(v); }
        function getMuted(): bool { return root.muted; }
        function toggleMute(): void { root.toggleMute(); }
    }
}
