# video-frames.ps1 —— 把视频抽成"一张九宫格图" + 基本信息
#
# 为什么这么做：
#   模型不能播放视频，但能读图片。把整段视频均匀抽 9 帧拼成一张图，
#   一眼就能看出"这个视频大概在讲什么"。
#
# 用法：
#   .\video-frames.ps1 -Path "D:\xxx\video.mp4"
#   .\video-frames.ps1 -Path video.mp4 -Count 12 -Width 420
#
# 输出：
#   <视频同目录>\frames-<视频名>.png   九宫格（或按 -Count 自动算行列）
#   控制台打印 时长/分辨率/帧率/码率/音轨

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Count = 9,
    [int]$Width = 480
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Find-FfTool([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $winget) {
        $hit = Get-ChildItem $winget -Recurse -Filter "$name.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$ffprobe = Find-FfTool 'ffprobe'
$ffmpeg  = Find-FfTool 'ffmpeg'
if (-not $ffmpeg -or -not $ffprobe) {
    throw "找不到 ffmpeg / ffprobe，先装：winget install --id Gyan.FFmpeg -e"
}
if (-not (Test-Path $Path)) { throw "文件不存在：$Path" }

$file = Get-Item $Path

# ---------- 1) 基本信息 ----------
$json = & $ffprobe -v error -print_format json -show_format -show_streams $file.FullName 2>$null | Out-String
$info = $json | ConvertFrom-Json

$v = $info.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
$a = $info.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

$duration = [double]$info.format.duration
$sizeMB = [math]::Round($file.Length / 1MB, 1)
$bitrate = [math]::Round([double]$info.format.bit_rate / 1000)

Write-Host "=== $($file.Name) ===" -ForegroundColor Cyan
Write-Host ("  时长   : {0:N1} 秒（{1:N1} 分）" -f $duration, ($duration / 60))
Write-Host ("  体积   : $sizeMB MB   总码率 {0:N0} kbps" -f $bitrate)
if ($v) {
    $fps = if ($v.avg_frame_rate -and $v.avg_frame_rate -ne '0/0') {
        $p = $v.avg_frame_rate -split '/'
        [math]::Round([double]$p[0] / [double]$p[1], 2)
    } else { 0 }
    Write-Host ("  画面   : {0}x{1}  {2} fps  编码 {3}" -f $v.width, $v.height, $fps, $v.codec_name)
}
if ($a) {
    Write-Host ("  音轨   : {0}  {1} Hz  {2} 声道" -f $a.codec_name, $a.sample_rate, $a.channels)
} else {
    Write-Host "  音轨   : 无" -ForegroundColor Yellow
}

# ---------- 2) 抽帧拼图 ----------
# 按帧数算行列：9 帧 → 3x3，12 帧 → 4x3
$cols = [math]::Ceiling([math]::Sqrt($Count))
$rows = [math]::Ceiling($Count / $cols)
# fps = 抽多少帧 / 总时长（保证整段均匀分布）
$fpsExpr = if ($duration -gt 0) { $Count / $duration } else { 1 }

$out = Join-Path $file.DirectoryName ("frames-" + $file.BaseName + ".png")
$filter = "fps=$([math]::Round($fpsExpr, 6)),scale=${Width}:-2,tile=${cols}x${rows}"

Write-Host "`n  正在抽 $Count 帧拼成 ${cols}x${rows} …" -ForegroundColor DarkGray
& $ffmpeg -y -v error -i $file.FullName -vf $filter -frames:v 1 $out 2>&1 | Out-Null

if (Test-Path $out) {
    $kb = [math]::Round((Get-Item $out).Length / 1KB)
    Write-Host ("  ✅ 输出: $out  ($kb KB)") -ForegroundColor Green
    Write-Host ("  网格: ${cols} 列 × ${rows} 行，每格约 ${Width}px 宽")
} else {
    Write-Host "  ❌ 抽帧失败（可能是纯音频/损坏文件）" -ForegroundColor Red
}
