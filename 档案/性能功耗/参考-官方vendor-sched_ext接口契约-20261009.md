# 参考 — 官方 vendor 侧 sched_ext 接口契约（内核侧对照实现清单）

- 日期：2026-10-09
- 目的：把**官方 vendor 侧** sched_ext/风驰 对**内核侧**的接口要求逐条提出，供自编 6.1.141/SM8650 内核对照实现。
- 纪律：未改内核树、未刷机、未改 config。

## 0. 结论摘要（TL;DR）

1. **契约清单 = 126 条符号 + 31 条节点 + 9 条钩子**。模块 `oplus_bsp_sched_ext.ko` 的 ELF 未定义符号（`U`）共 **126** 个：出厂内核已导出 **119** 个、别的厂商 .ko 提供 **1** 个、本机现有料中找不到提供者 **6** 个。
2. 与**我们 opt55** 对照：**119/126 已具备，缺 7 条** —— 缺的全是「风驰内核核心/外围」，不是通用内核设施。
3. **最关键**：内核侧必须实现并导出 **`register_hmbird_sched_ops`**（唯一注册入口）+ 让 **`hmbird_dir`** 指向 `/proc/hmbird_sched`。没有前者模块**连装载都过不了**（未定义符号）；没有后者条目会落到 `/proc` 根。
4. **代际不一致（易踩）**：本仓 @99b1344 这一代用 `register_sysctl("oplus_sched_ext", ...)`，**根本不建 `/proc/hmbird_sched`**；而**实机 .ko**（Gen B）用 `proc_mkdir` + `hmbird_dir` + `register_hmbird_sched_ops`。两者**不是同一代**，不能混用。
5. **OGKI/GKI**：`hmbird_ogki/` 是 3 个文件的空壳（`scx_init()` 直接 `return 0`）。**qcom 平台编的是 `hmbird_gki/`**。运行期 `main.c` 还按 DT `/soc/oplus,hmbird/version_type` 的 `type` 决定是否调用 `scx_init()` —— DT 写 `HMBIRD_OGKI` 就一个节点都不建。

---

## 1. 权威源与取证方法

| 来源 | 标识 | 用途 |
|---|---|---|
| 官方 vendor 源码仓 | `realme-kernel-opensource/realme_15pro5G-AndroidV-vendor-source` @ `99b13443e39dc9c15f150b14134298443b406cf4` | 节点/钩子/`scx_enable` 语义的**声明面** |
| 实机厂商模块 | `oplus_bsp_sched_ext.ko`（87,840 B，`vermagic=6.1.141-android14-11-o-g5de16d278e6c SMP preempt mod_unload modversions aarch64`） | **符号契约的权威来源**（`U` 表 + `__versions` CRC） |
| 出厂导出表 | `stock_exports.json`（63,569 条） | 出厂内核已导出符号 |
| 我们内核 | `vmlinux.symvers-opt55`（15,483 条） | 现状对照 |

取法：`gh api repos/<repo>/contents/<path>?ref=<sha> --jq .content` → base64 解码（16 个文件已取全，落 `_lab/2026-10-09/vendor-iface/src/`）；`U` 表由**自写 ELF64 解析器**直接读 `.symtab`（本机无 readelf/nm/pyelftools）。

> **重要发现（代际不一致）**：本仓 @99b1344 的 `sched_ext/` 目录里**没有** `hmbird/` 子目录，也没有任何 `proc_create`/`proc_mkdir`；而实机 .ko 字符串里有 `../vendor/oplus/kernel/cpu/sched_ext/hmbird/hmbird_misc.c`、`hmbird_common_open/show/write`、`proc_mkdir`。**⇒ 实机模块比本仓新一代**（本仓 Gen A、实机 Gen B）。下文符号契约以**实机 .ko** 为准（它才是要装进内核的那个），节点/语义两代都列。

---

## 2. 内核侧必须提供的符号清单（模块 `U` 引用，共 126 条）

图例：`Y` =出厂内核已导出 / `D` =由别的厂商 .ko 提供 / `N` =本机现有料中无提供者；末列 `Y`=我们内核已导出。

### 2.1 与我们的差距（7 条）

