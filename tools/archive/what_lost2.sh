#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git diff --name-only opt5-state opt6 | sort > /tmp/chg.txt
git show --name-only --format='' 372750608 | sed '/^$/d' | sort > /tmp/ours.txt
echo "=== A) opt5-state..opt6 的 35 个文件按类型拆开 ==="
echo "  其中 .patch/.txt 等 builder 生成物: $(grep -cE '\.patch$|\.txt$|\.orig$|~$' /tmp/chg.txt)"
grep -E '\.patch$|\.txt$|\.orig$|~$' /tmp/chg.txt | sed 's/^/    /' | head -12
echo "  真正的源码文件: $(grep -vcE '\.patch$|\.txt$|\.orig$|~$' /tmp/chg.txt)"
grep -vE '\.patch$|\.txt$|\.orig$|~$' /tmp/chg.txt | sed 's/^/    /'
echo
echo "=== B) 关键交集: 上游改的文件 vs 我们提交碰过的文件 ==="
comm -12 /tmp/ours.txt /tmp/chg.txt > /tmp/ov.txt
echo "  交集内容(必须为空, 否则=官方版本盖掉了我们的补丁):"
cat /tmp/ov.txt | sed 's/^/    /'
echo "  交集条数: $(wc -l < /tmp/ov.txt)"
echo
echo "=== C) 与 cctv18 基线比, 这 35 个文件里有谁被 cctv18 单独改过(=会被官方版本覆盖) ==="
for f in $(grep -vE '\.patch$|\.txt$' /tmp/chg.txt); do
  if ! git diff --quiet 7a244ff18 opt5-state -- "$f" 2>/dev/null; then
    printf "    覆盖风险: %-42s " "$f"
    git diff --numstat 7a244ff18 opt5-state -- "$f" | awk '{printf "+%s/-%s (我们或cctv18的本地改动)\n", $1, $2}'
  fi
done
echo
echo "=== D) 我们的 16 项特性在 opt6 里逐项点名(在源码树里搜得到实现) ==="
for pair in "lz4 1.10.0:lib/lz4/decompress.c" "zstd 1.5.7:crypto/zstd_comp.c" "CVE-2026-43499 rtmutex:kernel/locking/rtmutex.c" "BBG LSM:security/baseband_guard" "regdb 内嵌:firmware/regulatory.db" "BRUTAL:net/ipv4/tcp_brutal.c" "CAKE:net/sched/sch_cake.c" "FQ_CODEL:net/sched/sch_fq_codel.c" "setlocalversion 后缀:scripts/setlocalversion"; do
  n=${pair%%:*}; p=${pair#*:}
  if [ -e "$p" ]; then printf "    %-24s 在  %s\n" "$n" "$(grep -oE 'VERSION|version [0-9.]+' $p 2>/dev/null | head -1) $(test -f "$p" && stat -c %s "$p")B"; else printf "    %-24s 缺 !\n" "$n"; fi
done
echo
echo "=== E) 版本串与后缀最终确认 ==="
grep '^res=' scripts/setlocalversion | tail -2
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-60
