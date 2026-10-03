#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt9.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt9 = opt7-clean(诚实 config.gz 的干净基线) + 与 opt8 相同的 13 文件上游子集
# 目的: 一版同时拿到"上游修复"和"config.gz 不再谎报"。只编不刷。
set -u
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt9probe
PATCH=/home/builder/opt6_upstream.patch
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo '=== 0) 自证 ==='
echo "  whoami=$(whoami)"; clang --version | head -1 | sed 's/^/  /'
DROP=$(head -1 /home/builder/opt8.files)
echo "  沿用 opt8 的闭包裁剪清单(12 个): $DROP"

echo '=== 1) 从 opt7-clean 开 opt9, 套同一子集 ==='
git checkout -q -f opt7-clean
git checkout -q -B opt9-clean-upstream
EXC=""; for f in ${DROP//,/ }; do EXC="$EXC --exclude=$f"; done
git apply --check $EXC "$PATCH" && echo "  干跑 OK"
git apply $EXC "$PATCH"
echo "  改动文件=$(git status --porcelain | grep -c '^ M')  其中头文件=$(git status --porcelain | grep '^ M' | grep -c '\.h$')"
echo "  config_fix 还在不在(应无): $(grep -c config_fix kernel/Makefile)"

echo '=== 2) 后缀 -opt9, 配置基准用 opt8 实测 config(=opt5 等价) ==='
sed -i 's/^echo "-android14-11-o-ltcdz5-clean"$/echo "-android14-11-o-ltcdz5-opt9"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 3) 归一时间戳并开编 $(date) ==="
find . \( -path ./out -o -path ./.git \) -prune -o -type f -exec touch {} + 2>/dev/null
rm -f out/Module.symvers
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tee /tmp/o9.log | grep -iE 'clock skew|error' | head -4
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | grep -ciE 'clock skew' | sed 's/^/  第二遍 skew 警告数=/'

echo '=== 4) 读数 + 闸门 ==='
mkdir -p "$OUT"
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-58
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt9"; cp -f out/System.map "$OUT/System.map.opt9"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt9"
md5sum "$OUT/Image.opt9"
echo "  test_task_ux 镜像内出现=$(strings -a $OUT/Image.opt9 | grep -c test_task_ux) 基线=$(strings -a $BASE/Image.opt5 | grep -c test_task_ux)"
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt9"
echo "=== 5) 布局比对(opt9 vs opt5) ==="
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
d=open('/home/builder/opt9probe/Image.opt9','rb').read(); h=d.find(PAT)
to,tl,so,sl=struct.unpack_from('<IIII', d, h+8)
open('/home/builder/abi/btf/opt9.btf','wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt9.btf > /home/builder/abi/full/opt9.txt 2>/dev/null
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt9.txt | grep -cE '^[<>]')  (opt8 是 12 行)"
echo "=== 6) repack ==="
cd /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py "$OUT/Image.opt9" /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/备件-opt9-未刷.img 2>&1 | tail -4
echo "=== 结束 $(date) ==="
