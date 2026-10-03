#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt8_fix_and_layout.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 1) 消 clock skew: 把所有源码时间戳归一后重编, 确认警告消失
# 2) 抽 opt8 的 BTF, 与 opt5 基线做全类型布局比对(重点看 mm_types.h 动了哪些 struct)
set -u
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt8probe
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo '=== 1) 归一时间戳(把整个树 mtime 设为现在) ==='
find . -path ./out -prune -o -type f -newermt "$(date +%Y-%m-%d)" -print 2>/dev/null | wc -l | sed 's/^/  未来时间戳文件数=/'
find . \( -path ./out -o -path ./.git \) -prune -o -type f -exec touch {} + 2>/dev/null
touch include/linux/mm_types.h include/linux/file.h fs/eventpoll.c mm/memory.c mm/filemap.c net/unix/garbage.c arch/arm64/mm/fault.c

echo '=== 2) 重编(第一遍) ==='
date
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | grep -iE 'clock skew|error|warning: .*incomplete' | head -5
echo "  第一遍结束 $(date)"
echo '=== 3) 再编一遍直到 no work / 无 skew 警告 ==='
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tee /tmp/o8b.log | grep -iE 'clock skew|error' | head -5
echo "  skew 警告残留=$(grep -ci 'clock skew' /tmp/o8b.log)  第二遍结束 $(date)"

echo '=== 4) 存档 ==='
mkdir -p "$OUT"
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-58
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt8"
cp -f out/System.map "$OUT/System.map.opt8"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt8"
md5sum "$OUT/Image.opt8"
echo "  test_task_ux 出现=$(strings -a $OUT/Image.opt8 | grep -c test_task_ux)  基线=$(strings -a $BASE/Image.opt5 | grep -c test_task_ux)"

echo '=== 5) 抽 BTF 做全类型布局比对(opt8 vs opt5) ==='
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/opt8probe/Image.opt8','rb').read()
h=d.find(PAT)
type_off,type_len,str_off,str_len=struct.unpack_from('<IIII', d, h+8)
total=24+type_off+type_len+str_off+str_len
open('/home/builder/abi/btf/opt8.btf','wb').write(d[h:h+total])
print("  BTF @%#x total=%d" % (h,total))
PY
pahole /home/builder/abi/btf/opt8.btf > /home/builder/abi/full/opt8.txt 2>/dev/null
pahole /home/builder/abi/btf/opt5-ltcdz5-raw.btf > /home/builder/abi/full/opt5.txt 2>/dev/null
echo "  行数: opt8=$(wc -l < /home/builder/abi/full/opt8.txt)  opt5=$(wc -l < /home/builder/abi/full/opt5.txt)"
diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt8.txt > /tmp/o8lay.diff
echo "  全类型差异行数=$(grep -cE '^[<>]' /tmp/o8lay.diff)"
python3 - <<'PY'
import re
d=open('/tmp/o8lay.diff',errors='replace').read().split('\n')
cur=None; res={}
for L in d:
    m=re.match(r'^[<>] \s*(struct|union)\s+([A-Za-z0-9_]+)\s*\{',L)
    if m: cur=m.group(2); res.setdefault(cur,0)
    if cur: res[cur]+=1
sz=re.findall(r'size: (\d+)', '\n'.join(d))
print("  涉及类型数=%d -> %s" % (len(res), list(res)[:12]))
PY
echo '--- 差异摘要(前 30 行) ---'
head -30 /tmp/o8lay.diff | sed 's/^/   /'
echo '=== 6) 关键结构体尺寸点名对比 ==='
for s in vm_area_struct mm_struct page_owner eventpoll anon_vma folio scd_req_args; do
  a=$(pahole -C "$s" /home/builder/abi/btf/opt5-ltcdz5-raw.btf 2>/dev/null | grep -o 'size: [0-9]*' | head -1)
  b=$(pahole -C "$s" /home/builder/abi/btf/opt8.btf 2>/dev/null | grep -o 'size: [0-9]*' | head -1)
  flag=$([ "$a" = "$b" ] && echo 同 || echo 变)
  printf '  %-18s opt5=%-10s opt8=%-10s %s\n' "$s" "${a:-无}" "${b:-无}" "$flag"
done
