#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt11_stable150.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt11 = opt10 + stable 6.1.146..150 中能自洽落地的纯 .c 子集
# 规则(今天验实): 只留 .c; 落地时剔除含新增导出的文件; 编译普查->按报错 TU 退回->迭代到 0 错
# 闸: 新增导出 ∩ 厂商 .ko 引用名 = 空 ; 全类型 BTF 与 opt10 差 0 行 ; config 差 0 行
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
W=/home/builder/opt11
OUT=/home/builder/opt11probe
P=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/patches/stable
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
mkdir -p "$W" "$OUT"
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
mk() { eval make -j"$(nproc --all)" $MFLAGS "$@"; }

echo "=== 0) 自证 $(date) ==="
echo "  whoami=$(whoami)  起点=$(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD)  脏=$(git status --porcelain|wc -l)"
clang --version | head -1 | sed 's/^/  /'
cp -f out/.config "$W/config.opt10"
echo "  配置基准 = opt10 实测 out/.config ($(wc -l < "$W/config.opt10") 行)"

echo '=== 1) 开分支 opt11-stable150 (从 opt10) ==='
git checkout -q -B opt11-stable150 opt10-stable145
: > "$W/landed.txt"; : > "$W/skipped.tsv"
for v in 146 147 148 149 150; do
  xz -dc "$P/patch-6.1.$v.xz" > /tmp/pp$v
  python3 - "$v" "$W" <<'PY'
import sys, os, re, subprocess
v, W = sys.argv[1], sys.argv[2]
KEEP = re.compile(r'^(mm|fs|kernel|net|lib|block|crypto|security|include|arch/arm64|scripts)/')
EXP  = re.compile(r'^\+\s*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|EXPORT_SYMBOL_NS|DEFINE_HOOK|DECLARE_HOOK)')
D='/tmp/split-%s' % v; os.makedirs(D, exist_ok=True)
blocks, cur, name = [], None, None
for L in open('/tmp/pp%s' % v, errors='replace'):
    m = re.match(r'^diff --git a/(\S+)', L)
    if m:
        if cur is not None: blocks.append((name, cur))
        name, cur = m.group(1), [L]
    elif cur is not None: cur.append(L)
if cur is not None: blocks.append((name, cur))
rel=[(f,b) for f,b in blocks if f and KEEP.match(f)]
land=gated=0
for i,(f,b) in enumerate(rel):
    if any(EXP.match(x) for x in b):
        gated+=1; open('%s/skipped.tsv'%W,'a').write('%s\t%s\t新增导出\n'%(v,f)); continue
    p='%s/%04d.diff'%(D,i); open(p,'w').write(''.join(b))
    r=subprocess.run(['git','apply','--check','--whitespace=nowarn',p],capture_output=True,text=True,cwd=os.getcwd())
    if r.returncode: open('%s/skipped.tsv'%W,'a').write('%s\t%s\t上下文冲突\n'%(v,f)); continue
    r2=subprocess.run(['git','apply','--whitespace=nowarn',p],capture_output=True,text=True,cwd=os.getcwd())
    if r2.returncode: open('%s/skipped.tsv'%W,'a').write('%s\t%s\tapply失败\n'%(v,f)); continue
    land+=1; open('%s/landed.txt'%W,'a').write('%s\t%s\n'%(v,f))
print("  %s: 相关目录=%-5d 整文件落地=%-4d 含新增导出剔除=%d" % (v,len(rel),land,gated))
PY
done
echo "  落地条目=$(wc -l < "$W/landed.txt")  涉及文件=$(cut -f2 "$W/landed.txt"|sort -u|wc -l)  改动=$(git diff --name-only|wc -l)"

echo '=== 2) 第 0 轮: 只留纯 .c(退回 .h/.tbl/include/scripts/Kconfig/.S/dts) ==='
git diff --name-only | grep -E '(\.h|\.S|\.tbl|\.dts|\.dtsi|Kconfig)$|^include/|^scripts/|^lib/Kconfig' > /tmp/d0.lst || true
echo "  退回 $(wc -l < /tmp/d0.lst) 个非 .c 改动"
xargs -r -a /tmp/d0.lst git checkout --
echo "  剩余改动=$(git diff --name-only|wc -l)"

