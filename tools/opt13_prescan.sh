#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_prescan.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 减脂三项的风险面预判：厂商 .ko 引用名里有没有 __ubsan_* / kfence / init_on_alloc
P=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
V=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/vendor-ko-symbols.txt
cd "$P" || exit 1
echo "vendor-ko-symbols.txt 行数=$(wc -l < "$V")"
echo "--- 厂商引用里的 ubsan 相关 ---"
grep -c "ubsan" "$V"
grep -o "__ubsan[A-Za-z_]*" "$V" | sort -u | head -12
echo "--- 厂商引用里的 kfence / init_on ---"
grep -c -E "kfence|init_on_alloc|init_on_free" "$V"
echo "--- opt12 导出表里这三类符号有多少 ---"
grep -c "__ubsan" out/vmlinux.symvers 2>/dev/null || echo "out/vmlinux.symvers 不在"
grep -c -E "kfence" out/vmlinux.symvers 2>/dev/null
echo "--- 现役 config 三项现值 ---"
grep -E "^CONFIG_UBSAN|^CONFIG_INIT_ON_ALLOC_DEFAULT_ON|^CONFIG_KFENCE_SAMPLE_INTERVAL|^CONFIG_KFENCE=" out/.config
