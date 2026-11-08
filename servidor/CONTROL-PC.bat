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

REM soporte de modo directo por argumento (p.ej. elevacion de si mismo)
if "%~1"=="/firewall" goto :firewall_elevado

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
echo   [0] Salir
echo.
set "OPC="
set /p OPC="   Elige una opcion (0-8): "
if "%OPC%"=="1" goto :iniciar
if "%OPC%"=="2" goto :admin
if "%OPC%"=="3" goto :login
if "%OPC%"=="4" goto :firewall
if "%OPC%"=="5" goto :auto
if "%OPC%"=="6" goto :tscale
if "%OPC%"=="7" goto :auditia
if "%OPC%"=="8" goto :hotsp
if "%OPC%"=="0" exit /b 0
goto :menu

:iniciar
call "%BASE%iniciar.bat"
goto :menu

:admin
call "%BASE%iniciar_admin.bat"
goto :menu

:login
call "%BASE%login.bat"
goto :menu

:firewall
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/firewall'"
  exit /b
)
:firewall_elevado
echo Agregando la regla del Firewall para el telefono...
netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566
echo.
netsh advfirewall firewall show rule name="Control PC" | findstr /i "8566"
echo.
echo ==================================================
echo   REGLA CREADA. El telefono ya puede conectar.
echo ==================================================
pause
goto :menu

:auto
call "%BASE%autoinicio_todos.bat"
goto :menu

:tscale
call "%BASE%activar_tailscale.bat"
goto :menu

:auditia
call "%BASE%2-auditoria.bat"
pause
goto :menu

:hotsp
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%hotspot_auto.ps1"
pause
goto :menu
