# 第8步 · 风驰调度核心（Stage A/B/C）—— Lead 复核结论

> 日期：2026-10-09 ｜ 设备：真我 GT5 Pro（RMX3888 / SM8650 / ColorOS 16）｜ 主线内核：opt60
> 工作区：`wt-core`（独立 worktree）/ `O=/home/builder/kwork/out-core` ｜ 全部改动 gate 在 `CONFIG_HMBIRD_SCHED_CORE`（**默认 n**）

## 一、三个阶段与提交
| 阶段 | 内容 | 提交 | 判据 |
|---|---|---|---|
| **A** | 搬入 hmbird **sched_class 家族 19 文件 / 7,990 行**（权威 = `_lab/2026-10-08/scx-step4d/norm/loc_fengchi.patch`，独立再抽取 19/19）+ 构建胶水 + 子目录 Makefile + 5 处 guard 改名 | `2a08b68fc280` | 构建 rc=0；四关全绿；**导出集 15,489 逐名 diff 为空** |
| **B** | 补 **26 个缺失标识符** + API 适配（`set_cpus_allowed` 按本树签名、4 处 static 冲突改名、与 `ext.h`/`core.c` 去重、tracepoint 顺序）+ 排除 proc 重叠文件 | `a8c954cdd0a8` | **家族 TU 121 errors → 0**；`CORE=y` 全量 **rc=0**；四关全绿；**导出集 15,489** |
| **C** | **`core.c` 接线**（唯一改动的源文件）：`__task_prio` / `sched_can_stop_tick` / `select_task_rq` / `sched_fork` / `sched_cgroup_fork` / `sched_post_fork` / `scheduler_tick` 等 | `03e40923075a` | 由 **Lead 亲自跑** harness（见下）；四关全绿；**导出集 15,489** |

## 二、Lead 亲自复核（`_audit/gate_core.py --label stageC`）
````
2) audit_all(493模块)  ✅ PASS  modules=493 missing=0 crc=0
3) gate_vko_crc        ✅ PASS  拒载=0 (导出=15489)
4) gate_new_exports    ✅ PASS  新增=15 消失=0 遮蔽=0   (rc=1 = opt54 以来既定基线)
5) 导出集逐名 diff     ✅ PASS  候选=15489 基线=15489 逐名一致=True
6) proc 条目集对账     ✅ PASS  保留 21/21、DROP 异常=0 (BTF 感知)
判定: PASS
````
⇒ **完整链路 A→B→C 就位：家族能编进内核、且已接进调度路径；ABI 一点没动（导出集 15,489 逐名一致）。**

## 三、唯一核心文件改动（已单独声明）
- `drivers/cpufreq/cpufreq.c`：`store_scaling_governor()` **去掉 static**（只改修饰符，函数体逐字节未动）+ `include/linux/cpufreq.h` 加原型
- **无 EXPORT_SYMBOL** ⇒ 不进 `vmlinux.symvers` ⇒ **导出集/CRC 不受影响**（`System.map` 为全局 T，独立审计已核实）

## 四、仍缺（下一步）
1. `hmbird_sched_proc.c` 的 **13 条非重叠 proc 条目**按需注册
2. `slim_walt_*`：内核侧与厂商模块**各持一份** ⇒ 语义待统一（先只登记，避免遮蔽）
3. **上机验证**：需在 `CONFIG_HMBIRD_SCHED_CORE=y` 的镜像上刷机，然后 `echo 1 > /proc/hmbird_sched/scx_enable` ⇒ 观察 **dmesg 是否出现 hmbird_sched 标签**（= fork 真在跑的硬信号）

## 五、过程留痕
- 验证 harness：`_audit/gate_core.py`（参数化 O=/Image/symvers；BTF 感知的 proc 检查，已消除 `frame_per_sec` 假阳性）
- 出厂 oracle 快照：`_lab/2026-10-09/scx-verify/stock-oracle/`（63,569 字符串、stock.btf 150,929 行、厂商 __versions CRC 契约 11 项）
- Stage B 独立审计 JSON：`_lab/2026-10-09/scx-verify/audit-stageB.json`
- **备注**：Stage B/C 的两位执行体进程在收尾前**异常退出**（未留终版报告），因此 Stage C 的最终判据由 **Lead 亲自复核**（上表）；其提交与 JSON 产物完整可查。
