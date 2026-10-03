# modversions CRC 闸门 —— opt15 刷机翻车与补救（2026-10-02）

> **一句话**：opt15 刷上去之后 **WiFi / 蓝牙 / 网络加速全挂**（`lsmod` 621 → 607）。
> 根因是 **modversions CRC 漂移**，而项目原有的导出闸门**只能看见"符号集合"，
> 完全看不见"符号还在但 CRC 变了"**。这次补了两道闸门，其中一道用厂商 `.ko` 的
> `__versions` 做**真值**判定，实测能 100% 预测哪些模块会挂。

---

## 一、事故经过

| 步 | 动作 | 结果 |
|---|---|---|
| 1 | 应用 ACK 第二批 171 条 → 编译失败（5 条缺前置）→ 退 5 条 → 166 条 | `make rc=0` |
| 2 | 跑**导出集合**闸门 `gate_new_exports.py` | **PASS**（新增=6 消失=3，命中厂商 0/0） |
| 3 | 重打包 → `fastboot flash boot_a` → `set_active a` → 重启 | 25 秒开机，看起来正常 |
| 4 | 核对 | 6 个新导出在 `kallsyms`、3 个旧名消失、pstore 空、SELinux Enforcing |
| 5 | **但 `lsmod` = 607，而 opt14 是 621** | ★ 少了 14 个 |
| 6 | 查 dmesg | **9 个模块 `disagrees about version of symbol`** |
| 7 | 查 WiFi | `wlan0` **不存在**，`mac80211` / `qca_cld3_*` 未加载 |
| 8 | 查蓝牙 | `bluetooth` 未加载 |
| 9 | 立刻回退 opt14 | `lsmod` 回到 621，WiFi 恢复 |

### opt15 上挂掉的模块

```
bluetooth                    (sk_filter_trim_cap)          ← 原有问题, 见 §五
mac80211                     (__skb_get_hash)
qca_cld3_kiwi_v2             (__skb_get_hash)
qca_cld3_peach               (__skb_get_hash)
qca_cld3_qca6750             (__skb_get_hash)
rmnet_shs                    (__skb_get_hash)
oplus_connectivity_sla       (nf_ct_delete)
oplus_network_data_module    (tcf_action_exec / tcf_exts_*)
oplus_bsp_game_opt           (缺 __tracepoint_android_vh_scx_*, 另一类, 原有)
```

---

## 二、根因

`CONFIG_MODVERSIONS=y` 时，内核装载模块会走 `check_version()`：把厂商 `.ko`
`__versions` 节里记的 **CRC** 和本内核 `__kcrctab` 里的比，不等就拒载：

```
xxx: disagrees about version of symbol yyy
```

- CRC 由 **genksyms 从"声明"算出**（`scripts/genksyms`）。
  **改函数体不改 CRC；改原型 / 结构体定义会改。**
  ⇒ 风险**全部落在头文件**上。
- 而 `gate_new_exports.py` 只比"导出集合"（谁在 / 谁不在）。
  **符号还在、CRC 变了，它完全看不见。**
- 前几版（opt5…opt14）之所以没踩到，是因为它们的改动集中在
  `mm/` / `fs/f2fs/` / `kernel/sched/` / `block/`，**没碰网络栈的头**。
  这一批 ACK 全是 net/bpf/netfilter，正好踩中。

---

## 三、新增的两道闸门

### 3.1 `tools/gate_crc_drift.py` —— 便宜版（本地即可跑）

```
判据 = { 候选导出 CRC != 能开机基准的 CRC } ∩ { 厂商 .ko 引用过的符号名 }
用法: gate_crc_drift.py <候选 vmlinux.symvers> [基准 Module.symvers] [厂商引用名表]
```

对 opt15 的结果：共同导出 15385，**CRC 漂移 140 个，其中厂商引用 7 个** ——
正是那 7 个致命的。

