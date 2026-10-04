# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/sentinel.ps1 —— 环境变更哨兵（每小时留证）
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   作用 : 把「人记不住改了什么」变成证据：每小时往 sentinel.tsv 追加一行
#          （内核/banner、槽位、开机原因、uptime、模块数、oops/disagrees、Scene 版本与更新时刻、
#            各 policy 的 governor/max/min、电池状态、CPU 温度、阻止休眠 TOP5）
#   用法 : powershell -ExecutionPolicy Bypass -File tools\sentinel.ps1
#          （可挂 Windows 计划任务做到每小时自动跑；本脚本不自建计划任务）
# ---------------------------------------------------------------------------
param([string]$Root = 'C:\Users\xutengfa\Desktop\gt5pro-kernel',
      [string]$Adb  = 'D:\gaojizhushou\adb.exe')

$Out = Join-Path $Root 'logs\sentinel.tsv'
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'logs') | Out-Null
if (-not (Test-Path $Out)) { 'ts' + [char]9 + 'kernel' + [char]9 + 'slot' + [char]9 + 'bootreason' + [char]9 + 'uptime_h' + [char]9 + 'lsmod' + [char]9 + 'oops' + [char]9 + 'disagrees' + [char]9 + 'scene_ver' + [char]9 + 'scene_upd' + [char]9 + 'cpufreq' + [char]9 + 'batt' + [char]9 + 'tz' + [char]9 + 'ws_top5' | Add-Content $Out }

function Ensure {
  for ($k=1; $k -le 5; $k++) {
    & $Adb kill-server 2>&1 | Out-Null; Start-Sleep 2
    & $Adb start-server 2>&1 | Out-Null; Start-Sleep 3
    if ((((& $Adb devices 2>&1) -join ' ') -match '8ad67adf\s+device')) { return $true }
    Start-Sleep 4
  }
  return $false
}

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
if (-not (Ensure)) { ($now + ([char]9) + 'OFFLINE') | Add-Content $Out; Write-Output '设备离线，已记一行 OFFLINE'; exit 1 }

& $Adb push (Join-Path $PSScriptRoot 'sentinel-snap.sh') /data/local/tmp/sentinel-snap.sh 2>&1 | Out-Null
$raw = & $Adb shell su -c 'sh /data/local/tmp/sentinel-snap.sh' 2>&1

$B = @{}; $cur = ''
foreach ($line in $raw) {
  if ($line -match '^@@@@(\S+)') { $cur = $Matches[1]; $B[$cur] = @(); continue }
  if ($cur) { $B[$cur] += $line }
}
function G($k, $i = 0) { if ($B[$k] -and $B[$k].Count -gt $i) { return "$($B[$k][$i])".Trim() } return '' }
$ver = (G 'UNAME')
$kern = if ($ver -match 'version (\S+)') { $Matches[1] } else { '' }
$slot = G 'BOOT' 1
$boot = G 'BOOT' 0
$up = [math]::Round([double](G 'UP') / 3600, 2)
$lsmod = G 'LSMOD'
$oops = G 'DMESG' 0; $dis = G 'DMESG' 1
$sceneV = G 'SCENE' 0; $sceneT = G 'SCENE' 1
$cpuf = (G 'CPUFREQ').Trim()
$batt = ((G 'BATT' 0) + '/' + (G 'BATT' 1) + '%/' + (G 'BATT' 2) + 'uA')
$tz = (($B['TZ'] | Where-Object { $_ -match '\d' }) -join ',')
$ws = $B['WS']
$wsTop = @()
if ($ws -and $ws.Count -gt 1) {
  $wsTop = $ws[1..($ws.Count-1)] | Where-Object { $_ -match '\S' } | ForEach-Object {
    $f = $_ -split '\s+'
    if ($f.Count -ge 10) { [pscustomobject]@{ n = $f[0]; p = [int64]$f[9] } }
  } | Sort-Object p -Descending | Select-Object -First 5 | ForEach-Object { "$($_.n)=$($_.p)" }
}
$row = @($now, $kern, $slot, $boot, $up, $lsmod, $oops, $dis, $sceneV, $sceneT, $cpuf, $batt, $tz, ($wsTop -join '; ')) -join ([char]9)
$row | Add-Content $Out
Write-Output $row
