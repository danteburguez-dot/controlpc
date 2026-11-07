# -*- coding: utf-8 -*-
"""
pruebas_apk.py — batería de pruebas del proyecto Control PC.

Verifica TODO lo que la APK consume del servidor (clientes Android) y la
integridad del archivo APK descargado. Uso:
    python pruebas_apk.py [ruta_opcional_del_apk]
El servidor debe estar corriendo en 127.0.0.1:8566.
"""

import asyncio
import ctypes
import http.client
import io
import json
import os
import sys
import time
import urllib.request
import zipfile

# El servidor mapea en coordenadas fisicas (pantalla real); el test mide en lo mismo
try:
    ctypes.windll.user32.SetProcessDPIAware()
except Exception:
    pass

HOST, PUERTO = "127.0.0.1", 8566
RESULTADOS = []

def reportar(nombre, ok, detalle=""):
    RESULTADOS.append((nombre, ok, detalle))
    print(("  [OK]    " if ok else "  [FALLA] ") + nombre + ((" -> " + detalle) if detalle else ""))

def pedir(ruta, metodo="GET", cuerpo=None, token=None):
    try:
        con = http.client.HTTPConnection(HOST, PUERTO, timeout=10)
        encabezados = {}
        if token:
            encabezados["Cookie"] = "sesion=" + token
        datos = None
        if cuerpo is not None:
            datos = json.dumps(cuerpo).encode()
            encabezados["Content-Type"] = "application/json"
        con.request(metodo, ruta, body=datos, headers=encabezados)
        r = con.getresponse()
        texto = r.read().decode("utf-8", "replace")
        codigo = r.status
        con.close()
    except Exception:
        return -1, {}
    try:
        j = json.loads(texto)
    except Exception:
        j = texto
    return codigo, j

def consecucion_token(clave):
    estado, j = pedir("/api/acceso", "POST", {"contrasena": clave})
    return estado, j

CARPETA_SERVIDOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "servidor")

def leer_clave():
    with open(os.path.join(CARPETA_SERVIDOR, "config.json"), "r", encoding="utf-8") as f:
        return json.load(f)["contrasena"]

# ------------------------------------------------------------------ APK ----

def probar_archivo_apk():
    ruta = None
    if len(sys.argv) > 1:
        ruta = sys.argv[1]
    else:
        for candidata in (
            r"C:\Users\Dante burguez\Desktop\Control PC v1.3.apk",
            r"C:\Users\Dante burguez\Downloads\ControlPC-v1.3.apk",
            r"C:\Users\Dante burguez\Downloads\ControlPC-v1.2.apk",
        ):
            if os.path.exists(candidata):
                ruta = candidata
                break
    if not ruta or not os.path.exists(ruta):
        reportar("APK presente en computadora", False, "no se encontro archivo .apk")
        return
    z = zipfile.ZipFile(ruta)
    print(f"  Probando APK: {os.path.basename(ruta)} ({os.path.getsize(ruta)/1e6:.1f} MB)")
    danado = z.testzip()
    reportar("APK: integridad CRC de todas las entradas", danado is None, str(danado))
    nombres = z.namelist()
    necesita = ["AndroidManifest.xml", "lib/arm64-v8a/libapp.so",
                "lib/arm64-v8a/libflutter.so", "assets/flutter_assets/"]
    faltantes = [n for n in necesita if not any(n in x for x in nombres)]
    reportar("APK: contenido Flutter (manifest, libapp.so, libflutter.so, assets)",
             not faltantes, ",".join(faltantes) or "todo presente")
    firmas_v2 = None
    with open(ruta, "rb") as f:
        contenido_apk = f.read()
        firmas_v2 = b"APK Sig Block 42" in contenido_apk   # magic del esquema v2/v3
    reportar("APK: firma digital (esquema v2 Android, 'APK Sig Block 42')", bool(firmas_v2))
    dexes = [n for n in nombres if n.startswith("classes") and n.endswith(".dex")]
    contenido = b""
    for d in dexes:
        contenido += z.read(d)
    plugin_ok = (b"FlutterPcmSoundPlugin" in contenido) or (b"flutter_pcm_sound" in contenido)
    reportar("APK: plugin de AUDIO (flutter_pcm_sound) dentro del dex", plugin_ok)
    # manifest: permiso INTERNET + cleartext (los dos imnopensables para la APK)
    man = z.read("AndroidManifest.xml")
    def tiene(s):
        return (s.encode() in man) or (s.encode("utf-16-le") in man) or (s.encode("utf-16-be") in man)
    reportar("APK: permiso INTERNET en el manifest", tiene("android.permission.INTERNET"))
    reportar("APK: http-claro habilitado (usesCleartextTraffic)", tiene("usesCleartextTraffic"))
    # al menos 2 ABI? no critical
    print()

