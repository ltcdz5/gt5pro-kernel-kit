#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt6a3.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# -a3 = 三版砖的交集 4 个文件, 但去掉 android/abi_gki_aarch64_oplus
# 一次刷机判两件事: 开机=>凶手是导出白名单; 循环=>凶手是 blk-mq/file.h 那几行本身
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
A3=(block/blk-mq.c include/linux/blk-mq.h include/linux/file.h)

echo "=== 0) 假设的前提: 本机是否真的在用白名单裁剪导出 ==="
grep -E 'CONFIG_TRIM_UNUSED_KSYMS|CONFIG_UNUSED_KSYMS_WHITELIST|CONFIG_MODVERSIONS|CONFIG_KALLSYMS=' "$BASE/config" | sed 's/^/  /'

echo "=== 1) opt5-state + 只套这 3 个代码文件(不含白名单) ==="
git checkout -q -f opt5-state
git checkout -q -B a3-split
INC=""; for f in "${A3[@]}"; do INC="$INC --include=$f"; done
git apply --check $INC /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply $INC /home/builder/opt6_upstream.patch
git status --porcelain | grep '^ M' | sed 's/^/    已改: /'
echo "  白名单文件有没有被动: $(git status --porcelain | grep -c abi_gki_aarch64_oplus)"

echo "=== 2) 后缀 -a3, 配置用 opt5 实测 config 走 olddefconfig ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a3"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 3) 开编 $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -4

echo "=== 4) 存档读数 ==="
mkdir -p /home/builder/a3probe
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-52
cp -f out/Module.symvers /home/builder/a3probe/Module.symvers.a3
cp -f out/System.map     /home/builder/a3probe/System.map.a3
cp -f out/arch/arm64/boot/Image /home/builder/a3probe/Image.a3
echo "  导出数: opt5=$(cut -f2 "$BASE/Module.symvers" | sort -u | wc -l)  a3=$(cut -f2 /home/builder/a3probe/Module.symvers.a3 | sort -u | wc -l)"
echo "  与 opt5 比消失的导出=$(comm -23 <(cut -f2 "$BASE/Module.symvers" | sort -u) <(cut -f2 /home/builder/a3probe/Module.symvers.a3 | sort -u) | wc -l)"
md5sum /home/builder/a3probe/Image.a3

echo "=== 5) repack 成可刷 img(命名标明是待判试验件) ==="
cd /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools
python3 repack_any.py /home/builder/a3probe/Image.a3 "$WIN/试验-a3-未真机验证.img" 2>&1 | tail -6
cp -f /home/builder/a3probe/Image.a3 "$WIN/不能刷-裸内核/boot-opt6a3-split.raw.img"
echo "=== 结束 $(date) ==="
