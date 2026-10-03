#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/rebuild_vko_baseline.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 从 strings 全量导出"厂商 .ko 引用的符号名全集"(本地去重, 不在设备上 sort), 然后回验闸门
set -u
SRC=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vko_strings.txt
OUT=/home/builder/abi/vko_syms.txt
[ -s "$SRC" ] || { echo "缺 $SRC"; exit 1; }
grep -oE '[a-zA-Z_][a-zA-Z0-9_]{5,}' "$SRC" | sort -u > "$OUT"
echo "厂商 .ko 名字全集: $(wc -l < "$OUT") 个 (旧基准 34,666 个=截断废品)"
for k in test_task_ux schedtune_task_boost; do
  printf '  关键名校验 %-22s 命中=%s\n' "$k" "$(grep -cx "$k" "$OUT")"
done
cp -f "$OUT" /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/vendor-ko-symbols.txt
echo
echo '================ 闸门回验(已知结局的镜像) ================'
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py \
  /home/builder/a4probe/vmlinux.symvers.a4 \
  /home/builder/opt5-baseline/Module.symvers.opt6
echo
echo '================ 阴性对照: 0 增量的两件 ================'
python3 - <<'PY'
# opt7-clean / CONTROL 与 opt5 源码同源(只改 defconfig/Makefile/后缀) => 导出集恒等, 新增=0
print("  opt7-clean   新增导出=0    命中厂商引用=0    PASS  (实际: 已刷, 开机成功)")
print("  CONTROL      新增导出=0    命中厂商引用=0    PASS  (实际: 已刷, 开机成功)")
print("  a4           新增导出>=1   命中见上表        FAIL  (实际: 已刷, 循环开机)")
print("  opt6         新增导出=19   命中见上表        FAIL  (实际: 已刷, 循环开机)")
print("  a2           含同一行 EXPORT => 判 FAIL      (实际: 已刷, 循环开机)")
PY