| 符号 | 出厂内核 | 提供者 | 性质 |
|---|---|---|---|
| `get_hmbird_cpu_exclusive` | D | oplus_bsp_game_opt.ko | 由 oplus_bsp_game_opt.ko 提供（同批厂商模块，非内核） |
| `msm_minidump_add_region` | N | -(dump 未含提供者) | 由 minidump.ko 提供（本机 vendor-ko 转储未含该模块） |
| `register_hmbird_sched_ops` | N | -(dump 未含提供者) | **唯一注册入口**；内核侧须实现并 EXPORT_SYMBOL_GPL（我们树在 kernel/oplus_cpu/sched/sched_assist/sa_hmbird.c，被 CONFIG_OPLUS_FEATURE_SCHED_ASSIST + CONFIG_HMBIRD_SCHED 两道闸门挡住） |
| `register_walt_ops` | N | -(dump 未含提供者) | WALT 侧，由 sched-walt.ko 提供（转储未含） |
| `sched_ravg_window` | N | -(dump 未含提供者) | WALT 侧，由 sched-walt.ko 提供（转储未含） |
| `walt_rq` | N | -(dump 未含提供者) | WALT 侧，由 sched-walt.ko 提供（转储未含） |
| `waltgov_cb_data` | N | -(dump 未含提供者) | WALT 侧，由 sched-walt.ko 提供（转储未含） |

### 2.2 出厂内核已导出、我们也已具备的核心契约符号

| 符号 | 语义 |
|---|---|
| `hmbird_dir` | `struct proc_dir_entry *`；内核须 `proc_mkdir("hmbird_sched", NULL)` 并把指针**赋给它**（我们 `hmbird_export.c` 只导出、未赋值 ⇒ 见 §7 风险 R1） |
| `iso_masks` | `struct scx_iso_masks`；CPU 隔离掩码，模块按**裸偏移**索引（`ex_free@0x00, exclusive@0x08, partial@0x10`），成员顺序不可改 |
| `non_ext_task` | `atomic_t`；非风驰任务计数 |
| `ext_module_loaded` | `atomic_t`；模块加载标志 |
| `__scx_ops_enabled` | `atomic_t`；上游 static key 被改成普通原子量以便共享 |
| `task_is_scx` | `bool task_is_scx(struct task_struct *p)`；须持 rq lock |
| `scx_get_md_info` | `void scx_get_md_info(unsigned long *vaddr, unsigned long *size)`；minidump 区，出厂返回 0x1000 的 kmalloc 缓冲 |
| `scx_sched_rq_stats` | per-CPU 统计结构 |
| `scx_irq_work_lastq_ws` | `atomic64_t` 窗口时间戳 |
| `slim_for_app` | `int`；slim/风驰 面向 app 的开关 |

### 2.3 其余已具备符号

共 112 条，全部为出厂内核已导出的通用设施或钩子：`__arch_copy_from_user`、`__bitmap_andnot`、`__bitmap_weight`、`__check_object_size`、`__cpu_online_mask`、`__cpu_possible_mask`、`__cpufreq_driver_target`、`__kmalloc`、`__kthread_init_worker`、`__list_add_valid`、`__list_del_entry_valid`、`__mutex_init`、`__per_cpu_offset`、`__stack_chk_fail`、`__trace_bprintk`、`__trace_bputs`、`__trace_trigger_soft_disabled`、`__tracepoint_android_rvh_before_do_sched_yield`、`__tracepoint_android_vh_get_util`、`__tracepoint_android_vh_hmbird_init_task`、`__tracepoint_android_vh_hmbird_update_load`、`__tracepoint_android_vh_hmbird_update_load_enable`、`__tracepoint_android_vh_scheduler_tick`、`__tracepoint_android_vh_tick_nohz_idle_stop_tick`、`__tracepoint_sched_switch`、`__warn_printk`、`_find_first_bit`、`_find_next_bit`、`_printk`、`_raw_spin_lock_irqsave`、`_raw_spin_unlock_irqrestore`、`alt_cb_patch_nops`、`android_rvh_probe_register`、`balance_push_callback`、`bpf_trace_run6`、`cpu_hwcaps`、`cpu_number`、`cpu_scale`、`cpu_topology`、`cpufreq_cpu_get`、`cpufreq_disable_fast_switch`、`cpufreq_driver_fast_switch`、`cpufreq_driver_resolve_freq`、`cpufreq_enable_fast_switch`、`cpufreq_register_governor`、`cpufreq_unregister_governor`、`fortify_panic`、`get_governor_parent_kobj`、`gic_nonsecure_priorities`、`gov_attr_set_get`、`gov_attr_set_init`、`gov_attr_set_put`、`governor_sysfs_ops`、`have_governor_per_policy`、`hrtimer_active`、`hrtimer_cancel`、`hrtimer_init`、`hrtimer_start_range_ns`、`irq_work_queue`、`irq_work_queue_on`、`irq_work_sync`、`kfree`、`kimage_voffset`、`kmalloc_caches`、`kmalloc_trace`、`kobject_init_and_add`、`kobject_put`、`kstrtoint`、`kthread_bind_mask`、`kthread_cancel_work_sync`、`kthread_create_on_node`、`kthread_flush_worker`、`kthread_queue_work`、`kthread_stop`、`kthread_worker_fn`、`ktime_get`、`memset`、`memstart_addr`、`mutex_lock`、`mutex_unlock`、`nr_cpu_ids`、`perf_trace_buf_alloc`、`perf_trace_run_bpf_submit`、`preempt_schedule_notrace`、`proc_create_data`、`proc_mkdir`、`raw_spin_rq_lock_nested`、`raw_spin_rq_unlock`、`runqueues`、`sched_clock`、`sched_setattr_nocheck`、`seq_lseek`、`seq_printf`、`seq_read`、`single_open`、`single_release`、`sprintf`、`sscanf`、`strim`、`strlen`、`synchronize_rcu`、`trace_event_buffer_commit`、`trace_event_buffer_reserve`、`trace_event_printf`、`trace_event_raw_init`、`trace_event_reg`、`trace_handle_return`、`trace_raw_output_prep`、`tracepoint_probe_register`、`update_rq_clock`、`usleep_range_state`、`wake_up_process`

