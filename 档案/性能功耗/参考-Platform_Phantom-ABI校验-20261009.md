# 参考-Platform_Phantom ABI 校验（2026-10-09）

**对象**：`TheVoyager0777/Platform_Phantom` Release `v2026.06.14` 的
`PHANTOM_PINEAPPLE_PRIME-SukiSU-14.06.26.zip` 与 `PHANTOM_PINEAPPLE_NEW_PRIME-SukiSU-14.06.26.zip`
（PINEAPPLE / SM8650，内核 6.1，clang r487747c —— 与我方机型代号一致）。

**口径**：只读校验，不刷机、不装其 SukiSU、不动内核树。工具复用
`tools/gate_all_modules.py`（缺失 ∪ CRC，符号全集 = 内核导出 ∪ 各 .ko 的 `__ksymtab_strings` ∪
`refs/mod-exports-622mods-4623.txt`）与 `tools/gate_vko_crc.py`（纯 CRC）。
opt57 = 内核树 `out/vmlinux.symvers`（15489 导出）；opt55 = `_lab/2026-10-08/scx-step4b/vmlinux.symvers-opt55`（15483 导出）。

## 结论（一句话）

**14 个 .ko 里只有 2 个能装，且单独加载无任何功能意义；真正干活的 12 个装不上。**
原因不是 CRC（**CRC 全对，0 处不符**），而是**符号根本不存在**：
`phantom_vh.ko` 缺 32 个、`phantom_freq_qos.ko` 缺 2 个，
其余 10 个是**传递依赖**这两个模块而连带失败。

## 1. 两个前提需要更正

1. **Release zip 里没有 .ko**。它是 AnyKernel3 刷机包：`Image`(37 MB) + `anykernel.sh` +
   `patch/magisk.zip` + tools。14 个 .ko 藏在 `patch/magisk.zip` → `vendor.erofs`
   （EROFS 镜像 46 MB）→ `modules/`，用 WSL `mount -t erofs -o loop` 解开。
2. **两个 zip 的 `vendor.erofs` md5 完全相同**（`6767e6a335884a701a4ecf4f26f80ac3`）
   ⇒ PINEAPPLE 与 PINEAPPLE_NEW 的 14 个 .ko 是同一份二进制，一个结论覆盖两个包。
3. **它并非"不改 GKI 导出符号"**。`docs/ARCHITECTURE.md` 原文：
   "在 vmlinux 中嵌入轻量 `phantom_stubs.c`（函数指针定义 + EXPORT_SYMBOL）"。
   也就是说**它在自己的 vmlinux 里新增了导出符号**（下面 34 个）。
   "GKI 兼容"指的是不改既有符号语义，**不等于**其 .ko 能装到别的内核上。

## 2. 校验表（opt55 / opt57 结果逐字一致）

| # | .ko | 大小 | 缺失 | CRC不符 | vermagic | 结论 |
|---|-----|-----:|:---:|:---:|------|------|
| 1 | phantom_common.ko | 34024 | 0 | 0 | 6.1.141 SMP preempt mod_unload modversions aarch64 | 可加载（无功能） |
| 2 | phantom_clock.ko | 48368 | 0 | 0 | 同上 | 可加载（无功能） |
| 3 | phantom_freq_qos.ko | 49600 | **2** | 0 | 同上 | **不可用**（自身缺符号） |
| 4 | phantom_vh.ko | 127912 | **32** | 0 | 同上 | **不可用**（自身缺符号） |
| 5 | phantom_slim_walt.ko | 240288 | 0 | 0 | 同上 | 不可用（依赖 phantom_vh） |
| 6 | phantom_render_rt.ko | 24080 | 0 | 0 | 同上 | 不可用（依赖 phantom_slim_walt） |
| 7 | ph_glk.ko | 61144 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 8 | phase_lite.ko | 117480 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 9 | slim_walt_gov.ko | 39696 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 10 | phantom_phase_netlink.ko | 19712 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 11 | phantom_iaware.ko | 62664 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 12 | ph_ipc.ko | 44168 | 0 | 0 | 同上 | 不可用（传递依赖） |
| 13 | binder_prio_mod.ko | 22560 | 0 | 0 | 同上 | 不可用（依赖 phantom_vh） |
| 14 | phantom_perfctl.ko | 236368 | 0 | 0 | 同上 | 不可用（传递依赖） |

- `gate_all_modules.py`：**FAIL modules=2 missing=34 crc=0**（opt55 与 opt57 完全相同）。
- `gate_vko_crc.py`：**PASS，拒载 0**（14 个模块 `__versions` 全部对得上）。
- 两者不矛盾：CRC 全对，问题是**符号不存在**——正是 `gate_all_modules.py` 当初补的盲区。
- 传递依赖闭包：`phantom_vh` 被 8 个模块直接导入，`phantom_freq_qos` 被 2 个（`phantom_perfctl`、`phase_lite`），
  再由 `phantom_slim_walt` / `phase_lite` 扩散到剩余模块 ⇒ 14 − 2 = 12 不可用。

