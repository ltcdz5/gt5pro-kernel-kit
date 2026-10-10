# 收尾说明（analyst）：三次现场不可混用 + 今晚结论的对齐

- 作者：analyst · 2026-10-11 03:12 · 只写文件，未碰设备、未改源码
- 背景：captain 收工指令（03:10 结束，回退 opt60）。本文把 **t142 / t147 / t150** 三个现场的条件与形态并排写清，
  并与 `历史-opt13x实测事实表.md` 的结论对齐。

---

## 0. 一句话

**今晚三次现场不是同一个实验的三次重复，而是三个不同条件、三种不同形态的样本。**
把它们当成同一个「hmbird 开启即挂」的证据池，是今晚最容易犯、也确实犯过的错误。

最关键的分离：**「running 升高」与「硬挂」是两件可分离的事** ——
t147 在 **governor=uag** 下 running 升到 **30`40**（t147.log:18-52）却 **SURVIVED 90s**（t147.log:603）；
而 t141 只记到一个 running=48 的快照就断了（t141.log:7）。
⇒ 单看 running 数值**不能**判定挂/不挂。

---

## 1. 三个现场的条件对照（每一列都必须一起看）

| 维度 | **t142** | **t147** | **t150** |
|---|---|---|---|
| 内核 | opt142（d0a46fbc52e7，md5 6bd5892488b218b6c1fe5e043df196bd） | opt142（同左；t147.log:1 kernel=...opt142） | 同 opt142（t150.log 无 kernel 行，紧接 t147 之后） |
| governor | **无记录**（t142.sh 的 knobs() 不读 governor） | **uag 全程**（t147.log:2/16/17/18… GOV[policy0=uag policy2=uag policy5=uag policy7=uag]，且显式做了 AFTER-RESTORE-TO-UAG） | 无记录 |
| 观测开销 | 每 2s 一次快照（hmbird_stats + dmesg tail -40） | 同 t142 风格（每 `2.5s 一个 --- tN 快照） | **52 个 tracepoint 同时开**（t150.log:1 tracepoints_enabled=52）+ 循环内 dmesg + 3 次 sysrq-l |
| running 序列 | pre1=1, pre2=2 → t1=3, t2=16, t3=22（日志在 t3 后停止写入） | pre1=1 → 6,4,8,15,9,13,19,16,18,18,21,21,25,28,32,**40**,29,37,31,29,31,32,30,39,38,36,36,37,32,32 →（t31 scx=0 后）35,30,15,1,2,1,1,2,1,2,1,1,1,5 → post=6 | baseline=2 → 5,4,9,14,7,4,10,12,19,13,**36**,11,13,15,12…（4↔36 波动，非单调） |
| 形态 | **停摆 → hmbird 自禁恢复**：enable 60.555s → type(4) ux_page_pool_fi[1119] failed to run for 58.016s → 121.858s slim_walt_enable(0) + disabled finished（dmesg_142.txt:17575/18718/18719-18720） | **存活 90s 后正常关闭**（t147.log:603 == t147 SURVIVED 90s -> disabling ==；tpost 正常） | **卡死（由观测开销造成）**；captain 结论：不是 hmbird 单独造成 |
| 这组样本能支持什么 | 「partial 全关时仍会停摆」⇒ 排除 partial/rescue 族；「停摆不是 panic」 | 「**running 升高与 governor=uag 兼容**」⇒ 升高不依赖 scx_gov；「**running 升高 ≠ 必然挂**」 | 「**观测本身能造出挂**」⇒ 52 个 tracepoint + 循环 dmesg + 多次 sysrq 不可同时用 |
| 不能支持什么 | 不能说明 governor 是否参与（**没记录**）；不能与 opt139/141 的「硬挂」混为一谈 | 不能排除 scx_gov 作为**共同因子**（本次没打开它，只证了「不需要它也能升高」） | 不能当作 hmbird 的故障证据（自造的） |

### 1.1 补充：sched_debug 的 cfs_rq 段落 39 → 0

- 实测计数（我本地数过）：sd_pre.txt 含 cfs_rq 的行 = **39**；sd_t3.txt / sd_t8.txt / sd_t15.txt = **0 / 0 / 0**。
- 含义（**这是解释而非实测**，标注清楚）：hmbird 启用后任务都在 hmbird 类里，各 cgroup 的 leaf cfs_rq 没有实体
  ⇒ sched/debug 不再打印 cfs_rq 段。
- ⚠ 因此 **sched/debug 看不到 hmbird 的队列**（reviewer 也提醒过）；t150 里「任务压在 CPU0/1/2、CPU3-7 idle」
  只能说明 **rq->nr_running 的分布**，不能说明 hmbird 的 DSQ 分布。

---

## 2. 「不可混用」四条纪律（下次上机前先读）

1. **一次只改一个条件，并把它记录下来**：内核版本、policy*/scaling_governor、观测集（开了几个 tracepoint）、负载类型。
   （t142/t147/t150 三次的 governor 与观测开销都不同，且 t142 连 governor 都没记 —— 这是今晚最大的数据损失。）
