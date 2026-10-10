# 分析：slim_walt_ctrl=1 之后「hmbird 一开 running 就暴增到 48 并硬挂」

- 任务：t1 [T1] 根因分析（只读源码/文档，不碰设备）
- 作者：analyst · 时间：2026-10-11 02:42
- 输入：报告-20261011-夜间-hmbird放置修复.md、t139/t140/t141 日志、t139.sh/t141.sh、
  WSL 源码 /home/builder/kwork/wt-core/kernel/sched/hmbird/、vendor-src/kernel-hmbird、
  vendor-src/kernel-walt、core.c/fair.c/rt.c、研究-启用即硬挂-根因假说.md（captain 转述）
- 方法：静态阅读 + vendor↔ours 逐字 diff + git show opt139/140/141（**无设备、无 ftrace、无 lockdep**）

---

## 0. 结论（TL;DR）

25 分钟预算内**无法给出唯一根因**（本机没有 ftrace/kprobe/lockdep，单次样本也区分不了通过/偶发）。
但把范围收敛到**两条互斥候选**，并给出**一次开机即可判定**的最小实验：

| | 候选 | 一句话 | 判据（最小实验） |
|---|---|---|---|
| **C1 ★最可能★** | **WALT 的 tick 路径负载均衡在 hmbird 启用期间【没有被绕过】** | 与 opt121/122/123 已修的那条根因**同源**，但走的是**另一个没被守卫的钩子**（android_vh_scheduler_tick）。slim_walt_ctrl=1 只是**触发器**：它让 rescue 真正生效，第一次出现 hmbird 自造的跨簇不均衡，于是 WALT 的 tick LB 有活干 | opt142-A：按 Stage BO/BQ 同款条件绕开 core.c:5848 的 tick 钩子 ⇒ 不挂则 C1 成立 |
| **C2 ★很可能★** | **partial 簇 DSQ 的消费者被 partial_enable 整段开关** | gen_cluster_ctx(PARTIAL) 在 partial_enable==0 时返回 −1 ⇒ 那一拍 partial 簇的 DSQ **一个消费者都没有** ⇒ 已入队任务滞留 ⇒ add_nr_running(+1) 永不配平 ⇒ procs_running 单调虚增到 48 | opt143：partial_dynamic_ctrl() 只读不动作 ⇒ 稳定则缺陷在 rescue 动作侧 |

**对 captain 转述的两个「根因」的裁决：**

1. 「hmbird_update_task_ravg 先解引用 get_hmbird_ts(p)」——**代码事实成立，但作为本次挂死的解释我给反证，降级为「未排除但概率低」**。
   那 4 条热路径**只可能拿到 hmbird 类任务**（它们是 sched_class 回调，p 由 core 按 p->sched_class 派发），
   而 task_on_hmbird()（hmbird.c:4032-4035）**要求实体非空且非 idle** 才允许进 hmbird 类 ⇒ 热路径上不可能 NULL。
   唯一能拿到非 hmbird 任务的是 slim_walt_irq_work()（util_track.c:542 用 rq->curr），**opt141 已删掉**。
   ⇒ 它**不是** opt141 挂死的解释；但仍是真实的潜在缺陷（厂商自己也没加 class 保护，对照 hmbird.h:310-313），值得零成本加固+打点（§4 P1）。
2. 「rq->nr_running 泄漏/双计数 ⇒ 负载均衡正反馈」——**方向正确，我给出了它的具体制造者 = C2**。
   add_nr_running() 只在 enqueue_task_hmbird()（hmbird.c:2372）里加，只在 dequeue_task_hmbird()（hmbird.c:2449）里减，
   而 dequeue 靠一个 QUEUED 位 gate、early-return **不做减法**。只要「任务进了 DSQ 但没有消费者」，计数就永久虚增。
   **而「没有消费者」这件事，正是 C2 证明会发生的事**（不只是 WALT 的锅）。

---

## 1. 已排除（附证据）

