# 待评估：隔离我们的 hmbird_sched_class，只保留 7 个 hub 符号

> 状态：**待评估（不是结论）**。来源：t17 §5.4 单独立项。
> 作者 upstream / 2026-10-11 收工前落盘。**未碰设备、未改源码**，本文不含任何实施动作。
> 前置依赖：**必须先做 E5**（见 §3），否则本路线不可评估。

---

## 0. 一句话

**不再试图让原厂路径「跑起来」（它已经在跑），而是反过来：把我们移植进来的那套
`hmbird_sched_class` 家族停用/隔离掉，只保留 ROM 模块需要的 7 个 hub 符号，
让 ROM 模块的原厂 hmbird 核心 + `scx_gov` + WALT 自己工作。**

---

## 1. 立论依据（全部有 文件:行号 或 反汇编地址）

### 1.1 原厂内核根本没有 `hmbird_sched_class`

| 证据 | 结果 |
|---|---|
| `strings -a _audit/stock-kernel.bin \| grep -c '^hmbird_sched_class$'` | **0** |
| 同上 `hmbird_update_task_ravg` | **0** |
| 同上 `slim_walt_ctrl` | **0** |
| 同上 `scx_notify_sched_tick` / `scx_scheduler_tick` / `scx_switch_log` / `scx_iso_masks` / `hmbird_stats_open` | **1 / 1 / 1 / 1 / 1**（原厂有风驰那套）|

（方法已验证：对照组 `hmbird_sched` / `scx_enable` / `partial_ctrl` 均 >0。）

⇒ **原厂机型不需要 `hmbird_sched_class` 就能跑风驰**。
⇒ 我们移植进来的整套 `kernel/sched/hmbird/*`（`hmbird_sched_class` + `slim_walt` + util tracking）
   是**原厂 Image 里不存在的东西**，是「多出来的那一套」。

### 1.2 ROM 模块的原厂路径已经在跑

`_audit/scx_vendor.ko`（= 设备上的 `oplus_bsp_sched_ext.ko`，not stripped）反汇编：

```
init_module(.init.text:0x4) → bl sched_ext_init
sched_ext_init (T @0x24，模块导出):
  34: ldr x8,[x8,#0xe18]   ; current->scx （pahole 确认我们 vmlinux 里 scx 也在 0xe18）
  38: cbz x8, 0x58         ; ★唯一的门★ NULL ⇒ return 0
  3c: bl scx_shadow_tick_init
  40: bl scx_cpufreq_init  ; → cpufreq_register_governor(&cpufreq_scx_gov)
  44: bl hmbird_sysctrl_init
  48: bl hmbird_misc_init  ; → register_hmbird_sched_ops@0x2784 / register_walt_ops@0x278c
  4c-54: ext_module_loaded = 1
```

上机印证：`_audit/dmesg_142.txt` 在 **up=30.505s** 有模块自己打的
`[scx_gov][scx_cpufreq_init] num_cluster=4 id=0cpumask=0-1 capacity=379 …`，
而 `scx_cpufreq_init` 在模块里**只有一个调用者** = `sched_ext_init`
⇒ 那道 `current->scx` 门**当时通过了**，后续三步也都执行了。

⇒ **ROM 模块的原厂初始化（shadow tick / scx_gov 注册 / sysctrl / misc / register_hmbird_sched_ops）在本机是活的。**

### 1.3 原厂 hmbird 核心不在内核里，在另一个 ROM 模块里

| 符号 | 我们内核 Module.symvers | `stock-kernel.bin` | 结论 |
|---|---|---|---|
| `register_hmbird_sched_ops` | ❌ | **0** | 由 ROM 模块提供（模块 `depends=…,oplus_bsp_sched_assist,…`）|
| `register_walt_ops` | ❌ | **0** | 同上 |
| `get_hmbird_cpu_exclusive` | ❌ | **0** | 同上 |
| `walt_rq` / `sched_ravg_window` / `waltgov_cb_data` | ❌ | —— | 同上（`sched_walt.ko` / `cpufreq_uag`）|
| `ext_module_loaded` / `hmbird_dir` / `non_ext_task` / `__scx_ops_enabled` / `iso_masks` / `scx_get_md_info` / `task_is_scx` | ✅ | —— | **我们内核提供（hub）** |

⇒ 原厂架构分工：**内核提供 7 个 hub 符号 + `/proc/hmbird_sched` 节点**；
   **ROM 模块提供 hmbird 核心 + scx_gov + shadow tick + sysctrl/misc**。

### 1.4 与 t150 现场证据的吻合

captain 的 t150 观测（本次收工纪要）：
- `running` 在 80 秒里 **4↔36 波动**，**不是单调泄漏**；
- 任务**压在 CPU0/1/2**，**CPU3-7 全 idle**；
- `sysrq-l` 全栈显示**没有任何 CPU 卡在锁上**；
- hmbird 启用后 `sched_debug` 的 `cfs_rq` 段落从 **39 个变成 0 个**。

