#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存基线4.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 留存 v4：起点归一化（等 boot_completed → 设 MGLRU 状态 → 清全部第三方 → 静置）+ 死因取证
# 用法: sh /data/local/tmp/lx4.sh <标签> <Y|N> [N个] [静置秒]
TAG="$1"
STATE="$2"
N="${3:-40}"
DWELL="${4:-120}"
D=/data/local/tmp
NODE=/sys/kernel/mm/lru_gen/enabled

{
echo "标签=$TAG 要求MGLRU=$STATE 目标=$N 静置=${DWELL}s 内核=$(uname -r)"

# 1) 等系统真正起来
i=0
while [ "$i" -lt 90 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i+1))
done
echo "等 boot_completed 用了约 $((i*2))s"
sleep 30

# 2) 设定本轮 MGLRU 状态（模块会在 boot_completed+15s 写 Y，所以 N 组必须在它之后覆盖）
echo "$STATE" > "$NODE"
echo "设定后 enabled=$(cat $NODE) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms)"

# 3) 起点归一化：把全部第三方应用停干净，再静置 60 秒
echo "---- 清全部第三方应用 ----"
for p in $(pm list packages -3 | sed 's/package://'); do am force-stop "$p"; done
sleep 60
echo "起点 PSI: $(head -q -n 1 /proc/pressure/memory)"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
echo "起点应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG"

# 4) 连启被测集合
PKGS=$(pm list packages -3 | sed 's/package://' | head -n "$N")
echo "$PKGS" > "$D/pkglist.$TAG"
: > "$D/launched.$TAG"
for p in $PKGS; do
  monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
  if [ -n "$(pidof "$p")" ]; then echo "$p" >> "$D/launched.$TAG"; fi
done
LP=$(wc -l < "$D/launched.$TAG")
echo "实际启动成功=$LP / 目标 $N"
echo "---- 静置 ${DWELL}s ----"
sleep "$DWELL"

ALIVE=0
DEAD=""
for p in $(cat "$D/launched.$TAG"); do
  if [ -n "$(pidof "$p")" ]; then ALIVE=$((ALIVE+1)); else DEAD="$DEAD $p"; fi
done
echo "==== 结果: 启动 $LP 存活 $ALIVE 消失 $((LP-ALIVE)) ===="
echo "消失清单:$DEAD"
echo "终点应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
echo "终点 PSI: $(head -q -n 1 /proc/pressure/memory)"
echo "终点 MGLRU enabled=$(cat $NODE)"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG.end"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG.end"
DT=$(awk 'NR==FNR{a=$1;next}{printf "%.0f", $1-a}' "$D/up.$TAG" "$D/up.$TAG.end")
echo "本轮墙钟=${DT}s"
awk -v dt="$DT" 'NR==FNR{a[$1]=$2;next} ($1 in a){printf "   %-26s +%10d %8d/s\n", $1, $2-a[$1], ($2-a[$1])/dt}' "$D/vm.$TAG" "$D/vm.$TAG.end"

# 5) 死因取证（消失的包逐个查事件与崩溃缓冲）
echo "---- 死因取证 ----"
for p in $DEAD; do
  echo "  [$p]"
  logcat -b events -d | grep -E "am_proc_died|am_kill" | grep -i -- "$p" | tail -2 | sed 's/^/      /'
done
echo "  crash 缓冲里被测集合的崩溃数=$(logcat -b crash -d | grep -cE "$(echo "$PKGS" | sed -n '1,40p' | paste -sd'|' -)")"
echo "  am_proc_died 总数=$(logcat -b events -d | grep -c am_proc_died)"
ALL=$(logcat -b events -d | grep -c am_kill); SELF=$(logcat -b events -d | grep am_kill | grep -c "due to from pid")
echo "  am_kill 总数=$ALL 人工stop=$SELF 其他=$((ALL-SELF))"
logcat -b events -d | grep am_kill | grep -v "due to from pid" | tail -8 | sed 's/^/    /'

echo "---- 收尾：force-stop 被测集合 ----"
for p in $PKGS; do am force-stop "$p"; done
echo done
} > "$D/留存4.$TAG.txt" 2>&1
cat "$D/留存4.$TAG.txt"
