#!/usr/bin/env python3
"""Ponte JSON-lines entre o Skye e o servidor local do OpenCode.

- Lê ~/.local/state/opencode/service.json (url/password).
- Garante o serviço com `opencode serve --service` quando preciso.
- Assina GET /api/event (SSE) e repassa só eventos das sessões rastreadas.
- stdin: comandos JSON, um por linha.
- stdout: eventos JSON, um por linha.

Nada de prompt/resposta é gravado em disco; o texto só passa pelo pipe.
"""

import base64
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

STOP = threading.Event()
OUT_LOCK = threading.Lock()
TRACKED = set()
TRACKED_LOCK = threading.Lock()
TOOL_NAMES = {}
SESSION_CACHE = {}
RUNNING = set()
RUN_START = {}
RUNNING_LOCK = threading.Lock()
SERVICE = None
SERVICE_AT = 0.0


def emit(obj):
    with OUT_LOCK:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def log(message):
    sys.stderr.write("[opencode-bridge] " + str(message) + "\n")
    sys.stderr.flush()


def state_file():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "opencode", "service.json")


def read_service():
    with open(state_file(), "r", encoding="utf-8") as handle:
        service = json.load(handle)
    if not isinstance(service, dict) or not service.get("url") or not service.get("password"):
        raise RuntimeError("service.json inválido")
    return service


def auth(service):
    token = base64.b64encode(("opencode:" + service["password"]).encode()).decode()
    return "Basic " + token


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def http(service, method, path, body=None, timeout=20):
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(service["url"] + path, data=data, method=method)
    request.add_header("Authorization", auth(service))
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            payload = json.loads(raw) if raw else {}
        except Exception:
            payload = {"message": raw.decode("utf-8", "replace")}
        message = payload.get("message") or payload.get("_tag") or str(error.code)
        raise ApiError(error.code, message)


def ensure_service(force=False):
    global SERVICE, SERVICE_AT
    now = time.time()
    if not force and SERVICE is not None and now - SERVICE_AT < 3:
        return SERVICE
    last = None
    for attempt in range(24):
        try:
            service = read_service()
            http(service, "GET", "/api/info", timeout=3)
            SERVICE = service
            SERVICE_AT = now
            return service
        except Exception as error:
            last = error
            if attempt == 0:
                binary = shutil.which("opencode")
                if binary is None:
                    raise RuntimeError("opencode não encontrado no PATH")
                try:
                    subprocess.run([binary, "serve", "--service"], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=12, check=False)
                except Exception as start_error:
                    last = start_error
            time.sleep(0.5)
    raise RuntimeError("servidor do OpenCode indisponível: " + str(last))


def is_tracked(session):
    with TRACKED_LOCK:
        return session in TRACKED


def set_tracked(sessions, add=True):
    with TRACKED_LOCK:
        if add:
            TRACKED.update(sessions)
        else:
            TRACKED.difference_update(sessions)


def token_info(value):
    if not isinstance(value, dict):
        return None
    cache = value.get("cache") or {}
    return {
        "input": int(value.get("input") or 0),
        "output": int(value.get("output") or 0),
        "reasoning": int(value.get("reasoning") or 0),
        "cacheRead": int(cache.get("read") or 0),
        "cacheWrite": int(cache.get("write") or 0),
    }


def normalize_session(info):
    if not isinstance(info, dict):
        return None
    model = info.get("model") if isinstance(info.get("model"), dict) else {}
    location = info.get("location") if isinstance(info.get("location"), dict) else {}
    times = info.get("time") if isinstance(info.get("time"), dict) else {}
    busy = int(times.get("busy") or 0)
    idle = int(times.get("idle") or 0)
    return {
        "kind": "session",
        "session": info.get("id") or "",
        "title": info.get("title") or "",
        "directory": location.get("directory") or "",
        "model": model.get("id") or "",
        "provider": model.get("providerID") or "",
        "variant": model.get("variant") or "",
        "cost": float(info.get("cost") or 0),
        "tokens": token_info(info.get("tokens")),
        "outcome": info.get("outcome") or "",
        "updated": int(times.get("updated") or 0),
        "busy": busy,
        "idle": idle,
        "running": busy > idle,
    }


