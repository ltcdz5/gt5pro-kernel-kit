# 内核审核 A —— 存储与内存栈（fs/f2fs、fs/ext4/jbd2、mm、block/SSG、drivers/ufs、LZ4/Zstd、相关 config）

设备：Realme GT5 Pro (RMX3888 / SM8650 / Android 16 / ColorOS 16)
树：`/home/builder/kwork/cctv18/repo/local/kernel_workspace/common`，HEAD = `5ddf8408b29a` (v1.1-opt47)，基线 `7a244ff18620`
方法：静态代码审计（**设备离线**：`adb devices` 返回空 "List of devices attached"，未尝试唤醒/重启）+ git 逐提交核对 + 源码行号核对 + 汇编器语义实测（clang 18.1.3 aarch64，含**真实 .S 汇编成 .o 后的反汇编对比**）+ 与机主自带 `refs/stock_config.gz`（原厂配置，7585 行）对照。
**修订说明（v3）**：v1/v2 的 A-01（LZ4 标签捕获）经 Lead 指出并由我方用真实 .o 反汇编复核后，**确认是误报，已撤回**；证据与错误原因见 §2 与 §6。请以本版为准。

---

## 1) 结论摘要（按严重度）

1. **【P2 · 已确证，但需 root 主动写 sysfs】opt15-P32 对 f2fs 压缩 `log_cluster_size` 的上界收紧漏掉了 sysfs 入口** —— `fs/f2fs/sysfs.c:783` 仍允许写到 8（`MAX_COMPRESS_LOG_SIZE`），写进去后新建的压缩 inode 会得到 `i_cluster_size=256`，而 `di[]/rpages[]/cpages[]` 只有 8 项 ⇒ 读该文件时在**内核栈上**越界写约 1KB。**触发前提是"有 root 的进程主动往 `/sys/fs/f2fs/<dev>/compress_log_size` 写 8"**，普通应用/正常用户路径走不到；P32 新加在 `data.c` 的 `blkidx` 校验挡不住这一条（越界发生在填 `di[]` 时）。对应 A-02。
2. **【P2/P3 · 待实测】opt9 的 `VM_FAULT_RETRY_VMA`：生产者/消费者两半都在、位无冲突，但 filemap 侧的置位**没有** `FAULT_FLAG_TRIED` 闸门，与上游"退到 mmap_lock 重试"语义不同**，存在反复自旋（潜在活锁）面；同提交取入的 `fs/eventpoll.c`、`fs/pipe.c`、`include/linux/file.h`、`net/unix/garbage.c` 经核对是自洽的上游修复，**不引用**被剔除的 dtask/`test_task_ux`。对应 A-03/A-04。
3. **【P3 · 已确证】opt13/opt37 关掉的内存安全网，对照机主自带原厂配置是"从原厂有 → 改成没有"，不是"回到原厂"** —— 原厂 `stock_config.gz` 里 `UBSAN=y(TRAP/BOUNDS/LOCAL_BOUNDS/ARRAY_BOUNDS/SANITIZE_ALL)`、`INIT_ON_ALLOC_DEFAULT_ON=y`、`INIT_STACK_ALL_ZERO=y`、`KFENCE_SAMPLE_INTERVAL=500`、`KASAN=y(KASAN_HW_TAGS)` 全开；只有 `ZRAM_MEMORY_TRACKING`(n) 与 `RCU_NOCB_CPU_DEFAULT_ALL`(n) 这两项才是"我们多开过、退回原厂"。副作用是：A-02 这类数组越界失去了唯一的自动探测网。对应 A-05。
4. **【P3 · 已确证/待确认】三项次生问题**：`CONFIG_ZRAM=m` + 只能刷 boot_a ⇒ 本次对 zram/hybridswap 的 config 改动对实机**不生效**（实机 zram 核心是 OPPO vendor 模块）(A-06)；LZ4/Zstd 补丁包带进树的 61 个 `.rej/.orig` 在 opt45 被**删除而非逐个确认**，抽查 1 项已落地、50+ 个 `lib/zstd/**` 未穷尽 (A-07)；SSG 电梯在原厂配置里**根本不存在该符号**，属 owner 新引入 (A-08)。
5. **【已复核 · 未发现问题】**opt42 的 LZ4 修复**是正确的**（原 Permtable 越界读被消除，且与 pre-patch 逐分支等价 —— 已用真实 .o 反汇编对比确认，见 V-11）；opt15-P32 的 SSG 两处缺陷已修对；opt15-P30/P31 的 f2fs `dic_layout` 成套且不引入新 UAF；opt39 的 jbd2 搬家安全、ext4 `i_size` 校验的标志顺序正确；opt40 ext4 sysfs 锁两半到齐无死锁；opt36 UFS 三处形态与上游一致；opt12-clean/opt14-trim 退掉的 mm 文件确认**本机不编译**。

