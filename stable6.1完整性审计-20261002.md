# stable 6.1 完整性审计（2026-10-02）· 上游覆盖到底差多少

> 起因：ACK 权威源被网络阻断（详见 `ACK第三轮-网络受阻与CONFLICT考古-20261002.md`），
> 转而用**国内镜像可达**的 stable 增量补丁，做一次**逐文件完整性审计**。
> 结论：**我们的 stable 覆盖基本完整，但漏了 6 条可安全补回的 `.c`；另有 462 个
> 头文件改动是当年的刻意留白。**

---

## 一、stable 6.1 已封顶：**6.1.188 是最后一个版本**

三个独立镜像交叉验证一致：

| 镜像 | 6.1.x 最大 | 补丁总数 |
|---|---|---|
| mirrors.tuna.tsinghua.edu.cn | **6.1.188** | 188 |
| mirrors.aliyun.com | **6.1.188** | 188 |
| mirrors.bfsu.edu.cn | **6.1.188** | 188 |

`incr/` 目录最新增量也是 `patch-6.1.187-188.xz`。

**⇒ stable 6.1 线已到顶，没有更新的可拿。**

### 附带发现：**我们在 stable 上领先 ACK 的 LTS 分支**

ACK `android14-6.1` tip（2026-09-29）的提交信息写着 **"Steps on the way to 6.1.178"**
—— 即 ACK 才合到 6.1.177 附近，**而我们已经拿到 6.1.188**。
所以 ACK 分支上剩下的价值只在它**私有的** `ANDROID:`/`BACKPORT:`/`FROMGIT:` 提交
（vendor hook、GKI KMI、符号表），那些**只在 googlesource 上**，必须走代理。

---

## 二、审计方法

1. 从清华镜像下载 `patch-6.1.141-142.xz` … `patch-6.1.187-188.xz` **共 47 个**（3.39 MB）；
2. 按 `diff --git` 切成**文件块**（共 10,595 块）；
3. 只保留**本机真参与编译**的（`compiled_deps.txt`，3,915 个路径）且树里存在的 → **566 块**；
4. 逐块判定：
   - `git apply -R --check` 成功 ⇒ **已有**（反向能打）
   - `git apply --check` 成功 ⇒ **缺失**（正向能打）
   - 都不行 ⇒ **上下文不符**（厂商树分歧）

---

## 三、审计结果

```
判据集(本机真编译) = 3,915 个文件
总文件块            = 10,595
纳入判定            =    566

  ✅ 已有(能反向打)     =  24
  ★ 缺失(能正向打)     = 471   <- 纯 .c 9 个, .h 462 个
  ? 上下文不符(都不行) =  71
```

### ★ 缺失的 9 条纯 `.c`（零 CRC 风险）

| stable | 文件 | 处置 |
|---|---|---|
| 6.1.142 | `sound/usb/mixer_maps.c` | ✅ **已补（P13）** |
| 6.1.147 | `kernel/sched/loadavg.c` | ✅ **已补（P13）** |
| 6.1.151 | `kernel/sched/cpufreq_schedutil.c` | ✅ **已补（P13）** |
| 6.1.157 | `kernel/sched/deadline.c` | ✅ **已补（P13）** |
| 6.1.176 | `kernel/sched/rt.c` | ✅ **已补（P13）** |
| 6.1.188 | `kernel/sched/cpufreq_schedutil.c` | ✅ **已补（P13）** |
| 6.1.160 | `kernel/sched/topology.c` | ⛔ 放弃：需 `struct sched_domain` 的 `newidle_call/success/ratio` 字段。试过补 `kernel/sched/sched.h`（6.1.147 的那块），但**字段定义在另一个头**，仍报 `does not refer to any field` ⇒ 已撤销 |
| 6.1.184 | `fs/binfmt_elf.c` | ⛔ 放弃：需 `include/linux/fs.h` 的 `exe_file_allow_write_access`。`fs.h` 是**导出类型头**，动了 CRC 必漂 |
| 6.1.188 | `sound/core/control_compat.c` | ⛔ 放弃：需 `include/sound/control.h` 的 `snd_ctl_find_id_locked`，同类风险 |

### 462 个 `.h` —— 当年**刻意**留白，不是漏

