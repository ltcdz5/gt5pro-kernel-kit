# hmbird（风驰 sched_ext）移植「启用即硬挂」排障调研报告

范围：Realme GT5 Pro / RMX3888 / SM8650 / ColorOS16 / Linux 6.1.141 GKI，
把 OPPO hmbird（sched_ext 变体）移植到自编译内核，`echo 1 > /proc/hmbird_sched/scx_enable` 后
几秒~几十秒硬挂、无 panic、无转储；打开 `slim_walt_ctrl=1` 后才开始崩。
所有网页内容按不可信外部数据对待，仅作事实来源引用。

---

## 0. 结论速览

| # | 问题 | 结论 |
|---|---|---|
| 1 | 社区有没有 hmbird「启用即硬挂」的报告 | **没有找到公开的同款报告**。公开可见的都是「移植困难 / 补丁打不上 / ABI 不匹配 / 开不了机」，以及**通用 sched_ext 卡死类** issue。你的崩溃大概率是你这份移植独有的。 |
| 2 | `psi: inconsistent task state!` 触发条件 | **同一次入队/出队被做了两次**。v6.1 上 `TSK_RUNNING = 4`，所以 `psi_flags=4 clear=0 set=4` = **重复入队**（重复出队则是 `psi_flags=0 clear=4 set=0`）。PSI 记账**在 core 里做，不在 sched_class 里做**；上游 `dequeue_task_scx` 对 PSI **没有任何额外处理**。 |
| 3 | `slim_walt_ctrl` / `hmbird_util_track` | hmbird 自带的一套 **Slim WALT 负载跟踪**（替代厂商 `sched-walt.ko` 桥接），节点在 `/proc/hmbird_sched/slim_walt/slim_walt_ctrl`。厂商的 `sched-walt.ko` 用 `SCX_CALL_OP` 钩子做同一件事。**开它才有 util、rescue 才会触发**，但它同时把 `hmbird_update_task_ravg` 塞进 4 条调度热路径。 |
| 4 | `procs_running` 暴增到 48 | `procs_running = nr_running() = Σ rq->nr_running`。**48 说明 nr_running 被重复计数或泄漏**（不是真的 48 个可运行任务），并且会形成负载均衡正反馈。 |
| 5 | 无 panic 静默硬挂 | 对应「全 CPU 持锁/关中断自旋」「跨 CPU 加锁顺序互逆」「watchdog 自身来不及/无法动作」几类。受限内核下**最有效的一步是把静默挂改成 panic**（`hardlockup_panic` / `softlockup_panic` / `hung_task_panic`）+ pstore/ramoops。 |

---

## 1. 社区里有没有同类报告

### 1.1 明确相关的公开材料

- **OnePlusOSS 官方仓库 issue #21**（最接近、最有价值）：
  <https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750/issues/21>
  报告人指出**公开源码无法复现出厂 HMBIRD/WALT ABI**：
  - 出厂 `boot.img` 配置里有 `CONFIG_HMBIRD_SCHED=y`，且 kallsyms 里有
    `enqueue_task_hmbird / pick_next_task_hmbird / hmbird_sched_class / init_sched_hmbird_class`，
    字符串指向 `kernel/sched/hmbird/hmbird.c`；而公开源码里**只有 `CONFIG_HMBIRD_SCHED_GKI` 与接口桩**。
  - 出厂 `sched-walt.ko` 的 `struct walt_rq` **648 字节 / 40 成员**，比公开源码多
    **`curr_runnable_sum_fixed`（偏移 152）与 `prev_runnable_sum_fixed`（偏移 160）**；
    公开源码是 632 字节、没有这两个字段，导致 `walt_rq` 的导出 CRC 不一致。
  - 症状是 bootloop/fastboot，不是硬挂，但**直接印证了你担心的字段偏移问题**。
- **reigadegr/hmbird_controller**（`scx_enable` 守护模块）：
  <https://github.com/reigadegr/hmbird_controller>
  issue 区只有一条、且是补丁打不上：
  <https://github.com/reigadegr/hmbird_controller/issues/1>
- **Numbersf/SCHED_PATCH issue #2**（风驰补丁打不上，`kernel/sched/core.c` hunk 失败）：
  <https://github.com/Numbersf/SCHED_PATCH/issues/2>
- **LunarKernel-Dev/lunarkernel_sched_extention（LSE）** —— 目前公开资料里对 hmbird 架构讲得最清楚的一份：
  <https://github.com/LunarKernel-Dev/lunarkernel_sched_extention>
  要点：
  - 风驰有两个版本：**`hmbird`（6.1 与 MTK 用，魔改 sched_ext 调度类，节点在 `/proc/hmbird_sched`）**；
    **`hmbird_gki`（6.6 高通用，节点在 `/proc/sys/oplus_sched_ext`，靠 `sched_assist` 的 ots +
    在 sched-walt 里插 `SCX_CALL_OP` 钩子）**。你的 6.1 属于前者。
  - 原话：「**移植 hmbird 的工作量十分巨大困难，并且大量修改了内核本体，可以认为破坏了 KMI，我不推荐**」；
    「**OP 开源的 `SCX_CALL_OP` 有问题，你需要自己写 hook 框架**」。
- **cctv18/oppo_oplus_realme_sm8750**（欧加真 6.6 风驰移植自动化）：
  <https://github.com/cctv18/oppo_oplus_realme_sm8750>
  README 里直白说明「**绿厂官方摆烂，代码开源开一半**，导致部分内核代码无法通过已有的配置 xml 正常编译」。
- **WildKernels/OnePlus_KernelSU_SUSFS**（releases 带 🐦HMBIRD 标记）：
  <https://github.com/WildKernels/OnePlus_KernelSU_SUSFS>
  release 列表里 HMBIRD 只作为特性标记出现，未见「开启后硬挂」的 issue。
- **Numbersf/Action-Build issue #279**（一加 ACE5 刷 baka 内核后无限重启，且**未启用风驰**）：
  <https://github.com/Numbersf/Action-Build/issues/279>
  → 说明这类设备上「重启/挂死」多数与风驰无关，不能反推。
- **Reddit 上 OnePlus 13 风驰 SCX vs WALT 实测**（只有性能对比，无崩溃）：
  <https://www.reddit.com/r/MaxsTechReview/comments/1l9dlzm/oneplus_13_fengchi_vs_the_precinct_comparison_scx/>

### 1.2 通用 sched_ext 卡死/冻结类（可类比，但不是 hmbird）

- CachyOS 论坛 *Sched-ext crashing lately*：<https://discuss.cachyos.org/t/sched-ext-crashing-lately/17705>
- scx issue #3180 `scx_flash` 崩溃：<https://github.com/sched-ext/scx/issues/3180>
- scx issue #3687（框架侧冻结，含 **`note: rcu_preempt exited with irqs disabled`**）：
  <https://github.com/sched-ext/scx/issues/3687>
- scx issue #1202（watchdog 与 RT 任务）：<https://github.com/sched-ext/scx/issues/1202>
- scx_enable() 建 kthread 失败即崩溃：<https://patchew.org/linux/20251119103722.309211-1-skb99@linux.ibm.com/>

