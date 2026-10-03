#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_stage2_build.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt13 阶段2：提交状态 + 编 Image（日志落 ~/opt13base/build.log）
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
B=/home/builder/opt13base
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null

echo "=== 分支/改动确认 ==="
echo "BR=$(git rev-parse --abbrev-ref HEAD) HEAD=$(git rev-parse --short HEAD)"
git status --short
git commit -q -a -m "opt13 = opt12(d9a3e7eab) + 减脂三项(UBSAN 全关 / INIT_ON_ALLOC_DEFAULT_ON 关 / KFENCE 采样间隔 0)，后缀 -opt13；config 差 18 行全部属这三项及其依赖，导出符号基准 15388 个不变"
echo "提交后 HEAD=$(git rev-parse --short HEAD)"

echo "=== clock skew 自查 ==="
echo "skew=$(find out -newermt "$(date)" 2>/dev/null | wc -l)"

echo "=== 开编 $(date '+%H:%M:%S') ==="
make -j"$(nproc --all)" LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- 'CC=ccache clang' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image > "$B/build.log" 2>&1
echo "make_rc=$? errors=$(grep -cE '(: fatal error:|: error:)' "$B/build.log")"
tail -3 "$B/build.log"
grep -aoE "Linux version [ -~]{0,130}" out/arch/arm64/boot/Image | head -1
ls -l out/arch/arm64/boot/Image
