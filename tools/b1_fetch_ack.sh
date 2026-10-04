#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b1_fetch_ack.sh   （v2，2026-10-04 重写）
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# v1 的三个缺陷（2026-10-04 实测后重写；v1 留档为 b1_fetch_ack.v1-ghproxy.sh）：
#   ① 源错了：v1 走 gh-proxy + aosp-mirror/kernel_common，而该镜像【已冻结在 2025-11-19】
#      => 收获窗口永远停在那儿，"没有新东西" 是假象。v2 改用权威源 android.googlesource.com。
#   ② fail-open：v1 用 | tail -4 把 git 的报错吞掉，取不到也照常往下走。v2 是 fail-closed：
#      非零退出 / **error 级 stderr**（error|fatal|could not|denied|unable）/ 空结果 / tip 日期早于已知收获日
#      => 立刻非零退出（rc=3）。注：git 的进度与 warning 也走 stderr，故只对 error 级致命（warning 照打，便于发现残包等问题）。
#   ③ 粒度粗：v1 只到文件级。v2 加 hunk 级（文件 + 行区间 + 增删计数）与"纯 .c 修复"筛选。
#
# 用法：
#   b1_fetch_ack.sh verify                  只校验源与新鲜度（不取数）
#   b1_fetch_ack.sh fetch [基线ref]          取权威源分支(blobless) + 基线，并自检
#   b1_fetch_ack.sh new [N]                 列【上次收获日之后】的新提交（默认 40 条）
#   b1_fetch_ack.sh log [基线ref] [N]        列 基线..tip 的提交（CVE 高亮）
#   b1_fetch_ack.sh hunks [基线ref]          hunk 级清单 + 纯 .c 修复筛选
set -u

ACK=https://android.googlesource.com/kernel/common
MIRROR=https://github.com/aosp-mirror/kernel_common
BRANCH=refs/heads/android14-6.1-lts
REMOTE_REF=refs/remotes/ack/a14-lts
ACKBASE_TAG=refs/tags/android14-6.1-2025-07_r9
ACKBASE_LOCAL=refs/tags/ackbase07r9
LAST_SEEN_DATE=2026-10-02
REPO=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
# 传输参数：googlesource 上大传输常被 TLS 中途掐断（curl 56 / GnuTLS -110）
#   => 缩深度 + 强制 HTTP/1.1 + 放大 postBuffer + 重试；仍失败则 fail-closed（不许当没变化）
ACK_DEPTH=500
ACK_TRIES=3

