#!/bin/bash
B=/home/builder/opt5-baseline
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$T" || exit 1
echo "=== 基线目录里各文件的时间戳(判断它到底属于哪次构建) ==="
ls -la "$B"
echo
echo "=== 三方对照: 那 19 个符号在不在 ==="
for f in "$B/System.map" out/System.map; do
  printf "%-46s resched_curr_lazy=%-3s lock_task_fork=%-3s test_task_ux=%-3s 行数=%s\n" \
    "$f" "$(grep -c android_vh_resched_curr_lazy "$f")" "$(grep -c android_vh_lock_task_fork "$f")" "$(grep -c ' test_task_ux$' "$f")" "$(wc -l < "$f")"
done
echo
echo "=== 基线 Module.symvers 里有没有这些(=它属于哪一版) ==="
grep -cE "android_vh_resched_curr_lazy|test_task_ux" "$B/Module.symvers" | sed 's/^/  基线 symvers 命中: /'
grep -cE "android_vh_resched_curr_lazy|test_task_ux" out/Module.symvers | sed 's/^/  当前 symvers 命中: /'
echo
echo "=== 基线 config 与当前 config 的生成时间线索 ==="
head -3 "$B/config" | sed 's/^/  基线: /'
head -3 out/.config | sed 's/^/  当前: /'
echo
echo "=== 直接看两个 Image 的 kallsyms 不可能, 改看 System.map 版本行 ==="
grep -m1 " _stext" "$B/System.map" | head -1 | sed 's/^/  基线 /'
grep -m1 -oE "0000000000[0-9a-f]+ T kernel_init$" out/System.map | sed 's/^/  当前 /'
