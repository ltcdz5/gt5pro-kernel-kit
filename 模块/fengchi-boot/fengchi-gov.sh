#!/system/bin/sh
# fengchi-boot 守护 v2.6 —— hmbird 与 scx 同时完整在线（用户态时序方案）
#
# ★v2.6 修订依据★：独立复核 F:\工作区\_audit\审核-fengchi-boot v2.5.md（t121 / oc-glmf）。
#   本轮只补 t121 明确要求的两件事，主循环结构不动：
#   D4（§4）版本闸门 fail-closed 落地：未知内核或 opt < MIN_OPT ⇒ HMBIRD_CTL=0 且 GOV_SWITCH=0；
#     且 HMBIRD_CTL=0 时【不再对 hmbird 做任何写或在线探针】（含 hmbird_off 与启动探针）；
#     SAFE_RESTORE / VETO_OFF 保留（无害化动作）。每次启动打一行
#     "version gate: <reason> => ctl=0 govsw=0 (safe_restore/veto still active)"。
#   F1（§2.2）内核自禁盲区：dmesg_state() 从「只解析 hmbird_ctrl() rc=」改为
#     【两路信号按时间序取最新】—— A=proc 写路径行（proc_main.c:299-300），
#     B=内核自禁/自启收尾行 "hmbird (disabled|enabled) finished at jiffies = ..."
#     （hmbird.c:4857 / :5242 → hmbird_switch_log :4570-4579 → hmbird_debug
#      kernel/sched/hmbird.h:46-48）。内核自禁不打 A ⇒ 旧实现会拿到陈旧 "0 1"。
#
# ★v2.5 修订依据★：独立复核 F:\工作区\_audit\审核-fengchi-boot-v2.4.md
#   （t107 / oc-qwen；13 条缺陷 D1~D13）。逐条对照见 F:\工作区\_audit\修复-fengchi-boot-v2.5.md
#   D1(high) 退出游戏不再「裸 scx 常态化」：idle 分支不再看 KEEP_SCX_ON_IDLE，无条件拉回 IDLE_GOV。
#   D2(high) 版本闸门不再「半开」：命中 ⇒ HMBIRD_CTL=0 + GOV_SWITCH=0；由 SAFE_RESTORE 负责纠错。
#   D3(high) 顺序闸门不再把「意图值」当「真实状态」：判 rc（内核真信号）+ dmesg enabled 字段核对。
#   D4 fail-closed（解析不出 opt 号不再放行）；D5 veto 判据改 N/Y 且写后读回；
#   D6 VETO_OFF 默认 0；D7 HMBIRD_CTL=0 时 scx_on 硬失败；D8 退出顺序改为「先关 hmbird 再切 gov」。
#
# ★★ 意图值 vs 真实状态 —— 本脚本最重要的一条（D3）★★
#   意图值：/proc/hmbird_sched/scx_enable
#     proc_main.c:284-285 先 WRITE_ONCE(*pval, val) 发布【意图】；
#     proc_main.c:296-297 rc = ext_ctrl(!!val)；
#     proc_main.c:306-307 if (rc) return -EFAULT —— 【不回滚意图】；
#     proc_main.c:289-290 if (val == old) return count —— 意图==1 时再写 1 是惰性的，不驱动调度器；
#     proc_main.c:265-268 内核注释自己写明：
#       "scx_enable keeps the requested value: the int is the user intent,
#        hmbird_enabled() is the actual state"。
#     ⇒ 意图=1 不代表内核真的启用了 hmbird（-EBUSY @hmbird.c:5022-5040 与
#       -EINVAL @hmbird.c:5398-5402 两条拒绝路径都会留下意图=1）。
#   真实状态（两个可用源，都在内核侧）：
#     A. 写入的 rc —— ext_ctrl() 的返回值原样上报给写者（proc_main.c:306-307 转成 -EFAULT）。
#        enable 是【同步】路径：bpf_hmbird_reg() @hmbird.c:5336-5338 直接内联调用
#        hmbird_ops_enable()，失败点全部 return 非 0；成功点
#        hmbird_switch_log(HMBIRD_ENABLED,1,1,"") @hmbird.c:5242 +
#        scheduler_switch_done(true) @hmbird.c:5244 都在 return 0 之前。
#        ⇒ rc=0 即「真的启用了」；rc!=0 即「内核拒绝」。
#     B. dmesg 的 "hmbird_sched: scx_enable=%d -> hmbird_ctrl() rc=%d, enabled=%d"
#        （proc_main.c:299-300；enabled 取自 hmbird_enabled() = __hmbird_ops_enabled，
#         include/linux/sched/hmbird.h:56 #define hmbird_enabled() atomic_read(&__hmbird_ops_enabled)）
#   ✗ 不是真实状态、禁止用作判据（与 t107 报告 D3 的 requiredFix 措辞不同，依据是下面这些行号）：
#     - /proc/hmbird_sched/scx_enable（意图）
#     - /proc/hmbird_sched/hmbird_stats 的 "SCX Enabled:" —— seq_printf 打的就是同一个
#       scx_enable 意图变量（proc_main.c:345）
#     - /proc/hmbird_sched/hmbirdcore_debug —— 普通 int 数据节点
#       （proc_main.c:420-423 HMBIRD_CREATE_PROC_ENTRY_DATA + hmbird_common_proc_ops），与真实状态无关
#     - 可选第三源：hmbird.c:5310-5320 hmbird_debug_show() 会打印 enabled/enable_state，
#       但 HEAD 1d6ae8398186 全树没有它的注册点（sched_hmbird_fops 只有声明
#       kernel/sched/hmbird.h:190 与定义 hmbird.c:5327，grep 全树无引用）⇒ 设备上可能没有该节点。
#       本脚本运行时探测它，存在才用，不作为必需判据。【未验证】
#
# ★v2.5 相对 v2.4 的行为差异（务必先读）★
#   1) KEEP_SCX_ON_IDLE 默认 0，且 idle/启动清理一律不看它；要真的保留 scx 必须【同时】显式设
#      KEEP_SCX_ON_IDLE=1 与 ALLOW_BARE_SCX_AT_IDLE=1（后者是风险确认，会打 WARN）。
#   2) GOV_SWITCH=0 时守护仍会做「安全的」纠错写 gov（SAFE_RESTORE=1）：把 gov 拉回 IDLE_GOV。
#      这是 D2「半开且永久无纠错」的修复——拉回 IDLE_GOV 永不会制造裸 scx。
#   3) 顺序闸门的「hmbird 在线」判据 = 本轮 hmbird_on() 用 rc/dmesg 证实的真状态，
#      不再是 cat /proc 的意图值。
#   4) VETO_OFF 默认 0（D6）：不再主动拆掉 opt161 的策略层安全垫。
MODDIR=${0%/*}
[ -f "$MODDIR/fengchi.conf" ] && . "$MODDIR/fengchi.conf"
[ -z "$IDLE_GOV" ] && IDLE_GOV=uag
[ -z "$SCX_GOV" ] && SCX_GOV=scx
[ -z "$POLL_SEC" ] && POLL_SEC=4
[ -z "$LOG_DIR" ] && LOG_DIR=/sdcard/Download
[ -z "$LOG_MAX" ] && LOG_MAX=2000
[ -z "$CTB" ] && CTB=1
[ -z "$IDLE_DELAY" ] && IDLE_DELAY=10
[ -z "$HEARTBEAT_MIN" ] && HEARTBEAT_MIN=30
[ -z "$HMBIRD_CTL" ] && HMBIRD_CTL=1
[ -z "$GOV_SWITCH" ] && GOV_SWITCH=1
[ -z "$SCX_REQUIRE_HMBIRD" ] && SCX_REQUIRE_HMBIRD=1
[ -z "$SAFE_GOV_PRELOAD" ] && SAFE_GOV_PRELOAD=1
[ -z "$SAFE_GOV" ] && SAFE_GOV=uag
[ -z "$KEEP_SCX_ON_IDLE" ] && KEEP_SCX_ON_IDLE=0
[ -z "$REASSERT_SEC" ] && REASSERT_SEC=30
[ -z "$VETO_OFF" ] && VETO_OFF=0
# ---- v2.5 新增旋钮（默认全部取最保守值；conf 里都有说明）----
[ -z "$SAFE_RESTORE" ] && SAFE_RESTORE=1
[ -z "$ALLOW_BARE_SCX_AT_IDLE" ] && ALLOW_BARE_SCX_AT_IDLE=0
[ -z "$ALLOW_NO_HMBIRD_SCX" ] && ALLOW_NO_HMBIRD_SCX=0
[ -z "$ALLOW_UNKNOWN_KERNEL" ] && ALLOW_UNKNOWN_KERNEL=0
[ -z "$MIN_OPT" ] && MIN_OPT=160
[ -z "$HMBIRD_REQUIRE_REAL_STATE" ] && HMBIRD_REQUIRE_REAL_STATE=1
[ -z "$HMBIRD_SETTLE" ] && HMBIRD_SETTLE=1
[ -z "$HMBIRD_PROBE_SEC" ] && HMBIRD_PROBE_SEC=60
LOG=$LOG_DIR/fengchi-gov.log
PIDFILE=/data/adb/fengchi-gov.pid
BEAT=/data/adb/fengchi-gov.beat
# ★真状态记录（不是意图值）★：本守护【自己证实过】的 hmbird 真状态，内容 1=在线。
#   只在 rc=0 且真状态核对通过时写入；写 0/被拒绝时删除。用于避免每轮重复走 dmesg，
#   同时避免把「意图残留 1」误当在线。
HB_STATE=/data/adb/fengchi-hmbird.state
HB_PROBE=/data/adb/fengchi-hmbird.probe
CTB_NODE=/proc/game_opt/task_boost/ct_enable
CTB_ORIG=/data/adb/fengchi-ctb.orig
HMBIRD_NODE=/proc/hmbird_sched/scx_enable
HMBIRD_STATS=/proc/hmbird_sched/hmbird_stats
VETO_NODE=/sys/module/kernel/parameters/hmbird_gov_veto
if [ "$REASSERT_SEC" -gt 0 ] 2>/dev/null && [ "$POLL_SEC" -gt 0 ] 2>/dev/null; then
  REASSERT_TICKS=$((REASSERT_SEC / POLL_SEC))
else
  REASSERT_TICKS=0
fi
RA=0
HMBIRD_ONLINE=0
LAST_SETGOV_W=0
LAST_SETGOV_F=0
mkdir -p $LOG_DIR 2>/dev/null

# ---- 单实例保护（D10：判据写进日志；pidfile 失效时扫 /proc 兜底）----
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    c=$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)
    case "$c" in
      *fengchi-gov*)
        # D10：exit 前必须留日志，否则排障时表现为「模块没装」
        echo "[$(date '+%m-%d %H:%M:%S')] daemon already running (pidfile=$old cmdline=[$c]) => exit" >> "$LOG" 2>/dev/null
        exit 0 ;;
    esac
  fi
fi
# D10 兜底：pidfile 写失败或被 pid 复用时 pidfile 判据会漏；扫一遍 /proc
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  [ "$p" = "$$" ] && continue
  c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
  case "$c" in
    *fengchi-gov.sh*)
      echo "[$(date '+%m-%d %H:%M:%S')] daemon already running (pid=$p found by /proc scan) => exit" >> "$LOG" 2>/dev/null
      exit 0 ;;
  esac
done
echo $$ > "$PIDFILE" 2>/dev/null

log(){
  echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
  n=$(wc -l < "$LOG" 2>/dev/null)
  if [ -n "$n" ] && [ "$n" -gt "$LOG_MAX" ] 2>/dev/null; then
    tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
  fi
}
cur(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null; }
has_gov(){ cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
# D11：setgov 逐 policy 写 + 统计写失败（不再被 2>/dev/null 全吞）
setgov(){
  LAST_SETGOV_W=0; LAST_SETGOV_F=0
  for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
    [ -e "$p" ] || continue
    if echo "$1" > "$p" 2>/dev/null; then LAST_SETGOV_W=$((LAST_SETGOV_W + 1));
    else LAST_SETGOV_F=$((LAST_SETGOV_F + 1)); fi
  done
  [ "$LAST_SETGOV_F" = "0" ]
}
# D11：逐 policy 校验（policy0 一致不代表大小核都切成功）
all_gov_is(){
  for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
    [ -e "$p" ] || continue
    [ "$(cat "$p" 2>/dev/null)" = "$1" ] || return 1
  done
  return 0
}
# D11：所有 policy 都注册了 scx 才算「厂商栈就绪」
scx_ready(){
  n=0; bad=0
  for d in /sys/devices/system/cpu/cpufreq/policy*/; do
    [ -f "$d/scaling_available_governors" ] || continue
    n=$((n + 1))
    tr ' ' '\n' < "$d/scaling_available_governors" 2>/dev/null | grep -qx "$SCX_GOV" || bad=$((bad + 1))
  done
  [ "$n" -gt 0 ] && [ "$bad" = "0" ]
}