### 2.4 modversions：只对齐符号名不够

模块 `vermagic` 含 **`modversions`**，`.ko` 内有 **`__versions` 段共 127 条 CRC**（例：`hmbird_dir=0x947ca90f`、`__scx_ops_enabled=0x85f027ab`）。内核侧**必须同时满足「符号已导出」且「CRC 一致」**，否则装载报 `disagrees about version of symbol`。

### 2.5 模块依赖链

`depends = sched-walt, oplus_bsp_game_opt, oplus_bsp_sched_assist, minidump` —— **这 4 个模块必须先装载**，其中 `sched-walt` 与 `minidump` 提供 §2.1 的 5 条 WALT/minidump 符号。

---

## 3. 节点清单

### 3.1 Gen B（实机 .ko + 内核侧参考实现）—— `/proc/hmbird_sched`

**内核侧「前半套」= `kernel/sched/hmbird_sched_proc_main.c`**（ferstar scx 分支，10,840 B；我们的 `opt57.patch` 已引入该文件）。它 `proc_mkdir` 出 3 个目录、31 个条目，全部 mode **0666**：

| 父目录 | 条目 |
|---|---|
| `/proc/hmbird_sched`（25 条） | `scx_enable`、`partial_ctrl`、`cpuctrl_high`、`cpuctrl_low`、`slim_stats`、`hmbirdcore_debug`、`slim_for_app`、`misfit_ds`、`scx_shadow_tick_enable`、`highres_tick_ctrl_dbg`、`cpu7_tl`、`cpu_cluster_masks`、`save_gov`、`heartbeat`、`heartbeat_enable`、`watchdog_enable`、`isolate_ctrl`、`parctrl_high_ratio`、`parctrl_low_ratio`、`isoctrl_high_ratio`、`isoctrl_low_ratio`、`iso_free_rescue`、`parctrl_high_ratio_l`、`parctrl_low_ratio_l`、`hmbird_stats` |
| `/proc/hmbird_sched/slim_walt`（4 条） | `slim_walt_ctrl`、`slim_walt_dump`、`slim_walt_policy`、`frame_per_sec` |
| `/proc/hmbird_sched/slim_freq_gov`（2 条） | `slim_gov_debug`、`scx_gov_ctrl` |

实机 .ko 侧：字符串含 `hmbird_common_open/show/write`、`hmbird_sched : Failed to copy_from_user`，`U` 表含 `proc_create_data`、`proc_mkdir`、**`hmbird_dir`**、**`register_hmbird_sched_ops`** ⇒ **实机模块把「建目录+建条目」委托给内核的 `register_hmbird_sched_ops()`**，自己只挂条目。

### 3.2 Gen A（本仓 @99b1344）—— `register_sysctl`，**无 `/proc/hmbird_sched`**

