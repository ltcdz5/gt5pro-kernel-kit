# 评估：走原厂 sched_ext 路径（让 oplus_bsp_sched_ext.ko 的 scx_init() 真正执行）

> 任务 t17 / 成员 upstream / 2026-10-11。只读源码与既有日志/二进制，**未碰设备、未改源码**。
> 证据一律给 文件:行号 或 反汇编地址。二进制：`_audit/scx_vendor.ko`（= 设备上的 oplus_bsp_sched_ext.ko，not stripped）、`_audit/stock-kernel.bin`。

---

## 0. 结论（先看）

**不推荐改走原厂 sched_ext 路径。** 三条硬理由：

1. **原厂路径在这台设备上已经被 opt43 证否。**
   `_audit/opt54_entry.md:83`：「**不要在这台设备上 register 任何 scx 调度器**：opt43 实测 = 整机硬挂死 + PMIC 看门狗复位」；
   `kernel/sched/hmbird_export.c:18-21` 同样记载：registering a scheduler on this SoC **hard-hangs the device**。
   ⇒ 而「让 scx_init() 真正执行」在本机**唯一**的入口条件就是让 `current->scx != NULL`（见 §1），那**等价于注册一个 sched_ext 调度器**。

2. **任务书的核心前提不成立：设备模块没有版本分派，也完全不读 DT。**
   `nm -u scx_vendor.ko | grep -c of_` = **0**；`strings` 里 `oplus,hmbird` = **0**、`version_type` = **0**。
   ⇒ 途径 (a) 补 DT 节点、途径 (b) 改内核导出的 version 符号，**两条都无效**（模块连读 DT 的能力都没有）。

3. **原厂路径其实已经在跑。** dmesg_142 在 **up=30.505s** 有模块自己打的 `[scx_gov][scx_cpufreq_init] num_cluster=4 …`，
   而 `scx_cpufreq_init` 在模块里**只有一个调用者** = `sched_ext_init`（§1）⇒ 那道 `current->scx` 门**当时是通过的**，
   ⇒ 后面的 `hmbird_sysctrl_init` / `hmbird_misc_init` / `ext_module_loaded = 1` **也都执行了**。
   ⇒ **「让 scx_init() 真正执行」这个目标已经达成**；真正的问题不是「没跑」，而是**我们内核里那套 hmbird_sched_class 与原厂那套并存**。

---

## 1. 模块入口逐行（含反汇编）

### 1.1 调用链（每个被调函数**只有一个调用者**，已用全部 CALL26 relocation 核过）

```
init_module（.init.text:0x4）
  10: bl sched_ext_init                    R_AARCH64_CALL26 sched_ext_init

sched_ext_init（T @0x24，由模块导出）
  30: mrs  x8, SP_EL0
  34: ldr  x8, [x8, #0xe18]   ; x8 = current->scx
  38: cbz  x8, 0x58           ; ★唯一的门★ NULL ⇒ 直接 return 0，什么都不做
  3c: bl   scx_shadow_tick_init
  40: bl   scx_cpufreq_init   ; → cpufreq_register_governor(&cpufreq_scx_gov)
  44: bl   hmbird_sysctrl_init
  48: bl   hmbird_misc_init   ; → register_hmbird_sched_ops / register_walt_ops / 4 个 tracepoint
  4c: adrp x8, ext_module_loaded
  50: mov  w9, #1
  54: str  w9, [x8]           ; ext_module_loaded = 1
  58: mov  w0, wzr ; ret

hmbird_misc_init（T @0x2650）
  2784: bl register_hmbird_sched_ops
  278c: bl register_walt_ops

hmbird_skip_yield_handler（T @0x23c4）
  2414: bl get_hmbird_cpu_exclusive
```

★ 偏移校验：`pahole --hex -C task_struct out-core/vmlinux` 给出
  `struct sched_ext_entity * scx;  /* 0xe18  0x8 */`
  ⇒ **0xe18 在我们内核里也确实是 `current->scx`** ⇒ 反汇编解读成立。

### 1.2 它读的是什么？——**内核状态，不是 DT / 不是 version**

