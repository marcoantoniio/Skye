#!/usr/bin/env python3
"""Ponte JSON-lines entre o Skye e o Copilot CLI via ACP (Agent Client Protocol).

- Mantém um único processo `copilot --acp` (stdio, JSON-RPC).
- Traduz os eventos do ACP para o mesmo formato do opencode_bridge.py, para a
  UI tratar os dois provedores do mesmo jeito.
- stdin: comandos JSON, um por linha.
- stdout: eventos JSON, um por linha.

O Copilot não expõe tokens/custo no ACP; esses campos ficam zerados.
"""

import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time

STOP = threading.Event()
OUT_LOCK = threading.Lock()
STATE_LOCK = threading.Lock()

TRACKED = set()
SESSIONS = {}       # chave do Skye -> estado da sessão
ACP_TO_KEY = {}     # sessionId do ACP -> chave do Skye
PENDING = {}        # id JSON-RPC -> contexto
NEXT_ID = 1
AGENT = None
AGENT_LOCK = threading.Lock()


def emit(obj):
    with OUT_LOCK:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def log(message):
    sys.stderr.write("[copilot-bridge] " + str(message) + "\n")
    sys.stderr.flush()


def session_state(key):
    return SESSIONS.get(key)


def emit_session(key, force=False):
    with STATE_LOCK:
        state = SESSIONS.get(key)
        if state is None or key not in TRACKED:
            return
        payload = {
            "kind": "session",
            "session": key,
            "provider": "copilot",
            "title": state.get("title") or "",
            "directory": state.get("directory") or "",
            "model": state.get("model") or "",
            "providerID": "copilot",
            "variant": "",
            "cost": 0,
            "tokens": {"input": 0, "output": 0, "reasoning": 0, "cacheRead": 0, "cacheWrite": 0},
            "outcome": state.get("outcome") or "",
            "updated": int(state.get("updated") or 0),
            "busy": int(state.get("started") or 0),
            "idle": int(state.get("ended") or 0),
            "running": bool(state.get("running")),
        }
        state["last_emitted"] = json.dumps(payload, sort_keys=True)
    emit(payload)


class Agent:
    def __init__(self):
        self.proc = None
        self.reader = None
        self.stderr = None
        self.ready = threading.Event()
        self.next_id = 1

    def start(self):
        with AGENT_LOCK:
            if self.proc is not None and self.proc.poll() is None:
                return True
            binary = shutil.which("copilot")
            if binary is None:
                emit({"kind": "disconnected", "provider": "copilot", "message": "copilot não encontrado no PATH"})
                return False
            try:
                self.proc = subprocess.Popen(
                    [binary, "--acp"],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, bufsize=1,
                )
            except Exception as error:
                emit({"kind": "disconnected", "provider": "copilot", "message": str(error)[:200]})
                return False
            self.ready.clear()
            threading.Thread(target=self._read_stdout, daemon=True).start()
            threading.Thread(target=self._read_stderr, daemon=True).start()
            threading.Thread(target=self._watch, daemon=True).start()
        self.request("initialize", {
            "protocolVersion": 1,
            "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}},
        }, context={"type": "initialize"})
        self.ready.wait(10)
        emit({"kind": "connected", "provider": "copilot"})
        return True

    def _watch(self):
        proc = self.proc
        if proc is None:
            return
        proc.wait()
        emit({"kind": "disconnected", "provider": "copilot", "message": "copilot saiu com código " + str(proc.returncode)})

    def _read_stderr(self):
        proc = self.proc
        if proc is None or proc.stderr is None:
            return
        for line in proc.stderr:
            line = line.rstrip()
            if line:
                log(line)

    def _read_stdout(self):
        proc = self.proc
        if proc is None or proc.stdout is None:
            return
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except Exception:
                continue
            self._dispatch(message)

    def send(self, method, params):
        proc = self.proc
        if proc is None or proc.poll() is not None:
            return None
        with AGENT_LOCK:
            self.next_id += 1
            request_id = self.next_id
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        try:
            proc.stdin.write(json.dumps(payload) + "\n")
            proc.stdin.flush()
        except Exception as error:
            log("envio: " + str(error))
            return None
        return request_id

    def request(self, method, params, context=None):
        request_id = self.send(method, params)
        if request_id is not None and context is not None:
            PENDING[request_id] = context
        return request_id

    def notify(self, method, params):
        proc = self.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params}) + "\n")
            proc.stdin.flush()
        except Exception as error:
            log("notificação: " + str(error))

    def _dispatch(self, message):
        if "id" in message and ("result" in message or "error" in message):
            context = PENDING.pop(message["id"], None)
            if context is not None:
                handle_response(context, message)
            return
        method = message.get("method") or ""
        params = message.get("params") or {}
        if method == "session/update":
            handle_update(params)
        elif method == "session/request_permission":
            options = params.get("options") or []
            option = None
            for candidate in options:
                if candidate.get("kind") in ("allow_once", "allow_always"):
                    option = candidate
                    break
            if option is None and options:
                option = options[0]
            if option is not None:
                self.send_reply(message.get("id"), {
                    "outcome": {"outcome": "selected", "optionId": option.get("optionId")}
                })
            else:
                self.send_reply(message.get("id"), {"outcome": {"outcome": "cancelled"}})

    def send_reply(self, request_id, result):
        proc = self.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": request_id, "result": result}) + "\n")
            proc.stdin.flush()
        except Exception as error:
            log("resposta: " + str(error))