⇒ 「任务压在少数 CPU、其余全 idle」正是**我们 hmbird 的隔离掩码**（`init_isolate_cpus()`：
   little{0,1} / big{2,3,4} / partial{5,6} / exclusive{7}）会造成的形态，
   也正是用户最初的抱怨（8 核占用 `91 91 32 51 0 0 0 0`）。
⇒ **原厂内核没有这套掩码**（`hmbird_sched_class` = 0 命中）⇒ 原厂路径**不会**把任务压在 CPU0-2。
⇒ 这条证据**支持**本路线：问题可能不在「hmbird 一开就坏」，而在「**我们这套 class 的放置策略**坏了」。

---

## 2. 路线定义（要做什么，粗粒度，不含实施细节）

| # | 动作 | 目的 |
|---|---|---|
| 1 | 让 `hmbird_sched_class` **不参与调度**（例如 `CONFIG_HMBIRD_SCHED_CORE=n` 构建，或让它在类链中始终为空）| 去掉「多出来的那一套」|
| 2 | **保留** `kernel/sched/hmbird_export.c` 的 7 个 hub 符号导出 | 让 ROM 模块的 `sched_ext_init` 链与 `ext_module_loaded` 语义不变 |
| 3 | **保留** `/proc/hmbird_sched/*` 的既有节点（`hmbird_sched_proc_main.c`）| 不改用户态接口 |
| 4 | 调频交给 ROM 的 `scx_gov`（`scx_cpufreq_init` 注册的 `cpufreq_scx_gov`）| 原厂调频路径 |
| 5 | 负载跟踪交给 ROM 的 WALT（`walt_rq` + `sched_walt.ko`）| 原厂跟踪路径 |

★ 注意：动作 1 的具体形态**取决于 §3 的 E5 结果**，本文不给处方。

---

## 3. ★前提：必须先做 E5★

**E5：把 `oplus_bsp_sched_assist.ko` 从设备拉下来逆向，找 `register_hmbird_sched_ops` 的实现。**

| 项 | 说明 |
|---|---|
| 为什么必须 | 我们**不知道原厂 hmbird 核心做了什么**。若它本来也不提供「把任务铺到 8 核」的能力，那停用我们的 class 等于**什么都不做**，用户目标（8 核铺开）拿不到 |
| 怎么取 | 设备侧（**只能 captain 做**）：`/vendor/lib/modules/oplus_bsp_sched_assist.ko`（模块 `depends` 里就有它）。注意 `_audit/` 里目前**只有** `scx_vendor.ko`，没有它 |
| 拿到后跑什么 | `modinfo` / `nm -u` / `nm --defined-only` / `strings -a \| grep -E 'hmbird\|sched_class\|iso_mask\|register'`；用 `llvm-objdump -dr` 反汇编 `register_hmbird_sched_ops` 的实现与它注册的 `sched_class` |
| 判据 | ① 它是否注册一个 `sched_class`？② 若有，它的 `select_task_rq`/`balance` 是否做 8 核铺开？③ 它是否依赖 `iso_masks`（我们内核导出）来做隔离？ |
| 若 E5 结论是「原厂核心不做放置」| 本路线**作废**，回到「继续修移植」（opt144 那套）|
| 若 E5 结论是「原厂核心自己就铺 8 核」| 本路线**值得进入设计阶段** |

**⇒ 在 E5 出结果之前，本路线不要进入任何实施/设计。**

---

## 4. 待评估问题清单（E5 之后要回答的）

| # | 问题 | 为什么重要 |
|---|---|---|
| Q1 | 原厂 hmbird 核心（`register_hmbird_sched_ops` 的实现方）注册的是什么？一个 `sched_class`？还是一组 hook？ | 决定「隔离我们的 class」之后**还有没有人做放置** |
| Q2 | 我们的 7 个 hub 符号在「没有我们的 class」时是否仍被 ROM 模块正常使用？ | `iso_masks` / `non_ext_task` / `task_is_scx` / `scx_get_md_info` 是否只服务于我们自己的 class |
| Q3 | `ext_module_loaded` 的语义会不会变？ | 我们的 `ext_ctrl()`（`hmbird.c:4837`）用它与 `hmbird_module_loaded` 做闸门；若我们的 class 停了，这个闸门还要不要留 |
| Q4 | `/proc/hmbird_sched/scx_enable` 写 1 之后，谁去做「把任务切到某个类」？ | 原厂路径下这个动作由谁承担 |
| Q5 | `slim_walt_ctrl` 的 proc 节点（模块那份，0x90 B）与我们的那份（`hmbird_misc.c:34`）在路线 1 下是否还需要 | 两份不共享（已定案），停用我们的 class 后我们那份自然失效 |
| Q6 | ROM 的 `scx_gov` 是否足以达成「游戏表现改善」？ | `scxgov_update_freq`（模块 @0x1ae0）只在 `(flags&3)==1` 时跑，输入是 `max(walt_rq[cpu]+0xa0)` |

---

