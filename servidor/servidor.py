# -*- coding: utf-8 -*-
"""
Control PC — Servidor para Windows
==================================
Convierte tu PC en un servidor al que te conectas desde el teléfono:

  * Transmite la pantalla en vivo (JPEG por WebSocket).
  * Recibe toques, arrastres, scroll, teclado y combos (como si tu dedo fuera el ratón).
  * Muestra el estado del sistema: CPU, RAM, discos, batería, red, procesos...
  * Funciona en la red de casa (incluso SIN internet, solo Wi-Fi/hotspot) y por
    internet si instalas Tailscale o abres un puerto.

Uso rápido:  python servidor.py          (comienza a servir)
             python servidor.py --prueba (comprueba que todo funcione)

La contraseña se guarda en config.json la primera vez.
"""

import asyncio
import collections
import ctypes
import hmac
import io
import json
import platform
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import tempfile
import os
from queue import Empty, Full, Queue
from pathlib import Path

import mss
import psutil
import pyautogui
import qrcode
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageDraw, ImageFont

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0

try:
    from comtypes import CLSCTX_ALL
    from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume
    PYCAW = True
except Exception:
    PYCAW = False

BASE = Path(__file__).resolve().parent
ESTATICO = BASE / "estatico"
ARCHIVO_CONFIG = BASE / "config.json"

PUERTO_DEF = 8566
VERSION_APP = "1.0"
REPO_PUBLICO = "https://api.github.com/repos/danteburguez-dot/controlpc/releases/latest"
# nivel -> (ancho máximo, calidad JPEG)
CALIDADES = {0: (960, 45), 1: (1280, 55), 2: (1600, 68), 3: (1920, 78)}

# ------------------------------------------------------------------ config ---

def guardar_config(archivo: dict) -> None:
    ARCHIVO_CONFIG.write_text(
        json.dumps(archivo, indent=2, ensure_ascii=False), "utf-8"
    )

def cargar_config() -> dict:
    base = {
        "puerto": PUERTO_DEF,
        "contrasena": "",
        "pantalla": 1,
        "ancho_maximo": 1280,
        "fps": 24,
        "calidad_jpeg": 60,
    }
    if ARCHIVO_CONFIG.exists():
        try:
            datos = json.loads(ARCHIVO_CONFIG.read_text("utf-8"))
            for k in base:
                if k in datos:
                    base[k] = datos[k]
        except Exception:
            pass
    if not base["contrasena"]:
        alfabeto = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
        base["contrasena"] = "".join(
            secrets.choice(alfabeto) for _ in range(8)
        )
        guardar_config(base)
    return base

CFG = cargar_config()

# ----------------------------------------------------------------- sesiones ---

SESIONES: dict[str, float] = {}       # token -> fecha de caducidad (epoch)
INTENTOS: dict[str, list] = {}        # ip -> lista de intentos fallidos
ARCHIVO_SESIONES = BASE / "sesiones.json"

def _guardar_sesiones() -> None:
    try:
        ARCHIVO_SESIONES.write_text(json.dumps(SESIONES), "utf-8")
    except Exception:
        pass

def _cargar_sesiones() -> None:
    try:
        datos = json.loads(ARCHIVO_SESIONES.read_text("utf-8"))
        ahora = time.time()
        for t, caduca in datos.items():
            try:
                if float(caduca) > ahora:
                    SESIONES[t] = float(caduca)
            except Exception:
                pass
    except Exception:
        pass

_cargar_sesiones()

def token_valido(token: str) -> bool:
    if not token:
        return False
    exp = SESIONES.get(token)
    if exp is None:
        return False
    if exp < time.time():
        SESIONES.pop(token, None)
        return False
    return True

def podar_sesiones() -> None:
    ahora = time.time()
    for t in [t for t, e in SESIONES.items() if e < ahora]:
        SESIONES.pop(t, None)

# ---------------------------------------------------- actualizaciones ---

REV_CACHE = {"t": 0.0, "res": None}

def _version_tupla(v: str):
    try:
        t = tuple(int(x) for x in str(v).replace("v", "").strip().split("."))
        while len(t) > 1 and t[-1] == 0:
            t = t[:-1]
        return t
    except Exception:
        return (0,)

def _version_publicada(caducada: bool = False) -> dict:
    """Consulta el último release de GitHub (con 6 h de enlatadura)."""
    ahora = time.time()
    if not caducada and REV_CACHE["res"] is not None and ahora - REV_CACHE["t"] < 21600:
        return REV_CACHE["res"]
    res = {}
    try:
        import urllib.request
        peticion = urllib.request.Request(
            REPO_PUBLICO, headers={"User-Agent": "ControlPC-actualizador"})
        with urllib.request.urlopen(peticion, timeout=8) as r:
            datos = json.loads(r.read().decode("utf-8"))
        res = {
            "nueva": str(datos.get("tag_name", "")).lstrip("v"),
            "url": str(datos.get("html_url", "")),
        }
    except Exception as e:
        res = {"nueva": None, "url": None, "error": str(e)[:120]}
    REV_CACHE["t"] = ahora
    REV_CACHE["res"] = res
    return res

def _hay_actualizacion() -> dict:
    pub = _version_publicada()
    if not pub or not pub.get("nueva"):
        return {}
    if _version_tupla(VERSION_APP) < _version_tupla(pub["nueva"]):
        return {"nueva": pub["nueva"], "url": pub["url"]}
    return {}

aviso_box = [False]

