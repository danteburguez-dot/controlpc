@echo off
title Control PC - Tailscale (acceso desde cualquier lugar)
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. https://www.python.org/downloads/
  pause
  exit /b 1
)

where tailscale >nul 2>nul
if errorlevel 1 (
  if exist "C:\Program Files\Tailscale\tailscale.exe" (
    set "PATH=%PATH%;C:\Program Files\Tailscale"
  ) else (
    echo [1/3] Instalando Tailscale (gratis)...
    winget install -e --id tailscale.tailscale --accept-source-agreements --accept-package-agreements --silent
    if errorlevel 1 (
      echo [X] No se pudo instalar automaticamente.
      echo     Descargalo a mano: https://tailscale.com/download
      pause
      exit /b 1
    )
    set "PATH=%PATH%;C:\Program Files\Tailscale"
  )
)

echo [2/3] Iniciando sesion en Tailscale...
echo      Se abrira tu navegador para entrar con tu cuenta.
echo      IMPORTANTE: en el telefono usa LA MISMA cuenta
echo      que aqui, o no se veran entre si.
tailscale up --accept-dns=false
if errorlevel 1 (
  echo [!] El inicio de sesion no se completo. Reintenta: doble clic de nuevo.
  pause
  exit /b 1
)

echo [3/3] Abriendo la pantalla con IP y QR para conectar desde cualquer lugar:
python servidor.py --tailscale
echo.
echo PASOS FINALES:
echo   1) En el telefono: instala la app Tailscale e inicia sesion con la MISMA cuenta.
echo   2. En el telefono abre la APK Control PC y escribe la IP 100.x.y.z que ves arriba.
echo   3) Desde otro pais, cualquier red wifi o datos moviles: todo funcionara.
echo.
pause
