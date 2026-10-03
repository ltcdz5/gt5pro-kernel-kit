$ErrorActionPreference = 'Continue'
$ADB = 'D:\gaojizhushou\adb.exe'
$SMP = 'C:\Users\USERNAME\AppData\Local\Temp\perf\ruler_sample.sh'
$LOCAL = 'C:\Users\USERNAME\AppData\Local\Temp\boot_ruler.tsv'
$rounds = if ($args.Count -ge 1) { [int]$args[0] } else { 10 }
$keepResults = $true

& $ADB shell "su -c 'rm -f /data/local/tmp/boot_ruler.tsv'" | Out-Null
& $ADB push $SMP /data/local/tmp/rs.sh | Out-Null

function Wait-Device {
    for ($i = 0; $i -lt 60; $i++) {
        $d = & $ADB devices 2>&1
        if ($d -match 'DEVICE_SERIAL\s+device') { Start-Sleep -Seconds 2; return $true }
        if ($d -match 'DEVICE_SERIAL\s+offline') { Start-Sleep -Seconds 2 }
        else { Start-Sleep -Seconds 2 }
    }
    return $false
}

Write-Output "=== 启动测量: $rounds 轮 ==="
for ($i = 1; $i -le $rounds; $i++) {
    Write-Output "--- 第 $i/$rounds 轮: 重启 ---"
    $cap = (& $ADB shell "su -c 'cat /sys/class/power_supply/battery/capacity'" 2>&1).Trim()
    Write-Output "    电量 = $cap%"
    & $ADB reboot | Out-Null
    if (-not (Wait-Device)) { Write-Output "    ★ 设备未回来, 中止"; break }
    # 采样脚本自己会等 boot_completed
    $out = & $ADB shell "su -c 'sh /data/local/tmp/rs.sh $i 2>&1'" 2>&1
    Write-Output ("    " + ($out | Select-Object -First 1))
}

Write-Output ""
Write-Output "=== 拉结果 ==="
& $ADB pull /data/local/tmp/boot_ruler.tsv $LOCAL 2>&1 | Out-Null
if (Test-Path $LOCAL) {
    Write-Output "已保存: $LOCAL"
    Get-Content $LOCAL | ForEach-Object { "  $_" }
}