---

## 2) 发现清单

### 2.0 【已撤回 · 误报】A-01：opt42 的 LZ4 标签冲突（v1/v2 误判）

| 项 | 内容 |
|----|------|
| 原判 | "opt42 插入的新 `15:` 捕获了 :243 的 `b.hi 15b`，把 32B 前向拷贝循环改成错误路径" |
| **撤回结论** | **误报。该分支目标未变，opt42 的改动与 pre-patch 逐分支等价，且正确消除了 Permtable 越界读。** |
| 错误原因 | 我自己的最小实验其实已经否证了我的结论，我把结果映射反了：两个 `15:` 时，**后向引用 `15b` 解析到"最近的前一个"**。真实文件里 `:207` 是新标签（更靠前），`:237` 是原标签，`b.hi 15b` 在 `:243` ⇒ 最近的前一个是 **`:237`（原循环头）**，不是 `:207`。只有**前向**的 `b.hs 15f`(:202) 才会命中新标签 `:207`（正是本补丁想要的效果）。 |
| 真实 .o 反汇编证据（clang 18.1.3，`--target=aarch64-linux-gnu`；把 `lib/lz4/lz4armv8/lz4armv8.S` 与 `git show 77aa56a8024c^:…` 各自汇编成 .o 后 `llvm-objdump -d` 对比） | pre-patch（`/tmp/lz4_pre.o`）：`ldp q2,q3,[x11]`（读表）→ `tbl`×2 → `f100419f cmp x12,#0x10` → `54000043 b.lo 0x140`。post-patch（`/tmp/lz4armv8.o`）：新增 `f100419f cmp x12,#0x10` + `540000c2 b.hs 0x140` 在**读表之前**，读表后改 `14000002 b 0x144`。两版最终都到 `0x140: ldp q0,q1,[x9]` → `0x144`(等价于源码 `12:`)。**32B 前向拷贝循环末尾的 `b.hi` 在两版中机器码完全一致**（未被 diff 列出：源与目标同时后移 8 字节 ⇒ 立即数不变）。 |
| 最小复现（可自行跑） | `printf ".text\n.globl f\nf:\nnop\nnop\n15:\nnop\nnop\nnop\n15:\nnop\n b.hi 15b\n ret\n" > /tmp/t2.S; clang --target=aarch64-linux-gnu -c /tmp/t2.S -o /tmp/t2.o; llvm-objdump -d /tmp/t2.o` ⇒ `b.hi` 指向**第二个**（最近的）`15:`。 |
| 遗留说明 | 该 asm 确实是 **owner 引入**（基线 `git ls-tree 7a244ff18620 lib/lz4` 只有 upstream 四文件、无 `lz4armv8`），且在**本机编译进并默认使能**（`fs/f2fs/compress.c:13` → `include/linux/lz4.h:8` → `lib/lz4/lz4.h:76` → `lib/lz4/lz4armv8/lz4accel.h:6,41`；`arch/arm64/Kconfig:339-340` `KERNEL_MODE_NEON` 为 `def_bool y`；f2fs 默认布局 `COMPRESS_FIXED_OUTPUT`，见 `fs/f2fs/super.c:2217-2222`）。这条"引入第三方 NEON asm 到热解压路径"的**风险提示仍然成立**，但它不是已证缺陷。 |

### 2.1 发现表

