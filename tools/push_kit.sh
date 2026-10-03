#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/push_kit.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；借鉴项见 NOTICE.md 第三节
#   用途   : 推送本仓库。本机全局 git 配置把 github.com 改写成了 gh-proxy.com
#            （为国内网络加速），而 gh 的凭据助手只认 github.com ⇒ 直推会失败。
#            本脚本临时取消该改写后推送，再恢复。
#   用法   : bash tools/push_kit.sh [分支名]   （默认 master）
# ---------------------------------------------------------------------------
set -u
BRANCH="${1:-master}"
DIRECT="https://github.com/ltcdz5/gt5pro-kernel-kit.git"

cd "$(dirname "$0")/.." || exit 1
echo "[push_kit] 仓库: $(pwd)  分支: $BRANCH"

SAVED=$(git config --global --get-regexp '^url\.' 2>/dev/null || true)
if [ -n "$SAVED" ]; then
  echo "[push_kit] 临时取消 url 改写："
  echo "$SAVED" | sed 's/^/           /'
  # ★ 注意：不能用 IFS= read（那样整行会进第一个变量，unset 会静默失败）
  echo "$SAVED" | while read -r key val; do
    git config --global --unset-all "$key" 2>/dev/null || true
  done
fi

echo "[push_kit] 剩余 url 改写: $(git config --global --get-regexp '^url\.' 2>/dev/null | wc -l) 条（应为 0）"
GIT_TERMINAL_PROMPT=0 git push --force "$DIRECT" "$BRANCH"
RC=$?
echo "[push_kit] push rc=$RC"

if [ -n "$SAVED" ]; then
  echo "$SAVED" | while read -r key val; do
    git config --global --add "$key" "$val" 2>/dev/null || true
  done
  echo "[push_kit] 已恢复 url 改写：$(git config --global --get-regexp '^url\.' 2>/dev/null | wc -l) 条"
fi
exit $RC