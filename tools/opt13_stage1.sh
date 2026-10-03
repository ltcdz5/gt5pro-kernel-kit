#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_stage1.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt13 阶段1：开分支 + 存 opt12 基准 + 改后缀 + 三项 config 关掉 + olddefconfig + 差异自证
set -e
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
B=/home/builder/opt13base
KIT=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
mkdir -p "$B"

echo "=== 1) 存 opt12 基准(symvers/.config/Image/banner) ==="
cp out/vmlinux.symvers "$B/vmlinux.symvers.opt12"
cp out/.config "$B/config.opt12"
[ -f /home/builder/opt-prune/Image.before ] && cp /home/builder/opt-prune/Image.before "$B/Image.opt12"
grep -aoE "Linux version [ -~]{0,130}" "$B/Image.opt12" | head -1
ls -l "$B" | tail -4

echo "=== 2) 开分支 opt13-trim (从退料后 d9a3e7eab) ==="
git checkout -q -b opt13-trim d9a3e7eab
echo "HEAD=$(git rev-parse --short HEAD) BR=$(git rev-parse --abbrev-ref HEAD)"

echo "=== 3) 后缀改 opt13 ==="
sed -i 's/^echo "-android14-11-o-ltcdz5-opt12"$/echo "-android14-11-o-ltcdz5-opt13"/' scripts/setlocalversion
tail -1 scripts/setlocalversion

echo "=== 4) 三项关掉的 config 片段(存档进 kit) ==="
cat > "$B/opt13.fragment" <<'EOF'
# CONFIG_UBSAN is not set
# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set
CONFIG_KFENCE=y
CONFIG_KFENCE_SAMPLE_INTERVAL=0
EOF
cat "$B/opt13.fragment"

echo "=== 5) 就地改 out/.config ==="
sed -i -e 's/^CONFIG_UBSAN=y/# CONFIG_UBSAN is not set/' \
       -e 's/^CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y/# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set/' \
       -e 's/^CONFIG_KFENCE_SAMPLE_INTERVAL=500/CONFIG_KFENCE_SAMPLE_INTERVAL=0/' out/.config
grep -E "^# CONFIG_UBSAN |^# CONFIG_INIT_ON_ALLOC|^CONFIG_KFENCE_SAMPLE_INTERVAL|^CONFIG_KFENCE=" out/.config

echo "=== 6) olddefconfig 收敛 ==="
make LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out olddefconfig > "$B/olddefconfig.log" 2>&1
tail -2 "$B/olddefconfig.log"

echo "=== 7) 配置差异自证(期望只有这三项及其依赖) ==="
diff "$B/config.opt12" out/.config | grep -E "^[<>]" | sort | uniq -c | sort -rn | head -20
echo "差异行总数=$(diff "$B/config.opt12" out/.config | grep -cE '^[<>]')"

echo "=== 8) 复核关键符号还在不在(关 UBSAN 后导出表应无变化) ==="
echo "opt12 导出总数=$(wc -l < "$B/vmlinux.symvers.opt12")"
grep -c -E "kfence_sample_interval|__kfence_pool" "$B/vmlinux.symvers.opt12"

echo "=== 9) 存档片段进 kit 仓 ==="
cp "$B/opt13.fragment" "$KIT/opt13-减脂.config.fragment"
echo done
