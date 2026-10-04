#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_go.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
mkdir -p /home/builder/opt12 /home/builder/opt12probe
export OPT=opt12
export BASE=opt11-stable150
export VERS="$(seq 151 188 | tr '\n' ' ')"
echo "启动参数: OPT=$OPT BASE=$BASE VERS=$VERS"
exec bash /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/opt_stable_iterate.sh
