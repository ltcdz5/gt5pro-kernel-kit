# 评估：走上游官方 sched_ext（BPF struct_ops 调度器）路线

> 任务 t21 / 成员 upstream / 2026-10-11。只读源码与既有文档，**未碰设备、未改源码**。
> 证据一律给 文件:行号 或 .config 行号；不确定的标【未验证】。

---

## 0. 结论（先看）

**可行（推荐），但有一个硬前提、一个必须纠正的误解、和一个必须先做的最小实验。**

| # | 要点 |
|---|---|
| 1 | **硬前提：必须针对我们内核的 BTF 重新编译**。我们的 `ext.c` 是 **pre-6.12 的 out-of-tree sched_ext v1 快照**（OPPO 分支），不是 mainline 6.12+。struct_ops 的结构由 BTF 驱动，但 **flag 常量与 kfunc 集合是 v1 的** ⇒ 直接拿 mainline 的 scx 发布产物不行（§1）|
| 2 | **★纠正一个误解：opt43 的「注册 scx 必挂」不能迁移到官方路径★**。opt43 挂的是 OPPO 的自定义表（`register_hmbird_sched_ops` / `register_walt_ops`，见 t17）；官方走的是 **BPF struct_ops**（`bpf_sched_ext_ops`，`.name = sched_ext_ops`，ext.c:3372-3380），入口是 bpf 系统调用 → `bpf_scx_reg()`(ext.c:3346) → `scx_ops_enable()`(ext.c:2944)。**两条路的入口、注册对象、失败模式都不同**（§4）|
| 3 | **但也不能反推官方路径一定安全**（§4 末）：两者最终都要把任务从 CFS 切到新 class，切类/放置是共有风险区 ⇒ **必须先用最小调度器做实验**（§6 E1）|
| 4 | **★失败安全：任务书的一个假设是错的★** —— `/sys/kernel/sched_ext/enabled` 是 **0444 只读**（ext.c:4220），**不能写 0 回退**。真正的回退是 **`echo s > /proc/sysrq-trigger`**（`sysrq_handle_sched_ext_reset`，ext.c:3382-3388）或释放 bpf_link（§5）|
| 5 | 用户态工具链**在树里齐备**（bpftool 含 `struct_ops.c`、libbpf 含 `libbpf.c/bpf.c/btf.c`），WSL 里 `clang -target bpf` 与 `aarch64-linux-gnu-gcc` 均**已实测可用**（§3）|

---

## 1. Q1：我们的 ext.c 是哪个 sched_ext 版本？

### 1.1 判据逐项比对