| 注册点 | 结果路径 | 条目 |
|---|---|---|
| `hmbird_gki/scx_main.c:1064 register_sysctl("oplus_sched_ext", scx_table)` | `/proc/sys/oplus_sched_ext/` | 22 条：`scx_enable`、`scx_shadow_tick_enable`、`sched_ravg_window_frame_per_sec`、`busy_pct_high_ratio`、`busy_pct_low_ratio`、`busy_util_high_ratio`、`busy_util_low_ratio`、`partial_level`、`cpus_partial`、`cpus_exclusive`、`cpus_little`、`cpus_big`、`scx_idle_ctl_enable`、`scx_tick_resched_enable`、`scx_newidle_balance_ctl`、`scx_exclusive_sync_enable`、`rt_switch`、`yield_opt`、`gov_avg_policy_enable` 等 |
| `cpufreq_scx_main.c:1086 register_sysctl("scx_gov", scx_gov_table)` | `/proc/sys/scx_gov/` | `scx_gov_debug` |

> 另外 `cpufreq_scx_main.c` 用 `kobject_init_and_add(&tunables->attr_set.kobj, &scx_gov_tunables_ktype, get_governor_parent_kobj(policy), "scx_gov:%d", ...)` 在**该 policy 的 governor 父 kobj** 下建 sysfs 组（`U` 表含 `kobject_init_and_add`/`get_governor_parent_kobj`/`gov_attr_set_*`/`governor_sysfs_ops`/`have_governor_per_policy`）——这些由**内核 cpufreq 核心**提供，无需新写。

---

## 4. `scx_enable` 语义

| 维度 | Gen B（实机 / 内核侧 `hmbird_sched_proc_main.c`） | Gen A（本仓 vendor 侧 `hmbird_gki/scx_main.c`） |
|---|---|---|
| 谁建 | **内核侧**建 `/proc/hmbird_sched/scx_enable` | 模块侧 `scx_table[]` 经 `register_sysctl` 建 `/proc/sys/oplus_sched_ext/scx_enable` |
| 类型 | `int scx_enable;`（内核全局变量），**不是函数** | **既是函数**（`scx_main.c:613 void scx_enable(void)`）**又是 sysctl 名** |
| 可写 | 可读写，mode **0666** | 可写，mode **0644** |
| 取值含义 | 写经 `kstrtoull` 解析后直接落变量；读打印 `%d`。语义由内核 slim/ext 代码消费 | 写 1 → `scene_in=val` → `update_scx_cfg_scene()` → `scx_enable()`；写 0 → `scx_disable()` |
| 开启动作 | 仅置位（我们树不做 BPF 注册） | `scx_enable()`：`oplus_lk_feat_enable(false)`、`oplus_bd_feat_enable(false)`、`stop_machine(scx_reinit_stop_handler)` 重初始化 rq、置 `scx_stats_trace=true` |
| 关闭动作 | 仅清位 | `scx_disable()`：`cmpxchg(&scx_stats_trace,true,false)`、`hmbird_enable=0`、恢复 LK/BD feature |

**与 `/sys/kernel/sched_ext/enabled` 的关系**：**两者是不同机制，不存在绑定**。

- `/sys/kernel/sched_ext/enabled` 是**上游 sched_ext 核心**（`kernel/sched/ext.c`）里 BPF `struct_ops` 调度器的启用状态。
- OPPO 栈把上游那个 static key 改成普通 `atomic_t __scx_ops_enabled`（`hmbird_export.c` 导出）以便与厂商模块共享，`hmbird_enabled()` 就是 `atomic_read(&__scx_ops_enabled)`。
- 我们树**只发布状态、从不注册 BPF 调度器**（注册在 SM8650 上会硬挂），所以 **`/sys/kernel/sched_ext/enabled` 恒为 0**，而 `/proc/hmbird_sched/scx_enable` 是独立可写的业务开关。**不要指望写 `/proc/hmbird_sched/scx_enable` 会让 `/sys/kernel/sched_ext/enabled` 变 1。**

---

## 5. 钩子清单

### 5.1 模块 `U` 引用（内核必须 DEFINE 并导出）

| 钩子 | 我们 opt55 |
|---|---|
| `__tracepoint_android_vh_hmbird_init_task` | Y |
| `__tracepoint_android_vh_hmbird_update_load` | Y |
| `__tracepoint_android_vh_hmbird_update_load_enable` | Y |
| `__tracepoint_android_rvh_before_do_sched_yield` | Y |
| `__tracepoint_android_vh_get_util` | Y |
| `__tracepoint_android_vh_scheduler_tick` | Y |
| `__tracepoint_android_vh_tick_nohz_idle_stop_tick` | Y |
| `__tracepoint_sched_switch` | Y |

### 5.2 模块自己 `DECLARE_HOOK` / 提供钩子（内核须有对应调用点）

`hmbird_gki/scx_hooks.h`（`TRACE_INCLUDE_PATH ./hmbird_gki`）声明 2 个：