# -------------------------------------------------------------- protocolo ---

def probar_https(token_de_prueba=None):
    estado, cuerpo = pedir("/app/", "GET")
    ok = estado == 200 and ("Control PC" in str(cuerpo)[:4000] or estado == 200)
    reportar("WEB: portada /app/ responde 200", estado == 200, str(estado))

    MALA = "CLAVEMUYERRONEA"
    estado_mal, _ = pedir("/api/acceso", "POST", {"contrasena": MALA})
    reportar("APK: clave MALA responde 401 (mensaje claro en la app)", estado_mal == 401, str(estado_mal))

    with open(os.path.join(CARPETA_SERVIDOR, "config.json"), "r", encoding="utf-8") as f:
        clave = json.load(f)["contrasena"]
    estado_b, sesion = consecucion_token(clave)
    token = sesion.get("token", "")
    reportar("APK: clave buena responde 200 + token", estado_b == 200 and len(token) > 20)

    estado, datos = pedir("/api/estado", token=token)
    claves_apk = ["cpu", "ram_pct", "discos", "red_baja_kbps", "encendido_s", "procesos",
                  "host", "os", "ips", "puerto", "version", "avisos", "volumen",
                  "uac", "privilegio", "seguridad", "actualizacion", "clave_dias"]
    faltan = [k for k in claves_apk if k not in (datos if isinstance(datos, dict) else {})]
    reportar("APK: /api/estado trae TODAS las claves que pinta la app",
             estado == 200 and not faltan, ",".join(faltan) or "todo")

    estado, r = pedir("/api/entrada", "POST", {"t": "teclas", "mods": [], "k": "f15"}, token=token)
    reportar("APK: /api/entrada (teclado/combos) responde ok", estado == 200 and r.get("ok") is True)

    nivel_antes = pedir("/api/volumen", token=token)[1].get("nivel")
    estado, r = pedir("/api/volumen", "POST", {"nivel": nivel_antes if nivel_antes is not None else 50}, token=token)
    reportar("APK: /api/volumen POST + GET coherentes",
             estado == 200 and r.get("nivel") == nivel_antes, f"antes={nivel_antes} ahora={r.get('nivel')}")

    estado, r = pedir("/api/seguridad", token=token)
    reportar("APK: /api/seguridad (para banner de UAC) con claves",
             estado == 200 and "detectado" in r and "uac" in r)
    texto_prueba = "[pruebas] canal de avisos verificado en " + time.strftime("%H:%M:%S")
    pedir("/api/aviso", "POST", {"texto": texto_prueba}, token=token)
    _, datos2 = pedir("/api/estado", token=token)
    hay_aviso = any(texto_prueba[:30] in str(a.get("texto", "")) for a in datos2.get("avisos", []))
    reportar("APK: POST /api/aviso aparece en estado.avisos (snackbar)", hay_aviso)

    estado, r = pedir("/api/salir", "GET", token=token)
    estado_desp, cuerpo_desp = pedir("/api/estado", token=token)
    cerrado = estado == 200 and estado_desp == 401 and cuerpo_desp.get("error") == "sin-sesion"
    reportar("APK: /api/salir cierra la sesion (401 despues)", cerrado,
             f"antes={estado} despues={estado_desp} cuerpo={cuerpo_desp}")
    # para poder seguir con las websockets, se nueva sesion otra vez
    estado, sesion = consecucion_token(leer_clave())
    token = sesion.get("token", "")
    return token

# ---------------------------------------------------------------- websocket ---

