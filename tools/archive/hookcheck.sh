#!/system/bin/sh
# 查两件事: (1) 厂商 .ko 里到底有没有人引用这些 hook 名 (2) 当前内核有没有"符号找不到/版本不符"的加载失败
LOG=/data/local/tmp/hookcheck.txt
: > $LOG
echo "=== vendor .ko 总数 ===" >> $LOG
ls /vendor_dlkm/lib/modules/*.ko 2>/dev/null | wc -l >> $LOG
ls /vendor/lib/modules/*.ko 2>/dev/null | wc -l >> $LOG
echo "=== 逐个 hook 名在 .ko 里的命中文件 ===" >> $LOG
for h in android_vh_resched_curr_lazy android_vh_restore_curr_resched android_vh_clear_curr_lazy android_vh_lock_delay_schedule android_vh_lock_task_fork android_vh_lock_task_exit test_task_ux; do
  hits=$(grep -la "$h" /vendor_dlkm/lib/modules/*.ko /vendor/lib/modules/*.ko 2>/dev/null | tr '\n' ' ')
  echo "$h => ${hits:-无}" >> $LOG
done
echo "=== 当前 dmesg 里的模块加载失败/符号问题 ===" >> $LOG
dmesg | grep -iE "unknown symbol|disagrees about version|Invalid module|could not load|module check|bad kallsyms|version magic" | tail -25 >> $LOG
echo "=== logcat 里 init 报的模块/service 失败(近) ===" >> $LOG
logcat -d -b all 2>/dev/null | grep -iE "modprobe|insmod|Unknown symbol|disagrees" | tail -15 >> $LOG
cat $LOG