sed_i() { sed -i 's/^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$/echo "-android14-11-o-ltcdz5-opt11"/' scripts/setlocalversion; }
echo '=== 3) 编译收敛迭代(上限 6 轮) ==='
for r in 1 2 3 4 5 6; do
  sed_i
  NOW=$(date +%s); BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null | wc -l)
  [ "$BAD" -gt 0 ] && { find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null; echo "  第$r轮: 归一 $BAD 个未来时间戳"; }
  mk -k Image > "$W/build.$r" 2>&1
  NERR=$(grep -cE "error:" "$W/build.$r")
  echo "  第$r轮 $(date +%H:%M:%S): 改动=$(git diff --name-only|wc -l)  error=$NERR"
  [ "$NERR" = "0" ] && { echo "  ==> 收敛"; break; }
  grep -oE '\.\./[A-Za-z0-9_./-]+\.(c|h|S):[0-9]+:[0-9]+: error:' "$W/build.$r" \
    | sed -E 's@^\.\./@@; s@:[0-9]+:[0-9]+: error:@@' | sort -u > /tmp/bad.$r
  git diff --name-only > /tmp/ch.$r
  : > /tmp/drop.$r
  while read -r bad; do
    [ -z "$bad" ] && continue
    grep -qxF "$bad" /tmp/ch.$r && echo "$bad" >> /tmp/drop.$r
    grep -E "/$(basename "$bad")\$" /tmp/ch.$r >> /tmp/drop.$r
  done < /tmp/bad.$r
  sort -u /tmp/drop.$r -o /tmp/drop.$r
  if [ ! -s /tmp/drop.$r ]; then
    echo "  ⛔ 有错但无一落在我们改过的文件上(疑在链接/其它依赖)。报错前 6 行:"
    grep -E "error:" "$W/build.$r" | head -6 | sed 's/^/     /'; exit 2
  fi
  echo "     本轮退回 $(wc -l < /tmp/drop.$r) 个: $(tr '\n' ' ' < /tmp/drop.$r | cut -c1-150)"
  xargs -r -a /tmp/drop.$r git checkout --
done
sed_i
echo "  收敛后落地文件 = $(git diff --name-only | grep -v setlocalversion | wc -l)"
git diff --name-only | grep -v setlocalversion | sed 's/^/    /'

echo '=== 4) 正式再编(不带 -k) + 三道闸 ==='
mk Image > "$W/final.log" 2>&1; RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' "$W/final.log")  clock skew=$(grep -ciE 'clock skew' "$W/final.log")"
[ $RC -ne 0 ] && { tail -18 "$W/final.log"; exit 1; }
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-62 | sed 's/^/  横幅: /'
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt11"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt11"
md5sum "$OUT/Image.opt11" | sed 's/^/  /'
echo "  config 与 opt10 差 $(diff "$W/config.opt10" out/.config | grep -cE '^[<>]') 行"
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt11"
python3 - <<'PY'
import struct
PAT=bytes([0x9f,0xeb,0x01,0x00,0x18,0x00,0x00,0x00])
for tag in ('opt11',):
    d=open('/home/builder/opt11probe/Image.opt11','rb').read(); h=d.find(PAT)
    to,tl,so,sl=struct.unpack_from('<IIII',d,h+8)
    open('/home/builder/abi/btf/%s.btf'%tag,'wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt11.btf > /home/builder/abi/full/opt11.txt 2>/dev/null
echo "  全类型: opt11=$(wc -l < /home/builder/abi/full/opt11.txt) 行  与 opt10 差 $(diff /home/builder/abi/full/opt10.txt /home/builder/abi/full/opt11.txt | grep -cE '^[<>]') 行  与 opt5 差 $(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt11.txt | grep -cE '^[<>]') 行"
diff /home/builder/abi/full/opt10.txt /home/builder/abi/full/opt11.txt | grep -E '^[<>]' | head -14 | sed 's/^/    /'
echo "=== 结束 $(date) ==="
