#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/scx_stock_vs_ours.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 对拍: 原厂 boot_a.img 与我们的 opt9 —— 原厂内核里有没有内置的 scx 调度器
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images || exit 1
for f in boot_a.img boot-opt9-repacked.img boot-cctv-6.1.141-repacked.img; do
  [ -f "$f" ] || { echo "缺 $f"; continue; }
  echo "================= $f"
  echo "  scx_ 符号种类数 = $(strings -a "$f" | grep -oE 'scx_[a-z0-9_]+' | sort -u | wc -l)"
  echo "  出现最多的 8 个:"
  strings -a "$f" | grep -oE 'scx_[a-z0-9_]+' | sort | uniq -c | sort -rn | head -8 | sed 's/^/     /'
  echo "  自定义调度器/厂商标识:"
  strings -a "$f" | grep -oiE 'hmbird|ogki|oplus_scx|bpfland|rusty|lavender|local_kf|energykit|sched_ext_ops[a-z_]*|ext_sched[a-z_]*' \
    | sort | uniq -c | sort -rn | head -10 | sed 's/^/     /'
  echo "  struct_ops 注册名候选(BTF 里 ext 相关): $(strings -a "$f" | grep -oE '__BTF_ID__(struct|func)__[a-z0-9_]*ext[a-z0-9_]*' | sort -u | wc -l)"
done
echo
echo "=== 我们的 opt9 与原厂差异里, scx 相关独有的名字(只在一侧出现的) ==="
strings -a boot_a.img | grep -oE 'scx_[a-z0-9_]+' | sort -u > /tmp/stock.scx
strings -a boot-opt9-repacked.img | grep -oE 'scx_[a-z0-9_]+' | sort -u > /tmp/ours.scx
echo "  只在原厂有: $(comm -23 /tmp/stock.scx /tmp/ours.scx | tr '\n' ' ' | cut -c1-200)"
echo "  只在我们有: $(comm -13 /tmp/stock.scx /tmp/ours.scx | tr '\n' ' ' | cut -c1-200)"
