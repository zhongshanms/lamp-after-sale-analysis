param(
    [string]$SourceFile
)

$ErrorActionPreference = "Stop"

# 结束前等待（仅交互式控制台；重定向 stdin / -NonInteractive 调用时直接返回，避免抛错导致假失败）
function Wait-Exit {
    if ($env:SYNC_NO_PAUSE) { return }
    try {
        if (-not [Console]::IsInputRedirected) { Read-Host "按回车退出" }
    } catch { }
}

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
        Wait-Exit
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Host "[X] 文件不存在：$SourceFile"
    Wait-Exit
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
        Wait-Exit
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
        Wait-Exit
        exit 1
    }
}

# ── 查找 Git ──
$Git = @(
    "$env:USERPROFILE\.workbuddy\binaries\PortableGit\versions\*\mingw64\bin\git.exe",
    "$env:USERPROFILE\.workbuddy\binaries\PortableGit\versions\*\cmd\git.exe",
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
) | ForEach-Object {
    # 处理通配符（如 binaries\PortableGit\versions\*）
    if ($_ -like '*\*\*') {
        $glob = $_
        Get-ChildItem -Path $glob -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    } else {
        if (Test-Path $_) { $_ }
    }
} | Where-Object { $_ } | Select-Object -First 1

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
    Wait-Exit
    exit 1
}

Write-Host "[Git] $Git"

# 统一执行 git：git 的进度/提示走 stderr，PS5.1 在 EAP=Stop 且输出被重定向时会把它升级为终止性错误，
# 导致非交互/被管道调用时脚本中途假失败。这里临时放开 EAP，并保留 $LASTEXITCODE 供调用方判断。
function Git-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $saveEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { & "$script:Git" @GitArgs 2>&1 | ForEach-Object { "$_" } }
    finally { $ErrorActionPreference = $saveEAP }
}

Git-Run --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Git 无法运行"
    Wait-Exit
    exit 1
}
Write-Host ""

# ── 克隆或更新仓库缓存 ──
if (Test-Path (Join-Path $CACHE ".git")) {
    Write-Host "[1/4] 更新本地仓库缓存..."
    Set-Location -LiteralPath $CACHE
    Remove-Item -Path ".git\index.lock" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path ".git\refs\heads\$BRANCH.lock" -Force -ErrorAction SilentlyContinue
    # 补全老浅克隆（宝塔 force push 拒绝浅仓）
    if (Test-Path ".git\shallow") { Git-Run fetch --unshallow | Out-Null }
    Git-Run pull origin $BRANCH
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [警告] 拉取失败，尝试重置..."
        Git-Run fetch origin $BRANCH
        Git-Run reset --hard "origin/$BRANCH"
    }
    Write-Host "  [OK] 缓存已就绪"
} else {
    Write-Host "[1/4] 首次使用，克隆仓库（约10秒）..."
    if (Test-Path $CACHE) { Remove-Item -Path $CACHE -Recurse -Force }
    Git-Run clone $REPO $CACHE
    if ($LASTEXITCODE -ne 0) {        Write-Host "[X] 克隆失败！请确认 SSH 已配置、网络可达 GitHub"
        Wait-Exit
        exit 1
    }
    Write-Host "  [OK] 克隆完成"
}

# ── 复制 JSON + version.json ──
Write-Host ""
Write-Host "[2/4] 复制数据文件..."
Set-Location -LiteralPath $CACHE
$Dest = Join-Path $CACHE "data\after-sale-data-compact.json"
Copy-Item -Path $SourceFile -Destination $Dest -Force
Write-Host "  [OK]"

# version.json：优先取源 JSON 同目录（拖入场景），否则回退项目 data 目录
$VersionSrc = Join-Path (Split-Path -Parent $SourceFile) "version.json"
if (-not (Test-Path -LiteralPath $VersionSrc)) {
    $VersionSrc = Join-Path $WORKDIR "data\version.json"
}
$HasVersion = Test-Path -LiteralPath $VersionSrc
if ($HasVersion) {
    Copy-Item -Path $VersionSrc -Destination (Join-Path $CACHE "data\version.json") -Force
    Write-Host "  [OK] version.json ($VersionSrc)"
} else {
    Write-Host "  [警告] 未找到 version.json，跳过（前端版本提示可能滞后）"
}

