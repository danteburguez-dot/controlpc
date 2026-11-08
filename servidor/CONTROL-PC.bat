@echo off
title CONTROL PC - MENU MAESTRO
chcp 65001 >nul

REM ---------------------------------------------------------------
REM Encuentra la carpeta del servidor automaticamente:
REM   1) si este .bat esta en la carpeta servidor, usa esa
REM   2) sino, usa la ruta fija de esta PC
REM ---------------------------------------------------------------
set "BASE=%~dp0"
if not exist "%BASE%servidor.py" set "BASE=C:\Users\Dante burguez\Downloads\Proyecto predeterminado\ControlPC\servidor\"
if not exist "%BASE%servidor.py" (
  echo [X] No encuentro la carpeta del servidor de Control PC.
  echo     Mueve este .bat a la carpeta servidor del proyecto.
  pause
  exit /b 1
)

REM soporte de modo directo por argumento (elevacion / autoarranque / secciones)
if "%~1"=="/firewall" goto :firewall_elevado
if "%~1"=="/admin" goto :admin_elevado
if "%~1"=="/auto" goto :auto_elevado
if "%~1"=="/auditoria" goto :auditia_elevado
if "%~1"=="--auto" goto :respaldo_auto

:menu
cls
echo ============================================================
echo              CONTROL PC - MENU MAESTRO
echo ============================================================
echo.
echo   [1] Abrir el servidor (normal)
echo   [2] Servidor como ADMINISTRADOR (permite rechazo UAC desde telefono)
echo   [3] Login: ver contrasena / renovarla (Y/N) - con QR
echo   [4] FIREWALL: permitir el telefono (si no conecta, corre ESTO)
echo   [5] Autoarranque completo (server al encender la PC)
echo   [6] Tailscale: acceso desde CUALQUIER lugar del mundo
echo   [7] Auditoria de paquetes (ve que bloquea al telefono)
echo   [8] HOTSPOT automatico (lleva el telefono a la red del PC, SIN ROUTER)
echo   [9] Instalar la ULTIMA version de Python (para una PC nueva)
echo   [0] Salir
echo.
set "OPC="
set /p OPC="   Elige una opcion (0-9): "
if "%OPC%"=="1" goto :iniciar
if "%OPC%"=="2" goto :admin
if "%OPC%"=="3" goto :login
if "%OPC%"=="4" goto :firewall
if "%OPC%"=="5" goto :auto
if "%OPC%"=="6" goto :tscale
if "%OPC%"=="7" goto :auditia
if "%OPC%"=="8" goto :hotsp
if "%OPC%"=="9" goto :pyinst
if "%OPC%"=="0" exit /b 0
goto :menu

:iniciar
cd /d "%BASE%"
echo.
echo =========================================
echo    CONTROL PC - iniciando servidor...
echo =========================================
echo.
where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado o no esta en el PATH.
  echo     Usa la opcion [9] de este menu para instalarlo automaticamente.
  pause
  goto :menu
)
echo [1/2] Comprobando librerias (la primera vez puede tardar un poco)...
python -c "import fastapi, uvicorn, mss, PIL, psutil, pyautogui, qrcode" 2>nul
if errorlevel 1 (
  echo       Instalando librerias...
  python -m pip install -r requisitos.txt --quiet --no-input
  if errorlevel 1 (
    echo [X] No se pudieron instalar las librerias. Verifica tu conexion y ejecuta:
    echo     python -m pip install -r requisitos.txt
    pause
    goto :menu
  )
)
echo [OK] Librerias listas.
echo [2/2] Abriendo servidor (cierra la ventana para detenerlo)...
:iniciar_loop
python servidor.py
if "%errorlevel%" EQU "3" (
  echo [OK] Ya hay otro servidor corriendo. Esta copia termina sin cambiar nada.
  pause
  goto :menu
)
echo.
echo El servidor se cerro inesperadamente. Reiniciando en 3 segundos...
timeout /t 3 /nobreak >nul
goto iniciar_loop

:respaldo_auto
echo Autoarranque pendiente 60 s ^(respaldo: si el servidor de admin nunca arranco)...
timeout /t 60 /nobreak >nul
goto :iniciar

