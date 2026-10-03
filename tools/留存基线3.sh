#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存基线3.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 留存基线 v3：修掉 v2 三处缺陷 —— 记起止 uptime 归一化、区分"我自杀"与"系统查杀"、可选更大 N
# 用法: sh /data/local/tmp/lx3.sh <标签> [N] [静置秒]
TAG="$1"
N="${2:-40}"
DWELL="${3:-90}"
D=/data/local/tmp
PKGS=$(pm list packages -3 | sed 's/package://' | head -n "$N")
echo "$PKGS" > "$D/pkglist.$TAG"

{
echo "标签=$TAG 目标=$N 静置=${DWELL}s 内核=$(uname -r)"
echo "MGLRU enabled=$(cat /sys/kernel/mm/lru_gen/enabled) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms)"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
echo "起点 PSI: $(head -q -n 1 /proc/pressure/memory)"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG"

echo "---- 起始：force-stop 被测集合 ----"
for p in $PKGS; do am force-stop "$p"; done
sleep 5
echo "起始应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"

echo "---- 连启（每个停 5 秒），只把真起来的计入分母 ----"
: > "$D/launched.$TAG"
for p in $PKGS; do
  monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
  if [ -n "$(pidof "$p")" ]; then echo "$p" >> "$D/launched.$TAG"; fi
done
LP=$(wc -l < "$D/launched.$TAG")
echo "实际启动成功=$LP / 目标 $N"

echo "---- 静置 ${DWELL}s 让回收与查杀发生 ----"
sleep "$DWELL"

ALIVE=0
DEAD=""
for p in $(cat "$D/launched.$TAG"); do
  if [ -n "$(pidof "$p")" ]; then ALIVE=$((ALIVE+1)); else DEAD="$DEAD $p"; fi
done
echo "==== 结果: 启动 $LP 存活 $ALIVE 阵亡 $((LP-ALIVE)) ===="
echo "阵亡清单:$DEAD"
echo "终点应用进程数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
head -q -n 3 /proc/meminfo | tr '\n' ' '; echo
echo "终点 PSI: $(head -q -n 1 /proc/pressure/memory)"
cat /proc/uptime | cut -d' ' -f1 > "$D/up.$TAG.end"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > "$D/vm.$TAG.end"

DT=$(awk 'NR==FNR{a=$1;next}{printf "%.0f", $1-a}' "$D/up.$TAG" "$D/up.$TAG.end")
echo "本轮墙钟时长=${DT}s"
echo "---- 回收计数：绝对增量 与 每秒速率 ----"
awk -v dt="$DT" 'NR==FNR{a[$1]=$2;next} ($1 in a){printf "   %-26s +%10d   %8d/s\n", $1, $2-a[$1], ($2-a[$1])/dt}' "$D/vm.$TAG" "$D/vm.$TAG.end"

echo "---- 查杀：区分「我脚本自杀」与「系统查杀」----"
ALL=$(logcat -b events -d | grep -c am_kill)
SELF=$(logcat -b events -d | grep am_kill | grep -c "due to from pid")
echo "am_kill 总数=$ALL  其中人工 stop=$SELF  系统侧=$((ALL-SELF))"
echo "  系统侧明细:"
logcat -b events -d | grep am_kill | grep -v "due to from pid" | grep -v "isolated not needed" | tail -14 | sed 's/^/    /'

echo "---- 复原：force-stop 被测集合 ----"
for p in $PKGS; do am force-stop "$p"; done
echo done
} > "$D/留存.$TAG.txt" 2>&1
cat "$D/留存.$TAG.txt"
