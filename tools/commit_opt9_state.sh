#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/commit_opt9_state.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 把手机上正在跑的 opt9 源码状态精确重建并【提交】(之前只在工作区, 被 checkout -f 清掉过)
set -eu
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$TREE"
git config --global --add safe.directory "$TREE" 2>/dev/null
DROP=$(head -1 /home/builder/opt8.files)
echo "  闭包裁剪清单(12): $DROP"
echo "  当前: $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD) 脏=$(git status --porcelain | wc -l)"

git checkout -q -f opt7-clean
git checkout -q -B opt9-clean-upstream
EXC=""; for f in ${DROP//,/ }; do EXC="$EXC --exclude=$f"; done
git apply --check $EXC /home/builder/opt6_upstream.patch
git apply $EXC /home/builder/opt6_upstream.patch
sed -i 's/^echo "-android14-11-o-ltcdz5-clean"$/echo "-android14-11-o-ltcdz5-opt9"/' scripts/setlocalversion

echo "  改动文件=$(git status --porcelain | wc -l)  头文件=$(git status --porcelain | grep -cE '\.h$')"
echo "  版本串 = $(make kernelversion 2>/dev/null)$(sed -n 's/^echo "\(.*\)"$/\1/p' scripts/setlocalversion | tail -1)"
git add -A
git -c user.name=ltcdz5 -c user.email=ltcdz5@users.noreply.github.com commit -q \
  -m "opt9 = opt7-clean + Oplus ebdd1643c 同步的 13 文件子集(闭包剔除 12 项含 blk-mq.c 的 EXPORT) + 后缀 -opt9

剔因: block/blk-mq.c 的 EXPORT_SYMBOL_GPL(test_task_ux) 已被真机证明致砖(a4/opt6a/opt6a2),
      include/trace/hooks/dtask.h 等会新增导出, 与厂商 .ko 引用名相交(闸门 FAIL)。
现役手机镜像 = images/boot-opt9-repacked.img (md5 29ff625ac9fe...)"
echo "  已提交: $(git rev-parse --short HEAD)"
git log --oneline -2
