#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/layout_diff.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 把每个 .btf 规范化成 "struct名|size|字段:偏移:宽度;..." 的一行一结构表, 再逐行比。
# 规范化是为了消掉 BTF 排序带来的噪音 —— 只有真布局变化才会让某行内容不同。
cd /home/builder/abi 2>/dev/null || exit 1
mkdir -p tables

for f in btf/*.btf; do
  n=$(basename "$f" .btf)
  [ -s "tables/$n.tsv" ] && continue
  pahole "$f" 2>/dev/null | python3 -c '
import sys,re
cur=None; fields=[]; size=None; out=[]
def flush(name,size,fields):
    if name is None: return
    out.append("%s|%s|%s" % (name, size, ";".join(fields)))
for L in sys.stdin:
    s=L.rstrip("\n")
    m=re.match(r"^(struct|union)\s+([A-Za-z0-9_]+)\s*\{", s)
    if m:
        flush(cur,size,fields); cur=m.group(2); fields=[]; size=None; continue
    if cur is None: continue
    if s.startswith("};") or "size:" in s:
        mm=re.search(r"size:\s*(\d+)", s)
        if mm: size=mm.group(1)
        if s.startswith("};"):
            flush(cur,size,fields); cur=None; fields=[]
        continue
    fm=re.match(r"^(.*?)\s*/\*\s*(\d+)\s+(\d+)\s*\*/", s)
    if fm:
        decl=fm.group(1).strip().rstrip(";")
        nm=decl.split()[-1] if decl.split() else "?"
        nm=nm.lstrip("*").split("[")[0]
        fields.append("%s:%s:%s" % (nm, fm.group(2), fm.group(3)))
flush(cur,size,fields)
print("\n".join(out))
' > "tables/$n.tsv"
  echo "$(printf '%-28s' $n) $(wc -l < tables/$n.tsv) 个结构"
done

echo
echo "=== 逐行对比: 以 opt5(已知能开机) 为基准 ==="
python3 - <<'PY'
import os
D='/home/builder/abi/tables'
def load(n):
    m={}
    for L in open(os.path.join(D,n+'.tsv'),errors='replace'):
        p=L.rstrip('\n').split('|',2)
        if len(p)==3: m[p[0]]=p[1]+'\t'+p[2]
    return m
base=load('opt5-ltcdz5-raw')
print("基准 opt5 结构数: %d" % len(base))
for n in sorted(os.listdir(D)):
    n=n[:-4]
    if n=='opt5-ltcdz5-raw': continue
    c=load(n)
    size_chg=[]; off_chg=[]; miss=[]; new=[]
    for k,v in base.items():
        if k not in c: miss.append(k); continue
        bs,bf=v.split('\t'); cs,cf=c[k].split('\t')
        if bs!=cs: size_chg.append((k,bs,cs))
        elif bf!=cf: off_chg.append((k,bf,cf))
    for k in c:
        if k not in base: new.append(k)
    print("\n%s   (结构数 %d)  size变化=%d  字段布局变化=%d  消失=%d  新增=%d"
          % (n,len(c),len(size_chg),len(off_chg),len(miss),len(new)))
    for k,a,b in size_chg[:12]: print("   [size]  %-42s %s -> %s" % (k,a,b))
    for k,a,b in off_chg[:12]:
        # 只打印前 3 个不同的字段, 便于肉眼定位
        fa=a.split(';'); fb=b.split(';')
        d=[(x,y) for x,y in zip(fa,fb) if x!=y][:3]
        print("   [layout] %-41s %s" % (k, " | ".join("%s  vs  %s" % (x,y) for x,y in d)))
PY