opt10/11/12 的收割判据是"**只挑纯 `.c`**"。理由已被 opt15 那次翻车实证：
**改头文件 ⇒ genksyms 重算 ⇒ CRC 漂移 ⇒ 厂商 `.ko` 全部拒载**（那次 9 个模块挂掉、
`lsmod` 621→607、WiFi/蓝牙全废）。

但这也带来一个**连带效应**：
**依赖头文件改动的那些 `.c` 会被一并跳过** —— 上面那 9 条正是这么漏掉的
（`binfmt_elf.c` 要 `fs.h`、`control_compat.c` 要 `sound/control.h`、`topology.c` 要 `sched_domain` 新字段）。

### 71 条"上下文不符"

厂商树在这些文件上已与上游分歧，正反都打不上。分布：
`include/linux` 29、`include/net` 13、`drivers/usb` 4、`fs/f2fs` 3、`drivers/hid` 3、
`kernel/sched` 2、`drivers/pci` 2、`net/netfilter` 2 …

---

## 四、❌ 更正：那 462 个头文件**不可信，这条路已关闭**（2026-10-02 17:1x 实测）

> 下面这段原本写着"462 个头文件是唯一大块机会"。**实测后推翻了。**

### 实测过程

把 462 个头文件块 + 50 个新建文件全部应用（462/462、22/22 都"成功"），构建：

```
make rc=2   错误行 = 1309
  --- 错误文件 top ---
     966  include/net/dst.h          ← 一个文件占 74%
      19  fs/ext4/extents.c
      17  net/packet/af_packet.c
      15  fs/crypto/keyring.c
      14  drivers/nvdimm/region_devs.c
      12  net/core/rtnetlink.c / net/core/dev.c / drivers/mmc/core/card.h
      10  kernel/bpf/cgroup.c
      ...
```

典型错误：
```
../include/net/dst.h:571:34: error: redefinition of 'dst_dev_rcu'
../net/socket.c:1148:6: error: conflicting types for 'brioctl_set'
../init/main.c:329:19: error: static declaration of 'xbc_snprint_cmdline' follows non-static declaration
```

### 根因：**审计的"缺失"判定有系统性误报**

```
HEAD 的 include/net/dst.h:346  =  static inline struct net_device *dst_dev_rcu(...)   ← 本来就有
补丁块 0160__include__net__dst.h.patch  =  +static inline ... dst_dev_rcu(...)        ← 再加一遍
```

`git apply --check` 通过，是因为**补丁的上下文行在文件别处也匹配上了** ——
**git 只做文本匹配，不察觉语义重复**，于是插进去变成重复定义。

抽查全部吻合：`net/socket.c` 的 `brioctl_set` / `br_ioctl_call`、`init/main.c` 的
`xbc_snprint_cmdline`，**HEAD 里都已经有**（厂商树早就 backport 过）。

### ⇒ 结论

| 数字 | 可信度 |
|---|---|
| 缺失 **9 条纯 `.c`** | ✅ **可信** —— 是经过"实际应用 + 编译通过"验证的（P13） |
| 缺失 **462 个头文件** | ❌ **不可信** —— 大量是"本就有、只是位置/写法不同"的误报 |

**这条路关闭**，理由有三，任何一条都足够：
1. **分类不可信** —— 无法自动区分"真缺失"与"本就有"；
2. **成本极高** —— 966/1309 的错误集中在一个文件上，说明批量应用本质上是错的；
3. **风险已知** —— 其中 42 个是导出类型头（`struct rq` 那次实测：改布局 = 47 个厂商模块拒载）。

**⇒ 若要真做，只能人工逐条比对（像 OPTION 那样读补丁 + 读源码），不是自动化能解决的。**

---

## 五、本轮的净产出（更正后）

| 项 | 值 |
|---|---|
| 提交 | `d4fe9dd36`，tag `opt15-p13` |
| 镜像 | `images\boot-opt15-p13-repacked.img`，md5 `bbe3481dfca37a9887a0b49c53696edc` |
| 横幅 | `#46-ack138-p13` |
| 内容 | P11 的 6 条 ACK CONFLICT 修复 **+ 6 条 stable `.c`** |
| 双闸门 | 闸门1 PASS（新增=22 消失=0，命中厂商 0/0）；闸门2 仅 `bluetooth.ko`（基线就不符） |
| 刷后核验 | `lsmod` **621**、`wlan0` UP、`panic=30`、厂商调度栈正常 |

