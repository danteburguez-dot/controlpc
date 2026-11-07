@echo off
title Login de Control PC
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. https://www.python.org/downloads/
  pause
  exit /b 1
)

:inicio
cls
REM Muestra: contraseña actual + dias restantes + QR RAPIDO (entra sin escribir)
REM y QR NORMAL (pide la clave). Cambia con la clave porque la incluye.
python servidor.py --loginqr

echo.
echo   Quieres obtener una nueva contrasena? Y/N
set "RESP="
set /p RESP="   > "
if /i "%RESP%"=="Y" goto :rotar
if /i "%RESP%"=="S" goto :rotar
echo.
echo   Listo. La contrasena (y su QR) se mantienen igual.
echo.
pause
exit /b 0

:rotar
echo.
echo   Renovando contrasena y cortando todas las sesiones...
powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://127.0.0.1:8566/api/rotar-clave' -Method Post | Out-Null; 'servidor' } catch { 'offline' }" 2>nul > "%TEMP%\cp_rotar.txt"
set "MODO="
set /p MODO=<"%TEMP%\cp_rotar.txt"
if "%MODO%"=="servidor" (
  echo   [OK] El servidor en ejecucion genero la nueva clave.
) else (
  python servidor.py --rotar
  if errorlevel 1 (
    echo [X] No se pudo renovar.
    pause
    exit /b 1
  )
  echo   [OK] Clave renovada en config.json (el servidor estaba apagado).
)
echo.
echo   Presiona una tecla para ver la NUEVA contrasena con su QR...
pause >nul
goto :inicio
