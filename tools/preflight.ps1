# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/preflight.ps1 —— 发布前自检（表驱动，一屏可读）
#   作者 : ltcdz5   许可 : GPL-2.0
#   用法 : powershell -ExecutionPolicy Bypass -File tools\preflight.ps1 -Ver v1.1-opt47
#   设计 : 判定逻辑集中；检查项列表驱动（加检查 = 加一行，不新增一节）；
#          查不了的打印 MANUAL，不代填。判定：FAIL=0 才可发布。
#   权威值 : 现役/回退只看 CHANGELOG.md 第一节 与 README.md 第九节。
# ---------------------------------------------------------------------------
param(
  [Parameter(Mandatory=$true)][string]$Ver,
  [string]$Root = 'C:\Users\xutengfa\Desktop\gt5pro-kernel',
  [string]$Adb  = 'D:\gaojizhushou\adb.exe',
  [string]$Wsl  = 'Ubuntu-24.04',
  [string]$Tree = '/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
)
$Kit = Join-Path $Root 'kernel-kit'; $Imgs = Join-Path $Root 'images'
$RootWsl = $Root.Replace('\','/').Replace('C:','/mnt/c')
$KitWsl = $RootWsl + '/kernel-kit'
$nPass = 0; $nFail = 0; $nWarn = 0
function ok($m) { $script:nPass++; Write-Host ('  PASS  ' + $m) -ForegroundColor Green }
function no($m) { $script:nFail++; Write-Host ('  FAIL  ' + $m) -ForegroundColor Red }
function wn($m) { $script:nWarn++; Write-Host ('  WARN  ' + $m) -ForegroundColor Yellow }
function sec($m) { Write-Host ''; Write-Host ('== ' + $m + ' ==') -ForegroundColor Cyan }
function RunWsl($c) { (wsl.exe -d $Wsl -- bash -lc $c 2>&1) -join ([char]10) }

sec '1) 树与产物'
$br = (RunWsl ('cd ' + $Tree + ' && git rev-parse --abbrev-ref HEAD')).Trim()
$hd = (RunWsl ('cd ' + $Tree + ' && git log --oneline -1')).Trim()
wn ('分支=' + $br + '  HEAD=' + $hd)
$vs = (RunWsl ('cd ' + $Tree + ' && tail -1 scripts/setlocalversion')).Trim()
if ($vs -match [regex]::Escape($Ver)) { ok ('版本串匹配 ' + $Ver) } else { no ('版本串不含 ' + $Ver) }
if ([string]::IsNullOrWhiteSpace((RunWsl ('cd ' + $Tree + ' && git status --porcelain')).Trim())) { ok '工作树干净' } else { wn '工作树有未提交改动' }
$rejn = (RunWsl ("cd $Tree && git ls-files | grep -cE '\\.(rej|orig)$'")).Trim()
if ($rejn -eq '0') { ok '.rej/.orig 残留 = 0' } else { no ('.rej/.orig 残留 = ' + $rejn) }
$gl = (RunWsl ("cd $Tree && git ls-files -s | grep '^160000' | cut -f2")).Trim()
$gm = (RunWsl ('cd ' + $Tree + ' && grep -c ^[[]submodule .gitmodules 2>/dev/null || echo 0')).Trim()
if ([string]::IsNullOrWhiteSpace($gl)) { ok '无 gitlink 条目' }
elseif ($gm -match '^[0-9]+$' -and [int]$gm -ge 1) { ok ('gitlink 有 .gitmodules 对应：' + $gl) }
else { no ('悬空 gitlink：' + $gl) }

sec '2) 双闸门（该版真实产物）'
$g1 = RunWsl ('cd ' + $Tree + ' && python3 ' + $KitWsl + '/tools/gate_new_exports.py out/vmlinux.symvers 2>&1 | tail -3')
Write-Host $g1
if ($g1 -match 'PASS' -and $g1 -match '遮蔽=0') { ok '闸门1 PASS 且遮蔽=0' } else { no '闸门1 未过或遮蔽不为 0' }
$g2 = RunWsl ('cd ' + $Tree + ' && python3 ' + $KitWsl + '/tools/gate_vko_crc.py out/vmlinux.symvers ' + $RootWsl + '/vendor-ko/vendor_dlkm ' + $RootWsl + '/vendor-ko/system_dlkm 2>&1 | grep -m1 会拒绝装载')
if ($g2 -match '= 1') { ok '闸门2 会拒绝装载 = 1（仅蓝牙基线）' } else { no ('闸门2 异常：' + $g2) }

sec '3) 交付件'
$img = Join-Path $Imgs ('boot-' + $Ver + '-repacked.img')
if (Test-Path $img) { ok ($Ver + ' 镜像 md5=' + (Get-FileHash $img -Algorithm MD5).Hash.ToLower()) } else { no ('找不到 ' + $img) }
if ((Test-Path (Join-Path $Imgs '清单.txt')) -and ((Get-Content (Join-Path $Imgs '清单.txt') -Raw) -match [regex]::Escape($Ver))) { ok 'images/清单.txt 已含该版' } else { no 'images/清单.txt 未含该版' }
$rb = @(Get-ChildItem $Imgs -Filter 'boot-v1.1-opt*-repacked.img*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch [regex]::Escape($Ver) })
if ($rb.Count -gt 0) { ok ('可回退件 ' + $rb.Count + ' 个') } else { wn '没有其它可回退件' }

sec '4) 设备实测'
& $Adb push (Join-Path $Kit 'tools\preflight-dev.sh') /data/local/tmp/preflight-dev.sh 2>&1 | Out-Null
$raw = (& $Adb shell su -c 'sh /data/local/tmp/preflight-dev.sh' 2>&1) -join ([char]10)
$B = @{}; $cur2 = ''
foreach ($line in ($raw -split '\r?\n')) {
  if ($line -match '^@@@@(\S+)') { $cur2 = $Matches[1]; $B[$cur2] = @(); continue }
  if ($cur2) { $B[$cur2] += $line }
}
$devOk = (($B['UNAME'] -join '').Trim() -ne '')
if (-not $devOk) {
  no '设备未连接（adb 无设备）⇒ 设备节整体跳过；发布前必须连上设备再跑'
} else {
  $kern = ($B['UNAME'] -join '').Trim()
  if ($kern -match [regex]::Escape($Ver)) { ok ('设备内核 = ' + $kern) } else { no ('设备内核 = ' + $kern) }
  $lm = ($B['LSMOD'] -join '').Trim()
  if ($lm -eq '621') { ok 'lsmod = 621（基线）' } else { wn ('lsmod = ' + $lm) }
  if ((($B['SLOT'] -join '') -match '_a')) { ok '槽位 = _a' } else { wn '槽位不是 _a' }
  $dmRaw = ($B['DMESG'] -join ' ')
  $dmN = @($B['DMESG'] | Where-Object { $_ -and ($_.Trim() -match '^[0-9]+$') })
  if ($dmRaw -match 'klogctl') { no 'dmesg 不可读（klogctl）⇒ 判据不做数' }
  elseif ($dmN.Count -lt 3) { no ('dmesg 计数没取全（' + $dmN.Count + ' 项）') }
  elseif (([int]$dmN[0] -eq 0) -and ([int]$dmN[1] -eq 0) -and ([int]$dmN[2] -eq 0)) { ok 'dmesg: Unknown=0, disagrees=0, oops=0' }
  else { no ('dmesg 非零：' + $dmN[0] + '/' + $dmN[1] + '/' + $dmN[2]) }
  wn ('Scene: ' + (($B['SCENE'] -join ' ').Trim()) + '  -- 观察期内若更新须重算窗口')
}

sec '5) 仓库'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
if (Test-Path $gh) {
  $b2 = (& $gh api ('repos/ltcdz5/gt5pro-kernel-src/branches/' + $Ver) --jq '.name' 2>&1) -join ''
  if ($b2 -match $Ver) { ok ('源码仓库有分支 ' + $Ver) } else { no ('源码仓库缺分支 ' + $Ver) }
  $tg = (& $gh api ('repos/ltcdz5/gt5pro-kernel-src/git/ref/tags/' + $Ver) --jq '.ref' 2>&1) -join ''
  if ($tg -match $Ver) { ok ('源码仓库有 tag ' + $Ver) } else { no ('源码仓库缺 tag ' + $Ver) }
  wn ('默认分支 = ' + ((& $gh api 'repos/ltcdz5/gt5pro-kernel-src' --jq '.default_branch' 2>&1) -join ''))
} else { wn '没找到 gh，跳过' }

sec '6) 文档与边界（可计量）'
if ((Get-Content (Join-Path $Kit 'CHANGELOG.md') -Raw) -match [regex]::Escape($Ver)) { ok 'CHANGELOG（权威）含本版' } else { no 'CHANGELOG 缺本版' }
if ((Get-Content (Join-Path $Kit 'README.md') -Raw) -match [regex]::Escape($Ver)) { ok 'README（权威）含本版' } else { no 'README 未同步' }
$bad = @()
foreach ($d in (Get-ChildItem $Kit -Recurse -Filter '*.md')) {
  if ($d.Name -in @('CHANGELOG.md','README.md')) { continue }
  $ln = 0
  foreach ($line in (Get-Content $d.FullName)) {
    $ln++
    if ($line -notmatch '现役|回退首选') { continue }
    if ($line -notmatch 'opt[0-9]+') { continue }
    if ($line -match '历史|已过期|过期|曾|当时|快照|档案|归档') { continue }
    if (($line -match '现役') -and ($line -notmatch [regex]::Escape($Ver))) { $bad += ($d.Name + ':' + $ln) }
    elseif (($line -match '回退首选') -and ($line -notmatch 'opt42')) { $bad += ($d.Name + ':' + $ln) }
  }
}
if ($bad.Count -eq 0) { ok '非权威文档无冲突版本号' } else { no ('冲突 ' + $bad.Count + ' 处：' + (($bad | Select-Object -First 5) -join ', ')) }
$tracked = @(git -C $Kit ls-files)
$forbidden = @('refs/cctv18-config-20261001.txt','refs/cctv18-anykernel.sh','refs/manifest_gt5pro_u.xml','refs/manifest_oneplus12_v.xml')
$hit = @($forbidden | Where-Object { $tracked -contains $_ })
if ($hit.Count -eq 0) { ok ('他人原件 = 0（清单 ' + $forbidden.Count + ' 项）') } else { no ('仍跟踪他人原件：' + ($hit -join ', ')) }
$hb = @()
foreach ($t in ($tracked | Where-Object { $_ -match '\.md$' -and $_ -notmatch 'NOTICE\.md$|^README\.md$|审计-' })) {
  $fp = Join-Path $Kit $t
  if ((Test-Path $fp) -and ((Get-Content $fp -Raw) -match 'Numbersf|ITXUU|victor-egg')) { $hb += $t }
}
if ($hb.Count -eq 0) { ok '个人 handle 仅在署名类文件' } else { no ('handle 越界：' + ($hb -join ', ')) }
if ((Test-Path (Join-Path $Kit 'NOTICE.md')) -and ((Get-Content (Join-Path $Kit 'NOTICE.md') -Raw).Length -gt 200)) { ok 'NOTICE.md 在（上游归属保留）' } else { no 'NOTICE.md 缺失' }
$ai = Join-Path $Kit 'archive\README.md'
if (Test-Path $ai) {
  $rows = @(Get-Content $ai | Where-Object { $_ -match '^[|]' -and $_ -match '[0-9]' })
  $nd = @($rows | Where-Object { $_ -notmatch '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' })
  if ($nd.Count -eq 0) { ok ('归档索引 ' + $rows.Count + ' 条，全带日期') } else { no ('归档索引缺日期 ' + $nd.Count + ' 条') }
} else { wn '无 archive/README.md' }

sec '7) 人工项（不代填）'
foreach ($m in @('观察期起止时刻（须满 24h，期间 Scene 未更新、未刷机）','规范第一节 8 条判据的人工部分（体感/续航）','未结案清单复核；半补项写明缺哪一半')) { Write-Host ('  MANUAL  ' + $m) -ForegroundColor Cyan }

Write-Host ''
$col = if ($nFail -gt 0) { 'Red' } else { 'Green' }
Write-Host ('===== PASS=' + $nPass + '  FAIL=' + $nFail + '  WARN=' + $nWarn + ' =====') -ForegroundColor $col
if ($nFail -gt 0) { exit 1 } else { exit 0 }
