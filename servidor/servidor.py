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

BASE = Path(__file__).resolve().parent
ESTATICO = BASE / "estatico"
ARCHIVO_CONFIG = BASE / "config.json"

PUERTO_DEF = 8566
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
        "fps": 12,
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

# ------------------------------------------------------------------ estado ---

ESTADO: dict = {}

def _bucle_estado() -> None:
    """Hilo que sondea CPU, RAM, discos, batería, red y procesos cada 2,5 s."""
    global ESTADO
    psutil.cpu_percent(interval=None)  # primer sondeo para inicializar
    red_prev = psutil.net_io_counters()
    t_prev = time.time()
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

def _capturar(sct) -> tuple:
    indice = int(CFG.get("pantalla", 1) or 1)
    if indice < 0 or indice >= len(sct.monitors):
        indice = min(1, len(sct.monitors) - 1)
    region = sct.monitors[indice]
    captura = sct.grab(region)
    imagen = Image.frombytes("RGB", (captura.width, captura.height), captura.rgb)
    ancho_max = max(320, min(2560, int(CFG.get("ancho_maximo", 1280))))
    if imagen.width > ancho_max:
        alto = max(1, round(imagen.height * ancho_max / imagen.width))
        imagen = imagen.resize((ancho_max, alto), Image.BILINEAR)
    # la flecha del ratón para que se vea en la app
    try:
        _superponer_cursor(imagen, region)
    except Exception:
        pass
    calidad = max(30, min(90, int(CFG.get("calidad_jpeg", 60))))
    pago = io.BytesIO()
    imagen.save(pago, "JPEG", quality=calidad, subsampling=1)
    return pago.getvalue(), (region["left"], region["top"], region["width"], region["height"])

def _bucle_captura(cola: Queue, detener: threading.Event) -> None:
    """Hilo por cliente: captura la pantalla y mete JPEGs en la cola."""
    try:
        with mss.MSS() as sct:
            while not detener.is_set():
                inicio = time.perf_counter()
                try:
                    datos, recta = _capturar(sct)
                    RECTA[0] = recta
                except Exception:
                    time.sleep(0.4)
                    continue
                try:
                    cola.put_nowait(datos)
                except Full:
                    pass
                fps = max(1.0, min(30.0, float(CFG.get("fps", 12)) or 12.0))
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
    return datos

@app.get("/api/captura")
async def api_captura(req: Request):
    token = req.cookies.get("sesion", "")
    if not token_valido(token):
        return JSONResponse({"ok": False, "error": "sin-sesion"}, status_code=401)
    with mss.MSS() as sct:
        datos, _ = _capturar(sct)
    return Response(
        datos,
        media_type="image/jpeg",
        headers={"Content-Disposition": "inline; filename=captura-pc.jpg"},
    )

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

    async def _enviar_fotogramas():
        while not detener.is_set():
            try:
                dato = cola.get_nowait()
            except Empty:
                await asyncio.sleep(0.004)
                continue
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

    if modo_prueba:
        print("Comprobando módulos y captura…")
        with mss.MSS() as sct:
            for i, region in enumerate(sct.monitors):
                print(f"  Pantalla {i}: {region['width']}x{region['height']} en ({region['left']},{region['top']})")
            datos, recta = _capturar(sct)
            print(f"  Fotograma JPEG: {len(datos) / 1024:.0f} KB  OK")
        print(f"  Resolución usada por el raton: {pyautogui.size()}")
        print(f"  CPU {psutil.cpu_percent(interval=0.5):.0f}%  RAM {psutil.virtual_memory().percent:.0f}%")
        print("Todo listo.")
        print(f"Contraseña del servidor: {CFG['contrasena']}")
        sys.stdout.flush()
        sys.exit(0)

    import uvicorn
    _banner()
    cert = BASE / "cert.pem"
    clave = BASE / "clave.pem"
    if cert.exists() and clave.exists():
        uvicorn.run(app, host="0.0.0.0", port=int(CFG.get("puerto", PUERTO_DEF)),
                    ssl_certfile=str(cert), ssl_keyfile=str(clave), log_level="warning")
    else:
        uvicorn.run(app, host="0.0.0.0", port=int(CFG.get("puerto", PUERTO_DEF)),
                    log_level="warning")
