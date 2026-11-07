@echo off
title Firewall para Control PC (permite al telefono entrar)
chcp 65001 >nul

net session >nul 2>&1
if errorlevel 1 (
  echo Pidiendo permisos de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566
echo.
netsh advfirewall firewall show rule name="Control PC" | findstr /i "Control PC Nombre Name"
echo.
echo ===============================================
echo   REGLA CREADA.
echo   Ahora el telefono ya puede conectar a esta PC
echo   (abre la APK o la web y entra como siempre).
echo ===============================================
echo.
pause
