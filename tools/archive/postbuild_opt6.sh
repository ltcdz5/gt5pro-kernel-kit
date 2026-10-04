#!/bin/bash
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
cd "$TREE" || exit 1
echo "=== 内核里不能有内置 KSU(要 LKM 走 init_boot) ==="
grep -ci ksu /tmp/ic6.txt
grep -i "ksu\|supersu" /tmp/ic6.txt | head -3 || echo "  (一条都没有, 正确)"
echo
echo "=== opt6 与 opt5 的 config 差异(应只有编译器/版本相关) ==="
diff <(sort "$BASE/config") <(sort /tmp/ic6.txt) | grep -E "^[<>]" | head -20
echo "  差异行数: $(diff <(sort "$BASE/config") <(sort /tmp/ic6.txt) | grep -cE '^[<>]')"
echo
echo "=== 上游那 25 个文件确实进了这次编译(看 .o 时间戳) ==="
for o in fs/eventpoll.o fs/f2fs/checkpoint.o net/unix/garbage.o mm/memory.o kernel/sched/fair.o; do
  printf "  %-26s " "$o"; ls -la "out/$o" 2>/dev/null | awk '{print $6,$7,$8}' || echo 缺
done
echo
echo "=== 把裸 Image 复制到 Windows 侧 ==="
cp -f out/arch/arm64/boot/Image "/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt6-ltcdz5-up0914-raw.img"
ls -la /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-opt6-ltcdz5-up0914-raw.img
md5sum out/arch/arm64/boot.Image out/arch/arm64/boot/Image 2>/dev/null | tail -1