| # | 已排除 | 证据 |
|---|---|---|
| E1 | slim_walt_irq_work（全 rq 锁风暴 / cpufreq AB-BA） | opt141 已完全不排队它，仍挂；opt140 带着它跑过 45s 满载（t140.log） |
| E2 | 4 条热路径的调用点/守卫写错了 | vendor(vendor-src/kernel-hmbird/hmbird.c) ↔ ours 逐点比对：dequeue 2186↔2435、set_next 2598↔2891、put_prev 2629↔2922、task_tick 3117↔3472，**守卫逐字节一致** |
| E3 | hmbird_util_track.c 被我们改坏 | git diff --no-index vendor↔ours ⇒ **只有 opt139/140/141 三处补丁**（47 insertions / 8 deletions），其余逐字节相同 |
| E4 | 掩码有空洞 ⇒ 选出非法 CPU | little{0,1}/big{2,3,4}/partial{5,6}/exclusive{7}/ex_free{7} 覆盖 0-7 无空洞；select_cpu_from_cluster()（hmbird.c:3136-3138）已用 cpumask_and(&allowed, mask, p->cpus_ptr) + 空集返回 −1 |
| E5 | idle/RT 任务没有实体 ⇒ 热路径 NULL 解引用 | hmbird_pre_fork() 在 copy_process() 里**无条件**调用（core.c:4869-4871）⇒ fork_idle() 出来的 swapper/N 都有 kzalloc 实体；task_on_hmbird() 还要求 get_hmbird_ts(p)!=NULL 才准进 hmbird 类 |
| E6 | 除零会陷入（panic） | arm64 的 UDIV 除零**返回 0、不产生异常** ⇒ slim_walt_cpu_util() 的 prev_window_size>>10（无判零）、scale_time_to_util() 的 >>10、DIV64_U64_ROUNDUP(...,get_max_freq(cpu)) 都只会算错，不会崩 |
| E7 | 挂死是 scx 框架/调速器的锅 | 已由 t139/t140/t141 的 scx=1 跑 101s/120s 零异常排除 |

---

## 2. 候选缺陷清单（按可能性排序）

### C1 ★最可能★ WALT 的 tick 路径 LB 在 hmbird 启用期间未被绕过

代码链：

1) kernel/sched/core.c:5848 —— tick 钩子，**没有任何守卫**：

    scx_notify_sched_tick();
    #ifdef CONFIG_HMBIRD_SCHED_CORE
    	hmbird_notify_sched_tick();
    #endif
    	perf_event_task_tick();
    ...
    	trace_android_vh_scheduler_tick(rq);        <-- 5848：WALT 的 tick LB 在这里
    #ifdef CONFIG_HMBIRD_SCHED_CORE
    	scheduler_tick_handler(NULL, NULL);
    #endif

2) vendor-src/kernel-walt/walt.c:5274 在该钩子里调用 walt_lb_tick(rq)
   （注册点 walt.c:5562 register_trace_android_vh_scheduler_tick(android_vh_scheduler_tick, NULL)）。

3) vendor-src/kernel-walt/walt_lb.c:704-719 —— 唯一的「hmbird 让路点」：

    void walt_lb_tick(struct rq *rq)
    {
    ...
    #ifdef CONFIG_HMBIRD_SCHED
    	if (HMBIRD_GKI_VERSION == get_hmbird_version_type()) {
    		if (SCX_CALL_OP_RET(lb_tick_bypass, rq))
    			return;
    	}
    #endif

   本机 get_hmbird_version_type() == UNKNOWN（已确认事实 2）⇒ **这个让路点恒不成立**
   ⇒ **WALT 的 tick 迁移在整个 hmbird 启用期间照跑**。

4) 我们只守住了 newidle 这一条入口（Stage BO/BQ，fair.c:11852-11898）：

    if (!atomic_read(&__hmbird_ops_enabled) &&
    	!smp_load_acquire(&hmbird_transitioning))
    	trace_android_rvh_sched_newidle_balance(this_rq, rf, &pulled_task, &done);

   **同样需要守卫但【没有】守卫的三个点**（我逐个 grep 过）：
   - core.c:5848  trace_android_vh_scheduler_tick(rq)                  <- WALT 的 walt_lb_tick（真正会迁移任务的那个）
   - fair.c:11441 trace_android_rvh_sched_nohz_balancer_kick(rq,...)   <- vendor walt_lb.c:1154-1174
   - rt.c:1808   trace_android_rvh_sched_balance_rt(rq, p, &done)

为什么会造成 running 暴增 / 挂死：

- WALT 用 **prio** 判「是不是 fair 任务」（vendor walt.h:1243-1246），而 hmbird 类任务 prio 同样落在 [100,139]
  ⇒ hmbird 任务被 WALT 当成 fair 任务；walt_lb_pull_tasks（vendor walt_lb.c:320-368）
  **既没有 sched_class 判断、也没有 task_on_rq_queued()、也没有 QUEUED 判断**（fair.c:11866-11871 注释已写明）。