# ---- ★真实状态探针（D3 + v2.6 F1）★ ----
# 输出 "rc enabled"；不可用则空。★v2.6：两路信号按【时间序】取最新★
#   信号 A = proc 写路径：proc_main.c:299-300 "... hmbird_ctrl() rc=R, enabled=E"
#   信号 B = 内核自禁/自启收尾：hmbird.c:4857（disable 收尾）/ :5242（enable 收尾）
#            → hmbird_switch_log(hmbird.c:4570-4579) → hmbird_debug(kernel/sched/hmbird.h:46-48)
#            → dmesg 行 "<hmbird_sched>:hmbird disabled|enabled finished at jiffies = ..."
#   内核自禁【不打 A】⇒ 只看 A 会拿到上一条陈旧的 "0 1"（t121 §2.2 的盲区）。
#   两路都是内核自己打的日志，不引入第三来源（t121 §2.2 判据要求）。
dmesg_state(){
  # v2.7 fix (2026-10-13 device-proven): the old body captured the whole dmesg
  #   into a shell variable and handed it to an external grep via printf '%s\n' "$_k".
  #   One argv string above MAX_ARG_STRLEN (131072) makes that printf die with
  #   'Argument list too long' => dmesg_state always returned empty.
  #   Measured on device: 40318 B ok, 194594 B fails; this box dmesg ~2.1 MB.
  #   Now: one snapshot into a temp file; grep reads the file (no argv).
  _f=/data/adb/.fengchi-kmsg.$$
  dmesg 2>/dev/null > "$_f"
  if [ ! -s "$_f" ]; then
    rm -f "$_f" 2>/dev/null
    echo FAIL
    return 0
  fi
  _a=$(grep -n 'hmbird_ctrl() rc=' "$_f" | tail -n 1)
  _b=$(grep -nE 'hmbird (disabled|enabled) finished' "$_f" | tail -n 1)
  rm -f "$_f" 2>/dev/null
  _an=$(printf '%s' "${_a%%:*}" | tr -cd '0-9')
  _bn=$(printf '%s' "${_b%%:*}" | tr -cd '0-9')
  if [ -n "$_a" ] && { [ -z "$_b" ] || [ "$_an" -gt "$_bn" ] 2>/dev/null; }; then
    printf '%s\n' "$_a" | sed -n 's/.*rc=\(-*[0-9][0-9]*\), enabled=\([0-9][0-9]*\).*/\1 \2/p'
    return 0
  fi
  if [ -n "$_b" ]; then
    case "$_b" in
      *'disabled finished'*) echo "0 0" ;;
      *'enabled finished'*)  echo "0 1" ;;
    esac
    return 0
  fi
  return 0
}
# 可选第三源：hmbird.c:5310-5320 的 debug 节点（HEAD 无注册点，存在才用）
hb_debug_node(){
  for n in /sys/kernel/debug/sched/hmbird /proc/sched_hmbird; do
    [ -r "$n" ] && { cat "$n" 2>/dev/null; return 0; }
  done
  return 1
}
probe_due(){
  now=$(date +%s 2>/dev/null); last=$(cat "$HB_PROBE" 2>/dev/null)
  [ -z "$now" ] && return 0
  [ -z "$last" ] && return 0
  [ $((now - last)) -ge "$HMBIRD_PROBE_SEC" ] 2>/dev/null && return 0
  return 1
}
stamp_probe(){ date +%s > "$HB_PROBE" 2>/dev/null; }

