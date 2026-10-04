#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt6a2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt6a2 = A 组去掉 fs/f2fs/checkpoint.c(纯取证用: 证明凶手就是 f2fs 那段优先级代码)
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
A2=(block/blk-mq.c include/linux/blk-mq.h include/linux/file.h android/abi_gki_aarch64_oplus)

echo "=== 1) 回到干净的 opt5-state 再开 opt6a2 ==="
git checkout -q -f opt5-state
git checkout -q -B opt6a2
git status --porcelain | grep -vE '\.patch\.|\.bak|^\?\? ' | head -3 || true
echo "  基线 HEAD = $(git rev-parse --short HEAD)"

echo "=== 2) 只应用这 ${#A2[@]} 个文件(不含 f2fs) ==="
INC=""; for f in "${A2[@]}"; do INC="$INC --include=$f"; done
git apply --check $INC /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply $INC /home/builder/opt6_upstream.patch
git status --porcelain | grep '^ M' | sed 's/^/    已改: /'

echo "=== 3) 后缀 -a2, 配置用 opt5 的 ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a2"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数: $(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 4) 编 Image $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -5
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-50
echo "=== 5) 确认 f2fs 那行没进来 ==="
grep -c "test_task_ux" fs/f2fs/checkpoint.c | sed 's/^/  fs\/f2fs\/checkpoint.c 里 test_task_ux 出现次数(应为 0): /'
grep -c "test_task_ux" block/blk-mq.c | sed 's/^/  block\/blk-mq.c 里(应有定义+export): /'
cp -f out/arch/arm64/boot/Image "$WIN/不能刷-裸内核/boot-opt6a2-upstream.raw.img"
md5sum out/arch/arm64/boot/Image
