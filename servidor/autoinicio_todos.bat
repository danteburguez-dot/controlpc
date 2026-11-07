@echo off
title Control PC - Autoarranque completo
chcp 65001 >nul
REM Configura TODO para que arranque solo al encender la PC:
REM   1) Tarea programada del servidor ADMINISTRADOR (permite rechazar UAC desde el telefono)
REM   2) Atajo de respaldo (solo si el administrador no pudo arrancar)

cd /d "%~dp0"

net session >nul 2>&1
if errorlevel 1 (
  echo Necesito permisos de administrador para crear la tarea ^(acepta la ventana^)...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo [1/2] Creando tarea programada del servidor ADMINISTRADOR (.bat de admin)...
schtasks /Delete /TN "ControlPC Servidor Admin" /F >nul 2>&1
schtasks /Create /F /TN "ControlPC Servidor Admin" /SC ONLOGON /RL HIGHEST /TR "cmd /c start \"\" /min \"%~dp0iniciar_admin.bat\""
if errorlevel 1 (
  echo [!] No se pudo crear la tarea; quedara solo el respaldo normal.
) else (
  echo [OK] La PC arrancara con el servidor de administrador automaticamente.
)

echo [2/2] Atajo de respaldo (retardo 60 s; sale solo si ya corre el de admin)...
powershell -NoProfile -Command ^
 "$inicio=[Environment]::GetFolderPath('Startup');" ^
 "Remove-Item -LiteralPath (Join-Path $inicio 'Control PC - Servidor.lnk') -ErrorAction SilentlyContinue;" ^
 "$s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $inicio 'Control PC - respaldo.lnk'));" ^
 "$s.TargetPath='%ComSpec%';" ^
 "$s.Arguments='/c start \"\" /min \"%~dp0iniciar.bat\" --auto';" ^
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