| ID | 严重度 | 标题 | 证据（file:line / commit） | 触发条件 | 影响 | 建议 | 置信度 |
|----|--------|------|---------------------------|----------|------|------|--------|
| A-01 | —（**已撤回，误报**） | opt42 LZ4 标签冲突 | 见 §2.0：真实 .o 反汇编证明分支目标未变 | — | 无 | 无需改动 | **已否证** |
| A-02 | P2 | f2fs `compress_log_size` 上界收紧漏掉 sysfs 入口 ⇒ 栈/slab 越界仍可达（**需 root 主动写 sysfs**） | `fs/f2fs/sysfs.c:782-787`（仍 `> MAX_COMPRESS_LOG_SIZE`）；注册 `fs/f2fs/sysfs.c:1210,1347`（本机 `F2FS_FS_COMPRESSION_FIXED_OUTPUT=y`）；选项→inode `fs/f2fs/f2fs.h:4976-4991`；数组维度 `fs/f2fs/f2fs.h:1706,1734,1759-1763,1810-1811`；越界写 `fs/f2fs/data.c:2718-2735`（栈上 `cc->di[i]`，i<cluster_size）、`fs/f2fs/compress.c:2309-2312`；已收紧的三处 `super.c:1205`/`file.c:6240`/`inode.c:318`（commit `e1b638d4de99`） | **有 root 的进程**执行 `echo 8 > /sys/fs/f2fs/<dev>/compress_log_size`，然后新建压缩文件并读取 | 内核栈越界写约 248×4B；栈保护/邻接数据被破坏 ⇒ 崩溃或不可预测行为；`compress.c:2311` 同步 slab 越界读。**正常用户态路径不可达** | `fs/f2fs/sysfs.c:783` 改用 `MAX_SUPPORTED_COMPRESS_LOG_SIZE`；复核所有写 `F2FS_OPTION(sbi).compress_log_size` 的点 | 高（代码/config 已核）；可达性为中（需 root 主动操作） |
| A-03 | P2/P3 | `VM_FAULT_RETRY_VMA` 置位无 `FAULT_FLAG_TRIED` 闸门，与上游语义不同 | 定义 `include/linux/mm_types.h:946-950`（0x008000，无位冲突、不在 `VM_FAULT_ERROR`）；置位 `mm/filemap.c:3414-3420`（`fpin && FAULT_FLAG_VMA_LOCK`，无 TRIED 判断）、`mm/filemap.c:3467-3471`；`mm/memory.c:5313-5320`（do_swap_page 侧有 `fault_flag_allow_retry_first()`，含 `!(FAULT_FLAG_TRIED)`）；消费 `arch/arm64/mm/fault.c:604,633-634`。commit `206914f9cc64` | 用户态缺页走 lockless VMA 路径，且 filemap 需 `fpin`（放 mmap_lock 等 I/O） | 上游此情形直接 `lock_mmap` 取锁重试；此处继续 lockless 自旋；若同一 folio 反复 `fpin`，理论上可长时间重试（CPU 占用/活锁），未见"必然无限"证据（不持锁、可抢占、信号检查在前） | 置位处加 `!(vmf->flags & FAULT_FLAG_TRIED)`；或首轮后转 `lock_mmap` | 中（差异是事实，活锁未实测） |
| A-04 | P3 | opt9 取入的 eventpoll/pipe/file.h/unix-garbage **未发现**依赖被剔除的 dtask 基础设施 | `git show --stat 206914f9cc64`（14 文件）；`grep -n "task_ux\|dtask\|DTASK\|ux_task" fs/eventpoll.c fs/pipe.c include/linux/file.h net/unix/garbage.c` → **0 命中**；内容自洽：epoll 是上游 `ep_remove` 重构（`kfree_rcu(ep, rcu)`+`ep_remove_file()/ep_remove_epi()`）、`include/linux/file.h` 的 `DEFINE_FREE(fput,...)` 正是 epoll `__free(fput)` 的前提、pipe `kcalloc→kvcalloc`/`kfree→kvfree` 成对、garbage.c 增 `scc_index` | —（审查项） | 未发现语义缺口。**残余**：本机 vendor 树无 `ebdd1643c` 原提交，无法枚举"被剔除的 12 项" | 拿到 OPPO 原提交后逐文件比对 | 中（"无引用"高；"是否漏 hunk"低，缺证据） |
| A-05 | P3 | 四项内存安全/调试网被关，且**不是原厂状态** | 现树 `arch/arm64/configs/gki_defconfig:748-752,830-833,845-852`；原厂 `refs/stock_config.gz:6856-6859`(`INIT_STACK_ALL_ZERO=y`,`INIT_ON_ALLOC_DEFAULT_ON=y`)、`:7339-7350`(`UBSAN=y`+TRAP/BOUNDS/LOCAL_BOUNDS/ARRAY_BOUNDS/SANITIZE_ALL)、`:7402-7410`(`KASAN=y`,`KASAN_HW_TAGS=y`,`KFENCE_SAMPLE_INTERVAL=500`)；只有 `ZRAM_MEMORY_TRACKING`(refs:1903=n) 与 `RCU_NOCB_CPU_DEFAULT_ALL`(refs:158=n) 属"退回原厂"。commit `4e03a7d25409`、`48e095183986` | 常态 | 无直接故障；越界/UAF/未初始化读不再被拦，且失去"用真缺陷验证修复"的能力 | 至少把 KFENCE 采样恢复为原厂 500，或保留可切换的调试构建 | 高 |
| A-06 | P3 | `ZRAM=m` + 只能刷 boot_a ⇒ zram/hybridswap 侧的 config 改动不生效 | `gki_defconfig:325`(`CONFIG_ZRAM=m`)；原厂同 `=m`(refs:1896)、默认算法 `lzo-rle`(refs:1897-1901)；工作区既有实测 `优化机会-B-功耗内存.md:651-655`（加载的是 `oplus_bsp_hybridswap_zram` 等 vendor 模块，GKI `zram.ko` 未加载） | 常态 | 15.5GB+10GB zram+hybridswap 的行为由厂商模块决定，本次 config 变更对它无效 | 按"无效改动"处理，勿据此设计 A/B | 高 |
| A-07 | P3/待确认 | LZ4/Zstd 补丁包带进 61 个 `.rej/.orig`，opt45 直接删除而未逐个确认 | `git show --name-only 372750608ecd`（`crypto/zstd.c.rej`、`include/linux/zstd*.h.rej`、`lib/zstd/**` 约 50 个、`kernel/Makefile.rej`、`kernel/locking/rtmutex*.rej`）；删除 `846c9c1ba805` | — | 抽查 `crypto/zstd.c.rej` 的 hunk**已在** `crypto/zstd.c:22-40` 落地（`compression_level` 参数 + `zstd_get_params(compression_level, PAGE_SIZE)`）⇒ 多数 .rej 是"已另行落地"的残留；50+ 个 `lib/zstd/**` 未穷尽，不能排除个别 hunk 丢失 | 把补丁包重放到 pristine 副本与现树 diff | 低（抽查为正） |
| A-08 | P3 | SSG 电梯是 owner 新引入（原厂配置无此符号） | `gki_defconfig:846-847`；`refs/stock_config.gz` 全文 grep `SSG|ssg` **零命中**，原厂仅 `MQ_IOSCHED_DEADLINE/KYBER/BFQ`(refs:880-883)；代码 `block/ssg-iosched.c:876,883,906`；commit `e17ad23693ab` | 使用 ssg 作为 sda~sdf 电梯 | 原厂没有的 I/O 调度器；行为/功耗/与 UFS+f2fs 的交互需实机 A/B（P32 自述"设备上就是 [ssg]"是运行 opt 内核时的观察，不代表原厂） | 存 A/B 数据后再定去留 | 高（配置原文）；收益为中 |

