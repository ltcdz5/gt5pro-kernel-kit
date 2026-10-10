# 准备：官方 sched_ext（BPF struct_ops）加载侧调研与构建准备

> 作者：patcher ｜ 2026-10-11 03:20 ｜ **本文件不含任何设备操作**（未 adb / 未刷机 / 未改内核源码）
> 所有"已实测"都注明命令与输出；"待上机"的部分单独标注。

---

## 0. TL;DR（三条结论）

1. **本机内核的 sched_ext 不是 mainline**，而是 OPPO/OnePlus 的 `hmbird_sched/slim_sched` fork，
   且是 **pre-merge（2023 期）世代**的 ABI。实测：v6.12 / v6.13 / v6.14 / v6.15 / v6.16 / v6.17 / v6.18 / v6.19
   八个 mainline tag 里，**没有一个**含本机独有的标记（`prep_enable`/`cancel_enable`/`SCX_OPS_PREPPING`/
   `SCX_OPS_CGROUP_KNOB_WEIGHT`/`scx_bpf_switch_all`），而本机也**一个都没有** mainline 的
   `tick`/`init_task`/`exit_task`/`dump*`/`cgroup_*`。
2. ⇒ **官方 scx 用户态（github.com/sched-ext/scx v1.x，面向 ≥6.12 mainline）不能直接用**：
   它的 BPF 源码引用了本机不存在的 ops 成员与 kfunc，编译/加载都会失败；用户态还依赖
   `/sys/kernel/sched_ext/state`（本机没有这个属性）。
3. **可行的最小路径已经准备好**：用**本机自己的 BTF** 生成 vmlinux.h，手写一个最小 struct_ops
   调度器（`name` + `select_cpu`/`enqueue`/`dispatch`），用 `bpftool struct_ops register` 注册。
   - `bpftool v7.1.0` **本轮已从本树编出**（原机没有，apt 也没有候选）：`tools/bpf/bpftool/bpftool`
   - 最小程序**已在本机编译通过**（clang rc=0），`.struct_ops.link` 里的 map 大小 **336 字节**，
     与本机 `struct sched_ext_ops` 完全一致 ⇒ **BPF 侧布局对得上**，只差上机 register。

---

## 1. ABI 定版：本机是哪个世代？

### 1.1 实测对照（数据来源：raw.githubusercontent.com/torvalds/linux/<tag>/kernel/sched/ext.c 与 ext_internal.h）

| 项 | **本机** | v6.12 | v6.13 | v6.14 | v6.15 | v6.17 | v6.19 |
|---|---|---|---|---|---|---|---|
| ops 成员数 | **23** | 33 | 33 | 33 | 33 | 34 | 35 |
| `tick` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `init_task`/`exit_task` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `dump`/`dump_cpu`/`dump_task` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `cgroup_*` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅(+set_bandwidth) | ✅(+set_idle) |
| **`prep_enable`/`cancel_enable`** | **✅** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `SCX_OPS_PREPPING` 状态 | **✅(5 态)** | ❌(4 态) | ❌ | ❌ | ❌ | ❌ | ❌ |
| `SCX_OPS_SWITCH_PARTIAL` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `SCX_OPS_CGROUP_KNOB_WEIGHT` | **✅(1<<16)** | ❌(`HAS_CGROUP_WEIGHT`) | ❌ | ❌ | ❌ | ❌ | ❌ |
| `scx_bpf_switch_all` | **✅** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `scx_bpf_dsq_insert` | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `scx_bpf_now` | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| `scx_bpf_nr_cpu_ids` | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `exit_dump_len`/`hotplug_seq` 标量 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

复现命令（本机已跑过，可重跑）：
```bash
for t in v6.12 v6.13 v6.14 v6.15; do
  curl -sSL -o /tmp/u_ext_$t.c "https://raw.githubusercontent.com/torvalds/linux/$t/kernel/sched/ext.c"
  awk '/^struct sched_ext_ops \{/,/^\};/' /tmp/u_ext_$t.c | grep -oE '\(\*[a-z_0-9]+\)' | tr -d '(*)' | tr '\n' ' '; echo
done
# 本机
awk '/^struct sched_ext_ops \{/,/^\};/' /home/builder/kwork/wt-core/include/linux/sched/ext.h \
  | grep -oE '\(\*[a-z_0-9]+\)' | tr -d '(*)' | tr '\n' ' '; echo
```

