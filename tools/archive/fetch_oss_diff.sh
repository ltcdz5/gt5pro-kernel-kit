#!/bin/bash
# 拉 OnePlusOSS 官方分支(tip 2026-09-14)并与我们的基线 7a244ff18 做结构对比
set +e
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
OSS=https://gh-proxy.com/https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8650
BR=oneplus/sm8650_b_16.0.0_oneplus12
echo "=== $(date +%H:%M:%S) 开始 shallow fetch 官方分支 ==="
git fetch --depth=1 "$OSS" "$BR" 2>&1 | tail -5
echo "=== fetch 结束 $(date +%H:%M:%S), FETCH_HEAD 是什么 ==="
git log -1 --format="%h %cI %s" FETCH_HEAD | cut -c1-140
echo
echo "=== 总体差异规模 (7a244ff18 -> 官方tip) ==="
git diff --stat 7a244ff18 FETCH_HEAD | tail -3
echo
echo "=== 改动最多的目录 (前 20) ==="
git diff --name-only 7a244ff18 FETCH_HEAD | awk -F/ '{if(NF>2) print $1"/"$2; else print $1}' | sort | uniq -c | sort -rn | head -20
echo
echo "=== KMI 关注面: 核心内核/头文件/GKI 配置有没有动 ==="
git diff --stat 7a244ff18 FETCH_HEAD -- kernel mm net include/linux drivers/base init block fs io_uring certs security sound core | tail -25
echo
echo "=== GKI 符号/配置清单有没有动 ==="
git diff --stat 7a244ff18 FETCH_HEAD -- android 'arch/arm64/configs' 'build.config*' | tail -15
echo
echo "=== 导出的符号定义文件(可能改 CRC)抽样 ==="
git diff --name-only 7a244ff18 FETCH_HEAD | grep -E '\.(c|h)$' | grep -vE '^(drivers/(gpu|media|net|platform)|sound|techpack)' | head -25
echo
echo "=== 绿厂私码目录有没有动(kernel/oplus_cpu 等) ==="
git diff --stat 7a244ff18 FETCH_HEAD -- kernel/oplus_cpu drivers/gpu/drm/msm | tail -8
echo "=== 完成 $(date +%H:%M:%S) ==="
