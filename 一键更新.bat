@echo off
title Lamp Analysis - One-Click Update
chcp 65001 >nul

set "PYTHON=C:\Users\DELL\.workbuddy\binaries\python\versions\3.13.12\python.exe"
set "CONVERT=%~dp0convert_lamp_to_compact.py"
set "SYNC=%~dp0sync.ps1"

echo ============================================
echo   Lamp After-Sale - One-Click Update
echo ============================================
echo.

set "ARG=%~1"
if "%ARG%"=="" goto NO_ARG

if /i "%ARG:~-5%"==".json" goto IS_JSON
if /i "%ARG:~-5%"==".xlsx" goto IS_XLSX

echo [ERR] Unsupported file type, only .xlsx or .json supported
goto END

:NO_ARG
echo [1/2] Auto-detect Excel files from desktop...
set "ARG="
goto RUN_CONVERT

:IS_JSON
echo [1/2] JSON detected, skip convert, go to sync
goto RUN_SYNC

:IS_XLSX
echo [1/2] Excel detected, converting...
echo       File: %ARG%

:RUN_CONVERT
if not exist "%PYTHON%" goto ERR_PYTHON
if "%ARG%"=="" goto DO_CONVERT_AUTO
"%PYTHON%" "%CONVERT%" "%ARG%"
goto CHECK_CONVERT

:DO_CONVERT_AUTO
"%PYTHON%" "%CONVERT%"

:CHECK_CONVERT
if errorlevel 1 goto ERR_CONVERT
echo.
echo [2/2] Pushing to GitHub...
echo.

:RUN_SYNC
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC%"
if errorlevel 1 goto ERR_SYNC

echo.
echo ============================================
echo   Done! Wait 1-2 min for all devices to refresh
echo   https://zhongshanms.github.io/lamp-after-sale-analysis/
echo ============================================
goto END

:ERR_PYTHON
echo [ERR] Python not found: %PYTHON%
goto END

:ERR_CONVERT
echo [ERR] Convert failed!
goto END

:ERR_SYNC
echo [ERR] Sync failed!
goto END

:END
echo.
pause