## 3. 缺失的 34 个符号（全量）

```
phantom_vh.ko (32):
  android_vh_alter_rwsem_list_add_hook   check_preempt_wakeup_handler_hook   check_preempt_tick_handler_hook
  mvp_cfs_check_preempt_wakeup_hook      mvp_cfs_replace_next_task_fair_hook mvp_cfs_before_do_sched_yield_hook
  vts_sched_fork_init                    vts_flush_task                      vts_vh_free_task_handler
  vts_vh_dup_task_struct_handler         ph_swalt_enqueue_task               ph_swalt_dequeue_task
  ph_swalt_try_to_wake_up                ph_swalt_tick_entry                 ph_swalt_schedule
  ph_swalt_account_irq                   ph_swalt_wake_up_new_task           ph_swalt_flush_task
  ph_set_task_cpu                        ph_exec_notify                      ph_binder_set_priority
  ph_binder_trans                        ph_binder_transaction_init          ph_binder_proc_transaction_entry
  ph_binder_proc_transaction_finish      ph_binder_proc_transaction          ph_mutex_list_add
  ph_mutex_wait_start                    ph_mutex_unlock_slowpath            ph_rwsem_write_wait_start
  ph_rwsem_wake_finish                   ph_check_file_open

phantom_freq_qos.ko (2):
  freq_qos_set_exclusive_owner           freq_qos_clear_exclusive_owner
```

这 34 个在**他们自己的 `Image` 里都能以明文字符串命中**（`__ksymtab_strings`），
证明由 `phantom_stubs.c` 提供；我方内核与 622 模块参考快照里**一个都没有**。

## 4. vermagic 不是阻碍（机制复核）

- 他们：`6.1.141 SMP preempt mod_unload modversions aarch64`
- 我方：`6.1.141-android14-11-o-ltcdz5-v1.1-opt57 SMP preempt mod_unload modversions aarch64`
- `kernel/module/version.c:80 same_magic()` 在 `CONFIG_MODVERSIONS=y` 时
  **只比较第一个空格之后的部分**（`SMP preempt mod_unload modversions aarch64`）—— 两边一致。
- 我方 `CONFIG_MODVERSIONS=y`（`CONFIG_MODULE_FORCE_LOAD` 未开），现役 493 个厂商模块
  （vermagic `…-g5de16d278e6c`）就是这么加载的。
  ⇒ **vermagic 对所有 14 个 .ko 都不是问题**，判定以符号/CRC 为准。

## 5. 借鉴点清单（做法，不含其代码）

### 5.1 它实际引用的钩子名 → 我方是否已导出

| 它的钩子名 | 形态 | 我方内核 |
|---|---|---|
| `android_vh_alter_rwsem_list_add_hook` | 旧式**函数指针** `_hook` | ❌ 无此名。我方是 tracepoint 形态：`__tracepoint_android_vh_alter_rwsem_list_add` / `__traceiter_…` / `__SCK__tp_func_…`（均已导出 ✓） |
| `android_vh_alter_mutex_list_add_hook` | 它**自己导出** | 同上，名字形态不同 |
| `check_preempt_wakeup_handler_hook`、`check_preempt_tick_handler_hook` | 自有 stub | ❌ 源码 0 命中 |
| `mvp_cfs_check_preempt_wakeup_hook`、`mvp_cfs_replace_next_task_fair_hook`、`mvp_cfs_before_do_sched_yield_hook`、`mvp_can_migrate_task_hook` | 自有 stub | ❌ 0 命中 |
| `find_best_target_handler_hook`、`cpupri_find_fitness_handler_hook`、`migrate_task_handler`、`task_notify_handler`、`render_id_notify_handler`、`mm_task_notify_handler` | 自有 stub | ❌ 0 命中 |
| `vts_sched_fork_init`、`vts_flush_task`、`vts_vh_free_task_handler`、`vts_vh_dup_task_struct_handler` | 自有 stub | ❌ 0 命中 |

**它全程只碰 1 个 GKI 钩子名，而且是 6.1 上已不存在的 `_hook` 旧式形态；其余全是自家 vmlinux 新增导出。**
我方 `android_vh_*` / `android_rvh_*` 导出：opt57 = 1625 个，opt55 = 1619 个
（opt57 比 opt55 多 `android_vh_scx_update_task_scale_time`、`android_vh_task_fits_cpu_scx` 两组）。

### 5.2 可借鉴的技术点

