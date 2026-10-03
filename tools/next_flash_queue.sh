#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/next_flash_queue.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
echo '=== 1) 现役配置里可用的 zram 压缩器 ==='
grep -E 'CONFIG_LZ4=|CONFIG_LZ4HC|CONFIG_LZ4_COMPRESS|CONFIG_ZSTD|CONFIG_ZRAM|CONFIG_ZSMALLOC|CONFIG_ZSWAP' /home/builder/opt5-baseline/config
echo
echo '=== 2) 设备当前实际在用什么(上次 adb 读数已记录为 zstd, 这里只核配置侧) ==='
grep -E 'CONFIG_ZRAM_DEF_COMP' /home/builder/opt5-baseline/config
echo
echo '=== 3) 闸门能否扩到"结构体布局"这一类: 厂商模块名字全集里有没有这些类型名 ==='
for t in eventpoll deadline_wq sched_attr rq task_struct mm_struct inode file; do
  printf '  %-14s 命中=%s\n' "$t" "$(grep -cx "$t" /home/builder/abi/vko_syms.txt)"
done
echo
echo '=== 4) 当年 25 文件补丁里, 哪些文件会新增导出(=按新规则一律不搬) ==='
python3 - <<'PY'
import re
txt=open('/home/builder/opt6_upstream.patch',errors='replace').read().split('\n')
cur=None; hits={}
for L in txt:
    m=re.match(r'^\+\+\+ b/(.*)$',L)
    if m: cur=m.group(1).strip(); hits.setdefault(cur,[]); continue
    if cur and L.startswith('+') and not L.startswith('+++'):
        if re.search(r'EXPORT_SYMBOL|DEFINE_HOOK|DECLARE_HOOK|CREATE_TRACE', L):
            hits[cur].append(L[1:].strip()[:70])
bad=[(k,v) for k,v in hits.items() if v]
print("  会新增导出的文件 = %d / 总 %d" % (len(bad), len(hits)))
for k,v in bad:
    print("   ⛔", k)
    for x in v[:3]: print("         ", x)
print("\n  其余(不新增导出, 可按规则评估) :")
for k,v in hits.items():
    if not v and k!='android/abi_gki_aarch64_oplus': print("   ✓", k)
PY
