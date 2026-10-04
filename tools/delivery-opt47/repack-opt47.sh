set -u
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
echo "=== ① 确认 out/ 里就是 opt47 的 Image ==="
strings -a out/arch/arm64/boot/Image | grep -m1 -oE "#[0-9]+-ack304-v1.1-opt[0-9]+"
ls -l out/arch/arm64/boot/Image
echo
echo "=== ② 打包 ==="
IMG=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-v1.1-opt47-repacked.img
STOCK=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot_a.img
python3 /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/tools/repack_any.py out/arch/arm64/boot/Image "$IMG" "$STOCK" 2>&1 | tail -7
echo "repack rc=${PIPESTATUS[0]}"
echo
echo "=== ③ 核验 ==="
ls -l "$IMG"
md5sum "$IMG" | cut -c1-32
md5sum out/arch/arm64/boot/Image | cut -c1-32
strings -a "$IMG" | grep -m1 -oE "ltcdz5-v1.1-opt47"