def emit_session(session, force=False):
    if not is_tracked(session):
        return
    try:
        response = http(ensure_service(), "GET", "/api/session/" + session)
    except ApiError as error:
        if error.status != 404:
            log("sessão " + session + ": " + str(error))
        return
    except Exception as error:
        log("sessão " + session + ": " + str(error))
        return
    normalized = normalize_session((response or {}).get("data"))
    if normalized is None:
        return
    key = json.dumps(normalized, sort_keys=True)
    if not force and SESSION_CACHE.get(session) == key:
        return
    SESSION_CACHE[session] = key
    emit(normalized)
    # Se a execução terminou enquanto o SSE estava fora, o estado da sessão
    # conta isso uma vez; não confundir com o outcome antigo de uma sessão
    # que acabou de receber um prompt novo.
    with RUNNING_LOCK:
        start = RUN_START.get(session, 0)
        if normalized.get("outcome") and not normalized.get("running") and session in RUNNING \
                and normalized.get("idle", 0) >= start:
            RUNNING.discard(session)
            RUN_START.pop(session, None)
            log("sessão " + session + " terminou durante uma desconexão: " + normalized["outcome"])
            emit({"kind": "execution", "session": session, "state": normalized["outcome"]})


def content_text(content):
    parts = []
    for item in content or []:
        if isinstance(item, dict) and item.get("type") == "text":
            text = item.get("text")
            if isinstance(text, str) and text:
                parts.append(text)
    text = "\n".join(parts)
    return text[:4000]


def tool_summary(name, value):
    if isinstance(value, dict):
        for key in ("command", "filePath", "path", "pattern", "description", "query"):
            if key in value and isinstance(value[key], str):
                return value[key][:300]
        try:
            return json.dumps(value, ensure_ascii=False)[:300]
        except Exception:
            return ""
    return str(value)[:300] if value is not None else ""


def handle_event(payload):
    try:
        event = json.loads(payload)
    except Exception:
        return
    if not isinstance(event, dict):
        return
    kind = event.get("type") or ""
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    session = data.get("sessionID") or ""
    if not session:
        nested = data.get("session")
        if isinstance(nested, dict):
            session = nested.get("id") or ""
    if not session and isinstance(data.get("id"), str) and data["id"].startswith("ses"):
        session = data["id"]

    if kind == "server.connected":
        emit({"kind": "connected"})
        return
    if not session or not is_tracked(session):
        return

    if kind == "session.execution.started":
        with RUNNING_LOCK:
            RUNNING.add(session)
            RUN_START[session] = int(data.get("started") or time.time() * 1000)
        emit({"kind": "execution", "session": session, "state": "started"})
    elif kind in ("session.execution.succeeded", "session.execution.failed", "session.execution.interrupted"):
        state = kind.rsplit(".", 1)[-1]
        with RUNNING_LOCK:
            RUNNING.discard(session)
            RUN_START.pop(session, None)
        emit({"kind": "execution", "session": session, "state": state})
        emit_session(session, force=True)
    elif kind == "session.text.started":
        emit({"kind": "text_start", "session": session,
              "message": data.get("assistantMessageID") or "", "ordinal": data.get("ordinal") or 0})
    elif kind == "session.text.delta":
        emit({"kind": "text", "session": session,
              "message": data.get("assistantMessageID") or "", "ordinal": data.get("ordinal") or 0,
              "delta": data.get("delta") or ""})
    elif kind == "session.text.ended":
        emit({"kind": "text_end", "session": session,
              "message": data.get("assistantMessageID") or "", "ordinal": data.get("ordinal") or 0,
              "text": data.get("text") or ""})
    elif kind == "session.tool.input.started":
        call = data.get("id") or ""
        name = data.get("name") or ""
        TOOL_NAMES[(session, call)] = name
        emit({"kind": "tool", "session": session, "id": call, "name": name,
              "status": "started", "summary": ""})
    elif kind == "session.tool.called":
        call = data.get("id") or ""
        name = TOOL_NAMES.get((session, call), "")
        emit({"kind": "tool", "session": session, "id": call, "name": name,
              "status": "called", "summary": tool_summary(name, data.get("input")),
              "input": data.get("input")})
    elif kind in ("session.tool.success", "session.tool.failed"):
        call = data.get("id") or ""
        name = TOOL_NAMES.pop((session, call), "")
        status = "success" if kind.endswith("success") else "failed"
        emit({"kind": "tool", "session": session, "id": call, "name": name,
              "status": status, "output": content_text(data.get("content")),
              "metadata": data.get("metadata") or {}})
    elif kind == "session.step.started":
        model = data.get("model") if isinstance(data.get("model"), dict) else {}
        emit({"kind": "model", "session": session, "model": model.get("id") or "",
              "provider": model.get("providerID") or "", "variant": model.get("variant") or ""})
    elif kind == "session.step.ended":
        emit({"kind": "step", "session": session, "cost": float(data.get("cost") or 0),
              "tokens": token_info(data.get("tokens"))})
    elif kind == "session.usage.updated":
        emit({"kind": "usage", "session": session, "cost": float(data.get("cost") or 0),
              "tokens": token_info(data.get("tokens"))})
    elif kind in ("session.created", "session.renamed", "session.moved", "session.model.selected",
                  "session.archived", "session.unarchived", "session.status", "session.idle"):
        emit_session(session, force=True)
    elif kind == "session.step.failed":
        emit({"kind": "error", "session": session,
              "message": data.get("error") or data.get("message") or "passo falhou"})
    elif kind == "session.retry.scheduled":
        error = data.get("error") if isinstance(data.get("error"), dict) else {}
        emit({"kind": "retry", "session": session,
              "attempt": int(data.get("attempt") or 0),
              "at": float(data.get("at") or 0),
              "message": error.get("message") or ""})
    elif kind == "permission.asked":
        emit({"kind": "permission", "session": session,
              "id": data.get("id") or "", "title": data.get("title") or "",
              "message": data.get("message") or ""})