---

## 3) 严重度定义（本报告口径）

- **P0** = 可变砖 / 掉基带 / 数据永久损坏 / 无法开机
- **P1** = 严重功能失效，或频繁重启/挂死
- **P2** = 性能或功耗显著劣化
- **P3** = 隐患或加固弱化

> 本版**没有 P0/P1 级发现**。A-02 的后果（栈越界）本身很重，但**触发需要 root 主动写 sysfs**，按"需要 root 主动操作才可达"记 P2。

---

## 4) 无法确认 / 需要实测

| 编号 | 事项 | 需要什么证据 |
|------|------|--------------|
| U-04 | A-02 是否有真实写入者（是否有 OTA/调参工具会写 `compress_log_size`） | 设备：`grep -r compress_log_size /vendor /system /odm 2>/dev/null`；`dmesg | grep -i compress` |
| U-05 | A-03 是否真的活锁/长自旋 | kprobe/ftrace 统计 `retry_vma` 循环次数；压测下采样 `/proc/<pid>/stack`。离线无法做 |
| U-06 | A-04 "被剔除的 12 项"清单 | 拿到 OPPO `ebdd1643c` 原提交后逐文件 diff（本机 vendor 树无此 rev） |
| U-07 | A-07 的 `lib/zstd/**` 50+ 个 .rej 是否丢 hunk | 把补丁包重放到 pristine 副本 → 与现树 diff |
| U-08 | A-08 SSG 对 UFS/f2fs 的实测行为 | 设备 A/B：`/sys/block/sdX/queue/scheduler` 切 ssg/mq-deadline，测 f2fs 随机写延迟与功耗 |
| U-09 | 第三方 LZ4 NEON asm 的整体正确性（非本次撤回项，但仍是引入物） | 建议对 `_lz4_decompress_asm` 做离线差分测试（与 C 版 `LZ4_decompress_safe` 对随机语料逐字节比对）；本次只验证了 opt42 那处改动等价 |
| ~~U-01/02/03~~ | ~~A-01 激活面~~ | **已关闭**：A-01 为误报，无需实测 |

