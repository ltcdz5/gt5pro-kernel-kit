#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存4_cmp.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 比对 v4 两轮读数（纯本地，不碰设备）。用法: bash 留存4_cmp.sh
D=/c/Users/xutengfa/Downloads/v4
for t in B1_off A1_on; do
  [ -s "$D/$t.txt" ] || { echo "缺 $t.txt"; exit 1; }
done

echo "================ 状态与有效性 ================"
for t in B1_off A1_on; do
  printf '%-8s %s\n' "$t" "$(grep -E '设定后 enabled=|终点 MGLRU' "$D/$t.txt" | tr '\n' ' ')"
  grep -q '^done$' "$D/$t.txt" && echo "         收尾标记 OK" || echo "         ⚠ 无 done，作废"
done

echo "================ 留存结果 ================"
for t in B1_off A1_on; do
  grep -E '实际启动成功|==== 结果|消失清单' "$D/$t.txt" | sed "s/^/  $t /"
done

echo "================ 压力速率（每秒，消除时长差） ================"
for t in B1_off A1_on; do
  echo "  ---- $t"
  grep '/s$' "$D/$t.txt" | sed 's/^/    /'
done

echo "================ 起点是否真归一化 ================"
for t in B1_off A1_on; do
  printf '  %-8s %s\n' "$t" "$(grep -E '起点 PSI|起点应用进程数|MemAvailable' "$D/$t.txt" | head -2 | tr '\n' ' ')"
done

echo "================ 消失清单是否重叠 ================"
grep '^消失清单' "$D/B1_off.txt" | sed 's/^消失清单://' | tr ' ' '\n' | grep -v '^$' | sort > "$D/dead.B1"
grep '^消失清单' "$D/A1_on.txt"  | sed 's/^消失清单://' | tr ' ' '\n' | grep -v '^$' | sort > "$D/dead.A1"
echo "  B1(off) 消失 $(wc -l < "$D/dead.B1") 个；A1(on) 消失 $(wc -l < "$D/dead.A1") 个"
echo "  两轮共同消失（那就是压力本身干的，与 MGLRU 无关）:"
comm -12 "$D/dead.B1" "$D/dead.A1" | sed 's/^/    /'
echo "  只在 off 消失:"; comm -23 "$D/dead.B1" "$D/dead.A1" | sed 's/^/    /'
echo "  只在 on 消失:";  comm -13 "$D/dead.B1" "$D/dead.A1" | sed 's/^/    /'

echo "================ 死因取证原文 ================"
sed -n '/---- 死因取证 ----/,/---- 收尾/p' "$D/B1_off.txt" | sed 's/^/  B1 /'
sed -n '/---- 死因取证 ----/,/---- 收尾/p' "$D/A1_on.txt" | sed 's/^/  A1 /'