# ── 提交 ──
Write-Host ""
Write-Host "[3/4] 提交..."
& "$Git" config user.email "zhongshanms@github.com"
& "$Git" config user.name "数据同步"
& "$Git" add data/after-sale-data-compact.json
if ($HasVersion) { & "$Git" add data/version.json }
Git-Run commit -m "data sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  (内容未变化，跳过提交)"
} else {
    Write-Host "  [OK] 已提交"
}

# ── 推送（双远程：GitHub + 宝塔） ──
$ServerRemote = "server"
$ServerUrl = "root@119.29.107.118:/www/git/lamp.git"
$MaxRetries = 3

function Push-WithRetry {
    param($gitPath, [string]$remoteName = 'origin', [Switch]$Force)
    for ($i = 1; $i -le $MaxRetries; $i++) {
        if ($i -gt 1) { Write-Host "  [重试] $i/$MaxRetries，5秒后..." ; Start-Sleep 5 }
        $saveEAP = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        if ($Force) {
            $pushOutput = & $gitPath push --force $remoteName $BRANCH 2>&1 | Out-String
        } else {
            $pushOutput = & $gitPath push $remoteName $BRANCH 2>&1 | Out-String
        }
        $ErrorActionPreference = $saveEAP
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Host "  [WARN] git push 失败 (第$i/$MaxRetries 次):"
        $pushOutput.Trim() -split "`n" | Where-Object { $_ } | ForEach-Object { Write-Host "    $_" }
    }
    return $false
}

function Push-ToRemote {
    param($gitPath, [string]$remoteName, [string]$label, [string]$successUrl, [Switch]$Force)
    Write-Host "  推送 $label ..."
    $ok = Push-WithRetry $gitPath $remoteName -Force:$Force
    if ($ok) {
        Write-Host "  [OK] $label 推送成功"
        if ($successUrl) { Write-Host "       $successUrl" }
    } else {
        Write-Host "  [FAIL] $label 推送失败（已重试 $MaxRetries 次）"
    }
    return $ok
}

Write-Host ""
Write-Host "[4/4] 推送数据..."

# 关键：清除 webroot/data 下的 .gz 预压缩文件，避免 nginx gzip_static 返回旧 gz 包
$webroot = Join-Path $CACHE ".."
if (Test-Path "$webroot\data") {
    $gzCount = (Get-ChildItem "$webroot\data\*.gz" -ErrorAction SilentlyContinue).Count
    if ($gzCount -gt 0) {
        Get-ChildItem "$webroot\data\*.gz" -ErrorAction SilentlyContinue | Remove-Item -Force
        Write-Host "  [清缓存] 删除 $gzCount 个 .gz 预压缩文件（避免 nginx 返回旧数据）"
    }
}

# 确保 server 远程已添加
$remotes = Git-Run remote
if ($remotes -notcontains $ServerRemote) {
    Git-Run remote add $ServerRemote $ServerUrl 2>$null
}

$results = @{}
$results['github'] = Push-ToRemote "$Git" 'origin' 'GitHub' 'https://zhongshanms.github.io/lamp-after-sale-analysis/'
$results['server'] = Push-ToRemote "$Git" $ServerRemote '宝塔服务器' 'https://lamp.zhongshanzhiliang.top/' -Force

Write-Host ""
Write-Host "============================================"
if ($results['github'] -and $results['server']) {
    Write-Host "  [SUCCESS] 双端推送完成"
} elseif ($results['github']) {
    Write-Host "  [PARTIAL] GitHub [OK] | 宝塔 [FAIL]"
} elseif ($results['server']) {
    Write-Host "  [PARTIAL] 宝塔 [OK] | GitHub [FAIL]"
} else {
    Write-Host "  [FAILED] 双端推送均失败"
}
Write-Host "============================================"
Write-Host ""
Wait-Exit
if ($results['github'] -and $results['server']) { exit 0 } else { exit 1 }