- 一旦它对一个 hmbird 类任务做 deactivate_task / set_task_cpu，hmbird 侧的 DSQ 链接
  （get_hmbird_ts(p)->dsq / dsq_node）、get_hmbird_rq(rq)->nr_running 与 rq->nr_running
  （hmbird.c:2371-2372 / 2447-2449）就**被从外面撕开** ⇒ 任务既不在 rq 也不在可消费的 DSQ
  ⇒ sub_nr_running() 永不发生 ⇒ procs_running 单调虚增（1~3 → 48）⇒ pick_next_task/balance_hmbird 空转 ⇒ 硬挂。
- 与 opt120 死亡现场**同一条链**（LAST_KMSG_opt120：walt_lb_pull_tasks ← walt_newidle_balance ← newidle_balance）。

为什么现在才炸（新变量如何触发它）：

- opt139 之前：util 恒 0 ⇒ l_over/b_over 恒假 ⇒ set_partial_rescue()/free_isocpu() 从未被调用
  ⇒ 任务全落 little/big，**hmbird 的放置与 WALT 的均衡观基本一致**（没有可拉的活）。
- opt139 之后：p_en=1 iso_free=1（t140.log）⇒ 任务**第一次**被 hmbird 主动放到 partial{5,6} 与 exclusive{7}
  ⇒ **出现 hmbird 自造的跨簇不均衡** ⇒ WALT 的 tick LB 第一次有活干 ⇒ C1 被激活。
- ⇒ **回答 captain：这是同一条架构级根因的【变体】，不是全新缺陷。已修的是 newidle 入口；未修的是 tick 入口（+nohz_kick/+balance_rt）。**

### C2 ★很可能★ partial 簇 DSQ 的消费者被 partial_enable 整段开关

制造者：hmbird.c:965-1007 partial_dynamic_ctrl()，从**唤醒路径** hmbird_select_cpu_dfl()（hmbird.c:3182）调用，
限频 1 jiffy（hmbird.c:973-976，**250Hz**）：

    lmax = get_cpus_max_util(iso_masks.little);
    l_over = lmax > parctrl_high_ratio_l;
    ...
    if (is_partial_enabled() && (l_over || b_over)) { ... set_partial_rescue(true, l_over, b_over); }
    else if (!is_partial_enabled() && (l_over || b_over)) { set_partial_rescue(true, l_over, b_over); }
    else if (is_partial_enabled() && l_under && b_under) { set_partial_rescue(false, false, false); }
    ...
    if (is_partial_enabled()) { bmax = get_cpus_max_util(iso_masks.partial);
    	if (!is_iso_par_free() && bmax > isoctrl_high_ratio) free_isocpu(true);
    	else if (is_iso_par_free() && bmax < isoctrl_low_ratio) free_isocpu(false);
    } else if (is_iso_par_free()) free_isocpu(false);