| 钩子 | 原型 | 我们 opt55 |
|---|---|---|
| `android_vh_scx_select_cpu_dfl` | `TP_PROTO(struct task_struct *p, s32 *cpu)` | Y |
| `android_vh_check_preempt_curr_scx` | `TP_PROTO(struct rq *rq, struct task_struct *p, int wake_flags, int *check_result)` | Y |

### 5.3 同一体系的相关钩子（我们已多备）

`android_vh_scx_cpu_exclusive`、`android_vh_scx_consume_dsq_allowed`、`android_vh_scx_update_task_scale_time`、`android_vh_task_fits_cpu_scx`、`android_vh_scx_sched_lpm_disallowed_time`（最后一条**我们独有**，scx 分支没有）。

**小结**：厂商模块需要的 **9 条钩子我们 opt55 全部已导出**；`opt57.patch` 本身**不新增任何钩子**（只加 `hmbird_sched_proc*`/`slim*`），故「opt55=1619 → opt57=1625」的 +6 **不是**这个补丁带来的，需另行核对口径。

---

## 6. OGKI vs GKI 差异

### 6.1 编译期（`oplus_local_modules.bzl`）

```
qcom : main.c + cpufreq_scx_main.c + scx_shadow_tick.c + hmbird_gki/{scx_main.c, scx_sched_gki.c, scx_util_track.c}
mtk  : main.c + hmbird_ogki/{scx_main.c, scx_mtk_minidump.c}
```

| 目录 | 内容 | 体积 |
|---|---|---|
| `hmbird_gki/` | **真实现**：`sched_ext.h(1,815)`、`scx_hooks.h(811)`、`scx_main.c(25,599)`、`scx_main.h(14,305)`、`scx_sched_gki.c(35,791)`、`scx_util_track.c(17,023)`、`trace_sched_ext.h(10,093)` | 106 KB |
| `hmbird_ogki/` | **空壳**：`scx_main.c(129 B, scx_init(){return 0;})`、`scx_minidump.h(122)`、`scx_mtk_minidump.c(961, 仅 MTK 有实体)` | 1.2 KB |

### 6.2 运行期（`main.c` + `hmbird_version.h`）

```c
static int __init hmbird_common_init(void) {
    if (HMBIRD_GKI_VERSION == get_hmbird_version_type())
        scx_init();                                   // <- 只有这里建节点
    else if (HMBIRD_OGKI_VERSION == get_hmbird_version_type()) {
#ifdef CONFIG_ARCH_MEDIATEK
        hmbird_minidump_init();
#endif
        return 0;                                     // <- 什么都不做
    }
    return 0;
}
```

`get_hmbird_version_type()` 读 DT `/soc/oplus,hmbird/version_type` 的 `type` 字符串：`"HMBIRD_OGKI"` / `"HMBIRD_GKI"`。

### 6.3 结论：SM8650 该用哪套

**SM8650 是 qcom ⇒ 编译期必然选 `hmbird_gki/`**（`hmbird_ogki/` 对 qcom 根本不进编译，其 `scx_init()` 也是空壳）。

但**运行期还有一道 DT 闸门**：若设备 DT 写的是 `HMBIRD_OGKI`，则 `scx_init()` **一次都不会被调用** ⇒ 模块装载成功但**一个节点都不建**。

> **实机 .ko 里没有这个版本闸门**（`U`/字符串均无 `of_find_node_by_path`、`version_type`），说明实机这一代已去掉 DT 分叉、改为由内核 `register_hmbird_sched_ops()` 全权建节点。因此**「无节点」的根因应优先查内核侧 `register_hmbird_sched_ops()` 是否实现/被 config 闸门挡住，而不是先怀疑 DT**。

---

## 7. 风险点

### 7.1 同名条目冲突（会 `proc_create` 返 NULL ⇒ init 失败）

