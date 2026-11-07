@echo off
title Control PC - Servidor Administrador
chcp 65001 >nul
REM Corre el servidor CON permisos de administrador.
REM Con esto el telefono puede ademas RECHAZAR los avisos de seguridad (UAC).

net session >nul 2>&1
if errorlevel 1 (
  echo Pidiendo permisos de administrador ^(acepta la ventana de Windows^)...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

:admin
cd /d "%~dp0"

REM Regla de firewall de una vez (siendo administrador no vuelve a preguntar)
netsh advfirewall firewall show rule name="Control PC" >nul 2>&1
if errorlevel 1 netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566 >nul 2>&1

where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. https://www.python.org/downloads/
  pause
  exit /b 1
)

python -c "import fastapi, uvicorn, mss, PIL, psutil, pyautogui, qrcode" 2>nul
if errorlevel 1 (
  echo [1/2] Instalando librerias (primera vez)...
  python -m pip install -r requisitos.txt --quiet --no-input
)

echo [2/2] Abriendo servidor como ADMINISTRADOR...
:loop
python servidor.py
set "EC=%errorlevel%"
if "%EC%" EQU "3" (
  echo [OK] Ya habia otro servidor corriendo. Este sale sin cambiar nada.
  exit /b 0
)
echo.
echo El servidor se cerro. Reiniciando en 3 segundos...
timeout /t 3 /nobreak >nul
goto loop