**结论**：本机 ops 表比 mainline **少 10 个成员**（tick/init_task/exit_task/dump/dump_cpu/dump_task/
cgroup_init/cgroup_exit/cgroup_prep_move/cgroup_move/cgroup_cancel_move/cgroup_set_weight），
**多 2 个**（prep_enable/cancel_enable）；flag 集合与 mainline 的交集只有 KEEP_BUILTIN_IDLE / ENQ_LAST / ENQ_EXITING。
这正是树内注释所说的：*"the factory kernel on this device runs Oppo's own hmbird_sched/slim_sched fork of
sched_ext, not the upstream sched_ext that Oppo's OSS drop published"*（kernel/sched/ext.c:2965-2967）。

### 1.2 权威 ABI 面 = 本机内核 BTF（已生成）

```bash
cd /home/builder/kwork/wt-core
./tools/bpf/bpftool/bpftool btf dump file /home/builder/kwork/out-core/vmlinux format c > vmlinux.h
# 实测：0.27s，154804 行；struct sched_ext_ops 在 vmlinux.h:24832
```
设备侧等价物：`/sys/kernel/btf/vmlinux`（设备 `CONFIG_DEBUG_INFO_BTF=y`，captain 已确认）。

---

## 2. 本机 ABI 清单（写 BPF 程序照这个抄）

### 2.1 `struct sched_ext_ops`（vmlinux.h 实测，总大小 336 字节）

```
select_cpu, enqueue, dequeue, dispatch, runnable, running, stopping, quiescent,
yield, core_sched_before, set_weight, set_cpumask, update_idle,
cpu_acquire, cpu_release, cpu_online, cpu_offline,
prep_enable, enable, cancel_enable, disable, init, exit,
u32 dispatch_max_batch; u64 flags; u32 timeout_ms; char name[128];
```

### 2.2 flags 白名单（ext.c:117 `SCX_OPS_ALL_FLAGS`，设别的位 → `bpf_scx_init_member` 返回 -EINVAL）

| flag | 值 |
|---|---|
| `SCX_OPS_KEEP_BUILTIN_IDLE` | 1<<0 |
| `SCX_OPS_ENQ_LAST` | 1<<1 |
| `SCX_OPS_ENQ_EXITING` | 1<<2 |
| `SCX_OPS_CGROUP_KNOB_WEIGHT` | 1<<16 |

最小程序用 `flags = 0` 最安全。

### 2.3 enable 状态机（ext.c:98）

`SCX_OPS_PREPPING → SCX_OPS_ENABLING → SCX_OPS_ENABLED → SCX_OPS_DISABLING → SCX_OPS_DISABLED`

### 2.4 kfunc 白名单（BTF `FUNC` 实测，19 个）

```
scx_bpf_consume            scx_bpf_create_dsq        scx_bpf_destroy_dsq
scx_bpf_dispatch           scx_bpf_dispatch_nr_slots scx_bpf_dispatch_vtime
scx_bpf_dsq_nr_queued      scx_bpf_error_bstr        scx_bpf_get_idle_cpumask
scx_bpf_get_idle_smtmask   scx_bpf_kick_cpu          scx_bpf_pick_idle_cpu
scx_bpf_put_idle_cpumask   scx_bpf_reenqueue_local   scx_bpf_switch_all
scx_bpf_task_cgroup        scx_bpf_task_cpu          scx_bpf_task_running
scx_bpf_test_and_clear_cpu_idle
```
（另有非 `scx_bpf_` 前缀的：`bpf_cgroup_acquire` 等，见 ext.c:4147-4159 的 BTF_ID_FLAGS 集合。）

### 2.5 常量（**vmlinux.h 里没有**，必须手写）

```c
#define SCX_DSQ_FLAG_BUILTIN  (1ULL << 63)   /* include/linux/sched/ext.h:45 */
#define SCX_DSQ_FLAG_LOCAL_ON (1ULL << 62)
#define SCX_DSQ_GLOBAL        (SCX_DSQ_FLAG_BUILTIN | 1)
#define SCX_DSQ_LOCAL         (SCX_DSQ_FLAG_BUILTIN | 2)
#define SCX_SLICE_DFL         (20ULL * 1000000)      /* 20ms */
#define SCX_SLICE_INF         (~0ULL)                /* U64_MAX */
```

### 2.6 注册对象名与 sysfs

