#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_stable_iterate.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 通用: 把一批 stable 版本摊到当前树, 只留纯 .c, 编译普查迭代收敛, 再用 out/ 下有无 .o 判"真参与编译"
# 用法: OPT=opt12 BASE=<基线分支> VERS="151 152 ..." bash opt_stable_iterate.sh
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
P=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/patches/stable
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
OPT=${OPT:?要给定 OPT(如 opt12)}
BASE=${BASE:?要给定 BASE(基线分支)}
VERS=${VERS:?要给定 VERS(版本清单)}
W=/home/builder/$OPT
OUT=/home/builder/${OPT}probe
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
mkdir -p "$W" "$OUT"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
mk() { eval make -j"$(nproc --all)" $MFLAGS "$@"; }
setsfx() { sed -i "s|^echo \"-android14-11-o-ltcdz5-[a-z0-9]*\"\$|echo \"-android14-11-o-ltcdz5-$OPT\"|" scripts/setlocalversion; }

echo "=== 0) $(date) whoami=$(whoami) 基线=$BASE $(git rev-parse --short $BASE) ==="
clang --version | head -1 | sed 's/^/  /'
cp -f out/.config "$W/config.base"
git checkout -q -f "$BASE"; git checkout -q -B "$OPT-stable" "$BASE"
echo "  分支=$(git rev-parse --abbrev-ref HEAD)  脏=$(git status --porcelain|wc -l)"

: > "$W/landed.txt"; : > "$W/skipped.tsv"
echo "=== 1) 先建『已编译对象』白名单(把 13 万次 apply --check 压到几千次) ==="
find out -name "*.o" 2>/dev/null | sed -E 's@^out/@@; s@\.o$@@; s@^libs/@@' | sort -u > "$W/objs.txt"
echo "  out/ 里的对象数=$(wc -l < "$W/objs.txt")"
for v in $VERS; do
  xz -dc "$P/patch-6.1.$v.xz" > /tmp/pp$v
  python3 - "$v" "$W" <<'PY'
import sys, os, re, subprocess
v, W = sys.argv[1], sys.argv[2]
objs={l.strip() for l in open(W+'/objs.txt') if l.strip()}
KEEP = re.compile(r'^(mm|fs|kernel|net|lib|block|crypto|security|include|arch/arm64)/')
EXP  = re.compile(r'^\+\s*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|EXPORT_SYMBOL_NS|DEFINE_HOOK|DECLARE_HOOK)')
D='/tmp/s-%s'%v; os.makedirs(D, exist_ok=True)
blocks,cur,name=[],None,None
for L in open('/tmp/pp%s'%v,errors='replace'):
    m=re.match(r'^diff --git a/(\S+)',L)
    if m:
        if cur is not None: blocks.append((name,cur))
        name,cur=m.group(1),[L]
    elif cur is not None: cur.append(L)
if cur is not None: blocks.append((name,cur))
# 只尝试"该文件真被编进本机"的补丁(.c 且 out/ 下有同名 .o)
rel=[(f,b) for f,b in blocks if f and KEEP.match(f) and f.endswith('.c') and f[:-2] in objs]
skipped_notcompiled=sum(1 for f,_ in blocks if f and KEEP.match(f) and f.endswith('.c') and f[:-2] not in objs)
land=gated=0
for i,(f,b) in enumerate(rel):
    if any(EXP.match(x) for x in b):
        gated+=1; open('%s/skipped.tsv'%W,'a').write('%s\t%s\t新增导出\n'%(v,f)); continue
    p='%s/%04d.diff'%(D,i); open(p,'w').write(''.join(b))
    if subprocess.run(['git','apply','--check','--whitespace=nowarn',p],capture_output=True,text=True,cwd=os.getcwd()).returncode:
        open('%s/skipped.tsv'%W,'a').write('%s\t%s\t上下文冲突\n'%(v,f)); continue
    if subprocess.run(['git','apply','--whitespace=nowarn',p],capture_output=True,text=True,cwd=os.getcwd()).returncode: continue
    land+=1; open('%s/landed.txt'%W,'a').write('%s\t%s\n'%(v,f))
