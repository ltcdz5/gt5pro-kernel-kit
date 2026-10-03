#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/eval_perf_power_list.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 用"只刷 boot"这个过滤器, 判清单里每一项在我们产物里有没有作用面
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
CFG=$C/out/.config
cd "$C" || exit 1
q() { grep -E "^CONFIG_$1=|^# CONFIG_$1 is not set" "$CFG" | head -1 | sed "s/^# //;s/ is not set/=n/"; }

echo "=== A. 作用面判定(=y 才可能随 boot 带走) ==="
for k in FS_VERITY ZRAM ZSMALLOC EROFS_FS F2FS_FS MQ_IOSCHED_DEADLINE MQ_IOSCHED_BFQ \
         DRM_MSM TCG_ASIC_INDIRECT BPF_LSM SCHED_CORE DEBUG_VM LRU_GEN LRU_GEN_ENABLED \
         TCP_CONG_BBR TCP_CONG_CUBIC NET_SCH_FQ VM_EVENT_COUNTS; do
  printf "  %-24s %s\n" "$k" "$(q "$k" || echo '<无此项>')"
done

echo
echo "=== B. 清单点名的具体改动, 在我们树里是否已存在 ==="
chk() { printf "  %-42s %s\n" "$1" "$(grep -rc "$2" $3 2>/dev/null | grep -v ':0$' | head -2 | tr '\n' ' ')"; }
chk "fsverity WQ_UNBOUND (fs/verity|authenc)" "WQ_UNBOUND" "$C/fs/verity $C/fs/crypto"
chk "zram 异步回写 writeback_async" "writeback_async\|async" "$C/drivers/block/zram"
chk "MGLRU 实现文件 mm/lru_gen.c" "" "$C/mm/lru_gen.c"
chk "BBRv3 特征(bbr_is_in_disorder..." "bbr_is_in_congestion_recovery\|BBRv2\|prb_" "$C/net/ipv4/tcp_bbr.c"
chk "TCP PLB" "plb\|PLB" "$C/net/ipv4"
chk "Adreno/kgsl 在本树?" "adreno_a6xx\|kgsl_" "$C/drivers/gpu"
echo
echo "=== C. 这些路径在树里到底有没有源码(没有=不是我们的东西) ==="
for d in fs/verity drivers/block/zram mm/lru_gen.c net/ipv4/tcp_bbr.c drivers/gpu/drm/msm drivers/gpu/msm fs/f2fs; do
  if [ -e "$C/$d" ]; then echo "  在:   $d ($(find "$C/$d" -type f 2>/dev/null | wc -l) 文件)"; else echo "  ⛔ 无: $d"; fi
done
echo
echo "=== D. 运行时可调(不需要编内核)的入口在不在设备上 ==="
"D:/gaojizhushou/adb.exe" shell "su -c 'for p in /sys/class/kgsl/kgsl-3d0/min_pwrlevel /sys/class/kgsl/kgsl-3d0/force_no_nap /sys/block/zram0/idle /sys/block/zram0/comp_algorithm; do printf \"  %-44s \" \${p##*/}; [ -e \$p ] && echo 在 || echo 无; done'" 2>&1 | tr -d '\r'