⚠️ 依赖 `/home/builder/abi/vko_syms.txt`（199295 个名字，但其中只有 2706 个是
真导出）⇒ **这个集合不可靠，只能当快速预警，不能当结论**。

### 3.2 `tools/gate_vko_crc.py` —— **真值版（推荐，以后一律用这个）**

直接从设备上拉下来的**厂商 `.ko`** 里解析 `__versions`，拿厂商**期望的 CRC**
跟候选内核比。`__versions` 每条 64 字节：

```
u32 crc (little-endian) + u32 填充 + char name[56]
```

```
用法: gate_vko_crc.py <候选 vmlinux.symvers> <厂商.ko目录> [更多目录...]
退出码: 0=没有模块会挂  1=有模块会挂  2=输入错误
```

**对 opt15 的结果：493 个厂商模块里 8 个会拒载，符号 8 个 —— 与实测完全一致。**
（第 9 个 `oplus_bsp_game_opt` 是缺符号，属另一类。）

### 3.3 厂商 `.ko` 怎么取（`adb pull` 会被拒）

```bash
# 设备侧(root): 先拷到可读位置
mkdir -p /data/local/tmp/vko /data/local/tmp/vko_sys
cp -f /vendor_dlkm/lib/modules/*.ko /data/local/tmp/vko/
find /system_dlkm/lib/modules -name '*.ko' | while read f; do cp -f "$f" /data/local/tmp/vko_sys/; done
chmod -R 644 /data/local/tmp/vko/*.ko /data/local/tmp/vko_sys/*.ko
chmod 755 /data/local/tmp/vko /data/local/tmp/vko_sys
```
```powershell
# Windows 侧
adb pull /data/local/tmp/vko     ...\vendor-ko\vendor_dlkm
adb pull /data/local/tmp/vko_sys ...\vendor-ko\system_dlkm
```
本地结果：**433 + 60 = 493 个 `.ko`，151.7 MB**（`C:\Users\USERNAME\Desktop\gt5pro-kernel\vendor-ko\`）。

---

## 四、补救

**判据**：CRC 只由头文件决定 ⇒ **凡碰过"本次改动头文件"的补丁全部退掉**，
是保证 CRC 不变的上界。

- 本次改动 139 个文件，其中**头文件 26 个**
- 碰过这 26 个头文件的补丁 = **29 条**（占 171 条的 17%）
- **保留 142 条**（`~/opt15/crc_keep.txt`），退掉 29 条（`~/opt15/crc_revert_superset.txt`）

退掉的 29 条（都是因为改了头，不是因为有错）：

```
670887effc42 ipv4: rename and move ip_route_output_tunnel()        include/net/route.h, include/net/udp_tunnel.h
98440ef214c1 bpf: Add CHECKSUM_COMPLETE to bpf test progs           include/uapi/linux/bpf.h, tools/...
03695e7a2153 scsi: ufs: core: Include UTP error in INT_FATAL_ERRORS include/ufs/ufshci.h
06503e360d35 ipv6: annotate data-races in ip6_multipath_hash_*()    include/net/ipv6.h
19924bdd8a45 netfilter: nf_queue: hold bridge skb->dev while queued include/net/netfilter/nf_queue.h
1c9511ce36fa bpf: Don't use %pK through printk                    include/linux/filter.h
1f1b98fea6b9 net/sched: act_api: use RCU with deferred freeing     include/net/act_api.h
2375e0ec3b86 netfilter: Reorder fields in 'struct nf_conntrack_expect' include/net/netfilter/nf_conntrack_expect.h
30752d8bbd14 bpf: export bpf_link_inc_not_zero.                    include/linux/bpf.h
4e8ebc4c18ea net/sched: teql: Fix double-free in teql_master_xmit  include/net/sch_generic.h
5a1cf5746074 ext4: introduce ITAIL helper                          fs/ext4/xattr.h
5e149d8a8e73 bpf: Add bpf_prog_run_data_pointers()                 include/linux/filter.h
7c679cbc07f1 bpf: Improve program stats run-time calculation      include/linux/filter.h
8429da2ca513 bpf: Clear pfmemalloc flag when freeing all fragments include/net/xdp.h
8b1251bbf0f1 net/sched: act_gate: snapshot parameters with RCU     include/net/tc_act/tc_gate.h
8d5a2c94c24d netfilter: nf_conncount: rework API to use sk_buff     include/net/netfilter/nf_conntrack_count.h
9e1196d27ef4 netfilter: ctnetlink: ensure safe access to master ct include/net/netfilter/nf_conntrack_core.h
aa2a7743a44b crypto: scatterwalk - Backport memcpy_sglist()        include/crypto/scatterwalk.h
ad92ee87462f netfilter: ipset: drop logically empty buckets         net/netfilter/ipset/ip_set_hash_gen.h
b5a010bc7dba ext4: get rid of ppath in ext4_find_extent()          fs/ext4/ext4.h
bfe24a48c1d5 ext4: make ext4_es_remove_extent() return void        fs/ext4/extents_status.h
c4d829737329 ext4: fix use-after-free in update_super_work         fs/ext4/ext4.h
caad62e0a731 netfilter: ipset: use nla_strcmp for IPSET_ATTR_NAME  include/linux/netfilter/ipset/ip_set.h
cb5c028afed9 netfilter: nft_counter: fix reset on 32bit archs      include/linux/u64_stats_sync.h
e23da16dec5a ipv6: fix a race in ip6_sock_set_v6only()             include/net/ipv6.h
e7f6cef9d1fc ipv4: fib: Annotate access to struct fib_alias.fa_state net/ipv4/fib_lookup.h
f311a6f97fc2 scsi: core: Fix error handler encryption support      include/scsi/scsi_eh.h
fb3c380a54e3 net/sched: Only allow act_ct to bind to clsact/ingress include/net/act_api.h
fbfde85308b9 netfilter: nf_conntrack: destroy stale expectfn exp.  include/net/netfilter/nf_conntrack_helper.h
```

> ⚠️ 这是**上界**，其中 ext4 / scsi / ufs / crypto 那几个（7 条）其实碰不到网络符号，
> 很可能可以保留。等 opt15b 过了真值闸门之后，可以逐条试回。
> **顺序永远是：先保证能开机，再谈多收几条。**

### 4.1 两次踩坑（值得记住）

**坑 1：keep 列表的基准用错了。**
第一次我用 `apply_list.txt`（**171** 条）减 29 = 142 条。但那 171 条里**还包含之前
已经排除的 5 条缺前置补丁**（`b3fd3e1e0c35` 等），等于把它们又打回去了 ⇒ 编译炸
4819 行。**基准必须是 `apply_list_166.txt`。**

**坑 2：退掉了别人依赖的"提供者"。**
`aa2a7743a44b crypto: scatterwalk - Backport memcpy_sglist()` 提供了
`memcpy_sglist()`，而 `a69dedc3c482` / `d4c6a6d08e70` 在用它。只退提供者不退消费方
⇒ `error: call to undeclared function 'memcpy_sglist'`。
**退一条补丁前，先查它是不是别人的前置。**

### 4.2 最终结果（opt15c）——**成功**

```
基准     : apply_list_166.txt (166 条)
退料     : 28 条 (29 条 CRC 风险里放回 aa2a7743a44b)
保留     : 138 条
校验     : 保留 ∩ 退料 = 0 ; 保留 ∪ 退料 = 166
应用     : 138/138 成功, 0 失败;  92 files changed, +1171 / -498
构建     : make rc=0, 错误 0
版本串   : 6.1.141-android14-11-o-ltcdz5-opt15   (setlocalversion 已改)
Image    : md5 9c80309d3301434a1bc9de2d8abd855c
待刷件   : boot-opt15c-repacked.img  md5 dfe980d0b493af24d5d129d4352d0c42
```

**两道闸门**：

```
闸门1 导出集合   : 新增=1 消失=0 | 命中厂商 0/0        → PASS (rc=0)
闸门2 CRC 真值   : 493 个厂商模块中 1 个会拒载
                   bluetooth.ko / sk_filter_trim_cap   → 与 opt14 完全一致(原有问题)