执行者：hmbird.c:1212-1230（separate 版 1178-1184 同理）：

    static int gen_cluster_ctx_common(struct cluster_ctx *ctx, enum cpu_type type)
    {
    	switch (type) {
    	case PARTIAL:
    		if (!is_partial_enabled())
    			return -1;                 <-- 调用方直接 return 0 =「这个簇没活干」
    		fallthrough;
    	case BIG:
    	case LITTLE:
    		ctx->lower = NON_PERIOD_START; ctx->upper = NON_PERIOD_END; ctx->tidx = 0;
    		break;

所有消费者都这样起手：consume_timeout_dsq()(1241-1249)、consume_non_period_dsq()(1277-1284)、
consume_period_dsq()、update_dsq_idx()(1485-1492) ⇒ gen_cluster_ctx() 返回 −1 时**整段跳过该簇的 DSQ**。

为什么会造成 running 暴增：

- 入队：get_hmbird_rq(rq)->nr_running++; add_nr_running(rq, 1);   （hmbird.c:2371-2372）
- 出队：hmbird_rq->nr_running--; sub_nr_running(rq, 1);          （hmbird.c:2448-2449，只在该任务被正常 dequeue 时发生）
- partial_enable 一旦在 250Hz 尺度上翻转，翻转的那一拍**没有任何 CPU 会去消费 partial 簇的 DSQ**
  ⇒ 此刻在该簇 DSQ 里的任务滞留 ⇒ **计数永久虚增** ⇒ /proc/stat 的 procs_running 从 1~3 涨到 48。
- 同时 skip_update_idle()（hmbird.c:656-667）随 partial_enable/isolate_ctrl 改变行为
  ⇒ idle_masks.cpu（update_cpus_idle()，hmbird.c:604-617，**从唤醒路径无锁调用**）与
  hmbird_pick_idle_cpu()（hmbird.c:3033-3044）的选核结果跟着抖 ⇒ 任务被放到马上要退出掩码的核上 ⇒ 迁移风暴。

★取证盲点（必须纠正）★
opt139 的诊断是 pr_info_ratelimited(...)（opt139 diff，hmbird.c:983 那 3 行），
**ratelimit 默认 5 秒 10 条**，而 partial_dynamic_ctrl 以 **250Hz** 被调用 ⇒ **约 1250 次里只印 10 次**。
⇒ t140.log 里「每次采样 p_en=1 iso_free=1」**不能**证明它不翻转。必须改成**原子计数器统计翻转次数**（§4 P3）。

为什么现在才炸：opt139 之前 l_over/b_over 恒假 ⇒ partial_enable 恒 0 ⇒ **没有任何任务会被放进 partial 簇**
（这正是 opt138 的症状 91 91 32 51 0 0 0 0：CPU5/6 空转）。opt139 让 util 变真 ⇒ partial_enable/isolate_ctrl
第一次开始翻转 ⇒ 这条路径第一次可达。

### C3 未排除但概率低：非 hmbird 任务被喂给 hmbird_update_task_ravg()（研究子代理的「根因1」）

代码事实（成立）—— hmbird_util_track.c:486-496：

    void hmbird_update_task_ravg(struct task_struct *p, struct rq *rq, int event, u64 wallclock)
    {
    	struct hmbird_sched_task_stats *sts = &(get_hmbird_ts(p)->sts);   /* 489：先取地址 */
    	struct hmbird_sched_rq_stats *srq = &per_cpu(hmbird_sched_rq_stats, cpu_of(rq));
    	if (!slim_walt_ctrl)                                             /* 493：后判断 */
    		return;
    	if (!srq->window_start || sts->mark_start == wallclock)           /* 496：首次真解引用 */
    		return;

为什么我认为它不是本次挂死的解释（反证）：

1) 4 条热路径都是 hmbird_sched_class 的回调，core 按 p->sched_class 派发 ⇒ p **必然是 hmbird 类任务**：
   task_tick_hmbird(3473,curr) / set_next_task_hmbird(2893) / put_prev_task_hmbird(2924) / dequeue_task_hmbird(2437)。
2) 进 hmbird 类必须过 task_on_hmbird()（hmbird.c:4014-4036）：
   if (is_idle_task(p)) return false;  return hmbird_enabled() && get_hmbird_ts(p) != NULL;
   ⇒ **类内任务必有实体**，热路径上取不到 NULL。
3) 唯一会把**任意任务**（含 idle/RT）喂进去的是 slim_walt_irq_work()（util_track.c:540-543，用 rq->curr），
   而 **opt141 已删除排队**（opt141 diff：slim_walt_window_rollover_run_once 改成 (void)result;）。
4) 厂商自己也没在这个函数里加 class 保护（vendor↔ours 该文件逐字节相同）；厂商在别处用的是
   class 保护的写法 hmbird.h:310-313 hmbird_task_util()：
   (p->sched_class == &hmbird_sched_class) ? get_hmbird_ts(p)->sts.demand_scaled : 0
   ⇒ 「按 class 保护」确实是本项目的正确约定，值得照抄加固。

残留疑点（用 §4 P1 一次开机即可判定）：init_task（swapper/0）不经 copy_process，
android_oem_data1[HMBIRD_TS_IDX] 理论上是 0 ⇒ 在 opt139/opt140 的 irq_work 里
get_hmbird_ts(&init_task)->sts.mark_start 应立刻 fault；但 **opt140 活了 45 秒**（t140.log）。
⇒ 说明它实际非 NULL，或该 irq_work 并未真正执行。P1 打点一次开机就能给出答案。

### C4 窗口/窗口尺寸不变量被 opt141 打破（不崩，但让 util 语义漂移）

- sched_ravg_window_change()（util_track.c:658-665）唯一的**应用点**原本在 irq_work 内
  （util_track.c:545-551），**被 opt141 整段删掉** ⇒ new_hmbird_sched_ravg_window 永远不生效。
