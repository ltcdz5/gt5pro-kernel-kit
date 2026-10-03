#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存基线.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 后台留存基线：连启 N 个应用后，还剩多少进程活着、谁杀的、内核回收了多少。
# 用法（电脑 PowerShell）：
#   D:\gaojizhushou\adb.exe shell "su -c 'sh /data/local/tmp/留存基线.sh 24'"
# ⚠ 会在结束时把测试过的应用 force-stop 以便下一轮同条件重跑；跑之前确认没有正在用的应用在里面。
N="${1:-20}"
PSNAP=/data/local/tmp/psnap

snap() {
  grep -E "^(pgscan_direct|pgscan_kswapd|pgmajfault|workingset_refault_file|workingset_refault_anon|pswpin|pswpout) " /proc/vmstat > "$PSNAP.$1"
  head -q -n 1 /proc/pressure/memory > "$PSNAP.psi.$1"
  head -q -n 1 /proc/uptime > "$PSNAP.up.$1"
}

count_procs() {
  # 数"应用进程"：Android 里每个 app 进程的 USER 形如 u0_aNN（NAME 列不含它，别用 NAME 匹配）
  ps -A -o USER | grep -c "^u[0-9>_]*a[0-9]"
}

echo "== 取起点 =="
snap before
B=$(count_procs)
echo "起点存活应用进程=$B"
echo "起点 PSI: $(cat /proc/pressure/memory | head -1)"

echo "== 连启 $N 个（每个停留 5 秒）=="
i=0
for pkg in $(pm list packages -3 | sed 's/package://' | head -n "$N"); do
  i=$((i+1))
  monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 5
done

echo "== 取终点 =="
snap after
A=$(count_procs)
echo "终点存活应用进程=$A（起点 $B，净留 $((A-B))）"
echo "终点 PSI: $(head -q -n 1 /proc/pressure/memory)"
echo
echo "== 这段区间的内核回收计数增量 =="
while read -r k v; do
  ov=$(grep -m1 "^$k " "$PSNAP.before" | awk '{print $2}')
  [ -n "$ov" ] && echo "   $k: +$((v-ov))"
done < "$PSNAP.after"
echo
echo "== 这期间的查杀事件 =="
logcat -b events -d -t 400 | grep am_kill | tail -12
echo
echo "== 复原本轮启用的应用（force-stop，便于下一轮同条件）=="
i=0
for pkg in $(pm list packages -3 | sed 's/package://' | head -n "$N"); do
  am force-stop "$pkg"
done
echo "done"
