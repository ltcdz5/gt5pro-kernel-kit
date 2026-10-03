#!/system/bin/sh
echo "== /vendor 与相关目录的挂载行 =="
grep -E " /vendor( |/lib64( |/egl| |/hw)|/lib64/egl|/lib64/hw) " /proc/mounts
echo "== overlay 类挂载总行数 =="
grep -c overlay /proc/mounts
echo "== /vendor 的块设备 =="
V=$(grep -m1 " /vendor " /proc/mounts | awk '{print $1}')
echo "device=$V  fstype=$(grep -m1 ' /vendor ' /proc/mounts | awk '{print $3}')"
echo "== 直接看 libgsl 在不在挂载表里（bind 会逐文件列） =="
grep -c "vendor/lib64/libgsl.so" /proc/mounts
echo "== 尝试只读挂到 /dev/tmpv 读真件 =="
mkdir -p /dev/tmpv 2>/dev/null
if mount -o ro "$V" /dev/tmpv -t erofs 2>/dev/null || mount -o ro "$V" /dev/tmpv 2>/dev/null; then
  echo 挂载成功
  stat -c 'dev=%d ino=%i size=%s mtime=%y' /dev/tmpv/lib64/libgsl.so
  echo 真原厂md5=$(md5sum /dev/tmpv/lib64/libgsl.so | cut -c1-12)
  echo 模块md5=$(md5sum /data/adb/modules/第三方 GPU 模块/system/vendor/lib64/libgsl.so | cut -c1-12)
  umount /dev/tmpv
else
  echo 挂载失败=SELinux或文件系统类型限制
fi
