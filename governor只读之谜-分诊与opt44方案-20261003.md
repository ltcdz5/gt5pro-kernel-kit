# governor 只读之谜：分诊结论 + opt44 方案（2026-10-03）

> 起因：`lunar_ext_gov`（LSE 模块注册）无法激活，因为
> `/sys/devices/system/cpu/cpufreq/policyN/scaling_governor` 写入报 `Permission denied`。
> 目的：判断这是**影子挂载**（可 umount 秒解）还是**运行期锁定**（需内核侧开口）。

---

## 一、分诊结果（全部实测，只读）

| 检查 | 结果 | 含义 |
|---|---|---|
| `id` / `CapEff` | `uid=0 context=u:r:ksu:s0` / `000001ffffffffff` | 是真 root，**有 CAP_DAC_OVERRIDE** |
| `stat` 各节点 `dev` | governor=**20**、min_freq=**20**、btf/vmlinux=**20**、模块 refcnt=**20** | **同一 sysfs** ⇒ 不是影子挂载 |
| `umount <node>` / `umount policy0` | `Invalid argument`（不是挂载点） | 再次排除影子挂载 |
| 30 秒权限采样 | 恒 `-r--r--r--`，不变 | 不是周期性开合 |
| 20 次重试写 | **0 成功 / 20 失败**，全 EACCES | 稳定不可写 |
| `dd of=<node>` | `0 bytes copied` | 同上 |

### ★ 决定性推理
root 有 `CAP_DAC_OVERRIDE` ⇒ **若属性有 write fop，即使模式是 0444 也能写**。
报 EACCES ⇒ **该属性没有 write fop（真只读属性）**，不是权限位问题。

### ★ 但存在"曾经可写"的铁证
分诊脚本运行时（同一 inode **91287**）：
```
stat → 权限=-rw-r--r--   (0644)
printf 'performance' > <node>  → rc=0     ← 写成功
```
数分钟后再测：同一 inode → `-r--r--r--` 且 EACCES。

⇒ **有厂商代码在运行期移除并以只读方式重建了这个属性**（inode 复用），或在其上切换了 fops。
结合已发现的 **22 个 OPLUS MountMask**（tmpfs 影子挂载，遮蔽
`msm_performance/cpu_min_freq`、`walt/input_boost/*`、`cpufreq_bouncing/enable` 等），
可判定这是个**统合性的 anti-tamper 机制**：允许内核/框架内部改，不允许用户态改。

**结论：不能靠 umount 解决；要让 `lunar_ext_gov` 生效，必须从内核侧开可写入口。**

## 二、opt44 候选方案（CRC 中性）

**做法**：不动 `scaling_governor`（会被厂商锁），而是在 cpufreq 核心**新增一个不同名的可写属性**，
内部直接调 `cpufreq_set_policy()` 切 governor。

```c
/* drivers/cpufreq/cpufreq.c 新增（示意） */
static ssize_t store_gov_override(struct cpufreq_policy *policy, const char *buf, size_t count)
{
    /* 解析 governor 名 → cpufreq_get_governor() → cpufreq_set_policy(policy, new_policy) */
}
cpufreq_freq_attr_rw(gov_override);        /* 新名，厂商锁不到 */
/* 加进 cpufreq_attrs[] */
```
- 也可放在 **debugfs**（更隐蔽、不进 sysfs 属性表）：`/sys/kernel/debug/cpufreq/set_gov`
- **风险**：
  - `cpufreq_set_policy()` 内部会走 governor 切换（调用 LSE 的 `lunar_ext_gov` init）——
    **LSE 的 governor 在本机从未跑过（6.1+SM8650 无先例）**，首次切换有未知风险
  - 必须保证**能切回 `uag`**（同一入口），否则只能重启
- **收益**：解锁 LSE 的调频臂 ⇒ 才有真正的性能/功耗对比实验
- **闸门**：纯 `.c` 改动、不新增导出 ⇒ 预期 `crc_diff` 0 变化、双闸门不变

## 三、风险与回退

| 项 | 说明 |
|---|---|
| 首次切到 `lunar_ext_gov` | 无先例；若行为异常，用同一入口切回 `uag`；最坏重启 |
| LSE 模块 | `[permanent]`，`rmmod` 必然失败（源码无 `module_exit`）⇒ 重启才能卸载 |
| 回退顺序 | ① 切回 `uag`（+ `soft_freq_min/max` 写回 -1）② 重启（模块消失）③ 万一新内核有问题 → 刷回 opt42（md5 `4bd362b0a17513474de217ea9beb8ae3`） |

## 四、同时确认的可用资产（不需要内核改动）

```
/proc/sys/lunar_sched_ext/     ← LSE 的 Slim WALT 接口，实测可写、无需动 SELinux
  slim_walt_ctrl = 1     slim_walt_policy = 2
  sched_ravg_window_frame_per_sec = 120   （⚠ 写 0 会除零炸机）
  lse_gov_debug = 0 (0666)
tracepoint 实测：lse_run_window_rollover 翻转步进 16ms（真实窗口，非读数的 8.33ms）
                 lse_update_history 已注册
⇒ LSE 的负载跟踪半边【确认在运行且可控】；缺的只是调频臂（被 governor 锁挡住）
```
