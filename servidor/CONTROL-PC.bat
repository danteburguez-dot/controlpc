@echo off
title CONTROL PC - MENU MAESTRO
chcp 65001 >nul
REM bitacora de diagnostico (sobrevive cierres de consola)
set "PLOG=%TEMP%\maestro_debug.txt"
if "%~1"=="" del "%PLOG%" >nul 2>&1
echo [%DATE% %TIME%] arranque del maestro >> "%PLOG%"

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
echo   [9] INSTALAR TODO: Python + las 12 librerias (PC nueva lista en un clic)
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
if "%OPC%"=="9" goto :instalar_todo
if "%OPC%"=="0" exit /b 0
goto :menu

:iniciar
cd /d "%BASE%"
echo.
echo =========================================
echo    CONTROL PC - iniciando servidor...
echo =========================================
echo.
echo [1/3] Buscando un Python con las librerias de Control PC...
echo [%TIME%] [1] probar pythons... >> "%PLOG%"
call :elige_python
echo [%TIME%] [1] elige listo: PYOK=%PYOK% PYMODE=%PYMODE% >> "%PLOG%"
if "%PYOK%"=="none" (
  echo [X] No hay un Python con las librerias de Control PC en esta PC.
  echo     Corre la opcion [9] INSTALAR TODO y vuelve a intentarlo.
  pause
  goto :menu
)
echo [2/3] Python elegido (modo: %PYOK% %PYMODE%).
echo [3/3] Abriendo el servidor en SU PROPIA ventana...
echo [%TIME%] [1] abriendo ventana del servidor >> "%PLOG%"
if "%PYOK%"=="plain" (
  start "CONTROL PC - Servidor" cmd /k python servidor.py
) else if "%PYMODE%"=="py" (
  start "CONTROL PC - Servidor" cmd /k "%PYEXE8% -3.12 servidor.py"
) else (
  start "CONTROL PC - Servidor" cmd /k "%PYEXE8% servidor.py"
)
echo.
echo El servidor corre en SU PROPIA ventana (alli ves la IP, la clave y los QR).
echo Esa ventana NO se cierra sola: si el servidor falla, veras el error dentro.
echo (Para detener el servidor, cierra esa ventana del servidor.)
pause
goto :menu

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
call :elige_python
if "%PYOK%"=="none" (
  echo [X] No hay un Python con las librerias de Control PC.
  echo     Corre la opcion [9] INSTALAR TODO primero.
  pause
  exit /b 1
)
echo [OK] Python listo (modo: %PYOK% %PYMODE%).
echo Abriendo servidor ELEVADO en una ventana aparte...
if "%PYOK%"=="plain" (
  start "CONTROL PC - Servidor (admin)" cmd /k python servidor.py
) else if "%PYMODE%"=="py" (
  start "CONTROL PC - Servidor (admin)" cmd /k "%PYEXE8% -3.12 servidor.py"
) else (
  start "CONTROL PC - Servidor (admin)" cmd /k "%PYEXE8% servidor.py"
)
echo Ventana del servidor ADMIN abierta (puede rechazar UAC desde el telefono).
pause
goto :menu