# ---- ctb（关键线程通路，沿用 v2.3/v2.4，无回归）----
ctb_on(){
  [ "$CTB" = "1" ] || return 0
  [ -w "$CTB_NODE" ] || return 0
  v=$(cat "$CTB_NODE" 2>/dev/null)
  if [ "$v" != "1" ]; then
    [ -f "$CTB_ORIG" ] || echo "$v" > "$CTB_ORIG" 2>/dev/null
    echo 1 > "$CTB_NODE" 2>/dev/null && log "ctb -> 1 (was $v)"
  fi
}
ctb_off(){
  [ "$CTB" = "1" ] || return 0
  [ -f "$CTB_ORIG" ] || return 0
  o=$(cat "$CTB_ORIG" 2>/dev/null)
  if [ -w "$CTB_NODE" ] && [ "$(cat $CTB_NODE 2>/dev/null)" != "$o" ]; then
    echo "$o" > "$CTB_NODE" 2>/dev/null
    log "ctb -> $o (还原)"
  fi
  rm -f "$CTB_ORIG" 2>/dev/null
}

# ---- ★顺序闸门：hmbird 先、scx 后（判据=真状态）★ ----
# hmbird_on 返回 0=真状态已在线 1=未在线/未能证实（调用方据此决定是否切 scx）
hmbird_on(){
  # D7：HMBIRD_CTL=0 必须【硬失败】。v2.4 在这里 return 0（当作在线），
  #     再叠上闸门2 读意图值 ⇒ 完全没开 hmbird 也切 scx。
  [ "$HMBIRD_CTL" = "1" ] || { log "hmbird: HMBIRD_CTL=0 ⇒ 视为【未在线】，本轮禁止切 scx（D7 修复）"; return 1; }
  [ -w "$HMBIRD_NODE" ] || { log "hmbird: WARN 节点 $HMBIRD_NODE 不存在/不可写 ⇒ 未在线"; return 1; }
  intent=$(cat "$HMBIRD_NODE" 2>/dev/null)
  rec=$(cat "$HB_STATE" 2>/dev/null)
  # 路径 1：意图=1 且我们【自己证实过】它在线 ⇒ 确认（每 HMBIRD_PROBE_SEC 才复核一次 dmesg）
  if [ "$intent" = "1" ] && [ "$rec" = "1" ]; then
    if probe_due; then
      ds=$(dmesg_state)
      stamp_probe
      case "$ds" in
        "0 1") log "hmbird: 在线（意图=1 + dmesg rc=0/enabled=1 复核通过）"; return 0 ;;
        "")    log "hmbird: 在线（意图=1 + 真状态记录；dmesg 暂不可用）"; return 0 ;;
        *)     log "hmbird: WARN 意图=1/记录=1 但 dmesg=[$ds] ⇒ 改判未在线"; rm -f "$HB_STATE"; return 1 ;;
      esac
    fi
    return 0
  fi
  # 路径 2：意图=1 但没有我们自己的成功记录 ⇒ 可能是内核拒绝后的【意图残留】
  #   （proc_main.c:285 先发布意图，:307 拒绝时 return -EFAULT 且不回滚）
  #   而 proc_main.c:289-290 在 val==old 时直接 return count、不驱动调度器
  #   ⇒ 重写 1 是惰性的，必须先写 0 制造边沿，才能让内核真的再跑一次 enable。
  if [ "$intent" = "1" ]; then
    log "hmbird: WARN 意图=1 但无成功记录（疑似内核拒绝后的意图残留）⇒ 先写 0 制造边沿再验 rc"
    echo 0 > "$HMBIRD_NODE" 2>/dev/null
    log "hmbird: 边沿准备 -> 0 rc=$?（本来就已禁用时 -EBUSY 属正常）"
    rm -f "$HB_STATE" 2>/dev/null
    sleep "$HMBIRD_SETTLE"
  fi
  echo 1 > "$HMBIRD_NODE" 2>/dev/null
  rc=$?
  nv=$(cat "$HMBIRD_NODE" 2>/dev/null)
  ds=$(dmesg_state); stamp_probe
  # 意图读回值与真状态并列打印（D3 要求「意图与实际的差值写进日志」）
  log "hmbird -> 1 (was $intent) rc=$rc 意图读回=[$nv] 真状态(dmesg)=[${ds:-不可用}]"
  if [ "$rc" != "0" ]; then
    log "hmbird: ★内核拒绝★ rc=$rc（proc_main.c:306-307 转 -EFAULT）⇒ 真状态未启用，本轮绝不切 scx（D3 修复）"
    rm -f "$HB_STATE" 2>/dev/null
    return 1
  fi
  case "$ds" in
    "0 1")
      echo 1 > "$HB_STATE" 2>/dev/null
      return 0 ;;
    ""|FAIL)
      # rc 本身已是内核侧真信号（enable 同步完成才会 return 0），但 dmesg 不可用 ⇒ 按 conf 决定
      if [ "$HMBIRD_REQUIRE_REAL_STATE" = "1" ]; then
        log "hmbird: WARN rc=0 但 dmesg 真状态不可用，HMBIRD_REQUIRE_REAL_STATE=1 ⇒ 保守拒绝切 scx"
        rm -f "$HB_STATE" 2>/dev/null
        return 1
      fi
      log "hmbird: WARN dmesg 不可用，按 rc=0（同步 enable 的返回值）放行；上机后仍无 dmesg 请自行评估"
      echo 1 > "$HB_STATE" 2>/dev/null
      return 0 ;;
    *)
      log "hmbird: WARN rc=0 但 dmesg=[$ds] 未显示 enabled=1 ⇒ 不予确认，拒绝切 scx"
      rm -f "$HB_STATE" 2>/dev/null
      return 1 ;;
  esac
}
hmbird_off(){
  # ★v2.6（t121 §4）★：fail-closed 时 HMBIRD_CTL=0 ⇒ 对 hmbird 不做任何写。
  #   v2.5 的 hmbird_off 不看 HMBIRD_CTL，idle/启动清理仍会写 0（且内核 restore 会写 gov）。
  [ "$HMBIRD_CTL" = "1" ] || { log "hmbird: HMBIRD_CTL=0 ⇒ 不对 hmbird 做任何写（D4 fail-closed）"; return 1; }
  [ -w "$HMBIRD_NODE" ] || { log "hmbird: WARN 节点不可写，无法关闭"; return 1; }
  v=$(cat "$HMBIRD_NODE" 2>/dev/null)
  rm -f "$HB_STATE" 2>/dev/null
  if [ "$v" = "1" ]; then
    echo 0 > "$HMBIRD_NODE" 2>/dev/null
    rc=$?
    # disable 是同步的：bpf_hmbird_unreg() 内 hmbird_ops_disable() + kthread_flush_work()
    # （hmbird.c:5339-5343）⇒ 返回时 hmbird_gov_restore() @hmbird.c:3696 已经跑完。
    log "hmbird -> 0 (was $v) rc=$rc 意图读回=[$(cat $HMBIRD_NODE 2>/dev/null)] 真状态(dmesg)=[$(dmesg_state)]"
    return 0
  fi
  log "hmbird: 意图已=0，无需写（真状态记录已清）"
  return 0
}

