# 更正：page_cluster 的成因、RCU_NOCB 的空操作、HybridSwap 没编（2026-10-03）

> ⚠️ 本文更正**三条我们自己的错误认知**。三条都属同一类毛病：
> **把"看起来相关的两个东西"当成因果关系，没有读源码上下文。**

---

## 一、更正 1：`page_cluster` 与 `swappiness` **无关**

### 我错在哪
我在排查时说"`mm/swap.c:1113/1115` 会**按 swappiness 自动改写** `page_cluster`"。
**这是误读** —— 我只 grep 到了那两行赋值，没读上下文。

### 源码真相（`mm/swap.c:1107-1121` 原文）
```c
void __init swap_setup(void)
{
	unsigned long megs = totalram_pages() >> (20 - PAGE_SHIFT);

	/* Use a smaller cluster for small-memory machines */
	if (megs < 16)
		page_cluster = 2;
	else
		page_cluster = 3;
}
```

| 事实 | 依据 |
|---|---|
| 它是 **`__init`**（只在启动跑一次，运行期不再改） | `mm/swap.c:1107` |
| 条件是**内存 MB 数**（`<16` → 2，否则 → 3），**不是 swappiness** | `mm/swap.c:1109-1115` |
| `swappiness` 是**完全另一个变量** `vm_swappiness`（`mm/vmscan.c:202`，编译期默认 60） | 两者无任何代码关联 |
| **全部写入点只有那两行** | `grep -rn 'page_cluster *=' mm/` 只返回 `1113`/`1115` |
| `page_cluster` **不在导出表** ⇒ 任何 `.ko` 都写不了它 | `vmlinux.symvers` 0 命中、厂商真引用名 0 命中 |
| sysctl **无上界钳位**（只有 `extra1=SYSCTL_ZERO`，无 `extra2`） | `kernel/sysctl.c:2121-2128` |

⇒ 本机 16 GB ⇒ 内核启动时把 `page_cluster` 设为 **3**；而**厂商用户态把它写成 0**（那才是实际值）。

### 推论（★ 这条最重要）
既然 `CONFIG_CONT_PTE_HUGEPAGE=n`（见更正 3），走的是**上游路径**：
```c
mm/swap_state.c:582   max_pages = 1 << READ_ONCE(page_cluster);
mm/swap_state.c:584   if (max_pages <= 1) return 1;        ← page_cluster=0 时【预读被禁】
mm/swap_state.c:738   max_win = 1 << min_t(unsigned int, READ_ONCE(page_cluster), SWAP_RA_ORDER_CEILING);
mm/swap_state.c:741   if (max_win == 1) { ra_info->win = 1; return; }   ← 同样早退
```
⇒ **厂商把 `page-cluster` 设成 0，正是用 sysfs 达到"禁掉换入预读"的目的。**
而厂商自己在 `swap_state.c:729-733` 写明了理由：
> 「readahead on zram1 will lead to **swap leak** as swapout only calls
> `swap_alloc_cluster` which doesn't reclaim readahead swapcache」

⇒ **把 `page-cluster` 改成 2 = 重新打开厂商刻意关掉的那条会泄漏的路径。**
**这是有害的，不是优化。** ⛔ 不要做。

---

## 二、更正 2：`RCU_NOCB_CPU_DEFAULT_ALL=y→n` 是**空操作**

### 我错在哪
我在 opt37 里说这项能"省 8×3 个 `rcuo/N` kthread"。**错的。**

### 源码真相（`kernel/rcu/Kconfig:267-278` 原文）
```
config RCU_NOCB_CPU_DEFAULT_ALL
	bool "Offload RCU callback processing from all CPUs by default"
	depends on RCU_NOCB_CPU
	default n
	help
	  Use this option to offload callback processing from all CPUs
	  by default, **in the absence of the rcu_nocbs or nohz_full boot
	  parameter**. ...
```

⇒ **该选项只在没有 `rcu_nocbs=` / `nohz_full=` 启动参数时才起作用。**
本机实测有 10 个 `rcuo/N` kthread ⇒ **说明设备上存在这类 bootarg**（ColorOS 加的）
⇒ **改这个 config 完全不影响运行时**（改前改后都由 bootarg 决定）。

⇒ 所以 opt37 的那一项：**相对 opt36 是"撤掉了我们自己多开的一项"，但相对运行时收益 = 0。**
（子代理给的判据"`rcuo` 数 0 vs 24"**本身是错的** —— 它受 bootarg 支配，与 config 无关。）

### 可用的正解
`CONFIG_IKCONFIG=y` + `CONFIG_IKCONFIG_PROC=y`（**原厂也开着**）
⇒ **`/proc/config.gz` 就是运行内核的真实 config** —— 这是唯一能绕开"两个真值源不一致"的对账手段。
**插机后第一件事就该做这个对账**（`zcat /proc/config.gz | grep ...`）。

---

## 三、更正 3：**HybridSwap / 连续 PTE 大页【根本没编进内核】**

### 子代理的误判
它建议"深挖 HybridSwap 换入路径"，理由是"本机树里有 HybridSwap、`mm/cont_pte_hugepage.c` 存在、
`current_is_hybridswapd()` 被 `mm/vmscan.c` 调用"。**代码存在 ≠ 代码编入。**

### 实测真相
```
CONFIG_CONT_PTE_HUGEPAGE = n         （真原厂也是 n）
mm/Makefile:159   obj-$(CONFIG_CONT_PTE_HUGEPAGE) += cont_pte_hugepage.o    ← 展开为空
mm/vmscan.c:7242  #if defined(CONFIG_CONT_PTE_HUGEPAGE) && CONFIG_POOL_ASYNC_RECLAIM   ← 整块被排除
out/mm/cont_pte_hugepage.o                                                ← 【不存在】
```
⇒ 那个 94 KB 的 `mm/cont_pte_hugepage.c` 是个**死文件**；
`swap_state.c` 里两处 `#ifdef CONFIG_CONT_PTE_HUGEPAGE` 也是**死的**；
`include/linux/mm.h:4663` 的 `extern inline bool current_is_hybridswapd(void);` 只是**无定义的声明**（没人调，所以不报链接错）。

### 教训
**"文件在树里"、"符号被引用"、"有 #ifdef" 都不能推出"代码在跑"。**
⇒ 判"本机走不走得到"必须同时看：① `out/.config` 的开关 ② **`out/` 下有没有对应 `.o`** ③ 调用点有没有被 `#ifdef` 排除。

---

## 四、这三条更正对"下一步"的影响

| 原建议 | 核验后 |
|---|---|
| 深挖 HybridSwap 换入路径 | ❌ **没有靶子**（代码未编入） |
| 试 `page-cluster 0→2` | ⛔ **有害**（重开厂商刻意关掉的 swap leak 路径） |
| `RCU_NOCB` 省 kthread | ⚪ **空操作**（bootarg 支配） |
| `/proc/config.gz` 对账 | ✅ **有效**，且是唯一可信的运行时 config 来源 |
| `UBSAN_BOUNDS` 加回来对冲静默重启 | 🟡 待评估（与 opt37 的性能方向相反，需权衡） |

⇒ **靶子重新选为 `net/netfilter`**（117 个 `.o` 已编入、上一轮完全没碰过、本机 iptables/ipset/conntrack 真在跑）。
