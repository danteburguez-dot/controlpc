@echo off
title Auditoria de Firewall - Control PC
chcp 65001 >nul

net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo Activando auditoria de paquetes (90 segundos)...
auditpol /set /subcategory:"Filtering Platform Packet Drop" /success:enable /failure:enable >nul 2>&1

echo.
echo ==========================================================
echo   AHORA: presiona "Conectar" en la APK del telefono 2-3 veces
echo   (esperando 90 segundos)
echo ==========================================================
timeout /t 90 /nobreak >nul

echo Extrayendo eventos de firewall con el puerto 8566...
powershell -NoProfile -Command ^
 "try { Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5152,5156,5157; StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction Stop | Where-Object { $_.Message -match '8566' } | Select-Object -First 12 | ForEach-Object { $m=$_.Message -replace \"`r`n\",' | '; $m.Substring(0,[Math]::Min(220,$m.Length)) } | Out-File -FilePath 'C:\Users\Dante burguez\Downloads\Proyecto predeterminado\ControlPC\servidor\eventos_8566.txt' -Encoding UTF8; Write-Output 'OK' } catch { Write-Output $_.Exception.Message }"

echo.
echo Auditoria completada. Este archivo se cierra en 15 s...
timeout /t 15 /nobreak >nul