def acp_session(key):
    with STATE_LOCK:
        state = SESSIONS.get(key)
        return state.get("acp") if state else None


def new_session(key, directory):
    state = session_state(key)
    if state is None:
        state = {
            "key": key,
            "directory": directory,
            "title": "",
            "model": "",
            "running": False,
            "started": 0,
            "ended": 0,
            "outcome": "",
            "acp": "",
            "pending_prompt": "",
        }
        SESSIONS[key] = state
    agent = ensure_agent()
    if agent is None:
        return None
    request_id = agent.request("session/new", {"cwd": directory, "mcpServers": []},
                               context={"type": "new_session", "key": key})
    return request_id


def ensure_agent():
    global AGENT
    with STATE_LOCK:
        agent = AGENT
    if agent is None:
        agent = Agent()
        with STATE_LOCK:
            AGENT = agent
    if agent.proc is None or agent.proc.poll() is not None:
        if not agent.start():
            return None
    return agent


def choose_model(models):
    """Escolhe um modelo incluído no plano (0x); senão o atual; senão o primeiro."""
    if not isinstance(models, dict):
        return ""
    available = models.get("availableModels") or []
    current = models.get("currentModelId") or ""
    for candidate in available:
        meta = candidate.get("_meta") or {}
        if meta.get("copilotUsage") == "0x":
            return candidate.get("modelId") or current
    if current:
        return current
    return available[0].get("modelId") if available else ""


def handle_response(context, message):
    kind = context.get("type")
    if message.get("error"):
        error = message["error"]
        text = error.get("message") or error.get("code") or "erro do Copilot"
        if kind == "new_session":
            emit({"kind": "error", "session": context.get("key"), "message": text})
        elif kind == "set_model":
            # Modelo recusado: segue com o padrão da sessão.
            send_prompt(context.get("key"), context.get("prompt") or "",
                        context.get("directory") or os.getcwd())
        elif kind == "prompt":
            key = context.get("key")
            state = session_state(key)
            if state is not None:
                with STATE_LOCK:
                    state["running"] = False
                    state["ended"] = int(time.time() * 1000)
                    state["outcome"] = "failed"
                emit({"kind": "execution", "session": key, "state": "failed"})
                emit({"kind": "error", "session": key, "message": text})
                emit_session(key, force=True)
        else:
            log("ACP: " + str(text))
        return
    result = message.get("result") or {}
    if kind == "initialize":
        agent = AGENT
        if agent is not None:
            agent.ready.set()
    elif kind == "new_session":
        key = context.get("key")
        acp = result.get("sessionId") or ""
        models = result.get("models") or {}
        available = models.get("availableModels") or []
        current = models.get("currentModelId") or ""
        chosen = choose_model(models)
        with STATE_LOCK:
            state = SESSIONS.get(key)
            if state is None:
                state = {"key": key, "directory": "", "title": "", "running": False,
                         "started": 0, "ended": 0, "outcome": "", "acp": "", "pending_prompt": ""}
                SESSIONS[key] = state
            state["acp"] = acp
            state["model"] = chosen
            state["updated"] = int(time.time() * 1000)
            ACP_TO_KEY[acp] = key
            prompt = state.get("pending_prompt") or ""
            state["pending_prompt"] = ""
            directory = state.get("directory") or ""
        emit_session(key, force=True)
        agent = AGENT
        if agent is not None and chosen and chosen != current:
            agent.request("session/set_model", {"sessionId": acp, "modelId": chosen},
                          context={"type": "set_model", "key": key, "prompt": prompt,
                                   "directory": directory})
        elif prompt:
            send_prompt(key, prompt, directory)
    elif kind == "set_model":
        key = context.get("key")
        prompt = context.get("prompt") or ""
        directory = context.get("directory") or ""
        if prompt:
            send_prompt(key, prompt, directory)
    elif kind == "prompt":
        key = context.get("key")
        stop_reason = result.get("stopReason") or "end_turn"
        state = session_state(key)
        if state is None:
            return
        outcome = "succeeded" if stop_reason in ("end_turn", "max_tokens") else "interrupted"
        with STATE_LOCK:
            state["running"] = False
            state["ended"] = int(time.time() * 1000)
            state["outcome"] = outcome
            state["updated"] = state["ended"]
        emit({"kind": "execution", "session": key, "state": outcome})
        emit_session(key, force=True)


