@echo off
title Hotspot automatico de Control PC
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hotspot_auto.ps1"