print("  %s 落地=%-4d (可试=%d, 不编译跳过=%d, 新增导出剔除=%d)" % (v,land,len(rel),skipped_notcompiled,gated))
PY
done
echo "  合计落地条目=$(wc -l < "$W/landed.txt")  唯一文件=$(cut -f2 "$W/landed.txt"|sort -u|wc -l)  当前改动=$(git diff --name-only|wc -l)"

echo '=== 2) 只留纯 .c ==='
git diff --name-only | grep -E '(\.h|\.S|\.tbl|\.dts|\.dtsi|Kconfig)$|^include/|^scripts/' > /tmp/d0.lst || true
echo "  退回 $(wc -l < /tmp/d0.lst) 个"; xargs -r -a /tmp/d0.lst git checkout --
echo "  剩余=$(git diff --name-only|wc -l)"

echo '=== 3) 编译普查迭代收敛 ==='
for r in 1 2 3 4 5 6 7 8; do
  setsfx
  NOW=$(date +%s); BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null|wc -l)
  [ "$BAD" -gt 0 ] && find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null
  mk -k Image > "$W/build.$r" 2>&1
  NERR=$(grep -cE "error:" "$W/build.$r")
  echo "  第$r轮 $(date +%H:%M:%S): 改动=$(git diff --name-only|wc -l) error=$NERR"
  [ "$NERR" = "0" ] && { echo "  ==> 0 错收敛"; break; }
  grep -oE '\.\./[A-Za-z0-9_./-]+\.(c|h|S):[0-9]+:[0-9]+: error:' "$W/build.$r" | sed -E 's@^\.\./@@; s@:[0-9]+:[0-9]+: error:@@' | sort -u > /tmp/bad.$r
  git diff --name-only > /tmp/ch.$r; : > /tmp/dr.$r
  while read -r x; do [ -z "$x" ] && continue
    grep -qxF "$x" /tmp/ch.$r && echo "$x" >> /tmp/dr.$r
    grep -E "/$(basename "$x")\$" /tmp/ch.$r >> /tmp/dr.$r
  done < /tmp/bad.$r
  sort -u /tmp/dr.$r -o /tmp/dr.$r
  [ ! -s /tmp/dr.$r ] && { echo "  ⛔ 报错无一在我们改过的文件里"; grep -E "error:" "$W/build.$r"|head -6|sed 's/^/     /'; exit 2; }
  echo "     退回 $(wc -l < /tmp/dr.$r): $(tr '\n' ' ' < /tmp/dr.$r | cut -c1-160)"
  xargs -r -a /tmp/dr.$r git checkout --
done
setsfx

echo '=== 4) 用 out/ 下有无 .o 判"真参与编译" ==='
git diff --name-only | grep -v setlocalversion > /tmp/f.lst
: > "$W/compiled.lst"; : > "$W/dead.lst"
while read -r f; do
  if [ -f "out/$(dirname "$f")/$(basename "$f" .c).o" ]; then echo "$f" >> "$W/compiled.lst"; else echo "$f" >> "$W/dead.lst"; fi
done < /tmp/f.lst
echo "  编过(有 .o)=$(wc -l < "$W/compiled.lst")   未编译(无 .o, 白改)=$(wc -l < "$W/dead.lst")"
echo "  --- 真进本机的这些:"; sed 's/^/    /' "$W/compiled.lst"
echo "  --- 需人工过目的敏感路径命中(异常入口/sched/mm/blk-mq):"
grep -E "entry-common|traps\.c|signal\.c|kernel/sched/|blk-mq\.c|mm/fault" "$W/compiled.lst" | sed 's/^/    ⚠ /' || echo "    (无)"
echo "  改动总量:"; git diff --numstat | awk '{a+=$1;d+=$2} END{print "    +"a" -"d}'
echo "=== 结束 $(date) — 未做 gate/repack, 等人工确认清单 ==="
