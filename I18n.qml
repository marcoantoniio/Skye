pragma Singleton

// Idioma da interface: "pt" (padrão) ou "en". Persiste entre reinícios.
// IPC: qs -c skye ipc call language set en | toggle | get
//
// Uso: text: I18n.tr("key")            — textos simples
//      text: I18n.tr("key", [arg])     — "{0}" é substituído pelo arg
//      date.toLocaleString(I18n.dateLocale, "ddd d MMM")  — datas
// O dicionário pt mantém os textos atuais do app; o en traduz tudo.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string language: "pt"

    readonly property var dateLocale: Qt.locale(language === "en" ? "en_GB" : "pt_BR")

    onLanguageChanged: Quickshell.execDetached(["sh", "-c",
        "printf '%s' '" + language + "' > '" + Quickshell.stateDir + "/language.txt'"])

    Process {
        id: loadProc

        command: ["cat", Quickshell.stateDir + "/language.txt"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v === "pt" || v === "en")
                    root.language = v;
            }
        }
    }

    function tr(key, args) {
        const table = language === "en" ? en : pt;
        let s = table[key];
        if (s === undefined) {
            console.warn("[i18n] chave sem tradução:", key);
            return key;
        }
        if (args !== undefined) {
            for (let i = 0; i < args.length; ++i)
                s = s.replace("{" + i + "}", args[i]);
        }
        return s;
    }

    readonly property var pt: ({
        // quick settings
        "quickSettings": "Quick Settings",
        "network": "Rede",
        "dnd": "Não Perturbe",
        "nightLight": "Night Light",
        "caffeine": "Caffeine",
        "bluetooth": "Bluetooth",
        "recorder": "Gravador",
        "camera": "Câmera",
        "squareIsland": "Ilha quadrada",
        // sessão
        "session": "Sessão",
        "lock": "Bloquear",
        "logout": "Sair",
        "restart": "Reiniciar",
        "shutdown": "Desligar",
        // abas
        "tabControlCenter": "Control Center",
        "tabDashboard": "Dashboard",
        "tabClipboardNotes": "Clipboard & Notes",
        // níveis
        "levels": "Levels",
        "output": "Saída",
        "microphone": "Microfone",
        "brightness": "Brilho",
        "noAudioOutput": "sem saída de áudio",
        "noMicrophone": "sem microfone",
        "noDdc": "sem DDC/CI neste sistema",
        "appMixer": "Mixer de aplicativos",
        "appsPlaying": "Aplicativos tocando som",
        "noAppPlaying": "nenhum aplicativo tocando som agora",
        // clipboard e notas
        "history": "Histórico",
        "clear": "limpar",
        "clearAll": "limpar tudo",
        "noHistory": "Nenhum item no histórico",
        "historyUnavailable": "Histórico indisponível — instale o wl-clipboard",
        "notes": "Notas",
        "title": "Título",
        "untitled": "Sem título",
        // dashboard
        "system": "Sistema",
        "weather": "Clima",
        "week": "Semana ",
        "allDay": "Dia inteiro",
        "nothingScheduled": "Nada marcado",
        "goodMorning": "Bom dia",
        "goodAfternoon": "Boa tarde",
        "goodEvening": "Boa noite",
        "max": "Máx ",
        "min": "Mín",
        "feels": "Sens. ",
        "rain": "Chuva",
        "loading": "carregando…",
        "diskGames": "jogos",
        // clima (descrições)
        "wSunny": "Céu limpo",
        "wPartlyCloudy": "Parcialmente nublado",
        "wCloudy": "Nublado",
        "wFog": "Nevoeiro",
        "wThunder": "Trovoada",
        "wSnow": "Neve",
        "wFreezingRain": "Chuva congelante",
        "wRain": "Chuva",
        // música
        "lyrics": "Letras",
        "notFound": "não encontrada",
        "noPlayer": "nenhum player",
        "stPlaying": " (tocando)",
        "stPaused": " (pausado)",
        "stRunning": " (rodando)",
        "stStopped": " (parado)",
        // volume
        "muted": "Mudo",
        // notificações
        "notifications": "Notificações",
        "all": "Todas",
        "noNotifications": "Nenhuma notificação",
        "nothingIn": "Nada em",
        "systemTray": "System Tray",
        // recentes
        "recent": "Recentes",
        "nothingHere": "nada por aqui",
        "now": "agora",
        "agoMin": "há {0} min",
        "agoHour": "há {0} h",
        // timer
        "focus": "Foco",
        "break": "Pausa",
        "longBreak": "Pausa longa",
        "ready": "Pronto",
        "focusBang": "Foco!",
        "breakBang": "Pausa!",
        "longBreakBang": "Pausa longa!",
        "timeUp": "Tempo!",
        "stopwatch": "cronômetro",
        // câmera
        "noCamera": "nenhuma câmera encontrada"
    })

    readonly property var en: ({
        // quick settings
        "quickSettings": "Quick Settings",
        "network": "Network",
        "dnd": "Do Not Disturb",
        "nightLight": "Night Light",
        "caffeine": "Caffeine",
        "bluetooth": "Bluetooth",
        "recorder": "Recorder",
        "camera": "Camera",
        "squareIsland": "Square island",
        // sessão
        "session": "Session",
        "lock": "Lock",
        "logout": "Log out",
        "restart": "Restart",
        "shutdown": "Shut down",
        // abas
        "tabControlCenter": "Control Center",
        "tabDashboard": "Dashboard",
        "tabClipboardNotes": "Clipboard & Notes",
        // níveis
        "levels": "Levels",
        "output": "Output",
        "microphone": "Microphone",
        "brightness": "Brightness",
        "noAudioOutput": "no audio output",
        "noMicrophone": "no microphone",
        "noDdc": "no DDC/CI on this system",
        "appMixer": "App mixer",
        "appsPlaying": "Apps playing sound",
        "noAppPlaying": "no app playing sound right now",
        // clipboard e notas
        "history": "History",
        "clear": "clear",
        "clearAll": "clear all",
        "noHistory": "No history items",
        "historyUnavailable": "History unavailable — install wl-clipboard",
        "notes": "Notes",
        "title": "Title",
        "untitled": "Untitled",
        // dashboard
        "system": "System",
        "weather": "Weather",
        "week": "Week ",
        "allDay": "All day",
        "nothingScheduled": "Nothing scheduled",
        "goodMorning": "Good morning",
        "goodAfternoon": "Good afternoon",
        "goodEvening": "Good evening",
        "max": "Max ",
        "min": "Min",
        "feels": "Feels ",
        "rain": "Rain",
        "loading": "loading…",
        "diskGames": "games",
        // clima (descrições)
        "wSunny": "Sunny",
        "wPartlyCloudy": "Partly cloudy",
        "wCloudy": "Cloudy",
        "wFog": "Fog",
        "wThunder": "Thunderstorm",
        "wSnow": "Snow",
        "wFreezingRain": "Freezing rain",
        "wRain": "Rain",
        // música
        "lyrics": "Lyrics",
        "notFound": "not found",
        "noPlayer": "no player",
        "stPlaying": " (playing)",
        "stPaused": " (paused)",
        "stRunning": " (running)",
        "stStopped": " (stopped)",
        // volume
        "muted": "Muted",
        // notificações
        "notifications": "Notifications",
        "all": "All",
        "noNotifications": "No notifications",
        "nothingIn": "Nothing in",
        "systemTray": "System Tray",
        // recentes
        "recent": "Recent",
        "nothingHere": "nothing here",
        "now": "now",
        "agoMin": "{0} min ago",
        "agoHour": "{0} h ago",
        // timer
        "focus": "Focus",
        "break": "Break",
        "longBreak": "Long break",
        "ready": "Ready",
        "focusBang": "Focus!",
        "breakBang": "Break!",
        "longBreakBang": "Long break!",
        "timeUp": "Time's up!",
        "stopwatch": "stopwatch",
        // câmera
        "noCamera": "no camera found"
    })

    IpcHandler {
        target: "language"

        function set(l: string): void {
            if (l === "pt" || l === "en")
                root.language = l;
        }

        function get(): string { return root.language; }

        function toggle(): void {
            root.language = root.language === "pt" ? "en" : "pt";
        }
    }
}