### 1.3 结论

**没有搜到任何人报告「OPPO hmbird 启用后硬挂」**。酷安/知乎/XDA/Reddit/HN 层面的讨论基本停留在
「怎么移植、怎么刷、跑分多少」。所以：

> 这不是一个「已知 bug，照抄补丁即可」的问题，而是你这份移植自身的缺陷。
> 但也因此，**不能指望靠搜社区拿到答案，必须靠二分 + 打点自证**。

---

## 2. `psi: inconsistent task state!` 的确切触发条件

### 2.1 告警代码本体（Linux 6.1）

来源：<https://github.com/torvalds/linux/blob/v6.1/kernel/sched/psi.c>

```c
static void psi_flags_change(struct task_struct *task, int clear, int set)
{
        if (((task->psi_flags & set) ||
             (task->psi_flags & clear) != clear) &&
            !psi_bug) {                       /* ← 每次启动只报一次 */
                printk_deferred(KERN_ERR "psi: inconsistent task state! "
                        "task=%d:%s cpu=%d psi_flags=%x clear=%x set=%x\n",
                        task->pid, task->comm, task_cpu(task),
                        task->psi_flags, clear, set);
                psi_bug = 1;
        }
        task->psi_flags &= ~clear;
        task->psi_flags |= set;
}
```

**触发条件只有两种，都是「同一次状态迁移被做了两次」：**

1. `(psi_flags & set) != 0` —— 想把一个**已经置位的 bit 再置一次** → **重复入队**；
2. `(psi_flags & clear) != clear` —— 想清一个**本来就没置位的 bit** → **重复出队 / 清了没入过队的任务**。

因为 `psi_bug` 是全局一次性开关，**这条日志每次开机只会出现一次**，很容易被忽略或误判为「偶发」。

### 2.2 位定义（关键：`TSK_RUNNING = 4`）

来源：<https://github.com/torvalds/linux/blob/v6.1/include/linux/psi_types.h>

```c
enum psi_task_count { NR_IOWAIT, NR_MEMSTALL, NR_RUNNING, NR_MEMSTALL_RUNNING,
                      NR_PSI_TASK_COUNTS = 4 };
#define TSK_IOWAIT            (1 << NR_IOWAIT)            /* 0x1 */
#define TSK_MEMSTALL          (1 << NR_MEMSTALL)          /* 0x2 */
#define TSK_RUNNING           (1 << NR_RUNNING)           /* 0x4  ← 就是它 */
#define TSK_MEMSTALL_RUNNING  (1 << NR_MEMSTALL_RUNNING)  /* 0x8 */
#define TSK_ONCPU             (1 << NR_PSI_TASK_COUNTS)   /* 0x10 */
```

所以：

| 日志 | 含义 |
|---|---|
| `psi_flags=4 clear=0 set=4` | **重复入队**（任务已在运行队列上，又被 enqueue 一次） |
| `psi_flags=0 clear=4 set=0` | **重复出队**（任务已不在队列上，又被 dequeue 一次） |

LKML 上那个著名的 swapper/0 例子就是前者的标准形态：
<https://lkml.iu.edu/2409.2/05906.html>

### 2.3 PSI 记账在哪一步做（这是最关键的认知）

来源：<https://github.com/torvalds/linux/blob/v6.1/kernel/sched/stats.h>
与 <https://github.com/torvalds/linux/blob/v6.1/kernel/sched/core.c>

```c
/* stats.h (6.1) */
static inline void psi_enqueue(struct task_struct *p, bool wakeup)
{
        int clear = 0, set = TSK_RUNNING;          /* ← 入队必然置 TSK_RUNNING */
        if (static_branch_likely(&psi_disabled)) return;
        if (p->in_memstall) set |= TSK_MEMSTALL_RUNNING;
        if (!wakeup || p->sched_psi_wake_requeue) { ... }
        else { if (p->in_iowait) clear |= TSK_IOWAIT; }
        psi_task_change(p, clear, set);
}
static inline void psi_dequeue(struct task_struct *p, bool sleep)
{
        int clear = TSK_RUNNING;
        if (static_branch_likely(&psi_disabled)) return;
        if (sleep) return;      /* 自愿睡眠交给 psi_task_switch() 一起做 */
        if (p->in_memstall) clear |= (TSK_MEMSTALL | TSK_MEMSTALL_RUNNING);
        psi_task_change(p, clear, 0);
}

/* core.c (6.1) */
static inline void enqueue_task(struct rq *rq, struct task_struct *p, int flags)
{
        ...
        if (!(flags & ENQUEUE_RESTORE)) {
                sched_info_enqueue(rq, p);
                psi_enqueue(p, flags & ENQUEUE_WAKEUP);   /* 先 PSI */
        }
        uclamp_rq_inc(rq, p);
        p->sched_class->enqueue_task(rq, p, flags);        /* 后 sched_class */
        ...
}
static inline void dequeue_task(struct rq *rq, struct task_struct *p, int flags)
{
        ...
        if (!(flags & DEQUEUE_SAVE)) {
                sched_info_dequeue(rq, p);
                psi_dequeue(p, flags & DEQUEUE_SLEEP);     /* 先 PSI */
        }
        uclamp_rq_dec(rq, p);
        p->sched_class->dequeue_task(rq, p, flags);        /* 后 sched_class */
}

void activate_task(struct rq *rq, struct task_struct *p, int flags)
{
        enqueue_task(rq, p, flags);
        p->on_rq = TASK_ON_RQ_QUEUED;      /* ← 注意：没有 task_on_rq_queued() 保护！ */
}
void deactivate_task(struct rq *rq, struct task_struct *p, int flags)
{
        p->on_rq = (flags & DEQUEUE_SLEEP) ? 0 : TASK_ON_RQ_MIGRATING;
        dequeue_task(rq, p, flags);
}
```

**推论：**

- PSI 状态完全由 **core 的 enqueue_task/dequeue_task** 维护，
  `p->sched_class->enqueue_task()` / `dequeue_task()` **不负责 PSI**。
- 上游 sched_ext 的 `dequeue_task_scx()` 里**没有任何 PSI 处理**
  （见 <https://github.com/torvalds/linux/blob/master/kernel/sched/ext.c>；
  你本地移植版同样如此：`_lab/2026-10-08/scx-step4g/scx-branch/kernel/sched/ext.c:1806`
  全文只有 `ops_dequeue / trace_android_vh_hmbird_update_load / SCX_TASK_DEQD_FOR_SLEEP /
  sub_nr_running / dispatch_dequeue`，**没有任何 `psi_` 调用**）。
  → 所以「自定义 sched_class 需要额外补 PSI」这个方向是**错的**；正确方向是
  **「谁绕过了 core 的 enqueue/dequeue 对，谁就制造了双计数」**。
