#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo '=== 1) 上游补丁到底碰没碰 setlocalversion(证明交集=0) ==='
grep -c "setlocalversion" /home/builder/opt6_upstream.patch | sed 's/^/  补丁里出现次数: /'
grep -c "^+++ b/" /home/builder/opt6_upstream.patch | sed 's/^/  补丁文件数: /'
git diff --name-only opt5-state opt6 > /tmp/chg.txt
git diff --name-only 7a244ff18 FETCH_HEAD --diff-filter=d > /tmp/allup.txt
echo '  与"官方非删除改动"取交集后再排掉我们自己的两个文件, 结果:'
comm -12 <(sort /tmp/chg.txt) <(sort /tmp/allup.txt) | wc -l | sed 's/^/    交集条数: /'
echo
echo '=== 2) 我们五路补丁在 opt6 树里的准确落点与版本标记 ==='
echo '  -- lz4 版本 --'
grep -rhoE 'LZ4_VERSION_(MAJOR|MINOR|YEAR) +[0-9]+' lib/lz4* include/linux/lz4* 2>/dev/null | head -3
ls lib/lz4* 2>/dev/null | head -5
grep -rl "1\.10\.0" lib/ crypto/ include/ 2>/dev/null | head -5 | sed 's/^/    含 1.10.0 的文件: /'
echo '  -- zstd 版本 --'
grep -rhoE 'ZSTD_VERSION_(MAJOR|MINOR|RELEASE) +[0-9]+' lib/zstd/zstd_kernel.h lib/zstd/*/*.h include/linux/*.h 2>/dev/null | head -4
find . -path ./out -prune -o -name "zstd.h" -print 2>/dev/null | head -3
echo '  -- BBG / baseband_guard --'
find . -path ./out -prune -o -iname "*baseband*" -print 2>/dev/null | head -6
echo '  -- CVE-2026-43499 (rtmutex) 改动是否在 --'
grep -c "43499" *.patch* 2>/dev/null | head -3
git log --oneline -1 -- kernel/locking/rtmutex.c | cut -c1-80 | sed 's/^/    rtmutex.c 最后改动: /'
echo '  -- regdb --'
ls -la firmware/ | grep regulatory | sed 's/^/    /'
echo
echo '=== 3) 这些在 opt6 的 Image 里还在不在(最终以产物为准) ==='
python3 - out/arch/arm64/boot/Image <<'PY'
import sys
d=open(sys.argv[1],'rb').read()
for tag,pat in [("lz4 1.10.0", b"1.10.0"), ("zstd 1.5.7", b"1.5.7"), ("BBG 字符串", b"baseband_guard"),
                ("BRUTAL", b"brutal"), ("CAKE", b"cake"), ("FQ", b"fq_codel"),
                ("regulatory.db 头", b"RGDB"), ("-up0914 后缀", b"up0914")]:
    print("  %-16s %s" % (tag, "在" if d.count(pat) else "不在"))
PY
