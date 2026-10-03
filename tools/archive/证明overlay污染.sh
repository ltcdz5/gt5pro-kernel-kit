#!/system/bin/sh
F=/vendor/lib64/libgsl.so
M=/data/adb/modules/第三方 GPU 模块/system/vendor/lib64/libgsl.so
echo "== 全局 ns：这条 bind mount 在不在 =="
grep -c "libgsl.so" /proc/mounts
echo "== 进私有 ns 后，umount 前后对比 =="
unshare -m sh -c "
echo 卸载前挂载行=\$(grep -c libgsl.so /proc/mounts)
umount $F && echo umount=成功 || echo umount=失败
echo 卸载后挂载行=\$(grep -c libgsl.so /proc/mounts)
echo 原厂侧: \$(stat -c 'dev=%d ino=%i size=%s mtime=%y' $F)
echo 模块侧: \$(stat -c 'dev=%d ino=%i size=%s mtime=%y' $M)
echo 原厂md5=\$(md5sum $F | cut -c1-12)
echo 模块md5=\$(md5sum $M | cut -c1-12)
echo 原厂selinux=\$(ls -Z $F)
echo 模块selinux=\$(ls -Z $M)
"