- struct_ops 类型名 = **`"sched_ext_ops"`**（ext.c:3372 `bpf_sched_ext_ops = { .name = "sched_ext_ops" }`）
  ⇒ BPF 侧的 map 名/段名要对应这个类型。
- `/sys/kernel/sched_ext/` 只有两个属性，**都是只读**：`enabled`(0444)、`switched_all`(0444)。
  **没有 `state`、没有每调度器目录** ⇒ mainline scx 用户态读 `/sys/kernel/sched_ext/state` 会失败。
- 启用只能靠 **struct_ops 注册**（BPF link），不能靠写 sysfs。
- 安全网：本机注册了 sysrq `S` = `reset-sched-ext`（ext.c:3376-3390），
  会把 BPF 调度器停掉并把任务退回 CFS。**这是首次上机的必备逃生门**：
  ```
  echo 256 > /proc/sys/kernel/sysrq     # 需要含 SYSRQ_ENABLE_RTNICE(0x100) 位
  echo s > /proc/sysrq-trigger          # reset-sched-ext(S)
  ```

---

## 3. 官方 scx 用户态能不能直接用？——不能

| # | 硬理由 | 证据 |
|---|---|---|
| 1 | scx 的 BPF 源码使用本机不存在的 ops 成员（`ops.tick`/`init_task`/`exit_task`/`cgroup_*`/`dump*`） | 本机 ops 只有 23 个成员，见 §2.1 |
| 2 | scx 调用本机不存在的 kfunc（`scx_bpf_dsq_insert`/`select_cpu_dfl`/`now`/`nr_cpu_ids`/`pick_any_cpu`/`cpu_rq`/`cpuperf_*`…） | 本机 BTF kfunc 只有 §2.4 的 19 个 |
| 3 | scx 用户态读 `/sys/kernel/sched_ext/state` 与每调度器 `ops` 目录 | 本机 sysfs 只有 `enabled`/`switched_all` |
| 4 | scx README 明写「sched_ext is supported by the upstream kernel **starting from version 6.12**」 | scx main README（本轮实测抓取） |

**唯一"世代接近"的是 2023 年的 scx v0.1.x**（scx 仓库 36 个 tag 中最老的是 `v0.1.0`，pre-merge 世代）。
但：① 它仍是 *上游* 的 pre-merge 版本，与本机 OPPO fork 仍有差异（本机的 `prep_enable/cancel_enable` 未必同签名）；
② 该分支早已停止维护；③ 需要 Rust 工具链交叉编译。
⇒ **不建议**把 v0.1.x 当作主路径，最多作为"ops 表怎么写的参考"。

---

## 4. 推荐路径：最小 struct_ops「hello world」（已在本机编译通过）

### 步骤 0：生成 vmlinux.h（用本机 BTF）

```bash
cd /home/builder/kwork/wt-core
./tools/bpf/bpftool/bpftool btf dump file /home/builder/kwork/out-core/vmlinux format c > /tmp/vmlinux.h
wc -l /tmp/vmlinux.h          # 实测 154804
```
（设备侧等价：`bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h`）

### 步骤 1：最小程序（**自包含**，只依赖 vmlinux.h；已实测 clang rc=0）

源文件同时落盘：`F:\工作区\_audit\scx-minimal\minimal_scx.bpf.c`

```c
/* minimal_scx.bpf.c — minimal struct_ops sched_ext scheduler (hello world) */
#include "vmlinux.h"

#define SEC(name) __attribute__((section(name), used))
#define __ksym    __attribute__((section(".ksyms")))

char _license[] SEC("license") = "GPL";

#define SCX_DSQ_FLAG_BUILTIN  (1ULL << 63)
#define SCX_DSQ_GLOBAL        (SCX_DSQ_FLAG_BUILTIN | 1)
#define SCX_SLICE_DFL         (20ULL * 1000000)

extern void scx_bpf_dispatch(struct task_struct *p, __u64 dsq_id, __u64 slice, __u64 enq_flags) __ksym;
extern bool scx_bpf_consume(__u64 dsq_id) __ksym;

SEC("struct_ops/minimal_select_cpu")
__s32 minimal_select_cpu(struct task_struct *p, __s32 prev_cpu, __u64 wake_flags)
{
	return prev_cpu;
}

SEC("struct_ops/minimal_enqueue")
void minimal_enqueue(struct task_struct *p, __u64 enq_flags)
{
	scx_bpf_dispatch(p, SCX_DSQ_GLOBAL, SCX_SLICE_DFL, enq_flags);
}

SEC("struct_ops/minimal_dispatch")
void minimal_dispatch(__s32 cpu, struct task_struct *prev)
{
	scx_bpf_consume(SCX_DSQ_GLOBAL);
}

SEC(".struct_ops.link")
struct sched_ext_ops minimal_ops = {
	.select_cpu = (void *)minimal_select_cpu,
	.enqueue    = (void *)minimal_enqueue,
	.dispatch   = (void *)minimal_dispatch,
	.name       = "minimal",
};
```