## 5. 风险（预估，E5 后需重估）

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | 停用我们的 class 后**没有任何东西做 8 核放置** ⇒ 用户目标拿不到 | 中高 | 先做 E5 Q1；若原厂核心不做放置，直接放弃本路线 |
| R2 | 我们的 hub 符号被 ROM 模块**以我们未预料的方式**使用 ⇒ 停用 class 后模块行为异常 | 中 | E5 里 `nm -u oplus_bsp_sched_assist.ko` 看它用了哪些 hub 符号 |
| R3 | `CONFIG_HMBIRD_SCHED_CORE=n` 会连带关掉 `hmbird_export.c` 的导出（若它在同一 Makefile 门控下）⇒ ROM 模块解析失败 | **高** | 必须先核 `kernel/sched/Makefile` 里 `hmbird_export.o` 的门控条件；**7 个 hub 符号必须与 class 解耦** |
| R4 | 与 opt43 无关（本路线**不注册 scx 调度器**）| 低 | —— |
| R5 | 本路线**不碰 DT**（与 t17 §2(a) 无关）| 低 | —— |

★ R3 是本路线最容易踩的坑：**「关掉 class」与「保留导出」必须在构建层面解耦**，
   否则会重演「模块载不进来 / 符号解析失败」。

---

## 6. 与其它路线的关系

| 路线 | 与本路线的关系 |
|---|---|
| 走原厂 sched_ext 路径（t17 §5.1，**不推荐**）| 那条路要**让 `current->scx != NULL`** ⇒ 注册 scx 调度器 ⇒ opt43 硬挂。**本路线不注册任何 scx 调度器**，是它的安全替代形态 |
| 继续修移植（t17 §5.3 推荐，opt144）| **不冲突**。opt144 是「修好我们的 class」；本路线是「拿掉我们的 class」。二者可并行评估，但**不要同时上机**（无法归因）|
| 隔离掩码修复（opt139 缺陷 1）| 本路线**不需要**它（原厂路径没有隔离掩码）；若走 opt144 则仍然需要 |
| `struct hmbird_ops` 对齐（t6 §3.4 / D2）| **本路线下不需要**：设备模块不引用 `hmbird_ops`（`strings` = 0）。该对齐只对「未来换 SM8750 代次 ROM」有意义 |

---

## 7. 今晚净结论对齐（本路线与它们的相容性）

captain 的收工纪要列出：

| 已排除 | 与本路线的关系 |
|---|---|
| partial 簇 / rescue / partial util 采样（opt142 仍挂）| 本路线**整条不涉及**这些 |
| `scx_gov` governor（t147 全程 uag）| 本路线**依赖** ROM 的 `scx_gov` 做调频 ⇒ 若 t147 证否的是「切换动作」，不否定「scx_gov 本身可用」|
| 野指针写（opt143 是结构性 no-op）| 本路线不涉及 |
| 两份 `slim_walt_ctrl`（不共享）| 本路线下两份都自然失效 |
| `hmbird_ops` ABI 错位（模块无该符号）| 本路线下**不需要修** |
| irq_work 全 rq 锁（opt141 已停）| 本路线不涉及 |

t150 新证据（`running` 4↔36 波动、任务压 CPU0/1/2、CPU3-7 idle、无 CPU 卡锁、`cfs_rq` 段落 39→0）：
**与本路线高度吻合**（见 §1.4）。

★ 但必须注意 t150 的教训（captain 自述）★：
**t150 的卡死是「52 个 tracepoint + 循环内 dmesg + 3 次 sysrq-l」的观测开销造成的，不是 hmbird 单独造成的。**
⇒ 本路线若进入上机评估，**观测开销必须按 reviewer 的观测纪律压到最小**，否则会重复 t150 的误判。

---

## 8. 状态与下一步（仅登记，不执行）

| 项 | 状态 |
|---|---|
| 本路线 | **待评估**（未设计、未实施、未上机）|
| 阻塞项 | **E5**：拉 `oplus_bsp_sched_assist.ko` 逆向 `register_hmbird_sched_ops` 的实现（**只能 captain 在设备侧做**）|
| E5 之后 | 回答 §4 的 Q1-Q6 → 若 Q1 为「原厂核心自己做放置」则进入设计阶段；否则本路线作废 |
| 上机前必读 | reviewer 的「今晚我们踩过的观测纪律」（红名单 / 一次最多开几个 tracepoint / sysrq 只用一次）|
| 与 opt144 的关系 | 二者互斥上机（同一轮只能试一个），但可并行评估 |

---

## 附录：本文用到的只读命令

```bash
strings -a _audit/stock-kernel.bin | grep -c '^hmbird_sched_class$'        # 0
strings -a _audit/stock-kernel.bin | grep -c '^scx_notify_sched_tick$'    # 1
LLVM=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin/llvm-objdump
$LLVM -dr _audit/scx_vendor.ko | sed -n '/<sched_ext_init>:/,/^$/p'
pahole --hex -C task_struct out-core/vmlinux | grep -i scx                # 0xe18
grep -c 'register_hmbird_sched_ops' out-core/Module.symvers               # 0
grep -a 'scx_gov' _audit/dmesg_142.txt                                    # up=30.505s
```