# scx_on：三道闸门 —— 就绪 / 顺序（真状态） / 切换+读回
scx_on(){
  [ "$GOV_SWITCH" = "1" ] || return 0
  # 闸门1 就绪：所有 policy 都注册了 scx（厂商栈就绪，~14~43s）
  scx_ready || { log "scx: 有 policy 尚未注册 $SCX_GOV（厂商栈未就绪），本轮跳过"; return 1; }
  # 闸门2 顺序：hmbird 必须【真状态】在线（HMBIRD_ONLINE 由 hmbird_on 的 rc/dmesg 判定得出）
  if [ "$SCX_REQUIRE_HMBIRD" = "1" ] && [ "$HMBIRD_ONLINE" != "1" ]; then
    log "scx: hmbird 真状态未在线，拒绝切 scx（顺序闸门；判据=rc/dmesg，非意图值）"
    return 1
  fi
  all_gov_is "$SCX_GOV" && return 0
  # 闸门3 切换 + 逐 policy 读回校验（D11）
  setgov "$SCX_GOV"
  sleep 1
  if all_gov_is "$SCX_GOV"; then
    log "game -> $SCX_GOV (hmbird 真在线，顺序正确；write_ok=$LAST_SETGOV_W write_fail=$LAST_SETGOV_F)"
    return 0
  fi
  log "scx: 切换失败，policy0=[$(cur)] write_fail=$LAST_SETGOV_F（可能被 t93 否决 / EBUSY）"
  return 1
}