| 检查 | 结果 |
|---|---|
| `nm -u scx_vendor.ko | grep -c of_` | **0**（没有任何 of_* 导入 ⇒ 模块里不可能调用 `of_find_node_by_path` / `of_property_read_string`）|
| `strings -a scx_vendor.ko | grep -c 'oplus,hmbird'` | **0**（DT 路径字符串都不在）|
| `strings -a scx_vendor.ko | grep -c version_type` | **0** |
| 模块定义的 version 相关符号 | **无**（`get_hmbird_version_type` 是 static inline，连符号都没有）|
| `.modinfo` | 只有 license/vermagic/name/depends，**无 module_param**（`nm` 里也没有 `__param`）|

**⇒ 「UNKNOWN 时具体跳过了哪几步」这个问题在本机不适用**：设备模块**没有 UNKNOWN 这个分支**。
`vendor-src/vendor-sched_ext/main.c:14-26` 那套 `HMBIRD_GKI → scx_init() / HMBIRD_OGKI → hmbird_minidump_init()` 的版本分派，
**不是设备模块的代码** —— 设备模块的源码路径字符串是
`../vendor/oplus/kernel/cpu/sched_ext/hmbird/hmbird_misc.c`（单代次 `sched_ext/hmbird/`），
而 vendor-src 快照是 `hmbird_gki/ + hmbird_ogki/` 的 **SM8750 双代次合一树**。
（analyst 独立得到同一结论：模块 strings 里没有 HMBIRD_GKI/HMBIRD_OGKI/version_type。）

---

## 2. 让判定变成 OGKI/GKI 的所有可行途径（逐条：成本/风险/可逆性）

### (a) 补 DT 节点 `/soc/oplus,hmbird/version_type` —— **无效**

| 项 | 结论 |
|---|---|
| 对设备模块是否有效 | **完全无效**。模块 0 个 of_* 导入、0 个 `oplus,hmbird` 字符串、0 个 `version_type` 字符串 ⇒ **它读不到 DT** |
| 对我们内核是否有效 | 我们内核里的 DT 兼容层在 `kernel/sched/hmbird_sched_proc_main.c:66-130`（`hmbird_read_version_type()` @:120），**而且它没有 EXPORT_SYMBOL**（同文件 :83-84 明写「No EXPORT_SYMBOL here: hmbird is built into this image」）⇒ **改不了模块**，只影响我们内核自己的判定 |
| 成本 | 需要重编 dtbo 并刷 boot/dtbo（属设备操作）|
| 风险 | **高**（opt43 的形态：DT 与模块判定不一致 ⇒ 整机起不来 ⇒ PMIC 复位，见 §4）|
| 可逆 | 刷回原 dtbo 即可，但要经历一次起不来的风险 |
| **净收益** | **0** |

### (b) 模块自带那份 version 判定的实际输入 —— **不存在**

任务书假设「模块的判定最终依赖某个我们内核导出的符号，改那个符号就能同时影响模块」。
**核实结果：不成立。**
- 模块**没有** `get_hmbird_version_type` 符号（static inline + 未使用/被编译掉）；
- 模块**没有**任何 `of_*` 导入 ⇒ 无法读 DT；
- 模块的 `nm -u`（126 个）里**没有任何 version/type 相关符号**；
- 模块的 `nm` 定义符号里**没有** version 相关函数或数据。
⇒ **模块里根本不存在「version 判定」这个对象，所以没有任何输入可以改。**

### (c) 其他所有途径

| 途径 | 可行性 | 说明 |
|---|---|---|
| **让 `current->scx != NULL`**（模块 init 的唯一门）| **技术上可行，但被 opt43 证否** | 需要内核先把任务放到 `ext_sched_class` 上（我们树里 `p->scx` 只在 `kernel/sched/ext.c:2390` 分配，属 `scx_ops_enable()` 路径）⇒ **等价于注册一个 sched_ext 调度器 ⇒ opt43 的硬挂路径** |
| **内核直接调用模块导出的 `sched_ext_init()`** | 可行但**通常 no-op** | 模块把 `sched_ext_init` 导出（`T @0x24`）⇒ 内核可调；但它内部仍要过 `current->scx` 那道门。门为假时是安全 no-op（无用），门为真时又回到上一行 |
| **内核命令行 / sysfs / 模块参数** | **无此途径** | 模块无 `module_param`（`.modinfo` 只有 4 项，`nm` 无 `__param`）；也没有任何 `early_param`/`core_param` |
| **符号替换**（我们内核提供自己的 `register_hmbird_sched_ops` 等）| **不推荐** | 这些符号**已由另一个 ROM 模块提供**（见 §3）⇒ 我们再加一份会改变符号解析结果，风险中高 |
| **只读诊断**（kprobe / tracefs `events/hmbird/` / `/sys/kernel/debug/sched/debug`）| **✅ 安全可用** | captain 已实测：kprobe 可写（`echo 'p:hmbtest hmbird_update_task_ravg' > /sys/kernel/tracing/kprobe_events` rc=0）；`events/hmbird/` 存在（`hmbird_fatal_info` / `hmbird_update_history` / `scx_update_history`）；`events/schedwalt/` 存在 |