CMD=$1
[ -n "$CMD" ] || CMD=verify
ARG2=
ARG3=
[ $# -ge 2 ] && ARG2=$2
[ $# -ge 3 ] && ARG3=$3
N=$ARG3
[ -n "$N" ] || N=40

fail() { echo "❌ [fail-closed] $*" >&2; exit 3; }

# 只把 error 级 stderr 当致命；warning/进度照打不误
errcheck() {
  local tag=$1 file=$2 txt bad
  txt=$(cat "$file" 2>/dev/null || true)
  [ -n "$txt" ] || return 0
  printf '%s\n' "$txt" | sed "s/^/  [stderr:$tag] /" >&2
  bad=$(printf '%s\n' "$txt" | grep -icE 'error|fatal|could not|denied|unable|refus' || true)
  [ "$bad" = 0 ] || fail "$tag 出现 $bad 行 error 级 stderr（见上）"
}

# 带重试的 fetch（网络掐断是常态，不是异常）
ack_fetch() {
  local src=$1 refspec=$2 i rc=1
  for i in $(seq 1 $ACK_TRIES); do
    git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 fetch --filter=blob:none --depth=$ACK_DEPTH "$src" "$refspec" >/tmp/ack_out 2>/tmp/ack_err
    rc=$?
    [ "$rc" = 0 ] && { [ "$i" -gt 1 ] && echo "  ✅ 第 $i 次尝试成功"; return 0; }
    echo "  ⚠️ 第 $i/$ACK_TRIES 次 fetch 失败 rc=$rc：$(tail -2 /tmp/ack_err | tr '\n' ' ')" >&2
    sleep 5
  done
  return $rc
}

[ -d "$REPO" ] || fail "找不到内核树 $REPO"
cd "$REPO" || fail "进不去内核树"
git config --global --add safe.directory "$PWD" 2>/dev/null || true

tip() { git rev-parse --verify -q "$REMOTE_REF" 2>/dev/null; }

freshness() {
  local j res sha d verdict
  j=$(curl -s --max-time 60 "$ACK/+log/$BRANCH?format=JSON&n=1" 2>/tmp/ack_err) || fail "curl 取 gitiles 失败"
  errcheck curl /tmp/ack_err
  [ -n "$j" ] || fail "gitiles 返回空（源不可用、分支名错、或被限流）"
  res=$(printf '%s' "$j" | sed "s/^)]}'//" | python3 -c "import json,sys,email.utils,time; c=json.load(sys.stdin)['log'][0]; t=c['committer']['time']; e=email.utils.parsedate_to_datetime(t).timestamp(); last=time.mktime(time.strptime(sys.argv[1],'%Y-%m-%d')); print(c['commit'], t, 'OK' if e>=last else 'STALE', sep=chr(9))" "$LAST_SEEN_DATE" 2>/dev/null) || fail "gitiles JSON 解析失败（源返回的不是预期 JSON）"
  sha=$(printf '%s' "$res" | cut -f1)
  d=$(printf '%s' "$res" | cut -f2)
  verdict=$(printf '%s' "$res" | cut -f3)
  [ -n "$sha" ] || fail "gitiles 未给出提交信息"
  [ "$verdict" = "OK" ] || fail "远端 tip 日期 $d 早于已知收获日 $LAST_SEEN_DATE => 源疑似冻结/回退，禁止当"无新增"处理"
  echo "  ✅ 源新鲜：权威 tip = $sha"
  echo "     日期 = $d （不早于 $LAST_SEEN_DATE）"
}

case "$CMD" in
  verify)
    echo "=== 源与新鲜度校验 ==="
    echo "  权威源   = $ACK"
    echo "  对照镜像 = $MIRROR （已知冻结，仅作参考）"
    freshness
    ;;

  fetch)
    BASE=$ARG2
    [ -n "$BASE" ] || BASE=$ACKBASE_TAG
    echo "=== 0) fetch 前体积 ==="
    git count-objects -vH | grep -E '^(size-pack|count)' | sed 's/^/  /'
    echo "=== 1) 取权威源分支（blobless, depth=2000）==="
    ack_fetch "$ACK" "$BRANCH:$REMOTE_REF"; rc=$?
    [ "$rc" = 0 ] || fail "fetch 分支失败（已重试 $ACK_TRIES 次）: $(tail -3 /tmp/ack_err | tr '\n' ' ')"
    errcheck fetch /tmp/ack_err
    s=$(tip)
    [ -n "$s" ] || fail "fetch 后仍取不到 $REMOTE_REF"
    git show -s --format='  ✅ tip: %h %cs %s' "$s"
    echo "=== 2) 取基线 $BASE ==="
    if [ "$BASE" = "$ACKBASE_TAG" ]; then
      ack_fetch "$ACK" "$ACKBASE_TAG:$ACKBASE_LOCAL"; rc2=$?
      cp -f /tmp/ack_err /tmp/ack_err2 2>/dev/null || true
      [ "$rc2" = 0 ] || fail "fetch 基线失败（已重试 $ACK_TRIES 次）: $(tail -3 /tmp/ack_err | tr '\n' ' ')"
      errcheck fetch-base /tmp/ack_err2
      BASE=$ACKBASE_LOCAL
    fi
    git rev-parse --verify -q "$BASE" >/dev/null || fail "基线不可解析: $BASE"
    echo "  ✅ 基线 = $BASE"
    echo "=== 3) 增量规模（文件级概览）==="
    git diff --name-only "$BASE" "$REMOTE_REF" 2>/dev/null > /tmp/ack_files.txt
    n=$(wc -l < /tmp/ack_files.txt)
    [ "$n" -gt 0 ] || fail "基线..tip 差异为空 => 要么基线选错、要么源异常（不许当"没变化"）"
    echo "  涉及文件 = $n   其中头文件 = $(grep -cE '\.h$' /tmp/ack_files.txt)"
    echo "=== 4) 新鲜度自检 ==="
    freshness
    echo "  ★ 下一步：new（看新提交）/ hunks（看 hunk 级改动）"
    ;;

  new)
    [ -n "$(tip)" ] || fail "尚未 fetch，请先跑 fetch"
    echo "=== 上次收获日（$LAST_SEEN_DATE）之后的新提交（最多 $N 条）==="
    git log --since="$LAST_SEEN_DATE 00:00:00" -n "$N" --format='  %h %cs %s' "$REMOTE_REF" | sed 's/CVE/CVE★/g'
    echo "  合计 = $(git log --since="$LAST_SEEN_DATE 00:00:00" --oneline "$REMOTE_REF" | wc -l) 条"
    ;;

  log)
    B=$ARG2
    [ -n "$B" ] || B=$ACKBASE_LOCAL
    git rev-parse --verify -q "$B" >/dev/null || fail "范围起点不可解析: $B（先 fetch，或显式传基线）"
    echo "=== $B..$REMOTE_REF 提交（最多 $N 条，CVE 高亮）==="
    git log -n "$N" --format='  %h %cs %s' "$B..$REMOTE_REF" | sed 's/CVE/CVE★/g'
    echo "  合计 = $(git rev-list --count "$B..$REMOTE_REF") 条"
    ;;

  hunks)
    B=$ARG2
    [ -n "$B" ] || B=$ACKBASE_LOCAL
    git rev-parse --verify -q "$B" >/dev/null || fail "范围起点不可解析: $B"
    echo "=== hunk 级清单（$B..$REMOTE_REF）==="
    git diff --no-renames --unified=0 "$B" "$REMOTE_REF" > /tmp/ack.diff 2>/tmp/ack_err || fail "git diff 失败: $(cat /tmp/ack_err)"
    [ -s /tmp/ack.diff ] || fail "diff 为空 => 不许当"没变化""
    awk '
      /^diff --git/ { f=$3; sub(/^a\//,"",f); next }
      /^@@/        { h[f]++; tot++; next }
      /^\+/       { add[f]++; next }
      /^-/         { del[f]++; next }
      END {
        printf "  文件数=%d   hunk 总数=%d\n", length(h), tot
        for (k in h) printf "  %-58s hunks=%-5d +%-6d -%-6d\n", k, h[k], add[k]+0, del[k]+0
      }' /tmp/ack.diff | sort -t= -k2 -rn | head -40
    echo
    echo "=== 纯 .c 修复候选判断（是否只有 .c/.h 参与）==="
    bad=$(grep -E '^diff --git' /tmp/ack.diff | grep -cvE '\.(c|h) ')
    if [ "$bad" -gt 0 ]; then
      echo "  ⚠️ 有 $bad 个非 .c/.h 文件参与改动（可能动 Kconfig/Makefile/结构体）=> 需人工评估闸门风险"
    else
      echo "  ✅ 全部改动都在 .c/.h"
    fi
    echo "  ★ 提醒：无论多干净，仍须过两道闸门（新增/消失/遮蔽 + 非蓝牙拒载=0）才算可刷"
    ;;

  *)
    echo "用法: $0 {verify|fetch|new|log|hunks} [基线ref] [N]" >&2
    exit 2
    ;;
esac