# ---- 启动清理（D1/D8：不看 KEEP_SCX_ON_IDLE；先关 hmbird 再拉回 gov）----
if [ -f "$CTB_ORIG" ]; then ctb_off; log "启动清理：还原残留 ct_enable"; fi
# D5：veto 判据改 N/Y；写完读回；节点缺失/不可写要留日志（v2.4 整块静默）
if [ "$VETO_OFF" = "1" ]; then
  if [ -w "$VETO_NODE" ]; then
    vv=$(cat "$VETO_NODE" 2>/dev/null)
    case "$vv" in
      0|N|n) log "veto: 已是关闭态（[$vv]），不写" ;;
      *)     echo 0 > "$VETO_NODE" 2>/dev/null
             log "veto -> 0 (was $vv) rc=$? 读回=[$(cat $VETO_NODE 2>/dev/null)]" ;;
    esac
  else
    log "WARN: VETO_OFF=1 但 $VETO_NODE 不存在或不可写（D5：不再静默跳过）"
  fi
fi
# ---- 内核版本闸门（D2/D4：fail-closed 且禁止半开）----
# D13 更正：opt160 已把 hmbird_watchdog_workfn 里的周期性强切停用，代码现在是
#   hmbird.c:3762-3823（只有 check_rq_for_timeouts + requeue，无任何 governor 操作）；
#   hmbird.c:3649 的 t50 注释仍写「两个调用点」属文档滞后。
#   因此本闸门的理由不再是「60s 会抢 governor」，而是「未验证的旧/未知内核不放行」。
KREL=$(uname -r 2>/dev/null)
KOPT=$(echo "$KREL" | sed -n 's/.*-opt\([0-9][0-9]*\).*/\1/p')
KOPT=$(echo "$KOPT" | sed 's/^0*//')
case "$KOPT" in
  *[!0-9]*) KOPT= ;;
