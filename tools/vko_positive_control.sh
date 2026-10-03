#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/vko_positive_control.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 正对照 + hmbird 查询, 全走文件避免引号问题
F=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vko_strings.txt.gz
ls -l "$F" 2>&1 | sed 's/^/文件: /'
G=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vko_strings.txt
ls -l "$G" 2>&1 | sed 's/^/未压: /'
echo "总行数=$(zcat "$F" 2>/dev/null | wc -l)"
echo
echo "=== 正对照: 这份 strings 里必然存在的东西 ==="
for k in oplus_bsp_sched_assist frame_boost module_layout vermagic; do
  n=$(zgrep -c -F "$k" "$F" 2>/dev/null)
  echo "  %-28s 命中=%s" "$k" "$n"
done
echo
echo "=== 目标: hmbird / 注册符号 ==="
for k in hmbird register_hmbird_sched_ops task_is_scx scx_bpf_dispatch test_task_ux; do
  n=$(zgrep -c -F "$k" "$F" 2>/dev/null)
  echo "  %-28s 命中=%s" "$k" "$n"
done
echo
echo "=== 抽样看这份 strings 到底是什么(前 6 行) ==="
zcat "$F" 2>/dev/null | head -6 | sed 's/^/  /'
echo "=== 厂商模块符号名前缀 top10 ==="
zcat "$F" 2>/dev/null | grep -oE '^oplus_[a-z0-9_]+' | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
