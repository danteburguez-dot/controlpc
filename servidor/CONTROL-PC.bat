@echo off
title CONTROL PC - MENU MAESTRO
chcp 65001 >nul
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo              CONTROL PC - MENU MAESTRO
echo ============================================================
echo.
echo   [1] Abrir el servidor (normal)
echo   [2] Servidor como ADMINISTRADOR (permite [o] rechazar UAC desde telefono)
echo   [3] Login: ver contrasena / renovarla (Y/N) - con QR
echo   [4] FIREWALL: permitir el telefono (si no conecta, corre ESTO)
echo   [5] Autoarranque completo (server al encender la PC)
echo   [6] Tailscale: acceso desde CUALQUIER lugar del mundo
echo   [7] Auditoria de paquetes (ve que bloquea al telefono)
echo   [0] Salir
echo.
set "OPC="
set /p OPC="   Elige una opcion (0-7): "
if "%OPC%"=="1" goto :iniciar
if "%OPC%"=="2" goto :admin
if "%OPC%"=="3" goto :login
if "%OPC%"=="4" goto :firewall
if "%OPC%"=="5" goto :auto
if "%OPC%"=="6" goto :tscale
if "%OPC%"=="7" goto :auditia
if "%OPC%"=="0" exit /b 0
goto :menu

:iniciar
call "%~dp0iniciar.bat"
goto :menu

:admin
call "%~dp0iniciar_admin.bat"
goto :menu

:login
call "%~dp0login.bat"
goto :menu

:firewall
if exist "%~dp0 1-permitir_telefono.bat" call "%~dp01-permitir_telefono.bat"
if not exist "%~dp01-permitir_telefono.bat" (
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Dante burguez\Downloads\Proyecto predeterminado\ControlPC\servidor\regla_firewall.ps1'"
  echo [OK] regla aplicada si aceptaste el permiso.
  timeout /t 3 >nul
)
goto :menu

:auto
call "%~dp0autoinicio_todos.bat"
goto :menu

:tscale
call "%~dp0activar_tailscale.bat"
goto :menu

:auditia
if exist "%~dp02-auditoria.bat" call "%~dp02-auditoria.bat"
if not exist "%~dp02-auditoria.bat" (
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Dante burguez\Downloads\Proyecto predeterminado\ControlPC\servidor\regla_firewall.ps1'"
)
goto :menu