---

## 3. scx_init() 跑起来需要我们内核提供哪些符号？

### 3.1 模块的 126 个 `nm -u`，按提供者分类

| 符号 | 我们 out-core/Module.symvers | 提供者 |
|---|---|---|
| `ext_module_loaded` | ✅ | 我们内核 `hmbird_export.c:72` EXPORT_SYMBOL_GPL |
| `hmbird_dir` | ✅ | `hmbird_export.c:75` |
| `non_ext_task` | ✅ | `hmbird_export.c:78` |
| `__scx_ops_enabled` | ✅ | `hmbird_export.c:85` |
| `iso_masks` | ✅ | `hmbird_export.c:106` |
| `scx_get_md_info` | ✅ | `hmbird_export.c:172` |
| `task_is_scx` | ✅ | `hmbird_export.c:202` |
| `balance_push_callback` / `sched_setattr_nocheck` / 内核通用符号 | ✅ | 上游内核 |
| **`register_hmbird_sched_ops`** | ❌ 未导出（树内 refs=2，且在**不编译**的 `kernel/oplus_cpu/sched/sched_assist/sa_hmbird.c` 里）| **另一个 ROM 模块** |
| **`register_walt_ops`** | ❌ 树内 refs=**0** | **另一个 ROM 模块** |
| **`get_hmbird_cpu_exclusive`** | ❌ 树内 refs=**0** | **另一个 ROM 模块** |
| **`walt_rq`** | ❌ 不在我们内核 | ROM（percpu）|
| **`sched_ravg_window`** | ❌ 不在我们内核 | ROM |
| **`waltgov_cb_data`** | ❌ 不在我们内核 | ROM `cpufreq_uag` |

### 3.2 ★关键：缺的那 6 个**连原厂内核都不提供**★

对 `stock-kernel.bin` 做 strings（方法已验证：对照组 `hmbird_sched`/`scx_enable`/`partial_ctrl` 均 >0）：

```
register_hmbird_sched_ops = 0        <-- 原厂内核也没有
register_walt_ops         = 0        <-- 原厂内核也没有
get_hmbird_cpu_exclusive  = 0        <-- 原厂内核也没有
hmbird_sched_class        = 0        <-- 原厂内核没有这套（我们移植引入的）
hmbird_update_task_ravg   = 0        <-- 同上
slim_walt_ctrl            = 0        <-- 同上
scx_notify_sched_tick     = 1        <-- 原厂有（风驰）
scx_scheduler_tick        = 1        <-- 原厂有
scx_switch_log            = 1        <-- 原厂有（我们树 refs=0）
scx_iso_masks             = 1        <-- 原厂有（我们树 refs=5）
hmbird_stats_open         = 1        <-- 原厂有（我们树 refs=0）
```

模块 `.modinfo` 的 `depends=sched-walt,oplus_bsp_game_opt,oplus_bsp_sched_assist,minidump`
⇒ 这 6 个符号由 `sched_walt.ko` / `oplus_bsp_sched_assist.ko` 提供。

**⇒ 结论：「我们内核需要补哪些符号」的答案是 —— 一个都不需要补，也一个都不应该补。**
缺的 6 个全在 ROM 模块侧；我们内核已经提供了它需要的那 7 个 hub 符号。
（若我们硬补一份 `register_hmbird_sched_ops`，会与 ROM 模块的同名导出撞车，改变符号解析结果。）

---

## 4. 风险清单

