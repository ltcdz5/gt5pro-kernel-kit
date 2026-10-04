# 刷 opt15 到 boot_a —— 一条命令跑完全流程（含电量门槛与 md5 核验）
#
# 用法（管理员 PowerShell）:
#     powershell -ExecutionPolicy Bypass -File "C:\Users\xutengfa\Desktop\gt5pro-kernel\kernel-kit\tools\刷opt15.ps1"
#     powershell -ExecutionPolicy Bypass -File "...\刷opt15.ps1" -Force   # 跳过电量门槛(不推荐)
#
# 纪律：只写 boot_a。绝不碰 init_boot / devinfo / abl / xbl / vbmeta / super / userdata / boot_b。
#       fastboot flash 会把该槽设为 active，所以必须显式 set_active a。

param(
    [switch]$Force,
    [int]$MinBattery = 30
)

$ErrorActionPreference = 'Stop'

$ADB      = 'D:\gaojizhushou\adb.exe'
$FASTBOOT = 'D:\gaojizhushou\fastboot.exe'
$IMG      = 'C:\Users\xutengfa\Desktop\gt5pro-kernel\images\boot-opt15-repacked.img'
$EXPECT_MD5 = '600b612f95faed6d6daf4f6d0eb2c871'
$EXPECT_RAW_MD5 = '25df97f4642b77712008c0129f795527'   # 裸 Image 的 md5，写进日志备查

function Step($n, $t) { Write-Host "`n=== [$n] $t ===" -ForegroundColor Cyan }

Step 1 '待刷件 md5 核验'
if (-not (Test-Path $IMG)) { throw "找不到 $IMG" }
$h = (Get-FileHash $IMG -Algorithm MD5).Hash.ToLower()
Write-Host "  $IMG"
Write-Host "  md5 = $h"
if ($h -ne $EXPECT_MD5) { throw "md5 不符！期望 $EXPECT_MD5，实际 $h —— 停，不许刷" }
Write-Host "  ✅ 与记录一致（裸内核 md5 $EXPECT_RAW_MD5）" -ForegroundColor Green

Step 2 '设备与电量门槛'
$devs = & $ADB devices
Write-Host ($devs -join "`n")
if (-not ($devs -match 'DEVICE_SERIAL\s+device')) { throw "adb 没看到 DEVICE_SERIAL device —— 停" }

$lvlRaw = (& $ADB shell "su -c 'cat /sys/class/power_supply/battery/capacity'").Trim()
$curRaw = (& $ADB shell "su -c 'cat /sys/class/power_supply/battery/current_now'").Trim()
$lvl = 0; [void][int]::TryParse($lvlRaw, [ref]$lvl)
Write-Host "  电量 = $lvlRaw %   电流 = $curRaw uA (负=放电)"
if ($lvl -lt $MinBattery -and -not $Force) {
    throw "电量 $lvl% < 门槛 $MinBattery% —— 停。刷机中途没电会变砖。先充到 $MinBattery% 以上（建议 50%+，关屏充）。"
}
if ($lvl -lt $MinBattery) { Write-Host "  ⚠️ 已用 -Force 跳过电量门槛" -ForegroundColor Yellow }

Step 3 '起点横幅（回退后要拿它对照）'
& $ADB shell "su -c 'uname -a'"

Step 4 'BL 解锁状态（只认 /proc/cmdline，别信 getprop）'
$cmd = & $ADB shell "su -c 'cat /proc/cmdline'"
if ($cmd -match 'verifiedbootstate=orange') {
    Write-Host "  verifiedbootstate=orange ⇒ 已解锁 ✅" -ForegroundColor Green
} else {
    throw "cmdline 里不是 orange —— 停，不要刷"
}

Step 5 '重启进 fastboot'
& $ADB reboot bootloader
Start-Sleep -Seconds 8
$fb = $null
for ($i = 1; $i -le 20; $i++) {
    $fb = & $FASTBOOT devices 2>&1
    if ($fb -match '\S+\s+fastboot') { break }
    Start-Sleep -Seconds 3
}
Write-Host ($fb -join "`n")
if (-not ($fb -match '\S+\s+fastboot')) { throw "fastboot 没认出设备 —— 屏幕全黑是正常的，但没设备就停，不要猜" }
Write-Host "  current-slot = $(& $FASTBOOT getvar current-slot 2>&1)"

Step 6 '写 boot_a'
& $FASTBOOT flash boot_a $IMG
if ($LASTEXITCODE -ne 0) { throw "flash 失败，退出码 $LASTEXITCODE" }

Step 7 'set_active a（必做：flash 会顺手改 active 槽）'
& $FASTBOOT set_active a

Step 8 '重启'
& $FASTBOOT reboot

Step 9 '等起来并复核'
& $ADB wait-for-device
Start-Sleep -Seconds 25
& $ADB shell "su -c 'uname -a'"

Write-Host "`n完成。上面 uname -a 应出现 opt15 横幅。" -ForegroundColor Green
Write-Host "回退（任何不对就这一条）:" -ForegroundColor Yellow
Write-Host "  & '$FASTBOOT' flash boot_a 'C:\Users\xutengfa\Desktop\gt5pro-kernel\images\boot-opt14-repacked.img'"
Write-Host "  & '$FASTBOOT' set_active a"
Write-Host "  & '$FASTBOOT' reboot"
