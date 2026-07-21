@echo off
title Lamp After-Sale Data Sync - Drag JSON here

set "WORKDIR=C:\Users\DELL\WorkBuddy\独立站灯饰售后分析系统"
set "PS1=%WORKDIR%\sync.ps1"

if "%~1"=="" (
    echo Drag the exported JSON file onto this icon!
    echo Supports: .json
    pause
    exit /b 1
)

if not exist "%~1" (
    echo File not found: %~1
    pause
    exit /b 1
)

echo ============================================
echo   Lamp After-Sale Data Sync
echo ============================================
echo Source: %~1
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%~1"

echo.
pause
