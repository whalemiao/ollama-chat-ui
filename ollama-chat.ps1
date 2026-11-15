try {
# Qwen3.5 2B 本地聊天启动器
#
# 为什么需要这个小服务：
#   浏览器直接打开 file:// 页面时，请求 Ollama 带的 Origin 是 "null"，
#   Ollama 会回 403（实测：Origin=null → 403，Origin=http://127.0.0.1:8765 → 200）。
#   所以这里起一个只有本机能访问的静态服务，页面走 http://127.0.0.1:8765，
#   Origin 就变成白名单里的地址，fetch 才通。
#
# 顺带解决的两件事：
#   - 中文输入：浏览器输入框走系统输入法，比 GBK 控制台可靠
#   - 思考模式：页面里默认 think=false，一句话 10-30 秒（否则要 2-3 分钟）

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HtmlPath = Join-Path $ToolsDir 'ollama-chat.html'
$Port     = 8765

if (-not (Test-Path $HtmlPath)) {
    Write-Host "找不到页面文件：$HtmlPath" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# ---- 找 Python（和 run-daily.ps1 同一套逻辑，别写死路径）----
function Find-Python {
    $cands = @()
    if ($env:BILI_PYTHON) { $cands += $env:BILI_PYTHON }
    $dsh = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes'
    if (Test-Path $dsh) {
        $cands += Get-ChildItem $dsh -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'dependencies\python\python.exe' }
    }
    $uv = Join-Path $env:APPDATA 'uv\python'
    if (Test-Path $uv) {
        $cands += Get-ChildItem $uv -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'python.exe' }
    }
    foreach ($n in @('py', 'python', 'python3')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $cands += $c.Source }
    }
    foreach ($c in $cands) {
        if (-not $c -or -not (Test-Path $c)) { continue }
        $v = & $c -c "import sys;print(sys.version_info[0])" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$v".Trim() -eq '3') { return $c }
    }
    return $null
}

$py = Find-Python
if (-not $py) {
    Write-Host "找不到可用的 Python 3" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# ---- 确保 Ollama 在跑（重启后它经常没自动启动，页面就会满屏 Failed to fetch）----
function Test-Ollama {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 3 -UseBasicParsing
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

if (-not (Test-Ollama)) {
    Write-Host "Ollama 没在跑，正在启动…" -ForegroundColor Yellow
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    if (Test-Path $exe) {
        Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 700
            if (Test-Ollama) { break }
        }
    }
    if (Test-Ollama) {
        Write-Host "Ollama 已启动" -ForegroundColor Green
    } else {
        Write-Host "Ollama 启动失败：请手动打开 Ollama 应用后再试" -ForegroundColor Red
        Read-Host "按回车退出"
        exit 1
    }
}

# ---- 端口被占就先看看是不是已经在跑 ----
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "端口 $Port 已被占用，直接打开页面" -ForegroundColor Yellow
    Start-Process "http://127.0.0.1:$Port/ollama-chat.html"
    Start-Sleep -Seconds 2
    exit 0
}

Write-Host "=== Qwen3.5 2B 本地聊天 ===" -ForegroundColor Cyan
Write-Host "Python: $py" -ForegroundColor DarkGray
Write-Host "服务  : http://127.0.0.1:$Port （仅本机可访问）" -ForegroundColor DarkGray

$server = Start-Process -FilePath $py `
    -ArgumentList @('-m', 'http.server', "$Port", '--bind', '127.0.0.1', '--directory', $ToolsDir) `
    -PassThru -WindowStyle Hidden

# 等端口起来（最多 7 秒）
$ready = $false
for ($i = 0; $i -lt 14; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
}
if (-not $ready) {
    Write-Host "服务没起来，检查 Python 是否可执行" -ForegroundColor Red
    if ($server -and -not $server.HasExited) { $server.Kill() }
    Read-Host "按回车退出"
    exit 1
}

Write-Host "已启动，正在打开浏览器…" -ForegroundColor Green
Start-Process "http://127.0.0.1:$Port/ollama-chat.html"

Write-Host ""
Write-Host "关掉这个窗口就会停止服务（浏览器页面随之失效）。" -ForegroundColor DarkGray
Write-Host "现在可以最小化，去浏览器里聊。" -ForegroundColor DarkGray

try {
    while ($true) { Start-Sleep -Seconds 1 }
} finally {
    if ($server -and -not $server.HasExited) { $server.Kill() }
}

} catch {
    Write-Host ""
    Write-Host ("出错了：" + $_.Exception.Message) -ForegroundColor Red
    Write-Host ("位置：" + $_.InvocationInfo.PositionMessage) -ForegroundColor DarkYellow
    Read-Host "按回车关闭"
}