def _avisar_actualizacion() -> None:
    aviso = _hay_actualizacion()
    if not aviso:
        return
    _agregar_aviso("info",
                   f"🏁 Nueva versión disponible: V {aviso['nueva']} (tu servidor tiene V {VERSION_APP})",
                   clave="actualizacion", enfriamiento=21600)
    print(f"[!] Hay una nueva versión: V {aviso['nueva']}. Página: {aviso['url']}")
    if aviso_box[0]:
        return
    aviso_box[0] = True
    try:
        import webbrowser
        ventana = ctypes.windll.user32.MessageBoxW(
            0,
            f"Hay una nueva versión de Control PC:\n\n"
            f"  instada: V {VERSION_APP}\n"
            f"  pública: V {aviso['nueva']}\n\n"
            f"¿Abrir la página para descargar la nueva versión?",
            "Control PC — actualización",
            0x40 | 0x4)   # MDICON + YESNO
        if ventana == 6:
            webbrowser.open(aviso["url"])
    except Exception:
        pass

# ------------------------------------------------------------------- avisos ---

AVISOS = collections.deque(maxlen=40)
AVISO_SEQ = [0]
ENFRIAMIENTO = {}
SEGURIDAD = {"detectado": False, "desde": 0.0}

def _agregar_aviso(nivel: str, texto: str, clave: str = "", enfriamiento: float = 0.0,
                   seguridad: bool = False) -> None:
    ahora = time.time()
    if clave:
        anterior = ENFRIAMIENTO.get(clave, 0.0)
        if ahora - anterior < enfriamiento:
            return
        ENFRIAMIENTO[clave] = ahora
    AVISO_SEQ[0] += 1
    AVISOS.appendleft({
        "id": AVISO_SEQ[0],
        "nivel": nivel,
        "texto": texto,
        "tiempo": ahora,
        "seguridad": seguridad,
    })

def _lista_avisos() -> list:
    ahora = time.time()
    salida = []
    for a in list(AVISOS):
        av = dict(a)
        av["hace"] = int(ahora - av["tiempo"])
        av.pop("tiempo", None)
        salida.append(av)
    return salida

# ------------------------------------------------------------------- audio ---

AUDIO = {"sr": 0, "clientes": 0, "error": ""}
AUDIO_CLIENTES = []   # [{"cola": asyncio.Queue, "loop": ...}]
AUDIO_DETENER = threading.Event()

def _estado_privilegio() -> str:
    try:
        return "administrador" if ctypes.windll.shell32.IsUserAnAdmin() else "usuario"
    except Exception:
        return "usuario"

def _empujar_audio(cliente, datos: bytes) -> None:
    try:
        cliente["cola"].put_nowait(datos)
    except asyncio.QueueFull:
        # descarta lo viejo: el que escucha siempre oye lo más reciente
        try:
            cliente["cola"].get_nowait()
            cliente["cola"].put_nowait(datos)
        except Exception:
            pass

def _envia_audio(datos: bytes) -> None:
    for cliente in list(AUDIO_CLIENTES):
        try:
            cliente["loop"].call_soon_threadsafe(_empujar_audio, cliente, datos)
        except Exception:
            pass

def _bucle_audio() -> None:
    """Captura el sonido completo del sistema (loopback) y lo reparte."""
    try:
        import numpy as np
        import soundcard as sc
    except Exception as e:
        AUDIO["error"] = f"no hay libreria de audio: {e}"
        return
    try:
        salida = sc.default_speaker()
        micro = sc.get_microphone(id=str(salida.id), include_loopback=True)
        ultimo = None
        for sr in (48000, 44100):
            try:
                with micro.recorder(samplerate=sr) as rec:
                    AUDIO["sr"] = sr
                    AUDIO["error"] = ""
                    while not AUDIO_DETENER.is_set():
                        cuadro = rec.record(numframes=960)   # 20 ms
                        mono = np.asarray(cuadro, dtype="float32").mean(axis=1)
                        datos = (np.clip(mono, -1.0, 1.0) * 32760.0).astype("<i2").tobytes()
                        _envia_audio(datos)
                return
            except Exception as e:
                ultimo = e
        AUDIO["error"] = f"no se pudo abrir el audio: {ultimo}"
    except Exception as e:
        AUDIO["error"] = f"audio: {e}"

# ------------------------------------------------------------------- volumen ---

def _interfaz_volumen():
    """Devuelve la interfaz de volumen maestra de Windows (pycaw, rutas nueva y vieja)."""
    if not PYCAW:
        return None
    try:
        altavoces = AudioUtilities.GetSpeakers()
        if hasattr(altavoces, "EndpointVolume"):      # pycaw moderno
            return altavoces.EndpointVolume
        interfaz = altavoces.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        return interfaz.QueryInterface(IAudioEndpointVolume)
    except Exception:
        return None

def _leer_volumen() -> dict:
    if PYCAW:
        try:
            vol = _interfaz_volumen()
            if vol is not None:
                return {
                    "soportado": True,
                    "nivel": int(round(vol.GetMasterVolumeLevelScalar() * 100)),
                    "mudo": bool(vol.GetMute()),
                }
        except Exception:
            pass
    return {"soportado": False, "nivel": None, "mudo": False}

SUMA_FALLBACK = [50]

