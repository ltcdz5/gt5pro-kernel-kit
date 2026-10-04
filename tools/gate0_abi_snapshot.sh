#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/gate0_abi_snapshot.sh
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   作用 : 从 vmlinux 提取 ABI 语料（abidw / libabigail），供 gate0_type_diff.py 比较
#   用法 : gate0_abi_snapshot.sh <vmlinux> <输出.xml>
#   耗时 : 实测 530 MB 的 vmlinux 约 1 分 40 秒，产出约 18.5 MB XML
#   注意 : 语料只含「导出符号可达」的类型（约 5500 个），正是 ABI 关心的那部分
#          产物体积较大，建议放在仓库外（本地 refs），不要提交公开仓库
# ---------------------------------------------------------------------------
set -u
VMLINUX=${1:-}
OUT=${2:-}
[ -n "$VMLINUX" ] && [ -n "$OUT" ] || { echo "用法: $0 <vmlinux> <输出.xml>" >&2; exit 2; }
[ -f "$VMLINUX" ] || { echo "找不到 $VMLINUX" >&2; exit 2; }
command -v abidw >/dev/null || { echo "缺少 abidw（apt install libabigail）" >&2; exit 2; }
echo "提取 ABI 语料: $VMLINUX -> $OUT"
time abidw --no-corpus-path --no-show-locs "$VMLINUX" > "$OUT"
rc=$?
echo "abidw rc=$rc  大小=$(stat -c%s "$OUT" 2>/dev/null) 字节"
exit $rc
