#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b1b_list_ack.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git config --global --add safe.directory "$PWD" 2>/dev/null
echo "=== 本地可见的 ack 引用 ==="
git for-each-ref --format='  %(refname) %(objectname:short)' refs/remotes/ack refs/tags/ackbase07r9 refs/tags/android14-6.1-2025-07_r9 2>/dev/null
echo
TIP=refs/remotes/ack/a14-09
BASE=""
for b in refs/tags/ackbase07r9 android14-6.1-2025-07_r9 refs/tags/android14-6.1-2025-07_r9; do
  if git rev-parse --verify -q "$b" >/dev/null; then BASE=$b; break; fi
done
echo "基线 = ${BASE:-未取到(需要补 fetch 该 tag 的 commit 对象)}"
if [ -n "$BASE" ]; then
  echo "07_r9..09tip 提交数 = $(git rev-list --count "$BASE..$TIP" 2>/dev/null)"
  git rev-list --reverse "$BASE..$TIP" --format='%h|%ad|%s' --date=short 2>/dev/null | grep -v '^[0-9a-f]\{40\}$' > /tmp/ack_shas.txt
  wc -l < /tmp/ack_shas.txt | sed 's/^/清单行数 = /'
  head -3 /tmp/ack_shas.txt | sed 's/^/  /'
  cp /tmp/ack_shas.txt /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/logs/ack_commit_list.txt
fi
echo
echo "=== 若基线缺失: 单独补一条 commit-only fetch(只几 MB) ==="
if [ -z "$BASE" ]; then
  timeout 240 git fetch --filter=tree:0 --depth=1500 \
    https://gh-proxy.com/https://github.com/aosp-mirror/kernel_common \
    refs/tags/android14-6.1-2025-07_r9:refs/tags/ackbase07r9 2>&1 | tail -3
  echo "  补取后: $(git rev-list --count refs/tags/ackbase07r9..refs/remotes/ack/a14-09 2>/dev/null) 条"
  git rev-list --reverse refs/tags/ackbase07r9..refs/remotes/ack/a14-09 --format='%h|%ad|%s' --date=short 2>/dev/null | grep -v '^[0-9a-f]\{40\}$' > /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/logs/ack_commit_list.txt
  wc -l < /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/logs/ack_commit_list.txt | sed 's/^/  清单行数 = /'
fi