:admin
net session >nul 2>&1
if errorlevel 1 (
  echo Pidiendo permisos de administrador ^(acepta la ventana de Windows^)...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/admin' -Verb RunAs"
  pause
  goto :menu
)
:admin_elevado
cd /d "%BASE%"
REM Regla de firewall de una vez (siendo administrador no vuelve a preguntar)
netsh advfirewall firewall show rule name="Control PC" >nul 2>&1
if errorlevel 1 netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566 >nul 2>&1
where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. Usa la opcion [9] de este menu.
  pause
  exit /b 1
)
python -c "import fastapi, uvicorn, mss, PIL, psutil, pyautogui, qrcode" 2>nul
if errorlevel 1 (
  echo [1/2] Instalando librerias (primera vez)...
  python -m pip install -r requisitos.txt --quiet --no-input
)
echo [2/2] Abriendo servidor como ADMINISTRADOR (cierra la ventana para detenerlo)...
:admin_loop
python servidor.py
set "EC=%errorlevel%"
if "%EC%" EQU "3" (
  echo [OK] Ya habia otro servidor corriendo. Este sale sin cambiar nada.
  pause
  exit /b 0
)
echo.
echo El servidor se cerro. Reiniciando en 3 segundos...
timeout /t 3 /nobreak >nul
goto admin_loop

:login
where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. Usa la opcion [9] de este menu.
  pause
  goto :menu
)
cd /d "%BASE%"
:login_menu
cls
REM Muestra: contrasena actual + dias restantes + QR RAPIDO (entra sin escribir)
REM y QR NORMAL (pide la clave). Cambia con la clave porque la incluye.
python servidor.py --loginqr
echo.
echo   Quieres obtener una nueva contrasena? Y/N
set "RESP="
set /p RESP="   > "
if /i "%RESP%"=="Y" goto :login_rotar
if /i "%RESP%"=="S" goto :login_rotar
echo.
echo   Listo. La contrasena (y su QR) se mantienen igual.
pause
goto :menu

:login_rotar
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
    goto :menu
  )
  echo   [OK] Clave renovada en config.json (el servidor estaba apagado).
)
echo.
echo   Presiona una tecla para ver la NUEVA contrasena con su QR...
pause >nul
goto :login_menu

:firewall
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/firewall'"
  exit /b
)
:firewall_elevado
echo Agregando la regla del Firewall para el telefono (puerto 8566 + python.exe)...
netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566
REM regla por PROGRAMA: siempre permite al python.exe recibir conexiones
set "PYEXE="
for /f "delims=" %%p in ('where python 2^>nul') do if not defined PYEXE set "PYEXE=%%p"
if not "%PYEXE%"=="" netsh advfirewall firewall add rule name="Control PC - python allow" dir=in action=allow program="%PYEXE%" protocol=TCP enable=yes profile=any >nul 2>&1
echo.
netsh advfirewall firewall show rule name="Control PC" | findstr /i "8566"
echo.
echo ==================================================
echo   REGLA CREADA. El telefono ya puede conectar.
echo ==================================================
pause
goto :menu

:auto
net session >nul 2>&1
if errorlevel 1 (
  echo Necesito permisos de administrador para crear la tarea ^(acepta la ventana^)...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/auto' -Verb RunAs"
  pause
  goto :menu
)
:auto_elevado
echo [1/2] Creando tarea programada del servidor ADMINISTRADOR (este mismo menu)...
schtasks /Delete /TN "ControlPC Servidor Admin" /F >nul 2>&1
schtasks /Create /F /TN "ControlPC Servidor Admin" /SC ONLOGON /RL HIGHEST /TR "cmd /c start \"\" /min \"%~f0\" /admin"
if errorlevel 1 (
  echo [!] No se pudo crear la tarea; quedara solo el respaldo normal.
) else (
  echo [OK] La PC arrancara con el servidor de administrador automaticamente.
)
echo [2/2] Atajo de respaldo (retardo 60 s; sale solo si ya corre el de admin)...
powershell -NoProfile -Command ^
 "$inicio=[Environment]::GetFolderPath('Startup');" ^
 "Remove-Item -LiteralPath (Join-Path $inicio 'Control PC - Servidor.lnk') -ErrorAction SilentlyContinue;" ^
 "Remove-Item -LiteralPath (Join-Path $inicio 'Control PC - respaldo.lnk') -ErrorAction SilentlyContinue;" ^
 "$s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $inicio 'Control PC - respaldo.lnk'));" ^
 "$s.TargetPath='%ComSpec%';" ^
 "$s.Arguments='/c start \"\" /min \"%~f0\" --auto';" ^
 "$s.WorkingDirectory='%~dp0';" ^
 "$s.Description='Control PC (respaldo si el de admin no arranco)';" ^
 "$s.WindowStyle=7;" ^
 "$s.Save()"