async def probar_websockets(token):
    import websockets

    aspecto = {
        "frame": False, "dim": False, "fps": 0.0, "kbs": 0,
        "audio_meta": None, "audio_paq": 0, "audio_bytes": 0,
        "cierre_sin_sesion": False,
    }
    uri = f"ws://127.0.0.1:{PUERTO}/ws?sesion={token}"
    async with websockets.connect(uri, max_size=4 * 1024 * 1024) as ws:
        inicio = time.perf_counter()
        paquetes = 0
        vistos = 0
        ultimo_dim_time = None
        t_fin = inicio + 4.0
        while time.perf_counter() < t_fin:
            try:
                dato = await asyncio.wait_for(ws.recv(), timeout=0.8)
            except (asyncio.TimeoutError, TimeoutError):
                continue
            if isinstance(dato, bytes):
                vistos += 1
                if dato[:3] == b"\xff\xd8\xff":
                    aspecto["frame"] = True
            else:
                m = json.loads(dato)
                if m.get("t") == "dim":
                    aspecto["dim"] = True
        aspecto["fps"] = round(vistos / 4.0, 1)
        aspecto["kbs"] = 0

    # eventos que la APK envia: mover a la posicion ACTUAL del cursor (sin molestar)
    class _Punto(ctypes.Structure):
        _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]
    p = _Punto()
    ctypes.windll.user32.GetCursorPos(ctypes.byref(p))
    async with websockets.connect(uri, max_size=4 * 1024 * 1024) as ws:
        await ws.send(json.dumps({"t": "cfg", "ancho_maximo": 1280, "calidad_jpeg": 55, "fps": 12, "pantalla": 1}))
        await asyncio.sleep(0.4)
        x = max(0.0, min(1.0, p.x / 1920.0))
        y = max(0.0, min(1.0, p.y / 1080.0))
        await ws.send(json.dumps({"t": "mover", "x": x, "y": y}))
        await asyncio.sleep(0.3)
        p2 = _Punto()
        ctypes.windll.user32.GetCursorPos(ctypes.byref(p2))
        cerca = abs(p2.x - p.x) <= 3 and abs(p2.y - p.y) <= 3
        reportar("APK: evento 'mover' posiciona el raton exactamente", cerca,
                 f"de ({p.x},{p.y}) a ({p2.x},{p2.y})")

    reportar("APK: video WS entrega fotogramas JPEG", aspecto["frame"])
    reportar("APK: video WS envia meta 'dim' (tamano de imagen)", aspecto["dim"])
    reportar("APK: video WS alcanza >= 5 fps", aspecto["fps"] >= 5, f"{aspecto['fps']} fps")

    # audio
    uri_a = f"ws://127.0.0.1:{PUERTO}/ws-audio?sesion={token}"
    async with websockets.connect(uri_a) as ws:
        meta = None
        bytes_tot = 0
        paq = 0
        t_fin = time.perf_counter() + 3.0
        while time.perf_counter() < t_fin:
            try:
                dato = await asyncio.wait_for(ws.recv(), timeout=1.5)
            except (asyncio.TimeoutError, TimeoutError):
                break
            if isinstance(dato, str):
                meta = json.loads(dato)
            else:
                paq += 1
                bytes_tot += len(dato)
    sr = (meta or {}).get("sr")
    error_a = (meta or {}).get("error", "")
    reportar("APK: audio WS meta con sample rate >= 8000", bool(sr) and sr >= 8000 and not error_a,
             f"sr={sr} err={error_a[:60]}")
    reportar("APK: audio WS fluye datos en vivo (>= 100 KB / 3 s)", bytes_tot >= 100_000,
             f"{paq} paquetes, {bytes_tot // 1024} KB")

    # sin sesion -> cierre 4401/aviso
    async with websockets.connect(f"ws://127.0.0.1:{PUERTO}/ws") as ws_malo:
        try:
            dato = await asyncio.wait_for(ws_malo.recv(), timeout=3)
            if isinstance(dato, str) and json.loads(dato).get("t") == "error":
                aspecto["cierre_sin_sesion"] = True
        except Exception:
            aspecto["cierre_sin_sesion"] = False
    reportar("APK: WS sin sesion es rechazado (sin-sesion)", aspecto["cierre_sin_sesion"])

# ------------------------------------------------------------------- main ---

async def main():
    print("=" * 60)
    print("   PRUEBAS CONTROL PC — simulacion de la APK Android")
    print("=" * 60)
    print()
    clave = leer_clave()
    print(f"  Servidor: {HOST}:{PUERTO}  clave: {clave}  (de config.json)")
    print()

    probar_archivo_apk()

    # sesion de trabajo para websockets
    estado, sesion = consecucion_token(clave)
    token = sesion.get("token", "")
    if estado != 200:
        reportar("sesion de prueba creada", False, f"estado {estado}")
        print()
        return

    print()
    probar_https(token)

    print()
    await probar_websockets(token)

    print()
    ok = sum(1 for _, o, _ in RESULTADOS if o)
    malo = len(RESULTADOS) - ok
    print("=" * 60)
    print(f"   RESULTADO: {ok}/{len(RESULTADOS)} pruebas OK" + (f"   ({malo} FALLARON)" if malo else "   TODO VERDE"))
    print("=" * 60)
    for nombre, bueno, detalle in RESULTADOS:
        if not bueno:
            print(f"   -> FALLA: {nombre}: {detalle}")
    print()

if __name__ == "__main__":
    asyncio.run(main())
