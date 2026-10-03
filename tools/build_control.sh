#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_control.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 控制实验: opt5 的源码 + 我的构建流程(olddefconfig + make Image), 用来区分"流程问题"还是"上游代码问题"
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 0) 先保住 opt6 产物与符号表 ==="
cp -f out/arch/arm64/boot/Image "$BASE/Image.opt6" 2>/dev/null || true
cp -f out/Module.symvers "$BASE/Module.symvers.opt6" 2>/dev/null || true
ls -la "$BASE" | tail -6

echo "=== 1) 源码切回 opt5-state(证明与 opt6 无源码差异之外的因素) ==="
git checkout -q -f opt5-state
git log -1 --format='  现在 HEAD = %h %s' | cut -c1-80
git status --porcelain | head -3

echo "=== 2) 配置: 就用 opt5 那份 config(不读 gki_defconfig) ==="
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  与 opt5 基准差异行数: $(diff "$BASE/config" out/.config | grep -cE '^[<>]')"
grep -E '^CONFIG_(DEFAULT_BBR|IP6_NF_NAT|EXTRA_FIRMWARE)\b' out/.config
tail -1 scripts/setlocalversion

echo "=== 3) 只 make Image $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -12
echo "=== 4) 产物 ==="
ls -la out/arch/arm64/boot/Image
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-56
md5sum out/arch/arm64/boot/Image
cp -f out/arch/arm64/boot/Image "$WIN/boot-CONTROL-opt5src-rebuilt.raw.img"
echo "  已复制: $WIN/boot-CONTROL-opt5src-rebuilt.raw.img"
