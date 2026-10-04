#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/list_overhead_configs.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 列出"性能/开销类"config 现状, 并标出它在树里是否影响结构体定义(粗筛)
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
python3 - <<'PY'
import io, re, subprocess, os
C='/home/builder/kwork/cctv18/repo/local/kernel_workspace/common'
mine={}
for L in io.open(C+'/out/.config', encoding='utf-8', errors='replace'):
    m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L)
    if m: mine[m.group(1)]=m.group(2); continue
    m=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L)
    if m: mine[m.group(1)]='n'
st={}
import gzip
for L in gzip.open('/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/refs/stock_config.gz','rb').read().decode('utf-8','replace').splitlines():
    m=re.match(r'(CONFIG_[A-Za-z0-9_]+)=(.*)',L)
    if m: st[m.group(1)]=m.group(2); continue
    m=re.match(r'#\s*(CONFIG_[A-Za-z0-9_]+)\s+is not set',L)
    if m: st[m.group(1)]='n'

CAND=['FTRACE','FUNCTION_TRACER','SCHED_DEBUG','SCHED_INFO','SCHEDSTATS','TIMER_STATS',
 'PROVE_LOCKING','PROVE_RCU','DEBUG_LOCKUP','HARDLOCKUP_DETECTOR','SOFTLOCKUP_DETECTOR',
 'DEBUG_KERNEL','DEBUG_INFO','DEBUG_INFO_BTF','FRAME_POINTER','KALLSYMS','KPROBES',
 'PM_DEBUG','PM_SLEEP_STATS','LATENCYTOP','SCHED_TRACER','IRQTIME','STACKTRACE',
 'BUG','BUG_ON','UBSAN','KCSAN','GCOV','PROFILE','TRACE_IRQFLAGS','LOCK_STAT',
 'DEBUG_PREEMPT','PREEMPT_VOLUNTARY','PREEMPT_NONE','HZ_','HZ=','NO_HZ','HIGH_RES_TIMERS',
 'CPUIDLE','CPU_IDLE_GOV','THERMAL','CPU_FREQ_GOV','WALT','BLK_CGROUP','MEMCG','WRITEBACK',
 'SLUB','SLUB_DEBUG','DEBUG_OBJECTS','KFENCE','STACKPROTECTOR','RETPOLINE','SPECTRE',
 'MITIGATION','RANDOMIZE_BASE','CFI','SHADOW_CALL_STACK','INIT_ON_ALLOC','INIT_ON_FREE','SANITIZE']
rows=[]
for k,v in sorted(mine.items()):
    if v=='n' or not v: continue
    if not any(c in k for c in CAND): continue
    sv=st.get(k,'<原厂无此项>')
    rows.append((k,v,sv))
print("开着且属于开销/安全钩子类的项 = %d\n" % len(rows))
# 粗筛: 该项在头文件里是否出现在 struct 定义内(启发式)
same=diff=0
for k,v,sv in rows:
    tag='' if str(sv)==v else '  <>原厂不同'
    if str(sv)==v: same+=1
    else: diff+=1
    print("  %-46s 我们=%-6s %s" % (k, v[:6], tag))
print("\n与原厂取值一致 = %d ; 不一致 = %d" % (same, diff))
PY
