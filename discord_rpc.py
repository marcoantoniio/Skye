#!/usr/bin/env python3
# Rich Presence do Discord para o Skye. Lê uma linha JSON por atualização no
# stdin (faixa atual em segundos, ou null para limpar) e envia SET_ACTIVITY pelo
# socket IPC do Discord. Só biblioteca padrão. Uso: discord_rpc.py <client_id>

import json
import os
import queue
import socket
import struct
import sys
import threading
import urllib.request
import uuid

RETRY_SECONDS = 5
LISTENING = 2
# Texto do status na lista de membros: 0 = nome do app, 1 = artista (state),
# 2 = título (details). O perfil mostra details e state de qualquer forma.
STATUS_DISPLAY = 1


def text(value):
    if not value or len(value) < 2:
        return None
    return value[:128]


_artist_cache = {}


def full_artist(state):
    # O app do Deezer coloca só o artista principal no MPRIS; a API pública
    # do Deezer devolve todos os contribuintes. Se a consulta falhar, mantém
    # o artista que veio do MPRIS.
    url = state["url"]
    if url in _artist_cache:
        return _artist_cache[url]
    artist = state["artist"]
    track_id = url.split("?")[0].rstrip("/").rsplit("/", 1)[-1]
    if track_id.isdigit():
        try:
            with urllib.request.urlopen(f"https://api.deezer.com/track/{track_id}", timeout=5) as resp:
                data = json.load(resp)
            names = [c["name"] for c in data.get("contributors") or [] if isinstance(c, dict) and c.get("name")]
            if names:
                artist = ", ".join(names)
        except (OSError, ValueError):
            pass
    _artist_cache[url] = artist
    return artist


def activity_for(state):
    if state is None:
        return None
    timestamps = {"start": state["start"]}
    if state["end"]:
        timestamps["end"] = state["end"]
    assets = {}
    if state["artUrl"].startswith("https://"):
        assets["large_image"] = state["artUrl"]
    if text(state["album"]):
        assets["large_text"] = text(state["album"])
    buttons = []
    if state["url"].startswith("https://"):
        buttons.append({"label": "Ouvir no Deezer", "url": state["url"]})
    activity = {
        "type": LISTENING,
        "status_display_type": STATUS_DISPLAY,
        "details": text(state["title"]),
        "state": text(full_artist(state)),
        "timestamps": timestamps,
        "assets": assets or None,
        "buttons": buttons or None,
    }
    return {key: value for key, value in activity.items() if value is not None}


class Discord:
    def __init__(self, client_id):
        self.client_id = client_id
        self.sock = None

    def sync(self, state):
        if self.sock is None:
            self.connect()
        self.set_activity(activity_for(state))

    def connect(self):
        runtime = os.environ["XDG_RUNTIME_DIR"]
        for n in range(10):
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5)
            try:
                sock.connect(os.path.join(runtime, f"discord-ipc-{n}"))
            except OSError:
                sock.close()
                continue
            self.sock = sock
            try:
                self.send(0, {"v": 1, "client_id": self.client_id})
                reply = self.recv()
                if reply.get("evt") == "ERROR":
                    raise ConnectionError(reply["data"]["message"])
            except (OSError, ConnectionError):
                self.close()
                raise
            return
        raise ConnectionError("Discord não está aberto")

    def set_activity(self, activity):
        self.send(1, {
            "cmd": "SET_ACTIVITY",
            "args": {"pid": os.getpid(), "activity": activity},
            "nonce": str(uuid.uuid4()),
        })
        reply = self.recv()
        if reply.get("evt") == "ERROR":
            print("discord:", reply["data"]["message"], file=sys.stderr, flush=True)

    def send(self, op, payload):
        data = json.dumps(payload).encode()
        self.sock.sendall(struct.pack("<II", op, len(data)) + data)

    def recv(self):
        while True:
            op, length = struct.unpack("<II", self.read(8))
            payload = self.read(length)
            if op == 2:
                raise ConnectionError("Discord fechou a conexão")
            if op == 3:
                self.sock.sendall(struct.pack("<II", 4, length) + payload)
                continue
            return json.loads(payload)

    def read(self, size):
        data = b""
        while len(data) < size:
            chunk = self.sock.recv(size - len(data))
            if not chunk:
                raise ConnectionError("Discord fechou a conexão")
            data += chunk
        return data

    def close(self):
        if self.sock is not None:
            self.sock.close()
            self.sock = None


def read_stdin(updates):
    for line in sys.stdin:
        try:
            updates.put(("state", json.loads(line)))
        except json.JSONDecodeError as error:
            print("discord: linha inválida ignorada:", error, file=sys.stderr, flush=True)
    updates.put(("eof", None))


def main():
    client_id = sys.argv[1]
    if not client_id.isdigit():
        sys.exit("discord: client_id inválido; defina-o em DiscordPresence.qml")

    updates = queue.Queue()
    threading.Thread(target=read_stdin, args=(updates,), daemon=True).start()

    discord = Discord(client_id)
    state, sent, failing = None, object(), False
    while True:
        try:
            kind, value = updates.get(timeout=RETRY_SECONDS)
        except queue.Empty:
            kind = "tick"
        if kind == "eof":
            break
        if kind == "state":
            state = value
        if state != sent:
            try:
                discord.sync(state)
                sent, failing = state, False
            except (OSError, ConnectionError) as error:
                discord.close()
                if state is None:
                    sent = state
                elif not failing:
                    print(f"discord: {error}; tentando de novo", file=sys.stderr, flush=True)
                    failing = True

    if discord.sock is not None:
        try:
            discord.set_activity(None)
        except OSError:
            pass
    discord.close()


if __name__ == "__main__":
    main()
