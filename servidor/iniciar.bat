@echo off
title Control PC - Servidor
chcp 65001 >nul
cd /d "%~dp0"

REM Modo autoarranque: se usa como RESPALDO si el servidor de administrador
REM no arranco. Espera para darle prioridad al de admin y sale si ya corre.
if "%~1"=="--auto" (
  echo Autoarranque pendiente 60 s ^(respaldo^)...
  timeout /t 60 /nobreak >nul
)

echo.
echo =========================================
echo    CONTROL PC - iniciando servidor...
echo =========================================
echo.

where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado o no esta en el PATH.
  echo     Descarga Python desde https://www.python.org/downloads/
  echo     y marca la casilla "Add python.exe to PATH" al instalar.
  pause
  exit /b 1
)

echo [1/2] Comprobando librerias (la primera vez puede tardar un poco)...
python -c "import fastapi, uvicorn, mss, PIL, psutil, pyautogui, qrcode" 2>nul
if errorlevel 1 (
  echo       Instalando librerias...
  python -m pip install -r requisitos.txt --quiet --no-input
  if errorlevel 1 (
    echo [X] No se pudieron instalar las librerias. Verifica tu conexion a internet y ejecuta:
    echo     python -m pip install -r requisitos.txt
    pause
    exit /b 1
  )
)
echo [OK] Librerias listas.

echo [2/2] Abriendo servidor...
:loop
python servidor.py
if "%errorlevel%" EQU "3" (
  echo [OK] Ya hay otro servidor corriendo. Esta copia termina sin cambiar nada.
  exit /b 0
)
echo.
echo El servidor se cerro inesperadamente. Reiniciando en 3 segundos...
timeout /t 3 /nobreak >nul
goto loop
