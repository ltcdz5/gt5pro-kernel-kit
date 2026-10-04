#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/hmbird_wiring.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# hmbird 能不能开: 看 kernel/oplus_cpu 有没有被接进构建、缺什么
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
git config --global --add safe.directory "$PWD" 2>/dev/null
echo "=== 1) oplus_cpu 目录规模与真实文件 ==="
git ls-files kernel/oplus_cpu | wc -l
find kernel/oplus_cpu -name '*.c' | wc -l | sed 's/^/  .c 文件数=/'
ls -la kernel/oplus_cpu/ | head -12 | sed 's/^/  /'
echo
echo "=== 2) hmbird 相关文件与大小(空壳/符号链接会露出来) ==="
find kernel/oplus_cpu -iname '*hmbird*' -o -iname '*sched_assist*' -o -path '*sched_ext*' | head -20 |
while read -r f; do printf '  %-62s %s 字节\n' "$f" "$(stat -c%s "$f" 2>/dev/null)"; done
echo
echo "=== 3) 谁引用 kernel/oplus_cpu（顶层接线） ==="
grep -rn "oplus_cpu" kernel/Makefile Makefile init/Kconfig kernel/Kconfig* 2>/dev/null | head -8 | sed 's/^/  /'
echo "  oplus_cpu 自己的 Kconfig/Makefile:"
ls kernel/oplus_cpu/Kconfig* kernel/oplus_cpu/Makefile 2>/dev/null | sed 's/^/    /'
echo
echo "=== 4) hmbird 的 Kconfig 开关名 + 现役配置里的值 ==="
grep -rhoE 'config [A-Z0-9_]*(HMBIRD|SCHED_ASSIST|OPLUS_SCHED)[A-Z0-9_]*' kernel/oplus_cpu 2>/dev/null | sort -u | head -10 | sed 's/^/  /'
for k in $(grep -rhoE 'config ([A-Z0-9_]*(HMBIRD|SCHED_ASSIST)[A-Z0-9_]*)' kernel/oplus_cpu 2>/dev/null | awk '{print $2}' | sort -u); do
  printf '  CONFIG_%-34s 现役=%s\n' "$k" "$(grep -m1 "^CONFIG_$k" /home/builder/opt5-baseline/config || echo '(无此项)')"
done
echo
echo "=== 5) sa_hmbird.c 的依赖(缺一个就编不动) ==="
grep -nE '^#include' kernel/oplus_cpu/sched/sched_assist/sa_hmbird.c 2>/dev/null | head -14 | sed 's/^/  /'
echo "  --- 其中本地/厂商头是否存在 ---"
for h in $(grep -oE '<[a-z0-9_/]+\.h>' kernel/oplus_cpu/sched/sched_assist/sa_hmbird.c 2>/dev/null | tr -d '<>' | sort -u); do
  [ -e "include/$h" ] || echo "     缺 include/$h"
done
echo
echo "=== 6) 原厂内核里 hmbird 是真的编进去了吗(符号地址) ==="
echo "  注: 我们的 System.map(opt5) 里 hmbird 行数=$(grep -ic hmbird /home/builder/opt5-baseline/System.map)"
strings -a /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot_a.img | grep -iE 'hmbird' | sort -u | head -12 | sed 's/^/     原厂串: /'
