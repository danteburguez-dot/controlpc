@echo off
title PROBAR SIN FIREWALL - Control PC
chcp 65001 >nul

net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================================
echo   DESACTIVANDO Firewall de Windows 3 perfiles 90 segundos
echo   PERO antes guardando el estado original...
echo ============================================================
netsh advfirewall show allprofiles state
netsh advfirewall set allprofiles state off

echo.
echo Desactivando el adaptador Radmin VPN (puede interceptar)...
netsh interface set interface "Radmin VPN" admin=disable

echo.
echo ============================================================
echo   AHORA: presiona "Conectar" en la APK del telefono
echo   (esperando 90 segundos)
echo ============================================================
timeout /t 90 /nobreak >nul

echo ==========================================================================
echo   REACTIVANDO Firewall + Radmin VPN... *(salvo que el telefono haya
echo   conectado, en ese caso lo seguimos asi)*
echo ==========================================================================
netsh advfirewall set allprofiles state on
netsh interface set interface "Radmin VPN" admin=enable

echo.
echo Prueba de 90 segundos completada. Firewall reactivado.ivado.
pause
