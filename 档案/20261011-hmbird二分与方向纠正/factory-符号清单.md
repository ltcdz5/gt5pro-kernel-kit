# factory 逆向符号清单（upstream 支援 t7，2026-10-11）

> 由 upstream 提供，配合 t6 报告 F:\工作区\_audit\原厂对照与前瞻.md 使用。
> 全部证据为只读（WSL 侧 strings / nm / readelf / grep）。**未碰设备。**

---

## 0. ★最重要的发现：设备模块已经在手上，而且没 strip★

F:\工作区\_audit\scx_vendor.ko（87,840 字节）**就是设备上的 oplus_bsp_sched_ext.ko**：

```
modinfo:
  name:     oplus_bsp_sched_ext
  vermagic: 6.1.141-android14-11-o-g5de16d278e6c SMP preempt mod_unload modversions aarch64
  depends:  sched-walt,oplus_bsp_game_opt,oplus_bsp_sched_assist,minidump
  license:  GPL v2
file: ELF 64-bit LSB relocatable, ARM aarch64, **not stripped**, BuildID=307ee23cb2945b0894da8baf4ff92695e64b9fdd
```

⇒ **可以直接 nm / objdump 全量逆向，不需要再拉设备。** 这是 t7 最快的入口。
（还缺的是 sched_walt.ko —— 它不在 _audit 里，需要 captain 从 /vendor/lib/modules/ 拉。）

---

## 1. ★关键否定结论（可直接关闭三条假说）★

对 scx_vendor.ko 做 strings/nm 的结果：

| 目标符号/字符串 | 命中 | 含义 |
|---|---|---|
| hmbird_ops | **0** | 设备模块**没有** struct hmbird_ops 的任何引用 |
| get_hmbird_version_type | **0** | 设备模块**不读版本** |
| HMBIRD_GKI / HMBIRD_OGKI | **0 / 0** | **15 处 GKI 让路门在模块侧根本不存在** |
| oplus,hmbird | **0** | 模块**不读 DT**（与 HANDOFF:1275 的 of_*=0 一致）|
| register_scx_sched_gki_ops / scx_sched_gki_ops / scx_sched_ops | **0 / 0 / 0** | 设备模块**不用 GKI 那套** ⇒ 我们内核缺这个符号**不是问题** |

**⇒ 三条结论：**
1. **struct hmbird_ops 错位（CE2-H5）在本机是「纯惰性」的**：设备上没有任何代码解引用 hmbird_ops
   ⇒ t6 §3.5 的判断由二进制证据坐实。它仍是定时炸弹（未来换 ROM 才爆），但**与今晚硬挂无关**。
2. **captain 的「15 处 GKI 让路假说」在模块侧不可能成立**（模块里连 HMBIRD_GKI 字符串都没有）
   ⇒ 该假说若要成立，只能落在 **ROM sched_walt.ko** 上，而那需要先把 sched_walt.ko 拉下来验。
3. **t6 附录 D-6 的 scx_sched_gki_ops 风险关闭**：设备模块不调它。

---

## 2. 设备模块自带的私有变量（回答「两份 slim_walt_ctrl」）

nm 定义符号（节选，含节内偏移）：

```
0000000000000090 B slim_walt_ctrl      <-- 模块自己的那份
0000000000000094 B slim_walt_dump
0000000000000098 B slim_walt_policy
000000000000009c B slim_gov_debug
0000000000000088 B highres_tick_ctrl
000000000000008c B highres_tick_ctrl_dbg
000000000000021c D cpu7_tl
0000000000000220 D scx_gov_ctrl
0000000000000000 D cpufreq_scx_gov
0000000000000000 D boost_policy_params
0000000000000200 D yield_opt_params
0000000000000218 D sched_ravg_window_frame_per_sec
0000000000000000 D num_sched_clusters
0000000000000038 D stt
0000000000000118 D ystate
```

**⇒ slim_walt_ctrl 是模块的 BSS 变量（0x90），它不在模块的 nm -u 列表里 ⇒ 模块既不导入也不导出它。**
**⇒ 与内核那份（我们 hmbird_misc.c:34，无 EXPORT_SYMBOL）完全不共享。t6 附录 D-4 结论坐实：两份状态不一致不是硬挂原因。**