```

**刷入后实测**（2026-10-02 02:2x）：

| 项 | opt14 | opt15c |
|---|---|---|
| `uname -r` | `…-opt14` | **`…-opt15`** |
| `uname -v` | `#42 … 00:38:06` | `#44 … 02:23:29` |
| **`lsmod`** | **621** | **621** ✅ |
| `mac80211` / `cfg80211` / `qca_cld3_kiwi_v2` | 在 | **在** ✅ |
| `rmnet_shs` / `oplus_network_data_module` / `oplus_connectivity_sla` | 在 | **在** ✅ |
| `wlan0` | UP | **UP** ✅ |
| `disagrees` 条数 | 3（只有 bluetooth） | **3（只有 bluetooth）** ✅ |
| pstore | 0 | 0 |

⇒ **opt15c = opt14 + 138 条安全补丁，零模块回退。**


---

## 五、顺带查清的两件事

### 5.1 蓝牙**本来**就是坏的，跟我们无关

`bluetooth.ko` 在
`/system_dlkm/lib/modules/**6.1.141-android14-11-o-g6ed3e67335d5**/kernel/net/bluetooth/bluetooth.ko`。

注意那串版本：**`g6ed3e67335d5`** 是**官方 GKI** 的构建号，而我们的内核是厂商的
`ltcdz5`。它期望 `sk_filter_trim_cap = 0xf5845708`，而**能开机的基准内核**给的是
`0x43b2b8f0` —— **基线就对不上**。所以蓝牙在 opt14 上也一样不加载。

