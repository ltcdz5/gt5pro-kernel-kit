# 版本变更日志（CHANGELOG）

**设备**：真我 GT5 Pro（pineapple / RMX3888，SM8650）· Android 16 · GKI 6.1.141 OKI
**版本串格式**：6.1.141-android14-11-o-ltcdz5-v族.次-opt构建序（见《版本号规范-20261003.md》）
**发布节奏与记录规则**：见《发布规范-20261004.md》
**状态词表**：★现役 ／ ✅交付（有上机核验台账） ／ 🖼产出镜像（images/清单.txt 可证） ／ 📦留档 ／ ⛔否证（禁止使用）

---

## 一、发布记录

### 已发布：v1.1-opt42（Release 在源码仓库，2026-10-04；观察期 2026-10-04 01:12 → 2026-10-05 01:12）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt42 |
| git | tag v1.1-opt42 = 77aa56a8024c |
| 镜像 | boot-v1.1-opt42-repacked.img，md5 4bd362b0a17513474de217ea9beb8ae3（201,326,592 B） |
| 裸内核 | perf42/Image.opt42，md5 2e20e2c1b7dea60cdfee3d58a730a79f |
| 回退首选 | boot-v1.1-opt41-repacked.img，md5 8e449caedeb1791923393c9c4eb2245f |
| 源码快照 | 仓库 ltcdz5/gt5pro-kernel-src 分支 opt42 = a4428da6（main 上仍是最早的 2026-09-29 快照） |
| Release | **建在源码仓库**：[gt5pro-kernel-src 的 tag v1.1-opt42](https://github.com/ltcdz5/gt5pro-kernel-src/releases/tag/v1.1-opt42) ⇒ 直接指向该版源码快照 a4428da6（**不建在工具仓库**） |
| 上机时刻 | 2026-10-04 01:12 刷入，现役 |
| 观察期状态 | 截至 2026-10-04 02:33 已观察约 1.3 小时 / 需满 24 小时 ⇒ **未满**；经机主 2026-10-04 决定**提前发布**（按《发布规范》属例外，记录在案） |

**本版改动（相对 v1.1-opt41 与 opt37）**

1. **USB gadget bRequestType 位域误判**（drivers/usb/gadget/composite.c）
   USB_DIR_OUT == 0、USB_DIR_IN == 0x80，原式对整字节做相等比较，让 0x21（RNDIS class-OUT）等
   也走「截断后继续下发」；改为只测方向位且方向反转（命中 USB_DIR_IN 时截断，否则 stall），
   与上游 f08adf5add9a 语义一致。
2. **LZ4 armv8 Permtable 越界读**（lib/lz4/lz4armv8/lz4armv8.S）
   Permtable 16 行 x 32B = 512B，offset 属于 [16,31] 时最远读到 480B；把 cmp/b.hs 提到 add/ldp 之前，
   越界分支复用既有的 15:（32 字节整块拷贝）标签。
3. **累计（opt37 → opt42）**：ext4/jbd2 三项（含 CVE-2025-38337）、CVE-2026-31446 ext4 sysfs UAF、
   netfilter 四项（ipset dump 竞态、nf_conntrack_expect 空指针、TCP 非对齐读）、
   AF_PACKET 时间戳 cmsg 越界读（上游 1ee90b77b727）、版本号换新规范。

**验证**

| 项 | 结果 |
|---|---|
| 闸门1 gate_new_exports.py | PASS（命中厂商：新增=0 消失=0） |
| 闸门2 gate_vko_crc.py | 会拒绝装载的模块 = 1，即判定基线 bluetooth.ko / sk_filter_trim_cap |
| 更强证据 | opt37 与 opt42 的 vmlinux.symvers **字节级完全相同**（15437 行 / 923271 B）⇒ 导出集合与全部 CRC 零变化 |
| 代码审核 | 8 处改动逐条与上游修法一致（见《审核-opt37到opt42代码审核-20261004.md》） |
| 上机健康（2026-10-04 02:33 实测） | 内核 6.1.141-android14-11-o-ltcdz5-v1.1-opt42；槽位 _a；governor uag x4；oops 0；lsmod 621 |
| 频率控制 | 限频器 max 1132800/960000/960000/902400；下限 min 787200/729600/729600/787200 ⇒ Scene LP 正常 |

---

## 二、全量版本明细（opt5 → v1.1-opt42）

> 改动摘要取 **git commit 标题原文**（不改写）；日期为 tag/提交日期。

| 版本 | git ref | 提交 | 日期 | 改动摘要 | 状态 |
|---|---|---|---|---|---|
| v1.1-opt42 | tag v1.1-opt42 | 77aa56a8 | 10-03 | USB gadget bRequestType 位域误判 + LZ4 armv8 Permtable 越界读 | ★现役 |
| v1.1-opt41 | tag v1.1-opt41 | e5f8f1aa | 10-03 | 修 AF_PACKET 时间戳 cmsg 越界读（上游 1ee90b77b727）；实际修法 = 原型 + 去 static + 判定加析构校验 三件套 | ✅ |
| v1.1-opt40 | tag v1.1-opt40 | a9d0d61f | 10-03 | CVE-2026-31446 —— ext4 sysfs UAF（加 s_error_notify_mutex）；首次验证「改结构体也能零 CRC」 | ✅ |
| v1.0-opt39 | tag v1.0-opt39 | c6f3611b | 10-03 | ext4/jbd2 三项（含 CVE-2025-38337）：事务配额保守化、ext4_get_maxbytes 上界校验、abort 判定次序 | ✅ |
| v1.0-opt38 | tag v1.0-opt38 | 5a22d459 | 10-03 | netfilter 四项（ipset dump 竞态与空桶、nf_conntrack_expect 空指针、TCP 非对齐读）+ 版本号换新规范 | ✅ |
| version1-opt37 | tag version1-opt37 | 48e09518 | 10-03 | 四项 config 减法（UBSAN 全关 / INIT_ON_ALLOC 关 / INIT_STACK 归零关 / ZRAM_MEMORY_TRACKING + RCU_NOCB），并钉死 LTO_NONE 防 olddefconfig 翻掉 | ✅ |
| version1-opt36 | tag version1-opt36 | febd4235 | 10-03 | UFS 三处修复（含 CVE-2026-43471）；第一个新版本号规范的版本 | ✅ |
| version1-opt35 | tag version1-opt35（= opt15-p35） | cfd8e65c | 10-03 | 版本号规范切换为 v族.次-opt序；功能等同 opt15-P35 | ✅ |
| opt15-p32 | tag opt15-p32 | e1b638d4 | 10-03 | f2fs 压缩越界修复 + SSG 两处缺陷 | 🖼 |
| opt15-p31 | tag opt15-p31 | b96307ad | 10-03 | f2fs 解压路径改用 dic_layout + bootconfig 三修复 + qcom_geni 串口 | 🖼 |
| opt15-p30 | tag opt15-p30 | a79799cd | 10-03 | f2fs 修 dic 在 workqueue 晚释放路径上的 UAF | 🖼 |
| opt15-p28 | tag opt15-p28 | b45c37a0 | 10-02 | ACK round4 冲突块落地（53 文件） | 🖼 |
| opt15-p27 | tag opt15-p27 | 3448adab | 10-02 | ACK round4 头文件修复批 —— 11 个不碰中枢结构体的提交 | 🖼 |
| opt15-p25 | tag opt15-p25 | c2a84f3a | 10-02 | ACK round4 —— 老窗口（2026-05-20..09-29）的自洽子集 | 🖼 |
| opt15-p21 | tag opt15-p21 | e17ad236 | 10-02 | 启用 SSG 电梯（Samsung Generic I/O scheduler）※后评估属「贴原厂」而非调优 | 🖼 |
| opt15-p20 | tag opt15-p20 | d8e827ea | 10-02 | 补上 945be0af8244 posix-cpu-timers UAF 修复的生产者半边 | 🖼 |
| opt15-p19 | tag opt15-p19 | 14f326fc | 10-02 | ACK round3 —— 从 android14-6.1 收 104 个缺失文件块（26 个提交的真修复） | 🖼 |
| opt15-p16 | tag opt15-p16 | a54a45ae | 10-02 | 修掉 P13 引入的 /proc/loadavg 爆表 —— 退回 loadavg.c 的 (int) cast | 🖼 |
| opt15-p13 | tag opt15-p13 | d4fe9dd3 | 10-02 | 补上 stable 6.1.142..188 中本机参与编译却被跳过的 6 条纯 .c | 🖼 |
| opt15-p11 | tag opt15-p11 | e55a82a0 | 10-02 | 从 round2 遗留的 104 条 CONFLICT 中捞出 6 条自洽安全修复 | 🖼 |
| opt15-p5 | tag opt15-p5 | 1df7a34f | 10-02 | 把 P2/P4 的 config 增量录进 gki_defconfig 使构建可复现；PANIC_TIMEOUT -1 改 30 | 🖼 |
| opt15 | tag opt15c | 234e0260 | 10-02 | ACK 第二批 138 条（166 中退 28 条 modversions CRC 风险 + 5 条缺前置） | ✅ |
| opt14 | 提交 bc26f54a | bc26f54a | 10-02 | ACK android14-6.1-lts 68 条（mm 33 / f2fs 13 / sched 4 / block 4 / erofs 2 / 头 10 等） | ✅ |
| opt14-trim | 提交 05480beb | 05480beb | 10-02 | 退掉 23 条不进本机镜像的白改（判据 = 编译器 .o.cmd 依赖集） | 📦 |
| opt13 | 分支 opt13-trim | 4e03a7d2 | 10-02 | 减脂三项（UBSAN 全关 / INIT_ON_ALLOC 关 / KFENCE 采样 0）※2026-10-03 实测更正：当时仅 KFENCE 采样真生效 | ✅ |
| opt12-clean | 分支 opt12-stable | d9a3e7ea | 10-01 | 退掉 28 个不进本机内核镜像的白改（20 个编成 .ko 带不走 + 8 个本机不编） | ✅ |
| opt12 | 提交 bbe1b4de | bbe1b4de | 10-01 | stable 6.1.151..188 中真参与本机编译的 116 个 .c 修复 | ✅ |
| opt11 | 分支 opt11-stable150 | 4faf9066 | 09-30 | stable 6.1.146..150 中真参与本机编译的 6 个 .c 修复 | ✅ |
| opt10 | 分支 opt10-stable145 | 495c039a | 09-30 | stable 6.1.142..145 中自洽落地的 10 个纯 .c 修复 | ✅ |
| opt9 | 分支 opt9-clean-upstream | 206914f9 | 09-30 | Oplus ebdd1643c 同步的 13 文件子集（闭包剔除 12 项含 blk-mq.c 的 EXPORT） | ✅ |
| opt8 | 分支 opt8-upstream-nodelta | 6f55c321（分支未单独提交） | 09-29 | 按「不新增导出 + 闭包裁剪」规则裁出的 13 文件上游同步版（真正进代码 8 个） | ✅ 已上机（见第三节 §5） |
| opt7-clean | 分支 opt7-clean | d56788d5 | 09-30 | 拆除 builder 注入的 config_fix（不再谎报 IP6_NF_NAT）+ gki_defconfig 去重 + HEADERS_INSTALL 对齐原厂 | ✅ |
| opt5 | 分支 opt5-state | 6f55c321 | 09-29 | regdb 内嵌（消掉开机 60 秒固件回退等待，87s 降到 26s）+ 799 行干净 defconfig + ltcdz5 后缀 | ✅ |

---

## 三、否证与留档：**错误实验的原因**（禁止使用）

> 这一节回答「**为什么这条路不走了**」。每条都给机制与定案依据，不写「感觉不行」。

| 版本 / 实验 | 结论 | 一句话原因 |
|---|---|---|
| v1.1-opt44 | ⛔ 未交付 | gov_override 只服务于已被实测否证的 LSE ⇒ 收益为零、白扩可写面 |
| v1.1-opt43 | ⛔ 硬挂死整机 | 挂点在 scx_ops_enable() 核心（持 cpus_read_lock 死锁）；部分接管同样挂 |
| opt6 / opt6a / opt6a2 | ⛔ 全循环开机 | 新增导出 test_task_ux 唤醒 12 个厂商模块的「真调用」分支 ⇒ 活锁硬复位 |
| a2 / a4（判砖实验） | ⛔ 循环开机 | 与 opt6 同机制；a4 单独定罪，a5 免刷 ⇒ include/linux/file.h 无罪 |
| LSE 外挂模块 | ⛔ 净负面 | 实测 +1.7W 且帧率更差（55.5 vs 64.8） |
| opt8 | 📦 留档（已上机成功） | 未留独立提交 ⇒ 不可复现；已被 opt9 取代 |

### 1. opt6 / opt6a / opt6a2 —— 全循环开机（机制已定案，非猜测）

**现象**：开机即重启、循环；「连黄字都不跳」；零崩溃留痕。

**根因（由三条独立读数夹出来）**
1. test_task_ux 在 opt5 里**不导出**，而本机有 **12 个厂商 .ko 引用它**：
   oplus_binder_strategy、oplus_bsp_dynamic_readahead、oplus_bsp_hybridswap_zram、
   oplus_bsp_uxmem_opt、oplus_bsp_zram_opt、oplus_locking_strategy（/vendor 与 /vendor_dlkm 各一份镜像）。
   它们在 opt5 上照常装载 ⇒ 对该符号只能是 **weak undefined**（非弱引用缺符号会拒绝装载），
   即「拿不到就当 NULL、走跳过分支」。
2. opt6 引入了 **19 个新增导出**（含 EXPORT_SYMBOL_GPL(test_task_ux)）⇒ 符号突然**可解析**，
   这 12 个模块的指针判空守卫**同时翻成「真调用」**，而实现读的是厂商模块不认识的
   blk-mq 内部状态 ⇒ **活锁**。
3. 佐证：persist.sys.oplus.total_abnormal_reboot_count = total_9_dump_0_pmic_9
   （9 次异常重启、**0 个崩溃转储**、全记为 PMIC 级复位）；/sys/fs/pstore 为空且
   last_kmsg 从未存在，而 pstore 取证链两端都通 ⇒ **死法不经过 panic/oops**。

**定案依据**：闸门1 回验 **5/5** —— CONTROL PASS/开机、opt7-clean PASS/开机、a4 FAIL/循环、
opt6 FAIL/循环、a2 FAIL/循环。

**由此产生并沿用至今的规矩**：候选内核「**新增导出符号 ∩ 厂商 .ko 引用符号名**」必须为空
（tools/gate_new_exports.py，基准 vendor-ko-symbols.txt 199,295 个名字）；
上游增量里任何会新增导出符号的部分（EXPORT_SYMBOL*、DECLARE_HOOK / DEFINE_HOOK、CREATE_TRACE）
一律不搬，只搬**不改变导出集**的纯实现修复。

### 2. a4 / a5 判砖实验 —— 一次刷机买到定论

- **a4** = 只含 block/blk-mq.c 的 1 行 EXPORT_SYMBOL_GPL(test_task_ux) + include/linux/blk-mq.h 13 行声明
  ⇒ **循环开机**（随即刷回 opt7-clean，两条命令完成，无重刷损失）
- ⇒ **include/linux/file.h 无罪，a5 不必再刷**（a4 单独足以解释此前三砖）
- 代价：一次刷机；收益：把「头文件改动是否致砖」这条悬案切成二选一并一次出定论

### 3. v1.1-opt43 —— scx 硬挂死整机

**现象**：bpftool struct_ops register 命令发出后 shell 立即无响应 → 整机离线（adb/fastboot 均无）
→ 约 10 秒后设备自己回来（**uptime 归零**）、sys.boot.reason = reboot、**pstore 0 条**、
**真 oops 0**、异常重启计数不变（total_9_dump_0_pmic_9）。

**根因**：**scx_ops_enable() 路径死锁**（ext.c:2838 持 cpus_read_lock()）
⇒ 整机冻结 ⇒ 无现场 ⇒ 靠 PMIC 看门狗复位恢复。

**「只做部分接管」救不了（已实测证伪）**：opt43 已注释 ext.c:2840 的 scx_switch_all_req = true，
并重建了**不含 scx_bpf_switch_all() 调用**的 BPF 对象（该 kfunc 引用数 0），**依然硬挂死**。
⇒ 「挂死在批量切任务」的假设被证伪；对抗性审核指向 ops.init 的 BPF 调用（:2842）
或静态位（scx_has_op[] / __scx_switched_all）与 CPU 热插拔的交互 —— 两处都在锁内。

**为什么原厂自己也没启用（旁证一堆）**：scx_bpf_switch_all(bool) 被削成无参只能 true（部分接管没了）；
//slim_walt_enable(true)（ext.c:2817）被注释且 slim_walt.c 源码已删；**无** /sys/kernel/sched_ext；
**无** scx_bpf_cpuperf_*；**无** bpf_iter_num；dmesg **从未**出现 scx 启用消息。
⇒ 厂商把框架编进来却从未启用、也没给出启用路径。

**结论**：要定位必须 **ramdump/串口**拿挂死现场；要修好需把上游 6.12 的 sched_ext 完整重做一遍
⇒ 超出常规刷机内核范围，**结案不做**。

**⚠️ 安全提醒**：**不要**再在这台设备上 register 任何 scx 调度器 —— 实测 = 硬挂死整机。
（编译侧的 BPF 链路资产是真的，可用于**非 sched_ext** 的 tracepoint/kprobe/profile 实验，那些不碰调度类、挂死风险为零。）

### 4. v1.1-opt44 —— gov_override，未交付

**当初为什么做**：scaling_governor 被厂商**运行期锁成只读** ——
root 有 CAP_DAC_OVERRIDE 仍报 EACCES ⇒ **该属性没有 write fop**（不是权限位问题）；
但同一 inode 91287 曾在数分钟前是 -rw-r--r-- 且写入 rc=0 ⇒ **有厂商代码在运行期移除并以只读方式重建它**
（结合已发现的 22 个 OPLUS MountMask，判定为统合性 anti-tamper 机制）。
这挡住了 LSE 的 lunar_ext_gov 激活 ⇒ opt44 在 cpufreq 核心新增一个**不同名的可写入口**
（内部直接调 cpufreq_set_policy()），绕开厂商锁。

**为什么判它是错**
1. **它唯一服务的对象（LSE）已被实测否证**：平均功耗 5201 vs 3468 mW（**+1.7W**）、
   中核平均频率 2932 vs 1661 MHz、FPS 均值 **55.5 vs 64.8**（无 LSE 反而更流畅）、
   CPU 温度均值 80.6 vs 60.3 摄氏度。
2. **LSE 自身硬约束**（记录备查）：没有 module_exit ⇒ rmmod 必然失败、[permanent]；
   开机早期加载触发过**卡死循环**；sched_ravg_window_frame_per_sec 写 0 会**除零崩机**；
   LSE_DEBUG_PANIC 是编译期常量；**没有「governor 被选中才启用」的门**（不选它也一直付钩子开销）；
   与厂商 oplus_bsp_sched_assist 共用 task_struct.android_vendor_data1[63]（争用风险）。
3. **净收益为零，却扩大了用户态可写面、偏离原厂**。

**处理**：tag 保留、不删不改；**不进交付链**；**从未对外发布**（远端无该 ref / 无 release，
公开源码里 gov_override 命中 0）。

### 5. opt8 —— 已上机成功，但只作留档

**它是什么**：把 09-29 那份 25 文件上游补丁，按「不新增导出 + **闭包**裁剪」规则裁到 13 个文件
（其中 5 个非 arm64 的 fault.c 不参与本机构建 ⇒ 真正进代码 **8 个**）。
裁剪两步缺一不可：① 凡新增 EXPORT_SYMBOL* / DECLARE_HOOK / DEFINE_HOOK / CREATE_TRACE 的文件全裁；
② **闭包** —— 保留文件里若引用了第 1 步引入的符号（含 trace_xxx() 这种调用点）一起裁。
第一版只做**单词边界匹配**，漏掉 sched/core.c、fair.c、exit.c、fork.c 这批**调用点**
（那就是「系列补丁只取一半」，编得过也是死分支或悬空引用）；改成宽松子串匹配后裁到 12、留 13。

**结果**：**2026-09-30 00:02 真机上机，开机成功**（banner 以 -opt8 结尾、lsmod 621、
boot_progress_start=12.87s），并与 opt9 一起**验证了这条裁剪规则**（两次真机通过）。

**为什么只作留档**
- 分支 opt8-upstream-nodelta 指向 opt5-state ⇒ **没有独立提交、不可复现**
- 副作用：它切自 opt5-state，把 opt7-clean 已拆掉的 config_fix 谎报又带回来
  （/proc/config.gz 里 IP6_NF_NAT=n，但 /proc/net/ip6_tables_targets 里
  DNAT/SNAT/MASQUERADE/REDIRECT 都在 ⇒ **纯显示谎报，功能没缺**）
- 其后继是 **opt9**（同样规则、有提交），所以 opt8 被取代
- 当时的回退链：opt8(358d6cde) → opt7-clean(c27db830) → opt5(073bfdaa) → 原厂 boot_a.img(a33ff998)

### 6. LSE 外挂调度扩展（LunarKernel Scheduling Extention）—— 净负面，已放弃

**实测**：+1.7W、中核 2932 vs 1661 MHz、FPS 55.5 vs 64.8、CPU 温度 80.6 vs 60.3 摄氏度
⇒ **又费电又更卡**。机制：其 Slim-WALT 负载跟踪抬高 util 估计值 ⇒ governor 把中核顶到约 2.9GHz；
同时替换/干扰厂商自己的 WALT 跟踪 ⇒ 任务放置变差 ⇒ 帧率反而下降。

**教训**：**「频率顶满」不等于「浪费」** —— 要看频率高有没有换来收益，而不是看负载百分比。
（本次就误判过 LSE 的问题性质：它其实是「顶满还更卡」。）

**合规提示**：该 .ko 是第三方 GPL v2 二进制，本项目**没有它的源码** ⇒ 再分发必须提供源码
⇒ **公开仓库不放 .ko**，只放我们原创的管理脚本外壳 + 完整风险文档。

---

## 四、字段来源与核对方式

| 字段 | 来源 | 怎么核 |
|---|---|---|
| 改动摘要 | git commit 标题原文 | git log --oneline |
| git ref / 提交 | tag 与分支 | git for-each-ref refs/tags、git branch -vv |
| 日期 | tag 创建日 | git for-each-ref --sort=creatordate |
| 状态 | 上机核验台账 + images/清单.txt | 见 kernel-kit 下各类 -上机核验-*.md |
| 镜像 md5 | images/清单.txt | 改文件后重跑 tools/images_出清单.sh |
| 否证原因 | 定案文档 | 判砖实验-a4a5.md、⛔事故-scx加载硬挂死-20261003.md、governor只读之谜-*.md、抖音功耗异常-根因定位与结案-*.md |
| **构建历史（审计用）** | 源码仓库 **history 分支的 build-history/**：opt5→v1.1-opt42 的 33 个补丁，每个保留原始 SHA / 作者 / 日期 / 提交原文 / 完整 diff | 打开对应补丁与上表「提交」列逐一核对；git am 可复现 |

### 可审计性说明（2026-10-04）

上表「逐版改动」原本只是文档自述。现已补上可验证的载体：

**https://github.com/ltcdz5/gt5pro-kernel-src/tree/history/build-history**

为什么不直接推 git 提交历史：本机内核树是**浅克隆**（.git/shallow 有 9 个浅边界提交，
含 7a244ff18620 那次 Revert 与 ebdd1643cfdb 的 Oplus 同步），直接推会被 GitHub 拒绝：

    remote: fatal: did not receive expected object a224a9d8ee062fb81018a44ab1df4964ab379dd8
    error: remote unpack failed: index-pack failed

而把 33 个提交重建成自洽 lineage 会让**每一个 SHA 都变**，与上表「提交」列脱钩。
⇒ 采用**不篡改 SHA** 的补丁序列：补丁头里的 From 行就是原始提交 SHA，可与本表逐条对上。

> ⚠️ images/清单.txt 生成于 2026-10-03 18:16，**未收录 opt43 之后的镜像**。
> 按机主 2026-10-04 指示：**本次不收录、不单独重跑清单脚本，留到下次更新时一并跟进**。

---

## 五、仓库级事件（非内核改动）

- **2026-10-04 · 公开仓库内容边界清理**：按机主要求，移出 23 个与本项目无关的文件
  （第三方 GPU 模块原件 18 + 他人内核对照件 5），并把文档里对它们的产品名与细节匿名化（保留方法与结论）。
  随后**删除并重建 kernel-kit 仓库、历史重置为单提交** —— 原因：早期提交里含这些内容，
  仅删 HEAD 无法让它们从历史消失。旧提交 SHA 已不可访问；被清理资料移至机主本地归档。
  规则已固化为《发布规范-20261004》§八。

---

*最近更新：2026-10-04（补齐 opt5 → v1.1-opt42 全量 changelog；建立发布规范；补写全部错误实验的机制级原因；修正 opt8 误标为「未上机」；内容边界清理与仓库重建）。*
