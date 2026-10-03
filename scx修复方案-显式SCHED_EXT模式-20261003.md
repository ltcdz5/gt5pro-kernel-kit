# scx 修复方案：关掉"强制全接管"，走"显式 SCHED_EXT"模式（2026-10-03）

> 前置：`⛔事故-scx加载硬挂死-20261003.md`（加载 scx 调度器 = 整机硬挂死，无 pstore）。
> 本文回答"为什么会这样"和"怎么修好"。

---

## 一、为什么会这样（原厂为什么留下残缺）

1. **一树多机**：这棵 `common` 树是 OPPO 系多机型共用的。
   `sched_ext` backport 是为一加那边的"风驰"做的——那些机型的 stock 内核真的在游戏时启用 scx。
2. **拼贴 backport**：`scx_bpf_switch_all` 的注释是新 API（带 `@into_scx` 参数、
   "If %false, only tasks which have %SCHED_EXT explicitly set are put on SCX"），
   实现却是旧 API（无参、只能 true）——注释和实现从不同版本拼出来的。
3. **drop 裁剪**：`slim_walt.c` 被删（内部代码不随对外 drop 导出），调用点留下注释
   （`ext.c:287 // #include "./slim_walt.c"`、`:2817 // slim_walt_enable(true)`）。
4. **设备门控**：这台真我的 `gameopt_hal_service` 从未触发过 scx enable
   ⇒ 死锁从未暴露。我们这次的加载测试是**这台内核第一次真正走 enable 路径**。

## 二、★ 修复的关键事实（本树实测）

```
SCHED_EXT 策略号 = 7（include/uapi/linux/sched.h:121）
core.c:4848 / :7157   task_on_scx(p) 为真 ⇒ p->sched_class = &ext_sched_class
task_on_scx()（ext.c:2522-2524）：
    if (READ_ONCE(scx_switching_all))  → 所有任务
    return p->policy == SCHED_EXT      → ★ 否则只有显式 SCHED_EXT 的任务
挂死范围：enable 全程持 cpus_read_lock（:2838 → :3020 之后才解锁）⇒ 挂哪都是整机冻结
```

⇒ **"部分接管"的机制在 core.c 里完好存在**——只是 `enable()` 开头那行
**无条件 `scx_switch_all_req = true`（:2840）** 把所有任务都塞进了 scx。
而挂死极可能就发生在"批量切 ~13000 个任务的调度类"这一步（全程持全局锁）。

## 三、修复实验（两步，每步都可独立判定）

### 第一步（opt43 实验版）：去掉"强制全接管"
```
改动 A（kernel/sched/ext.c:2840）：注释掉 scx_switch_all_req = true;
改动 B（BPF 样例）：去掉对 scx_bpf_switch_all() 的调用
                  （simple.bpf.o 的 needed.txt 里就有它——样例 init() 会调它）
```
**预期**：加载调度器后**零任务被切换**，全部任务照常走 CFS ⇒ 系统应当存活。
- 存活 ⇒ 证明"挂死发生在批量切任务"，进入第二步
- 仍挂死 ⇒ 挂点在 enable 核心（与切任务无关）⇒ **结案：需要 ramdump，不做**

### 第二步：单任务验证
```
在设备上跑一个小程序对自己 sched_setscheduler(0, SCHED_EXT /*=7*/)
⇒ 该任务经 task_on_scx() 进入 ext 类 ⇒ 由 BPF 调度器调度
验证：任务活着、系统活着、/proc/<pid>/stat 的 policy == 7
```
- 成功 ⇒ **scx 以"显式指定任务"模式复活** —— 这正是 Scene 式用法（只给目标任务上 scx），
  CFS+WALT+UAG 对其余任务完全不受影响
- 失败 ⇒ per-task 切换路径也有问题 ⇒ 结案

### 为什么这不是"给原厂擦屁股"
- 部分模式 = **零风险使用**（不碰其余任务、不碰调频链）
- 原厂"全接管 + slim_walt"是给游戏场景设计的（他们有自己的利用率反馈），
  但这台 drop 连 slim_walt 都没有 ⇒ 全接管在这台机器上**本来就不成立**

## 四、成本与风险
- 改动量：内核 1 行 + 样例 1 处；构建/闸门流程照旧（纯 .c，预期 CRC 零变化）
- 风险：实验可能再次挂死手机（每次 1~2 分钟，自动恢复，异常计数不会涨——上次未计数）
- 收益：若成功，本机获得一个**可控的 scx**（Scene 下一版可直接用）