- `activate_task()` **不检查 `task_on_rq_queued()`**。任何人在任务已经 on_rq 时再调一次
  `activate_task()`，就会：`psi_enqueue` 重复置 `TSK_RUNNING`（→ 本条告警）
  **并且 `add_nr_running()` 再加 1**（→ `procs_running` 虚高）。
  **这一条同时解释了你观察到的两个现象。**

### 2.4 「自定义 sched_class 的任务被厂商 WALT LB 拉走时，最容易漏哪一步」

对比上游与厂商实现：

**上游 `kernel/sched/fair.c`（v6.1）**：<https://github.com/torvalds/linux/blob/v6.1/kernel/sched/fair.c>

```c
static int can_migrate_task(struct task_struct *p, struct lb_env *env)
{
        if (throttled_lb_pair(...)) return 0;
        if (kthread_is_per_cpu(p)) return 0;            /* 排除 per-cpu kthread */
        if (!cpumask_test_cpu(env->dst_cpu, p->cpus_ptr)) { ... return 0; }
        if (task_on_cpu(env->src_rq, p)) { ... return 0; }   /* 排除正在跑的 */
        ...
}
static void detach_task(struct task_struct *p, struct lb_env *env)
{
        lockdep_assert_rq_held(env->src_rq);
        deactivate_task(env->src_rq, p, DEQUEUE_NOCLOCK);
        set_task_cpu(p, env->dst_cpu);
}
static void attach_task(struct rq *rq, struct task_struct *p)
{
        lockdep_assert_rq_held(rq);
        WARN_ON_ONCE(task_rq(p) != rq);
        activate_task(rq, p, ENQUEUE_NOCLOCK);
        check_preempt_curr(rq, p, 0);
}
```
且 `detach_tasks()` 只遍历 `env->src_rq->cfs_tasks`（**sched_ext 任务不在这个链表上**），
`attach_tasks()` 在持有 dst rq 锁时把 `env->tasks` 上的任务逐个 attach。

**厂商 WALT `walt_lb.c`**：
<https://github.com/realme-kernel-opensource/realme_GT7pro-AndroidB-kernel-source/blob/c541ad76/kernel/sched/walt/walt_lb.c>

```c
static inline bool _walt_can_migrate_task(struct task_struct *p, int dst_cpu,
                                          bool to_lower, bool to_higher, bool force)
{
        struct walt_rq *wrq = &per_cpu(walt_rq, task_cpu(p));
        struct walt_task_struct *wts = (struct walt_task_struct *) p->android_vendor_data1;
        if (wrq->push_task == p) return false;
        ... /* 只做 boost / rtg / pipeline / fits_max / cpu_halted 判断 */
        return true;
}                                        /* ← 没有 task_on_rq_queued()，也没有 sched_class 判断 */

void walt_detach_task(struct task_struct *p, struct rq *src_rq, struct rq *dst_rq)
{
        //TODO can we just replace with detach_task in fair.c??
        deactivate_task(src_rq, p, 0);          /* flags=0 → on_rq = TASK_ON_RQ_MIGRATING */
        set_task_cpu(p, dst_rq->cpu);
}
void walt_attach_task(struct task_struct *p, struct rq *rq)
{
        activate_task(rq, p, 0);
        check_preempt_curr(rq, p, 0);
}

static int walt_lb_pull_tasks(int dst_cpu, int src_cpu, struct task_struct **pulled_task_struct)
{
        raw_spin_lock_irqsave(&src_rq->__lock, flags);
        list_for_each_entry_reverse(p, &src_rq->cfs_tasks, se.group_node) {
                if (!cpumask_test_cpu(dst_cpu, p->cpus_ptr)) continue;
                if (task_on_cpu(src_rq, p)) continue;        /* 只挡了"正在跑" */
                if (!_walt_can_migrate_task(p, dst_cpu, to_lower, to_higher, false)) continue;
                ...
        }
        if (pull_me) { walt_detach_task(pull_me, src_rq, dst_rq); goto unlock; }
        ...
unlock:
        raw_spin_unlock_irqrestore(&src_rq->__lock, flags);
        if (!pull_me) return 0;
        raw_spin_lock_irqsave(&dst_rq->__lock, flags);      /* ← detach 与 attach 之间放锁 */
        walt_attach_task(pull_me, dst_rq);
        raw_spin_unlock_irqrestore(&dst_rq->__lock, flags);
        ...
}
```

**最容易漏掉的三步（按危险程度）：**

1. **没有 `task_on_rq_queued(p)` 校验。** 只要 `p` 还挂在 `src_rq->cfs_tasks` 上，
   就会被选中并 `deactivate_task()`。如果这个任务其实**已经不在队列上**（例如某个
   自定义 class 的 dequeue 忘了 `list_del(&p->se.group_node)`，或者 sched_ext 把
   任务挂在 cfs_tasks 上却没维护好），就是**对没入队的任务做出队** → `psi_flags=0 clear=4 set=0`。
2. **detach 与 attach 之间释放了 rq 锁。** 这段窗口里 `p->on_rq = TASK_ON_RQ_MIGRATING`、
   `task_cpu(p)` 已改成 dst。此时若发生一次唤醒，`ttwu_runnable()` 会因为
   `!task_on_rq_queued(p)` 而走完整唤醒路径 → `activate_task(dst_rq, p, ...)`；
   随后 WALT 自己的 `walt_attach_task()` **又 `activate_task()` 一次** →
   **对同一个任务双入队** → `psi_flags=4 clear=0 set=4` **且 `nr_running` +1**。
   上游 `detach_task()/attach_task()` 用 `DEQUEUE_NOCLOCK`/`ENQUEUE_NOCLOCK`
   并由 `attach_tasks()` 在 dst 锁内立即完成，窗口小得多；厂商这条路径窗口更大。
3. **没有 `p->sched_class` 过滤。** `rq->cfs_tasks` 是 fair 私有链表，正常不应有 sched_ext 任务；
   但如果移植把 hmbird 任务也挂了上去（或残留了 `se.group_node`），
   厂商 LB 会**按 fair 语义去 deactivate/activate 一个 ext 任务**，
   而 ext 的 `dequeue_task_scx` 见到 `SCX_TASK_QUEUED` 已清就 **early-return，
   不做 `sub_nr_running()`**（见 §4）→ 计数彻底失衡。

### 2.5 上游有没有「为 PSI 打补丁」的先例？有，但那是 6.12 的 `sched_delayed`

- `[PATCH] sched: psi: handle delayed-dequeue task migration` —— Johannes Weiner：
  <https://lkml.iu.edu/2410.1/05468.html>
  原话：「**Since sched_delayed tasks remain queued even after blocking, the load balancer can
  migrate them between runqueues while PSI considers them to be asleep. As a result, it
  misreads the migration requeue followed by a wakeup as a double queue**」，
  症状正是 `psi: inconsistent task state! ... psi_flags=4 clear=. set=4`。
- 合入版本（`c6508124193d42bbc3224571eb75bfa4c1821fbb`）：
  <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2410.1/08909.html>
  补丁说明还强调：「**It's not just the warning in dmesg, the task state corruption causes a
  permanent CPU pressure indication**」。
