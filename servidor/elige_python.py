# elige_python.py — encuentra un Python que tenga TODAS las librerias de Control PC.
# El .bat maestro lo invoca y lee los RESULTADOS por archivos planos (cero parsing):
#   cp_elige_ok.txt:  CUSTOM | NONE
#   cp_elige_mod.txt: py (launcher -3.12) | direct (exe directo)
#   cp_elige_exe.txt: ruta del interprete
# Tambien anota en la bitacora %TEMP%\maestro_debug.txt.
import os, sys, glob, subprocess, tempfile

TMP = tempfile.gettempdir()
LOG = os.path.join(TMP, "maestro_debug.txt")
MOD = "import fastapi, uvicorn, mss, PIL, psutil, pyautogui, qrcode, numpy, soundcard, pycaw, comtypes, win32api"

def log(t):
    try:
        with open(LOG, "a", encoding="utf-8", errors="replace") as f:
            f.write("[elige.py] " + t + "\n")
    except Exception:
        pass

def wfile(name, txt):
    try:
        with open(os.path.join(TMP, name), "w", encoding="utf-8") as f:
            f.write(txt)
    except Exception:
        pass

def probe(path, args):
    try:
        r = subprocess.run([path] + args + ["-c", MOD], capture_output=True, timeout=60)
        return r.returncode == 0
    except Exception:
        return False

def main():
    # valores por defecto: si algo falla a mitad de camino quedan como NONE
    wfile("cp_elige_ok.txt", "NONE")
    wfile("cp_elige_mod.txt", "")
    wfile("cp_elige_exe.txt", "")

    cand = []   # (ruta, modo, args)
    try:
        cand.append([sys.executable, "direct", []])   # el python que corre este script
    except Exception:
        pass

    la = os.environ.get("LOCALAPPDATA", "")
    pf = os.environ.get("ProgramFiles", "")
    rutas = []
    if la:
        rutas.append(os.path.join(la, "Programs", "Python", "Launcher", "py.exe"))
        rutas += glob.glob(os.path.join(la, "Programs", "Python", "Python*", "python.exe"))
        rutas += glob.glob(os.path.join(la, "Python", "pythoncore-3*", "python.exe"))
    if pf:
        rutas += glob.glob(os.path.join(pf, "Python3*", "python.exe"))

    for p in rutas:
        if "WindowsApps" in p:
            continue    # alias de la tienda: nunca
        try:
            if not os.path.isfile(p):
                continue
        except Exception:
            continue
        if p.lower().endswith("py.exe"):
            cand.append([p, "py", ["-3.12"]])
        else:
            cand.append([p, "direct", []])

    log("candidatos: " + ",".join(c[0] for c in cand))

    for path, mode, args in cand:
        ok = probe(path, args)
        log("probe " + mode + " " + path + " -> " + ("OK" if ok else "no"))
        if not ok:
            continue
        wfile("cp_elige_ok.txt", "CUSTOM")
        wfile("cp_elige_mod.txt", mode)
        wfile("cp_elige_exe.txt", path)
        log("resultado: CUSTOM " + mode + " " + path)
        return

    log("resultado: NONE")

# protege contra cierre abrupto: los archivos por defecto ya estan escritos
try:
    main()
finally:
    pass
