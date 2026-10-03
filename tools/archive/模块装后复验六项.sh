#!/bin/bash
set -u
ADB=/d/gaojizhushou/adb.exe
"$ADB" reboot
echo "已发 reboot $(date '+%H:%M:%S')"
sleep 12
"$ADB" wait-for-device
for i in $(seq 1 120); do
  V=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$V" = "1" ] && { echo "boot_completed=1 $(date '+%H:%M:%S')"; break; }
  sleep 2
done
# 等模块钩子跑完（service.sh 在 boot_completed 后 15s 才写 lru_gen）
sleep 40

echo "===== 1 模块是否已换上清理版 ====="
"$ADB" shell "su -c 'ls /data/adb/modules/第三方 GPU 模块; echo ---; grep -E \"^version\" /data/adb/modules/第三方 GPU 模块/module.prop; echo update标记数=; ls /data/adb/modules/第三方 GPU 模块/update 2>/dev/null | wc -l; echo 暂存区是否已清空=; ls /data/adb/modules_update 2>/dev/null | wc -l'"
echo "===== 2 删掉的项应读为空 ====="
"$ADB" shell "getprop ro.surface_flinger.sched_policy; getprop ro.surface_flinger.enable_layer_caching; getprop ro.egl.blobcache.multifile_limit; getprop ro.hwui.max_texture_allocation_size"
echo "===== 3 保留的伪装项应仍在 ====="
"$ADB" shell "getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked; getprop ro.boot.vbmeta.device_state; getprop ro.secureboot.lockstate; getprop ro.zygote.disable_gl_preload; getprop ro.egl.blobcache.multifile; getprop ro.surface_flinger.enable_frame_rate_override"
echo "===== 4 驱动栈是否真的挂上了（读 /vendor 应等于模块件 md5）====="
"$ADB" shell "su -c 'md5sum /vendor/lib64/libgsl.so | cut -c1-12; md5sum /data/adb/modules/第三方 GPU 模块/system/vendor/lib64/libgsl.so | cut -c1-12; pidof surfaceflinger'"
echo "===== 5 内核与 MGLRU ====="
"$ADB" shell "su -c 'uname -r; cat /sys/kernel/mm/lru_gen/enabled; tail -3 /data/adb/lru_gen_on/state.log'"
echo "===== 6 开机里程碑与 /data 余量 ====="
"$ADB" shell "logcat -b events -d | grep -E 'boot_progress_start|boot_progress_enable_screen' | tail -2"
"$ADB" shell "df /data | tail -1"
"$ADB" shell "dumpsys battery | grep -m1 level"
echo done-marker