★ 附带：模块源码路径字符串为 `../vendor/oplus/kernel/cpu/sched_ext/hmbird/hmbird_misc.c`
⇒ 设备模块编译自 **sched_ext/hmbird/**（单代次），而 vendor-src 快照是 **hmbird_gki/ + hmbird_ogki/**（SM8750 双代次合一）。
**⇒ 再次确认 vendor-src/vendor-sched_ext/ 与设备模块不是同一份源码，不要用快照的行为推设备行为。**

---

## 3. ★设备模块的完整 nm -u 清单（126 个）—— 这是「内核+ROM 模块必须提供」的契约★

### 3.1 hmbird / scx / walt / tracepoint 相关（最关键）

```
U __scx_ops_enabled
U __tracepoint_android_rvh_before_do_sched_yield
U __tracepoint_android_vh_get_util
U __tracepoint_android_vh_hmbird_init_task
U __tracepoint_android_vh_hmbird_update_load
U __tracepoint_android_vh_hmbird_update_load_enable
U __tracepoint_android_vh_scheduler_tick          <-- ★ core.c:5848 的那个钩子
U __tracepoint_android_vh_tick_nohz_idle_stop_tick
U __tracepoint_sched_switch
U ext_module_loaded
U get_hmbird_cpu_exclusive
U hmbird_dir
U non_ext_task
U register_hmbird_sched_ops
U register_walt_ops
U scx_get_md_info
U sched_ravg_window
U sched_setattr_nocheck
U task_is_scx
U walt_rq
U waltgov_cb_data
U iso_masks
U balance_push_callback
U raw_spin_rq_lock_nested / raw_spin_rq_unlock
U update_rq_clock / sched_clock / runqueues
```

### 3.2 ★对我们内核的核对结果★

把上面的符号与我们 out-core/Module.symvers（= 我们内核的导出表）对照：

| 符号 | 我们内核是否导出 | 说明 |
|---|---|---|
| ext_module_loaded | ✅ 导出（hmbird_export.c:72 EXPORT_SYMBOL_GPL）| Stage AZ 的门就是它 |
| hmbird_dir | ✅ 导出（hmbird_export.c:75）| |
| non_ext_task | ✅ 导出（hmbird_export.c:78）| |
| __scx_ops_enabled | ✅ 导出（hmbird_export.c:85）| |
| iso_masks | ✅ 导出（hmbird_export.c:106）| |
| scx_get_md_info | ✅ 导出（hmbird_export.c:172）| |
| task_is_scx | ✅ 导出（hmbird_export.c:202）| |
| balance_push_callback / sched_setattr_nocheck | ✅ 在 Module.symvers | 上游内核自带 |
| **register_hmbird_sched_ops** | ❌ 不在 Module.symvers（树内 refs=2）| **待查**：可能由 ROM 模块（oplus_bsp_sched_assist）导出，或我们漏导出 |
| **get_hmbird_cpu_exclusive** | ❌ 树内 refs=**0**，Module.symvers 无 | **★我们内核完全没有这个符号★** ⇒ 必须由 ROM 模块提供 |
| **register_walt_ops** | ❌ 树内 refs=**0** | 必须由 ROM sched_walt.ko 提供 |
| **walt_rq** | ❌ Module.symvers 无 | 必须由 ROM sched_walt.ko 提供（percpu）|
| **sched_ravg_window** | ❌ Module.symvers 无 | 必须由 ROM 模块提供 |
| **waltgov_cb_data** | ❌ 树内 refs=**0** | 必须由 ROM 模块提供 |

**⇒ 给 factory 的两个逆向目标（按价值排序）：**
1. **walt_rq 的结构与偏移**：scx_vendor.ko 导入 `walt_rq`（percpu）。
   这直接决定 `init_hmbird_rq_wrq_variables()`（vendor walt.h:660-661）里 `&wrq->prev_runnable_sum_fixed`
   与 `&wrq->prev_window_size` 的**字节偏移**——如果哪天要手工补 util 源，这两个偏移是必需的。
   做法：在 scx_vendor.ko 里找对 `walt_rq` 的 relocation（`readelf -r`），看它被加了多少立即数。
2. **sched_walt.ko 里有没有 hmbird 集成**（决定 captain 的 15 处 GKI 门假说是否适用）：
   拉下来后跑：`strings -a sched_walt.ko | grep -E 'HMBIRD|hmbird|slim_walt|init_hmbird'`
   以及 `nm -u sched_walt.ko | grep -E 'hmbird|walt_ops'`。

---

## 4. stock-kernel.bin 的探测结果（方法已验证）

文件：F:\工作区\_audit\stock-kernel.bin（35,695,104 字节，`file` = data，xxd 前 16 字节全 0 ⇒ 非压缩裸 Image 风格的转储）。

**方法校验（对照组，全部 >0，证明探测方法有效）**：

```
strings -a stock-kernel.bin | grep -c '^hmbird_sched$'        -> 1
strings -a stock-kernel.bin | grep -c '^scx_enable$'          -> 1
strings -a stock-kernel.bin | grep -c '^partial_ctrl$'        -> 1
strings -a stock-kernel.bin | grep -c '^slim_stats$'          -> 1
strings -a stock-kernel.bin | grep -c '^watchdog_enable$'     -> 2
strings -a stock-kernel.bin | grep -c '^version_type$'        -> 1
```

**目标符号（全部 0，两种方法交叉验证：strings 精确匹配 + grep -a 任意匹配）**：

```
hmbird_ops                        = 0
get_hmbird_version_type           = 0
init_hmbird_rq_wrq_variables      = 0
hmbird_sched_ops_init             = 0
slim_walt_ctrl                    = 0
walt_lb_tick                      = 0        <-- 它在 sched_walt.ko 里，不在内核 Image
walt_sched_newidle_balance        = 0        <-- 同上
register_scx_sched_gki_ops        = 0
scx_sched_gki_ops                 = 0
hmbird_get_boost_weight           = 0
hmbird_get_boost_enable           = 0
HMBIRD_OGKI / HMBIRD_GKI          = 0 / 0
oplus,hmbird                      = 0
```

**⇒ 结论**：原厂 GT5 Pro 的**内核 Image 里完全没有 SM8750 那一代的 hmbird/WALT 桥接**
（没有 hmbird_ops、没有 version_type 读取、没有 slim_walt、没有 walt_lb_tick）。
WALT 全部以 **sched_walt.ko 模块**形式存在 ⇒ **`walt_lb_tick` / `walt_sched_newidle_balance`
必须去 sched_walt.ko 里找，不要在内核 Image 里找**（这是给 factory 的省时提示）。

另外：`version_type` 这个字符串**存在**（=1），但 `oplus,hmbird` 不存在 ⇒ 说明内核里有一处别的
`version_type` 用途（不是 hmbird 的 DT 节点）。值得 factory 顺手定位一下它的调用者。

---

## 5. 给 factory 的「去设备拉什么」清单（零风险，captain 执行）

| 文件 | 用途 |
|---|---|
| /vendor/lib/modules/sched_walt.ko | **最高优先**：验「有没有 hmbird 集成」+ 定位 walt_lb_tick / walt_sched_newidle_balance / android_vh_scheduler_tick 的实现 |
| /vendor/lib/modules/oplus_bsp_sched_assist.ko | 找 register_hmbird_sched_ops / get_hmbird_cpu_exclusive / waltgov_cb_data 的提供者 |
| /vendor/lib/modules/oplus_bsp_game_opt.ko | 依赖链一员，顺手 |
| /vendor/lib/modules/oplus_bsp_sched_ext.ko | **已有**（= _audit/scx_vendor.ko，可核对 BuildID 307ee23c...）|
| /proc/kallsyms（root，WALT 就绪后）| 复核 walt_disabled 是否仍为 1（t6 附录 D-7 的关键判据）|

---

## 6. 一句话总结给 factory

**你手上已经有一个没 strip 的设备模块（scx_vendor.ko = oplus_bsp_sched_ext.ko），
它证明了设备上「没有任何东西引用 hmbird_ops、也不读 DT/版本」；
剩下唯一值得反的是 sched_walt.ko —— 它是 WALT 的全部，也是 walt_lb_tick /
walt_sched_newidle_balance / android_vh_scheduler_tick 的真实所在，还是 walt_rq 结构偏移的唯一来源。**
