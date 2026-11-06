#!/usr/bin/env python3
"""Ponte JSON-lines entre o Skye (Midea.qml) e o ar-condicionado Midea local.

- Lê ~/.config/skye/midea.json (ip, port, id, token, key, extraídos uma vez).
- Autentica localmente (protocolo V3) e mantém a conexão TCP com o aparelho.
- stdin: comandos JSON, um por linha:
    {"set": {"power": true, "mode": "COOL", "target": 24.5, "fan": "AUTO",
             "swing": "OFF", "eco": false, "turbo": false, "display": true,
             "sound": false, "sleep": false, "freeze": false}}
    {"refresh": true}
- stdout: status JSON, uma linha por mudança:
    {"online": true, "power": true, "mode": "COOL", "target": 24.0, ...}
- Consulta o aparelho a cada 20s APENAS enquanto o painel está aberto
  (comando {"watch": true/false}) e após cada comando; só emite quando muda.
  Com o painel fechado a ponte fica bloqueada no stdin: zero consultas, 0% CPU.
"""

import asyncio
import json
import os
import sys

from msmart.device import AirConditioner as AC
from msmart.discover import Discover

CONFIG = os.path.expanduser("~/.config/skye/midea.json")
REFRESH_SECS = 20   # painel aberto: atualização frequente
HEARTBEAT_SECS = 60 # painel fechado: 1 consulta/min (detecta queda e re-conecta)
RETRY_SECS = 30     # tentativas de reconexão quando o ar está fora


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def _enum_name(value):
    """Nome do enum; valores crus (ex.: fan custom int) viram string."""
    return value.name if hasattr(value, "name") else str(value)


def _fan_name(value):
    try:
        return AC.FanSpeed(value).name
    except (ValueError, TypeError):
        return str(value)


def _energy(getter):
    """Consumo em kWh (ou W): BCD é o formato válido; BINARY como fallback."""
    for fmt in (AC.EnergyDataFormat.BCD, AC.EnergyDataFormat.BINARY):
        try:
            value = getter(fmt)
        except Exception:
            value = None
        if value is not None:
            return round(float(value), 2)
    return None


class Bridge:
    def __init__(self, cfg):
        self.cfg = cfg
        self.dev = None
        self.last = None
        self.watch = False

    async def _open(self, ip):
        dev = AC(ip=ip, port=self.cfg["port"], device_id=self.cfg["id"])
        await dev.authenticate(self.cfg["token"], self.cfg["key"])
        await dev.get_capabilities()
        dev.enable_energy_usage_requests = True
        await dev.refresh()
        return dev

    def _save_cfg(self):
        with open(CONFIG, "w") as f:
            json.dump(self.cfg, f, indent=2)

    async def _rediscover(self):
        """Procura o aparelho pelo device ID (o IP pode mudar após reinício do
        modem/DHCP) e atualiza o IP salvo em midea.json."""
        devices = await Discover.discover(discovery_packets=3, auto_connect=False)
        for dev in devices:
            if dev.id == self.cfg["id"]:
                if dev.ip != self.cfg["ip"]:
                    log("novo IP:", dev.ip, "(era", self.cfg["ip"], ")")
                    self.cfg["ip"] = dev.ip
                    try:
                        self._save_cfg()
                    except Exception as e:
                        log("não consegui salvar o novo IP:", e)
                return await self._open(dev.ip)
        raise RuntimeError("aparelho não encontrado na rede (Wi-Fi/DHCP)")

    async def connect(self):
        try:
            dev = await self._open(self.cfg["ip"])
        except Exception as e:
            log("IP salvo falhou (", e, "); redescobrindo pelo device ID...")
            dev = await self._rediscover()
        self.dev = dev
        log("conectado:", self.cfg.get("name", ""), "@", self.cfg["ip"])

    def status(self):
        d = self.dev
        return {
            "online": True,
            "power": bool(d.power_state),
            "mode": _enum_name(d.operational_mode),
            "fan": _fan_name(d.fan_speed),
            "swing": _enum_name(d.swing_mode),
            "target": d.target_temperature,
            "indoor": d.indoor_temperature,
            "outdoor": d.outdoor_temperature,
            "eco": bool(d.eco),
            "turbo": bool(d.turbo),
            "display": bool(d.display_on),
            "sound": bool(d.sound),
            "sleep": bool(getattr(d, "sleep", False)),
            "freeze": bool(getattr(d, "freeze_protection", False)),
            "ieco": bool(getattr(d, "ieco", False)),
            "purifier": bool(getattr(d, "purifier", False)),
            "flash": bool(getattr(d, "flash", False)),
            "breezeAway": bool(getattr(d, "breeze_away", False)),
            "selfClean": bool(getattr(d, "self_clean_active", False)),
            "energyToday": _energy(d.get_current_energy_usage),
            "energyTotal": _energy(d.get_total_energy_usage),
            "powerW": _energy(d.get_real_time_power_usage),
            "caps": {
                "ieco": bool(getattr(d, "supports_ieco", False)),
                "turbo": bool(getattr(d, "supports_turbo", False)),
                "display": bool(getattr(d, "supports_display_control", False)),
                "purifier": bool(getattr(d, "supports_purifier", False)),
                "flash": bool(getattr(d, "supports_flash", False)),
                "breezeAway": bool(getattr(d, "supports_breeze_away", False)),
                "selfClean": bool(getattr(d, "supports_self_clean", False)),
            },
            "modes": [_enum_name(m) for m in d.supported_operation_modes],
            "fans": [_enum_name(f) for f in d.supported_fan_speeds],
            "swings": [_enum_name(s) for s in d.supported_swing_modes],
        }

    def emit(self, force=False):
        if self.dev is None:
            return
        st = self.status()
        key = json.dumps(st, sort_keys=True, default=str)
        if force or key != self.last:
            self.last = key
            print(json.dumps(st), flush=True)

    async def apply(self, patch):
        d = self.dev

        # Display: a lib só tem comando de alternância, que já bipa embutido.
        # Quando é só ele, atalho (1 bipe só).
        if set(patch.keys()) == {"display"}:
            if bool(patch["display"]) != bool(d.display_on):
                await d.toggle_display()
            await d.refresh()
            self.emit(force=True)
            return
        if "display" in patch and bool(patch["display"]) != bool(d.display_on):
            await d.toggle_display()

        if "power" in patch:
            d.power_state = bool(patch["power"])
        if "mode" in patch:
            d.operational_mode = AC.OperationalMode[patch["mode"]]
        if "fan" in patch:
            d.fan_speed = AC.FanSpeed[patch["fan"]]
        if "swing" in patch:
            d.swing_mode = AC.SwingMode[patch["swing"]]
        if "target" in patch:
            d.target_temperature = float(patch["target"])
        for key in ("eco", "turbo", "sleep", "purifier"):
            if key in patch:
                setattr(d, key, bool(patch[key]))
        if "sound" in patch:
            d.sound = bool(patch["sound"])
        if "ieco" in patch:
            d.ieco = bool(patch["ieco"])
        if "flash" in patch:
            d.flash = bool(patch["flash"])
        if "breezeAway" in patch:
            d.breeze_away = bool(patch["breezeAway"])
        if "freeze" in patch:
            d.freeze_protection = bool(patch["freeze"])

        # Propriedades auxiliares (ieco/flash/breeze) saem num comando extra
        # que também carrega o buzzer — biparia uma segunda vez. Separa:
        # manda o estado com bipe e as auxiliares depois, em silêncio.
        pending = set(d._updated_properties)
        d._updated_properties.clear()

        # Bipe a cada comando (como no controle): o SetStateCommand só bipa
        # quando beep_on = True; a lib manda o valor da config "sound", que
        # estava desligada — por isso as mudanças pelo Skye eram silenciosas.
        # Campo interno direto: o setter público também agendaria um comando
        # de propriedade SOUND que este aparelho não suporta (warning inútil).
        d._sound = True
        await d.apply()

        if pending:
            props = {k: d._PROPERTY_MAP[k](d) for k in pending & d._PROPERTY_MAP.keys()}
            d._sound = False
            await d._apply_properties(props)
            d._sound = True

        await d.refresh()
        self.emit(force=True)