| # | 判据 | 我们树 | mainline | 结论 |
|---|---|---|---|---|
| 1 | `include/uapi/linux/sched/ext.h` 是否存在 | **不存在**（`include/uapi/linux/sched/` 下只有 `types.h`）| **存在**（6.12 随 sched_ext 进主线引入，是用户态 ABI 头）| ⇒ **pre-6.12** |
| 2 | `SCX_ENQ_WAKEUP` 的定义 | `kernel/sched/ext.h:99` = `ENQUEUE_WAKEUP`（**内核内部枚举的别名**）| uapi 固定值（不随内核内部枚举变化）| ⇒ **不是 mainline ABI**；BPF 程序里的常量值会跟着内核内部枚举走 |
| 3 | `SCX_DEQ_SLEEP` | `kernel/sched/ext.h:153` = `DEQUEUE_SLEEP`（内部别名）| uapi 固定值 | 同上 |
| 4 | `SCX_OPS_NAME_LEN` | `include/linux/sched/ext.h:17` = 128 | 6.12 也是 128 | 一致 |
| 5 | `SCX_SLICE_DFL` | `include/linux/sched/ext.h:22` = 20ms；**另有 `include/linux/sched/sa_common_struct.h:77` 重定义为 1ms** | 6.12 = 20ms | ⚠ OPPO 有第二处重定义 ⇒ **头文件冲突风险，需注意包含顺序** |
| 6 | `scx_ops_enable()` 签名 | `ext.c:2944` `static int scx_ops_enable(struct sched_ext_ops *ops)`（**无 bpf_link 参数**）| 6.13 起带 link | ⇒ 早于 6.13 |
| 7 | `scx_bpf_rcu_read_lock` / `scx_bpf_now` / `scx_bpf_nr_node_ids` | **全 0** | 6.13 | ⇒ 早于 6.13 |
| 8 | `dump` / `dump_cpu` / `dump_task`（ops 成员）| **全 0** | 6.13 | ⇒ 早于 6.13 |
| 9 | `scx_bpf_dsq_insert` / `scx_bpf_dsq_move_to_local` / `scx_bpf_dispatch_from_dsq` | **全 0** | 6.14（v2 名字）| ⇒ 早于 6.14 |
| 10 | `SCX_OPS_HAS_CGROUP_WEIGHT` / `SCX_OPS_ALLOW_QUEUED_WAKEUP` / `SCX_OPS_BUILTIN_IDLE_PER_NODE` | **全 0** | 6.12 | ⇒ **早于 6.12** |
| 11 | `SCX_OPS_HAS_CPU_PREEMPT` | 0 | 6.14 | ⇒ 早于 6.14 |
| 12 | `SCX_OPS_KEEP_BUILTIN_IDLE` | **6 处**（存在）| 6.12 | v1 也有此 flag |
| 13 | `struct sched_ext_ops` 字段集 | 见 `include/linux/sched/ext.h:165-499`：`select_cpu/enqueue/dequeue/dispatch/runnable/running/stopping/quiescent/yield/core_sched_before/set_weight/set_cpumask/update_idle/cpu_acquire/cpu_release/cpu_online/cpu_offline/prep_enable/enable/cancel_enable/disable/init/exit/dispatch_max_batch/flags/timeout_ms/name[128]` | 6.12 大体同形 | **与 6.12 大体同形** |
| 14 | struct_ops 名字 | `ext.c:3379` `.name = "sched_ext_ops"` | 同 | ✅ **libbpf/scx 靠这个名字找 struct_ops，一致** |
| 15 | `scx_bpf_*` kfunc 数量 | **20 个唯一名字**（ext.c 全树 79 处引用）| 6.12 有 50+ | ⇒ **kfunc 集合明显更小** |
| 16 | `.BTF` / `.BTF_ids` 段 | **存在**（readelf -S out-core/vmlinux）| 必需 | ✅ struct_ops 可加载的前提具备 |
| 17 | `struct bpf_struct_ops bpf_sched_ext_ops` | `ext.c:3372-3380`（`.verifier_ops/.reg/.unreg/.check_member/.init_member/.init/.name`）| 同形 | ✅ 官方 BPF 入口**完整存在** |
| 18 | `kernel/bpf/bpf_struct_ops.c` | 存在（18,212 B）| 同 | ✅ |
| 19 | `BPF_PROG_TYPE_STRUCT_OPS` / `BPF_LINK_CREATE` | `include/uapi/linux/bpf.h:993` / `:912` | 同 | ✅ 所需 bpf 系统调用 ABI 存在 |

### 1.2 结论

**我们的 `ext.c` 是 out-of-tree / pre-mainline（v6.11 时代，sched_ext v1）的 OPPO 分支快照，不是 mainline 6.12+。**

**兼容性结论（关键）：**
- **struct_ops 的 ABI 由 BTF 驱动**：`bpf_sched_ext_ops.init`（ext.c:3357-3367）只用 `btf_find_by_name_kind(btf, "task_struct")`，成员校验走 `bpf_struct_ops.c` 的 BTF 比对；
  ⇒ 只要 BPF 程序是针对**我们内核的 BTF** 编译的，`struct sched_ext_ops` 的布局**天然匹配**。
- **但 flag 常量（`SCX_ENQ_*` / `SCX_DEQ_*` / `SCX_OPS_*`）不参与校验**（它们是编译期常量）。
  ⇒ 用 mainline 头文件编译出来的调度器会传**错误的 flag 值** ⇒ 行为错乱（不一定崩）。
- **kfunc 集合更小**：scx_lavd 等现代调度器大量使用 6.13/6.14 的 kfunc（`scx_bpf_now` / `scx_bpf_dsq_insert` / `scx_bpf_rcu_read_lock` …），**在我们树上会加载失败**（kfunc 不存在 ⇒ 验证器拒绝）。

**⇒ 必须用我们内核的 BTF/头文件重新编译，且优先选 kfunc 依赖最少的调度器（scx_central / 最小调度器），不要一上来就 scx_lavd。**

---

## 2. Q2：加载一个 BPF 调度器需要哪些用户态组件？

### 2.1 内核侧（已具备，逐条给 .config 行号）

