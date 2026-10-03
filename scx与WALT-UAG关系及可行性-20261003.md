# scx 与 WALT/UAG 的关系（2026-10-03 实测结论）

> 机主两个问题：①加载 scx 后一定接管调度器吗？②Scene 指定 uag/walt，也会变 scx 吗？

---

## 一、问题①：加载 scx 后一定接管吗？

**本树：是，一定全接管，无法选"部分"。** 证据链（`kernel/sched/ext.c`）：

```
:2840   scx_switch_all_req = true;        ← enable 时无条件设（在 ops.init() 之前）
:2967   WRITE_ONCE(scx_switching_all, scx_switch_all_req);
:3003   if (scx_switch_all_req) static_branch_enable_cpuslocked(&__scx_switched_all);
:3341   void scx_bpf_switch_all(void)     ← kfunc 被削成【无参】，只能设 true
```

⇒ 上游本来有 `scx_bpf_switch_all(bool into_scx)`（注释里 `@into_scx: switch direction` 还在，
`If %false, only tasks which have %SCHED_EXT explicitly set are put on SCX` 这句也在），
但厂商 backport 把**参数削掉了**，实现只剩 `scx_switch_all_req = true`。
⇒ **部分接管这条路在本树是断的。**

调度类优先级（`core.c:9999` 的 BUG_ON 断言）：
```
dl > rt > fair(CFS) > ext(scx) > idle
```
⇒ 任务一旦被切到 `ext_sched_class`，就**不在 CFS 的 rq 上**了。

---

## 二、问题②：Scene 指定 uag/walt，会变 scx 吗？

**不会"变成 scx"。** 这是两个不同层面：

| 东西 | 是什么 | 在哪一层 |
|---|---|---|
| **WALT** (`sched_walt` 模块) | 高通 **负载跟踪**：统计每个任务的 CPU 利用率 | CFS 调度类内部（挂在 `fair.c` 的 vendor hook 上） |
| **UAG** (`cpufreq_uag` 模块) | **CPU 调频 governor**：根据 util 选频率 | cpufreq 层（不是调度类） |
| **scx** (`ext_sched_class`) | 一个**独立的调度类** | 与 CFS 平行（在 CFS 之下、idle 之上） |

设备实测（v1.1-opt42）：
```
scaling_governor = uag        ← 当前调频用的就是 UAG
可选 governor: walt uag conservative powersave performance schedutil
/sys/module/sched_walt/holders/cpufreq_uag   ← ★ UAG 依赖 WALT 的 util 输入！
/proc/sys/walt/sched_walt_rotate_big_tasks 等 sysctl 在
fair.c 里 vendor hook 调用点 = 36 个（enqueue_entity/dequeue_entity/update_load_avg/
  util_est_update/place_entity/util_fits_cpu/…）—— 这些就是 WALT/uag 挂钩的地方
```

⇒ **Scene 指定 uag 或 walt，只是切调频方案/调 WALT 参数，不会把任务变成 scx。**

---

## 三、★ 但 scx 全接管后，这条链会【断】

```
任务在 CFS → WALT 统计 util（经 fair.c 的 36 个 hook）→ UAG 读 util → 选频率
     ↑ scx 全接管后任务离开 CFS，这一段断掉
```

后果：
1. **被接管的任务不再走 CFS** ⇒ `fair.c` 的 36 个 vendor hook 对它们**不再触发**
   ⇒ WALT 不再统计它们的 util
2. **UAG 读到的 util 掉下来** ⇒ **调频偏低 ⇒ 性能下降**
3. **本树没有 `scx_bpf_cpuperf_*`**（0 个）⇒ scx 调度器**无法直接推调频**补偿
   （上游就是靠这组 kfunc 让 BPF 调度器接管调频的）
4. `slim_walt_enable(true)` 协调钩子被厂商**注释掉**（`ext.c:2817`），且 `slim_walt.c` 源码已删 ⇒ 协调机制是死的

**⇒ 结论：本树能"跑" scx（框架完整），但跑起来大概率掉频掉性能 —— 不建议全接管加载。**

---

## 四、可行方案（如果一定要用 scx）

**恢复上游的 `scx_bpf_switch_all(bool into_scx)` 签名**（一个小而精准的改动）：

```c
/* 现状（厂商削过的） */            /* 恢复成上游的 */
void scx_bpf_switch_all(void)       void scx_bpf_switch_all(bool into_scx)
{                                   {
    if (!scx_kf_allowed(SCX_KF_INIT))   if (!scx_kf_allowed(SCX_KF_INIT))
        return;                             return;
    scx_switch_all_req = true;          scx_switch_all_req = into_scx;
}                                   }
```

⇒ 调度器在 `init()` 里调 `scx_bpf_switch_all(false)` ⇒ **部分接管模式**：
- **只有显式 `sched_setscheduler(SCHED_EXT)` 的任务**走 scx
- **其余所有任务照常走 CFS + WALT + UAG** ⇒ Scene 的调优完全不受影响
- 两条路并存，可以安全实验

**CRC 影响评估**：`scx_bpf_*` 是 **kfunc**（BTF 暴露），**不是** `EXPORT_SYMBOL`
（`ext.c` 里 EXPORT_SYMBOL 数 = 0，`vmlinux.symvers` 里 scx_ 导出数 = 0）
⇒ **不在 symvers 里 ⇒ 不参与 modversions CRC ⇒ 厂商 .ko 不受影响**（预期；仍须 `crc_diff.py` + 双闸门实测）。

配套还需要：一个适配本树 `sched_ext_entity` 布局的 BPF 调度器（树里 5 个样例都按更新版本写的，
需小改）+ arm64 loader（`libbpf.a` 已交叉编译成功）。

---

## 五、本树 scx 能力边界（汇总）

```
✅ 有：ext_sched_class / bpf_sched_ext_ops / bpf_scx_verifier_ops
✅ 有：19 个 scx_bpf_* kfunc / BTF 完整（struct sched_ext_ops 全字段）
✅ 有：CONFIG_BPF_SYSCALL=y / BPF_JIT=y / DEBUG_INFO_BTF=y（/sys/kernel/btf/vmlinux 5.8MB）
❌ 无：scx_bpf_switch_all(false) 部分接管（kfunc 被削成无参只能 true）
❌ 无：scx_bpf_cpuperf_*（无法直接控制调频）
❌ 无：bpf_iter_num（6.13 的 BPF 迭代器）
❌ 无：/sys/kernel/sched_ext（sysfs 运维接口）
❌ 无：slim_walt 协调（厂商注释掉且源码已删）
```

## 六、编译验证进度（本轮已通到哪）

```
✅ 最小 BPF 程序编译通过（3816 字节）—— 证明 BPF 编译链路全通
   （需要：vmlinux.h 用 bpftool 从 out/vmlinux 的 BTF 生成；
     bpf 助手头用 tools/sched_ext/tools/include/bpf/ 那套；
     asm 头需要自造 include 目录——内核树的 asm/errno.h 是缺失的转发软链）
✅ libbpf.a 交叉编译成功（arm64，2.8 MB）
✅ bpftool 编出（x86 版，仅用于本地生成 vmlinux.h / skel.h）
❌ 5 个官方样例均按更新内核编写，需适配本树 sched_ext_entity 布局
❌ arm64 bpftool 交叉编失败（libbpf 的 .so 用 ld.lld 链接 version script 失败；
   静态 .a 成功 ⇒ loader 不受影响，只影响设备端 bpftool）
```