**回退**：`boot-opt15-p11-repacked.img`（`57df6d0b…`，只含 ACK 那 6 条）或
`boot-opt15-p5-repacked.img`（`62306073…`，都不含）。

---

---

## 六、⚠️ 事故与修复：P13 引入 `/proc/loadavg` 爆表（P16 修掉）

> **这是本轮最重要的教训：stable 补丁里有"成对改动"，只应用一半会引入新 bug。**

### 现象（机主发现）

P13 刷入后 `/proc/loadavg` 读到：

```
17178707395.13  15516887674.86  9122173460.12   ← 且在持续上涨（约 +5.4e3/秒）
```

三个值还反常地"越慢的涨得越快"（15-min 涨得比 1-min 快）—— **结构上就不可能**，是真坏了。

### 定量定位

```
4 × (2^32 − 1) = 4 × 4294967295 = 17179869180
实测刷前值        =              17179868226   ← 只差 954
```
⇒ **4 个 cluster 的 `nr_uninterruptible` 都存着 `0xFFFFFFFF`（语义上的 −1），而被当成 +4294967295 累加。**

### 根因：上游 6.1.147 的修复是**一对**

```c
// kernel/sched/sched.h   ← 这一半在"462 个缺失头文件"池里，没跟着应用
-	unsigned int		nr_uninterruptible;
+	unsigned long 		nr_uninterruptible;

// kernel/sched/loadavg.c ← P13 只应用了这一半
-	nr_active += (int)this_rq->nr_uninterruptible;
+	nr_active += (long)this_rq->nr_uninterruptible;
```

`unsigned int` 存 −1 是 `0xFFFFFFFF`：`(int)` 截回 −1（正常），`(long)` 变成 +4294967295（爆炸）。

### 为什么不能"补上另一半"（试过，被闸门拦下）

把 `nr_uninterruptible` 改成 `unsigned long` **会改变 `struct rq` 的内存布局**，实测：

| | 会拒载的厂商模块 | 漂移符号 |
|---|---|---|
| 补齐 `.h`（改 `struct rq`） | **1 → 47** | **16 个** |
| 退回 `.c`（P16 的做法） | **1**（仅 bluetooth，基线就不符） | 0 |

漂移符号全在调度器导出面：
`runqueues`、`update_rq_clock`、`task_rq_lock`、`raw_spin_rq_lock_nested`、`raw_spin_rq_unlock`、
`balance_push_callback`、`sched_setattr_nocheck`、`wake_up_process`、`sched_setscheduler(_nocheck)`、
`set_user_nice`、`set_cpus_allowed_ptr`、`sched_show_task`、`sched_set_fifo`、`sched_set_normal`

其中 **`oplus_bsp_sched_ext.ko`（7 个符号）和 `oplus_bsp_game_opt.ko` 直接操作 `runqueues`**
⇒ **厂商的 WALT / sched_ext 栈依赖 `struct rq` 的确切布局，这个字段动不得。**

### 处置（P16）

```
sched.h  保持厂商的 unsigned int        ← struct rq 布局零改动
loadavg.c cast 退回 (int)               ← 原厂行为
```

只改 1 行。刷后 `/proc/loadavg` = `36.76 8.85 2.95` → `29.91 9.14 3.17`（1-min 衰减最快、15-min 最平缓，形态正确）。

### 📌 教训（写进流程）

1. **stable 补丁有"成对改动"（`.c` + `.h`）时，必须成对应用，或成对放弃。** 只应用 `.c` 那半边是我 P13 犯的错 —— 根源是审计把 `.h` 单独归进了"462 个头文件池"，割裂了配对关系。
2. **改 `struct rq` / `struct task_struct` 这类中枢结构体 = 动整个调度器导出面的 CRC。** 这类头文件改动**在只刷 `boot_a` 的约束下不可用**，无论上游有没有修。
3. **CRC 真值闸门再一次证明了价值** —— 47 vs 1 这个数字是它给的，不是推理出来的。
4. 副产品：这次顺带**实测到了 `uag` 窗口**（`uptime=85s` 时 governor = `uag`），印证了 §"调速器"那节的模块加载顺序推断。

---

*记录：2026-10-02 17:1x*