def sse_loop():
    while not STOP.is_set():
        try:
            service = ensure_service()
            request = urllib.request.Request(service["url"] + "/api/event", method="GET")
            request.add_header("Authorization", auth(service))
            request.add_header("Accept", "text/event-stream")
            with urllib.request.urlopen(request, timeout=120) as response:
                data = []
                for raw in response:
                    if STOP.is_set():
                        return
                    line = raw.decode("utf-8", "replace").rstrip("\r\n")
                    if line == "":
                        if data:
                            handle_event("\n".join(data))
                            data = []
                    elif line.startswith(":"):
                        continue
                    elif line.startswith("data:"):
                        data.append(line[5:].lstrip())
        except Exception as error:
            if STOP.is_set():
                return
            emit({"kind": "disconnected", "message": str(error)[:200]})
            time.sleep(1)


SESSION_PERMISSIONS = [
    # Mesmo comportamento do antigo `opencode run --auto`: o agente pode
    # ler/editar arquivos e rodar comandos sem pedir aprovação a cada passo.
    {"action": "*", "resource": "*", "effect": "allow"},
    # O Skye é headless: sem o app desktop o browser do Code Mode nunca
    # conecta. Negar remove as ferramentas de browser do catálogo do modelo.
    {"action": "browser", "resource": "*", "effect": "deny"},
    {"action": "skill", "resource": "browser", "effect": "deny"},
]


def browser_denied(permissions):
    for rule in permissions or []:
        if isinstance(rule, dict) and rule.get("action") == "browser" \
                and rule.get("effect") == "deny":
            return True
    return False


def ensure_session(session, directory, title="", model=None):
    service = ensure_service()
    try:
        response = http(service, "GET", "/api/session/" + session, timeout=8)
        data = (response or {}).get("data") or {}
        if not browser_denied(data.get("permissions")):
            try:
                http(service, "PATCH", "/api/session/" + session,
                     {"permissions": SESSION_PERMISSIONS}, timeout=10)
            except Exception as error:
                log("permissões " + session + ": " + str(error))
        return service
    except ApiError as error:
        if error.status != 404:
            raise
    body = {
        "id": session,
        "location": {"directory": directory or os.getcwd()},
        "permissions": SESSION_PERMISSIONS,
    }
    if title:
        body["title"] = title
    if model:
        body["model"] = model
    try:
        http(service, "POST", "/api/session", body, timeout=15)
    except ApiError as error:
        if error.status != 409:
            raise
    return service


