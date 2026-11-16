pragma Singleton

// Camada fina de provedores de agente. Hoje só o OpenCode está conectado,
// mas a UI (ilha, abas, cartões) consome sessões normalizadas daqui — então
// adicionar outro provedor é registrar um adaptador com o mesmo formato.

import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property var providers: [
        {
            id: "opencode",
            name: "OpenCode",
            tint: Theme.accent
        },
        {
            id: "copilot",
            name: "Copilot",
            tint: Theme.accentPurple
        }
    ]

    function provider(id) {
        for (let i = 0; i < root.providers.length; ++i)
            if (root.providers[i].id === id)
                return root.providers[i];
        return null;
    }

    // Sessões normalizadas do(s) adaptador(es) conectado(s).
    readonly property var sessions: OpenCode.sessions
    readonly property var runningSessions: {
        const out = [];
        for (let i = 0; i < root.sessions.length; ++i)
            if (root.sessions[i].state === "working")
                out.push(root.sessions[i]);
        return out;
    }
    readonly property var oldestRunning: {
        let best = null;
        for (let i = 0; i < root.runningSessions.length; ++i) {
            const session = root.runningSessions[i];
            if (best === null || session.startedAt < best.startedAt)
                best = session;
        }
        return best;
    }

    readonly property string readout: AgentSettings.readout
    readonly property var usage: OpenCode.usage

    function _dateKey(offset) {
        const d = new Date();
        d.setDate(d.getDate() - (offset || 0));
        const two = (n) => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
    }

    function usageSteps(count) {
        if (root.usage === null || !Array.isArray(root.usage.activity))
            return 0;
        const from = root._dateKey(count - 1);
        const to = root._dateKey(0);
        const activity = root.usage.activity;
        let total = 0;
        for (let i = 0; i < activity.length; ++i) {
            const date = activity[i].date || "";
            if (date >= from && date <= to)
                total += Number(activity[i].steps) || 0;
        }
        return total;
    }

    function usageToday() {
        return root.usageSteps(1);
    }

    function usageWeek() {
        return root.usageSteps(7);
    }

    function usageTokens() {
        if (root.usage === null)
            return 0;
        const tokens = root.usage.tokens || {};
        return (Number(tokens.input) || 0) + (Number(tokens.output) || 0)
             + (Number(tokens.reasoning) || 0) + (Number((tokens.cache || {}).read) || 0);
    }

    function cycleReadout() {
        AgentSettings.cycleReadout();
    }

    function readoutLabel() {
        return AgentSettings.readoutLabel();
    }

    function readoutValue(session, now) {
        if (session === null)
            return "";
        if (root.readout === "tokens")
            return OpenCode.formatTokens(session.tokens);
        if (root.readout === "cost")
            return OpenCode.formatCost(session.cost);
        return OpenCode.clock((now - session.startedAt) / 1000);
    }
}
