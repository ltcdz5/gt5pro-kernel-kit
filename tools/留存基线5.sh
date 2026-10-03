#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存基线5.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 留存 v5：在 v4 基础上补三样仪器（v4 的 A1 轮因此作废）
#   1) 每个阶段边界打时间戳 —— 没打时间戳就无法证明"存活判定"发生在"收尾 force-stop"之前
#   2) 存活判定之前先把 events 快照存盘 —— 否则 am_kill 记录里混着我自己的收尾，死因分不清
#   3) 每个包同时用 pidof 和 ps 两种探针并把原始结果落盘 —— 判定本身要可审计
# 用法: sh /data/local/tmp/lx5.sh <标签> <Y|N> [N个] [静置秒]
TAG="$1"; STATE="$2"; N="${3:-40}"; DWELL="${4:-120}"
D=/data/local/tmp
NODE=/sys/kernel/mm/lru_gen/enabled
T() { echo "[$(date '+%H:%M:%S')] $*"; }

{
T "标签=$TAG 要求MGLRU=$STATE 目标=$N 静置=${DWELL}s 内核=$(uname -r)"

i=0
while [ "$i" -lt 90 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2; i=$((i+1))
done
T "boot_completed=1（自己等了约 $((i*2))s），再静置 30s 让开机尾流走完"
sleep 30

echo "$STATE" > "$NODE"
T "设定后 enabled=$(cat $NODE) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms)"

PKGS=$(pm list packages -3 | sed 's/package://' | head -n "$N")
echo "$PKGS" > "$D/pkglist.$TAG"

T "---- 清全部第三方应用（起点归一化）----"
for p in $(pm list packages -3 | sed 's/package://'); do am force-stop "$p"; done
T "清完，静置 60s"
sleep 60
T "起点 PSI: $(head -q -n 1 /proc/pressure/memory)"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
T "起点应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG"

T "---- 连启（每个停 5 秒）----"
: > "$D/launched.$TAG"
: > "$D/nolaunch.$TAG"
for p in $PKGS; do
  monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
  if [ -n "$(pidof "$p")" ]; then echo "$p" >> "$D/launched.$TAG"; else echo "$p" >> "$D/nolaunch.$TAG"; fi
done
[ -f "$D/nolaunch.$TAG" ] && echo "  无启动器入口被排除的包: $(tr '\n' ' ' < "$D/nolaunch.$TAG")"

T "连启结束，实际启动成功=$(wc -l < "$D/launched.$TAG") / 目标 $N"
T "---- 静置 ${DWELL}s ----"
sleep "$DWELL"

T "---- 存活判定（先抓 events 快照，再判定，保证快照不含我的收尾）----"
logcat -b events -d | grep -E "am_kill|am_proc_died|lowmemorykiller" > "$D/ev.$TAG.snap"
T "快照行数=$(wc -l < "$D/ev.$TAG.snap")"
: > "$D/alive.$TAG.raw"
ALIVE=0; DEAD=""
for p in $(cat "$D/launched.$TAG"); do
  PP=$(pidof "$p")
  SS=$(ps -A -o NAME | grep -cx "$p")
  echo "    $p pidof=[$PP] ps=$SS" >> "$D/alive.$TAG.raw"
  if [ -z "$PP" ]; then DEAD="$DEAD $p"; else ALIVE=$((ALIVE+1)); fi
done
LP=$(wc -l < "$D/launched.$TAG")
T "==== 结果: 启动 $LP 存活 $ALIVE 消失 $((LP-ALIVE)) ===="
echo "消失清单:$DEAD"
echo "  两探针打架的包（pidof 空但 ps 非空 => 判定不可信，要人工复核）:"
grep 'pidof=\[\]' "$D/alive.$TAG.raw" | grep -v 'ps=0' | sed 's/^/    /'

echo "终点应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
echo "终点 PSI: $(head -q -n 1 /proc/pressure/memory)"
echo "终点 MGLRU enabled=$(cat $NODE)"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG.end"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG.end"
DT=$(awk 'NR==FNR{a=$1;next}{printf "%.0f", $1-a}' "$D/up.$TAG" "$D/up.$TAG.end")
echo "本轮墙钟=${DT}s"
awk -v dt="$DT" 'NR==FNR{a[$1]=$2;next} ($1 in a){printf "   %-26s +%10d %8d/s\n", $1, $2-a[$1], ($2-a[$1])/dt}' "$D/vm.$TAG" "$D/vm.$TAG.end"

T "---- 死因取证（只用快照，不重读缓冲）----"
for p in $DEAD; do
  echo "  [$p]"
  grep -- "$p" "$D/ev.$TAG.snap" | tail -2 | sed 's/^/      /'
done
echo "  快照里 am_kill 总数=$(grep -c am_kill "$D/ev.$TAG.snap") 其中人工stop=$(grep am_kill "$D/ev.$TAG.snap" | grep -c 'due to from pid')"
echo "  快照里 am_proc_died 总数=$(grep -c am_proc_died "$D/ev.$TAG.snap")"
echo "  消失清单里、快照中能找到 am_kill 的个数=$(for p in $DEAD; do grep -q -- "$p" "$D/ev.$TAG.snap" && echo x; done | wc -l)"

T "---- 收尾：force-stop 被测集合（此后产生的 am_kill 一律不算进死因）----"
for p in $PKGS; do am force-stop "$p"; done
T "done-marker"
echo done
} > "$D/留存5.$TAG.txt" 2>&1
cat "$D/留存5.$TAG.txt"