### 步骤 2：编译（实测 rc=0，产物 673576 字节）

```bash
clang -target bpf -D__TARGET_ARCH_arm64 -O2 -g -c minimal_scx.bpf.c -o minimal_scx.bpf.o -I/tmp
readelf -S minimal_scx.bpf.o | grep struct_ops
#  [ 3] struct_ops/minimal_select_cpu   [ 4] struct_ops/minimal_enqueue
#  [ 6] struct_ops/minimal_dispatch      [ 9] .struct_ops.link
bpftool btf dump file minimal_scx.bpf.o | grep -A2 "DATASEC '.struct_ops.link'"
#  VAR 'minimal_ops' type_id=327, size=336   ← 与内核 struct sched_ext_ops 大小一致
```
> 说明：不要 `#include <bpf/bpf_helpers.h>` —— 本机没装 libbpf-dev，而树内那份
> `tools/lib/bpf/bpf_helpers.h` 依赖构建期生成的 `bpf_helper_defs.h`（当前不在）。
> 上面的 `SEC`/`__ksym` 手写宏即可，编译完全等价。

### 步骤 3：上机注册（**设备侧，只有 captain 能做**）

```
# 1) 传上去（captain）
adb push minimal_scx.bpf.o /data/local/tmp/
# 2) 逃生门先就位
adb shell "echo 256 > /proc/sys/kernel/sysrq"
# 3) 注册
adb shell "/data/local/tmp/bpftool struct_ops register /data/local/tmp/minimal_scx.bpf.o"
# 4) 观察
adb shell "cat /sys/kernel/sched_ext/enabled /sys/kernel/sched_ext/switched_all"
adb shell "/data/local/tmp/bpftool struct_ops show"
# 5) 退出：kill 掉 bpftool 进程（link 随之释放）或 sysrq-S
adb shell "echo s > /proc/sysrq-trigger"
```
**注意**：`bpftool` 是 x86-64 静态/动态二进制，**设备是 aarch64** ⇒ 需要 **aarch64 版 bpftool**。
本机已有 `aarch64-linux-gnu-gcc`，可以：
```bash
cd /home/builder/kwork/wt-core
make -C tools/bpf/bpftool ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j16   # 待验证
```
或改用 **libbpf 自写的小 loader**（同样需交叉编译）。
—— **这是本任务发现的最大缺口，见 §6。**

---

## 5. 工具链现状（WSL 实测，2026-10-11 03:15）

| 工具/库 | 状态 | 备注 |
|---|---|---|
| clang | ✅ 18.1.3（含 `bpf`/`bpfeb`/`bpfel` target） | BPF 侧编译够用 |
| llc / llvm-objdump / llvm-nm | ✅ 18.1.3 | 反汇编核对 |
| **bpftool** | ✅ **本轮编出** `tools/bpf/bpftool/bpftool` v7.1.0（libbpf v1.1） | apt **无候选包**；用本树源码编：`make -C tools/bpf/bpftool -j16` |
| pahole | ✅ v1.25 | |
| libelf-dev / zlib1g-dev / libzstd-dev | ✅ | bpftool/libbpf 依赖 |
| libbpf | ✅ 树内 `tools/lib/bpf`（v1.1）；系统只有运行库 `libbpf1 1.3.0`，**无 -dev** | 用树内头即可 |
| aarch64-linux-gnu-gcc | ✅ 13.3.0 | 交叉编译用户态用 |
| rustc / cargo | ❌ **未安装** | 只有走完整 scx 用户态才需要 |
| 网络（github/raw.githubusercontent） | ✅ 可达（api 200，文件可下） | |

---

## 6. 还缺什么 / 怎么拿（按优先级）