- 6.12 之前的同类讨论（`psi_enqueue` 要在 `->enqueue_task()` **之后**调用）：
  <https://lkml.iu.edu/2409.2/05906.html>
- Arch 论坛用户从 6.12.1 起看到同一条日志：
  <https://bbs.archlinux.org/viewtopic.php?id=301794>
- 代理执行（proxy exec）下同类告警：
  <https://www.spinics.net/lists/kernel/msg5931579.html>（该站对抓取返回 403，仅作引用）

**注意：`sched_delayed` 是 6.12 引入的机制，你的 6.1.141 没有它。**
所以 6.12 的那个具体 bug 不适用；但它给出了**同一类**根因的判据：
**「负载均衡迁移了一个 PSI 认为是睡着的任务」→ 迁移重入队 + 唤醒 = 双入队。**

### 2.6 顺带：上游 `ops.dequeue()` 语义本身也是「不可靠」的

`[PATCHSET v5] sched_ext: Fix ops.dequeue() semantics`：
<https://lore-kernel.gnuweeb.org/lkml/20260204160710.1475802-1-arighi@nvidia.com/>
→ 如果你打算靠 `ops.dequeue` 回调做记账，要注意上游已经承认它当前不可靠。

---

## 3. `slim_walt_ctrl` / `hmbird_util_track` 是什么

### 3.1 它是什么（以你工作区内的厂商源码为准）

- `_audit/vendor-src/kernel-hmbird/hmbird_util_track.c` —— hmbird **自带的 Slim WALT 负载跟踪实现**：
  - `DEFINE_PER_CPU(struct hmbird_sched_rq_stats, hmbird_sched_rq_stats)`（第 20 行）
  - `hmbird_sched_ravg_window = 8000000`（8ms / 125Hz 窗口）
  - `scale_exec_time()` / `add_to_task_demand()` / `update_history()` / `update_task_demand()` /
    `update_cpu_busy_time()` / `rollover_cpu_window()` / `update_window_start()` —— 一套完整 ravg 实现
  - `slim_walt_cpu_util()` / `slim_get_cpu_util()` / `slim_get_task_util()` —— 对外提供 util
  - `static struct irq_work hmbird_slim_walt_irq_work`（第 23 行）
- **入口函数 `hmbird_update_task_ravg()`（第 466 行起）**：

```c
void hmbird_update_task_ravg(struct task_struct *p, struct rq *rq, int event, u64 wallclock)
{
        struct hmbird_sched_task_stats *sts = &(get_hmbird_ts(p)->sts);   /* ← 先解引用！ */
        struct hmbird_sched_rq_stats *srq = &per_cpu(hmbird_sched_rq_stats, cpu_of(rq));
        u64 old_window_start;

        if (!slim_walt_ctrl)        /* ← 开关判断在解引用之后 */
                return;
        if (!srq->window_start || sts->mark_start == wallclock)
                return;
        old_window_start = update_window_start(rq, wallclock, event);
        if (!sts->window_start) sts->window_start = srq->window_start;
        if (!sts->mark_start) goto done;
        update_task_rq_cpu_cycles(p, rq, event, wallclock);
        update_task_demand(p, rq, event, wallclock);
        update_cpu_busy_time(p, rq, event, wallclock);
        sts->window_start = srq->window_start;
done:
        sts->mark_start = wallclock;
        slim_walt_window_rollover_run_once(old_window_start, rq);
}
```

- **开关本体 `slim_walt_enable()`（第 594 行）**：

```c
void slim_walt_enable(int enable)
{
        if (1 == !!enable) {
                hmbird_sched_stats_init();      /* 逐个 rq 加锁初始化 window_start / prev_window_size */
                WRITE_ONCE(tick_sched_clock, 0);
        } else
                slim_walt_ctrl = 0;             /* 只关标志，不清理已排队的 irq_work / 窗口状态 */
}
```

- **proc 节点**：`_audit/vendor-src/kernel-hmbird/hmbird_sched_proc.c`
  - 第 592–596 行：`/proc/hmbird_sched/slim_walt/slim_walt_ctrl`
  - 第 232–247 行：`slim_walt_ctrl_write()` → 直接 `slim_walt_enable(tmp_val)`
  - 同目录还有 `slim_walt_dump`、`slim_walt_policy`

### 3.2 厂商为什么需要它 / 什么条件下打开

- hmbird 的 **rescue（partial/exclusive 核唤醒）判据**依赖 CPU util：
  `_audit/vendor-src/kernel-hmbird/hmbird.c:843-854`：

```c
static u64 get_cpus_max_util(struct cpumask *mask)
{
        for_each_cpu(cpu, mask) {
                if (slim_walt_ctrl)
                        slim_get_cpu_util(cpu, &util);      /* 走 hmbird 自带跟踪 */
                else
                        util = get_hmbird_cpu_util(cpu);    /* 走厂商 walt_rq 桥接字段 */
                ...
        }
}
```
- 关闭 hmbird 时：`hmbird.c:3704-3705` `if (slim_walt_ctrl) slim_walt_enable(false);`
- **两种数据源二选一**：
  - `slim_walt_ctrl=0` → 读 `get_hmbird_rq(rq)->prev_runnable_sum_fixed`，
    而该指针**唯一的写入者是厂商 `sched-walt.ko` 的 `init_hmbird_rq_wrq_variables()`**，
    只在 `get_hmbird_version_type() == HMBIRD_OGKI_VERSION` 时才调用
    （与你 `_audit/报告-20261011-夜间-hmbird放置修复.md` 里的记录一致）。
  - `slim_walt_ctrl=1` → 读 hmbird 自己的 `srq->prev_runnable_sum`，不依赖厂商模块。