| 项 | 位置 | 状态 |
|---|---|---|
| `CONFIG_SCHED_CLASS_EXT=y` | out-core/.config:116 | ✅ |
| `CONFIG_BPF_SYSCALL=y` | :97 | ✅ |
| `CONFIG_BPF_JIT=y` / `CONFIG_BPF_JIT_ALWAYS_ON=y` / `CONFIG_BPF_JIT_DEFAULT_ON=y` | :98 / :99 / :100 | ✅ |
| `CONFIG_DEBUG_INFO_BTF=y` / `CONFIG_DEBUG_INFO_BTF_MODULES=y` | :7401 / :7405 | ✅（struct_ops 的硬前提）|
| `CONFIG_CGROUP_BPF=y` / `CONFIG_BPF_EVENTS=y` | :230 / :7614 | ✅ |
| `.BTF` / `.BTF_ids` 段 | readelf -S out-core/vmlinux | ✅ |
| `bpf_sched_ext_ops` struct_ops | ext.c:3372-3380 | ✅ |

### 2.2 用户态：两条路，**都在树里有源码**

| 路线 | 组件 | 树内状态 |
|---|---|---|
| **(A) bpftool** | `tools/bpf/bpftool/struct_ops.c`（`bpftool struct_ops register <obj>`）| ✅ **存在**；`gen.c` / `main.c` / `btf.c` 均 ✅；`main.h:164 do_struct_ops()` 声明存在 |
| **(B) 官方 scx（libbpf skeleton）** | `tools/lib/bpf/`：`libbpf.c` / `bpf.c` / `bpf.h` / `btf.c` / `btf.h` / `libbpf.h` / `relo_core.c` / `gen_loader.c` … | ✅ **齐备**（`libbpf` 上游没有独立 `struct_ops.c`，struct_ops 支持在 `libbpf.c` 内 —— **未验证**本树 libbpf 是否含 `bpf_map__attach_struct_ops`）|
| `tools/testing/selftests/bpf/` | 目录存在（`bench.c` / `btf_helpers.c` / `bpf_testmod` …）| ✅ 可作参考 |

### 2.3 关键步骤：用**我们内核的 BTF** 生成 `vmlinux.h`

```
# 1) 构建 bpftool（源码在树里）
# 2) 从我们的 vmlinux 生成 vmlinux.h
bpftool btf dump file /home/builder/kwork/out-core/vmlinux format c > vmlinux.h
# 3) 用这份 vmlinux.h 编译 BPF 调度器（clang -target bpf）
```

**这一步是「针对我们内核编译」的全部要害。**（若改用 `bpftool btf dump file /sys/kernel/btf/vmlinux` 在设备上取，效果等同，但只能由 captain 做。）

### 2.4 其他

- `/sys/fs/bpf` pin：**可选**。不 pin 也能跑，只要 loader 进程活着（link 由 loader 持有）。
- `SCX_OPS_*` 版本号：**我们树里没有版本号字段**（v1 ABI 无 `SCX_OPS_VERSION`）—— 【未验证】mainline 6.12 是否有；若有而我们没有，则 mainline 编译的调度器会报版本不匹配。
- `BPF_F_*` 标志：**不需要**特殊标志。

---

## 3. Q3：aarch64 的官方调度器从哪来？

### 3.1 结论：**没有可直接用的现成 aarch64 产物；也没有任何 tag 与本机 ABI 匹配**

- `github.com/sched-ext/scx` 的 tag（如 `v1.0.19`）全部面向 **mainline 6.12+** ABI；我们树是 **v1（pre-6.12）** ⇒ **没有 tag 能开箱匹配**（§1）。
  【未验证】是否存在与 v6.11-v1 同期的老 commit 可直接用；即使有，也需自行验证 kfunc 集合。
- scx 上游 release 是**源码**，不发布 aarch64 预编译二进制（【未验证】是否有第三方 aarch64 包）。

### 3.2 ★推荐获取/构建路径（按顺序）★

| 步 | 做什么 | 为什么 |
|---|---|---|
| 1 | 构建 `bpftool`（源码在树里）| 生成 `vmlinux.h` + 后续 `bpftool struct_ops register` |
| 2 | `bpftool btf dump file out-core/vmlinux format c > vmlinux.h` | **拿到我们内核的真实布局** |
| 3 | **自己写一个最小 BPF 调度器**（~100 行：只实现 `enqueue` + `dispatch`，全部任务直投 `SCX_DSQ_GLOBAL`，`flags = 0`，`timeout_ms` 默认）| 验证整条链，且**只依赖最老的 kfunc**（`scx_bpf_dispatch` 在 ext.c:3676 存在）|
| 4 | `clang -target bpf -O2 -g -c min.bpf.c -o min.bpf.o`（实测 **可用**：clang 18.1.3，`-target bpf` 生成了 .o）| BPF 字节码**与架构无关** |
| 5 | `bpftool struct_ops register min.bpf.o` | 走官方入口 |
| 6 | 验证通过后，再考虑移植 `scx_central` / `scx_rusty`（kfunc 依赖少），最后才 `scx_lavd` | 现代调度器依赖 6.13/6.14 kfunc，我们树上会加载失败 |

