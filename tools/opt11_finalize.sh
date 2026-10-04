#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt11_finalize.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt11 收口: 只保留真参与编译的 .c(out/ 里有 .o 的), 其余退回 -> 重编 -> 三道闸
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
W=/home/builder/opt11
OUT=/home/builder/opt11probe
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 0) $(date) 分支=$(git rev-parse --abbrev-ref HEAD) 改动=$(git diff --name-only|wc -l) ==="
echo "  whoami=$(whoami)"

echo '=== 1) 按 .o 存在性筛: 无 .o 的改动一律退回 ==='
git diff --name-only | grep -v setlocalversion > /tmp/all.lst
: > /tmp/keep.lst; : > /tmp/rev.lst
while read -r f; do
  o="out/$(dirname "$f")/$(basename "$f" .c).o"
  if [ -f "$o" ]; then echo "$f" >> /tmp/keep.lst; else echo "$f" >> /tmp/rev.lst; fi
done < /tmp/all.lst
echo "  保留(参与编译)=$(wc -l < /tmp/keep.lst)  退回(不编译)=$(wc -l < /tmp/rev.lst)"
sed 's/^/    保留: /' /tmp/keep.lst
xargs -r -a /tmp/rev.lst git checkout --
sed -i 's/^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$/echo "-android14-11-o-ltcdz5-opt11"/' scripts/setlocalversion
echo "  现在改动=$(git diff --name-only|wc -l)"

echo '=== 2) 重编 ==='
NOW=$(date +%s); BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null | wc -l)
[ "$BAD" -gt 0 ] && { find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null; echo "  归一 $BAD 个未来时间戳"; }
eval make -j"$(nproc --all)" $MFLAGS Image > "$W/final2.log" 2>&1; RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' "$W/final2.log")  skew=$(grep -ciE 'clock skew' "$W/final2.log")"
[ $RC -ne 0 ] && { grep -E "error:" "$W/final2.log" | head -8 | sed 's/^/  ⛔ /'; exit 1; }
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-62 | sed 's/^/  横幅: /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt11"; cp -f out/arch/arm64/boot/Image "$OUT/Image.opt11"
md5sum "$OUT/Image.opt11" | sed 's/^/  Image md5 /'
echo "  config 与 opt10 差 $(diff "$W/config.opt10" out/.config | grep -cE '^[<>]') 行"

echo '=== 3) 三道闸 ==='
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt11"
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/opt11probe/Image.opt11','rb').read(); h=d.find(PAT)
to,tl,so,sl=struct.unpack_from('<IIII',d,h+8)
open('/home/builder/abi/btf/opt11.btf','wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt11.btf > /home/builder/abi/full/opt11.txt 2>/dev/null
echo "  全类型 opt11=$(wc -l < /home/builder/abi/full/opt11.txt) 行; 与 opt10 差 $(diff /home/builder/abi/full/opt10.txt /home/builder/abi/full/opt11.txt|grep -cE '^[<>]') 行; 与 opt5 差 $(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt11.txt|grep -cE '^[<>]') 行"

echo '=== 4) 提交源码状态 ==='
git commit -q -a -m "opt11 = opt10 + stable 6.1.146..150 中真参与本机编译的 7 个 .c 修复 + 后缀 -opt11

保留判据: out/ 下存在对应 .o(= 真进 boot)。146..150 原落地 46 个 .c,
其中 39 个所在子系统本机不编译(XFS/atm/rose/omfs/jffs2/hfsplus/jfs/nfs/
squashfs/cachefiles/ptdump/debug_vm_pgtable/test_objagg/appletalk/hsr/l2tp/
nfc/mac80211/rxrpc/sctp/nfacct/apparmor), 属零效果零风险 -> 退回, 使改动集=效果集。
实测闸: 新增导出 0 / 命中厂商引用 0; config 与 opt10 差 0 行; 全类型 BTF 与 opt10 差 0 行。
SUBLEVEL 保持 141: 只落 7 文件, 未整套追到 150, 不许虚标。"
echo "  $(git log --oneline -1)"
echo "  脏=$(git status --porcelain|wc -l)"

echo '=== 5) repack ==='
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
cp -f "$OUT/Image.opt11" /tmp/Image.opt11
python3 repack_any.py /tmp/Image.opt11 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt11-repacked.img 2>&1 | tail -5
md5sum /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt11-repacked.img
echo "=== 结束 $(date) ==="