esac
GATE=none
GATE_REASON=
if [ -z "$KOPT" ]; then
  if [ "$ALLOW_UNKNOWN_KERNEL" = "1" ]; then
    # ★t121 §4★：豁免开关【只对 (a) 未知内核有效】；MIN_OPT 以下不可用任何开关豁免
    log "WARN: 无法从 uname -r 解析 opt 号（[$KREL]），但 ALLOW_UNKNOWN_KERNEL=1（显式豁免，仅对未知内核有效）⇒ 按 conf 执行"
  else
    GATE=unknown
    GATE_REASON="uname -r 解析不出 opt 号（[$KREL]；含厂商串 o-xxxx）"
  fi
elif [ "$KOPT" -lt "$MIN_OPT" ] 2>/dev/null; then
  # (b) 低于 MIN_OPT：任何开关都不能豁免（只能用户显式改 conf 的 MIN_OPT）
  GATE=old
  GATE_REASON="opt$KOPT < MIN_OPT=$MIN_OPT（[$KREL]）"
fi
if [ "$GATE" != "none" ]; then
  # ★D2 修复：禁止半开★ 只降 GOV_SWITCH 会让「hmbird 照开 + 退出时 restore 写回 scx + 守护禁写 gov」
  #   ⇒ 主动制造裸 scx 且永久无纠错。两个能力一起收，纠错交给 SAFE_RESTORE。
  HMBIRD_CTL=0
  GOV_SWITCH=0
  # ★t121 §4 逐字要求的可 grep 判据行★
  log "version gate: $GATE_REASON => ctl=0 govsw=0 (safe_restore/veto still active)"
  log "WARN: 版本闸门命中（$GATE）⇒ HMBIRD_CTL=0 且 GOV_SWITCH=0（禁止半开）；SAFE_RESTORE=$SAFE_RESTORE 仍负责把 gov 纠回 $IDLE_GOV"
fi
# D7 兜底：conf 层面的半开组合（HMBIRD_CTL=0 + GOV_SWITCH=1）直接禁止
if [ "$HMBIRD_CTL" != "1" ] && [ "$GOV_SWITCH" = "1" ] && [ "$ALLOW_NO_HMBIRD_SCX" != "1" ]; then
  GOV_SWITCH=0
  log "WARN: HMBIRD_CTL=0 但 GOV_SWITCH=1（禁止半开）⇒ 强制 GOV_SWITCH=0（D7）"
fi
# 顺序闸门不能被 conf 单方面关掉（D3 的形态就是「没有 hmbird 也切 scx」）
if [ "$SCX_REQUIRE_HMBIRD" != "1" ] && [ "$ALLOW_NO_HMBIRD_SCX" != "1" ]; then
  SCX_REQUIRE_HMBIRD=1
  log "WARN: SCX_REQUIRE_HMBIRD!=1 ⇒ 强制回 1（要绕过必须同时设 ALLOW_NO_HMBIRD_SCX=1）"
fi
# ---- D1：退出后是否保留 scx（默认不保留，且 idle 分支根本不看这个开关）----
IDLE_GOV_KEEP=0
if [ "$KEEP_SCX_ON_IDLE" = "1" ]; then
  if [ "$ALLOW_BARE_SCX_AT_IDLE" = "1" ]; then
    IDLE_GOV_KEEP=1
    log "WARN: KEEP_SCX_ON_IDLE=1 + ALLOW_BARE_SCX_AT_IDLE=1（显式风险确认）⇒ 退出游戏后【保留裸 scx】"
  else
    log "WARN: KEEP_SCX_ON_IDLE=1 已被 v2.5 忽略（D1）：idle 一律拉回 $IDLE_GOV；要保留必须同时显式设 ALLOW_BARE_SCX_AT_IDLE=1"
  fi