### 3.3 交叉编译可行性（**已在 WSL 实测**）

| 项 | 实测结果 |
|---|---|
| `clang` | 18.1.3（`/usr/bin/clang`）|
| `clang -target bpf -c` | **✅ 可用**（实测生成 `/tmp/t.o`，520 B）|
| `aarch64-linux-gnu-gcc` | **✅ 存在**（`/usr/bin/aarch64-linux-gnu-gcc`）|
| aarch64 sysroot | **✅ 存在**（`/usr/aarch64-linux-gnu/{bin,include,lib}`）|
| `pahole` | ✅（`/usr/bin/pahole`）|
| `bpftool` | ❌ 未安装 ⇒ **需从树里构建**（源码齐备）|
| loader 架构 | **必须 aarch64**（BPF 程序本身与架构无关，只有 loader 需要）|

⇒ **交叉编译可行**：BPF 目标用 `clang -target bpf`；loader 用 `aarch64-linux-gnu-gcc` + 树内 libbpf。

---

## 4. Q4 ★最关键：opt43 的「注册 scx = 硬挂」是否适用于官方 BPF 调度器？★

### 4.1 两条路的逐项对比（**结论：不同，不能迁移**）

| 维度 | OPPO 路径（opt43 挂的那条）| 官方 sched_ext（BPF struct_ops）|
|---|---|---|
| **入口** | ROM 模块调用内核导出的 `register_hmbird_sched_ops()` / `register_walt_ops()`（**普通 C 函数调用**）| **bpf 系统调用**：`BPF_PROG_LOAD`（`BPF_PROG_TYPE_STRUCT_OPS`，bpf.h:993）→ `BPF_LINK_CREATE`（bpf.h:912）绑定 struct_ops |
| **注册对象** | OPPO 自定义表（`struct hmbird_ops` / `struct scx_sched_gki_ops`，见 t17 §3）| **`struct bpf_struct_ops bpf_sched_ext_ops`**（ext.c:3372-3380），`.name = "sched_ext_ops"`，由 **BPF 验证器 + BTF** 驱动 |
| **内核侧启用函数** | OPPO 的 `ext_ctrl()` → `bpf_hmbird_reg()`（我们树 `hmbird.c:4837`）| `bpf_scx_reg()`（ext.c:3346-3349）→ `scx_ops_enable()`（ext.c:2944）|
| **卸载/失败回退** | OPPO 自己的 disable work | `bpf_scx_unreg()`（ext.c:3351-3355）→ `scx_ops_disable(SCX_EXIT_UNREG)`；**外加内核 sysrq-S**（ext.c:3382-3395）|
| **是否依赖 WALT** | **是**（读 `walt_rq+0xa0` 等；见 t17 §1.3）| **否**（BPF 调度器自己算 util，用 `scx_bpf_*`）|
| **用户是否可编程** | 否（OPPO 固定实现）| **是**（任意 BPF 调度器）|

### 4.2 结论

**opt43 的结论不能直接迁移。** 理由：入口机制（C 函数调用 vs bpf 系统调用 + BTF 验证）、注册对象（OPPO 自定义表 vs `bpf_struct_ops`）、内核侧启用函数（`bpf_hmbird_reg` vs `bpf_scx_reg`）**三者都不同**，
⇒ 「注册 OPPO 的 scx 表会硬挂」**不蕴含**「注册官方 BPF struct_ops 会硬挂」。

### 4.3 ★但也不能反推官方路径一定安全（这是核心未知）★

两条路**共有的风险区**：都要经历「把任务从 CFS 切到新 sched_class」的切类循环 + 放置决策。
如果 opt43 的硬挂根因在**切类/放置**而不是在「OPPO 表本身」，那官方路径**同样会挂**。
⇒ 【未验证】这是本评估**唯一无法从源码判定的问题**，也正是必须先做 §6 E1 的理由。

---

## 5. Q5：失败安全

### 5.1 ★先纠正任务书里的一个假设★

