#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b1_fetch_ack.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# B 方案第 1 步: 取 ACK 的树对象(blobless) + 我们基线 tag, 并实测"有没有 merge base"
set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git config --global --add safe.directory "$PWD" 2>/dev/null
ACK=https://gh-proxy.com/https://github.com/aosp-mirror/kernel_common

echo "=== 0) fetch 前体积 ==="
git count-objects -vH | grep -E '^(-|Size|size-pack)' | sed 's/^/  /'

echo "=== 1) fetch ACK 09 分支(带树, blob 按需) ==="
date
git fetch --filter=blob:none --depth=1400 "$ACK" \
  refs/heads/android14-6.1-2025-09:refs/remotes/ack/a14-09 2>&1 | tail -4
echo "=== 2) fetch 我们基线 tag 07_r9(做 diff 的另一端) ==="
git fetch --filter=blob:none --depth=1400 "$ACK" \
  refs/tags/android14-6.1-2025-07_r9:refs/tags/ackbase07r9 2>&1 | tail -4
echo "=== 3) fetch 后体积 ==="
date
git count-objects -vH | grep -E '^(-|Size|size-pack)' | sed 's/^/  /'

echo "=== 4) 两端是否可见 + 相差多少 ==="
git rev-parse --verify -q refs/remotes/ack/a14-09 | head -c 12; echo "  <- a14-09 tip"
git rev-parse --verify -q refs/tags/ackbase07r9   | head -c 12; echo "  <- 07_r9"
echo "  ACK 内部提交数(07_r9..09)=$(git rev-list --count refs/tags/ackbase07r9..refs/remotes/ack/a14-09 2>/dev/null || echo 不可算)"

echo "=== 5) 关键判定: 我们的树与 ACK 有没有共同祖先(决定能否真 merge) ==="
for a in opt5-state snap-6.1.141; do
  mb=$(git merge-base "$a" refs/remotes/ack/a14-09 2>/dev/null)
  echo "  merge-base($a, ack) = ${mb:-无(历史不相交)}"
done
echo "  07_r9 是不是我们基线? 我们树里 Makefile 版本:"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' Makefile | tr -d '\t' | tr '\n' ' '; echo
echo "  ACK 07_r9 的 Makefile 版本:"
git show refs/tags/ackbase07r9:Makefile 2>/dev/null | grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' | tr -d '\t' | tr '\n' ' '; echo
echo "  ACK 09 tip 的 Makefile 版本:"
git show refs/remotes/ack/a14-09:Makefile 2>/dev/null | grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' | tr -d '\t' | tr '\n' ' '; echo

echo "=== 6) 增量画像(只到文件级, 不取 blob) ==="
git diff --name-only refs/tags/ackbase07r9 refs/remotes/ack/a14-09 2>/dev/null > /tmp/ack_files.txt
echo "  涉及文件数=$(wc -l < /tmp/ack_files.txt)"
echo "  其中头文件=$(grep -cE '\.h$' /tmp/ack_files.txt)  include/linux 下=$(grep -cE '^include/linux/' /tmp/ack_files.txt)"
echo "  分布 top12:"
awk -F/ '{print $1"/"$2}' /tmp/ack_files.txt | sort | uniq -c | sort -rn | head -12 | sed 's/^/    /'
