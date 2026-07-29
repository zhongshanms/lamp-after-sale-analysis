param(
    [string]$SourceFile
)

$ErrorActionPreference = "Stop"

# 工作目录：脚本所在目录
$WORKDIR = $PSScriptRoot
$REPO    = "git@github.com:zhongshanms/lamp-after-sale-analysis.git"
$CACHE   = Join-Path $WORKDIR ".sync_cache"
$BRANCH  = "main"

Write-Host "============================================"
Write-Host "  数据上传 - 独立站灯饰售后分析系统"
Write-Host "============================================"
Write-Host ""

# ── 自动定位 JSON（项目 data 目录 > 桌面 > 下载） ──
if (-not $SourceFile) {
    $ProjectData = Join-Path $PSScriptRoot "data\after-sale-data-compact.json"
    $DesktopJson = Join-Path $env:USERPROFILE "Desktop\after-sale-data-compact.json"
    $DownloadsJson = Join-Path $env:USERPROFILE "Downloads\after-sale-data-compact.json"
    if (Test-Path -LiteralPath $ProjectData) {
        $SourceFile = $ProjectData
        Write-Host "[提示] 自动定位项目 data 目录文件"
    } elseif (Test-Path -LiteralPath $DesktopJson) {
        $SourceFile = $DesktopJson
        Write-Host "[提示] 自动定位桌面文件"
    } elseif (Test-Path -LiteralPath $DownloadsJson) {
        $SourceFile = $DownloadsJson
        Write-Host "[提示] 自动定位下载目录文件"
    } else {
        Write-Host "用法：把 after-sale-data-compact.json 拖到 上传数据.bat 上"
        Write-Host "      或直接双击运行（脚本会自动查找项目/桌面/下载目录的文件）"
        Write-Host ""
        Read-Host "按回车退出"
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Host "[X] 文件不存在：$SourceFile"
    Read-Host "按回车退出"
    exit 1
}

# ── 加密检测与自动解密 ──
$IsEncrypted = $false
try {
    $FirstLine = Get-Content -LiteralPath $SourceFile -TotalCount 1 -ErrorAction Stop
    if ($FirstLine -notmatch '^\s*[\{\[]') { $IsEncrypted = $true }
} catch {
    $IsEncrypted = $true
}

if ($IsEncrypted) {
    Write-Host "[检测] 文件被绿盾加密，尝试自动解密..."
    $PythonExe = "$env:USERPROFILE\.workbuddy\binaries\python\versions\3.13.12\python.exe"
    $DecScript = Join-Path $WORKDIR "decrypt_json.py"
    $DecOut = [System.IO.Path]::GetTempFileName() + ".json"

    if (-not (Test-Path $DecScript)) {
        Write-Host "[X] 解密脚本不存在: $DecScript"
        Read-Host "按回车退出"
        exit 1
    }

    $DecResult = & "$PythonExe" "$DecScript" "$SourceFile" "$DecOut" 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path $DecOut)) {
        Write-Host "[解密] 自动解密成功"
        $SourceFile = $DecOut
    } else {
        Write-Host "[X] 自动解密失败"
        $DecResult | ForEach-Object { Write-Host "    $_" }
        Write-Host ""
        Write-Host "手动解决方法：用记事本/WPS 打开文件 → 另存为 → 重新运行"
        Read-Host "按回车退出"
        exit 1
    }
}

# ── 查找 Git ──
$Git = @(
    "$env:USERPROFILE\.workbuddy\vendor\PortableGit\mingw64\bin\git.exe",
    "$env:USERPROFILE\.workbuddy\vendor\PortableGit\cmd\git.exe",
    "$env:USERPROFILE\scoop\shims\git.exe",
    "$env:ProgramData\scoop\shims\git.exe",
    "C:\Program Files\Git\bin\git.exe",
    "C:\Program Files\Git\cmd\git.exe",
    "C:\Program Files (x86)\Git\bin\git.exe",
    "C:\Program Files (x86)\Git\cmd\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $Git) {
    $GitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($GitCmd) { $Git = $GitCmd.Source }
}

if (-not $Git) {
    $regPaths = @(
        "HKLM:\SOFTWARE\GitForWindows",
        "HKLM:\SOFTWARE\Wow6432Node\GitForWindows",
        "HKCU:\SOFTWARE\GitForWindows"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            try {
                $installPath = (Get-ItemProperty $rp -Name InstallPath -ErrorAction SilentlyContinue).InstallPath
                if ($installPath) {
                    $candidate = Join-Path $installPath "bin\git.exe"
                    if (Test-Path $candidate) { $Git = $candidate; break }
                    $candidate = Join-Path $installPath "cmd\git.exe"
                    if (Test-Path $candidate) { $Git = $candidate; break }
                }
            } catch { }
        }
    }
}

if (-not $Git) {
    Write-Host "[X] 未找到 Git，请安装 Git for Windows"
    Write-Host "    下载地址：https://git-scm.com/download/win"
    Read-Host "按回车退出"
    exit 1
}

Write-Host "[Git] $Git"
& "$Git" --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Git 无法运行"
    Read-Host "按回车退出"
    exit 1
}
Write-Host ""