fi
IDLE_TICKS=0
HB=0
# 真状态记录与探针文件：新守护启动时清掉（避免上一代的陈旧记录被当成真状态）
rm -f "$HB_STATE" "$HB_PROBE" 2>/dev/null
echo $(date +%s) > "$BEAT" 2>/dev/null
log "daemon start v2.7 pid=$$ (idle=$IDLE_GOV scx=$SCX_GOV poll=$POLL_SEC ctb=$CTB delay=$IDLE_DELAY hmbird_ctl=$HMBIRD_CTL gov_switch=$GOV_SWITCH require_hmbird=$SCX_REQUIRE_HMBIRD safe_restore=$SAFE_RESTORE keep_scx=$KEEP_SCX_ON_IDLE idle_keep=$IDLE_GOV_KEEP veto_off=$VETO_OFF require_real_state=$HMBIRD_REQUIRE_REAL_STATE min_opt=$MIN_OPT gate=$GATE uname=$KREL reassert=${REASSERT_TICKS}x${POLL_SEC}s) [判据: scx 进入用真状态, gov 纠错用 SAFE_RESTORE]"
# 上机可观测性：把真状态源是否可用记进日志（一次）
# ★v2.6（t121 §4）★：HMBIRD_CTL=0 ⇒ 连 hmbird 的在线探针都不做（要求原文「含探针」）
if [ "$HMBIRD_CTL" = "1" ]; then
  _ds=$(dmesg_state)
  if [ "$_ds" = "FAIL" ]; then
    log "WARN: probe: dmesg 读取失败（权限或 ARG_MAX/E2BIG）—— HMBIRD_REQUIRE_REAL_STATE=1 时会保守拒绝切 scx"
  elif [ -n "$_ds" ]; then
    log "probe: dmesg 真状态源可用（最近一条=[$_ds]）"
  else
    log "probe: dmesg 可读，但本 boot 尚无 hmbird 信号行（正常：首次 enable 后才会出现）"
  fi
else
  log "probe: HMBIRD_CTL=0 ⇒ 跳过 hmbird 真状态探针（D4 fail-closed：不写 hmbird、不判在线）"
fi
_gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
case "$_gp" in *game_pid=-1*|"") _g=0 ;; *) _g=1 ;; esac
if [ "$_g" = "0" ]; then
  # D1：不再有 KEEP_SCX_ON_IDLE != 1 前置；D8：先 hmbird_off 再拉 gov
  # ★v2.6（t121 §4）★：HMBIRD_CTL=0 ⇒ 不对 hmbird 做任何写，启动清理也不碰它
  if [ "$HMBIRD_CTL" != "1" ]; then
    log "启动清理：HMBIRD_CTL=0 ⇒ 不碰 hmbird（D4 fail-closed；SAFE_RESTORE 仍会纠 gov）"
  elif [ "$(cat $HMBIRD_NODE 2>/dev/null)" = "1" ] || [ -f "$HB_STATE" ]; then
    hmbird_off
    log "启动清理：无游戏，已关闭 hmbird（先关，restore 已跑完，不会再把 scx 写回）"
  fi
  if [ "$SAFE_RESTORE" = "1" ] && [ "$IDLE_GOV_KEEP" != "1" ] && [ -n "$IDLE_GOV" ] && [ "$(cur)" != "$IDLE_GOV" ] \
     && { [ "$(cur)" = "$SCX_GOV" ] || [ -z "$(cur)" ]; }; then
    setgov "$IDLE_GOV"
    sleep 1
    log "启动清理：无游戏但 gov=[$SCX_GOV]，已切回 $(cur)（write_fail=$LAST_SETGOV_F）"
  fi
fi