- **LSE（LunarKernel）对 `slim_walt_ctrl` 的说明**（公开、可引用）：
  <https://github.com/LunarKernel-Dev/lunarkernel_sched_extention>
  > `slim_walt_ctrl`: 启用 Slim WALT 负载跟踪，**别随便关不然没法调频** ((((
  → 即：这是**调频/负载**链路的地基，不是可选的调试开关。
  对 6.6 的 `hmbird_gki`，等价的机制是「内建高通 sched-walt 模块 + 在 `SCX_CALL_OP` 钩子里
  调 `update_task_ravg` 的最小化回调」。

### 3.3 有没有「打开它就崩」的已知案例或补丁

**没有找到任何公开案例**。逐符号检索结果：

| 符号 | 公开可查情况 |
|---|---|
| `slim_walt_ctrl` | 只在 hmbird 厂商源码与 LSE 移植里出现；无 bug 报告 |
| `hmbird_sched_rq_stats` | 同上（`DEFINE_PER_CPU`，仅 hmbird 内部使用） |
| `slim_walt_irq_work` | 同上 |
| `prev_runnable_sum_fixed` | **唯一有实质信息的是 OnePlusOSS issue #21**：该字段是**出厂私有 ABI**，公开源码里没有；出厂 `struct walt_rq` 比公开源码多 `curr_runnable_sum_fixed`(152) 与 `prev_runnable_sum_fixed`(160)。<https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750/issues/21> |

### 3.4 `slim_walt_ctrl=1` 打开后新增了什么（这是你崩溃的「新增面」）

1. **4 条调度热路径开始调用 `hmbird_update_task_ravg`**
   （task_tick / set_next / put_prev / dequeue，即你 `报告-20261011` 里列的）。
2. `hmbird_update_task_ravg_rqclock_wrapper()` 会在 `!(rq->clock_update_flags & RQCF_UPDATED)`
   时调用 `update_rq_clock(rq)` —— **如果调用点没有持有 rq 锁，这是未定义行为**
   （正常 `update_rq_clock()` 有 `lockdep_assert_rq_held`，而你的内核没有 lockdep）。
3. `hmbird_sched_stats_init()`：`slim_walt_enable(1)` 时逐个 rq 加锁重置窗口。
4. `slim_walt_window_rollover_run_once()` → `irq_work_queue(&hmbird_slim_walt_irq_work)`。
5. `slim_walt_irq_work()`（第 494 行）：

```c
static void slim_walt_irq_work(struct irq_work *irq_work)
{
        cpumask_copy(&lock_cpus, cpu_possible_mask);
        for_each_cpu(cpu, &lock_cpus) {
                if (level == 0) raw_spin_lock(&cpu_rq(cpu)->__lock);
                else raw_spin_lock_nested(&cpu_rq(cpu)->__lock, level);
                level++;
        }
        wc = sched_clock();
        for_each_cpu(cpu, &lock_cpus)
                hmbird_update_task_ravg(cpu_rq(cpu)->curr, cpu_rq(cpu), TASK_UPDATE, wc);
        cpufreq_update_util(cpu_rq(0), HMBIRD_CPUFREQ_WINDOW_ROLLOVER);
        ...
        for_each_cpu(cpu, &lock_cpus)
                raw_spin_unlock(&cpu_rq(cpu)->__lock);
}
```

   → **在 hard-IRQ 上下文里，按 CPU 升序一次性持住全部 rq 锁**。
   而调度器其它路径（`double_lock_balance`）的加锁顺序是
   「先 busiest、再 this_rq」，与 CPU 升序**不构成全序**，存在 AB-BA 可能。
   你的 `opt140/opt141` 审核已经证明这条在 t139/t140 上不是空操作之外的原因，
   `opt141` 干脆不再排队它；**但 `slim_walt_enable(1)`/`hmbird_sched_stats_init()` 仍在，
   而且 `slim_walt_enable(false)` 不会取消已排队的 irq_work**。

6. **★最值得怀疑的一点★**：`get_hmbird_ts(p)` 在 **`slim_walt_ctrl` 判断之前**就被求值，
   且 `hmbird_update_task_ravg()` 对**任何任务**都会被调用。
   而厂商自己在别处是**按 sched_class 保护**这个访问器的：
   `_audit/vendor-src/kernel-hdr/hmbird.h:335`：
   ```c
   return (p->sched_class == &hmbird_sched_class) ? get_hmbird_ts(p)->sts.demand_scaled : 0;
   ```
   → **同一个访问器，一处有 class 保护、热路径处没有。**
   若某个任务（内核线程、early-boot 任务、`non_hmbird_task` 集合里的任务）
   没有 hmbird 的 per-task 实体，`get_hmbird_ts(p)` 返回的就是 NULL 或野指针，
   `update_task_demand()/update_history()` 会**往任意地址写** →
   **静默硬挂、无 panic、无转储**，与你的现象完全吻合。

---

## 4. `procs_running` 暴增到几十意味着什么

### 4.1 语义

- `/proc/stat` 的 `procs_running` = `nr_running()` = `Σ_cpu cpu_rq(cpu)->nr_running`。
  参考：<https://man7.org/linux/man-pages/man5/proc_stat.5.html>、
  <https://support.checkpoint.com/results/sk/sk65143>
- `rq->nr_running` 由各调度类在 enqueue/dequeue 里通过 `add_nr_running()` / `sub_nr_running()` 维护。
  sched_ext 也不例外（上游 `kernel/sched/ext.c`：
  <https://github.com/torvalds/linux/blob/master/kernel/sched/ext.c>）。

### 4.2 你这份移植里存在**天然不对称**

`_lab/2026-10-08/scx-step4g/scx-branch/kernel/sched/ext.c`：

```c
1731: static void enqueue_task_scx(struct rq *rq, struct task_struct *p, int enq_flags)
1749:     if (test_bit(ffs(SCX_TASK_QUEUED), (unsigned long*)&p->scx->flags)) {
1750:             WARN_ON_ONCE(!watchdog_task_watched(p));
1751:             return;                       /* ← 已置位就返回，不再 add_nr_running（对称的） */
1752:     }
1755:     set_bit(ffs(SCX_TASK_QUEUED), (unsigned long*)&p->scx->flags);
1756:     rq->scx->nr_running++;
1757:     add_nr_running(rq, 1);                /* ← 只在"首次入队"时 +1 */
1758:     do_enqueue_task(rq, p, enq_flags, sticky_cpu);

1806: static void dequeue_task_scx(struct rq *rq, struct task_struct *p, int deq_flags)
1810:     if (!test_bit(ffs(SCX_TASK_QUEUED), (unsigned long*)&p->scx->flags)) {
1811:             WARN_ON_ONCE(watchdog_task_watched(p));
1812:             return;                       /* ← 未置位就返回，不再 sub_nr_running */
1813:     }
1815:     ops_dequeue(p, deq_flags);
1817:     if (task_current(rq, p))
1818:             trace_android_vh_hmbird_update_load(p, rq, PUT_PREV_TASK, rq->clock);
1825:     clear_bit(ffs(SCX_TASK_QUEUED), (unsigned long*)&p->scx->flags);
1826:     WARN_ON(!scx_rq->nr_running);
1827:     scx_rq->nr_running--;
1828:     sub_nr_running(rq, 1);                /* ← 只在"确实置位"时 -1 */
1829:     dispatch_dequeue(scx_rq, p);
```

**逻辑本身是对称的——但完全依赖 `SCX_TASK_QUEUED` 这一个 bit 的一致性。**
只要有任何一条路径**在这个 bit 之外**改变了任务状态，就会出现
「enqueue 加了 1、dequeue 提前 return 没减 1」→ **`rq->nr_running` 永久泄漏**。

而 §2.4 已经说明：厂商 WALT LB 的 `_walt_can_migrate_task()` **既不校验
`task_on_rq_queued()` 也不校验 `sched_class`**，detach 与 attach 之间还放开了锁。
这两个事实叠加，就是一条现成的泄漏/双计数路径。

### 4.3 为什么会「暴增到 48 然后挂死」（正反馈）

`rq->nr_running` 同时是**负载均衡的输入**。厂商 WALT 的
`walt_lb_find_busiest_cpu()` / `similar_cap_skip_cpu()` / `find_first_idle_if_others_are_busy()`
都直接读 `cpu_rq(i)->nr_running`（`walt_lb.c`）：

```c
if (cpu_util(i) < SMALL_TASK_THRESHOLD && cpu_rq(i)->nr_running == 1) { ... }
if (rq->nr_running < 2) return true;
```

于是形成闭环：

```
nr_running 虚高 → 该 rq 被判为"最忙" → 被反复 pull
   → 每次 pull 的 detach/attach 又有机会多计一次 → nr_running 更高
   → …… → 48 → 负载均衡风暴 / 任务反复迁移
   → PSI 记账彻底错乱（那条告警）→ 最终死锁/硬挂
```

**这与 sched_ext 上游已知的失败模式同类**：
`[PATCH v2 14/14] sched_ext: Implement load balancer for bypass mode`
<https://lists.openwall.net/linux-kernel/2025/11/10/1911>
> 「a failure mode where a BPF scheduler can skew task placement severely ...
>  those CPUs can accumulate queues that are too long to drain in a reasonable time,
>  **leading to RCU stalls and hung tasks**」

即：**任务分布被搞歪 → 队列排不空 → RCU stall / hung task**，正是「procs_running 暴增后挂死」的形态。

### 4.4 sched_ext 移植里 `nr_running` 异常的其他已知成因（供交叉排查）

| 成因 | 说明 |
|---|---|
| **重复入队 / 漏出队** | 本报告主线；`activate_task()` 无 on_rq 保护 + LB 双 attach |
| **SCX_TASK_QUEUED 与 on_rq 失配** | 上述 early-return 不对称；bypass/enable-fail/disable 过渡期最容易 |
| **bypass 模式集中排队** | 上游为此专门加了 bypass LB 补丁（见上）；老内核没有 |
| **DSQ 反复重派** | `dispatch_enqueue/dispatch_dequeue` 与 `dispatch_to_local_dsq` 之间锁序/重试 |
| **IPI/kick 风暴** | `scx_bpf_kick_cpu` 无节制；上游为此把 hardlockup 检测挂进 sched_ext |
| **kthread 不停唤醒** | hmbird 有 `hmbird_shadow_tick`（`hmbird_shadow_tick.c`）与 `highres_tick_ctrl`，需确认 shadow tick 不会自我续期成风暴 |
| **自旋重入** | `slim_walt_irq_work` 持全 rq 锁 + 其它路径持锁重入 |

---

## 5. 「无 panic 的静默硬挂」对应哪几类缺陷 & 受限内核怎么定位

### 5.1 对应哪几类缺陷（sched_ext/调度器语境）

1. **全 CPU 关中断自旋死锁**：一个 CPU 在关中断下持锁自旋等另一个永远拿不到锁的 CPU。
   上游为此专门给 sched_ext 接 hardlockup 检测：
   `[PATCH UPDATED 10/14] sched_ext: Hook up hardlockup detector`
   <https://lists.openwall.net/linux-kernel/2025/11/11/1638>（另见
   <https://lkml.iu.edu/hypermail/linux/kernel/2511.1/02809.html>）
   > 「A poorly behaving BPF scheduler can trigger hard lockup. For example ... if the BPF scheduler
   > puts all tasks in a single DSQ and lets all CPUs at it, **the DSQ lock can be contended to the
   > point where hardlockup triggers**」
2. **持全部 rq 锁做跨 CPU 同步**（你的 `slim_walt_irq_work` 就是这一类），与
   `double_lock_balance` 的「busiest→this_rq」顺序互逆 → AB-BA。
3. **NMI 上下文里取不可 NMI 安全的锁**：上游有
   `sched_ext: Defer scx_hardlockup() out of NMI`（`scx_sched_lock` 非 NMI 安全）
   <https://yhbt.net/lore/lkml/aevsXVY6tmmimonU@gpd4/T/>
4. **workqueue 死锁 / 错误退出路径本身卡死**：scx issue #3687 里
   `scx_dump_state()` 在 hard-IRQ 上下文做 O(CPUs×tasks) 转储，直接造成 25s soft lockup，
   并留下 `note: rcu_preempt exited with irqs disabled`：
   <https://github.com/sched-ext/scx/issues/3687>
5. **内存踩踏**（本报告 §3.4 第 6 点）：往野指针写 → 立即挂死，**完全不会经过 panic 路径**。
   这是「无 panic、无转储、硬件看门狗无声复位」最经典的一类。
6. **watchdog 自身失效**：hardlockup 检测依赖 NMI；如果被关中断自旋的 CPU 恰好不响应
   NMI（或 `nmi_watchdog` 未开 / `watchdog_thresh` 太宽），就是「无声复位」。
   sched_ext 的 watchdog 语义见 <https://docs.kernel.org/scheduler/sched-ext.html>
   （stalled runnable task → abort 并回退 fair），以及 scx #1202 关于 RT 任务的盲区：
   <https://github.com/sched-ext/scx/issues/1202>

### 5.2 没有 ftrace / kprobe / lockdep 时能用的手段

> 你的环境：`available_tracers=[nop]`、无 lockdep、无 kprobe。
> 那么**第一优先级不是"观测"，而是"把静默挂变成有转储的 panic"**。

**(A) 把静默挂变成可分析的 panic（最高性价比）**

- 内核 cmdline / sysctl：
  - `kernel.hardlockup_panic=1`（对应 `CONFIG_BOOTPARAM_HARDLOCKUP_PANIC`）
  - `kernel.softlockup_panic=1`
  - `kernel.hung_task_panic=1`、`kernel.hung_task_timeout_secs=10`
  - `nmi_watchdog=1`、`watchdog_thresh=10`
- 你当前把 `hung_task_panic=0` 是**为了不打扰**，但在定位阶段应临时打开。
- 一旦有 panic，`ramoops/pstore` 才能抓到：
  `/sys/fs/pstore/console-ramoops-0`、`dmesg-ramoops-*`（Android 上即 last_kmsg）。
  需确认内核开了 `CONFIG_PSTORE` + `CONFIG_PSTORE_RAM` 且 DT 有 `ramoops` 节点。
- hmbird 自己**自带 minidump 设施**（你树里有
  `_lab/2026-10-09/vendor-iface/src/hmbird_ogki__scx_minidump.h` /
  `hmbird_ogki__scx_minidump.c`），把它接上比自造打点更省事。

**(B) 无 tracer 时的软件打点**

- `pr_info()`/`printk_deferred()` 打点 + **环形缓冲区 + 只在异常时 dump**：
  在 `hmbird_update_task_ravg()` 入口记 `(cpu, pid, comm, sched_class, psi_flags, on_rq, nr_running)`，
  在检测到 `nr_running > 阈值` 或 `psi_flags` 异常时把环形缓冲一次性打出来。
  注意**不要在调度热路径里同步刷串口/console**（会自己造成卡顿甚至死锁）。
- 用 `printk_deferred` 而不是 `printk`（调度器上下文里 `printk` 有锁风险；
  PSI 自己用的就是 `printk_deferred`）。
- **采集 PSI 那一行全文**：`psi_bug` 是一次性的，所以必须靠一个常驻的
  `cat /dev/kmsg` 或 pstore 把首次出现抓下来；`clear/set` 的数值直接判定
  「双入队」还是「双出队」，这是**零成本、零风险**的黄金证据。

**(C) 用现成的 /proc 与 sysfs 做无侵入观测**

- `/proc/stat` 的 `procs_running`（你已在用）——建议同时抓 `procs_blocked` 与 `ctxt`；
  `ctxt` 的斜率能区分「任务真的变多」还是「计数被虚增」。
- `/proc/sched_debug`（若开 `CONFIG_SCHED_DEBUG`）：可看到每个 rq 的
  `nr_running`、`cfs.h_nr_running`、`scx.nr_running`，**三者不一致本身就是证据**。
  你移植版 `ext.c:2532-2534` 正好有打印 `rq->scx->nr_running` 与 `sum += cpu_rq(i)->nr_running` 的调试代码。
- `/proc/<pid>/stack`、`/proc/<pid>/stat`、`/sys/kernel/sched_ext/state`
  （见 <https://wiki.androidperformance.com/part4-system/ch19-oem/03-oem-scheduling-game-input.html>
  关于 `/sys/kernel/sched_ext/state` 与 `CONFIG_SCHED_CLASS_EXT` 的说明）。
- **SysRq**（Android 需先 `echo 1 > /proc/sys/kernel/sysrq`）：
  `SysRq-D` 显示锁/被阻塞任务（有 lockdep 才有完整信息，无 lockdep 也有参考值）、
  `SysRq-T` 全任务栈、`SysRq-W` 阻塞任务栈、`SysRq-L` 各 CPU 回溯（需 arch NMI）、
  `SysRq-M` 内存。**用 SysRq 做「开启 hmbird 后 N 秒自动 dump」比等着它挂更可控。**

**(D) 二分（最有效，你已经开始了）**

你 `报告-20261011` 里的 A/B/C/D 四步是对的，建议顺序微调：

1. `slim_walt_ctrl=1`，但 **`get_hmbird_ts(p)` 只对 `p->sched_class == &hmbird_sched_class` 生效**
   （其余任务直接 return）→ 直接验证 §3.4 第 6 点。
2. `slim_walt_ctrl=1`，`get_cpus_max_util()` 返回常量（切断 rescue 触发）→ 区分 tracking vs rescue。
3. `set_partial_rescue()`/`free_isocpu()` 改成只打印 → rescue 路径。
4. `slim_walt_ctrl=0` 但保留掩码修正 → 验证掩码修正本身。
5. **额外补一步**：在 `walt_detach_task()/walt_attach_task()` 前后加
   `WARN_ON_ONCE(task_on_rq_queued(p))` 与 `WARN_ON_ONCE(p->on_rq == TASK_ON_RQ_MIGRATING)`，
   并在 `_walt_can_migrate_task()` 开头加
   `if (!task_on_rq_queued(p) || p->sched_class != &fair_sched_class) return false;`
   → 直接验证 §2.4 的双入队假说。
6. **再补一步**：在 `add_nr_running/sub_nr_running` 附近（或 scx 的
   `rq->scx->nr_running` 增减处）打点，记录 `cpu/pid/comm/前后 nr_running`，
   开启 hmbird 后看谁在净 +1 而不 -1。

**(E) 缩小战场**

- `maxcpus=1` 或 `nr_cpus=2` 启动：若单核下不挂、双核下挂 → 锁定跨 CPU 同步/锁序问题。
- 临时关闭 WALT LB（若厂商暴露了 sysctl）或在 `walt_newidle_balance()` 开头直接 return：
  若不再挂 → 锁定 WALT LB 路径（与 `psi` 告警的调用栈一致）。
- 临时禁用 hmbird 的 shadow tick（`hmbird_shadow_tick.c`）观察 `ctxt` 斜率变化。

---

## 6. 最可能的三条根因 + 各自如何验证

### 根因 1（最可能）★ `hmbird_update_task_ravg()` 对非 hmbird 任务解引用 `get_hmbird_ts(p)`

**依据**
- `hmbird_util_track.c:466`：`get_hmbird_ts(p)` 在 `if (!slim_walt_ctrl)` **之前**求值；
  函数对**任何**任务都会跑（4 条热路径对所有任务生效）。
- 厂商自己在 `_audit/vendor-src/kernel-hdr/hmbird.h:335` **是按 class 保护的**：
  `(p->sched_class == &hmbird_sched_class) ? get_hmbird_ts(p)->sts.demand_scaled : 0`
  → 说明「非 hmbird 任务没有有效的 hmbird 实体」是厂商自己的前提。
- 症状完全吻合：**往野指针写 → 立即硬挂、无 panic、无转储、硬件看门狗无声复位**，
  且「关掉 `slim_walt_ctrl` 就稳定」（因为整条路径被关掉了）。

**验证（改动最小、最先做）**
1. 在 4 个热路径调用点（task_tick / set_next / put_prev / dequeue）外层加
   `if (p->sched_class == &hmbird_sched_class)` 再调用；
   或把该判断挪进 `hmbird_update_task_ravg()` 第一行。
2. 更保险：把 `hmbird_update_task_ravg` 改成
   `if (!slim_walt_ctrl || !p || p->sched_class != &hmbird_sched_class) return;`
   且**把 `get_hmbird_ts(p)` 挪到判断之后**（顺带修掉「先解引用后判开关」）。
3. 判据：`slim_walt_ctrl=1` + 满载 10 分钟不挂，且 `procs_running` 稳定在 1~4。
4. 反向确认：在 `get_hmbird_ts()` 里加 `WARN_ON_ONCE(!hmbird_entity_valid(p))`
   （或打印 `p->sched_class / comm / pid`），看是否在挂死前刷出非 hmbird 任务。

### 根因 2（很可能）★ `rq->nr_running` 泄漏/双计数 → 负载均衡正反馈 → 挂死

**依据**
- `ext.c:1749-1757` / `1810-1828`：`add_nr_running` 与 `sub_nr_running` 完全依赖
  `SCX_TASK_QUEUED` 一个 bit，**early-return 时不做减法**；bit 一旦与 `on_rq` 失配就永久泄漏。
- `walt_lb.c` 的 `_walt_can_migrate_task()` **没有 `task_on_rq_queued()`、没有 `sched_class` 判断**；
  `walt_detach_task()`/`walt_attach_task()` 在放锁窗口两端分别
  `deactivate_task(p,0)` + `activate_task(p,0)`；core 的 `activate_task()` **无 on_rq 保护**。
- 现象吻合：`procs_running` 由 1~3 **暴增到 48**（计数虚高，不是真的 48 个任务）；
  PSI 那条 `psi_flags=4 clear=0 set=4`（**双入队**）正好是这条路径的指纹。
- 上游同类失败模式的定性（「skew → 队列排不空 → RCU stall / hung task」）见
  <https://lists.openwall.net/linux-kernel/2025/11/10/1911>。

**验证**
1. 在 `_walt_can_migrate_task()` 开头加：
   `if (!task_on_rq_queued(p) || p->sched_class != &fair_sched_class) return false;`
   → 若不再挂，即坐实。
2. 在 `dequeue_task_scx` 的 early-return 分支里加
   `if (rq->nr_running > 0) pr_info(...)` 并记录，看是否有任务在 `SCX_TASK_QUEUED` 已清时被 dequeue。
3. 打点记录 `add_nr_running/sub_nr_running`（或 `rq->scx->nr_running`）的净变化，
   开启 hmbird 后确认 `Σ rq->nr_running` 单调上升。
4. 交叉证据：把 PSI 那一行完整抓下来，`set=4` ⇒ 双入队（本假说）；`clear=4 set=0` ⇒ 双出队。

### 根因 3（已被部分排除，但同类缺陷必须再审计）★ 持全部 rq 锁 / 跨 CPU 加锁顺序

**依据**
- `hmbird_util_track.c:494 slim_walt_irq_work()` 在 **hard-IRQ 上下文按 CPU 升序一次性持全部 rq 锁**，
  与 `double_lock_balance`（先 busiest 再 this_rq）的加锁顺序不构成全序 → **AB-BA 可能**。
- 上游明确承认「全 CPU 抢同一把锁可以抢到 hardlockup」：
  <https://lists.openwall.net/linux-kernel/2025/11/11/1638>
- **但你的 opt141 已经不再排队这个 irq_work，却仍然「开启后立刻硬挂」**
  → 说明**它不是当前这版的直接原因**，只能排第三。

**验证（确认它是真的被移除干净，而不是换个地方还在）**
1. 全树 grep：`irq_work_queue` / `slim_walt_window_rollover_run_once` /
   `hmbird_slim_walt_irq_work`，确认没有任何残留排队点（包括间接调用）。
2. 确认 `slim_walt_enable(1)` → `hmbird_sched_stats_init()` 这条「逐个 rq 加锁」路径
   不会与任何持多把 rq 锁的路径交叉（它一次只持一把，风险较低，但要确认没有嵌套）。
3. 确认 `hmbird_sched_stats_init()` 与 `slim_walt_enable(false)` 之间没有
   「窗口状态半新半旧」的竞态（`slim_walt_enable(false)` 只置 `slim_walt_ctrl=0`，
   不重置 `tick_sched_clock` / 各 rq 的 `window_start`）。
4. 复现判据：`maxcpus=1` 或 `nr_cpus=2` 下若不挂、多核下挂 → 支持跨 CPU 锁序/同步类缺陷。

---

## 附：建议立刻做的三件事（按顺序）

1. **先抓 PSI 那一行的完整数值**（`clear=`/`set=`），它零成本地决定根因 2 的方向。
2. **打开 `hardlockup_panic=1` / `softlockup_panic=1` / `hung_task_panic=1` + pstore**，
   让下一次挂死留下转储而不是静默复位。
3. **按根因 1 的改法（加 `sched_class` 保护 + 把 `get_hmbird_ts` 挪到开关判断之后）做一次实验**，
   这是改动最小、最可能一击命中的。

---

### 引用清单（全部 URL）

- PSI 源码/头/核心：<https://github.com/torvalds/linux/blob/v6.1/kernel/sched/psi.c> ·
  <https://github.com/torvalds/linux/blob/v6.1/include/linux/psi_types.h> ·
  <https://github.com/torvalds/linux/blob/v6.1/kernel/sched/stats.h> ·
  <https://github.com/torvalds/linux/blob/v6.1/kernel/sched/core.c>
- PSI 迁移 bug 与修复：<https://lkml.iu.edu/2410.1/05468.html> ·
  <https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2410.1/08909.html> ·
  <https://lkml.iu.edu/2409.2/05906.html> · <https://bbs.archlinux.org/viewtopic.php?id=301794>
- sched_ext 上游：<https://github.com/torvalds/linux/blob/master/kernel/sched/ext.c> ·
  <https://docs.kernel.org/scheduler/sched-ext.html> ·
  <https://lore-kernel.gnuweeb.org/lkml/20260204160710.1475802-1-arighi@nvidia.com/>
- fair.c：<https://github.com/torvalds/linux/blob/v6.1/kernel/sched/fair.c>
- 厂商 WALT LB：<https://github.com/realme-kernel-opensource/realme_GT7pro-AndroidB-kernel-source/blob/c541ad76/kernel/sched/walt/walt_lb.c>
- hmbird/WALT ABI 与 `prev_runnable_sum_fixed`：
  <https://github.com/OnePlusOSS/android_kernel_oneplus_sm8750/issues/21>
- hmbird 架构与移植难度：<https://github.com/LunarKernel-Dev/lunarkernel_sched_extention> ·
  <https://github.com/reigadegr/hmbird_controller> ·
  <https://github.com/reigadegr/hmbird_controller/issues/1> ·
  <https://github.com/cctv18/oppo_oplus_realme_sm8750> ·
  <https://github.com/Numbersf/SCHED_PATCH/issues/2> ·
  <https://github.com/Numbersf/Action-Build/issues/279> ·
  <https://github.com/WildKernels/OnePlus_KernelSU_SUSFS>
- sched_ext 卡死/锁类：<https://github.com/sched-ext/scx/issues/3687> ·
  <https://github.com/sched-ext/scx/issues/1202> ·
  <https://github.com/sched-ext/scx/issues/3180> ·
  <https://discuss.cachyos.org/t/sched-ext-crashing-lately/17705> ·
  <https://lists.openwall.net/linux-kernel/2025/11/11/1638> ·
  <https://lkml.iu.edu/hypermail/linux/kernel/2511.1/02809.html> ·
  <https://yhbt.net/lore/lkml/aevsXVY6tmmimonU@gpd4/T/> ·
  <https://lists.openwall.net/linux-kernel/2025/11/10/1911> ·
  <https://patchew.org/linux/20251119103722.309211-1-skb99@linux.ibm.com/>
- /proc/stat 语义：<https://man7.org/linux/man-pages/man5/proc_stat.5.html> ·
  <https://support.checkpoint.com/results/sk/sk65143>
- Android sched_ext 观测：<https://wiki.androidperformance.com/part4-system/ch19-oem/03-oem-scheduling-game-input.html>

### 本地证据文件（本工作区）

- `_audit/报告-20261011-夜间-hmbird放置修复.md`（opt139→opt141，三次硬挂实测）
- `_audit/报告-hmbird放置根因.md`
- `_audit/vendor-src/kernel-hmbird/hmbird_util_track.c`（466/494/594 行）
- `_audit/vendor-src/kernel-hmbird/hmbird_sched_proc.c`（232/592 行）
- `_audit/vendor-src/kernel-hmbird/hmbird.c`（843/3704 行）
- `_audit/vendor-src/kernel-hdr/hmbird.h`（335 行：按 class 保护 `get_hmbird_ts`）
- `_lab/2026-10-08/scx-step4g/scx-branch/kernel/sched/ext.c`（1731-1830 行）