- 于是三个「窗口尺寸」可能分叉：全局 hmbird_sched_ravg_window（scale_time_to_util 用它、
  update_window_start 的步进用它）、srq->prev_window_size（slim_walt_cpu_util 的除数、
  update_cpu_busy_time 的 full_window 判定用它）、new_hmbird_sched_ravg_window。
- 若用户态把窗口设到 ≥1024 帧：hmbird_sched_ravg_window >> 10 == 0
  ⇒ scale_time_to_util() 除以 0（arm64 得 0）⇒ demand_scaled 恒 0 ⇒ 又回到「util 恒 0」的老症状。

### C5 二次 enable 后 mark_start 陈旧 ⇒ update_history() 的 nr_full_windows 循环（真·长循环）

- util_track.c:289-303 + 210-213：

    delta = window_start - mark_start;
    nr_full_windows = div64_u64(delta, window_size);
    ...
    if (nr_full_windows) {
    	u64 scaled_window = scale_exec_time(window_size, rq);
    	update_history(rq, p, scaled_window, nr_full_windows, event);  /* samples 次循环 */

  update_history() 里：for (; samples > 0; samples--) { hist[sts->cidx] = runtime; ... }
- slim_walt_enable(1)（util_track.c:626-640）只重置 **per-rq** 状态（hmbird_sched_init_rq，566-573），
  **不重置 per-task sts->mark_start**；而 hmbird_scheduler_tick()（util_track.c:602-624）
  在 enable 后把 window_start 重新基准到 rq->clock - 20000
  ⇒ **二次 enable 时 window_start - mark_start 可以等于一整段 disable 期的时长**
  （秒级 ⇒ nr_full_windows 10^5~10^6）⇒ **在 rq 锁内、调度热路径上跑 10^5~10^6 次循环**。
- 单次长时间睡眠的任务唤醒同理（mark_start = 入睡时刻）。
- 这条在 opt139 之前**不可达**（hmbird_update_task_ravg 直接 return）。

### C6 update_rq_clock() 重入（任务书点名项）

    void hmbird_update_task_ravg_rqclock_wrapper(struct task_struct *p, struct rq *rq, int event)
    {
    	if (!(rq->clock_update_flags & RQCF_UPDATED))
    		update_rq_clock(rq);                                      /* util_track.c:478-479 */
    	struct hmbird_sched_rq_stats *srq = &per_cpu(hmbird_sched_rq_stats, cpu_of(rq));
    	hmbird_update_task_ravg(p, rq, event, max(rq_clock(rq), srq->latest_clock));
    }

- core.c:778-798：RQCF_UPDATED **只在 CONFIG_SCHED_DEBUG 下**被置位（787-791），
  而 RQCF_ACT_SKIP 会让 update_rq_clock() 静默返回（784-785）。
  ⇒ 若 CONFIG_SCHED_DEBUG=n（GKI 常见），RQCF_UPDATED **恒 0** ⇒ 4 个热路径**每次都真的重跑 update_rq_clock()**。
- 4 个调用点都在 rq 锁内（core 保证），lockdep_assert_rq_held 在无 lockdep 下是空 ⇒ **不会死锁**；
  风险是「时钟语义被二次推进」，以及命中 RQCF_ACT_SKIP 时 rq_clock(rq) 是**过期值**而 max() 又可能取
  srq->latest_clock ⇒ sts->mark_start = wallclock 被写成过期值 ⇒ 下一次调用的 delta 突然变大 ⇒ 喂给 C5 的长循环。
- **未决**：本内核的 CONFIG_SCHED_DEBUG 值。WSL 里树中没有 .config（配置在 out/ 或 fragment）⇒ 请 captain 侧确认。

---

## 3. 推荐的二分顺序（opt142 / opt143 / opt144 …）

原则：每个实验只改**一个**变量，且都带 §4 的计数器，**不能再用 ratelimited 打印当证据**。

### opt142-A（首选：成本最低、判据最硬）
改法：core.c:5848 按 Stage BO/BQ 同款条件绕开 WALT 的 tick 钩子：

    #ifdef CONFIG_HMBIRD_SCHED_CORE
    {
    	extern atomic_t __hmbird_ops_enabled;
    	extern bool hmbird_transitioning;
    	if (!atomic_read(&__hmbird_ops_enabled) &&
    	    !smp_load_acquire(&hmbird_transitioning))
    		trace_android_vh_scheduler_tick(rq);
    	else
    		atomic64_inc(&hmbird_dbg_tick_hook_skip);
    }
    #else
    	trace_android_vh_scheduler_tick(rq);
    #endif

（顺带把 fair.c:11441 nohz_balancer_kick 与 rt.c:1808 balance_rt 也按同样条件收进守卫，
 但**要分开计数**，否则分不清是哪一条在作恶。）

若结果 X ⇒ 说明 Y
- **不再挂 / running 不再暴增 ⇒ C1 成立**：凶手是 WALT 的 tick 路径 LB（walt_lb_tick）。
  修法＝把三个未守卫的 WALT 钩子补齐（并保留 panic_on_walt_bug 哨兵长期观察）。
  ⇒ 同时解释了 opt104/110/111/112/133 那一整族「启用即硬挂」（都发生在 hmbird 启用后几秒~几十秒）。
- **照旧挂（或 running 照旧暴增）⇒ C1 被排除**，转 opt143。此时「启用即硬挂」与 WALT 无关，
  范围收缩到 hmbird 自己的 ravg 记账 + rescue 动作（C2/C5/C6）。

### opt143（若 opt142-A 无效；也可与 opt142-A 并行做第二组，互为对照）
改法：partial_dynamic_ctrl()（hmbird.c:965）改成**只读 + 只计数**：保留 lmax/bmax 计算与原子计数器，
**删掉 set_partial_rescue() 与 free_isocpu() 两个动作**（rescue 状态恒为初始 false）。

若结果 X ⇒ 说明 Y
- **稳定 ⇒ 缺陷在「rescue 动作」这一侧** ⇒ 转 opt144。
- **仍挂 ⇒ 缺陷在「ravg 记账 + get_cpus_max_util 读取」这一侧** ⇒ 跳 opt145（4 条热路径二分）。
  （注意：opt143 仍会执行 4 条热路径的 wrapper + get_cpus_max_util，所以它**能**区分这两侧。）

### opt144（rescue 动作侧收窄：抖动 vs 使用）
改法：在 opt143 基础上只恢复「**常开不抖动**」：enable 时一次性
set_partial_status(true, false, false); free_isocpu(false);，之后**冻结**，不再随 util 变化。

若结果 X ⇒ 说明 Y
- **稳定 ⇒ 问题是【250Hz 抖动】**（C2 成立）：DSQ 消费者随 partial_enable 开关 + 选核掩码抖动 ⇒ 迁移风暴。
  修法＝单向锁存 + 迟滞（例如只在 l_over/b_over 连续 N 个 jiffy 成立时才翻转，或干脆常开）。
- **仍挂 ⇒ 只要 partial 簇被真正使用就挂** ⇒ 嫌疑落在 update_cpus_idle()/idle_masks（hmbird.c:604-617、
  3022-3044）与跨簇 consume（check_misfit_task_on_little() 2553-2592、consume_dispatch_q）⇒ 下一步单独二分这两处。

### opt145（记账侧收窄，仅当 opt143 仍挂）
改法：把 4 条热路径的 wrapper 调用**一次关一条**（顺序：先只留 task_tick，再放 dequeue，
再放 set_next/put_prev），每条都带 P1/P3/P4 打点。
若结果 X ⇒ 说明 Y：哪一条一关就不挂 ⇒ 缺陷就在那条路径的 sts/srq 交互（结合 C5 的长循环与 C6 的时钟污染）。

### opt146（对照，不解释现象）
slim_walt_ctrl=0 但保留掩码修正（= opt138 + 掩码）。**稳定**则与已知结论一致（掩码本身无害）。

---

## 4. 打点清单（无 ftrace ⇒ pr_info/计数器；**热路径只累加原子量，快照时才打印**）

铁律：pr_info_ratelimited 默认 **5 秒 10 条**；partial_dynamic_ctrl 是 **250Hz** ⇒ 用它做统计等于没开。
**所有频次类证据必须是 atomic64_t 计数器。**

**P1（判定 C3；零成本，同时也是加固）** —— hmbird_util_track.c 的 hmbird_update_task_ravg() 开头：

    if (!slim_walt_ctrl)
    	return;
    if (unlikely(!p))
    	return;
    if (unlikely(!get_hmbird_ts(p))) {
    	pr_info_ratelimited("hmbird-dbg: ravg NULL entity %s pid=%d cls=%ps\n",
    			    p->comm, p->pid, p->sched_class);
    	return;
    }
    struct hmbird_sched_task_stats *sts = &(get_hmbird_ts(p)->sts);
    struct hmbird_sched_rq_stats *srq = &per_cpu(hmbird_sched_rq_stats, cpu_of(rq));

⇒ 开机后**出现该行** = C3 成立（且这是一个真实的 NULL 解引用）；**从不出现** = C3 彻底排除。
（同时建议按厂商写法加 class 保护：p->sched_class != &hmbird_sched_class 直接 return，见 hmbird.h:310-313。）

**P2（判定 C1，最关键的一个计数器）** —— 在 core.c:5848 的守卫处：

    static atomic64_t hmbird_dbg_tick_hook_pass;   /* 放行了 WALT 的 tick LB */
    static atomic64_t hmbird_dbg_tick_hook_skip;   /* 被 hmbird 守卫挡住 */

快照时打印两数 + 每秒速率。**hmbird 启用期间 pass 速率 ≈ HZ×nr_cpus ⇒ WALT 的 tick LB 一直在跑**（C1 直接证据）。

**P3（判定 C2/C5；per-cpu 原子计数器，热路径只 atomic64_inc）**
- enq_cnt / deq_cnt（hmbird.c:2372 / 2449 处）—— **差值就是泄漏量**
- consume_ok_cnt / consume_fail_cnt（consume_dispatch_q() 返回 1/0 分别累加）
- **DSQ 积压快照**：遍历 gdsqs[0..max_hmbird_dsq_internal_id)，统计 !list_empty(&gdsqs[i].fifo)
  的个数与每个 DSQ 的 priq 节点数 —— **DSQ 积压 = running 暴增的直接证据**
- partial_dynamic_ctrl 调用次数，以及 l_over/b_over/p_en/iso_free 的**翻转次数**（不是当前值）
- hmbird_update_task_ravg 调用次数 + 观测到的 nr_full_windows **最大值**（C5）

**P4（判定 C6）** —— 在 hmbird_update_task_ravg_rqclock_wrapper() 里累加两个计数：
「RQCF_UPDATED 已置位（跳过 update_rq_clock）」与「未置位（真的调了）」。
若后者速率 = 4 条热路径的调用速率 ⇒ 说明 CONFIG_SCHED_DEBUG=n，C6 需按「每次真的重跑」评估。

**P5（PSI 线索）** —— psi: inconsistent task state! 每次开机只报一次（psi_bug 是一次性开关）
⇒ 必须抓完整数值：TSK_RUNNING=4（v6.1）
- psi_flags=4 clear=0 set=4 ⇒ **重复入队**
- psi_flags=0 clear=4 set=0 ⇒ **重复出队**

---

## 5. 上机取证配置（t106.sh 落盘快照 + 哨兵）—— 给 captain 用

保持 t106.sh 骨架（**前台**循环，每 2 秒把内容写 /data/local/tmp/t106.log 再 sync；
⛔ **不要 nohup &**：从 su -c 起的后台进程会被回收，opt104 那轮快照全丢）。

快照内容（按重要性排序）
1. /proc/stat 的 procs_running + ctxt + 每核 busy（t106.sh 已有）
2. cat /proc/hmbird_sched/hmbird_stats —— hmbird.c:4923 已有 rq_nr / scxrq_nr 两个字段：
   p->rq_nr[cpu] = rq->nr_running; p->scxrq_nr[cpu] = get_hmbird_rq(rq)->nr_running;
   **这两个数就是「running 虚增」的判定依据**（core 计数 vs hmbird 自己的计数）
3. **新增一行汇总**：enq_cnt deq_cnt（差值=泄漏量）、gdsqs 非空个数、
   p_en/iso_free 翻转次数、tick_hook_pass 速率、nr_full_windows_max
4. dmesg | tail -45（含 hmbird-dbg、WALT-BUG、psi: inconsistent task state!）
5. 哨兵（三条一起开；硬挂无 panic 时这是唯一手段）：
   - echo 8 > /proc/sys/kernel/printk
   - echo 1162141187 > /proc/sys/walt/panic_on_walt_bug   <-- **对 C1 特别有效**：
     若 WALT 对 hmbird 任务做越权迁移/记账，会**立刻 panic 并落盘完整栈**（比等硬挂强得多）
   - hung_task_panic=1（t140.sh 已用过）

建议的实验顺序（每次开机只改一个变量，**≥3 次重复**）
1. opt142-A + P2/P5 哨兵 → 判定 C1
2. （若 C1 排除）opt143 + P3 → 判定 rescue 动作侧
3. （若 opt143 稳定）opt144 → 判定抖动 vs 使用

---

## 6. 本次分析的边界与未决项

- 无设备、无 ftrace/kprobe（available_tracers=[nop]）、无 lockdep ⇒ 结论全部来自静态阅读 + 上机日志 + 逐字 diff。
- **未决 1**：CONFIG_SCHED_DEBUG 的值（决定 C6 严重性）。树里没有 .config，请 captain 侧确认
  （若 =n，则 RQCF_UPDATED 恒 0，4 条热路径每次都真的重跑 update_rq_clock()）。
- **未决 2**：init_task（swapper/0）是否有 hmbird 实体 —— §4 P1 一次开机即知（C3 的最后一环）。
- **未决 3**：partial_enable/isolate_ctrl 的真实翻转频率（t140 的 ratelimited 打印无法回答）—— §4 P3 计数器回答。
- **未决 4**：WALT 三个未守卫钩子里到底是哪一条在迁移 hmbird 任务（tick / nohz_kick / balance_rt）——
  opt142-A 里**分开计数**即可区分。
- **重要更正**：t141.log **在磁盘上不存在**（F:\工作区\_audit\ 里只有 run141.log，且它没有 DONE/pull 行 ⇒
  与「开启后立刻硬挂、日志没来得及拉回」一致）。报告里引用的 t=0s running=48 load1=8.76 是 captain
  在设备侧实时观测到的，不是文件内容。t139.log 同样不存在（只有 run139.log）。

---

## 7. 订正（2026-10-11 02:45，据 captain 的新证据 + opt142 rev2 已上机）

1. **C1（WALT 的 tick 路径 LB）保留并升级为首选**：core.c:5848 的 `trace_android_vh_scheduler_tick` 注册者是
   **ROM 的 sched_walt.ko**（vendor walt.c:5562 → walt_lb_tick），不是 UAG 的 AMU 采样
   （`CONFIG_OPLUS_UAG_AMU_AWARE` 不存在 ⇒ stall_util_cal.o 不编译）。
   ⇒ 给它加守卫是**可行且不伤己方**的（opt144）。
2. **C3（野指针写）正式关闭**：四个活调用点 hmbird.c:2454/2910/2941/3491 全是 sched_class 回调，
   p 必为 hmbird 类任务（task_on_hmbird() 要求实体非空且非 idle 才准进类）；
   唯一能收到任意类任务的 util_track.c:542 已无排队者 ⇒ **opt143 ≡ opt141 结构性 no-op**。
   另外 hmbird_init()（hmbird.c:5116-5131）已在启动时给 init_task 分配实体 ⇒ 本文 §6 的「未决 2」关闭。
3. **version_type 的措辞订正**：内核侧自 Stage K 起**恒为 OGKI**（include/linux/sched/hmbird_version.h:39-42、56-58），
   不是 UNKNOWN；UNKNOWN 只存在于 ROM 模块自己那份 header（厂商原版 vendor-sched_ext/hmbird_version.h:39-42、47-49）。
   因此「厂商 3 处 OGKI 门早就是开的、15 处 GKI 门是关的」；本机 util 恒 0 的原因是
   **ROM sched_walt.ko 没有 hmbird 集成**，不是门关着。⇒ **不要再打 DT 的主意。**
4. **候选重排**：opt139→opt141 三版里唯一真实改变行为的是 opt139；其中真正改变**放置**的是
   `cpumask_set_cpu(4, iso_masks.big)`（hmbird.c:703）让 partial{5,6}/exclusive{7} 首次真正投入使用，
   而不是 `slim_walt_ctrl = 1`（那只是把厂商的调试记账打开，厂商量产机该值恒 0）。
5. **opt142 rev2 的判读**：它同时关掉了 rescue + partial 簇启用 + partial util 采样。
   仍挂 ⇒ 这三族全部无罪，优先做 opt144；稳定 ⇒ 元凶在其中，走 §4 的 R1/R2。

详见 **[方案-opt144.md](方案-opt144.md)**（A/B 两分支预案、opt145/opt146 改法、计数器清单、
以及「dequeue 里的 wrapper 会不会造成 nr_running 只增不减」的直接回答）。
