#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/ack_cve_scan.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# ACK android14-6.1-2025-09 分支: 窗口内提交数 + 按 CVE 号点名(哪些修的是什么)
set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git config --global --add safe.directory "$PWD" 2>/dev/null
REF=refs/remotes/ack/a14-09
git log -1 --format="  tip  %ad  %h  %s" --date=short "$REF"
echo "  窗口内提交数=$(git log --since=2025-07-01 --oneline "$REF" | wc -l)"
git log --since=2025-07-01 --format="%H%x1f%h%x1f%ad%x1f%s%x1f%b%x1e" --date=short "$REF" \
  > /tmp/ack_win.raw

python3 - <<'PY'
import re, collections
raw = open('/tmp/ack_win.raw', errors='replace').read()
recs = [r for r in raw.split('\x1e') if r.strip()]
rows = []
for r in recs:
    p = r.strip('\n').split('\x1f')
    if len(p) >= 5:
        rows.append({'sha': p[0][:12], 'short': p[1], 'date': p[2], 'subj': p[3], 'body': p[4]})
print("  解析出提交 = %d" % len(rows))
bycve = collections.OrderedDict()
for x in rows:
    for cve in sorted(set(re.findall(r'CVE-20\d{2}-\d{4,7}', x['body'] + ' ' + x['subj']))):
        bycve.setdefault(cve, []).append(x)
print("  去重 CVE 号 = %d   涉及提交 = %d" % (len(bycve), sum(len(v) for v in bycve.values())))
print()
def subsys(s):
    m = re.match(r'^([A-Za-z0-9_/.+-]+)\s*:', s)
    return m.group(1) if m else s.split()[0] if s.split() else '?'
cnt = collections.Counter()
for cve, xs in bycve.items():
    for x in xs:
        cnt[subsys(x['subj'])] += 1
print("  按子系统标题前缀分布 (top 22):")
for k, v in cnt.most_common(22):
    print("     %-28s %d" % (k[:28], v))
print()
print("  CVE 清单(前 40, 附第一条标题):")
for cve in list(bycve)[:40]:
    x = bycve[cve][0]
    print("     %-20s %s %s" % (cve, x['date'], x['subj'][:66]))
PY

echo
echo "=== 分支内的自纠条目(说明回移本身会出错) ==="
git log --since=2025-07-01 --format="  %h %s" "$REF" | grep -iE "bad backport|incorrect|wrong fix|Revert \"" | head -8
