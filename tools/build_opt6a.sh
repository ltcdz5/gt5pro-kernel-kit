#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt6a.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt6-A 组: 只打"块层+f2fs+属性上下文"这 5 个文件的上游改动(风险最独立、且已确认代码路径是活的)
# CONFIG_BLK_MQ_USE_LOCAL_THREAD=y 且 test_task_ux() 定义在 block/blk-mq.c:2349 => f2fs 那段新分支不是死代码
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
A=(fs/f2fs/checkpoint.c block/blk-mq.c include/linux/blk-mq.h include/linux/file.h android/abi_gki_aarch64_oplus)

echo "=== 1) 以 opt5-state 为底, 开 opt6a 分支 ==="
git checkout -q -f opt5-state
git checkout -q -B opt6a
echo "  HEAD=$(git rev-parse --short HEAD)"

echo "=== 2) 只应用 A 组这 ${#A[@]} 个文件 ==="
INC=""; for f in "${A[@]}"; do INC="$INC --include=$f"; done
git apply --check $INC /home/builder/opt6_upstream.patch && echo "  干跑 OK"
git apply $INC /home/builder/opt6_upstream.patch
git diff --name-only | sed 's/^/    已改: /'

echo "=== 3) 版本后缀 opt6a, 配置仍用 opt5 的 ==="
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-a"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  config 与 opt5 差异行数: $(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 4) 编 Image $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image 2>&1 | tail -6
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-58
cp -f out/arch/arm64/boot/Image "$WIN/boot-opt6a-upstream.raw.img"
echo "  已复制 $WIN/boot-opt6a-upstream.raw.img"
