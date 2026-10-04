#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_prune_and_build.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 退回无关子系统 -> 用 make -k 一轮把所有编译错列全 -> 按报错文件再退回 -> 再编, 直到干净
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt10probe
W=/home/builder/opt10
cd "$T" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
mkdir -p "$OUT" "$W"

echo "=== 0) 自证 $(date) ==="
echo "  whoami=$(whoami)  $(clang --version | head -1)"

DROP_PREFIX="include/xen/ include/acpi/ include/drm/ include/sound/ include/media/ \
fs/xfs/ fs/omfs/ fs/jffs2/ fs/squashfs/ fs/nls/ crypto/ scripts/ samples/ tools/ \
net/atm/ net/can/ net/nfc/ net/rose/ net/tipc/ net/l2tp/ net/vmw_vsock/ net/bluetooth/ \
net/ieee802154/ net/phonet/ net/qr-tap/ net/smc/ net/openvswitch/ net/mac80211/ net/wireless/ \
include/linux/crypto.h include/uapi/linux/can lib/test_ lib/longest_symbol_kunit.c lib/Kconfig"
for p in $DROP_PREFIX; do git diff --name-only | grep -E "^$p"; done | sort -u > /tmp/drop1.lst
echo "=== 1) 退回无关子系统: $(wc -l < /tmp/drop1.lst) 个文件 ==="
cat /tmp/drop1.lst | sed 's/^/    /'
xargs -a /tmp/drop1.lst -r git checkout --

set_sfx() { sed -i 's/^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion; }
set_sfx
echo "  退回后改动文件=$(git diff --name-only | wc -l)  后缀=$(tail -1 scripts/setlocalversion)"
git diff --numstat | awk '{a+=$1; d+=$2} END {print "  合计 +" a " -" d}'

echo "=== 2) 第一轮 make -k $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS -k Image > /tmp/k1.log 2>&1
echo "  退出码=$?"
grep -E "error:" /tmp/k1.log | sed -E 's/^.*[[:space:]]([^ :]+):[0-9]+:[0-9]+: error: /\1: /' | sort -u > /tmp/err1.lst
echo "  报错文件数=$(wc -l < /tmp/err1.lst)"
head -30 /tmp/err1.lst | sed 's/^/    /'

echo "=== 3) 按报错文件退回(只退我们改过的) ==="
: > /tmp/drop2.lst
while read -r f; do
  [ -z "$f" ] && continue
  git diff --name-only | grep -qxF "$f" && echo "$f" >> /tmp/drop2.lst
done < /tmp/err1.lst
# 报错里出现在别的文件、但根因是我们改过的头文件: 也一并退掉这些头
git diff --name-only | grep -E '^include/linux/(crypto|xen|swait|kvm|vga|sony_laptop)' >> /tmp/drop2.lst
sort -u /tmp/drop2.lst -o /tmp/drop2.lst
echo "  本轮退回=$(wc -l < /tmp/drop2.lst) 个"
cat /tmp/drop2.lst | sed 's/^/    /'
xargs -a /tmp/drop2.lst -r git checkout --
set_sfx
echo "  现存改动文件=$(git diff --name-only | wc -l)"

echo "=== 4) 第二轮 make -k $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS -k Image > /tmp/k2.log 2>&1
RC=$?
echo "  退出码=$RC  clock skew=$(grep -ciE 'clock skew' /tmp/k2.log)"
grep -E "error:" /tmp/k2.log | head -20 | sed 's/^/  ⛔ /'
if [ $RC -ne 0 ]; then
  echo "  仍未过, 停在这里(不伪造成功)。日志尾 20 行:"; tail -20 /tmp/k2.log; exit 1
fi

echo "=== 5) 读数 + 闸门 ==="
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-64 | sed 's/^/  /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt10"
cp -f out/System.map "$OUT/System.map.opt10"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt10"
md5sum "$OUT/Image.opt10" | sed 's/^/  /'
echo "  test_task_ux 镜像内=$(strings -a $OUT/Image.opt10 | grep -c test_task_ux)  opt5基线=$(strings -a $BASE/Image.opt5 | grep -c test_task_ux)"
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt10"
echo "  config 与 opt9 差异行数=$(diff $W/config.opt9 out/.config | grep -cE '^[<>]')"

echo "=== 6) 全类型布局比对 opt10 vs opt5 ==="
python3 - <<'PY'
import struct
PAT = bytes([0x9f, 0xeb, 0x01, 0x00, 0x18, 0x00, 0x00, 0x00])
d = open('/home/builder/opt10probe/Image.opt10', 'rb').read()
h = d.find(PAT)
to, tl, so, sl = struct.unpack_from('<IIII', d, h + 8)
open('/home/builder/abi/btf/opt10.btf', 'wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt10.btf > /home/builder/abi/full/opt10.txt 2>/dev/null
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -cE '^[<>]')  (opt9=0, opt8=12)"
diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -E '^[<>]' | head -16 | sed 's/^/    /'
echo "=== 结束 $(date) ==="
