#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_apply_stable.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt10 = opt9 + stable 6.1.142..145 逐文件尝试: 能整文件干净落地的才要
# 闸1(落地时): 该文件的新增行里不得有 EXPORT_SYMBOL/DEFINE_HOOK/DECLARE_HOOK
# 闸2(构建后): 新导出 ∩ 厂商 .ko 引用名 必须为空  —— 由 gate_new_exports.py 做
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/patches/stable
W=/home/builder/opt10
mkdir -p "$W"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null

echo "=== 0) 自证 ==="
echo "  whoami=$(whoami)  起始分支=$(git rev-parse --abbrev-ref HEAD)  脏=$(git status --porcelain|wc -l)"
[ "$(git status --porcelain|wc -l)" != "0" ] && { echo "  ⛔ 工作区不干净, 停"; exit 1; }

echo "=== 1) 从 opt9 开 opt10-stable145 ==="
git checkout -q -B opt10-stable145 opt9-clean-upstream
git reset -q --hard opt9-clean-upstream
echo "  现在=$(git log --oneline -1)"

: > "$W/landed.txt"
: > "$W/skipped.tsv"
printf '%-8s %8s %8s %8s %8s\n' 版本 补丁内文件 相关目录 整文件落地 因新增导出剔除 | tee "$W/summary.tsv"

for v in 142 143 144 145; do
  xz -dc "$P/patch-6.1.$v.xz" > /tmp/p$v
  python3 - "$v" "$W" <<'PY'
import sys, os, re, subprocess
v, W = sys.argv[1], sys.argv[2]
KEEP = re.compile(r'^(mm|fs|kernel|net|lib|block|crypto|security|include|arch/arm64|scripts)/')
EXP  = re.compile(r'^\+\s*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|EXPORT_SYMBOL_NS|DEFINE_HOOK|DECLARE_HOOK|android_kabi_rename)')
D = '/tmp/split-%s' % v
os.system('rm -rf %s; mkdir -p %s' % (D, D))
blocks, cur, name = [], None, None
for L in open('/tmp/p%s' % v, errors='replace'):
    m = re.match(r'^diff --git a/(\S+)', L)
    if m:
        if cur is not None: blocks.append((name, cur))
        name, cur = m.group(1), [L]
    elif cur is not None:
        cur.append(L)
if cur is not None: blocks.append((name, cur))
total = len(blocks)
rel = [(f, b) for f, b in blocks if f and KEEP.match(f)]
landed = gated = 0
for i, (f, b) in enumerate(rel):
    txt = ''.join(b)
    fn = '%s/%04d.diff' % (D, i)
    open(fn, 'w').write(txt)
    if any(EXP.match(x) for x in b):
        gated += 1
        open('%s/skipped.tsv' % W, 'a').write('%s\t%s\t新增导出\n' % (v, f)); continue
    r = subprocess.run(['git','apply','--check','--whitespace=nowarn', fn],
                       cwd=os.getcwd(), capture_output=True, text=True)
    if r.returncode == 0:
        r2 = subprocess.run(['git','apply','--whitespace=nowarn', fn],
                            cwd=os.getcwd(), capture_output=True, text=True)
        if r2.returncode == 0:
            landed += 1
            open('%s/landed.txt' % W, 'a').write('%s\t%s\n' % (v, f))
        else:
            open('%s/skipped.tsv' % W, 'a').write('%s\t%s\tapply失败\n' % (v, f))
    else:
        open('%s/skipped.tsv' % W, 'a').write('%s\t%s\t上下文冲突\n' % (v, f))
print('%-8s %8d %8d %8d %8d' % (v, total, len(rel), landed, gated))
open('%s/.cnt-%s' % (W, v), 'w').write('%d %d %d %d' % (total, len(rel), landed, gated))
PY
  cnt=$(cat "$W/.cnt-$v")
  printf '%-8s %s\n' "$v" "$cnt" >> "$W/summary.tsv"
done

echo
echo "=== 2) 落地后的树 ==="
echo "  落地条目(版本+文件) = $(wc -l < "$W/landed.txt")   跳过 = $(wc -l < "$W/skipped.tsv")"
echo "  涉及文件数 = $(cut -f2 "$W/landed.txt" | sort -u | wc -l)"
echo "  跳过原因分布:"
cut -f3 "$W/skipped.tsv" | sort | uniq -c | sed 's/^/    /'
echo "  改动统计(前 15):"
git diff --stat | tail -3 | sed 's/^/    /'
git diff --numstat | awk '{a+=$1;d+=$2} END{print "    合计 +"a" -"d}'
echo
echo "=== 3) 落地文件里是否已有新增导出(再核一遍, 防漏) ==="
git diff -U0 | grep -cE '^\+\s*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|DEFINE_HOOK|DECLARE_HOOK)' | sed 's/^/  新增导出行数=/'
echo
echo "=== 4) 版本号字段 ==="
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)' Makefile | sed 's/^/  /'
