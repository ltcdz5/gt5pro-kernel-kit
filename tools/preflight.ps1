# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/preflight.ps1 —— 发布前自检（照《发布规范》第五节逐条）
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   用法 : powershell -ExecutionPolicy Bypass -File tools\preflight.ps1 -Ver v1.1-opt47
#   说明 : 能自动查的自动查（打印 PASS/FAIL），查不了的打印 MANUAL 待办，不代填
# ---------------------------------------------------------------------------
param(
  [Parameter(Mandatory=$true)][string]$Ver,
  [string]$Root = 'C:\Users\xutengfa\Desktop\gt5pro-kernel',
  [string]$Adb  = 'D:\gaojizhushou\adb.exe',
  [string]$Wsl  = 'Ubuntu-24.04',
  [string]$Tree = '/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
)
$Kit  = Join-Path $Root 'kernel-kit'
$KitWsl = '/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit'
$DevScript = '/data/local/tmp/preflight-dev.sh'
$Imgs = Join-Path $Root 'images'
$pass = 0; $fail = 0; $warn = 0
function Say($t, $m) { $c = switch ($t) { 'PASS' {'Green'} 'FAIL' {'Red'} 'WARN' {'Yellow'} default {'Cyan'} }; Write-Host ("  [" + $t + "] " + $m) -ForegroundColor $c }
function Head($t) { Write-Host ""; Write-Host ("== " + $t + " ==") -ForegroundColor Cyan }
function WslDo($cmd) { (wsl -d $Wsl -- bash -lc $cmd 2>&1) -join ([char]10) }

Head "1) 树与构建产物（WSL）"
$branch = (WslDo "cd $Tree && git rev-parse --abbrev-ref HEAD").Trim()
$head   = (WslDo "cd $Tree && git log --oneline -1").Trim()
Say WARN "当前分支=$branch  HEAD=$head"
$verstr = (WslDo "cd $Tree && tail -1 scripts/setlocalversion").Trim()
if ($verstr -match [regex]::Escape($Ver)) { $pass++; Say PASS "版本串匹配 $Ver ：$verstr" } else { $fail++; Say FAIL "版本串不含 $Ver ：$verstr" }
$dirty = (WslDo "cd $Tree && git status --porcelain | head -5").Trim()
if ([string]::IsNullOrWhiteSpace($dirty)) { $pass++; Say PASS "工作树干净" } else { $warn++; Say WARN ("工作树有未提交改动：" + $dirty) }

Head "2) 残留与子模块（规范第五节第 10 项）"
$rej = (WslDo "cd $Tree && git ls-files | grep -cE '\.(rej|orig)$'").Trim()
if ($rej -eq '0') { $pass++; Say PASS ".rej/.orig 残留 = 0" } else { $fail++; Say FAIL (".rej/.orig 残留 = " + $rej) }
$gl = (WslDo "cd $Tree && git ls-files -s | grep '^160000' | cut -f2 | head -5").Trim()
$gm = (WslDo "cd $Tree && test -f .gitmodules && cat .gitmodules | grep -c '^\[submodule' || echo 0").Trim()
if ([string]::IsNullOrWhiteSpace($gl)) { $pass++; Say PASS "无 gitlink 条目" }
elseif ([int]$gm -ge 1) { $pass++; Say PASS ("gitlink 有 .gitmodules 对应：$gl") }
else { $fail++; Say FAIL ("悬空 gitlink 且无 .gitmodules：$gl") }

Head "3) 双闸门（在该版真实产物上）"
$g1 = WslDo "cd $Tree && python3 $KitWsl/tools/gate_new_exports.py out/vmlinux.symvers 2>&1 | tail -3"
Write-Host $g1
if ($g1 -match 'PASS' -and $g1 -match '遮蔽=0') { $pass++; Say PASS "闸门1：PASS 且遮蔽=0" } else { $fail++; Say FAIL "闸门1 未过或遮蔽≠0" }
$g2 = WslDo "cd $Tree && python3 $KitWsl/tools/gate_vko_crc.py out/vmlinux.symvers /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/vendor_dlkm /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/vendor-ko/system_dlkm 2>&1 | grep -m1 '会拒绝装载的模块'"
Write-Host ("  " + $g2)
if ($g2 -match '= 1$') { $pass++; Say PASS "闸门2：会拒绝装载 = 1（仅蓝牙基线）⇒ 非蓝牙拒载 = 0" } else { $fail++; Say FAIL "闸门2 非蓝牙拒载 ≠ 0，需人工看" }

Head "4) 镜像与回退件"
$img = Join-Path $Imgs ("boot-" + $Ver + "-repacked.img")
if (Test-Path $img) { $h = (Get-FileHash $img -Algorithm MD5).Hash.ToLower(); $pass++; Say PASS ($Ver + " 镜像存在，md5=" + $h) }
else { $fail++; Say FAIL ("找不到 " + $img) }
$man = Join-Path $Imgs '清单.txt'
if (Test-Path $man) {
  $m = Get-Content $man -Raw
  if ($m -match [regex]::Escape($Ver)) { $pass++; Say PASS "images/清单.txt 已含该版" } else { $fail++; Say FAIL "images/清单.txt 未含该版（重跑 tools/images_出清单.sh）" }
}
$rb = Get-ChildItem $Imgs -Filter "boot-v1.1-opt4*-repacked.img" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $Ver }
if ($rb) { $pass++; Say PASS ("可用回退件 " + $rb.Count + " 个，最新：" + $rb[-1].Name) } else { $warn++; Say WARN "没找到其他可回退件" }

