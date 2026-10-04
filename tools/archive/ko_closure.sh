#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE"; git config --global --add safe.directory "$TREE" 2>/dev/null
export PATH="$HOME/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"

echo '=== A) 那 61 个 .ko 是什么来路 ==='
find /home/builder /mnt/c/Users/xutengfa/Desktop -name '*.ko' 2>/dev/null | sed 's/^/  /' | head -12
echo "  总数=$(find /home/builder /mnt/c/Users/xutengfa/Desktop -name '*.ko' 2>/dev/null | wc -l)"

echo
echo '=== B) blk-mq 那个开关在我们配置里是什么值(-a2 的头文件改动按它二选一) ==='
grep -E 'CONFIG_BLK_MQ_USE_LOCAL_THREAD' "$BASE/config" | sed 's/^/  /'
grep -n 'CONFIG_BLK_MQ_USE_LOCAL_THREAD' kernel/block/Kconfig block/Kconfig 2>/dev/null | head -3 | sed 's/^/  /'

echo
echo '=== C) -a2 的两个头文件改动, 在当前配置下到底是"活代码"还是死分支 ==='
git diff opt5-state -- include/linux/blk-mq.h 2>/dev/null | head -5 | tr -d '\r'
echo "  (工作区现在是 opt7-clean, 上面为空属正常; 真正的判定看下面)"
grep -n -A4 'ifdef CONFIG_BLK_MQ_USE_LOCAL_THREAD' include/linux/blk-mq.h 2>/dev/null | head -12 | sed 's/^/  /'

echo
echo '=== D) 厂商 .ko 的未定义符号闭集 vs opt5 导出表 ==='
LS=/home/builder/opt5-baseline/Module.symvers
python3 - <<'PY'
import subprocess, os, glob, re
ko = []
for r in ['/home/builder','/mnt/c/Users/xutengfa/Desktop']:
    for dp,dn,fn in os.walk(r):
        for f in fn:
            if f.endswith('.ko'): ko.append(os.path.join(dp,f))
ko = sorted(set(ko))
print("  .ko 数量=%d" % len(ko))
if not ko:
    raise SystemExit(0)
exports = {}
for L in open('/home/builder/opt5-baseline/Module.symvers', errors='replace'):
    p = L.rstrip('\n').split('\t')
    if len(p) >= 4: exports[p[1]] = (p[0], p[2], p[3])
print("  opt5 导出符号数=%d" % len(exports))
need = {}
for k in ko[:400]:
    try:
        out = subprocess.run(['llvm-nm','-u','--format=posix',k],capture_output=True,text=True,timeout=25).stdout
    except Exception:
        continue
    for line in out.splitlines():
        m = re.match(r'^(\S+)\s+UND', line)
        if m and not m.group(1).startswith(('__check_env','_ddebug','module_')):
            need.setdefault(m.group(1), set()).add(os.path.basename(k))
print("  这些 .ko 引用的未定义符号总数=%d" % len(need))
miss = [s for s in need if s not in exports]
print("  opt5 里没有的(=靠内建/别的模块提供, 或根本不该有)=%d" % len(miss))
core = [s for s in miss if not s.startswith(('oplus','hmbird','gki_','__cf'))]
print("  其中不像模块间符号的=%d, 前 20 个:" % len(core))
for s in sorted(core)[:20]: print("     ", s, "  <-", ",".join(sorted(need[s])[:2]))
PY