def send_prompt(key, text, directory):
    agent = ensure_agent()
    if agent is None:
        emit({"kind": "prompt", "session": key, "ok": False, "error": "copilot indisponível"})
        return
    acp = acp_session(key)
    if not acp:
        state = session_state(key)
        if state is not None:
            with STATE_LOCK:
                state["pending_prompt"] = text
                state["directory"] = directory
        new_session(key, directory)
        return
    state = session_state(key)
    with STATE_LOCK:
        if state is not None:
            if not state.get("title"):
                state["title"] = text.strip().splitlines()[0][:60]
            state["running"] = True
            state["started"] = int(time.time() * 1000)
            state["outcome"] = ""
            state["updated"] = state["started"]
    emit({"kind": "execution", "session": key, "state": "started"})
    emit_session(key, force=True)
    agent.request("session/prompt", {
        "sessionId": acp,
        "prompt": [{"type": "text", "text": text}],
    }, context={"type": "prompt", "key": key})
    emit({"kind": "prompt", "session": key, "ok": True})


def content_text(content):
    if not isinstance(content, list):
        return ""
    parts = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            text = item.get("text")
            if isinstance(text, str) and text:
                parts.append(text)
    return "\n".join(parts)[:4000]


def handle_update(params):
    acp = params.get("sessionId") or ""
    update = params.get("update") or {}
    kind = update.get("sessionUpdate") or ""
    with STATE_LOCK:
        key = ACP_TO_KEY.get(acp)
    if not key:
        return
    if kind == "agent_message_chunk":
        content = update.get("content") or {}
        text = content.get("text") if isinstance(content, dict) else ""
        if text:
            emit({"kind": "text", "session": key, "message": "", "ordinal": 0, "delta": text})
    elif kind == "agent_thought_chunk":
        return
    elif kind == "tool_call":
        call = update.get("toolCallId") or ""
        title = update.get("title") or update.get("kind") or "tool"
        emit({"kind": "tool", "session": key, "id": call, "name": title,
              "status": "started", "summary": title})
    elif kind == "tool_call_update":
        call = update.get("toolCallId") or ""
        status = update.get("status") or ""
        title = update.get("title") or update.get("kind") or "tool"
        if status in ("completed", "failed"):
            emit({"kind": "tool", "session": key, "id": call, "name": title,
                  "status": "success" if status == "completed" else "failed",
                  "output": content_text(update.get("content"))})
        else:
            emit({"kind": "tool", "session": key, "id": call, "name": title,
                  "status": "called", "summary": title})
    elif kind == "plan":
        return


def handle_command(command):
    if not isinstance(command, dict):
        return
    cmd = command.get("cmd")
    key = command.get("session") or ""
    if cmd == "track":
        sessions = [s for s in command.get("sessions") or [] if isinstance(s, str) and s]
        with STATE_LOCK:
            TRACKED.update(sessions)
        for session in sessions:
            emit_session(session)
    elif cmd == "untrack":
        if key:
            with STATE_LOCK:
                TRACKED.discard(key)
    elif cmd == "prompt":
        text = command.get("text") or ""
        directory = command.get("directory") or os.getcwd()
        if not key or not text:
            return
        state = session_state(key)
        if state is None:
            with STATE_LOCK:
                SESSIONS[key] = {
                    "key": key, "directory": directory, "title": "", "model": "",
                    "running": False, "started": 0, "ended": 0, "outcome": "",
                    "acp": "", "pending_prompt": text,
                }
        else:
            with STATE_LOCK:
                state["directory"] = directory
                state["pending_prompt"] = text
        if acp_session(key):
            send_prompt(key, text, directory)
        else:
            new_session(key, directory)
    elif cmd == "interrupt":
        acp = acp_session(key)
        if acp:
            agent = AGENT
            if agent is not None:
                agent.notify("session/cancel", {"sessionId": acp})
        state = session_state(key)
        if state is not None:
            with STATE_LOCK:
                state["running"] = False
                state["ended"] = int(time.time() * 1000)
                state["outcome"] = "interrupted"
            emit({"kind": "execution", "session": key, "state": "interrupted"})
            emit_session(key, force=True)
    elif cmd == "refresh":
        emit_session(key, force=True)
    elif cmd == "list":
        emit({"kind": "sessions", "data": []})
    elif cmd == "stop":
        STOP.set()


def command_loop(commands):
    while not STOP.is_set():
        try:
            command = commands.get(timeout=0.5)
        except queue.Empty:
            continue
        try:
            handle_command(command)
        except Exception as error:
            log("comando: " + str(error))


def main():
    commands = queue.Queue()
    threading.Thread(target=command_loop, args=(commands,), daemon=True).start()
    emit({"kind": "ready", "provider": "copilot"})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                command = json.loads(line)
            except Exception:
                continue
            commands.put(command)
            if command.get("cmd") == "stop":
                break
    except KeyboardInterrupt:
        pass
    finally:
        STOP.set()
        agent = AGENT
        if agent is not None and agent.proc is not None:
            try:
                agent.proc.terminate()
            except Exception:
                pass
        time.sleep(0.1)


if __name__ == "__main__":
    main()