def model_ref(text):
    text = (text or "").strip()
    if "/" not in text:
        return None
    provider, rest = text.split("/", 1)
    variant = None
    if "#" in rest:
        rest, variant = rest.split("#", 1)
    provider = provider.strip()
    rest = rest.strip()
    if not provider or not rest:
        return None
    value = {"id": rest, "providerID": provider}
    if variant:
        value["variant"] = variant
    return value


def default_model():
    try:
        response = http(ensure_service(), "GET", "/api/model/default", timeout=10)
        data = response.get("data") if isinstance(response, dict) else None
        if isinstance(data, dict) and data.get("id") and data.get("providerID"):
            return {"id": data["id"], "providerID": data["providerID"]}
    except Exception as error:
        log("modelo padrão: " + str(error))
    return None


def command_prompt(command):
    session = command.get("session") or ""
    text = command.get("text") or ""
    request_id = command.get("requestId") or ""
    directory = command.get("directory") or os.getcwd()
    model = model_ref(command.get("model") or "")
    if model is None and command.get("resetModel"):
        model = default_model()
    try:
        service = ensure_session(session, directory, model=model)
        if model:
            try:
                http(service, "POST", "/api/session/" + session + "/model", {"model": model}, timeout=10)
            except ApiError as error:
                log("modelo " + session + ": " + str(error))
        http(service, "POST", "/api/session/" + session + "/prompt", {"text": text}, timeout=20)
        emit({"kind": "prompt", "requestId": request_id, "session": session, "ok": True})
        emit_session(session, force=True)
    except Exception as error:
        emit({"kind": "prompt", "requestId": request_id, "session": session,
              "ok": False, "error": str(error)})


def handle_command(command):
    if not isinstance(command, dict):
        return
    cmd = command.get("cmd")
    if cmd == "track":
        sessions = [s for s in command.get("sessions") or [] if isinstance(s, str) and s]
        set_tracked(sessions, True)
        for session in sessions:
            emit_session(session)
    elif cmd == "untrack":
        session = command.get("session") or ""
        if session:
            set_tracked([session], False)
    elif cmd == "prompt":
        command_prompt(command)
    elif cmd == "create":
        session = command.get("session") or ""
        directory = command.get("directory") or os.getcwd()
        request_id = command.get("requestId") or ""
        try:
            ensure_session(session, directory, title=command.get("title") or "",
                           model=model_ref(command.get("model") or ""))
            emit({"kind": "created", "requestId": request_id, "session": session, "ok": True})
            emit_session(session, force=True)
        except Exception as error:
            emit({"kind": "created", "requestId": request_id, "session": session,
                  "ok": False, "error": str(error)})
    elif cmd == "interrupt":
        session = command.get("session") or ""
        try:
            http(ensure_service(), "POST", "/api/session/" + session + "/interrupt", timeout=10)
            emit({"kind": "interrupt", "session": session, "ok": True})
        except Exception as error:
            emit({"kind": "interrupt", "session": session, "ok": False, "error": str(error)})
    elif cmd == "setModel":
        session = command.get("session") or ""
        model = model_ref(command.get("model") or "")
        if model:
            try:
                http(ensure_service(), "POST", "/api/session/" + session + "/model", {"model": model}, timeout=10)
                emit({"kind": "model", "session": session, "ok": True})
            except Exception as error:
                emit({"kind": "model", "session": session, "ok": False, "error": str(error)})
    elif cmd == "refresh":
        emit_session(command.get("session") or "", force=True)
    elif cmd == "list":
        try:
            response = http(ensure_service(), "GET", "/api/session?limit=50", timeout=15)
            emit({"kind": "sessions", "data": (response or {}).get("data") or []})
        except Exception as error:
            emit({"kind": "sessions", "data": [], "error": str(error)})
    elif cmd == "stats":
        try:
            response = http(ensure_service(), "GET", "/api/experimental/session/stats", timeout=20)
            emit({"kind": "stats", "data": (response or {}).get("data") or {}})
        except Exception as error:
            emit({"kind": "stats", "data": {}, "error": str(error)})
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
    threading.Thread(target=sse_loop, daemon=True).start()
    threading.Thread(target=command_loop, args=(commands,), daemon=True).start()
    emit({"kind": "ready"})
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
        time.sleep(0.1)


if __name__ == "__main__":
    main()
