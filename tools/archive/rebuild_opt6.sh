#!/bin/bash
# 用 opt5 的实测 config 作为唯一基准重做 opt6 配置并重编(绕开 builder 的 defconfig 堆积)
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
MFLAGS="LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC=\"ccache clang\" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error"

echo "=== 1) 还原干净的 gki_defconfig(不再让 builder 追加块说话) ==="
git checkout HEAD -- arch/arm64/configs/gki_defconfig
echo "  gki_defconfig 行数: $(wc -l < arch/arm64/configs/gki_defconfig)"
echo "  重复键数: $(grep '^CONFIG_' arch/arm64/configs/gki_defconfig | sed 's/=.*//' | sort | uniq -d | wc -l)"

echo "=== 2) 基准 config 自检(opt5 那份必须含我们要的项) ==="
grep -E "^CONFIG_(IP6_NF_NAT|DEFAULT_BBR|DEFAULT_TCP_CONG|DEFAULT_FQ|NET_SCH_DEFAULT|TCP_CONG_BRUTAL|EXTRA_FIRMWARE)\b" "$BASE/config"
grep -c . "$BASE/config" | sed 's/^/  基准 config 行数: /'

echo "=== 3) 以 opt5 config 为输入 olddefconfig(新符号取默认, 老符号一律保留) ==="
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" $MFLAGS olddefconfig
echo "  --- olddefconfig 后与基准的差异(应只有上游新增符号) ---"
diff "$BASE/config" out/.config | grep -E "^[<>]" | head -20
echo "  差异行数: $(diff "$BASE/config" out/.config | grep -cE '^[<>]')"
grep -E "^CONFIG_(IP6_NF_NAT|DEFAULT_BBR|DEFAULT_FQ|TCP_CONG_BRUTAL|EXTRA_FIRMWARE)\b" out/.config

echo "=== 4) 重编 Image $(date) ==="
eval make -j"$(nproc --all)" $MFLAGS Image
echo "=== 结束 $(date) ==="
ls -la out/arch/arm64/boot/Image
md5sum out/arch/arm64/boot/Image