| # | 缺什么 | 影响 | 获取方式 |
|---|---|---|---|
| 1 | **aarch64 版 bpftool**（或自写 aarch64 loader） | 设备侧无法 register | `make -C tools/bpf/bpftool ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j16`（需实测；bpftool 依赖 libbpf 也要交叉编）**或** 写一个 ~50 行 libbpf loader 交叉编译 |
| 2 | 设备侧 `/sys/kernel/btf/vmlinux` 导出 | 生成设备权威 vmlinux.h | `adb pull /sys/kernel/btf/vmlinux`（captain） |
| 3 | rustc/cargo + `aarch64-unknown-linux-gnu` target + libclang | 只有走完整 scx 用户态才需要 | `rustup`（网络可达）；但**本机 ABI 不匹配，不建议**（见 §3） |
| 4 | libbpf-dev | 只是头文件方便 | `apt-get install libbpf-dev`（有候选 1.3.0）；或用树内头 |
| 5 | `CONFIG_NUMA`/`SCHED_CORE`/`SCHED_AUTOGROUP` 等 | mainline scx 期望它们；最小路径不需要 | 需要改内核（**等 captain 批准**） |
| 6 | `CONFIG_FUNCTION_TRACER`/`DYNAMIC_FTRACE`/`PROVE_LOCKING` | 只是调试便利 | 同上（可选） |

---

## 7. .config 与 scx 官方 `kernel.config` 对照（实测）

```bash
curl -sSL -o /tmp/scx_kernel.config https://raw.githubusercontent.com/sched-ext/scx/main/kernel.config
# 逐项与 out-core/.config 对比
```
- **核心项全 OK**：`CONFIG_BPF`、`BPF_SYSCALL`、`BPF_JIT`、`BPF_JIT_ALWAYS_ON`、`BPF_JIT_DEFAULT_ON`、
  `SCHED_CLASS_EXT`、`DEBUG_INFO`、`DEBUG_INFO_BTF`、`KALLSYMS_ALL`、`SCHED_DEBUG`、`BPF_EVENTS`、
  `KPROBES`/`KPROBE_EVENTS`、`UPROBES`、`DEBUG_FS`、`IKCONFIG_PROC`、`SCHED_MC`、`PREEMPT`。
- **不一致（均不影响最小路径）**：`CONFIG_NUMA`(n)、`CONFIG_NUMA_BALANCING`(n)、`CONFIG_SCHED_CORE`(n)、
  `CONFIG_SCHED_AUTOGROUP`(n)、`CONFIG_PREEMPT_DYNAMIC`(n)、`CONFIG_DEBUG_LOCKDEP`/`PROVE_LOCKING`(n)、
  `CONFIG_FUNCTION_TRACER`/`DYNAMIC_FTRACE`/`FTRACE_SYSCALLS`(n)、`CONFIG_DEBUG_ATOMIC_SLEEP`(n)、
  `CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT`(n)、`CONFIG_IKHEADERS`(=m)。

---

## 8. 风险与判据

- **opt43 那次硬挂的是 OPPO 的 `oplus_bsp_sched_ext.ko`**（注册 OPPO 自定义 `scx_sched_ops`），
  **不是**官方 BPF struct_ops 路径 ⇒「注册 scx 必挂」不能直接搬过来，但也不能假定官方路径安全。
- 首次上机判据（建议按此顺序，**captain 执行，成员不碰设备**）：
  1. 先只 `register` 最小程序，**不做任何负载**：`/sys/kernel/sched_ext/enabled` 应为 1，
     `bpftool struct_ops show` 能看到 `minimal`，系统不卡、`procs_running` 仍在 1~3。
  2. 再跑 8 线程满载 60s：`procs_running` 不应像 opt141 那样 t=0s 就跳到 48。
  3. 任何时候可用 **sysrq-S**（`reset-sched-ext`）退回 CFS —— 这是本内核自带的逃生门。
- 失败模式预判：`register` 直接返回 `-EINVAL`/`-ENOTSUPP`（说明 BPF 侧布局或 kfunc 名不匹配）；
  或注册成功但 watchdog 30s 超时（`timeout_ms` 上限 `SCX_WATCHDOG_MAX_TIMEOUT=30s`）后自禁 —— 都可在 dmesg 看到
  `sched_ext:` 前缀日志。

---

## 9. 本轮产出的可复现清单

