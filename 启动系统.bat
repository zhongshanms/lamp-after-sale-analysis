@echo off
chcp 65001 >nul
title 独立站灯饰售后工单分析系统
echo ============================================
echo   独立站灯饰售后工单分析系统 - 正在启动...
echo ============================================
echo.
cd /d "%~dp0"
echo.
start "" "%~dp0独立站灯饰售后分析系统.html"
echo 页面加载可能需要几秒钟（等待数据载入）...
echo.
echo 【使用提示】
echo - 预置数据已包含在 data/ 文件夹中（约9MB）
echo - 如果启动后提示「加载失败」，请检查 data/ 文件夹
echo - 如需上传新数据，请点击「登录」后操作
echo - 数据保存在浏览器本地，下次打开无需重复上传
echo.
echo 【GitHub Pages 在线版】
echo 如需联网使用最新数据，请访问：
echo https://zhongshanms.github.io/lamp-after-sale-analysis/
echo.
pause
