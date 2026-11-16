#!/usr/bin/env python3
"""Ponte entre o Skye e o gpu-screen-recorder.

O Quickshell 0.3.2 crasha (segfault no QLocalSocket) quando o socket IPC do
gravador fecha. Esta ponte mantém o socket no Python, onde o fechamento é
tratado como exceção normal, e fala JSON-lines com o QML.

stdin:  {"cmd":"start","screen":"DP-1","file":"/...","socket":"/run/..."}
        {"cmd":"stop"} | {"cmd":"pause","paused":true|false} | {"cmd":"status"}
stdout: {"kind":"ready"} | {"kind":"started","file":...} | {"kind":"connected"}
        {"kind":"paused","paused":...} | {"kind":"stopped","code":...,"file":...}
        {"kind":"error","message":...}
"""

import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

STOP = threading.Event()
OUT_LOCK = threading.Lock()
IPC_LOCK = threading.Lock()

PROC = None
IPC = None
IPC_CONNECTED = False
PAUSED = False
SOCKET_PATH = ""
FILE = ""
RUN_ID = 0
NEXT_ID = 1


def emit(obj):
    with OUT_LOCK:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def log(message):
    sys.stderr.write("[recorder-bridge] " + str(message) + "\n")
    sys.stderr.flush()


def send_ipc(name, data=None):
    global IPC, IPC_CONNECTED
    with IPC_LOCK:
        if not IPC_CONNECTED or IPC is None:
            return False
        global NEXT_ID
        message = {"id": NEXT_ID, "name": name}
        NEXT_ID += 1
        if data is not None:
            message["data"] = data
        try:
            IPC.sendall((json.dumps(message) + "\n").encode("utf-8"))
            return True
        except Exception:
            IPC_CONNECTED = False
            IPC = None
            return False


def read_ipc(sock):
    global IPC, IPC_CONNECTED
    buffer = b""
    try:
        while not STOP.is_set():
            data = sock.recv(4096)
            if not data:
                break
            buffer += data
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    reply = json.loads(line.decode("utf-8", "replace"))
                except Exception:
                    continue
                result = reply.get("result")
                if result and result != "ok":
                    emit({"kind": "info", "message": str(result)})
    except Exception:
        pass
    finally:
        with IPC_LOCK:
            if IPC is sock:
                IPC = None
                IPC_CONNECTED = False
        try:
            sock.close()
        except Exception:
            pass


def connect_ipc(path, run_id):
    global IPC, IPC_CONNECTED
    for _ in range(40):
        if STOP.is_set() or RUN_ID != run_id:
            return
        proc = PROC
        if proc is None or proc.poll() is not None:
            return
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect(path)
        except Exception:
            sock.close()
            time.sleep(0.25)
            continue
        with IPC_LOCK:
            IPC = sock
            IPC_CONNECTED = True
        emit({"kind": "connected"})
        read_ipc(sock)
        return


def watch_process(proc, run_id):
    for line in proc.stdout:
        line = line.rstrip()
        lower = line.lower()
        if line and ("error" in lower or "failed" in lower or "fatal" in lower):
            log(line)
    code = proc.wait()
    if run_id == RUN_ID:
        emit({"kind": "stopped", "code": code, "file": FILE})


def stop_sequence(proc, run_id):
    global PAUSED
    # Um gravador pausado pode ignorar o comando de stop; retoma antes.
    if PAUSED:
        if not send_ipc("set-paused", False):
            try:
                proc.send_signal(signal.SIGCONT)
            except Exception:
                pass
        PAUSED = False
        emit({"kind": "paused", "paused": False})
    if not send_ipc("stop"):
        try:
            proc.send_signal(signal.SIGINT)
        except Exception:
            pass
    deadline = time.time() + 5
    while proc.poll() is None and time.time() < deadline and run_id == RUN_ID:
        time.sleep(0.1)
    if proc.poll() is None:
        try:
            proc.send_signal(signal.SIGTERM)
        except Exception:
            pass
        deadline = time.time() + 3
        while proc.poll() is None and time.time() < deadline:
            time.sleep(0.1)
    if proc.poll() is None:
        try:
            proc.kill()
        except Exception:
            pass


def child_setup():
    # Se a ponte morrer (inclusive SIGKILL), o gravador recebe SIGTERM.
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
    except Exception:
        pass


def start(command):
    global PROC, PAUSED, SOCKET_PATH, FILE, RUN_ID
    if PROC is not None and PROC.poll() is None:
        return
    screen = command.get("screen") or ""
    FILE = command.get("file") or ""
    SOCKET_PATH = command.get("socket") or ""
    if not screen or not FILE:
        emit({"kind": "error", "message": "tela ou arquivo ausente"})
        return
    args = [
        "gpu-screen-recorder",
        "-w", screen,
        "-c", "mp4",
        "-k", "h264",
        "-f", "60",
        "-a", "default_output|default_input",
        "-ac", "aac",
        "-ipc", SOCKET_PATH,
        "-o", FILE,
    ]
    try:
        PROC = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, preexec_fn=child_setup,
        )
    except Exception as error:
        emit({"kind": "error", "message": str(error)[:200]})
        return
    RUN_ID += 1
    run_id = RUN_ID
    PAUSED = False
    emit({"kind": "started", "file": FILE})
    threading.Thread(target=watch_process, args=(PROC, run_id), daemon=True).start()
    threading.Thread(target=connect_ipc, args=(SOCKET_PATH, run_id), daemon=True).start()


def set_paused(paused):
    global PAUSED
    proc = PROC
    if proc is None or proc.poll() is not None:
        return
    if not send_ipc("set-paused", bool(paused)):
        try:
            proc.send_signal(signal.SIGSTOP if paused else signal.SIGCONT)
        except Exception:
            pass
    PAUSED = bool(paused)
    emit({"kind": "paused", "paused": PAUSED})


def handle_command(command):
    if not isinstance(command, dict):
        return
    cmd = command.get("cmd")
    if cmd == "start":
        start(command)
    elif cmd == "stop":
        proc = PROC
        if proc is not None and proc.poll() is None:
            threading.Thread(target=stop_sequence, args=(proc, RUN_ID), daemon=True).start()
    elif cmd == "pause":
        set_paused(bool(command.get("paused")))
    elif cmd == "status":
        proc = PROC
        emit({
            "kind": "status",
            "recording": proc is not None and proc.poll() is None,
            "paused": PAUSED,
            "connected": IPC_CONNECTED,
            "file": FILE,
        })
    elif cmd == "quit":
        STOP.set()


def shutdown(signum, frame):
    STOP.set()
    proc = PROC
    if proc is not None and proc.poll() is None:
        try:
            proc.send_signal(signal.SIGCONT)
            proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=2)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    os._exit(0)


def main():
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
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
            handle_command(command)
            if command.get("cmd") == "quit":
                break
    except KeyboardInterrupt:
        pass
    finally:
        STOP.set()
        proc = PROC
        if proc is not None and proc.poll() is None:
            try:
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        time.sleep(0.1)


if __name__ == "__main__":
    main()
