@echo off
title Login de Control PC
chcp 65001 >nul
cd /d "%~dp0"
cls
echo ====================================================
echo              LOGIN de Control PC
echo ====================================================
echo.

REM Lee la contraseña actual desde config.json
set "CLAVE="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "(Get-Content 'config.json' -Encoding UTF8 | ConvertFrom-Json).contrasena" 2^>nul`) do set "CLAVE=%%p"
if "%CLAVE%"=="" (
  echo [X] No se encontro config.json. Ejecuta este bat dentro de la carpeta servidor.
  pause
  exit /b 1
)

REM Dias restantes del ciclo de 90 dias
set "DIAS="
for /f "usebackq delims=" %%d in (`powershell -NoProfile -Command "$c=(Get-Content 'config.json' -Encoding UTF8 | ConvertFrom-Json).creada; [int](90 - ((New-TimeSpan ([DateTime]::new(1970,1,1,0,0,0,[DateTimeKind]::Utc).AddSeconds($c)) (Get-Date)).TotalDays))" 2^>nul`) do set "DIAS=%%d"

echo   Contraseña actual:  %CLAVE%
if not "%DIAS%"=="" echo   Ciclo de sesiones:   %DIAS% dias restantes
echo   (escrabela en el telefono para conectar)
echo.
echo ----------------------------------------------------
echo.
echo   Quiere obtener una nueva contraseña? Y/N
set "RESP="
set /p RESP="   > "
if /i "%RESP%"=="Y" goto :rotar
if /i "%RESP%"=="S" goto :rotar
echo.
echo   Listo. La contraseña se mantiene: %CLAVE%
echo.
pause
exit /b 0

:rotar
REM Si el servidor esta corriendo, le pide rotar la clave por HTTP (local)
powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://127.0.0.1:8566/api/rotar-clave' -Method Post | Out-Null; 'servidor' } catch { 'offline' }" 2>nul > "%TEMP%\cp_rotar.txt"
set "MODO="
set /p MODO=<"%TEMP%\cp_rotar.txt"
if "%MODO%"=="servidor" (
  echo   Renovando clave en el servidor en ejecucion...
) else (
  echo   El servidor no esta corriendo: renovando en el archivo...
  python -c "import servidor, time; servidor._rotar_contrasena_si_corresponde(ventana=True, forzar=True)" 2>nul
)

REM Relea la nueva contraseña para mostrarla
set "CLAVE=%CLAVE%"
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "(Get-Content 'config.json' -Encoding UTF8 | ConvertFrom-Json).contrasena" 2^>nul`) do set "CLAVE=%%p"
echo.
echo ====================================================
echo    ¡CONTRASEÑA RENOVADA!
echo.
echo    Nueva contraseña:  %CLAVE%
echo.
echo    Todas las sesiones fueron cortadas:
echo    los telefonos deben escribir esta clave
echo    nueva para volver a conectar.
echo ====================================================
echo.
pause