Head "5) 文档一致性"
$chg = Join-Path $Kit 'CHANGELOG.md'; $rdm = Join-Path $Kit 'README.md'
if ((Get-Content $chg -Raw) -match [regex]::Escape($Ver)) { $pass++; Say PASS "CHANGELOG 含 $Ver" } else { $fail++; Say FAIL "CHANGELOG 缺 $Ver 条目" }
if ((Get-Content $rdm -Raw) -match [regex]::Escape($Ver)) { $pass++; Say PASS "README 含 $Ver" } else { $fail++; Say FAIL "README 未同步现役口径" }
$hasGh = Test-Path (Join-Path $Kit '.github')
$badgeCi = (Get-Content $rdm -Raw) -match 'GitHub%20Action'
if ($badgeCi -and -not $hasGh) { $fail++; Say FAIL "徽章写了 GitHub Action 但仓库无 .github" } else { $pass++; Say PASS "徽章与实际一致" }

Head "6) 设备实测（规范第五节第 17 项与判据）"
& $Adb push (Join-Path $Kit 'tools\preflight-dev.sh') $DevScript 2>&1 | Out-Null
$raw = (& $Adb shell su -c ("sh " + $DevScript) 2>&1) -join ([char]10)
Write-Host $raw
$B = @{}; $cur = ''
foreach ($line in ($raw -split "\r?\n")) {
  if ($line -match '^@@@@(\S+)') { $cur = $Matches[1]; $B[$cur] = @(); continue }
  if ($cur) { $B[$cur] += $line }
}
$kern = ($B['UNAME'] -join '').Trim()
if ($kern -match [regex]::Escape($Ver)) { $pass++; Say PASS ("设备运行内核 = " + $kern) } else { $fail++; Say FAIL ("设备运行内核 = " + $kern) }
$lm = ($B['LSMOD'] -join '').Trim()
if ($lm -eq '621') { $pass++; Say PASS "lsmod = 621（基线）" } else { $warn++; Say WARN ("lsmod = " + $lm) }
$sl = ($B['SLOT'] -join '').Trim()
if ($sl -eq '_a') { $pass++; Say PASS "槽位 = _a" } else { $warn++; Say WARN ("槽位 = " + $sl) }
$dm = ($B['DMESG'] | Where-Object { $_ -match '\d' })
if ($dm.Count -ge 3) {
  $unk = [int]($dm[0]); $dis = [int]($dm[1]); $oop = [int]($dm[2])
  if ($unk -eq 0 -and $dis -eq 0 -and $oop -eq 0) { $pass++; Say PASS ("dmesg: Unknown symbol=0, disagrees=0, oops=0") }
  else { $fail++; Say FAIL ("dmesg: Unknown symbol=" + $unk + ", disagrees=" + $dis + ", oops=" + $oop) }
} else { $warn++; Say WARN "dmesg 计数没取到" }
$sc = ($B['SCENE'] -join ' | ').Trim()
Say WARN ("Scene: " + $sc + "   <- 若更新时刻在观察期内，观察期须重算")
$gov = ($B['GOV'] -join ' ').Trim(); Say WARN ("限频: " + $gov)

Head "7) 仓库（源码快照 / tag / 默认分支）"
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
if (Test-Path $gh) {
  $br = (& $gh api "repos/ltcdz5/gt5pro-kernel-src/branches/$Ver" --jq '.name' 2>&1) -join ''
  if ($br -match $Ver) { $pass++; Say PASS "源码仓库有分支 $Ver" } else { $fail++; Say FAIL "源码仓库缺分支 $Ver" }
  $tg = (& $gh api "repos/ltcdz5/gt5pro-kernel-src/git/ref/tags/$Ver" --jq '.ref' 2>&1) -join ''
  if ($tg -match $Ver) { $pass++; Say PASS "源码仓库有 tag $Ver" } else { $fail++; Say FAIL "源码仓库缺 tag $Ver" }
  $def = (& $gh api "repos/ltcdz5/gt5pro-kernel-src" --jq '.default_branch' 2>&1) -join ''
  Say WARN ("源码仓库默认分支 = " + $def + "（须等于现役分支，或 README/Release 正文写明现役在哪）")
} else { $warn++; Say WARN "没找到 gh，跳过仓库检查" }

Head "8) 人工项（脚本不代填）"
Say MANUAL "观察期起止时刻（须满 24 小时，且期间 Scene 未更新、未刷机）"
Say MANUAL "规范第一节 8 条判据的人工部分（体感/续航等）"
Say MANUAL "未结案清单复核；半补项写明缺哪一半"
Say MANUAL "公开件里不含第三方模块/他人内核原始件（见规范第八节）"

Write-Host ""
Write-Host ("===== 自检汇总：PASS=" + $pass + "  FAIL=" + $fail + "  WARN=" + $warn + " =====") -ForegroundColor ($(if ($fail -gt 0) {'Red'} else {'Green'}))
if ($fail -gt 0) { exit 1 } else { exit 0 }
