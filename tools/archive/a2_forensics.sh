#!/bin/bash
WIN=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/images/不能刷-裸内核
BASE=/home/builder/opt5-baseline
echo '=== 1) 每个裸 Image 的版本串(产物身份证, 证明 -a2 就是那 4 个文件那轮) ==='
for f in "$WIN"/*.img; do
  printf '  %-42s %s\n' "$(basename $f)" "$(strings -a "$f" 2>/dev/null | grep -m1 'Linux version' | cut -c15-60)"
done
echo
echo '=== 2) -a2 那 4 个文件在补丁里各改了什么性质的东西 ==='
python3 - <<'PY'
import re
txt=open('/home/builder/opt6_upstream.patch',errors='replace').read().split('\n')
WANT={'block/blk-mq.c','include/linux/blk-mq.h','include/linux/file.h','android/abi_gki_aarch64_oplus'}
cur=None; buf=[]
def flush():
    if cur and buf:
        add=[l[1:] for l in buf if l.startswith('+') and not l.startswith('+++')]
        rem=[l[1:] for l in buf if l.startswith('-') and not l.startswith('---')]
        print("  --- %s   +%d/-%d 行" % (cur,len(add),len(rem)))
        # 判定性质: 是不是改了 inline / 宏 / 导出白名单
        kind=[]
        for l in add+rem:
            if re.search(r'static inline|#define|EXPORT_SYMBOL',l): kind.append(l.strip()[:96])
        inline_hit = any('static inline' in l or '#define' in l for l in add+rem)
        print("      含 inline/宏/EXPORT 改动: %s" % inline_hit)
        for k in kind[:8]: print("        ", k)
        for l in add[:6]:
            if not l.strip().startswith('*'): print("      +", l.strip()[:96])
        for l in rem[:4]:
            if not l.strip().startswith('*'): print("      -", l.strip()[:96])
for L in txt:
    m=re.match(r'^\+\+\+ b/(.*)$', L)
    if m:
        if cur in WANT: flush()
        cur=m.group(1).strip(); buf=[]
        continue
    if cur in WANT and (L.startswith('+') or L.startswith('-')):
        buf.append(L)
if cur in WANT: flush()
PY
echo
echo '=== 3) 外挂 .ko 通道的前提(和那位作者同一路线) ==='
grep -E '^CONFIG_MODULES=|^CONFIG_MODULE_UNLOAD|^CONFIG_KALLSYMS|^CONFIG_LIVEPATCH|^CONFIG_KPROBES|^CONFIG_FTRACE_KPROBES|^CONFIG_KSU' "$BASE/config" | sed 's/^/  /'
