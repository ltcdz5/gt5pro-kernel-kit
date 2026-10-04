#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt10_stable.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt10 = opt9 + linux-6.1.y stable 142..145 增量(裁剪到相关目录) -> 编 -> 过闸 -> 比布局
set -u
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
P=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/patches
OUT=/home/builder/opt10probe
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$PWD" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 0) 自证 ==="; echo "  whoami=$(whoami)"; clang --version | head -1 | sed 's/^/  /'

echo "=== 1) 开分支 opt10-stable145 (从 opt9) ==="
git checkout -q -f opt9-clean-upstream
git checkout -q -B opt10-stable145
git status --porcelain | head -3

for v in 142 143 144 145; do
  echo "=== 2) 套 patch-6.1.$v (裁剪) ==="
  xz -dc "$P/p$v.xz" > /tmp/full-$v 2>/dev/null
  python3 - "$v" <<'PY'
import sys, re
v = sys.argv[1]
KEEP = re.compile(r'^(mm|fs|kernel|net|lib|block|crypto|include|arch/arm64|arch/x86/mm)/')
DROP = re.compile(r'^(drivers/|Documentation/|sound/|tools/|samples/|certs/|usr/|io_uring/)')
out, keep = [], False
for L in open('/tmp/full-%s' % v, errors='replace'):
    m = re.match(r'^diff -u N/N (?:--label )?a/(\S+)', L) or re.match(r'^diff --git a/(\S+)', L)
    if m:
        f = m.group(1)
        keep = bool(KEEP.match(f)) and not DROP.match(f)
    if keep:
        out.append(L)
open('/tmp/fit-%s' % v, 'w').writelines(out)
n = sum(1 for L in out if L.startswith('diff '))
print("  6.1.%s: 保留文件块=%d" % (v, n))
PY
  before=$(find /tmp/rej-$v >/dev/null 2>&1; echo 0)
  patch -p1 -N --no-backup-if-mismatch -r /tmp/rej-$v < /tmp/fit-$v > /tmp/plog-$v 2>&1
  echo "  冲突片段数=$(grep -c 'FAILED' /tmp/plog-$v)   rej字节=$(du -b /tmp/rej-$v 2>/dev/null | cut -f1)"
  grep 'FAILED' /tmp/plog-$v | head -5 | sed 's/^/      /'
  rm -f /tmp/rej-$v /tmp/fit-$v /tmp/full-$v
done

echo "=== 3) 版本: Makefile 与后缀 ==="
grep -E '^SUBLEVEL' Makefile | tr -d '\t' | sed 's/^/  /'
sed -i 's/^echo "-android14-11-o-ltcdz5-opt9"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion
tail -1 scripts/setlocalversion | sed 's/^/  /'
echo "  实际改动文件数=$(git status --porcelain | wc -l)"
echo "  其中头文件=$(git status --porcelain | grep -cE '\.h$')"

echo "=== 4) 配置与编译 $(date) ==="
find . \( -path ./out -o -path ./.git \) -prune -o -type f -exec touch {} + 2>/dev/null
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig >/dev/null 2>&1
eval make -j"$(nproc --all)" $MFLAGS Image > /tmp/opt10build.log 2>&1
rc=$?
echo "  编译退出码=$rc"
grep -iE 'error:|clock skew' /tmp/opt10build.log | head -6 | sed 's/^/    /'
tail -3 /tmp/opt10build.log | sed 's/^/    /'
if [ $rc -ne 0 ]; then echo "  === 编译失败, 不进入闸门 ==="; exit 1; fi

echo "=== 5) 读数 + 闸门 ==="
mkdir -p "$OUT"
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-70 | sed 's/^/  /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt10"; cp -f out/System.map "$OUT/System.map.opt10"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt10"
md5sum "$OUT/Image.opt10" | sed 's/^/  /'
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt10"

echo "=== 6) 布局比对(opt10 vs opt5) ==="
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/opt10probe/Image.opt10','rb').read(); h=d.find(PAT)
to,tl,so,sl=struct.unpack_from('<IIII', d, h+8)
open('/home/builder/abi/btf/opt10.btf','wb').write(d[h:h+24+to+tl+so+sl])
print("  BTF @%#x total=%d" % (h, 24+to+tl+so+sl))
PY
pahole /home/builder/abi/btf/opt10.btf > /home/builder/abi/full/opt10.txt 2>/dev/null
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -cE '^[<>]')"
diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -E '^[<>] .*(size:|struct )' | head -16 | sed 's/^/    /'
for s in task_struct mm_struct vm_area_struct file inode dentry eventpoll signal_struct; do
  a=$(pahole -C "$s" /home/builder/abi/btf/opt5-ltcdz5-raw.btf 2>/dev/null | grep -o 'size: [0-9]*' | head -1)
  b=$(pahole -C "$s" /home/builder/abi/btf/opt10.btf 2>/dev/null | grep -o 'size: [0-9]*' | head -1)
  [ "$a" = "$b" ] && f=同 || f="★变了"
  printf '  %-18s opt5=%-11s opt10=%-11s %s\n' "$s" "${a:-无}" "${b:-无}" "$f"
done
echo "=== 结束 $(date) ==="
