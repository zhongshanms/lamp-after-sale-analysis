@echo off
chcp 65001 >nul
title 数据同步 - 独立站灯饰售后分析系统
cd /d "%~dp0"
echo ============================================
echo   正在同步最新数据...
echo ============================================
echo.
echo 正在从 GitHub 下载最新数据文件...
echo.

cd /d "%~dp0data"

echo [1/2] 下载 after-sale-data-compact.json ...
curl -s -L -o "after-sale-data-compact.json" "https://raw.githubusercontent.com/zhongshanms/lamp-after-sale-analysis/main/data/after-sale-data-compact.json"
if %ERRORLEVEL% EQU 0 (
    echo    ✓ 下载成功
) else (
    echo    ✗ 下载失败，请检查网络
    pause
    exit /b 1
)

echo [2/2] 下载 version.json ...
curl -s -L -o "version.json" "https://raw.githubusercontent.com/zhongshanms/lamp-after-sale-analysis/main/data/version.json"
if %ERRORLEVEL% EQU 0 (
    echo    ✓ 下载成功
) else (
    echo    ✗ 下载失败
)

echo.
echo ============================================
echo   同步完成！
echo.
echo 如果同步后页面不更新，请按 Ctrl+F5 硬刷新
echo ============================================
echo.
pause