---

## 5) 已复核且未发现问题（避免重复劳动）

| 编号 | 事项 | 结论 | 证据 |
|------|------|------|------|
| V-11 | **opt42 的 LZ4 Permtable 修复本身** | **正确且等价**：新增 `cmp offset,#16 / b.hs 15f` 在**读表之前**跳过越界读；`b.hi 15b` 目标未变。用真实 .S 汇编成 .o 后 pre/post `llvm-objdump -d` 对比确认（详见 §2.0） | `lib/lz4/lz4armv8/lz4armv8.S:201-210,237-243`；commit `77aa56a8024c`；`/tmp/lz4_pre.o` vs `/tmp/lz4armv8.o` |
| V-01 | opt15-P32 SSG 两处缺陷 | **都修好**：(1) `ssg_blkcg_shallow_depth()` 的 `atomic_read(&ssg_blkg->current_rqs)`/`shallow_depth` 已在 RCU 段内（`block/ssg-cgroup.c:127-142`）；(2) `ssg_var_store()` 返回 int 且宏内检查（`block/ssg-iosched.c:761-766,791-812`） | 上列行号；`e1b638d4de99` |
| V-02 | opt15-P30/P31 f2fs `dic_layout` | **成套、无新 UAF**：字段 `fs/f2fs/f2fs.h:1800`；`f2fs_alloc_dic()` 在分配后/错误路径前显式赋值（`fs/f2fs/compress.c:2297-2304`）；晚释放路径用缓存（`:2474`）；`:340`、`:1376` 同步改缓存；`:2316` 保留 `dic->inode` 是正确的（此刻缓存未赋值）。余下 `dic->inode` 使用点都在 page 锁定、inode 被钉住的上下文 | 上列行号；`a79799cda102`/`b96307adfd22` |
| V-03 | `dic_layout` 缓存语义 | **几何量飞行中不可变**：`f2fs_set_compress_option_v2()` 对已有块的文件拒绝改几何（`fs/f2fs/file.c:6259-6276`）；layout 位只在建 inode 时由挂载选项写入（`fs/f2fs/f2fs.h:4986-4988`），sysfs 改 `compress_layout` 只影响新 inode | 上列行号 |
| V-04 | opt39 jbd2 `journal = transaction->t_journal;` 搬家 | **安全**：`journal` 首次使用在赋值之后（`fs/jbd2/transaction.c:1578` 起），abort 分支（`:1543-1553`）不碰 `journal` ⇒ 无未初始化读。缺的只是上游同提交的 `data_race()` 注解（KCSAN 注解，本机未开 KCSAN，无功能影响） | `fs/jbd2/transaction.c:1470-1561`；`c6f3611bb39d` |
| V-05 | opt39 ext4 `i_size` 上界校验的标志顺序 | **正确，不会误拒**：`ei->i_flags = le32_to_cpu(raw_inode->i_flags)`（`fs/ext4/inode.c:4971`）使 bit19=`EXT4_INODE_EXTENTS` 直接来自磁盘位，晚于它的 `inode->i_size=ext4_isize()`(`:4978`) 与新校验(`:4979-4980`) 因此判对分支；`ext4_get_maxbytes()` 在 `fs/ext4/ext4.h:3363-3368` | 上列行号 |
| V-06 | opt40 ext4 sysfs UAF 两半 | **都在，无死锁可见**：notify 侧持锁+判 `state_in_sysfs`（`fs/ext4/sysfs.c:519-527`）；register/unregister 持同一锁包 `kobject_init_and_add`/`kobject_del`（`:536-545`、`:572-580`）；锁初始化 `fs/ext4/super.c:5296` 早于 register；umount 次序 `:1259 → :1267` 使 worker 醒来即跳过。全树 `sysfs_notify` 仅此一处 | 上列行号；`a9d0d61fbf68` |
| V-07 | opt36 UFS 三处 | 形态与上游一致：`drivers/ufs/core/ufshcd.c:498-505`、`:4318`、`:9862-9872`（成对提交） | `febd4235f865` |
| V-08 | opt12-clean/opt14-trim 退掉的 mm 文件是否真的不编译 | **判据成立**：`mm/kasan/init.c` 只在 `KASAN_GENERIC/SW_TAGS` 下编（`mm/kasan/Makefile` 末尾），本机是 `KASAN_HW_TAGS`；`hugetlb.o` 需 `HUGETLBFS`(`mm/Makefile:94`)、`hugetlb_cgroup.o` 需 `CGROUP_HUGETLB`(:119)、`memory-failure.o` 需 `MEMORY_FAILURE`(:121)、`secretmem.o` 需 `SECRETMEM`(:140)、`damon/` 需 `DAMON`(:145) —— 均未开 | 上列 Makefile 行 + `05480beb0c27`/`d9a3e7eab9b6` |
| V-09 | opt9 `VM_FAULT_RETRY_VMA` 位定义 | `0x008000` 与既有位无交集，且总与 `VM_FAULT_RETRY` 同时返回 ⇒ 只看 RETRY 的既有代码行为不变 | `include/linux/mm_types.h:946-950`；`mm/filemap.c:3469-3471` |
| V-10 | MGLRU/低内存主体 config | 未被 owner 偏离：`LRU_GEN=y`+`LRU_GEN_ENABLED=y` 在基线(7a244ff18620:138-139)与原厂(refs:1035-1036)都已开；`PSI=y` 同样 | 上列行号 |