| 产物 | 路径 | 状态 |
|---|---|---|
| 本文件 | `F:\工作区\_audit\准备-官方sched_ext加载侧.md` | ✅ |
| 最小 BPF 程序源码 | `F:\工作区\_audit\scx-minimal\minimal_scx.bpf.c` | ✅（本机 clang 编译 rc=0） |
| 最小 BPF 目标文件 | `/tmp/minimal_scx.bpf.o`（WSL，673576 字节） | ✅（未上机） |
| vmlinux.h（本机 BTF 导出） | `/tmp/vmlinux.h`（WSL，154804 行） | ✅ |
| bpftool | `/home/builder/kwork/wt-core/tools/bpf/bpftool/bpftool` v7.1.0 | ✅（x86-64，设备需 aarch64 版） |
| mainline ext.c 对照样本 | `/tmp/u_ext_v6.{12,13,14,15,16,17,18,19}.c` | ✅ |

**未做**：未 adb / 未刷机 / 未改任何内核源码（本任务只做调研与构建准备）。
---

## 10. ★未验证 / 待确认清单（明确标注，别当成结论用）★

| # | 未验证的东西 | 现状 | 怎么验证 |
|---|---|---|---|
| 1 | **aarch64 版 bpftool 能否这样编出来** | 只是建议命令，**没跑过**：`make -C tools/bpf/bpftool ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j16`。bpftool 依赖 libbpf，可能需要先交叉编 `tools/lib/bpf` | 在 WSL 跑一次；失败则改走"自写 aarch64 libbpf loader" |
| 2 | **最小程序能否真的 register 成功** | 只验证到"clang rc=0 + BTF 里 map 336 字节"；**从未加载过** | 设备侧 `bpftool struct_ops register`（captain） |
| 3 | **kfunc 解析是否通过** | 本机 BTF 里确有 `scx_bpf_dispatch`/`scx_bpf_consume`（§2.4），但**没做过实际 load** | 同 #2；失败会在 dmesg 留 `libbpf: extern ... not found` |
| 4 | **本 fork 的 enable 路径要求哪些 ops** | 只看到 `SCX_HAS_OP()` static branch 机制（ext.c:264）⇒ 缺失的 op 大概率被容忍；**没有完整读 validate 逻辑** | 读 `scx_ops_enable()`（ext.c:2944 起）+ 首次 register 实测 |
| 5 | **`prep_enable` 是否必须实现** | 未验证。本 fork 有 `SCX_OPS_PREPPING` 状态，理论上 enable 前会走 prep 阶段 | 同上；若 register 报 `-EINVAL` 就先补 `prep_enable` 返回 0 |
| 6 | **设备 `/sys/kernel/btf/vmlinux` 与本机 out-core/vmlinux 的 BTF 是否逐字段一致** | 未验证（同树同 config 应当一致） | `adb pull /sys/kernel/btf/vmlinux` 后 `bpftool btf dump` 对比 |
| 7 | **scx v0.1.x（2023 世代）是否与本 fork 同源** | **没验证成**：v0.1.0 的 bpf 头文件路径三次尝试都 404（仓库布局不同） | 克隆 `sched-ext/scx` v0.1.0 看 `scheds/` 与 `rust/` 里的 ops 定义 |
| 8 | **`bpftool struct_ops register` 在 libbpf v1.1 上对本内核可用** | 未验证（bpftool 是 v7.1.0 + in-tree libbpf v1.1） | 设备侧实测；不行就用 libbpf 自写 loader |
| 9 | **`switched_all` 的语义** | 本 fork 有 `scx_bpf_switch_all()` kfunc 与只读 `switched_all` 属性；与 mainline 的 `SCX_OPS_SWITCH_PARTIAL` flag **不是一回事** | 读 ext.c:2804/3171 附近的 static branch 逻辑 |
| 10 | **本机 `ext.c` 与 OPPO OSS drop / ferstar 分支的关系** | 树内注释说"从 ferstar GT5 Pro scx 分支移植、非整包替换"（ext.c:13-20）；**没有逐行比对** | 若能拿到 ferstar 分支源码再 diff |

> 其余部分（§1 的 ABI 对照、§2 的清单、§4/§5/§6/§7 的工具链与 config 实测）都是**本轮真跑过的命令与输出**，
> 可以直接引用；§4 步骤 3 与 §8 的设备侧动作**全部留给 captain**。

