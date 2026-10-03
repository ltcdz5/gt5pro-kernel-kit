#!/bin/bash
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git show opt5-state:arch/arm64/configs/gki_defconfig > /tmp/def5 2>/dev/null
echo "   (defconfig 已取, 行数 $(wc -l < /tmp/def5))"
echo "=== A) SUSFS 到底在不在树里(符号/文件/hooks 三路查) ==="
echo "   fs/proc/task_mmu.c 里 susfs 出现次数: $(grep -c susfs fs/proc/task_mmu.c)"
echo "   fs/proc/base.c     里 susfs 出现次数: $(grep -c susfs fs/proc/base.c)"
echo "   全树含 susfs 的文件数(排除 out/): $(git grep -l susfs -- ':!out' 2>/dev/null | wc -l)"
git grep -l susfs -- ':!out' 2>/dev/null | head -6 | sed 's/^/     /'
echo "   反证: 树里有没有 susfs 的头文件/目录: $(find . -path ./out -prune -o -iname '*susfs*' -print 2>/dev/null | head -3)"
echo "   Image 里有没有 susfs 字符串: $(strings out/arch/arm64/boot/Image 2>/dev/null | grep -ci susfs)"
echo
echo "=== B) zstd / lz4 实际版本与位置 ==="
for d in lib/zstd crypto/zstd lib/lz4; do [ -d "$d" ] && echo "   目录存在: $d"; done
grep -rhoE "ZSTD_VERSION_(MAJOR|MINOR|RELEASE)[[:space:]]+[0-9]+" lib/zstd/zstd_kernel.h include/linux/zstd*.h lib/zstd/common/huf.h 2>/dev/null | head -4 | sed 's/^/     /'
grep -rhoE "LZ4_VERSION_(MAJOR|MINOR)[[:space:]]+[0-9]+" lib/lz4/lz4.h 2>/dev/null | head -2 | sed 's/^/     /'
echo
echo "=== C) config_fix 拆掉的影响面(它只碰 config_data 吗) ==="
sed -n '155,186p' kernel/Makefile | grep -nE "config_data|KCONFIG_CONFIG|\.config|auto.conf" | sed 's/^/   /'
echo
echo "=== D) 未跟踪垃圾 + 已提交 defconfig 重复键明细(前 31 全量) ==="
git status --porcelain | grep '^??' | sed 's/^/   /'
grep '^CONFIG_' /tmp/def5 | sed 's/=.*//' | sort | uniq -d | wc -l | sed 's/^/   重复键数: /'
echo "   其中重复项取值不一致的(真隐患):"
python3 - <<'PY'
import collections
d=collections.OrderedDict()
for L in open('/tmp/def5',encoding='utf-8',errors='replace'):
    L=L.strip()
    if L.startswith('CONFIG_') and '=' in L:
        k=L.split('=')[0]; d.setdefault(k,[]).append(L)
bad=[(k,v) for k,v in d.items() if len(v)>1 and len(set(v))>1]
print("     条数:", len(bad))
for k,v in bad[:12]: print("     ", k, "→", v)
PY
