@echo off
chcp 65001 >nul
REM Crea un acceso directo en el inicio de Windows para que el servidor
REM arranque solo cada vez que enciendas o reinicies la PC.

set "DESTINO=%~dp0"
set "NOMBRE=Control PC - Servidor.lnk"

powershell -NoProfile -Command ^
 "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\%NOMBRE%');" ^
 "$s.TargetPath='%DESTINO%iniciar.bat';" ^
 "$s.WorkingDirectory='%DESTINO%';" ^
 "$s.Description='Servidor de Control PC (se ejecuta en segundo plano)';" ^
 "$s.WindowStyle=7;" ^
 "$s.Save()"

if errorlevel 1 (
  echo [X] No se pudo crear el acceso directo.
  pause
  exit /b 1
)
echo [OK] Listo: el servidor arrancara automaticamente al encender la PC
echo      (se quedara minimizado en la barra de tareas).
echo      Para revertirlo, borra el acceso directo "Control PC - Servidor"
echo      en la carpeta shell:startup  (Win+R y escribe shell:startup)
pause