| 做法 | 是否可能砖机 | 依据 |
|---|---|---|
| **register 任何 sched_ext 调度器 / 让 `current->scx != NULL`** | **★必然硬挂★** | `_audit/opt54_entry.md:83`「不要在这台设备上 register 任何 scx 调度器：opt43 实测 = 整机硬挂死 + PMIC 看门狗复位」；`kernel/sched/hmbird_export.c:18-21`「registering a scheduler on this SoC hard-hangs the device」 |
| 补 DT `/soc/oplus,hmbird/version_type` | **可能**（且对本机模块无效）| `hmbird_sched_proc_main.c:69-74` 原文：「The factory vendor module compares it against HMBIRD_GKI; when the kernel's expected type and the DT's do not agree **the device does not come up** -- that is the mechanism behind the **opt43 whole-device hang followed by a PMIC reset**」；`opt54_entry.md:27` 记录 opt43 否证档「无 /sys/kernel/sched_ext」|
| 内核命令行 / sysfs / 模块参数 | 无此途径 | 模块无 module_param |
| 我们内核提供 `register_hmbird_sched_ops` 等同名符号 | **中高** | ROM 模块侧已有同名导出 ⇒ 撞车 / 双注册 |
| 只读诊断（kprobe / tracefs / sched/debug）| **安全** | captain 已实测可用 |

★ 需要澄清的一点 ★：`hmbird_sched_proc_main.c:69-74` 那段注释假设「厂商模块会比较 DT 里的 type」。
**对 GT5 Pro 的 `oplus_bsp_sched_ext.ko` 这个假设不成立**（§1.2：0 个 of_* 导入）。
所以 opt43 的真实机制**需要重新解释**：要么当年动的是 dtbo 本身（破坏了别的节点），
要么当时触发的是「注册 sched_ext 调度器」而不是「DT 不一致」。
**这条不改变结论（补 DT 仍然无效），但改变了归因，建议记录。**

---

## 5. 明确结论：推荐 / 不推荐 / 先做哪个实验

### 5.1 结论：**不推荐**改走原厂 sched_ext 路径

三条独立理由（任一条单独成立即可否掉该路线）：
1. 它的入口条件（`current->scx != NULL`）**在本机等价于 opt43 的硬挂操作**；
2. 任务书设想的两个开关（DT / 内核导出的 version 符号）**对设备模块都不存在**；
3. **它其实已经在跑**（30.505s 的 `[scx_gov][scx_cpufreq_init]` 是模块自己打的日志，而 `scx_cpufreq_init` 的唯一调用者是 `sched_ext_init`）
   ⇒ 「改走原厂路径」这个动作在语义上是「**去掉我们内核里那套多余的 hmbird_sched_class**」，而不是「打开原厂路径」。

### 5.2 ★必须先做的实验（零刷机，captain 的新观测能力刚好够用）★

| # | 实验 | 目的 | 判据 |
|---|---|---|---|
| **E1** | kprobe：`echo 'p:extinit sched_ext_init' >> /sys/kernel/tracing/kprobe_events`，然后看下次开机（或重新 insmod）是否命中 | **验证 §1 的门是否真的通过** | 若命中且未在 `current->scx==NULL` 处提前返回 ⇒ 门通过（与 30.505s 日志一致）；若命中但 `ext_module_loaded` 仍为 0 ⇒ 说明模块写的是**另一个地址**，§1 的解读需修正 |
| **E2** | kprobe：`p:scxcpufreq scx_cpufreq_init` | 独立复核 E1 | 命中 ⇒ 原厂 init 链确实跑完 |
| **E3** | 读 `ext_module_loaded` 的真值。`/proc/kcore` 与 `/dev/mem` 不可用 ⇒ **自编一个 debug .ko**（同树构建 ⇒ vermagic 一致）读 `ext_module_loaded` / `hmbird_module_loaded` | **判定「两套 hmbird 是否并存」** | `ext_module_loaded==1` ⇒ 原厂 init 跑完了 |
| **E4** | `cat /proc/hmbird_sched/hmbird_stats | tail -12`（只看真变量：`SCX Enabled` / `SCX Exit Type` / `SCX Rejected Tasks` / `DT Version Type`）；`events/hmbird/` 三个 tracepoint 是否被 enable | 观察原厂核心是否在活动 | —— |
| **E5**（可选，但价值最高）| 拉 `oplus_bsp_sched_assist.ko` 逆向，找 `register_hmbird_sched_ops` 的实现 | **比 DT 更值得做的下一步** | 弄清原厂 hmbird 核心到底做什么 |