2. **running 数值必须带「观测开销」一起解读**：t150 证明 52 个 tracepoint + 循环 dmesg 就能造出卡死；
   任何「开了大量 tracepoint 时观测到的 running」都不能当 hmbird 的故障证据。
3. **形态要分档**（沿用 t19 表的三档）：①写即挂/秒级挂 ②负载相关挂 ③停摆后自禁恢复。
   **opt142（③）与 opt139/opt141（①②）不是同一种故障**，不能互相印证。
4. **单次样本只写「本次观察到」，不写「该版本会/不会挂」**：t19 表里 opt118/opt121/opt127 各有一次过、一次挂；
   t147（uag）存活 90s 而 t142（同内核）停摆 —— 都是同一类证据不足。

---

## 3. 与 captain 净结论的对齐（逐条核对）

| captain 的净结论 | 我的核对 |
|---|---|
| 已排除 partial 簇 / rescue / partial util 采样（opt142 仍挂） | 与 t142 一致；但**注意形态**：t142 是「停摆后自禁」，不是「硬挂」 |
| 已排除 scx_gov governor（t147 全程 uag） | running 升高确实不需要 scx_gov；⚠ 但 t147 **没挂**，严格说只排除了「升高需要 scx_gov」，**没有**排除「scx_gov 是挂的共同因子」 |
| 已排除野指针写（opt143 结构性 no-op） | 与 t19 附录 B1 及我 t1 报告的 X1 一致 |
| 已排除两份 slim_walt_ctrl（不共享） | 与 t19 附录 B2 一致（设备侧实证：子目录由 ROM 模块创建） |
| 已排除 hmbird_ops ABI 错位（模块无该符号） | 与 upstream t6 的符号表结论一致 |
| 已排除 irq_work 全 rq 锁（opt141 已停） | 我们内核侧已停；⚠ **ROM 模块侧仍有同款**（scx_irq_work()：全 rq 锁 + 持锁进 cpufreq，见 分析-opt142现场-锁与饥饿.md §Q2）—— 这是「我们的已排除」，不是「整机的已排除」 |
| t150：running 4↔36 波动、非单调泄漏 | 与 t150.log 序列一致（我复核了前 30 个快照） |
| t150：任务压 CPU0/1/2、CPU3-7 idle；sysrq-l 无 CPU 卡锁 | ⚠ 我未能独立复核（原始片段在 sd_*.txt 与 t150.log 里；我这次只核了 cfs_rq 计数与 running 序列）；按 §1.1 提醒，这条只能读作 rq->nr_running 分布 |
| t150：cfs_rq 段落 39 → 0 | 我独立数过（39 / 0 / 0 / 0） |
| 教训：t150 的卡死是观测开销造成的 | 采纳（t150.log:1 tracepoints_enabled=52 是直接证据） |

---

## 4. 今晚 analyst 已落盘的产物（交接清单）

| 文件 | 内容 |
|---|---|
| 历史-opt13x实测事实表.md | t19：opt137→opt142 逐版本实测事实（出处/running/形态）+ 更早族（opt104-opt133）+ 附录 B 三条更正（stub 计数器 / 模块 slim_walt_ctrl / kprobe 可用） |
| 分析-opt142现场-锁与饥饿.md | t142 三问：谁切 governor（无人）、scx_gov 卡在哪把锁（模块 scx_irq_work 全 rq 锁 + 持锁进 cpufreq）、ux_page_pool_fi 为什么饿死 58s |
| 方案-opt144.md | opt144（C1 守卫）/opt145（ravg 窗口应用）/opt146（窗口不滚动）方案 + 附录 A（android_vh_get_util 可作 util 源） |
| 分析-slim_walt_ctrl不稳定.md | t1：候选清单 + 二分方案 + 打点清单 + §7 订正 |
| **本文件** | 三次现场条件对照 + 不可混用纪律 + 与净结论的对齐 |

## 5. 下次上机的最小记录集（建议写进 harness）

1. uname -r + 镜像 md5（**每次**）；
2. cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor（**每次**，t142 就是漏了这项）；
3. awk '/^procs_running/{print $2}' /proc/stat + blocked（唯一没被 stub 化的全局量）；
4. **一次最多开 3 个 tracepoint**（建议 events/hmbird/hmbird_update_history + events/schedwalt/sched_enq_deq_task + events/sched/sched_switch），
   **sysrq 整轮只用一次**，且不要放进快照循环；
5. 日志**落地前先改名**（cp /data/local/tmp/tN.log tN-版本-gov.log），避免被下一次运行覆盖（opt138 那次的教训）。

## 6. 设备状态（收尾时）

captain 正在回退到 **opt60（md5 5fd7909866e0de04b8e46cd9b388cc2e）**；本文件不依赖设备状态，
所有结论只基于 _audit 下的日志与源码。
