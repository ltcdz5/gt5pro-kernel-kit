#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存基线2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 后台留存基线 v2：同起点 ⇒ 连启 N 个第三方应用 ⇒ 静置 ⇒ 数"存活应用/进程" + 回收计数增量 + 查杀原因
# 用法: sh /data/local/tmp/lx2.sh <标签> [N]
TAG="$1"
N="${2:-20}"
OUT=/data/local/tmp/留存.$TAG.txt
PKGS=$(pm list packages -3 | sed 's/package://' | head -n "$N")
echo "$PKGS" > /data/local/tmp/pkglist.$TAG

{
echo "标签=$TAG 目标数=$N 内核=$(uname -r)"
echo "MGLRU enabled=$(cat /sys/kernel/mm/lru_gen/enabled) min_ttl=$(cat /sys/kernel/mm/lru_gen/min_ttl_ms)"
echo "起点: $(head -q -n 1 /proc/pressure/memory) | $(head -q -n 1 /proc/uptime) | 电量$(dumpsys battery | grep -m1 level | tr -d ' ')"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > /data/local/tmp/vm.$TAG
echo "---- 起始清理：force-stop 本轮全部被测应用 ----"
for p in $PKGS; do am force-stop "$p"; done
sleep 5
echo "起始存活应用进程=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
echo "---- 连启（每个停 5 秒）----"
: > /data/local/tmp/launched.$TAG
for p in $PKGS; do
  monkey -p "$p" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
  # 只把"真的起来了"的包计入分母：无 LAUNCHER 入口的服务/覆盖层包不算阵亡
  if [ -n "$(pidof "$p")" ]; then echo "$p" >> /data/local/tmp/launched.$TAG; else echo "   未能启动(无启动器入口): $p"; fi
done
LP=$(wc -l < /data/local/tmp/launched.$TAG)
echo "实际启动成功=$LP / 目标 $N"
echo "---- 静置 90 秒让回收/查杀发生 ----"
sleep 90
ALIVE=0
DEAD=""
for p in $(cat /data/local/tmp/launched.$TAG); do
  if [ -n "$(pidof "$p")" ]; then
    ALIVE=$((ALIVE+1))
  else
    DEAD="$DEAD $p"
  fi
done
echo "==== 结果: 成功启动 $LP 个后存活应用=$ALIVE  阵亡=$((LP-ALIVE)) ===="
echo "阵亡清单:$DEAD"
echo "存活应用进程总数=$(ps -A -o USER | grep -c '^u[0-9>_]*a[0-9]')"
echo "终点: $(head -q -n 1 /proc/pressure/memory)"
grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout|allocstall_normal) " /proc/vmstat > /data/local/tmp/vm.$TAG.end
echo "---- 本段回收计数增量 ----"
awk 'NR==FNR{a[$1]=$2;next} ($1 in a){printf "   %-28s +%d\n", $1, $2-a[$1]}' /data/local/tmp/vm.$TAG /data/local/tmp/vm.$TAG.end
echo "---- 查杀事件（全 events 缓冲，不再截窗口）----"
echo "am_kill 总数=$(logcat -b events -d | grep -c am_kill)"
logcat -b events -d | grep am_kill | tail -12
echo "---- 复原：force-stop 本轮被测应用 ----"
for p in $PKGS; do am force-stop "$p"; done
echo done
} > "$OUT" 2>&1
cat "$OUT"
