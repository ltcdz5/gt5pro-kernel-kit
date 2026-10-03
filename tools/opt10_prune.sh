#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_prune.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 把与本机无关的子系统退回 opt9 状态, 缩小 opt10 的落地面
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null

DROP_PREFIX="include/xen/ include/acpi/ include/drm/ include/sound/ include/media/ \
fs/xfs/ fs/omfs/ fs/jffs2/ fs/squashfs/ fs/nls/ lib/ crypto/ scripts/ samples/ tools/ \
net/atm/ net/can/ net/nfc/ net/rose/ net/tipc/ net/l2tp/ net/vmw_vsock/ net/bluetooth/ \
net/ieee802154/ net/phonet/ net/qr-tap/ net/smc/ net/openvswitch/ net/mac80211/ net/wireless/ \
include/linux/crypto.h include/linux/crypto_internal.h include/uapi/linux/can"

echo "=== 退回前 ==="
echo "  改动文件数=$(git diff --name-only | wc -l)"
for p in $DROP_PREFIX; do git diff --name-only | grep -E "^$p" ; done | sort -u > /tmp/drop.lst
wc -l < /tmp/drop.lst | sed 's/^/  将被退回的文件数=/'
cat /tmp/drop.lst | sed 's/^/    /'
xargs -a /tmp/drop.lst -r git checkout --
# setlocalversion 的 -opt10 后缀不能被退掉, 单独保一下
sed -i 's/^echo "-android14-11-o-ltcdz5-clean"$/echo "-android14-11-o-ltcdz5-opt10"/;s/^echo "-android14-11-o-ltcdz5-opt9"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion
echo "=== 退回后 ==="
echo "  改动文件数=$(git diff --name-only | wc -l)"
git diff --numstat | awk '{a+=$1; d+=$2} END {print "  合计 +" a " -" d}'
echo "  后缀=$(tail -1 scripts/setlocalversion)"
echo "  剩余文件:"
git diff --name-only | sed 's/^/    /'
echo "=== 新增导出自检 ==="
echo "  行数=$(git diff -U0 | grep -cE '^\+[[:space:]]*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|DEFINE_HOOK|DECLARE_HOOK)' || true)"
