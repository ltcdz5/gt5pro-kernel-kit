#!/bin/bash
# 取 arm64 静态 busybox（QEMU 里当 init 用），走阿里云 ubuntu-ports 镜像
cd /home/builder/qemu-test 2>/dev/null || { mkdir -p /home/builder/qemu-test; cd /home/builder/qemu-test; }
BASE=https://mirrors.aliyun.com/ubuntu-ports/pool/main/b/busybox
echo "=== 目录里有哪些 arm64 deb ==="
wget -q -O - "$BASE/" | grep -oE 'busybox-static_[^"]*_arm64\.deb' | sort -u | tail -5
PKG=$(wget -q -O - "$BASE/" | grep -oE 'busybox-static_[^"]*_arm64\.deb' | sort -u | tail -1)
if [ -z "$PKG" ]; then echo "!! 没抓到包名"; exit 1; fi
echo "=== 下载 $PKG ==="
time wget -q -O "$PKG" "$BASE/$PKG" && ls -l "$PKG"
dpkg-deb -x "$PKG" rootfs-arm64 2>/dev/null || dpkg -x "$PKG" rootfs-arm64
find rootfs-arm64 -name busybox -type f
file $(find rootfs-arm64 -name busybox -type f | head -1)