while true; do
  gp=$(cat /proc/game_opt/game_pid 2>/dev/null)
  case "$gp" in *game_pid=-1*|"") game=0 ;; *) game=1 ;; esac
  HMBIRD_ONLINE=0
  if [ "$game" = 1 ]; then
    IDLE_TICKS=0
    # (0) SAFE_GOV_PRELOAD：只在 hmbird【真状态】尚未在线时才做
    #     ★限定条件是必需的★（无条件执行会在 6 个轮询里造成 44 次 governor 写入 = 拉锯）
    #     v2.4 这里判的是意图值 ⇒ 意图残留 1 时会跳过预置，让内核把 scx 记进 orig_gov（污染）。
    #     ★判据只用真状态记录 HB_STATE★（不再看意图节点：意图残留 1/真状态 0 时必须照常预置，
    #       否则内核会把 scx 记进 orig_gov —— 这正是 v2.4 的 D3 路径 c）
    if [ "$SAFE_GOV_PRELOAD" = "1" ] && [ "$GOV_SWITCH" = "1" ] && [ -n "$SAFE_GOV" ] \
       && [ "$(cat $HB_STATE 2>/dev/null)" != "1" ] && [ "$(cur)" = "$SCX_GOV" ]; then
      setgov "$SAFE_GOV"
      log "preload -> $(cur) (开 hmbird 前先离开 scx，避免 orig_gov 被污染)"
    fi
    # (1)(2)(3) 顺序闸门：★必须先 hmbird（且真状态确认），后 scx★
    if hmbird_on; then
      HMBIRD_ONLINE=1
      scx_on
    fi
    # ★v2.5 新增（D2 的另一面）★：本轮结束时若 hmbird 真状态不在线，则任何 gov=$SCX_GOV 都是【裸 scx】
    #   （版本闸门/conf 把 GOV_SWITCH 置 0、或内核拒绝了 enable，而 gov 本来就是 scx）。
    #   SAFE_RESTORE 把它纠回 IDLE_GOV —— 这正是 D2「禁写 gov ⇒ 永久无纠错」的反面。
    #   例外：显式风险豁免（SCX_REQUIRE_HMBIRD!=1 且 ALLOW_NO_HMBIRD_SCX=1）时不动 gov。
    if [ "$HMBIRD_ONLINE" != "1" ] && [ "$SAFE_RESTORE" = "1" ] && [ "$IDLE_GOV_KEEP" != "1" ] \
       && [ -n "$IDLE_GOV" ] && [ "$(cur)" = "$SCX_GOV" ] \
       && { [ "$SCX_REQUIRE_HMBIRD" = "1" ] || [ "$ALLOW_NO_HMBIRD_SCX" != "1" ]; }; then
      setgov "$IDLE_GOV"
      log "WARN: hmbird 未在线但 gov=$SCX_GOV（裸 scx）⇒ SAFE_RESTORE 纠回 $(cur)（D2 的另一面）"
    fi
    ctb_on
  else
    # ---- 无游戏（D1 修复：到点后【无条件】拉回 IDLE_GOV，不再看 KEEP_SCX_ON_IDLE）----
    need=0
    case "$(cat $HMBIRD_NODE 2>/dev/null)" in 1) need=1 ;; esac
    [ -f "$HB_STATE" ] && need=1
    [ -f "$CTB_ORIG" ] && need=1
    if [ -n "$IDLE_GOV" ] && [ "$(cur)" != "$IDLE_GOV" ]; then need=1; fi
    if [ "$need" = "1" ]; then
      IDLE_TICKS=$((IDLE_TICKS + POLL_SEC))
      if [ $IDLE_TICKS -ge $IDLE_DELAY ]; then
        # ★D8 修复★：v2.4 是「先写 IDLE_GOV 再关 hmbird」，而 hmbird_gov_restore()
        #   只在 cur == HMBIRD_SAFE_GOV("uag") 时才写回 orig_gov（hmbird.c:3736-3739；
        #   orig 非空才处理 :3712；清条目 :3755）——先写 uag 恰好是【触发写回】的条件，
        #   若 orig 被污染成 scx 就会把 scx 写回去。
        #   v2.5：先 hmbird_off（disable 同步跑完，restore 在返回前执行；此时 cur=scx ≠ uag
        #   ⇒ 走 hmbird.c:3747-3749 的 t55「只打日志不写」分支），再写 IDLE_GOV 兜底。
        hmbird_off
        if [ "$IDLE_GOV_KEEP" = "1" ]; then
          log "WARN: idle(${IDLE_TICKS}s) 保留裸 scx（IDLE_GOV_KEEP=1：KEEP_SCX_ON_IDLE=1 + ALLOW_BARE_SCX_AT_IDLE=1）"
        elif [ "$SAFE_RESTORE" = "1" ] && [ -n "$IDLE_GOV" ]; then
          if [ "$(cur)" != "$IDLE_GOV" ]; then
            setgov "$IDLE_GOV"
            sleep 1
          fi
          if [ "$(cur)" = "$IDLE_GOV" ]; then
            log "idle(${IDLE_TICKS}s) -> $(cur)（hmbird 已先关闭；write_fail=$LAST_SETGOV_F）"
          else
            log "WARN: idle 切回失败，读回=[$(cur)] write_fail=$LAST_SETGOV_F"
          fi
        fi
        ctb_off
      fi
    fi
  fi
  # (6) 低频重申：只在 hmbird【真状态】在线且 gov 掉出 scx 时补一次（对抗未知写者）
  if [ "$game" = 1 ] && [ "$REASSERT_TICKS" -gt 0 ] 2>/dev/null; then
    RA=$((RA + 1))
    if [ $RA -ge $REASSERT_TICKS ]; then
      RA=0
      # v2.4 这里判意图值 ⇒ 意图残留 1/实际 0 时每 30s 把 gov 从 uag 抢回 scx（D3 路径 d）。
      if [ "$HMBIRD_ONLINE" = "1" ] && [ "$GOV_SWITCH" = "1" ] && [ "$(cur)" != "$SCX_GOV" ]; then
        log "reassert: hmbird 真在线但 gov 掉出 [$(cur)] -> 补设 $SCX_GOV"
        setgov "$SCX_GOV"
      fi
    fi
  fi
  # hmbird 失联提示（判据=真状态）
  if [ "$game" = 1 ] && [ "$HMBIRD_CTL" = "1" ] && [ "$HMBIRD_ONLINE" != "1" ]; then
    log "WARN: 游戏中 hmbird 真状态未在线（意图=[$(cat $HMBIRD_NODE 2>/dev/null)] 记录=[$(cat $HB_STATE 2>/dev/null)]），下一轮重试"
  fi
  if [ "$HEARTBEAT_MIN" -gt 0 ] 2>/dev/null; then
    HB=$((HB + POLL_SEC))
    if [ $HB -ge $((HEARTBEAT_MIN * 60)) ]; then
      HB=0
      # D3：意图与真状态并列打印（v2.4 只打意图值，日志不足以证伪）
      log "heartbeat: 运行中 | gov=$(cur) | game=$game | hmbird意图=$(cat $HMBIRD_NODE 2>/dev/null) | hmbird真状态记录=[$(cat $HB_STATE 2>/dev/null)] | dmesg=[$(dmesg_state)] | ctb=$(cat $CTB_NODE 2>/dev/null) | scxdir=$(ls -d /sys/devices/system/cpu/cpufreq/policy*/scx 2>/dev/null | wc -l)"
    fi
  fi
  # D9：心跳文件 —— 让看门狗能发现「进程活着但卡住」
  echo $(date +%s) > "$BEAT" 2>/dev/null
  sleep "$POLL_SEC"
done