---

## 6) 复核记录与自我更正（可复现）

- 设备：`adb.exe devices` → 空 ⇒ 全程静态分析（未唤醒设备）。
- **A-01 的撤回过程（含我的错误）**：
  1. 最小实验：两个 `15:` + 末尾 `b.hi 15b`，`clang --target=aarch64-linux-gnu -c` + `llvm-objdump -d` ⇒ `b.hi` 指向**第二个（最近的前一个）** `15:`。**该结果本来就否证了我的结论，我在 v1/v2 中把它映射反了**（把"最近的前一个"误当成"插入的新标签"）。
  2. 真实文件复核（本版新增）：`awk -f arch/arm64/tools/gen-cpucaps.awk arch/arm64/tools/cpucaps > /tmp/gen/asm/cpucaps.h`；`awk -f arch/arm64/tools/gen-sysreg.awk arch/arm64/tools/sysreg > /tmp/gen/asm/sysreg-defs.h`；`: > /tmp/gen/generated/asm-offsets.h`；`printf ... > /tmp/gen/linux/version.h`；然后 `clang --target=aarch64-linux-gnu -D__ASSEMBLY__ -D__KERNEL__ -I /tmp/gen -I out_verify/include/generated -I out_verify/include/generated/uapi -I include -I arch/arm64/include -c lib/lz4/lz4armv8/lz4armv8.S -o /tmp/lz4armv8.o`（**只写 /tmp，未改内核树**）。pre 版同法取 `git show 77aa56a8024c^:lib/lz4/lz4armv8/lz4armv8.S` → `/tmp/lz4_pre.o`。
  3. `llvm-objdump -d` 两份对比：唯一实质差异是新增 `cmp x12,#0x10` + `b.hs 0x140`（在 `ldp q2,q3,[x11]` 读表之前）与读表后的 `b 0x144`；`0x140: ldp q0,q1,[x9]`、`0x144:` 与 pre 版一致；**32B 拷贝循环末尾的 `b.hi` 两版机器码相同**。⇒ 结论：分支等价、越界读已消除。
- 原厂对照：`zcat /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/kernel-kit/refs/stock_config.gz > /tmp/stock.config`（7585 行），按 A-05/A-06/A-08 所列逐项 grep。
- 其他：`git show <commit> -- <paths>` 逐个 owner 提交；`git ls-tree 7a244ff18620 lib/lz4`；`mm/Makefile`、`mm/kasan/Makefile` 依赖核对。

（报告结束）