| # | 技术点 | 具体做法 | 可移植性 |
|---|--------|---------|:---:|
| 1 | **Slim WALT** | 20ms 窗口负载跟踪 + 16 级 bucket 平滑预测替代 PELT；**主动压制高通闭源 WALT RVH 避免双轨记账错乱**；热路径运行时开关（A/B 无需重刷） | 中高 |
| 2 | **Phase-Lite AMU** | ARM AMU 硬件计数器按 CPU 采样指令/周期/内存停顿增量 → 实时 IPC + stall% → FreqQoS 查表出最佳 OPP；参数 `phase_lite_cpu_boost_pct / ipc_high_x100 / ipc_low_x100 / stall_pct / mem_boost_pct` | **最高**（纯 AMU + 频率表，不依赖内核新导出） |
| 3 | **GLK 帧感知** | 帧六态 queue/dequeue/vsync/touch/doframe/drawframes；8 帧 Jank 历史 → NONE/LOW/MID/HIGH 四档 boost；场景 idle/bench/schedule/camera/game 切换 | 高 |
| 4 | **iAware 多帧** | 8 帧并发；VLoad 紧迫度随帧时间线非线性增长；帧内 Binder 事务自动编组进同一 RTG | 高 |
| 5 | **IPC Peer** | 前台与 32 对端 Binder+wakeup 频次；MVP Peer 两级（IPC_PEER/BINDER）自动编入 RTG；2s decay + 5s 过期；RCU 回调链投递 | 高 |
| 6 | **Binder Prio** | 30+ 关键服务 RT/FIFO 提升；**专属 workqueue 延后规避 "scheduling while atomic" panic** | 高（踩坑经验，直接照抄） |
| 7 | **PerfCtl 四级 escape** | 低 IPC 2/4/6 帧逐级提频探针 probe_level 1→4，防卡顿不可逆恶化 | 高 |
| 8 | **IFH 回调槽** | `phantom_common` 内置回调指针槽（`phantom_ifh_*`）打破 14 模块循环依赖 | 高（模块化拆分通用手法） |
| 9 | **cmpxchg 原子注册 hook** | 单次原子注册，杜绝中间态指针 EL1 panic | 高 |
| 10 | **PHBT 内嵌引导** | 产物 blob 链进 vmlinux `.rodata`，late_initcall 解析并按序加载 .ko，无需挂载 | 中 |
| 11 | **Phantom VDisk** | sysfs 被动接口 + 用户态触发 erofs 挂载 + Ed25519 签名 + 原子回滚 | 中高 |
| 12 | **Phantom Clock** | 私有 monotonic 时钟，offset + scale(ppm) 校准，不受 NTP/suspend 影响 | 高（帧/功耗时间戳对齐） |

### 5.3 不建议借鉴

`docs/REDACTED.md` 自曝的 5 项删改：MIGT（迁移引导）、Metis 调度反馈、
APEX 透明重定向、内核态 ELF 注入器、PHBT 描述中的 ART 关联。
作者标注"竞品敏感 / 安全审查 / 法律评估"，**合规风险高，不建议借鉴**。

## 6. 对我方的处置建议

1. **不采用其任何二进制**：12/14 装不上，剩余 2 个无功能。刷它的 Image 等于换内核，与"只读校验"边界冲突，不做。
2. **不做符号 shim 移植**：补齐 34 个符号意味着往我方 vmlinux 加一整套 `phantom_stubs.c`
   风格的函数指针导出 —— 这正是它自己承认的"改 vmlinux"，与我方"不新增 GKI 导出面"的既有边界不符。
3. **只取做法**：优先 Phase-Lite AMU（第 2 项）与 Binder Prio 的 workqueue 规避（第 6 项），
   两者都不需要新增内核导出，可在现有 `sched_assist` / hmbird 体系内实现。
4. **工具链已够用**：本次两组闸门在 opt55 / opt57 上给出逐字一致的结论，
   `gate_all_modules.py` 的"缺失 ∪ CRC"双口径再次证明是外源模块准入的正确闸门
   （`gate_vko_crc.py` 单独看会误判为全绿）。

## 7. 证据与归档

- 原始输出：`_lab/2026-10-09/phantom/out/{gate_all_opt55,gate_all_opt57,gate_crc_opt55,gate_crc_opt57}.txt`
- 机器可读表：`_lab/2026-10-09/phantom/out/ko_abi_table.tsv`
- 逐 .ko 明细：`_lab/2026-10-09/phantom/out/analysis.json`
- 14 个 .ko 本体：`_lab/2026-10-09/phantom/ko/{pineapple,pineapple_new}/`
- 其文档：`_lab/2026-10-09/phantom/docs/`
- 归档索引：`_lab/2026-10-09/phantom/README.md`