# ── 克隆或更新仓库缓存 ──
if (Test-Path (Join-Path $CACHE ".git")) {
    Write-Host "[1/4] 更新本地仓库缓存..."
    Set-Location -LiteralPath $CACHE
    Remove-Item -Path ".git\index.lock" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path ".git\refs\heads\$BRANCH.lock" -Force -ErrorAction SilentlyContinue
    & "$Git" pull origin $BRANCH
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [警告] 拉取失败，尝试重置..."
        & "$Git" fetch origin $BRANCH
        & "$Git" reset --hard "origin/$BRANCH"
    }
    Write-Host "  [OK] 缓存已就绪"
} else {
    Write-Host "[1/4] 首次使用，克隆仓库（约10秒）..."
    if (Test-Path $CACHE) { Remove-Item -Path $CACHE -Recurse -Force }
    & "$Git" clone --depth 1 $REPO $CACHE
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] 克隆失败！请确认 SSH 已配置、网络可达 GitHub"
        Read-Host "按回车退出"
        exit 1
    }
    Write-Host "  [OK] 克隆完成"
}

# ── 复制 JSON ──
Write-Host ""
Write-Host "[2/4] 复制数据文件..."
Set-Location -LiteralPath $CACHE
$Dest = Join-Path $CACHE "data\after-sale-data-compact.json"
Copy-Item -Path $SourceFile -Destination $Dest -Force
Write-Host "  [OK]"

# ── 提交 ──
Write-Host ""
Write-Host "[3/4] 提交..."
& "$Git" config user.email "zhongshanms@github.com"
& "$Git" config user.name "数据同步"
& "$Git" add data/after-sale-data-compact.json
& "$Git" commit -m "data sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  (内容未变化，跳过提交)"
} else {
    Write-Host "  [OK] 已提交"
}

# ── 推送 ──
$BT_HOST = "119.29.107.118"
$BT_PORT = "53844"
$BT_USER = "root"
$BT_KEY  = "$env:USERPROFILE\.ssh\lamp_baota_rsa"
$BT_PATH = "/www/wwwroot/lamp.zhongshanzhiliang.top"

function Push-ToRemote {
    param([string]$Remote, [string]$Label)
    Write-Host ""
    Write-Host "[4/4] 推送到 $Label ..."
    $attempt = 0; $maxTries = 3
    while ($attempt -lt $maxTries) {
        $attempt++
        & "$Git" push $Remote $BRANCH 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $Label 推送成功"
            return $true
        }
        if ($attempt -lt $maxTries) {
            Write-Host "  [重试 $attempt/$maxTries] $Label 推送失败，3秒后重试..."
            Start-Sleep 3
        }
    }
    Write-Host "  [FAIL] $Label 推送失败（已重试 $maxTries 次）"
    return $false
}

$githubOk = Push-ToRemote origin "GitHub"

# ── 宝塔服务器同步 ──
$btOk = $false
if (Test-Path $BT_KEY) {
    Write-Host ""
    Write-Host "[5/5] 同步宝塔服务器..."
    $sshCmd  = "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i `"$BT_KEY`" -p $BT_PORT `"$BT_USER@$BT_HOST`""
    $gitCmd  = "cd $BT_PATH && git fetch origin $BRANCH && git reset --hard FETCH_HEAD"
    $fullCmd = "$sshCmd `"$gitCmd`""
    
    $attempt = 0; $maxBT = 3
    while ($attempt -lt $maxBT) {
        $attempt++
        try {
            $result = Invoke-Expression $fullCmd 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] 宝塔服务器同步成功"
                Write-Host "  https://lamp.zhongshanzhiliang.top/"
                $btOk = $true
                break
            }
        } catch { }
        if ($attempt -lt $maxBT) {
            Write-Host "  [重试 $attempt/$maxBT] SSH 连接失败，5秒后重试..."
            Start-Sleep 5
        }
    }
    if (-not $btOk) {
        Write-Host "  [FAIL] 宝塔服务器同步失败（已重试 $maxBT 次）"
        if ($result) { Write-Host "  详情: $result" }
    }
} else {
    Write-Host ""
    Write-Host "[5/5] 跳过宝塔同步（SSH 密钥未找到: $BT_KEY）"
}

Write-Host ""
Write-Host "============================================"
if ($githubOk -and $btOk) {
    Write-Host "  同步完成 [SUCCESS]"
} elseif ($githubOk -or $btOk) {
    Write-Host "  同步完成 [PARTIAL]"
    if ($githubOk) { Write-Host "  GitHub: OK  |  宝塔: FAIL" }
    else           { Write-Host "  GitHub: FAIL  |  宝塔: OK" }
} else {
    Write-Host "  同步完成 [FAILED] — 所有远程推送失败"
}
Write-Host ""
Write-Host "  GitHub: https://zhongshanms.github.io/lamp-after-sale-analysis/"
if ($btOk) {
    Write-Host "  宝塔:   https://lamp.zhongshanzhiliang.top/"
}
Write-Host "============================================"
Write-Host ""
Read-Host "按回车退出"