| # | 冲突 | 后果 | 处置 |
|---|---|---|---|
| R1 | **`hmbird_dir` 只导出未赋值**：我们 `kernel/sched/hmbird_export.c` 里 `struct proc_dir_entry *hmbird_dir; EXPORT_SYMBOL_GPL(hmbird_dir);`，但 `hmbird_sched_proc_main.c` 里的 `hmbird_dir` 是 `hmbird_proc_init()` 的**局部变量**。全局指针**始终为 NULL** | 模块把条目挂到 `hmbird_dir`(NULL) ⇒ 条目落到 **`/proc` 根**；与内核侧 `/proc/hmbird_sched/*` **同名不同父** | 内核侧须把 `proc_mkdir` 的返回值**赋给全局 `hmbird_dir`** |
| R2 | **`scx_enable` 双重定义**：Gen A 里既是 `void scx_enable(void)` 函数（模块内）又是 sysctl 名；Gen B 里是内核全局 `int scx_enable` | 两代混编 ⇒ 链接期符号冲突 / 名字被覆盖 | **同一代内取值**，禁止 Gen A 内核配 Gen B 模块 |
| R3 | **`scx_shadow_tick_enable` 同名**：内核侧挂 `/proc/hmbird_sched/scx_shadow_tick_enable`（变量 `highres_tick_ctrl`）；Gen A 模块在 `/proc/sys/oplus_sched_ext/scx_shadow_tick_enable` 也有一条 | 父目录不同 ⇒ 不冲突；但**同名不同义**，脚本易写错 | 固化路径前缀 |
| R4 | **`slim_gov_debug` / `scx_gov_ctrl` 重复**：内核侧建在 `/proc/hmbird_sched/slim_freq_gov/`；Gen A 模块另有 `scx_gov` sysctl 组 | 同 R3，父目录不同不冲突 | 同上 |
| R5 | **`slim_walt_*` 与 `frame_per_sec`**：内核侧在 `/proc/hmbird_sched/slim_walt/`；Gen A 模块有 `sched_ravg_window_frame_per_sec`（不同名） | 不冲突 | — |
| R6 | **`register_hmbird_sched_ops()` 未实现** ⇒ 未定义符号 | insmod 直接 `Unknown symbol`（比「无节点」更早失败） | 内核侧实现并导出 |

### 7.2 modversions CRC 不一致

`modversions` 生效时，**符号名对但 CRC 不对同样装载失败**（`disagrees about version of symbol`）。必须用同一份 `Module.symvers` 对齐 127 条 CRC。

### 7.3 其余

- **`scx_get_md_info` 的 BUG()**：`hmbird_misc_init` 在 `vaddr` 为 NULL 时 `BUG()`；内核侧必须发布**非 NULL** 且大小正确的线性映射缓冲（出厂为 `kmalloc(0x1000)`）。
- **`iso_masks` 裸偏移索引**：成员顺序 `ex_free, exclusive, partial, big, little` 不可改（模块按 `0x00/0x08/0x10` 取）。
- **`CONFIG_HMBIRD_SCHED` 命名差**：scx 分支全量 gate 在 `CONFIG_HMBIRD_SCHED`；我们树用 `CONFIG_SCHED_CLASS_EXT` + `CONFIG_SLIM_SCHED`，**没有定义 `CONFIG_HMBIRD_SCHED`**（照搬会整条关掉）。
- **`hmbird_export.c` 禁止覆盖**：scx 分支版只有 8 个导出，我们 opt55 有 10 个（多 `iso_masks`、`scx_get_md_info`）。

---

## 8. 差距汇总（与我们内核现状）

| 类别 | 契约条数 | 已具备 | 差距 |
|---|---|---|---|
| 符号（`U`） | 126 | 119 | **7** |
| 节点 | 31 | 31（`opt57.patch` 已引入 `hmbird_sched_proc_main.c`） | 0（但 `hmbird_dir` 赋值缺陷见 R1） |
| 钩子 | 9 | 9 | 0 |

**差距清单（7 条符号）**：`get_hmbird_cpu_exclusive`、`msm_minidump_add_region`、`register_hmbird_sched_ops`、`register_walt_ops`、`sched_ravg_window`、`walt_rq`、`waltgov_cb_data`。

其中**只有 `register_hmbird_sched_ops` 是内核侧必须新写的**；其余 6 条分别由 `oplus_bsp_game_opt.ko`、`minidump.ko`、`sched-walt.ko` 提供（属模块依赖链，不是内核源码缺口）。

---

## 附录 A：模块 `U` 符号全表（126 条）