echo [OK] Todo configurado.
echo.
echo Para revertir:
echo   - tarea:      schtasks /Delete /TN "ControlPC Servidor Admin" /F
echo   - respaldo:   borra "Control PC - respaldo.lnk" en shell:startup
pause
goto :menu

:tscale
where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python no esta instalado. Usa la opcion [9] de este menu.
  pause
  goto :menu
)
cd /d "%BASE%"
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
      goto :menu
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
  echo [!] El inicio de sesion no se completo. Reintenta: opcion [6] de nuevo.
  pause
  goto :menu
)
echo [3/3] Abriendo la pantalla con IP y QR para conectar desde cualquier lugar:
python servidor.py --tailscale
echo.
echo PASOS FINALES:
echo   1) En el telefono: instala la app Tailscale e inicia sesion con la MISMA cuenta.
echo   2) En el telefono abre la APK Control PC y escribe la IP 100.x.y.z que ves arriba.
echo   3) Desde otro pais, cualquier red wifi o datos moviles: todo funcionara.
echo.
pause
goto :menu

:auditia
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/auditoria' -Verb RunAs"
  pause
  goto :menu
)
:auditia_elevado
cd /d "%BASE%"
echo Activando auditoria de paquetes (90 segundos)...
auditpol /set /subcategory:"Filtering Platform Packet Drop" /success:enable /failure:enable >nul 2>&1
echo.
echo ==========================================================
echo   AHORA: presiona "Conectar" en la APK del telefono 2-3 veces
echo   (esperando 90 segundos)
echo ==========================================================
timeout /t 90 /nobreak >nul
echo Extrayendo eventos de firewall con el puerto 8566...
powershell -NoProfile -Command "try { Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5152,5156,5157; StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction Stop | Where-Object { $_.Message -match '8566' } | Select-Object -First 12 | ForEach-Object { $m=$_.Message -replace \"`r`n\",' | '; $m.Substring(0,[Math]::Min(220,$m.Length)) } | Out-File -FilePath '%BASE%eventos_8566.txt' -Encoding UTF8; Write-Output 'OK' } catch { Write-Output $_.Exception.Message }"
echo.
echo Resultado guardado en: %BASE%eventos_8566.txt
echo.
pause
goto :menu

:hotsp
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%hotspot_auto.ps1"
pause
goto :menu

:pyinst
echo ============================================================
echo    DESCARGANDO LA ULTIMA VERSION DE PYTHON
echo ============================================================
echo.
where winget >nul 2>&1
if errorlevel 1 goto :py_sin_winget
echo [1/2] Instalando con winget (puede demorar unos minutos)...
winget install -e --id Python.Python.3 --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
goto :py_fin

:py_sin_winget
echo [1/2] winget no esta; descargando el instalador oficial...
powershell -NoProfile -Command "$f=[IO.Path]::Combine([IO.Path]::GetTempPath(),'python-setup.exe'); $v=(irm 'https://endoflife.date/api/python.json')[0].latest; Write-Host ('Version mas nueva: ' + $v); iwr -UseBasicParsing ('https://www.python.org/ftp/python/'+$v+'/python-'+$v+'-amd64.exe') -OutFile $f; & $f /quiet InstallAllUsers=0 PrependPath=1 Include_test=0"
echo [2/2] Instalacion silenciosa terminada.

:py_fin
echo.
echo ==================================================
echo   PYTHON INSTALADO. Reabre este menu (o abre
echo   una ventana de cmd nueva) para que quede
echo   en el PATH y el servidor pueda usarse.
echo ==================================================
pause
goto :menu
