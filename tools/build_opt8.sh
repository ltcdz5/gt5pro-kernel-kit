#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/build_opt8.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt8 = 25 文件补丁, 按"不新增导出"规则裁剪, 且把对被裁符号有引用的文件一起裁掉(闭包)
set -u
PATCH=/home/builder/opt6_upstream.patch
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt8probe
WIN=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images
LOG=/home/builder/opt8.decision
cd "$TREE" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$TREE" 2>/dev/null

echo '=== 0) 自证: 账号 / 编译器 ==='
echo "  whoami=$(whoami)"; clang --version | head -1 | sed 's/^/  /'

echo '=== 1) 算闭包: 哪些文件必须一起裁 ==='
# 闭包(宽松匹配, 含 trace_<hook> 调用点)
python3 - <<'PY' > /home/builder/opt8.files
import re, collections
txt = open('/home/builder/opt6_upstream.patch', errors='replace').read().split('\n')
per = collections.OrderedDict()
cur = None
for L in txt:
    m = re.match(r'^\+\+\+ b/(.*)$', L)
    if m:
        cur = m.group(1).strip(); per.setdefault(cur, [])
        continue
    if cur is not None and L.startswith('+') and not L.startswith('+++'):
        per[cur].append(L[1:])

# 1a. 新增"导出/钩子声明"的文件, 及它们引入的新符号名
drop = set(); names = set()
for f, adds in per.items():
    hits = [a for a in adds if re.search(r'EXPORT_SYMBOL|DEFINE_HOOK|DECLARE_HOOK|CREATE_TRACE', a)]
    if hits:
        drop.add(f)
        for a in hits:
            for n in re.findall(r'(?:EXPORT_SYMBOL(?:_GPL|_NS_GPL)?)\(\s*([A-Za-z_][A-Za-z0-9_]*)', a): names.add(n)
            for n in re.findall(r'DECLARE_HOOK\(\s*([A-Za-z_][A-Za-z0-9_]*)', a): names.add(n)

# 1b. 闭包: 保留文件里若新增行引用了这些名字, 一并裁掉(迭代到稳定)
#     用"子串"而非 \b —— 调用点写成 trace_<hook>() 时前面是下划线, \b 匹配不到会漏(半个系列)
changed = True
while changed:
    changed = False
    for f, adds in per.items():
        if f in drop: continue
        if names and any(n in a for n in names for a in adds):
            drop.add(f); changed = True
print(",".join(sorted(drop)))
print("# 引入的新符号: " + " ".join(sorted(names)), file=__import__('sys').stderr)
PY
DROP=$(head -1 /home/builder/opt8.files)
echo "  必须裁掉的文件: $DROP"
python3 - <<'PY'
import re
txt=open('/home/builder/opt6_upstream.patch',errors='replace').read()
allf=[l[6:].strip() for l in txt.split('\n') if l.startswith('+++ b/')]
drop=set(open('/home/builder/opt8.files').readline().strip().split(','))
keep=[f for f in allf if f not in drop]
print("  总数=%d  裁=%d  留=%d" % (len(allf), len(drop), len(keep)))
open('/home/builder/opt8.keep','w').write(",".join(keep))
for f in sorted(drop): print("     ⛔", f)
PY

echo '=== 2) 从 opt5-state 开 opt8, 只套保留文件 ==='
git checkout -q -f opt5-state
git checkout -q -B opt8-upstream-nodelta
EXC=""; for f in ${DROP//,/ }; do EXC="$EXC --exclude=$f"; done
git apply --check $EXC "$PATCH" && echo "  干跑 OK"
git apply $EXC "$PATCH"
echo "  实际改动文件数=$(git status --porcelain | grep -c '^ M')  其中头文件=$(git status --porcelain | grep '^ M' | grep -c '\.h$')"
git status --porcelain | grep '^ M' | sed 's/^/    /'

echo '=== 3) 后缀 -opt8, 配置用 opt5 实测 config ==='
sed -i 's/^echo "-android14-11-o-ltcdz5"$/echo "-android14-11-o-ltcdz5-opt8"/' scripts/setlocalversion
tail -1 scripts/setlocalversion
cp -f "$BASE/config" out/.config
eval make -j"$(nproc --all)" LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- 'CC="ccache clang"' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error olddefconfig
echo "  config 与 opt5 差异行数=$(diff "$BASE/config" out/.config | grep -cE '^[<>]')"

echo "=== 4) 开编 $(date) ==="
rm -f out/Module.symvers
eval make -j"$(nproc --all)" LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- 'CC="ccache clang"' LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error Image 2>&1 | tail -4
echo '=== 5) 读数与闸门 ==='
mkdir -p "$OUT"
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-100
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt8"; cp -f out/System.map "$OUT/System.map.opt8"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt8"
echo "  镜像里 test_task_ux 出现次数(应 0 或 1, 不得进 __ksymtab)=$(strings -a $OUT/Image.opt8 | grep -c test_task_ux)  基线 opt5=$(strings -a $BASE/Image.opt5 | grep -c test_task_ux)"
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt8"
echo '=== 结束 '$(date)' ==='
