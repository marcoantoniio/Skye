pragma Singleton

// Serviço das abas de agentes: abas independentes por provedor. O OpenCode
// usa um bridge SSE com o servidor local; o Copilot usa um bridge ACP. Cada
// aba tem provedor, sessão, pasta e modelo próprios. Texto, ferramentas,
// tokens, custo, título e fim chegam estruturados — sem polling e sem passar
// o prompt por argv.
//
// IPC: qs -c skye ipc call opencode send "prompt" | stop | newTab | newTabAt
//      | newTabProvider | chooseFolder | closeTab | selectTab | newSession
//      | clear | status

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var tabs: []
    property int currentTab: 0
    property bool loaded: false
    property int _nextTabId: 1
    property int _nextLineId: 1
    property var _lines: ({})
    property var _streamLines: ({}) // tabId -> id da linha em streaming
    property var _streamText: ({})  // tabId -> deltas ainda não aplicados
    property var _toolLines: ({})   // "tabId|toolId" -> id da linha
    property string _pendingDir: ""
    property string _pendingTabId: ""
    property string _bridgeState: "starting"
    property string _copilotState: "off"
    property var _copilotQueue: []
    property bool _bridgeWanted: true
    property var finishNotice: null
    property bool finishVisible: false
    property var usage: null

    readonly property var current: (root.currentTab >= 0 && root.currentTab < root.tabs.length)
        ? root.tabs[root.currentTab] : null

    property var lines: []

    readonly property bool runningNow: {
        for (let i = 0; i < root.tabs.length; ++i)
            if (root.tabs[i].running)
                return true;
        return false;
    }

    // Modelo normalizado consumido pela ilha e pelos cartões. Hoje só há o
    // adaptador do OpenCode, mas o formato é o mesmo para futuros provedores.
    readonly property var sessions: root.tabs.map(tab => root.sessionView(tab))

    readonly property string stateFile: Quickshell.stateDir + "/opencode.json"

    Timer {
        id: finishTimer

        interval: 7000
        repeat: false
        onTriggered: root.finishVisible = false
    }

    // Deltas de texto chegam em rajada; aplicar no máximo a cada 60 ms evita
    // recriar o modelo do ListView a cada token.
    Timer {
        id: streamFlush

        interval: 60
        repeat: false
        onTriggered: root._flushStreams()
    }

    Timer {
        interval: 2000
        repeat: true
        running: root._bridgeWanted && !bridge.running
        onTriggered: bridge.running = true
    }

    Process {
        id: bridge

        command: ["python3", Quickshell.shellDir + "/scripts/opencode_bridge.py"]
        stdinEnabled: true
        running: true

        stdout: SplitParser {
            onRead: (line) => root._onBridge(line)
        }

        stderr: SplitParser {
            onRead: (line) => console.warn("[skye] opencode: " + line)
        }

        onExited: (code) => {
            root._bridgeState = "stopped";
            if (code !== 0)
                console.warn("[skye] opencode: bridge saiu com código " + code);
        }
    }

    Process {
        id: copilotBridge

        command: ["python3", Quickshell.shellDir + "/scripts/copilot_bridge.py"]
        stdinEnabled: true
        running: false

        stdout: SplitParser {
            onRead: (line) => root._onBridge(line)
        }

        stderr: SplitParser {
            onRead: (line) => console.warn("[skye] copilot: " + line)
        }

        onExited: (code) => {
            root._copilotState = "stopped";
            if (code !== 0)
                console.warn("[skye] copilot: bridge saiu com código " + code);
        }
    }

    Process {
        id: loadProc

        command: ["cat", root.stateFile]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    data = null;
                }

                if (data !== null && typeof data === "object" && !Array.isArray(data)
                        && Array.isArray(data.tabs)) {
                    const list = [];
                    const lines = ({});
                    for (let i = 0; i < data.tabs.length; ++i) {
                        const saved = data.tabs[i];
                        if (saved === null || typeof saved !== "object")
                            continue;
                        const tab = root._newTab(typeof saved.workingDir === "string" && saved.workingDir !== ""
                            ? saved.workingDir : Quickshell.env("HOME"),
                            saved.provider === "copilot" ? "copilot" : "opencode");
                        if (typeof saved.sessionId === "string" && saved.sessionId.startsWith("ses_"))
                            tab.sessionId = saved.sessionId;
                        if (typeof saved.model === "string")
                            tab.model = saved.model;
                        if (typeof saved.lastModel === "string")
                            tab.lastModel = saved.lastModel;
                        list.push(tab);
                        lines[tab.id] = [];
                    }
                    if (list.length === 0) {
                        const tab = root._newTab(Quickshell.env("HOME"));
                        list.push(tab);
                        lines[tab.id] = [];
                    }
                    root._lines = lines;
                    root.tabs = list;
                    const idx = parseInt(data.currentTab, 10);
                    root.currentTab = (!isNaN(idx) && idx >= 0 && idx < list.length) ? idx : 0;
                    root._syncLines();
                    root.loaded = true;
                    root.save();
                    root._trackAll();
                } else if (data !== null && typeof data === "object" && !Array.isArray(data)) {
                    // Formato antigo: uma sessão só.
                    const tab = root._newTab(typeof data.workingDir === "string" && data.workingDir !== ""
                        ? data.workingDir : Quickshell.env("HOME"));
                    if (typeof data.sessionId === "string" && data.sessionId.startsWith("ses_"))
                        tab.sessionId = data.sessionId;
                    if (typeof data.model === "string")
                        tab.model = data.model;
                    if (typeof data.lastModel === "string")
                        tab.lastModel = data.lastModel;
                    const firstLines = ({});
                    firstLines[tab.id] = [];
                    root._lines = firstLines;
                    root.tabs = [tab];
                    root.currentTab = 0;
                    root._syncLines();
                    root.loaded = true;
                    root.save();
                    root._trackAll();
                } else if (text.trim() === "") {
                    const tab = root._newTab(Quickshell.env("HOME"));
                    const firstLines = ({});
                    firstLines[tab.id] = [];
                    root._lines = firstLines;
                    root.tabs = [tab];
                    root.currentTab = 0;
                    root._syncLines();
                    root.loaded = true;
                    root.save();
                    root._trackAll();
                } else {
                    const tab = root._newTab(Quickshell.env("HOME"));
                    const firstLines = ({});
                    firstLines[tab.id] = [];
                    root._lines = firstLines;
                    root.tabs = [tab];
                    root.currentTab = 0;
                    root._syncLines();
                    root.loaded = true;
                    root._trackAll();
                    console.warn("[skye] opencode: estado ilegível em " + root.stateFile);
                }
            }
        }
    }

    Process {
        id: dirProc

        stdout: StdioCollector {
            onStreamFinished: {
                const index = root._findTab(root._pendingTabId);
                if (index < 0)
                    return;
                const dir = text.trim();
                if (dir !== "") {
                    const tab = root.tabs[index];
                    root.finishVisible = false;
                    if (tab.running)
                        root._send({ cmd: "interrupt", session: tab.sessionId });
                    root._untrackSession(tab.sessionId);
                    root._patch(index, {
                        prevDir: tab.workingDir,
                        workingDir: dir,
                        sessionId: root._newSessionId(),
                        title: "",
                        modelReset: false,
                        tokens: 0,
                        totalTokens: 0,
                        cost: 0,
                        cache: 0,
                        outcome: "",
                        running: false,
                        startedAt: 0,
                        lastDuration: 0
                    });
                    root._clearTransient(tab.id);
                    root._setLines(tab.id, []);
                    root.addLine(tab.id, "pasta: " + dir, "info");
                    root._trackSession(root.tabs[index].sessionId);
                    root.save();
                } else {
                    root.addLine(root._pendingTabId, "pasta não encontrada: " + root._pendingDir, "err");
                }
            }
        }
    }

    Process {
        id: folderProc

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out === "__NO_PICKER__") {
                    const tab = root._currentTab();
                    if (tab !== null)
                        root.addLine(tab.id, I18n.tr("ocFolderError"), "err");
                } else if (out !== "") {
                    root.newTabAt(out);
                }
            }
        }
    }

    function _newSessionId() {
        return "ses_skye-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function _newTab(dir, provider) {
        return {
            id: "tab-" + (root._nextTabId++),
            provider: provider === "copilot" ? "copilot" : "opencode",
            sessionId: root._newSessionId(),
            workingDir: dir && dir !== "" ? dir : Quickshell.env("HOME"),
            prevDir: "",
            model: "",
            lastModel: "",
            modelReset: false,
            history: [],
            running: false,
            startedAt: 0,
            title: "",
            tokens: 0,
            totalTokens: 0,
            cost: 0,
            cache: 0,
            outcome: "",
            lastDuration: 0
        };
    }

    function _currentTab() {
        return (root.currentTab >= 0 && root.currentTab < root.tabs.length)
            ? root.tabs[root.currentTab] : null;
    }

    function _findTab(id) {
        for (let i = 0; i < root.tabs.length; ++i)
            if (root.tabs[i].id === id)
                return i;
        return -1;
    }

    function _findTabBySession(session) {
        for (let i = 0; i < root.tabs.length; ++i)
            if (root.tabs[i].sessionId === session)
                return i;
        return -1;
    }

    function _patch(index, patch) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tab = root.tabs[index];
        const next = ({});
        for (let key in tab)
            next[key] = tab[key];
        for (let key in patch)
            next[key] = patch[key];
        const list = root.tabs.slice();
        list[index] = next;
        root.tabs = list;
    }

    function _syncLines() {
        const tab = root._currentTab();
        root.lines = tab ? (root._lines[tab.id] || []) : [];
    }

    function _setLines(id, list) {
        if (!(id in root._lines) && root._findTab(id) < 0)
            return;
        const map = ({});
        for (let key in root._lines)
            map[key] = root._lines[key];
        map[id] = list;
        root._lines = map;
        const tab = root._currentTab();
        if (tab !== null && tab.id === id)
            root.lines = list;
    }

    function _dropLines(id) {
        root._clearTransient(id);
        const map = ({});
        for (let key in root._lines)
            if (key !== id)
                map[key] = root._lines[key];
        root._lines = map;
    }

    function _clearTransient(tabId) {
        delete root._streamLines[tabId];
        delete root._streamText[tabId];
        const prefix = tabId + "|";
        const keys = [];
        for (let key in root._toolLines)
            if (key.startsWith(prefix))
                keys.push(key);
        for (let i = 0; i < keys.length; ++i)
            delete root._toolLines[keys[i]];
    }

    function _ensureCopilot() {
        if (copilotBridge.running)
            return true;
        copilotBridge.running = true;
        root._copilotState = "starting";
        return false;
    }

    function _flushCopilotQueue() {
        const queue = root._copilotQueue;
        if (queue.length === 0)
            return;
        root._copilotQueue = [];
        for (let i = 0; i < queue.length; ++i)
            copilotBridge.write(JSON.stringify(queue[i]) + "\n");
    }

    function _providerOf(session) {
        const index = root._findTabBySession(session);
        return index >= 0 ? root.tabs[index].provider : "opencode";
    }

    function _sendTo(provider, message) {
        if (provider === "copilot") {
            root._ensureCopilot();
            if (root._copilotState !== "ready" && root._copilotState !== "connected") {
                root._copilotQueue = root._copilotQueue.concat([message]);
                return true;
            }
            copilotBridge.write(JSON.stringify(message) + "\n");
            return true;
        }
        if (!bridge.running) {
            root._bridgeState = "stopped";
            return false;
        }
        bridge.write(JSON.stringify(message) + "\n");
        return true;
    }

    function _send(message) {
        const provider = message.session !== undefined
            ? root._providerOf(message.session)
            : (root._currentTab() !== null ? root._currentTab().provider : "opencode");
        return root._sendTo(provider, message);
    }

    function _trackSession(session) {
        if (session === "")
            return;
        const index = root._findTabBySession(session);
        const provider = index >= 0 ? root.tabs[index].provider : "opencode";
        root._sendTo(provider, { cmd: "track", sessions: [session] });
    }

    function _untrackSession(session) {
        if (session === "")
            return;
        const index = root._findTabBySession(session);
        const provider = index >= 0 ? root.tabs[index].provider : "opencode";
        root._sendTo(provider, { cmd: "untrack", session: session });
    }

    function _trackAll() {
        const byProvider = { opencode: [], copilot: [] };
        for (let i = 0; i < root.tabs.length; ++i) {
            const tab = root.tabs[i];
            if (tab.sessionId !== "")
                byProvider[tab.provider === "copilot" ? "copilot" : "opencode"].push(tab.sessionId);
        }
        for (let provider in byProvider) {
            if (byProvider[provider].length > 0)
                root._sendTo(provider, { cmd: "track", sessions: byProvider[provider] });
        }
    }

    function save() {
        if (!root.loaded)
            return;
        const tabs = root.tabs.map(tab => ({
            provider: tab.provider,
            sessionId: tab.sessionId,
            workingDir: tab.workingDir,
            model: tab.model,
            lastModel: tab.lastModel
        }));
        const json = JSON.stringify({
            currentTab: root.currentTab,
            tabs: tabs
        });
        Quickshell.execDetached(["sh", "-c",
            "printf '%s' \"$1\" > '" + root.stateFile + ".tmp' && mv '" + root.stateFile + ".tmp' '" + root.stateFile + "'",
            "sh", json]);
    }

    function _string(value) {
        if (value === null || value === undefined)
            return "";
        if (typeof value === "string")
            return value;
        try {
            return JSON.stringify(value);
        } catch (e) {
            return String(value);
        }
    }

    function addLine(tabId, text, kind) {
        const index = root._findTab(tabId);
        if (index < 0)
            return;
        const raw = root._string(text);
        const clean = raw
            .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, "")
            .replace(/\u001b\][^\u0007]*\u0007/g, "")
            .replace(/\u001b/g, "")
            .replace(/\r/g, "");
        if (raw !== "" && clean.trim() === "")
            return;
        const list = (root._lines[tabId] || []).slice(-499);
        list.push({ id: root._nextLineId++, text: clean, kind: kind });
        root._setLines(tabId, list);
    }

    function _flushStream(tabId) {
        const pending = root._streamText[tabId];
        if (pending === undefined || pending === "")
            return;
        delete root._streamText[tabId];
        const id = root._streamLines[tabId];
        if (id === undefined)
            return;
        const list = (root._lines[tabId] || []).slice();
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === id) {
                const next = ({});
                for (let key in list[i])
                    next[key] = list[i][key];
                next.text = (next.text || "") + pending;
                list[i] = next;
                break;
            }
        }
        root._setLines(tabId, list);
    }

    function _flushStreams() {
        const ids = [];
        for (let tabId in root._streamText)
            ids.push(tabId);
        for (let i = 0; i < ids.length; ++i)
            root._flushStream(ids[i]);
    }

    function _streamStart(index, message, ordinal) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tab = root.tabs[index];
        root._flushStream(tab.id);
        root._streamEnd(index, "");
        const list = (root._lines[tab.id] || []).slice(-499);
        const line = {
            id: root._nextLineId++,
            text: "",
            kind: "out",
            streaming: true,
            message: message || "",
            ordinal: ordinal || 0
        };
        list.push(line);
        root._streamLines[tab.id] = line.id;
        root._setLines(tab.id, list);
    }

    function _streamDelta(index, delta) {
        if (index < 0 || index >= root.tabs.length || !delta)
            return;
        const tab = root.tabs[index];
        if (root._streamLines[tab.id] === undefined) {
            const list = (root._lines[tab.id] || []).slice(-499);
            const line = { id: root._nextLineId++, text: "", kind: "out", streaming: true };
            list.push(line);
            root._streamLines[tab.id] = line.id;
            root._setLines(tab.id, list);
        }
        root._streamText[tab.id] = (root._streamText[tab.id] || "") + delta;
        if (!streamFlush.running)
            streamFlush.start();
    }

    function _streamEnd(index, text) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tab = root.tabs[index];
        root._flushStream(tab.id);
        const id = root._streamLines[tab.id];
        if (id === undefined)
            return;
        const list = (root._lines[tab.id] || []).slice();
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id === id) {
                const next = ({});
                for (let key in list[i])
                    next[key] = list[i][key];
                if (text !== "")
                    next.text = text;
                next.streaming = false;
                list[i] = next;
                break;
            }
        }
        delete root._streamLines[tab.id];
        root._setLines(tab.id, list);
    }

    function _clip(text, maxLines, maxChars) {
        let value = root._string(text).replace(/\r/g, "");
        const lines = value.split("\n");
        if (lines.length > maxLines)
            value = lines.slice(0, maxLines).join("\n") + "\n…";
        if (value.length > maxChars)
            value = value.slice(0, maxChars) + "…";
        return value;
    }

    function _toolUpdate(index, event) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tab = root.tabs[index];
        const key = tab.id + "|" + (event.id || "");
        const list = (root._lines[tab.id] || []).slice();
        let line = null;
        let lineIndex = -1;
        const known = root._toolLines[key];
        if (known !== undefined) {
            for (let i = 0; i < list.length; ++i) {
                if (list[i].id === known) {
                    line = list[i];
                    lineIndex = i;
                    break;
                }
            }
        }

        const name = root._string(event.name || "tool");
        const summary = root._clip(event.summary || "", 1, 120);
        let text = "$ " + name + (summary !== "" ? " · " + summary : "");
        if (event.status === "success" && event.output)
            text += "\n" + root._clip(event.output, 4, 320);
        else if (event.status === "failed")
            text += "\n" + root._clip(event.output || "falhou", 2, 200);

        if (line === null) {
            line = {
                id: root._nextLineId++,
                text: text,
                kind: "tool",
                tool: name,
                status: event.status || ""
            };
            list.push(line);
            root._toolLines[key] = line.id;
        } else {
            const next = ({});
            for (let field in line)
                next[field] = line[field];
            next.text = text;
            next.tool = name;
            next.status = event.status || "";
            list[lineIndex] = next;
        }
        if (event.status === "success" || event.status === "failed")
            delete root._toolLines[key];
        root._setLines(tab.id, list);
    }

    function _applyUsage(index, event) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tokens = event.tokens || {};
        const input = Number(tokens.input) || 0;
        const output = Number(tokens.output) || 0;
        const reasoning = Number(tokens.reasoning) || 0;
        const cacheRead = Number(tokens.cacheRead) || 0;
        const cacheWrite = Number(tokens.cacheWrite) || 0;
        const prompt = input + cacheWrite + cacheRead;
        root._patch(index, {
            tokens: output + reasoning,
            totalTokens: prompt + output + reasoning,
            cost: Number(event.cost) || 0,
            cache: prompt > 0 ? cacheRead / prompt : 0
        });
    }

    function _finishRun(index, state, endAt) {
        if (index < 0 || index >= root.tabs.length)
            return;
        const tab = root.tabs[index];
        if (!tab.running)
            return;
        const end = endAt > 0 ? endAt : Date.now();
        const duration = tab.startedAt > 0 ? Math.max(0, (end - tab.startedAt) / 1000) : 0;
        root._streamEnd(index, "");
        root._patch(index, {
            running: false,
            startedAt: 0,
            outcome: state,
            lastDuration: duration
        });
        if (AgentSettings.finishNotice && duration >= AgentSettings.finishMin) {
            const current = root.tabs[index];
            root.finishNotice = {
                tabId: current.id,
                title: root.tabTitle(current),
                duration: duration,
                tokens: current.tokens,
                cost: current.cost,
                outcome: state
            };
            root.finishVisible = true;
            finishTimer.restart();
        }
        if (tab.provider !== "copilot")
            root._sendTo("opencode", { cmd: "stats" });
    }

    function _onBridge(raw) {
        let event = null;
        try {
            event = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (event === null || typeof event !== "object")
            return;
        const kind = event.kind || "";
        if (kind === "ready" || kind === "connected") {
            if (event.provider === "copilot") {
                root._copilotState = kind === "ready" ? "ready" : "connected";
                root._flushCopilotQueue();
            } else {
                root._bridgeState = kind === "ready" ? "ready" : "connected";
                root._sendTo("opencode", { cmd: "stats" });
            }
            root._trackAll();
            return;
        }
        if (kind === "disconnected") {
            if (event.provider === "copilot")
                root._copilotState = "disconnected";
            else
                root._bridgeState = "disconnected";
            return;
        }
        if (kind === "stats") {
            root.usage = event.data || null;
            return;
        }

        const index = root._findTabBySession(event.session || "");
        if (index < 0)
            return;
        const tab = root.tabs[index];

        if (kind === "session") {
            const patch = ({});
            const modelChanged = typeof event.model === "string" && event.model !== ""
                && event.model !== tab.lastModel;
            if (typeof event.title === "string" && event.title !== "")
                patch.title = event.title;
            if (typeof event.directory === "string" && event.directory !== "")
                patch.workingDir = event.directory;
            if (typeof event.model === "string" && event.model !== "")
                patch.lastModel = event.model;
            if (typeof event.cost === "number")
                patch.cost = event.cost;
            if (event.tokens) {
                const input = Number(event.tokens.input) || 0;
                const output = Number(event.tokens.output) || 0;
                const reasoning = Number(event.tokens.reasoning) || 0;
                const cacheRead = Number(event.tokens.cacheRead) || 0;
                const cacheWrite = Number(event.tokens.cacheWrite) || 0;
                const prompt = input + cacheWrite + cacheRead;
                patch.tokens = output + reasoning;
                patch.totalTokens = prompt + output + reasoning;
                patch.cache = prompt > 0 ? cacheRead / prompt : 0;
            }
            if (typeof event.busy === "number")
                patch.busy = event.busy;
            if (typeof event.idle === "number")
                patch.idle = event.idle;
            if (event.running === true) {
                patch.running = true;
                patch.outcome = "";
                if (event.busy > 0)
                    patch.startedAt = event.busy;
            } else if (typeof event.outcome === "string" && !tab.running) {
                patch.outcome = event.outcome;
            }
            root._patch(index, patch);
            if (modelChanged)
                root.save();
            if (root.finishVisible && root.finishNotice !== null
                    && root.finishNotice.tabId === root.tabs[index].id) {
                const notice = ({});
                for (let key in root.finishNotice)
                    notice[key] = root.finishNotice[key];
                notice.title = root.tabTitle(root.tabs[index]);
                notice.tokens = root.tabs[index].tokens;
                notice.cost = root.tabs[index].cost;
                root.finishNotice = notice;
            }
            // Reconexão do bridge: a sessão já terminou depois do início desta
            // execução, mas o evento de fim pode ter passado.
            if (event.running === false && tab.running
                    && typeof event.outcome === "string" && event.outcome !== ""
                    && typeof event.idle === "number" && event.idle >= tab.startedAt)
                root._finishRun(index, event.outcome, event.idle);
        } else if (kind === "execution") {
            if (event.state === "started") {
                root._patch(index, {
                    running: true,
                    startedAt: tab.startedAt > 0 ? tab.startedAt : Date.now(),
                    outcome: ""
                });
            } else {
                root._finishRun(index, event.state);
            }
        } else if (kind === "text_start") {
            root._streamStart(index, event.message, event.ordinal);
        } else if (kind === "text") {
            root._streamDelta(index, event.delta);
        } else if (kind === "text_end") {
            root._streamEnd(index, event.text);
        } else if (kind === "tool") {
            root._toolUpdate(index, event);
        } else if (kind === "usage") {
            root._applyUsage(index, event);
        } else if (kind === "model") {
            if (typeof event.model === "string" && event.model !== "")
                root._patch(index, { lastModel: event.model });
        } else if (kind === "prompt") {
            if (!event.ok) {
                root._patch(index, { running: false, startedAt: 0 });
                root.addLine(tab.id, "falha ao enviar: " + root._clip(event.error || "erro", 3, 300), "err");
            }
        } else if (kind === "created" || kind === "interrupt") {
            if (event.ok === false)
                root.addLine(tab.id, "falha: " + root._clip(event.error || "erro", 3, 300), "err");
        } else if (kind === "error") {
            root.addLine(tab.id, root._clip(event.message || "erro", 4, 400), "err");
        } else if (kind === "info") {
            root.addLine(tab.id, root._clip(event.message || "", 4, 400), "info");
        } else if (kind === "retry") {
            const at = Number(event.at) || 0;
            const wait = at > 0 ? Math.max(0, Math.round((at - Date.now()) / 1000)) : 0;
            const reason = root._clip(event.message || "", 1, 120);
            root.addLine(tab.id, "provedor ocupado"
                + (reason !== "" ? ": " + reason : "")
                + (wait > 0 ? " · nova tentativa em " + wait + "s" : ""), "info");
        } else if (kind === "permission") {
            root.addLine(tab.id, "[permissão] " + root._clip(event.title || event.message || "", 2, 200), "info");
        }
    }

    function send(prompt) {
        const tab = root._currentTab();
        if (tab === null || tab.running)
            return;

        const index = root.currentTab;
        root._patch(index, { history: [...tab.history, prompt].slice(-50) });

        if (prompt === "/cd" || prompt === "cd") {
            root.changeDir(Quickshell.env("HOME"));
            return;
        }
        if (prompt === "/cd -" || prompt === "cd -") {
            if (tab.prevDir !== "")
                root.changeDir(tab.prevDir);
            else
                root.addLine(tab.id, "sem pasta anterior", "info");
            return;
        }
        if (prompt.startsWith("/cd ") || prompt.startsWith("cd ")) {
            root.changeDir(prompt.replace(/^\/?cd\s+/, ""));
            return;
        }
        if (prompt.startsWith("/model")) {
            const name = prompt.slice(6).trim();
            root._patch(index, { model: name, modelReset: name === "" });
            root.save();
            root.addLine(tab.id, name === "" ? "modelo: padrão do opencode" : "modelo: " + name, "info");
            return;
        }
        if (prompt === "/new") {
            root.newSession();
            return;
        }

        root.addLine(tab.id, "❯ " + prompt, "cmd");
        root.finishVisible = false;
        root._patch(index, {
            running: true,
            startedAt: Date.now(),
            outcome: "",
            lastDuration: 0,
            modelReset: false
        });
        root._trackSession(tab.sessionId);
        const sent = root._send({
            cmd: "prompt",
            requestId: tab.id + "-" + Date.now(),
            session: tab.sessionId,
            directory: tab.workingDir,
            text: prompt,
            model: tab.model,
            resetModel: tab.modelReset === true
        });
        if (!sent) {
            root._patch(index, { running: false, startedAt: 0 });
            root.addLine(tab.id, "bridge do " + root.providerName(tab) + " não está rodando", "err");
        }
    }

    function stop() {
        const tab = root._currentTab();
        if (tab === null || !tab.running)
            return;
        root.addLine(tab.id, "(parado)", "info");
        if (!root._send({ cmd: "interrupt", session: tab.sessionId }))
            root._patch(root.currentTab, { running: false, startedAt: 0 });
    }

    function newTab(provider) {
        const current = root._currentTab();
        const dir = current ? current.workingDir : Quickshell.env("HOME");
        const next = provider === "copilot" || provider === "opencode"
            ? provider : (current ? current.provider : "opencode");
        const tab = root._newTab(dir, next);
        if (current !== null && current.provider === next) {
            tab.model = current.model;
            tab.lastModel = current.lastModel;
        }
        root.tabs = root.tabs.concat([tab]);
        root.currentTab = root.tabs.length - 1;
        root._setLines(tab.id, []);
        root.addLine(tab.id, "nova sessão: " + tab.sessionId, "info");
        root._trackSession(tab.sessionId);
        root.save();
    }

    function newTabAt(dir, provider) {
        root.newTab(provider);
        root.changeDir(dir);
    }

    function chooseFolder() {
        if (folderProc.running)
            return;
        folderProc.command = ["sh", "-c",
            "if command -v zenity >/dev/null 2>&1; then "
            + "exec zenity --file-selection --directory --title=\"$1\"; "
            + "elif command -v kdialog >/dev/null 2>&1; then "
            + "exec kdialog --getexistingdirectory \"$HOME\" --title \"$1\"; "
            + "else printf '%s' '__NO_PICKER__'; fi",
            "sh", I18n.tr("ocChooseFolder")];
        folderProc.running = true;
    }

    function _syncCopilot() {
        let has = false;
        for (let i = 0; i < root.tabs.length; ++i)
            if (root.tabs[i].provider === "copilot")
                has = true;
        if (!has && copilotBridge.running) {
            copilotBridge.running = false;
            root._copilotState = "off";
            root._copilotQueue = [];
        }
    }

    function closeTab(index) {
        if (index < 0 || index >= root.tabs.length)
            return;

        const tab = root.tabs[index];
        if (root.finishNotice !== null && root.finishNotice.tabId === tab.id)
            root.finishVisible = false;
        if (tab.running)
            root._send({ cmd: "interrupt", session: tab.sessionId });
        root._untrackSession(tab.sessionId);

        if (root.tabs.length === 1) {
            const fresh = root._newTab(tab.workingDir, tab.provider);
            root._dropLines(tab.id);
            root.tabs = [fresh];
            root.currentTab = 0;
            root._setLines(fresh.id, []);
            root._syncLines();
            root._trackSession(fresh.sessionId);
            root.save();
            root._syncCopilot();
            return;
        }

        const list = root.tabs.slice();
        list.splice(index, 1);
        root._dropLines(tab.id);
        root.tabs = list;

        if (index < root.currentTab)
            root.currentTab -= 1;
        else if (root.currentTab >= list.length)
            root.currentTab = list.length - 1;
        root._syncLines();
        root.save();
        root._syncCopilot();
    }

    function selectTab(index) {
        if (index < 0 || index >= root.tabs.length)
            return;
        root.currentTab = index;
    }

    function focusTabById(tabId) {
        for (let i = 0; i < root.tabs.length; ++i) {
            if (root.tabs[i].id === tabId) {
                root.selectTab(i);
                return;
            }
        }
    }

    function focusRunningTab() {
        let best = -1;
        for (let i = 0; i < root.tabs.length; ++i) {
            const tab = root.tabs[i];
            if (!tab.running)
                continue;
            if (best < 0 || tab.startedAt < root.tabs[best].startedAt)
                best = i;
        }
        if (best >= 0)
            root.selectTab(best);
    }

    function newSession() {
        const tab = root._currentTab();
        if (tab === null)
            return;
        root.finishVisible = false;
        if (tab.running)
            root._send({ cmd: "interrupt", session: tab.sessionId });
        root._untrackSession(tab.sessionId);
        const index = root.currentTab;
        root._patch(index, {
            sessionId: root._newSessionId(),
            title: "",
            modelReset: false,
            tokens: 0,
            totalTokens: 0,
            cost: 0,
            cache: 0,
            outcome: "",
            running: false,
            startedAt: 0,
            lastDuration: 0
        });
        root._clearTransient(tab.id);
        root._setLines(tab.id, []);
        root.addLine(tab.id, "nova sessão: " + root.tabs[index].sessionId, "info");
        root._trackSession(root.tabs[index].sessionId);
        root.save();
    }

    function clearLines() {
        const tab = root._currentTab();
        if (tab === null)
            return;
        root._clearTransient(tab.id);
        root._setLines(tab.id, []);
    }

    function changeDir(raw) {
        const tab = root._currentTab();
        if (tab === null)
            return;
        let dir = raw.trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
        if (dir === "")
            return;
        if (!dir.startsWith("/"))
            dir = tab.workingDir.replace(/\/+$/, "") + "/" + dir;
        root._pendingDir = dir;
        root._pendingTabId = tab.id;
        dirProc.command = ["sh", "-c", "cd \"$1\" 2>/dev/null && pwd -P", "sh", dir];
        dirProc.running = true;
    }

    function sessionView(tab) {
        return {
            id: tab.id,
            provider: tab.provider,
            providerName: root.providerName(tab),
            session: tab.sessionId,
            title: root.tabTitle(tab),
            project: root.projectName(tab),
            model: root.modelFor(tab),
            directory: tab.workingDir,
            state: tab.running ? "working" : (tab.outcome !== "" ? tab.outcome : "idle"),
            startedAt: tab.startedAt,
            tokens: tab.tokens || 0,
            totalTokens: tab.totalTokens || 0,
            cost: tab.cost || 0,
            cache: tab.cache || 0,
            outcome: tab.outcome || "",
            duration: tab.lastDuration || 0
        };
    }

    function tabTitle(tab) {
        if (tab === null)
            return "";
        return tab.title !== "" ? tab.title : root.projectName(tab);
    }

    function projectName(tab) {
        if (tab === null)
            return "";
        const clean = tab.workingDir.replace(/\/+$/, "");
        const base = clean.split("/").pop();
        return base !== "" ? base : root.providerName(tab);
    }

    function providerName(tab) {
        return tab !== null && tab.provider === "copilot" ? "Copilot" : "OpenCode";
    }

    function modelFor(tab) {
        if (tab === null)
            return "";
        if (tab.model !== "")
            return tab.model;
        return tab.lastModel !== "" ? tab.lastModel : "";
    }

    function tokensOf(tab) {
        return tab !== null ? (tab.tokens || 0) : 0;
    }

    function costOf(tab) {
        return tab !== null ? (tab.cost || 0) : 0;
    }

    function cacheOf(tab) {
        return tab !== null ? (tab.cache || 0) : 0;
    }

    function formatTokens(value) {
        return Format.tokens(value);
    }

    function formatCost(value) {
        return Format.cost(value);
    }

    function clock(seconds) {
        return Format.clock(seconds);
    }

    onCurrentTabChanged: {
        root._syncLines();
        if (root.loaded)
            save();
    }

    IpcHandler {
        target: "opencode"

        function send(prompt: string): void { root.send(prompt); }
        function stop(): void { root.stop(); }
        function newTab(): void { root.newTab(); }
        function newTabProvider(provider: string): void { root.newTab(provider); }
        function newTabAt(path: string): void { root.newTabAt(path); }
        function newTabAtProvider(path: string, provider: string): void { root.newTabAt(path, provider); }
        function chooseFolder(): void { root.chooseFolder(); }
        function closeTab(n: int): void { root.closeTab(n); }
        function selectTab(n: int): void { root.selectTab(n); }
        function newSession(): void { root.newSession(); }
        function clear(): void { root.clearLines(); }
        function status(): string {
            const tab = root._currentTab();
            const last = root.lines.length > 0 ? root.lines[root.lines.length - 1].text : "";
            return "abas=" + root.tabs.length + " aba=" + (root.currentTab + 1)
                 + " provedor=" + (tab ? tab.provider : "")
                 + " rodando=" + (tab ? tab.running : false)
                 + " sessao=" + (tab ? tab.sessionId : "")
                 + " titulo=" + JSON.stringify(tab ? root.tabTitle(tab) : "")
                 + " pasta=" + (tab ? tab.workingDir : "")
                 + " modelo=" + (tab && root.modelFor(tab) !== "" ? root.modelFor(tab) : "(padrao)")
                 + " tokens=" + (tab ? root.tokensOf(tab) : 0)
                 + " custo=" + root.formatCost(tab ? root.costOf(tab) : 0)
                 + " estado=" + (tab ? tab.outcome : "")
                 + " duracao=" + (tab ? tab.lastDuration : 0)
                 + " aviso=" + root.finishVisible
                 + " bridge=" + root._bridgeState
                 + " copilot=" + root._copilotState
                 + " linhas=" + root.lines.length
                 + " ultima=" + JSON.stringify(last.slice(0, 120));
        }
    }
}
