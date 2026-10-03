#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo "=== 1) /proc/config.gz 会不会撒谎: builder 注入的 config_fix 在不在(哪来的) ==="
grep -n "config_fix" kernel/Makefile | head -3
git log --oneline -1 -S "config_fix" -- kernel/Makefile | cut -c1-90 | sed 's/^/   引入它的提交: /'
echo
echo "=== 2) 已提交的 gki_defconfig 干不干净(以 opt5-state 为准) ==="
git show opt5-state:arch/arm64/configs/gki_defconfig > /tmp/def5 2>/dev/null
echo "   行数 $(wc -l < /tmp/def5)  重复键数 $(grep '^CONFIG_' /tmp/def5 | sed 's/=.*//' | sort | uniq -d | wc -l)"
echo "   重复的键(前 8):"; grep '^CONFIG_' /tmp/def5 | sed 's/=.*//' | sort | uniq -c | awk '$1>1' | head -8 | sed 's/^/     /'
echo
echo "=== 3) 工作区里 builder 留下的垃圾文件(未跟踪) ==="
git status --porcelain | grep '^??' | wc -l | sed 's/^/   未跟踪文件数: /'
git status --porcelain | grep '^??' | head -12 | sed 's/^/     /'
echo
echo "=== 4) kit 里那个 69_hide_stuff.patch 到底有没有进树 ==="
P=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/patches/69_hide_stuff.patch
head -6 "$P" 2>/dev/null | sed 's/^/   /'
echo "   补丁涉及文件:"; grep -E '^(diff --git|\+\+\+ )' "$P" 2>/dev/null | sed 's/^/     /' | head -8
for f in $(grep -oE '^\+\+\+ b/.*' "$P" 2>/dev/null | sed 's|^+++ b/||' | head -6); do
  printf "     %-42s " "$f"
  if git log --oneline -1 -S "hide" -- "$f" >/dev/null 2>&1; then echo "文件存在, 需人工看内容"; else echo "文件不存在"; fi
  ls -la "$f" >/dev/null 2>&1 || echo "       ^ 该路径在本树里不存在"
done
echo
echo "=== 5) 我们有意加的三项是否都还在(opt5-state 树里) ==="
for s in "security/baseband-guard:BBG" "lib/lz4/lz4.c:lz4" "crypto/zstd:zstd" "kernel/locking/rtmutex.c:CVE"; do
  f=${s%%:*}; tag=${s##*:}; printf "   %-12s %s\n" "$tag" "$( [ -e "$f" ] && echo 在 || echo 缺 )"
done
grep -c "EXPORT_SYMBOL_GPL(sk_filter_trim_cap)" net/core/filter.c | sed 's/^/   (对照) sk_filter CRC 源文件在: /'
