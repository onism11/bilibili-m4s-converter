@echo off
chcp 65001 >nul
title B站 M4S 转换器
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0m4s-converter.ps1" -Gui
if errorlevel 1 pause