任务书问「`/sys/kernel/sched_ext/enabled` 写 0 回退？」—— **不行**：
`ext.c:4219-4220`：`static struct kobj_attribute scx_attr_enabled = __ATTR(enabled, 0444, scx_enabled_show, NULL);`
`ext.c:4227-4228`：`__ATTR(switched_all, 0444, scx_switched_all_show, NULL);`
⇒ **两个属性都是 0444（只读）**，只能读不能写。

### 5.2 真正的回退手段（按优先级）

| # | 手段 | 机制（文件:行号）| 备注 |
|---|---|---|---|
| **1** | **`echo s > /proc/sysrq-trigger`** | `sysrq_handle_sched_ext_reset()`（ext.c:3382-3388）→ `scx_ops_disable(SCX_EXIT_SYSRQ)`；`action_msg = "Disable sched_ext and revert all tasks to CFS"`（ext.c:3393）；`.enable_mask = SYSRQ_ENABLE_RTNICE`（ext.c:3394）| ★需先 `echo 1 > /proc/sys/kernel/sysrq`（captain 已实测 sysrq 可用）★ **这是内核内建、不依赖用户态的应急出口** |
| 2 | **释放 bpf_link**：杀掉 loader 进程 / `bpftool struct_ops unregister` | `bpf_scx_unreg()`（ext.c:3351-3355）→ `scx_ops_disable(SCX_EXIT_UNREG)`；`SCX_EXIT_UNREG` 在 ext.c:2711 有分支 | loader 活着才有调度器 ⇒ **进程一死就自动回退** |
| 3 | 重启 / 卸载模块 | —— | 最后手段 |

### 5.3 内核自带的兜底保护

`scx_ops_error_type(SCX_EXIT_ERROR_STALL, ...)`（ext.c:2235）：**runnable 任务超过 `ops.timeout_ms` 未被调度 ⇒ 内核自己检测并禁用调度器**。
⇒ 即使 BPF 调度器写错，也不会无限期饿死任务（这是 t142 里我们 hmbird 那条 `failed to run for 58.016s` 的**通用形态**）。

### 5.4 会不会像 opt43 那样挂到需要 PMIC 复位？

**【未验证】**。结构上有两点比 OPPO 路径好：
① 官方路径有**内核内建的 sysrq-S**（不依赖 OPPO 的 disable work 是否还能跑）；
② 失败时 `scx_ops_disable` 会把任务**回退 CFS**（ext.c:3393 的 action_msg 原文）。
★但若失败发生在**持 rq 锁的切类循环里**，sysrq-S 也未必能跑 —— 这条与 §4.3 是同一个未知，**必须靠实验排除**。

---

## 6. 明确结论：可行 / 不可行 / 先做哪个实验

### 6.1 结论：**可行（推荐），但必须先做 E1**

理由：
1. 内核侧**全部前提已具备**（§2.1，含 `.BTF` 段与 `bpf_sched_ext_ops`）；
2. 用户态工具链**在树里齐备且已在 WSL 实测可编译**（§3.3）；
3. opt43 的结论**不适用**于官方路径（§4.2）；
4. 官方路径有**内核内建的失败回退**（sysrq-S + link 释放 + stall 兜底，§5）；
5. 它**不依赖 WALT**（用户明确要求的：不要帧率感知那套）。

### 6.2 ★必须先做的实验 E1（唯一阻塞项，零源码改动）★

**E1：写一个最小 BPF 调度器并用官方入口加载。**

| 项 | 内容 |
|---|---|
| 内容 | ~100 行 BPF：只实现 `enqueue` + `dispatch`，全部任务 `scx_bpf_dispatch(p, SCX_DSQ_GLOBAL, SCX_SLICE_DFL, 0)`；`flags = 0`；`name = "min"`；不实现 `select_cpu`（用内核默认，需 `SCX_OPS_KEEP_BUILTIN_IDLE`，见 ext.c 的 flag）|
| 编译 | `bpftool btf dump file out-core/vmlinux format c > vmlinux.h` → `clang -target bpf -O2 -g -c min.bpf.c -o min.bpf.o` |
| 加载 | `bpftool struct_ops register min.bpf.o`（或 libbpf skeleton）|
| 判据① | `cat /sys/kernel/sched_ext/enabled` 变成 **1**（只读也能读）|
| 判据② | 设备**不挂**、`running` 正常、`echo s > /proc/sysrq-trigger` 之后 `enabled` 回 **0** |
| 判据③ | 卸载 loader 后 `enabled` 自动回 0 |
| **三条同时满足** | ⇒ 官方路线打通 ⇒ 再谈移植 `scx_central` / `scx_rusty`，最后才是 `scx_lavd` |
| **E1 就挂** | ⇒ 说明「切类/放置」是共有风险，官方路线也走不通 ⇒ **回到 opt144**（t17 §5.3）|

