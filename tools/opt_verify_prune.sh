#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_verify_prune.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 验退料：退掉 28 个白改后重编，证明"本机内核镜像内容没变 => 已刷的 opt12 仍是这块树的正确产物，不用重刷"
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/home/builder/opt-prune
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1

echo "clang=$(which clang)"
echo "clock_skew=$(find out -newermt "$(date)" 2>/dev/null | wc -l)"
echo "=== 开编 $(date '+%H:%M:%S') ==="
make -j"$(nproc --all)" LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- 'CC=ccache clang' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image > "$P/build.log" 2>&1
rc=$?
echo "make_rc=$rc  errors=$(grep -cE '(: fatal error:|: error:)' "$P/build.log")"
tail -3 "$P/build.log"
diff "$P/System.map.before" out/System.map > "$P/systemmap.diff" 2>&1
echo "System.map 差异行数=$(wc -l < "$P/systemmap.diff")"
echo "Image md5 退料后 = $(md5sum out/arch/arm64/boot/Image | cut -d' ' -f1)"
echo "Image md5 退料前 = $(md5sum "$P/Image.before" | cut -d' ' -f1)"
echo "banner: $(grep -aoE 'Linux version [ -~]{0,120}' out/arch/arm64/boot/Image | head -1)"
