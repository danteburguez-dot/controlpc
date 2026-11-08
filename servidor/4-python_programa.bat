@echo off
title Permiso permanente para python.exe (Control PC)
setlocal enabledelayedexpansion

net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

REM encuentra la ruta EXACTA de python.exe
set "PYEXE="
for /f "delims=" %%p in ('where python 2^>nul') do (
  set "PYEXE=%%p"
)

if "%PYEXE%"=="" (
  echo [X] python no esta en el PATH
  pause
  exit /b 1
)

echo Ruta de python: %PYEXE%
netsh advfirewall firewall add rule name="Control PC - python allow" dir=in action=allow program="%PYEXE%" protocol=TCP enable=yes profile=any
echo.
netsh advfirewall firewall show rule name="Control PC - python allow" verbose | findstr /i "python"
echo.
echo ===============================================
echo   REGLA DE PROGRAMA AGREGADA.
echo   Ahora el firewall SIEMPRE va a permitir que
echo   el python.exe de Control PC reciba
echo   conexiones del telefono (toda red).
echo ===============================================
echo.
pause