**⇒ 只有 E1/E3 出结果，才能判断「原厂路径是否已经完整在跑」。在那之前不要做任何 DT/注册类改动。**

### 5.3 与「继续修移植」逐项对比

| 维度 | 走原厂 sched_ext 路径 | 继续修移植（opt144 那套）|
|---|---|---|
| 工作量 | **无法完成**：入口门需要注册 sched_ext 调度器（opt43 硬挂）；或依赖 ROM 模块（我们改不了）| 中：`get_hmbird_cpu_util()` 换 `trace_android_vh_get_util(cpu,NULL,&util)`（1 行）+ task util 三处（3 行）+ 去掉 `slim_walt_ctrl=1`（1 行）+ 回滚 opt142（1 行）|
| 风险 | **★必然硬挂（opt43 已实测）** | 中低：不碰 slim_walt 热路径（唯一被证明会挂的路径）；V3 已由 factory 关闭（钩子唯一注册者、无 NULL 解引用）|
| 可回退性 | 刷回即可，但每次尝试都要经历一次硬挂 + PMIC 复位 | 单提交可回退，且失败时 util=0 与今天行为一致（失败安全）|
| 能否达成用户目标「hmbird 与 sched_ext 配合可用」| **不能** —— 入口门打不开 | **能** —— 8 核铺开 + 稳定（需 ≥5 次重复实验验证）|
| 需要补的符号 | 0 个（缺的 6 个在 ROM 模块侧）| 0 个 |

### 5.4 ★一个值得单独评估的中间路线（不推荐直接做，但应记录）★

**不注册 scx 调度器，但停用/隔离我们内核的 `hmbird_sched_class`**，只保留 7 个 hub 符号
（让 ROM 模块继续正常 init），把调频交给 ROM 模块的 `scx_gov`、把负载跟踪交给 ROM 的 WALT。

| 项 | 说明 |
|---|---|
| 依据 | 原厂内核 `hmbird_sched_class` = 0 命中 ⇒ **原厂根本不需要这个类**；而 ROM 模块的 `scx_gov` + WALT 已在跑 |
| 前提 | 必须先回答「ROM 模块的原厂 hmbird 核心（`register_hmbird_sched_ops` 的实现方）到底做了什么」⇒ **需要 E5** |
| 为什么暂不推荐 | 我们不知道原厂核心是否提供「把任务铺到 8 核」的能力；若它也不提供，那停用我们的类等于**什么都不做** |
| 价值 | 若成立，它比「继续修移植」更接近原厂行为，且**完全避开 slim_walt 与 opt43 两条硬挂路径** |

---

## 附录：本次用到的全部命令（只读）

```bash
# 模块入口链（必须用 llvm-objdump；binutils objdump 报 architecture UNKNOWN）
LLVM=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin/llvm-objdump
$LLVM -dr /mnt/f/工作区/_audit/scx_vendor.ko | sed -n '/<sched_ext_init>:/,/^$/p'
$LLVM -dr ... | grep -B1 'R_AARCH64_CALL26 sched_ext_init'      # 找调用者
# 模块是否读 DT
nm -u /mnt/f/工作区/_audit/scx_vendor.ko | grep -c of_           # 0
strings -a /mnt/f/工作区/_audit/scx_vendor.ko | grep -c 'oplus,hmbird'   # 0
# task_struct->scx 偏移
pahole --hex -C task_struct /home/builder/kwork/out-core/vmlinux | grep -i scx   # 0xe18
# 原厂内核是否提供那些符号（对照组验证方法有效）
strings -a /mnt/f/工作区/_audit/stock-kernel.bin | grep -c '^hmbird_sched$'      # 1
strings -a /mnt/f/工作区/_audit/stock-kernel.bin | grep -c '^register_hmbird_sched_ops$'  # 0
# 我们内核的导出表
grep -c 'register_hmbird_sched_ops' /home/builder/kwork/out-core/Module.symvers   # 0
```
