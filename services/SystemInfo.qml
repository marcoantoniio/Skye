pragma Singleton

// Métricas do sistema para o card "Sistema" do Dashboard. Um único processo
// de shell em intervalos de 1,5 s enquanto o painel está visível; o painel só
// consome valores normalizados daqui.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool active: false
    property string cpuText: "—"
    property real cpuProgress: -1
    property string memText: "—"
    property real memProgress: -1
    property string gpuText: "—"
    property string gpuLabel: "GPU"
    property real gpuProgress: -1
    property string tempText: "—"
    property var disks: []
    property string uptimeText: "—"

    property real prevCpuTotal: -1
    property real prevCpuIdle: -1

    readonly property string command: "echo \"cpu $(head -1 /proc/stat)\"; "
        + "echo \"mem $(free -b | sed -n 2p)\"; "
        // GPU: NVIDIA via nvidia-smi; AMD (amdgpu) via sysfs; Intel via
        // intel_gpu_top (intel-gpu-tools), se instalado
        + "g=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1); "
        + "if [ -z \"$g\" ]; then for d in /sys/class/drm/card*/device; do "
        + "if [ -r \"$d/gpu_busy_percent\" ]; then "
        + "u=$(cat \"$d/gpu_busy_percent\" 2>/dev/null); "
        + "vu=$(cat \"$d/mem_info_vram_used\" 2>/dev/null); "
        + "vt=$(cat \"$d/mem_info_vram_total\" 2>/dev/null); "
        + "g=\"$u, $(( ${vu:-0} / 1048576 )), $(( ${vt:-0} / 1048576 ))\"; break; fi; done; fi; "
        + "if [ -z \"$g\" ] && command -v intel_gpu_top >/dev/null 2>&1; then "
        + "u=$(timeout 1.2 intel_gpu_top -J -s 400 2>/dev/null | tail -1 | grep -oE '\"Render/3D[^\"]*\": \\{\"busy\": [0-9.]+' | head -1 | grep -oE '[0-9.]+$'); "
        + "if [ -n \"$u\" ]; then g=\"$u, 0, 0\"; fi; fi; "
        + "echo \"gpu $g\"; "
        + "echo \"temp $(sensors 2>/dev/null | grep -m1 -E 'Package id 0|Tctl|Tdie')\"; "
        + "echo \"disks $(df -B1 -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs -x fuse.portal --output=source,target,size,used 2>/dev/null | tail -n +2 | awk '!seen[$1]++ { print $2, $3, $4 }' | sort -k2 -n -r | head -3 | paste -sd'|' -)\"; "
        + "echo \"uptime $(cat /proc/uptime)\""

    Process {
        id: collector

        command: ["sh", "-c", root.command]

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    onActiveChanged: if (root.active) root.refresh()

    function refresh() {
        if (!collector.running)
            collector.running = true;
    }

    function parse(out) {
        const lines = out.split("\n").filter(l => l.trim().length > 0);
        const data = ({});

        for (let i = 0; i < lines.length; ++i) {
            const sp = lines[i].indexOf(" ");
            if (sp > 0)
                data[lines[i].slice(0, sp)] = lines[i].slice(sp + 1);
        }

        // CPU (delta entre amostras de /proc/stat)
        if (data.cpu !== undefined) {
            const f = data.cpu.trim().split(/\s+/).slice(1).map(Number);
            const total = f.reduce((a, b) => a + b, 0);
            const idle = (f[3] || 0) + (f[4] || 0);
            if (root.prevCpuTotal > 0 && total > root.prevCpuTotal) {
                const dt = total - root.prevCpuTotal;
                const di = idle - root.prevCpuIdle;
                const busy = Math.max(0, Math.min(1, 1 - di / dt));
                root.cpuText = Math.round(busy * 100) + "%";
                root.cpuProgress = busy;
            }
            root.prevCpuTotal = total;
            root.prevCpuIdle = idle;
        }

        // Memória
        if (data.mem !== undefined) {
            const f = data.mem.trim().split(/\s+/);
            const total = Number(f[1]);
            const used = Number(f[2]);
            if (total > 0) {
                root.memText = Math.round(used / total * 100) + "%";
                root.memProgress = used / total;
            }
        }

        // GPU (NVIDIA via nvidia-smi, AMD/amdgpu via sysfs ou Intel via
        // intel_gpu_top: utilização, VRAM usada, VRAM total em MiB)
        if (data.gpu !== undefined && /^\d/.test(data.gpu.trim())) {
            const f = data.gpu.split(",").map(s => Number(s.trim()));
            if (f.length >= 3 && isFinite(f[0])) {
                root.gpuText = Math.round(f[0]) + "%";
                root.gpuProgress = f[0] / 100;
                root.gpuLabel = (f[1] > 0 && f[2] > 0)
                    ? "GPU · " + (f[1] / 1024).toFixed(1) + "/" + (f[2] / 1024).toFixed(0) + " GB"
                    : "GPU";
            }
        }

        // Temperatura da CPU
        if (data.temp !== undefined) {
            const m = data.temp.match(/\+([0-9.]+)°C/);
            if (m)
                root.tempText = Math.round(Number(m[1])) + "°C";
        }

        // Discos (3 maiores filesystems reais)
        if (data.disks !== undefined) {
            const entries = data.disks.split("|").filter(s => s.trim().length > 0);
            const list = [];
            for (let i = 0; i < entries.length; ++i) {
                const f = entries[i].trim().split(/\s+/);
                if (f.length >= 3) {
                    const size = Number(f[1]);
                    const used = Number(f[2]);
                    if (size > 0)
                        list.push({ label: f[0], percent: Math.round(used / size * 100) + "%", progress: used / size });
                }
            }
            root.disks = list;
        }

        // Uptime
        if (data.uptime !== undefined) {
            const secs = Number(data.uptime.trim().split(/\s+/)[0]);
            if (isFinite(secs)) {
                const d = Math.floor(secs / 86400);
                const h = Math.floor((secs % 86400) / 3600);
                const m = Math.floor((secs % 3600) / 60);
                root.uptimeText = (d > 0 ? d + "d " : "") + h + "h " + m + "min";
            }
        }
    }
}