async def stdin_lines(queue):
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    while True:
        line = await reader.readline()
        if not line:
            return
        queue.put_nowait(line)


async def main():
    if not os.path.exists(CONFIG):
        log("sem", CONFIG, "- extraia o token primeiro")
        return 1

    cfg = json.load(open(CONFIG))
    bridge = Bridge(cfg)
    queue = asyncio.Queue()
    reader_task = asyncio.create_task(stdin_lines(queue))

    while True:
        if bridge.dev is None:
            try:
                await bridge.connect()
                bridge.emit(force=True)
            except Exception as e:
                log("falha ao conectar:", e)
                print(json.dumps({"online": False}), flush=True)
                await asyncio.sleep(RETRY_SECS)
                continue

        try:
            timeout = REFRESH_SECS if bridge.watch else HEARTBEAT_SECS
            line = await asyncio.wait_for(queue.get(), timeout=timeout)
        except asyncio.TimeoutError:
            try:
                await bridge.dev.refresh()
                bridge.emit()
            except Exception as e:
                log("refresh falhou:", e)
                bridge.dev = None
                print(json.dumps({"online": False}), flush=True)
            continue

        text = line.decode(errors="replace").strip()
        if not text:
            continue
        try:
            msg = json.loads(text)
            if "watch" in msg:
                bridge.watch = bool(msg["watch"])
                if bridge.watch:
                    try:
                        await bridge.dev.refresh()
                        bridge.emit(force=True)
                    except Exception as e:
                        # conexão ociosa foi fechada pelo aparelho: reconecta
                        log("reconectando:", e)
                        bridge.dev = None
                        print(json.dumps({"online": False}), flush=True)
            elif "action" in msg:
                if msg["action"] == "self_clean":
                    await bridge.dev.start_self_clean()
                await bridge.dev.refresh()
                bridge.emit(force=True)
            elif "set" in msg:
                await bridge.apply(msg["set"])
            else:
                await bridge.dev.refresh()
                bridge.emit()
        except Exception as e:
            log("erro no comando:", e)
            # conexão pode ter caído (aparelho fecha ociosas): reconecta
            bridge.dev = None
            print(json.dumps({"online": True, "error": str(e)}), flush=True)

    # nunca chega aqui (loop infinito); leitor termina sozinho no EOF
    await reader_task


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