### 5.2 `oplus_bsp_game_opt` 也是原有的

它要 `__tracepoint_android_vh_scx_select_cpu_dfl` 等 4 个 SCX tracepoint
（SCX 是 6.12+ 的调度器），本树没有。属**缺符号**，不是 CRC。

---

## 六、纪律（写进流程）

1. **刷机前必须跑两道闸门**：
   - `gate_new_exports.py`（导出集合）
   - `gate_vko_crc.py`（厂商 CRC 真值）
   两道都 PASS 才允许重打包刷机。**rc 必须检查**（0=过, 1=砖, 2=输入错误）。
2. **`git apply --check` 通过 ≠ 能编译**（第一批 5 条缺前置）。
   **能编译 ≠ 能开机**（这一批 CRC 漂移）。
3. **每次刷完必须核 `lsmod` 计数**，跟上一版比。**光看能开机、能上网不够**
   —— 这次 WiFi 挂了我差点没发现，因为当时走的是移动数据。
4. 判据集用的是 `out/**/.<obj>.o.cmd`，它**同时包含 `=m` 模块的目标文件**，
   所以"LAND"只代表"会被编译"，不代表"会进 `boot_a` 的镜像"。
   最终必须再用 `ar t out/vmlinux.a` 过一遍。

---

## 附：本次新增/修改的文件

| 文件 | 说明 |
|---|---|
| `tools/gate_vko_crc.py` | **新增**，厂商 CRC 真值闸门（推荐） |
| `tools/gate_crc_drift.py` | **新增**，本地 CRC 漂移预警（依赖 vko_syms.txt，仅预警） |
| `C:\Users\USERNAME\Desktop\gt5pro-kernel\vendor-ko\` | **新增**，493 个厂商 `.ko`（151.7 MB），真值来源 |
| `~/opt15/crc_keep.txt` | 保留的 142 条 |
| `~/opt15/crc_revert_superset.txt` | 退掉的 29 条 |

*记录日期：2026-10-02*