def _aplicar_volumen(nivel, mudo) -> dict:
    if PYCAW:
        try:
            vol = _interfaz_volumen()
            if vol is not None:
                if nivel is not None:
                    vol.SetMasterVolumeLevelScalar(
                        max(0.0, min(1.0, float(nivel) / 100.0)), None)
                if mudo is not None:
                    vol.SetMute(1 if mudo else 0, None)
                estado = _leer_volumen()
                estado["ok"] = True
                return estado
        except Exception:
            pass
    # Parejo sin pycaw: teclas de volumen (aproximado)
    try:
        if nivel is not None:
            objetivo = max(0, min(100, int(nivel)))
            pasos = max(-25, min(25, (objetivo - SUMA_FALLBACK[0]) // 2))
            tecla = "volumeup" if pasos > 0 else "volumedown"
            for _ in range(abs(pasos)):
                pyautogui.press(tecla, _pause=False)
            SUMA_FALLBACK[0] = objetivo
        if mudo:
            pyautogui.press("volumemute", _pause=False)
            SUMA_FALLBACK[0] = 0 if mudo else SUMA_FALLBACK[0]
        return {"soportado": False, "nivel": SUMA_FALLBACK[0], "mudo": bool(mudo) if mudo is not None else False, "ok": True}
    except Exception:
        return {"soportado": False, "nivel": None, "mudo": False, "ok": False}

# --------------------------------------------------------------- seguridad UAC ---

def _leer_uac() -> dict:
    if os.name != "nt":
        return {"soportado": False, "modo": "aviso"}
    try:
        import winreg
        clave = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System")
        cpa, _t = winreg.QueryValueEx(clave, "ConsentPromptBehaviorAdmin")
        winreg.CloseKey(clave)
        return {"soportado": True,
                "modo": "silencioso" if int(cpa) == 0 else "aviso"}
    except Exception:
        return {"soportado": True, "modo": "aviso"}

def _aplicar_uac(modo: str) -> dict:
    """Cambia los avisos de administración (UAC). Si el servidor ya corre como
    administrador lo aplica directo; si no, pide la ventana de Windows una vez."""
    quieto = modo == "silencioso"
    try:
        if _estado_privilegio() == "administrador":
            import winreg
            clave = winreg.OpenKey(
                winreg.HKEY_LOCAL_MACHINE,
                "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
                0, winreg.KEY_SET_VALUE)
            winreg.SetValueEx(clave, "ConsentPromptBehaviorAdmin", 0,
                              winreg.REG_DWORD, 0 if quieto else 2)
            winreg.SetValueEx(clave, "PromptOnSecureDesktop", 0,
                              winreg.REG_DWORD, 0 if quieto else 1)
            winreg.CloseKey(clave)
            _agregar_aviso("info", "Modo de avisos de seguridad actualizado en la PC")
            return {"ok": True, "metodo": "directo", **_leer_uac()}
    except Exception as e:
        return {"ok": False, "error": str(e)[:160]}
    # sin permisos: abre la ventana de Windows para que la autorices en la PC
    try:
        comando = (
            "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System'"
            f" -Name ConsentPromptBehaviorAdmin -Value {0 if quieto else 2};"
            f" Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System'"
            f" -Name PromptOnSecureDesktop -Value {0 if quieto else 1};"
        )
        indicadores = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        subprocess.Popen(
            ["powershell", "-NoProfile", "-Command",
             "Start-Process powershell -Verb RunAs -WindowStyle Hidden"
             " -ArgumentList '-NoProfile','-Command','" + comando + "'"],
            creationflags=indicadores)
        _agregar_aviso("info", "Autoriza la ventana de permisos en la PC para aplicar el cambio")
        return {"ok": True, "metodo": "ventana-en-la-pc", "pendiente": True}
    except Exception as e:
        return {"ok": False, "error": str(e)[:160]}

def _rechazar_consentimiento() -> dict:
    if _estado_privilegio() != "administrador":
        return {"ok": False, "error": "requiere-admin"}
    try:
        matados = 0
        for p in psutil.process_iter(["name", "pid"]):
            n = (p.info["name"] or "").lower()
            if n in ("consent.exe", "credentialuibroker.exe"):
                try:
                    psutil.Process(int(p.info["pid"])).kill()
                    matados += 1
                except Exception:
                    pass
        if matados:
            _agregar_aviso("info", "Aviso de seguridad rechazado desde el teléfono")
        return {"ok": True, "rechazados": matados}
    except Exception as e:
        return {"ok": False, "error": str(e)[:160]}


ESTADO: dict = {}

def _bucle_estado() -> None:
    """Hilo que sondea CPU, RAM, discos, batería, red y procesos cada 2,5 s."""
    global ESTADO
    psutil.cpu_percent(interval=None)  # primer sondeo para inicializar
    red_prev = psutil.net_io_counters()
    t_prev = time.time()
    bat_enchufado = None
    racha_baja = racha_peligro = False
    ram_flag = False
    discos_flag = set()
    cpu_racha = 0
    while True:
        try:
            time.sleep(2.5)
            cpu = psutil.cpu_percent(interval=None)
            mem = psutil.virtual_memory()
            ahora = time.time()
            red = psutil.net_io_counters()
            dt = max(0.001, ahora - t_prev)
            sube = (red.bytes_sent - red_prev.bytes_sent) / dt      # B/s
            baja = (red.bytes_recv - red_prev.bytes_recv) / dt
            red_prev, t_prev = red, ahora

            bateria = None
            try:
                b = psutil.sensors_battery()
                if b is not None:
                    bateria = {"pct": round(b.percent, 0), "enchufado": bool(b.power_plugged)}
            except Exception:
                pass

            discos = []
            try:
                for d in psutil.disk_partitions():
                    if not d.mountpoint or "cdrom" in d.opts.lower():
                        continue
                    try:
                        u = psutil.disk_usage(d.mountpoint)
                        discos.append({
                            "montaje": d.mountpoint,
                            "pct": round(u.percent, 0),
                            "libre_gb": round(u.free / 1e9, 1),
                            "total_gb": round(u.total / 1e9, 1),
                        })
                    except Exception:
                        pass
            except Exception:
                pass

            procesos = []
            for proc in psutil.process_iter(["pid", "name"]):
                try:
                    procesos.append({
                        "nombre": proc.info["name"] or "?",
                        "cpu": proc.cpu_percent(None),
                    })
                except Exception:
                    pass
            procesos = [p for p in procesos if p["cpu"] and p["cpu"] > 0.1]
            procesos.sort(key=lambda p: p["cpu"], reverse=True)
            procesos = procesos[:6]

            # ------------------- avisos automáticos -------------------
            if bateria is not None:
                pct = int(bateria["pct"])
                enchufado = bateria["enchufado"]
                if bat_enchufado is True and not enchufado:
                    _agregar_aviso("info", f"Se desconectó el cargador ({pct}%)")
                if bat_enchufado is False and enchufado:
                    _agregar_aviso("info", f"Enchufado: cargando batería ({pct}%) ⚡")
                bat_enchufado = enchufado
                if not enchufado and pct <= 25 and not racha_baja:
                    racha_baja = True
                    _agregar_aviso("advertencia", f"Batería baja: {pct}% sin cargador")
                if not enchufado and pct <= 10 and not racha_peligro:
                    racha_peligro = True
                    _agregar_aviso("peligro", f"¡Batería casi agotada: {pct}%! Conecta el cargador")
                if pct > 30:
                    racha_baja = False
                    racha_peligro = False
            if mem.percent > 92 and not ram_flag:
                ram_flag = True
                _agregar_aviso("advertencia", f"Memoria al límite: {mem.percent:.0f}% usada")
            if mem.percent < 82:
                ram_flag = False
            for disco in discos:
                if disco["pct"] > 95 and disco["montaje"] not in discos_flag:
                    discos_flag.add(disco["montaje"])
                    _agregar_aviso("advertencia", f"Disco {disco['montaje']}: {disco['libre_gb']} GB libres")
                elif disco["pct"] < 90:
                    discos_flag.discard(disco["montaje"])
            if cpu > 92:
                cpu_racha += 1
                if cpu_racha >= 24:   # ~60 s sostenido
                    cpu_racha = 0
                    _agregar_aviso("advertencia", "CPU de altísimo uso hace más de un minuto",
                                   clave="cpu-alta", enfriamiento=900)
            else:
                cpu_racha = 0

            # ------------------- ventana de permisos (UAC) -------------------
            try:
                visto = False
                for proc in psutil.process_iter(["name"]):
                    nombre = (proc.info["name"] or "").lower()
                    if nombre in ("consent.exe", "credentialuibroker.exe"):
                        visto = True
                        break
            except Exception:
                visto = SEGURIDAD["detectado"]
            if visto and not SEGURIDAD["detectado"]:
                SEGURIDAD["detectado"] = True
                SEGURIDAD["desde"] = time.time()
                _agregar_aviso("peligro", "🛡️ Ventana de permisos de administrador esperando en la PC",
                               "", 0.0, True)
            elif not visto and SEGURIDAD["detectado"]:
                SEGURIDAD["detectado"] = False
                _agregar_aviso("info", "La ventana de permisos se cerró o respondió")

            ESTADO = {
                "cpu": round(cpu, 0),
                "ram_pct": round(mem.percent, 0),
                "ram_usada_gb": round((mem.total - mem.available) / 1e9, 1),
                "ram_total_gb": round(mem.total / 1e9, 1),
                "bateria": bateria,
                "discos": discos,
                "red_sube_kbps": round(sube / 125.0, 1),   # kB/s
                "red_baja_kbps": round(baja / 125.0, 1),
                "red_total_sube_gb": round(red.bytes_sent / 1e9, 1),
                "red_total_baja_gb": round(red.bytes_recv / 1e9, 1),
                "encendido_s": int(ahora - psutil.boot_time()),
                "procesos": procesos,
                "version": VERSION_APP,
            }
        except Exception:
            time.sleep(1)

threading.Thread(target=_bucle_estado, daemon=True).start()

def listar_ips() -> list:
    resultados = []
    try:
        for nombre, direcciones in psutil.net_if_addrs().items():
            for a in direcciones:
                if a.family == socket.AF_INET:
                    ip = a.address
                    if ip.startswith("127.") or ip.startswith("169.254."):
                        continue
                    if all(c.isdigit() or c == "." for c in ip):
                        resultados.append({"nombre": nombre, "ip": ip})
    except Exception:
        pass
    return resultados

def ip_principal() -> str:
    ips = listar_ips()
    preferidas = [r for r in ips if r["ip"].startswith(("192.168.", "10.", "172.16.", "172.17.", "172.18.", "172.19.", "100."))]
    if preferidas:
        return preferidas[0]["ip"]
    if ips:
        return ips[0]["ip"]
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def _puerto_ocupado(puerto: int) -> bool:
    """True si ya hay algo escuchando en ese puerto (otra instancia del servidor)."""
    try:
        with socket.create_connection(("127.0.0.1", int(puerto)), timeout=0.6):
            return True
    except OSError:
        return False

# ------------------------------------------------------------------ cursor ---

class _PuntoCt(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

class _CursorInfoCt(ctypes.Structure):
    _fields_ = [
        ("tam", ctypes.c_uint),
        ("banderas", ctypes.c_uint),
        ("handle", ctypes.c_void_p),
        ("pos", _PuntoCt),
    ]

_usuario32 = ctypes.windll.user32 if os.name == "nt" else None

def _posicion_cursor():
    """(x, y) de donde está la flecha del ratón, o None si está oculta."""
    if _usuario32 is None:
        return None
    try:
        info = _CursorInfoCt()
        info.tam = ctypes.sizeof(_CursorInfoCt)
        if not _usuario32.GetCursorInfo(ctypes.byref(info)):
            return None
        if info.banderas == 0:
            return None
        return info.pos.x, info.pos.y
    except Exception:
        return None

def _boton_pulsado(vk: int) -> bool:
    """True si un botón del ratón está presionado ahora mismo."""
    try:
        return (_usuario32.GetAsyncKeyState(vk) & 0x8000) != 0
    except Exception:
        return False

# Coordenadas de una flecha clásica de ratón (alto ~17 unidades).
_FLECHA = [
    (0.0, 0.0),
    (0.0, 17.0),
    (3.8, 13.2),
    (6.5, 19.0),
    (9.2, 17.8),
    (6.6, 12.3),
    (12.0, 12.3),
]

def _dibujar_flecha(imagen: Image.Image, cx: float, cy: float, escala: float) -> None:
    """Superpone la flecha del ratón sobre la pantalla capturada."""
    d = ImageDraw.Draw(imagen)
    s = max(2.4, escala * 2.2)           # un poco más grande que el puntero real
    puntos = [(cx + px * s, cy + py * s) for px, py in _FLECHA]
    color_borde = (
        (255, 60, 60) if (_boton_pulsado(0x01) or _boton_pulsado(0x02)) else (0, 0, 0)
    )
    grosor = max(2, int(s * 0.55))
    d.line(puntos + [puntos[0]], fill=color_borde, width=grosor, joint="curve")
    d.polygon(puntos, fill=(255, 255, 255))

def _superponer_cursor(imagen: Image.Image, region: dict) -> None:
    pos = _posicion_cursor()
    if pos is None:
        return
    cx = pos[0] - region["left"]
    cy = pos[1] - region["top"]
    if not (0 <= cx < region["width"] and 0 <= cy < region["height"]):
        return
    escala = imagen.width / region["width"]
    _dibujar_flecha(imagen, cx * escala, cy * escala, escala)

# ----------------------------------------------------------------- captura ---

RECTA = [None]   # (izquierda, arriba, ancho, alto) de la zona capturada
metaData = [None]  # dict {"t":"dim","w","h"} pendiente de avisar al cliente

def _capturar(sct) -> tuple:
    indice = int(CFG.get("pantalla", 1) or 1)
    if indice < 0 or indice >= len(sct.monitors):
        indice = min(1, len(sct.monitors) - 1)
    region = sct.monitors[indice]
    captura = sct.grab(region)
    # BGRA crudo directo (evita la copia lenta píxel a píxel de c.rgb)
    rgba = Image.frombuffer(
        "RGBA", (captura.width, captura.height), captura.raw, "raw", "BGRA", 0, 1
    )
    ancho_max = max(320, min(2560, int(CFG.get("ancho_maximo", 1280))))
    if rgba.width == ancho_max * 2:
        # ruta rápida: bajada exacta a la mitad (reduce 2) y conversión en chico
        imagen = rgba.reduce(2).convert("RGB")
    elif rgba.width > ancho_max:
        alto = max(1, round(rgba.height * ancho_max / rgba.width))
        imagen = rgba.resize((ancho_max, alto), Image.BILINEAR).convert("RGB")
    else:
        imagen = rgba.convert("RGB")
    # la flecha del ratón para que se vea en la app
    try:
        _superponer_cursor(imagen, region)
    except Exception:
        pass
    calidad = max(30, min(90, int(CFG.get("calidad_jpeg", 60))))
    pago = io.BytesIO()
    # sin optimize=True: la codificación rápida reduce la latencia de cada fotograma
    imagen.save(pago, "JPEG", quality=calidad, subsampling=1)
    return pago.getvalue(), (region["left"], region["top"], region["width"], region["height"]), (imagen.width, imagen.height)

def _bucle_captura(cola: Queue, detener: threading.Event) -> None:
    """Hilo por cliente: captura la pantalla y mete JPEGs en la cola."""
    ultimo_dims = None
    try:
        with mss.MSS() as sct:
            while not detener.is_set():
                inicio = time.perf_counter()
                try:
                    datos, recta, dims = _capturar(sct)
                    RECTA[0] = recta
                    if metaData[0] is None and (ultimo_dims is None or dims != ultimo_dims):
                        metaData[0] = {"t": "dim", "w": dims[0], "h": dims[1]}
                    ultimo_dims = dims
                except Exception:
                    time.sleep(0.4)
                    continue
                # mete el fotograma descartando el viejo si la cola está llena:
                # el teléfono siempre recibe lo MÁS reciente (cero acumulación)
                try:
                    cola.put_nowait(datos)
                except Full:
                    try:
                        cola.get_nowait()
                        cola.put_nowait(datos)
                    except (Full, Empty):
                        pass
                fps = max(1.0, min(30.0, float(CFG.get("fps", 24)) or 24.0))
                espera = 1.0 / fps - (time.perf_counter() - inicio)
                if espera > 0:
                    time.sleep(espera)
    except Exception:
        pass

# ------------------------------------------------------------------- entrada ---

CLAVES_VALIDAS = {
    "escape": "esc", "esc": "esc",
    "enter": "enter", "return": "enter",
    "backspace": "backspace", "tab": "tab",
    "space": "space", "espacio": "space",
    "delete": "delete", "supr": "delete", "del": "delete",
    "insert": "insert", "ins": "insert",
    "home": "home", "end": "end", "inicio": "home", "fin": "end",
    "pageup": "pageup", "pagedown": "pagedown", "repag": "pageup", "avpag": "pagedown",
    "left": "left", "right": "right", "up": "up", "down": "down",
    "flecha_izquierda": "left", "flecha_derecha": "right",
    "flecha_arriba": "up", "flecha_abajo": "down",
}
MODIFICADORES = {"ctrl", "alt", "shift", "win"}
BOTONES = {"izq": "left", "der": "right", "medio": "middle"}

def _nombre_tecla(nombre: str):
    nombre = str(nombre).strip().lower()
    if nombre in CLAVES_VALIDAS:
        return CLAVES_VALIDAS[nombre]
    if re.fullmatch(r"f[1-9]|f1[0-2]", nombre):
        return nombre
    if re.fullmatch(r"[a-z0-9_]{1,16}", nombre):
        return nombre
    return None

def _mover(x: float, y: float) -> None:
    recta = RECTA[0]
    if not recta:
        return
    izq, arriba, ancho, alto = recta
    px = izq + int(max(0.0, min(1.0, x)) * ancho)
    py = arriba + int(max(0.0, min(1.0, y)) * alto)
    pyautogui.moveTo(px, py, _pause=False)

def _pegar_texto(texto: str) -> None:
    """Escribe texto no-ASCII (ñ, á, é, ...) copiándolo al portapapeles y pegando."""
    ruta = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8-sig", delete=False) as f:
            f.write(texto)
            ruta = f.name
        cmd = (
            "$t=[IO.File]::ReadAllText('" + ruta + "',[Text.Encoding]::UTF8);"
            "Set-Clipboard -Value $t"
        )
        indicadores = 0
        if os.name == "nt":
            indicadores = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", cmd],
            creationflags=indicadores, timeout=6,
        )
        try:
            pyautogui.hotkey("ctrl", "v", _pause=False)
        except Exception:
            pass
        time.sleep(0.05)
    except Exception:
        pass
    finally:
        if ruta:
            try:
                os.remove(ruta)
            except Exception:
                pass

def _escribir_texto(texto: str) -> None:
    if all(ord(c) < 128 for c in texto):
        try:
            pyautogui.write(texto, interval=0.012, _pause=False)
            return
        except Exception:
            pass
    _pegar_texto(texto)

def manejar_entrada(e: dict):
    """Recibe un evento JSON del teléfono y lo ejecuta en Windows."""
    try:
        t = e.get("t")
        if t == "ping":
            return {"t": "pong", "ts": e.get("ts")}
        elif t == "cfg":
            if "ancho_maximo" in e:
                CFG["ancho_maximo"] = max(480, min(2560, int(e["ancho_maximo"])))
            if "fps" in e:
                CFG["fps"] = max(3, min(30, int(e["fps"])))
            if "calidad_jpeg" in e:
                CFG["calidad_jpeg"] = max(30, min(90, int(e["calidad_jpeg"])))
            if "pantalla" in e:
                CFG["pantalla"] = int(e["pantalla"])
            return None
        elif t == "mover":
            _mover(float(e.get("x", 0)), float(e.get("y", 0)))
        elif t == "pulsar":
            _mover(float(e.get("x", 0)), float(e.get("y", 0)))
            pyautogui.mouseDown(BOTONES.get(e.get("b", "izq"), "left"), _pause=False)
        elif t == "soltar":
            try:
                pyautogui.mouseUp(BOTONES.get(e.get("b", "izq"), "left"), _pause=False)
            except Exception:
                pass
        elif t == "clic":
            _mover(float(e.get("x", 0)), float(e.get("y", 0)))
            boton = BOTONES.get(e.get("b", "izq"), "left")
            try:
                if e.get("dobles"):
                    pyautogui.doubleClick(button=boton, _pause=False)
                else:
                    pyautogui.click(button=boton, _pause=False)
            except Exception:
                pass
        elif t == "deslizar":
            try:
                dy = float(e.get("dy", 0))
                pasos = max(-20, min(20, int(-dy / 120.0)))
                if pasos:
                    pyautogui.scroll(pasos, _pause=False)
            except Exception:
                pass
        elif t == "texto":
            _escribir_texto(str(e.get("s", ""))[:500])
        elif t == "teclas":
            combo = []
            for m in e.get("mods", [])[:4]:
                m = str(m).lower()
                if m in MODIFICADORES:
                    combo.append(m)
            principal = _nombre_tecla(str(e.get("k", "")))
            if principal:
                if combo:
                    pyautogui.hotkey(*combo, principal, _pause=False)
                else:
                    pyautogui.press(principal, _pause=False)
    except Exception:
        pass
    return None

# -------------------------------------------------------------------- app ---

app = FastAPI(title="Control PC", docs_url=None, redoc_url=None)

@app.get("/")
def raiz():
    return RedirectResponse(url="/app/", status_code=307)

@app.post("/api/acceso")
async def api_acceso(req: Request):
    podar_sesiones()
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    clave = str(datos.get("contrasena", ""))
    ip = req.client.host if req.client else "?"
    ahora = time.time()
    lista = [t for t in INTENTOS.get(ip, []) if ahora - t < 60]
    if len(lista) >= 8:
        return JSONResponse({"ok": False, "error": "demasiados-intentos"}, status_code=429)
    if not hmac.compare_digest(clave, str(CFG.get("contrasena", ""))):
        lista.append(ahora)
        INTENTOS[ip] = lista
        time.sleep(0.4)
        return JSONResponse({"ok": False, "error": "clave-erronea"}, status_code=401)
    INTENTOS.pop(ip, None)
    token = secrets.token_urlsafe(24)
    caduca = ahora + 90 * 24 * 3600
    SESIONES[token] = caduca
    podar_sesiones()
    _guardar_sesiones()
    resp = JSONResponse({"ok": True, "token": token})
    resp.set_cookie("sesion", token, max_age=90 * 24 * 3600, samesite="lax", httponly=True)
    return resp

@app.get("/api/salir")
async def api_salir(req: Request):
    token = req.cookies.get("sesion", "")
    if token:
        SESIONES.pop(token, None)
    resp = JSONResponse({"ok": True})
    resp.delete_cookie("sesion")
    return resp

@app.get("/api/estado")
async def api_estado(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    datos = dict(ESTADO)
    ips = listar_ips()
    datos["ips"] = ips
    datos["puerto"] = CFG.get("puerto", PUERTO_DEF)
    datos["host"] = platform.node()
    datos["os"] = platform.platform(terse=True)
    datos["tailscale"] = any("tailscale" in i["nombre"].lower() for i in ips)
    datos["avisos"] = _lista_avisos()
    datos["volumen"] = _leer_volumen()
    datos["uac"] = _leer_uac()
    datos["privilegio"] = _estado_privilegio()
    datos["seguridad"] = {"detectado": SEGURIDAD["detectado"]}
    datos["version"] = VERSION_APP
    datos["actualizacion"] = _hay_actualizacion()
    return datos

@app.get("/api/captura")
async def api_captura(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    with mss.MSS() as sct:
        datos, _recta, _dims = _capturar(sct)
    return Response(
        datos,
        media_type="image/jpeg",
        headers={"Content-Disposition": "inline; filename=captura-pc.jpg"},
    )

@app.get("/api/volumen")
async def api_volumen_get(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    return _leer_volumen()

@app.post("/api/volumen")
async def api_volumen(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    nivel = datos.get("nivel", None)
    mudo = datos.get("mudo", None)
    if nivel is not None:
        try:
            nivel = max(0, min(100, int(nivel)))
        except Exception:
            nivel = None
    if mudo is not None:
        mudo = bool(mudo)
    return _aplicar_volumen(nivel, mudo)

@app.get("/api/uac")
async def api_uac_get(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    return _leer_uac()

@app.post("/api/uac")
async def api_uac(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    modo = str(datos.get("modo", "aviso"))
    if modo not in ("silencioso", "aviso"):
        modo = "aviso"
    return _aplicar_uac(modo)

@app.get("/api/seguridad")
async def api_seguridad(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    return {
        "detectado": SEGURIDAD["detectado"],
        "privilegio": _estado_privilegio(),
        "uac": _leer_uac(),
    }

@app.post("/api/seguridad-accion")
async def api_seguridad_accion(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    accion = str(datos.get("accion", ""))
    if accion == "rechazar":
        return _rechazar_consentimiento()
    if accion == "permitir":
        resultado = _aplicar_uac("silencioso")
        if resultado.get("ok"):
            resultado["mensaje"] = "Modo silencioso aplicado: Windows ya no preguntará"
        return resultado
    return {"ok": False, "error": "accion-desconocida"}

@app.post("/api/aviso")
async def api_aviso(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    texto = str(datos.get("texto", "")).strip()[:200] or "Aviso de prueba 🔔"
    _agregar_aviso("info", texto)
    return {"ok": True}

@app.post("/api/entrada")
async def api_entrada(req: Request):
    """Ejecuta cualquier evento del protocolo (teclas, texto, mover, clic…) por HTTP,
    sin necesidad de la conexión de video abierta."""
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    try:
        datos = await req.json()
    except Exception:
        datos = {}
    if not isinstance(datos, dict) or not datos:
        return {"ok": False, "error": "evento-vacio"}
    manejar_entrada(datos)
    return {"ok": True}

@app.websocket("/ws-audio")
async def ws_audio(ws: WebSocket):
    token = ws.cookies.get("sesion", "") or ws.query_params.get("sesion", "")
    await ws.accept()
    if not token_valido(token):
        try:
            await ws.send_text(json.dumps({"t": "error", "m": "sin-sesion"}))
            await ws.close(code=4401)
        except Exception:
            pass
        return
    cliente = {
        "cola": asyncio.Queue(maxsize=24),
        "loop": asyncio.get_running_loop(),
    }
    AUDIO_CLIENTES.append(cliente)
    hay = len([c for c in AUDIO_CLIENTES if True])
    AUDIO["clientes"] = hay
    if hay == 1:
        AUDIO["error"] = ""
        AUDIO["sr"] = 0
        AUDIO_DETENER.clear()
        threading.Thread(target=_bucle_audio, daemon=True).start()
        for _ in range(80):
            if AUDIO["sr"] or AUDIO["error"]:
                break
            await asyncio.sleep(0.05)
    try:
        await ws.send_text(json.dumps({
            "t": "meta-audio",
            "sr": AUDIO["sr"],
            "error": AUDIO["error"][:200],
        }))
        async def _enviar_audio_cliente():
            while True:
                try:
                    dato = cliente["cola"].get_nowait()
                except asyncio.QueueEmpty:
                    await asyncio.sleep(0.004)
                    continue
                await ws.send_bytes(dato)

        tarea_audio = asyncio.create_task(_enviar_audio_cliente())
        try:
            while True:
                mensaje = await ws.receive()
                if mensaje.get("type") == "websocket.disconnect":
                    break
        finally:
            tarea_audio.cancel()
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        try:
            AUDIO_CLIENTES.remove(cliente)
        except ValueError:
            pass
        if not AUDIO_CLIENTES:
            AUDIO["sr"] = 0
            AUDIO["error"] = ""
            AUDIO_DETENER.set()

@app.websocket("/ws")
async def ws_pantalla(ws: WebSocket):
    token = ws.cookies.get("sesion", "") or ws.query_params.get("sesion", "")
    await ws.accept()
    if not token_valido(token):
        try:
            await ws.send_text(json.dumps({"t": "error", "m": "sin-sesion"}))
            await ws.close(code=4401)
        except Exception:
            pass
        return

    cola: Queue = Queue(maxsize=2)
    detener = threading.Event()
    hilo = threading.Thread(target=_bucle_captura, args=(cola, detener), daemon=True)
    hilo.start()
    candado = asyncio.Lock()
    try:
        ws_client_host = ws.client.host if ws.client else "?"
        _agregar_aviso("info", f"El teléfono se conectó ({ws_client_host})")
    except Exception:
        pass

    async def _enviar_fotogramas():
        while not detener.is_set():
            # manda primero el aviso de dimensiones si hay uno pendiente
            meta = metaData[0]
            if meta is not None:
                try:
                    async with candado:
                        await ws.send_text(json.dumps(meta))
                    metaData[0] = None
                except Exception:
                    break
            try:
                dato = cola.get_nowait()
            except Empty:
                await asyncio.sleep(0.004)
                continue
            # drena hasta el fotograma más nuevo antes de enviar (evita atraso
            # cuando la red va más lenta que la captura)
            while True:
                try:
                    dato = cola.get_nowait()
                except Empty:
                    break
            async with candado:
                await ws.send_bytes(dato)

    tarea = asyncio.create_task(_enviar_fotogramas())
    try:
        while True:
            mensaje = await ws.receive()
            if mensaje.get("type") == "websocket.disconnect":
                break
            texto = mensaje.get("text")
            if texto:
                try:
                    respuesta = manejar_entrada(json.loads(texto))
                except Exception:
                    respuesta = None
                if respuesta:
                    async with candado:
                        await ws.send_text(json.dumps(respuesta))
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        detener.set()
        tarea.cancel()
        try:
            _agregar_aviso("info", "El teléfono se desconectó")
        except Exception:
            pass

# ------------------------------------------------------------- recursos web ---

def _crear_iconos() -> None:
    carpeta = ESTATICO / "iconos"
    carpeta.mkdir(parents=True, exist_ok=True)
    fuente = None
    for nombre_fuente in ("arialbd.ttf", "segoeuib.ttf", "calibrib.ttf"):
        try:
            fuente = ImageFont.truetype(f"C:/Windows/Fonts/{nombre_fuente}", 120)
            break
        except Exception:
            fuente = None
    if fuente is None:
        fuente = ImageFont.load_default()
    objetivo = {
        "icon-192.png": (192, 18),
        "icon-512.png": (512, 60),
        "icon-maskable-512.png": (512, 130),
    }
    for nombre, (tamano, margen) in objetivo.items():
        ruta = carpeta / nombre
        if ruta.exists():
            continue
        img = Image.new("RGB", (tamano, tamano), (10, 14, 25))
        d = ImageDraw.Draw(img)
        margen_real = margen * tamano // 512
        d.rounded_rectangle(
            (margen_real, margen_real, tamano - margen_real, tamano - margen_real),
            radius=tamano // 6, fill=(37, 99, 235),
        )
        texto = "PC"
        caja = d.textbbox((0, 0), texto, font=fuente)
        ancho_t = caja[2] - caja[0]
        alto_t = caja[3] - caja[1]
        d.text(((tamano - ancho_t) / 2 - caja[0], (tamano - alto_t) / 2 - caja[1]),
               texto, font=fuente, fill=(255, 255, 255))
        img.save(ruta, "PNG")

def _banner() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ancho_terminal = 46
    ip = ip_principal()
    puerto = int(CFG.get("puerto", PUERTO_DEF))
    url = f"http://{ip}:{puerto}/app/"
    print("=" * ancho_terminal)
    print("  CONTROL PC — servidor activo".center(ancho_terminal))
    print("=" * ancho_terminal)
    print(f"  Peligro de privacidad: solo comparte esto con tu teléfono.")
    print(f"  Abre en el teléfono:   {url}")
    print(f"  Contraseña:            {CFG.get('contrasena', '????')}")
    print("-" * ancho_terminal)
    try:
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.make()
        qr.print_ascii(invert=True)
    except Exception:
        pass
    print("  (Ctrl+C aquí para apagar el servidor)")
    print("=" * ancho_terminal)

# Montaje de archivos estáticos al final
ESTATICO.mkdir(exist_ok=True)
app.mount("/app", StaticFiles(directory=ESTATICO, html=True), name="app")

# ----------------------------------------------------------- arranque directo ---

if __name__ == "__main__":
    modo_prueba = "--prueba" in sys.argv
    _crear_iconos()

    if not modo_prueba and _puerto_ocupado(int(CFG.get("puerto", PUERTO_DEF))):
        print("Ya hay otro servidor de Control PC corriendo en ese puerto. Saliendo sin cambiar nada.")
        sys.exit(3)

    if modo_prueba:
        print("Comprobando módulos y captura…")
        with mss.MSS() as sct:
            for i, region in enumerate(sct.monitors):
                print(f"  Pantalla {i}: {region['width']}x{region['height']} en ({region['left']},{region['top']})")
            datos, recta, dims = _capturar(sct)
            print(f"  Fotograma JPEG: {len(datos) / 1024:.0f} KB  OK")
        print(f"  Resolución usada por el raton: {pyautogui.size()}")
        print(f"  CPU {psutil.cpu_percent(interval=0.5):.0f}%  RAM {psutil.virtual_memory().percent:.0f}%")
        print("Todo listo.")
        print(f"Contraseña del servidor: {CFG['contrasena']}")
        sys.stdout.flush()
        sys.exit(0)

    import uvicorn
    _banner()
    _agregar_aviso("info", "Servidor Control PC listo ✓ conecta el teléfono desde el QR")
    threading.Thread(target=_avisar_actualizacion, daemon=True).start()
    cert = BASE / "cert.pem"
    clave = BASE / "clave.pem"
    if cert.exists() and clave.exists():
        uvicorn.run(app, host="0.0.0.0", port=int(CFG.get("puerto", PUERTO_DEF)),
                    ssl_certfile=str(cert), ssl_keyfile=str(clave), log_level="warning")
    else:
        uvicorn.run(app, host="0.0.0.0", port=int(CFG.get("puerto", PUERTO_DEF)),
                    log_level="warning")