★ E1 的安全性设计（必须在 captain 执行前确认）★：
- 加载前先 `echo 1 > /proc/sys/kernel/sysrq`（否则 sysrq-S 静默无输出）；
- 前台跑、不要 `nohup &`（与 t142 的教训一致）；
- **不要**同时开 tracepoint / 循环 dmesg（t150 的教训：观测开销本身会造成卡死）；
- 先确认 `/sys/kernel/sched_ext/enabled` 可读且为 0；
- 准备物理回退（captain 的刷机流程）。

### 6.3 三条路线对比

| 维度 | 官方 sched_ext（BPF struct_ops）| 继续修移植（opt144）| 隔离我们的 hmbird_sched_class（t17 §5.4）|
|---|---|---|---|
| 工作量 | **中**：写/移植一个 BPF 调度器 + 工具链（bpftool/libbpf 树里已有）| 小：换 util 源 1 行 + task util 3 行 + 去 slim_walt 1 行 + 回滚 opt142 1 行 | 未知（阻塞在 E5）|
| 风险 | **中**（E1 若挂则可能硬挂；但有 sysrq-S + stall 兜底）| 中低（不碰唯一被证明会挂的路径）| 未知 |
| 可回退性 | **好**（sysrq-S / 杀 loader / 重启；enabled 只读但不需要写）| 好（单提交可退，失败时 util=0 与今天一致）| 未知 |
| 依赖 WALT | **否**（用户明确要求）| 否（但仍在 OPPO 的 class 框架里）| **是**（ROM 的 WALT）|
| 能否达成用户目标 | **最可能**（用户明确点名这条路）| 能（8 核铺开 + 稳定）| 不能（仍依赖帧率感知 util）|
| 阻塞项 | **E1 最小调度器实验** | 无（已编好待上机）| **E5**（拉 `oplus_bsp_sched_assist.ko`）|

---

## 附录 A：本文用到的只读命令

```bash
# 版本判据
ls include/uapi/linux/sched/                                   # 只有 types.h ⇒ pre-6.12
grep -n 'SCX_ENQ_WAKEUP' kernel/sched/ext.h                   # = ENQUEUE_WAKEUP（内部别名）
grep -n 'scx_ops_enable(' kernel/sched/ext.c                  # 2944，无 bpf_link
grep -n 'bpf_sched_ext_ops' kernel/sched/ext.c                # 3372-3380，name=sched_ext_ops
# 工具链
ls tools/bpf/bpftool/struct_ops.c tools/lib/bpf/libbpf.c      # 均在
clang -target bpf -c /tmp/t.c -o /tmp/t.o                     # 可用
which aarch64-linux-gnu-gcc                                   # 存在
# BTF
readelf -S out-core/vmlinux | grep -i btf                     # .BTF / .BTF_ids
# 回退手段
grep -n '__ATTR(enabled, 0444' kernel/sched/ext.c             # 4220 只读
grep -n 'sysrq_handle_sched_ext_reset' kernel/sched/ext.c     # 3382-3395
grep -n 'bpf_scx_unreg' kernel/sched/ext.c                    # 3351-3355
```

## 附录 B：本文的【未验证】项汇总

| # | 未验证项 | 怎么验 |
|---|---|---|
| 1 | mainline 6.12 是否真的有 `include/uapi/linux/sched/ext.h`（我用的是外部知识 + 上游文档，未在本地核对）| 拉一份 6.12 源码树比对 |
| 2 | 树内 libbpf 是否含 `bpf_map__attach_struct_ops` | `grep -n bpf_map__attach_struct_ops tools/lib/bpf/libbpf.c` |
| 3 | `scx` 上游是否有与 v1 ABI 同期的可用 commit | 查 `sched-ext/scx` 早期 tag/commit + 试编译 |
| 4 | 是否存在 aarch64 预编译 scx 包 | 查发行版仓库 |
| 5 | **opt43 的硬挂根因是否在「切类/放置」（若是，官方路径同样会挂）** | **E1 实验** |
| 6 | `scx_ops_disable` 在持锁切类循环中是否还能跑（决定 sysrq-S 是否有效）| **E1 实验** |
| 7 | 我们树是否有 `SCX_OPS_VERSION` 之类的版本号字段 | `grep -rn SCX_OPS_VERSION include/ kernel/sched/` |