:login
cd /d "%BASE%"
call :elige_python
if "%PYOK%"=="none" (
  echo [X] No hay un Python con las librerias. Corre la opcion [9] INSTALAR TODO.
  pause
  goto :menu
)
:login_menu
cls
REM Muestra: contrasena actual + dias restantes + QR RAPIDO (entra sin escribir)
REM y QR NORMAL (pide la clave). Cambia con la clave porque la incluye.
call :pyrun servidor.py --loginqr
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
  call :pyrun servidor.py --rotar
  if errorlevel 1 (
    echo [X] No se pudo renovar.
    pause
    goto :menu
  )
  echo   [OK] Clave renovada en config.json - el servidor estaba apagado.
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
set "PYEXE_F="
where python > "%TEMP%\cp_py.txt" 2>nul
for /f "delims=" %%p in (%TEMP%\cp_py.txt) do if not defined PYEXE_F set "PYEXE_F=%%p"
if not "%PYEXE_F%"=="" netsh advfirewall firewall add rule name="Control PC - python allow" dir=in action=allow program="%PYEXE_F%" protocol=TCP enable=yes profile=any >nul 2>&1
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
cd /d "%BASE%"
call :elige_python
if "%PYOK%"=="none" (
  echo [X] No hay un Python con las librerias. Corre la opcion [9] INSTALAR TODO.
  pause
  goto :menu
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
call :pyrun servidor.py --tailscale
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

:instalar_todo
cd /d "%BASE%"
echo ============================================================
echo    INSTALAR TODAS LAS DEPENDENCIAS DE CONTROL PC
echo    (Python 3.12 estable + las 12 librerias ya compiladas)
echo ============================================================
echo.
echo [1/3] Poniendo un Python compatible...
echo [%TIME%] [9] iniciar instalacion >> "%PLOG%"
call :elige_python
if "%PYOK%"=="custom" goto dep_prueba_full
if "%PYOK%"=="plain" goto dep_prueba_full
echo       No hay ninguno util; instalando Python 3.12 (tiene TODOS los compilados)...
where winget >nul 2>nul
if errorlevel 1 goto dep_py_api
winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
goto dep_py_dete

:dep_py_api
echo [i] winget no esta; descargando el instalador oficial de Python 3.12...
powershell -NoProfile -Command "$f=[IO.Path]::Combine([IO.Path]::GetTempPath(),'python-312.exe'); iwr -UseBasicParsing 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $f; & $f /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0"

:dep_py_dete
REM refresca la ruta del launcher de ESTA ventana
echo [%TIME%] [9] instalado; redetectando python... >> "%PLOG%"
set "PATH=%PATH%;%LOCALAPPDATA%\Programs\Python\Launcher;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%LOCALAPPDATA%\Programs\Python\Python312"
call :elige_python
if "%PYOK%"=="none" goto dep_libs_instalar
echo [OK] Ya hay un Python con todo: comprobando librerias...
goto dep_prueba_full

:dep_libs_instalar
echo [2/3] Instalando las 12 librerias del servidor (demora unos minutos)...
set "PYINS="
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PYINS=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PYINS if exist "%ProgramFiles%\Python312\python.exe" set "PYINS=%ProgramFiles%\Python312\python.exe"
if not defined PYINS for /d %%d in ("%LOCALAPPDATA%\Python\pythoncore-3.12-*") do if not defined PYINS set "PYINS=%%d\python.exe"
if not defined PYINS set "PYINS=python"
echo      usando: %PYINS%
"%PYINS%" -m pip install --upgrade pip --quiet --no-input
"%PYINS%" -m pip install -r "%BASE%requisitos.txt" --no-input
if not errorlevel 1 goto dep_prueba_full
echo.
echo [i] Reintentando solo con paquetes YA compilados (sin herramientas C++)...
"%PYINS%" -m pip install -r "%BASE%requisitos.txt" --no-input --only-binary=:all:
if not errorlevel 1 goto dep_prueba_full
echo.
echo [X] pip no pudo: a esa version de Python le faltan compilaciones para Windows.
echo     Son gratis:
echo     https://visualstudio.microsoft.com/visual-cpp-build-tools/
echo     Instalalas y corre este [9] de nuevo.
pause
goto :menu

:dep_prueba_full
call :elige_python
if "%PYOK%"=="none" goto dep_diagnostico
echo [3/3] Comprobando cada una de las 12 y reparando lo que falla...
set "FALLOS="
for %%p in ("fastapi fastapi" "uvicorn uvicorn" "mss mss" "PIL Pillow" "psutil psutil" "pyautogui pyautogui" "qrcode qrcode" "numpy numpy" "soundcard soundcard" "pycaw pycaw" "comtypes comtypes" "win32api pywin32") do (
  for /f "tokens=1,2" %%a in (%%p) do call :dep_toca %%a %%b
)
if not defined FALLOS goto dep_todo_bien
echo.
echo [X] Estas librerias siguen rotas en esta PC:%FALLOS%
echo     Instala gratis las herramientas de C++ de Microsoft y vuelve a correr [9]:
echo     https://visualstudio.microsoft.com/visual-cpp-build-tools/
pause
goto :menu

:dep_diagnostico
echo.
echo [X] Ningun Python quedo usable en esta PC. Revisa la bitacora:
echo     %PLOG%
pause
goto :menu

:dep_todo_bien
echo.
echo ==================================================
echo   TODO LISTO (las 12 importan bien). Esta PC
echo   ya puede correr el servidor:
echo   opcion [1] (o [2] admin). Todas las opciones
echo   usan este mismo Python automaticamente.
echo ==================================================
pause
goto :menu

:dep_toca
REM %1 = nombre para "import X" | %2 = nombre del paquete en pip
call :pyrun -c "import %~1"
if not errorlevel 1 (
  echo   [OK] %~1
  goto :eof
)
echo   reparando %~2 ...
call :pyrun -m pip install --upgrade --only-binary=:all: %~2 >nul 2>&1
call :pyrun -c "import %~1"
if errorlevel 1 (
  call set "FALLOS=%%FALLOS%% %~1"
  echo   [X] %~1 sigue roto
  goto :eof
)
echo   [OK] %~1 (reparada)
goto :eof

:elige_python
REM PYOK lo resuelve elige_python.py (cero parsing batch: lee archivos planos):
REM   PYOK=custom -> PYEXE (PYMODE "py"=launcher 3.12 | "direct"=exe) que SI tiene las 12
REM   PYOK=none   -> nada sirve (correr [9])
set "PYOK=none"
set "PYEXE="
set "PYMODE="
set "PYEXE8="
if not exist "%BASE%elige_python.py" goto elige_fin
del "%TEMP%\cp_elige_ok.txt" "%TEMP%\cp_elige_mod.txt" "%TEMP%\cp_elige_exe.txt" >nul 2>&1
python "%BASE%elige_python.py" >nul 2>&1
set /p "LG1=" < "%TEMP%\cp_elige_ok.txt" 2>nul
echo [elige] finder dice: [%LG1%] >> "%PLOG%"
if not defined LG1 goto elige_intenta_launcher
if "%LG1%"=="CUSTOM" call :elige_leer
goto elige_fin

:elige_intenta_launcher
REM caso: no hay "python" en PATH pero si el launcher con el 3.12 ya preparado
if exist "%LOCALAPPDATA%\Programs\Python\Launcher\py.exe" (
  set "LG1="
  "%LOCALAPPDATA%\Programs\Python\Launcher\py.exe" -3.12 "%BASE%elige_python.py" >nul 2>nul
  set /p "LG1=" < "%TEMP%\cp_elige_ok.txt" 2>nul
)
echo [elige] segundo intento con launcher: [%LG1%] >> "%PLOG%"
if "%LG1%"=="CUSTOM" call :elige_leer
goto elige_fin

:elige_leer
set /p "PYMODE=" < "%TEMP%\cp_elige_mod.txt" 2>nul
set /p "PYEXE=" < "%TEMP%\cp_elige_exe.txt" 2>nul
if not defined PYEXE goto :eof
for %%q in ("%PYEXE%") do set "PYEXE8=%%~sq"
set "PYOK=custom"
goto :eof

:elige_fin
echo [elige] resultado: %PYOK% %PYMODE% %PYEXE% >> "%PLOG%"
goto :eof

:pyrun
REM ejecuta %* con el interprete elegido por :elige_python
if "%PYOK%"=="plain" goto pyrun_plain
if "%PYMODE%"=="py" ( "%PYEXE%" -3.12 %* ) else ( "%PYEXE%" %* )
goto :eof
:pyrun_plain
python %*
goto :eof
