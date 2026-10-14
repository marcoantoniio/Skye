pragma Singleton

// Clima atual via Open-Meteo (coordenadas fixas), atualizado a cada 10 min.
// Alerta de chuva: toast quando a chance passar do limite nas proximas horas.
// IPC: qs -c skye ipc call weather refresh | status

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool available: false
    property int tempC: 0
    property int high: 0
    property int low: 0
    property int rainChance: 0
    property int descCode: 0 // codigo WMO
    readonly property string desc: descFor(descCode)
    property string icon: "\u{F0599}" // nf-md-weather-sunny
    property var hourly: []

    // Coordenadas da sua cidade (padrao: Brasilia). O mesmo par lat,lon vale
    // para a Open-Meteo: https://open-meteo.com
    readonly property string location: "-15.7939,-47.8828"
    readonly property var coords: location.split(",")
    readonly property string apiUrl: "https://api.open-meteo.com/v1/forecast"
        + "?latitude=" + coords[0].trim() + "&longitude=" + coords[1].trim()
        + "&current=temperature_2m,weather_code"
        + "&hourly=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,precipitation_probability,wind_speed_10m,wind_direction_10m"
        + "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        + "&timezone=auto&forecast_days=2"

    // Alerta de chuva: primeira hora futura (ate 8h) com chance >= 60%.
    // Um aviso por evento, com espera minima de 3h entre avisos.
    readonly property int rainAlertThreshold: 60
    readonly property int rainAlertWindow: 8
    property int rainAlertHour: -1
    property double rainAlertAt: 0

    function refresh() {
        if (!fetch.running)
            fetch.running = true;
    }

    // WMO weather codes -> icone (Material Design Icons)
    function iconFor(code) {
        if (code <= 1)
            return "\u{F0599}"; // sunny
        if (code === 2)
            return "\u{F0595}"; // partly cloudy
        if (code === 3)
            return "\u{F0590}"; // cloudy
        if (code === 45 || code === 48)
            return "\u{F0591}"; // fog
        if (code >= 95)
            return "\u{F0593}"; // lightning
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "\u{F0598}"; // snowy
        if (code === 65 || code === 82)
            return "\u{F0596}"; // pouring
        return "\u{F0597}"; // rainy
    }

    function descFor(code) {
        if (code <= 1)
            return I18n.tr("wSunny");
        if (code === 2)
            return I18n.tr("wPartlyCloudy");
        if (code === 3)
            return I18n.tr("wCloudy");
        if (code === 45 || code === 48)
            return I18n.tr("wFog");
        if (code >= 95)
            return I18n.tr("wThunder");
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return I18n.tr("wSnow");
        if (code === 56 || code === 57 || code === 66 || code === 67)
            return I18n.tr("wFreezingRain");
        return I18n.tr("wRain");
    }

    function windDirFor(deg) {
        const dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        return dirs[Math.round((((deg % 360) + 360) % 360) / 22.5) % 16];
    }

    function checkRainAlert(times, probs) {
        const now = Date.now();
        let target = -1;
        let chance = 0;
        for (let i = 0; i < times.length; ++i) {
            const t = new Date(times[i]).getTime();
            if (t <= now)
                continue;
            if (t > now + root.rainAlertWindow * 3600000)
                break;
            if (Number(probs[i]) >= root.rainAlertThreshold) {
                target = new Date(times[i]).getHours();
                chance = Number(probs[i]);
                break;
            }
        }
        if (target < 0) {
            root.rainAlertHour = -1;
            return;
        }
        if (target === root.rainAlertHour || now - root.rainAlertAt < 3 * 3600000)
            return;
        root.rainAlertHour = target;
        root.rainAlertAt = now;
        Quickshell.execDetached(["notify-send", "-a", "Clima",
            I18n.tr("rainAlertTitle"), I18n.tr("rainAlertBody", [target, chance])]);
    }

    Process {
        id: fetch

        command: ["curl", "-s", "--max-time", "12", root.apiUrl]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.tempC = Math.round(d.current.temperature_2m);
                    root.descCode = Number(d.current.weather_code);
                    root.icon = root.iconFor(root.descCode);
                    root.high = Math.round(d.daily.temperature_2m_max[0]);
                    root.low = Math.round(d.daily.temperature_2m_min[0]);
                    root.rainChance = Math.round(d.daily.precipitation_probability_max[0] || 0);

                    // proximas 2 horas (a partir da hora atual)
                    const now = new Date();
                    const hourStart = new Date(now.getFullYear(), now.getMonth(),
                                               now.getDate(), now.getHours()).getTime();
                    const list = [];
                    for (let i = 0; i < d.hourly.time.length && list.length < 2; ++i) {
                        const t = new Date(d.hourly.time[i]);
                        if (t.getTime() < hourStart)
                            continue;
                        list.push({
                            label: t.getHours() + "h",
                            temp: Math.round(d.hourly.temperature_2m[i]),
                            feels: Math.round(d.hourly.apparent_temperature[i]),
                            humidity: Math.round(d.hourly.relative_humidity_2m[i]),
                            wind: Math.round(d.hourly.wind_speed_10m[i]),
                            windDir: root.windDirFor(d.hourly.wind_direction_10m[i]),
                            rain: Math.round(d.hourly.precipitation_probability[i] || 0),
                            icon: root.iconFor(Number(d.hourly.weather_code[i]))
                        });
                    }
                    root.hourly = list;
                    root.available = true;
                    root.checkRainAlert(d.hourly.time, d.hourly.precipitation_probability);
                } catch (e) {
                    console.warn("[skye] weather: falha ao ler", e);
                }
            }
        }
    }

    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "weather"

        function refresh(): void { root.refresh(); }
        function status(): string {
            return "disponivel=" + root.available + " temp=" + root.tempC + "C"
                 + " chuva=" + root.rainChance + "%"
                 + (root.rainAlertHour >= 0 ? " alerta=~" + root.rainAlertHour + "h" : "");
        }
    }
}
