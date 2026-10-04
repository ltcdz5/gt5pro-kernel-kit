#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt11_drop_traps.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt11 收口第 2 步: 剔掉 arch/arm64/kernel/traps.c(SError 异常路径, 单独归因) -> 重编 -> 三道闸 -> repack
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
W=/home/builder/opt11
OUT=/home/builder/opt11probe
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 0) $(date) HEAD=$(git rev-parse --short HEAD) ==="
echo "  whoami=$(whoami)"
echo '=== 1) 退回 traps.c, 核对改动集 ==='
git checkout HEAD~1 -- arch/arm64/kernel/traps.c 2>/dev/null || git checkout opt10-stable145 -- arch/arm64/kernel/traps.c
echo "  相对 opt10 的改动文件:"
git diff --name-only opt10-stable145 HEAD 2>/dev/null | sed 's/^/    提交里: /'
echo "  工作区里 traps.c 是否已回到 opt10 状态: $(git diff opt10-stable145 -- arch/arm64/kernel/traps.c | wc -l) 行差异(应为 0)"
git commit -q -a --amend -m "opt11 = opt10 + stable 6.1.146..150 中真参与本机编译的 6 个 .c 修复 + 后缀 -opt11

保留判据: out/ 下存在对应 .o(= 真进 boot)。146..150 原落地 46 个 .c:
  - 39 个所在子系统本机不编译(XFS/atm/rose/omfs/jffs2/hfsplus/jfs/nfs/squashfs/
    cachefiles/ptdump/debug_vm_pgtable/test_objagg/appletalk/hsr/l2tp/nfc/
    mac80211/rxrpc/sctp/nfacct/apparmor) -> 退回(零效果零风险, 不留在改动集里充数)
  - arch/arm64/kernel/traps.c 的 arm64_serror_panic 那一行 -> 亦剔除,
    理由: 它动 SError 致命异常路径, 按\"一次刷机只判一件事\"不许与其它改动同批刷
保留 6 个: uprobes.c traps已除外 fs/buffer.c kernel/dma/pool.c security/inode.c
            net/bluetooth/{eir,mgmt_util}.c(注: 本机蓝牙走厂商用户态栈, 这 2 个预期无效果)
实测闸: 新增导出 0 / 命中厂商引用 0; config 与 opt10 差 0 行; 全类型 BTF 与 opt10 差 0 行。
SUBLEVEL 保持 141: 只落 6 文件, 未整套追到 150, 不许虚标。"
echo "  改后提交: $(git log --oneline -1)"
echo "  实际改动文件=$(git diff --name-only opt10-stable145 | grep -v setlocalversion | wc -l)"
git diff --name-only opt10-stable145 | sed 's/^/    /'

echo '=== 2) 重编 ==='
NOW=$(date +%s); BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null | wc -l)
[ "$BAD" -gt 0 ] && find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null
eval make -j"$(nproc --all)" $MFLAGS Image > "$W/final3.log" 2>&1; RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' "$W/final3.log")  skew=$(grep -ciE 'clock skew' "$W/final3.log")"
[ $RC -ne 0 ] && { grep -E "error:" "$W/final3.log" | head -6 | sed 's/^/  ⛔ /'; exit 1; }
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-62 | sed 's/^/  横幅: /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt11"; cp -f out/arch/arm64/boot/Image "$OUT/Image.opt11"
md5sum "$OUT/Image.opt11" | sed 's/^/  /'
echo "  config 与 opt10 差 $(diff "$W/config.opt10" out/.config | grep -cE '^[<>]') 行"
echo "  traps.c 在镜像里的痕迹核对: 与 opt10 同则应无差异"

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
echo "  全类型 opt11=$(wc -l < /home/builder/abi/full/opt11.txt) 行; 与 opt10 差 $(diff /home/builder/abi/full/opt10.txt /home/builder/abi/full/opt11.txt|grep -cE '^[<>]') 行"

echo '=== 4) repack ==='
cp -f "$OUT/Image.opt11" /tmp/Image.opt11
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /tmp/Image.opt11 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt11-repacked.img 2>&1 | tail -4
md5sum /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt11-repacked.img
echo "  脏=$(git status --porcelain|wc -l)"
echo "=== 结束 $(date) ==="
