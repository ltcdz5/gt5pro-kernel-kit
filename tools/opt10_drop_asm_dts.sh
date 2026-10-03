#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_drop_asm_dts.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
git diff --name-only | grep -E '(\.S|\.dts|\.dtsi|Kconfig)$|^arch/arm64/kernel/probes/uprobes\.c$' > /tmp/drop3.lst
echo "本轮退回 $(wc -l < /tmp/drop3.lst) 个:"
sed 's/^/  - /' /tmp/drop3.lst
xargs -a /tmp/drop3.lst -r git checkout --
sed -i 's/^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion
echo "剩余改动文件=$(git diff --name-only | wc -l)"
git diff --name-only | grep -v setlocalversion | sed 's/^/  /'
