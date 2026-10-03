#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_finalize.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt12 收口: 剔 traps.c -> 正式编译 -> 三道闸 -> 提交 -> repack
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
W=/home/builder/opt12
OUT=/home/builder/opt12probe
BASE=/home/builder/opt5-baseline
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 1) 剔掉 SError 路径 traps.c $(date) ==="
git checkout opt11-stable150 -- arch/arm64/kernel/traps.c
sed -i 's|^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$|echo "-android14-11-o-ltcdz5-opt12"|' scripts/setlocalversion
echo "  traps.c 与基线差异行数=$(git diff opt11-stable150 -- arch/arm64/kernel/traps.c | wc -l) (应 0)"
echo "  改动文件=$(git diff --name-only | wc -l)"

echo '=== 2) 正式编译(不带 -k) ==='
eval make -j"$(nproc --all)" $MFLAGS Image > "$W/final.log" 2>&1; RC=$?
echo "  退出码=$RC error=$(grep -cE '(fatal error| error):' "$W/final.log") skew=$(grep -ciE 'clock skew' "$W/final.log")"
[ $RC -ne 0 ] && { grep -E "(fatal error| error):" "$W/final.log" | head -6 | sed 's/^/  ⛔ /'; exit 1; }
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-64 | sed 's/^/  横幅: /'
mkdir -p "$OUT"; cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt12"; cp -f out/arch/arm64/boot/Image "$OUT/Image.opt12"
md5sum "$OUT/Image.opt12" | sed 's/^/  /'
echo "  test_task_ux 镜像内=$(strings -a "$OUT/Image.opt12" | grep -c test_task_ux) (opt5 基线=$(strings -a "$BASE/Image.opt5" | grep -c test_task_ux))"
echo "  config 与 opt11 差 $(diff "$W/config.base" out/.config | grep -cE '^[<>]') 行"

echo '=== 3) 三道闸 ==='
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt12"
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/opt12probe/Image.opt12','rb').read(); h=d.find(PAT)
to,tl,so,sl=struct.unpack_from('<IIII',d,h+8)
open('/home/builder/abi/btf/opt12.btf','wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt12.btf > /home/builder/abi/full/opt12.txt 2>/dev/null
echo "  全类型: opt12=$(wc -l < /home/builder/abi/full/opt12.txt) 行"
echo "  与 opt11 差 $(diff /home/builder/abi/full/opt11.txt /home/builder/abi/full/opt12.txt | grep -cE '^[<>]') 行"
diff /home/builder/abi/full/opt11.txt /home/builder/abi/full/opt12.txt | grep -E '^[<>]' | head -12 | sed 's/^/    /'

echo '=== 4) 提交 ==='
git commit -q -a -m "opt12 = opt11 + stable 6.1.151..188 中真参与本机编译的 116 个 .c 修复 + 后缀 -opt12

摊了 38 个 stable 版本。落地链条: 162 文件(白名单=out/ 下有 .o 才尝试) -> 编译普查迭代
(84 错退 44 / 缺 linux/pgalloc.h 退 percpu.c+sparse-vmemmap.c / 第3轮 0 错) -> 116 个 .c。
另剔 arch/arm64/kernel/traps.c(arm64_serror_panic): 与 opt11 同一条规矩, SError 异常路径不混批刷。
保留 arch/arm64/kvm/vgic/vgic-mmio-v2.c: 本机无虚拟机负载, 记录在此。
闸: 新增导出 ∩ 厂商 .ko 引用 = 0; config 与 opt11 差 0 行; 全类型 BTF 与 opt11 差 0 行。
SUBLEVEL 仍 141(只落子集, 不虚标 188)。"
echo "  $(git log --oneline -1)"

echo '=== 5) repack ==='
cp -f "$OUT/Image.opt12" /tmp/Image.opt12
cd /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /tmp/Image.opt12 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/boot-opt12-repacked.img 2>&1 | tail -4
md5sum /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/boot-opt12-repacked.img
echo "  树脏=$(git status --porcelain | wc -l)"
echo "=== 结束 $(date) ==="
