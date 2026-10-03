#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b3_fetch_patches.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 拉 ACK 每条提交的 .patch 正文, 并从正文里算: 是否新增导出、是否碰 .h
set -u
D="$1/patchset"; mkdir -p "$D/raw"
LIST="$1/_uniq.tsv"
P="https://gh-proxy.com/https://github.com/aosp-mirror/kernel_common/commit"
pull() {
  sha="$1"
  [ -s "$D/raw/$sha.patch" ] && return
  curl -sL --max-time 40 "$P/$sha.patch" -o "$D/raw/$sha.patch" 2>/dev/null
}
export -f pull; export D P
cut -f2 "$LIST" | sort -u | xargs -P 4 -I{} bash -c 'pull {}'
echo "拉到补丁文件数 = $(ls "$D/raw" | wc -l)   总字节 = $(du -sh "$D/raw" | cut -f1)"
echo
: > "$D/manifest.tsv"
: > "$D/ack.mbox"
while IFS=$'\t' read -r path sha date subj; do
  f="$D/raw/$sha.patch"; [ -s "$f" ] || continue
  exp=$(grep -cE '^\+[[:space:]]*(EXPORT_SYMBOL|DEFINE_HOOK|DECLARE_HOOK)' "$f")
  hdr=$(grep -cE '^\+\+\+ b/.*\.h$' "$f")
  printf '%s\t%s\t导出新增=%s\t碰h=%s\t%s\t%s\n' "$sha" "$date" "$exp" "$hdr" "$path" "$subj" >> "$D/manifest.tsv"
  cat "$f" >> "$D/ack.mbox"
done < "$LIST"
echo "=== 会被闸门否掉的(有新增导出/钩子) ==="
awk -F'\t' '$3!="导出新增=0"{print "  ⛔ " $2" "$4" "$5" "substr($6,1,66)}' "$D/manifest.tsv" | head -14
echo
echo "=== 碰 .h 的条目数 = $(awk -F'\t' '$4!="碰h=0"' "$D/manifest.tsv" | wc -l) / 总数 = $(wc -l < "$D/manifest.tsv") ==="
awk -F'\t' '$4!="碰h=0"{print "  ⚠ " $2" "substr($6,1,72)}' "$D/manifest.tsv" | head -12
echo
echo "合集: $D/ack.mbox ($(wc -l < "$D/ack.mbox") 行)"