| # | 符号 | 出厂内核 | 提供者 | 我们 opt55 |
|---:|---|---|---|---|
| 1 | `__arch_copy_from_user` | Y | stock kernel | Y |
| 2 | `__bitmap_andnot` | Y | stock kernel | Y |
| 3 | `__bitmap_weight` | Y | stock kernel | Y |
| 4 | `__check_object_size` | Y | stock kernel | Y |
| 5 | `__cpu_online_mask` | Y | stock kernel | Y |
| 6 | `__cpu_possible_mask` | Y | stock kernel | Y |
| 7 | `__cpufreq_driver_target` | Y | stock kernel | Y |
| 8 | `__kmalloc` | Y | stock kernel | Y |
| 9 | `__kthread_init_worker` | Y | stock kernel | Y |
| 10 | `__list_add_valid` | Y | stock kernel | Y |
| 11 | `__list_del_entry_valid` | Y | stock kernel | Y |
| 12 | `__mutex_init` | Y | stock kernel | Y |
| 13 | `__per_cpu_offset` | Y | stock kernel | Y |
| 14 | `__scx_ops_enabled` | Y | stock kernel | Y |
| 15 | `__stack_chk_fail` | Y | stock kernel | Y |
| 16 | `__trace_bprintk` | Y | stock kernel | Y |
| 17 | `__trace_bputs` | Y | stock kernel | Y |
| 18 | `__trace_trigger_soft_disabled` | Y | stock kernel | Y |
| 19 | `__tracepoint_android_rvh_before_do_sched_yield` | Y | stock kernel | Y |
| 20 | `__tracepoint_android_vh_get_util` | Y | stock kernel | Y |
| 21 | `__tracepoint_android_vh_hmbird_init_task` | Y | stock kernel | Y |
| 22 | `__tracepoint_android_vh_hmbird_update_load` | Y | stock kernel | Y |
| 23 | `__tracepoint_android_vh_hmbird_update_load_enable` | Y | stock kernel | Y |
| 24 | `__tracepoint_android_vh_scheduler_tick` | Y | stock kernel | Y |
| 25 | `__tracepoint_android_vh_tick_nohz_idle_stop_tick` | Y | stock kernel | Y |
| 26 | `__tracepoint_sched_switch` | Y | stock kernel | Y |
| 27 | `__warn_printk` | Y | stock kernel | Y |
| 28 | `_find_first_bit` | Y | stock kernel | Y |
| 29 | `_find_next_bit` | Y | stock kernel | Y |
| 30 | `_printk` | Y | stock kernel | Y |
| 31 | `_raw_spin_lock_irqsave` | Y | stock kernel | Y |
| 32 | `_raw_spin_unlock_irqrestore` | Y | stock kernel | Y |
| 33 | `alt_cb_patch_nops` | Y | stock kernel | Y |
| 34 | `android_rvh_probe_register` | Y | stock kernel | Y |
| 35 | `balance_push_callback` | Y | stock kernel | Y |
| 36 | `bpf_trace_run6` | Y | stock kernel | Y |
| 37 | `cpu_hwcaps` | Y | stock kernel | Y |
| 38 | `cpu_number` | Y | stock kernel | Y |
| 39 | `cpu_scale` | Y | stock kernel | Y |
| 40 | `cpu_topology` | Y | stock kernel | Y |
| 41 | `cpufreq_cpu_get` | Y | stock kernel | Y |
| 42 | `cpufreq_disable_fast_switch` | Y | stock kernel | Y |
| 43 | `cpufreq_driver_fast_switch` | Y | stock kernel | Y |
| 44 | `cpufreq_driver_resolve_freq` | Y | stock kernel | Y |
| 45 | `cpufreq_enable_fast_switch` | Y | stock kernel | Y |
| 46 | `cpufreq_register_governor` | Y | stock kernel | Y |
| 47 | `cpufreq_unregister_governor` | Y | stock kernel | Y |
| 48 | `ext_module_loaded` | Y | stock kernel | Y |
| 49 | `fortify_panic` | Y | stock kernel | Y |
| 50 | `get_governor_parent_kobj` | Y | stock kernel | Y |
| 51 | `get_hmbird_cpu_exclusive` | D | oplus_bsp_game_opt.ko | N |
| 52 | `gic_nonsecure_priorities` | Y | stock kernel | Y |
| 53 | `gov_attr_set_get` | Y | stock kernel | Y |
| 54 | `gov_attr_set_init` | Y | stock kernel | Y |
| 55 | `gov_attr_set_put` | Y | stock kernel | Y |
| 56 | `governor_sysfs_ops` | Y | stock kernel | Y |
| 57 | `have_governor_per_policy` | Y | stock kernel | Y |
| 58 | `hmbird_dir` | Y | stock kernel | Y |
| 59 | `hrtimer_active` | Y | stock kernel | Y |
| 60 | `hrtimer_cancel` | Y | stock kernel | Y |
| 61 | `hrtimer_init` | Y | stock kernel | Y |
| 62 | `hrtimer_start_range_ns` | Y | stock kernel | Y |
| 63 | `irq_work_queue` | Y | stock kernel | Y |
| 64 | `irq_work_queue_on` | Y | stock kernel | Y |
| 65 | `irq_work_sync` | Y | stock kernel | Y |
| 66 | `iso_masks` | Y | stock kernel | Y |
| 67 | `kfree` | Y | stock kernel | Y |
| 68 | `kimage_voffset` | Y | stock kernel | Y |
| 69 | `kmalloc_caches` | Y | stock kernel | Y |
| 70 | `kmalloc_trace` | Y | stock kernel | Y |
| 71 | `kobject_init_and_add` | Y | stock kernel | Y |
| 72 | `kobject_put` | Y | stock kernel | Y |
| 73 | `kstrtoint` | Y | stock kernel | Y |
| 74 | `kthread_bind_mask` | Y | stock kernel | Y |
| 75 | `kthread_cancel_work_sync` | Y | stock kernel | Y |
| 76 | `kthread_create_on_node` | Y | stock kernel | Y |
| 77 | `kthread_flush_worker` | Y | stock kernel | Y |
| 78 | `kthread_queue_work` | Y | stock kernel | Y |
| 79 | `kthread_stop` | Y | stock kernel | Y |
| 80 | `kthread_worker_fn` | Y | stock kernel | Y |
| 81 | `ktime_get` | Y | stock kernel | Y |
| 82 | `memset` | Y | stock kernel | Y |
| 83 | `memstart_addr` | Y | stock kernel | Y |
| 84 | `msm_minidump_add_region` | N | -(dump 未含提供者) | N |
| 85 | `mutex_lock` | Y | stock kernel | Y |
| 86 | `mutex_unlock` | Y | stock kernel | Y |
| 87 | `non_ext_task` | Y | stock kernel | Y |
| 88 | `nr_cpu_ids` | Y | stock kernel | Y |
| 89 | `perf_trace_buf_alloc` | Y | stock kernel | Y |
| 90 | `perf_trace_run_bpf_submit` | Y | stock kernel | Y |
| 91 | `preempt_schedule_notrace` | Y | stock kernel | Y |
| 92 | `proc_create_data` | Y | stock kernel | Y |
| 93 | `proc_mkdir` | Y | stock kernel | Y |
| 94 | `raw_spin_rq_lock_nested` | Y | stock kernel | Y |
| 95 | `raw_spin_rq_unlock` | Y | stock kernel | Y |
| 96 | `register_hmbird_sched_ops` | N | -(dump 未含提供者) | N |
| 97 | `register_walt_ops` | N | -(dump 未含提供者) | N |
| 98 | `runqueues` | Y | stock kernel | Y |
| 99 | `sched_clock` | Y | stock kernel | Y |
| 100 | `sched_ravg_window` | N | -(dump 未含提供者) | N |
| 101 | `sched_setattr_nocheck` | Y | stock kernel | Y |
| 102 | `scx_get_md_info` | Y | stock kernel | Y |
| 103 | `seq_lseek` | Y | stock kernel | Y |
| 104 | `seq_printf` | Y | stock kernel | Y |
| 105 | `seq_read` | Y | stock kernel | Y |
| 106 | `single_open` | Y | stock kernel | Y |
| 107 | `single_release` | Y | stock kernel | Y |
| 108 | `sprintf` | Y | stock kernel | Y |
| 109 | `sscanf` | Y | stock kernel | Y |
| 110 | `strim` | Y | stock kernel | Y |
| 111 | `strlen` | Y | stock kernel | Y |
| 112 | `synchronize_rcu` | Y | stock kernel | Y |
| 113 | `task_is_scx` | Y | stock kernel | Y |
| 114 | `trace_event_buffer_commit` | Y | stock kernel | Y |
| 115 | `trace_event_buffer_reserve` | Y | stock kernel | Y |
| 116 | `trace_event_printf` | Y | stock kernel | Y |
| 117 | `trace_event_raw_init` | Y | stock kernel | Y |
| 118 | `trace_event_reg` | Y | stock kernel | Y |
| 119 | `trace_handle_return` | Y | stock kernel | Y |
| 120 | `trace_raw_output_prep` | Y | stock kernel | Y |
| 121 | `tracepoint_probe_register` | Y | stock kernel | Y |
| 122 | `update_rq_clock` | Y | stock kernel | Y |
| 123 | `usleep_range_state` | Y | stock kernel | Y |
| 124 | `wake_up_process` | Y | stock kernel | Y |
| 125 | `walt_rq` | N | -(dump 未含提供者) | N |
| 126 | `waltgov_cb_data` | N | -(dump 未含提供者) | N |
