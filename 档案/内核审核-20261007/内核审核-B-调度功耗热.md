# 内核审核 B：调度 / 功耗 / 热 / 显示 / GPU

设备：Realme GT5 Pro（RMX3888，SM8650，Android 16 / ColorOS 16）；内核 ACK 6.1.141-android14-11 + OPPO/OnePlus 厂商代码，自编 **v1.1-opt47**（HEAD 5ddf8408b29a）。
审查区间：`7a244ff18620..5ddf8408b29a`（40 提交 / 592 文件）。本方向边界：kernel/sched、kernel/power、drivers/base/power、drivers/thermal、drivers/cpufreq、drivers/cpuidle、drivers/devfreq、drivers/opp、drivers/gpu、drivers/gpu/drm、kernel/oplus_cpu，以及影响 CPU/GPU 频率、热控、suspend/resume 的 config。
方式：**只读静态分析**。设备对本人全程离线（`adb devices` 输出为空），未做实测、未改内核树、未刷机、未改设备状态。

> 版本说明（v2）：本版依据 **Lead 的设备侧实测** 做了两处更正——B-05（`/proc/sys/walt/*` 在设备上**确实存在且可写**，由厂商预编译 .ko 提供，而非不存在）、B-04（HZ 失配只影响**编译期常量实参**的 msecs 换算点，且须区分 tick **+20%** 与时长 **-16.7%**）。两处更正均已在对应条目注明来源。

---

## 1) 结论摘要（按严重度排序）

1. **【P2 · 待实测】runtime PM 工作队列 `pm_wq` 被去掉 WQ_FREEZABLE（改成纯 WQ_UNBOUND）** —— `kernel/power/main.c:920`，opt15-P28 / commit b45c37a0c6b4。查证为 **2025 年 9 月与 12 月两则上游改动**的合并结果（"PM: WQ_UNBOUND added to pm_wq workqueue" 把 unbound 显式化；"PM: sleep: Do not flag runtime PM workqueue as freezable" 进一步要求**不**打 freezable），且与同窗口落地的 `drivers/base/power/main.c`（`__device_suspend_late` 改用 `pm_runtime_disable(dev)`，内部 `pm_runtime_barrier()` 冲刷挂起请求）构成**配套一对**，因此判定为"有意回移"，**不是**解冲突失误。但它恰好落在"待机耗电 / 能否进入深睡"主路径上（genpd 电源域、USB 唤醒、runtime PM 工作），**必须与上一版本对比待机耗电后才能定论；若回归，第一嫌疑就是这两处**。
2. **【P3 · 高置信度】`CONFIG_PANIC_TIMEOUT` 从 -1 改成 30，但改动说明里的理由写反了** —— `gki_defconfig:761` / commit 1df7a34f6453。本树 `lib/Kconfig.debug:1030-1037` 与 `Documentation/admin-guide/kernel-parameters.txt:4041-4044` 双向确认：**负值 = 立即重启（immediate reboot），0 = 永不重启（wait forever）**。所以基线 -1 本来就是"panic 后立刻自动重启"，并不存在说明里写的"黑屏卡死需手动长按电源"；改成 30 的真实效果是**每次 panic/oops 先忙等（`mdelay` + 闪灯循环）30 秒再重启**。对 opt45 那种"硬挂死"两种取值都无效（根本走不到 `panic()`，复位靠 qcom WDT bark/bite）。pstore 日志在 `console_flush_on_panic()` 已先行落盘（`PSTORE_RAM=y`/`PSTORE_CONSOLE=y`），"丢现场"风险低于说明所述。
3. **【P3 · 高置信度】opt45 的 sched_ext 拦截在 BPF 侧是"结构性完整"的，但只覆盖 sched_ext 一个类型** —— 类型表 `kernel/bpf/bpf_struct_ops_types.h` 被 `kernel/bpf/bpf_struct_ops.c:76/81/89/116` 四次包含，同时生成类型数组、enum 索引、`BTF_TYPE_EMIT` 与 map value 类型；`bpf_struct_ops_find()`/`bpf_struct_ops_find_value()` 都只遍历这张表 → 摘掉 `BPF_STRUCT_OPS_TYPE(sched_ext_ops)` 后，**程序装载查找与 map value 查找同时失效**（commit dfea5e50fd23），再加 `scx_ops_enable()` 开头的 -EOPNOTSUPP 兜底（`kernel/sched/ext.c:2792-2813`，commit 83f9166efbd4），共两道独立闸门；sysrq 'S' 复位键也是安全的（`ext.c:3232-3238` 在 `scx_ops_helper == NULL` 时只打印一行）。**残留隐患**：`tcp_congestion_ops`/`bpf_dummy_ops` 仍是已注册类型，如果硬挂死的根因在共享的 struct_ops/verifier 代码（2022 残缺 backport），换个类型仍可能复现——需要一次 bpftool 低风险验证（T-06）。
4. **【P3 · 中置信度】`CONFIG_HZ` 由 Kconfig 默认 250 写成 300（+20% 定时器中断）** —— `gki_defconfig:831-832`，commit 1df7a34f6453（"P4 相对 gki_defconfig 的 25 项增量: HZ 250->300"）。基线两侧（本树 baseline 与 OPPO 分支 `oneplus/sm8650_b_16.0.0_oneplus12_6.1.141`）都**不含**任何 CONFIG_HZ，`kernel/Kconfig.hz` 的 choice 默认是 HZ_250 → 原厂构建大概率也是 250。真正风险不在内核自身（`CONFIG_NO_HZ=y`，空闲影响接近 0），而在**厂商 621 个预编译 .ko**。机制已逐行核对：`msecs_to_jiffies()`（`include/linux/jiffies.h:363-372`）走 `__builtin_constant_p(m)` 分支——**只有编译期常量实参**才内联折叠到 `_msecs_to_jiffies()`（:308-311，直接拿 `MSEC_PER_SEC / HZ` 做常量除法，用的是**模块自己编译时的 HZ**）；**非常量实参**走导出的 `__msecs_to_jiffies()`（`kernel/time/time.c:552,561` `EXPORT_SYMBOL`），按**内核当前 HZ** 计算、结果正确。因此失配**只**发生在厂商 .ko 里"常量实参"的调用点（如 `msecs_to_jiffies(1000)`）以及直接写 `HZ/n` 的地方。数值方向要分清：HZ 250→300 是 **tick 频次 +20%**，反过来这些点的**时长变成 −16.7%**（25 jiffies 由 100 ms 变 83.3 ms）。HZ 不进 vermagic/CRC，所以**不会**导致拒载。建议：若无法用原厂 `/proc/config.gz` 证明原厂也是 300，就回退这两行（零收益换一致性）。
5. **【P3 · 已按设备实测修正】`/proc/sys/walt/*` 由厂商预编译 .ko 提供、源码不在本树；本次 40 个提交对它零影响** —— 我的静态初判（"本树 grep 不到 ⇒ 节点不存在"）**已被 Lead 的设备侧实测推翻**：`/proc/sys/walt/sched_fmax_cap` 存在且可写，读到 `2265600 3148800 2956800 3302400`（= Scene powercfg.sh 写入值），`sched_sbt_enable=0`，`/proc/sys/kernel/sched_util_clamp_max=1024`。正确结论：实现来自**厂商预编译的 walt/sched 扩展 .ko**（源码不在本树），而 40 个提交对 `kernel/oplus_cpu/`、`drivers/soc/oplus/`、`drivers/cpufreq/`、`drivers/cpuidle/`、`drivers/devfreq/` **零改动**（`git diff --name-status` 可复现）→ **内核侧没有改这些接口的语义/默认值/可用性，也没有破坏提供它们的模块**；该模块在 opt47 上已成功加载并生效（值等于 Scene 写入值），这反过来是"厂商 .ko 不拒载"约束的正向证据。残余问题只剩一个：该接口源码不在本树、无法静态审，只能靠设备侧对比默认值（T-05）。

> 另有一条"引入真 bug 又自己修回"的复盘见第 5 节 **L-01**（P13/P16 的 /proc/loadavg 爆表），现状已正确、无遗留。

---

## 2) 发现清单表

| ID | 严重度 | 标题 | 证据（file:line / commit） | 触发条件 | 影响 | 建议 | 置信度 |
|---|---|---|---|---|---|---|---|
| **B-01** | **P2** | `pm_wq` 去掉 WQ_FREEZABLE（runtime PM workqueue 在系统级 suspend/resume 过渡期不再被冻结） | `kernel/power/main.c:920`：`alloc_workqueue("pm", WQ_UNBOUND, 0)`（基线为 `WQ_FREEZABLE, 0`，OPPO 分支同基线）；commit **b45c37a0c6b4**；使用者：`drivers/base/power/runtime.c:480/663/866`（runtime resume/idle work）、`drivers/base/power/domain.c:604`（genpd power_off_work）、`drivers/usb/core/hcd.c:2415`（USB wakeup_work）；原有设计注释 `drivers/pci/pcie/pme.c:285` "We don't use pm_wq, because it's freezable." | 进入系统级 suspend（灭屏深睡）或 resume 期间，任何已排队/新排队的 runtime PM、genpd、USB 唤醒 work | 这些 work 现在可能在 suspend 回调并发的时机执行：设备被重新上电后仍留在 suspend（**待机耗电**）、genpd 关域与父域 suspend 竞争、USB wakeup work 在冻结窗口执行造成虚假唤醒；vendor 电源域 enter/exit 计数可能改变 | 与上一版本（opt44/opt45 之前）对比整夜待机耗电 + `suspend_stats`（T-03/T-04）；若回归，优先回滚这两处（改回 `WQ_FREEZABLE | WQ_UNBOUND` 可同时满足两侧顾虑，1 行、无 ABI 影响） | 中 |
| **B-02** | **P3** | PANIC_TIMEOUT -1→30 的说明与代码语义相反，实际效果是"每次 panic 多冻 30 秒" | `lib/Kconfig.debug:1030-1037`（"n = 0, wait forever；n > 0 wait n seconds；n < 0 reboot immediately"）；`Documentation/admin-guide/kernel-parameters.txt:4041-4044`（timeout < 0: reboot immediately）；`kernel/panic.c:402-424`（`if (panic_timeout > 0) {mdelay 循环}`，随后 `if (panic_timeout != 0) emergency_restart();`）；`arch/arm64/configs/gki_defconfig:760-761`（`PANIC_ON_OOPS=y`+`PANIC_TIMEOUT=30`）；commit 1df7a34f6453 | oops / BUG / `BUG_ON_DATA_CORRUPTION`（`CONFIG_BUG_ON_DATA_CORRUPTION=y`）触发的 panic | 基线 -1 = panic 后**立即**重启；改 30 后 = 黑屏 + `mdelay` 忙等 30 秒再重启（这段时间还持续耗电发热）。既不会"永不重启"（那是 0），也不解决硬挂死（软死锁到不了 panic()） | 建议回退 -1；若确实要给 ramdump/调试留时间，请把真实目的写进说明，否则每次崩溃都白等 30 秒 | 高 |
| **B-03** | **P3** | sched_ext 拦截完整（两道闸门 + 安全 sysrq），但仅覆盖 sched_ext 类型；共享 struct_ops 路径未验证 | `kernel/bpf/bpf_struct_ops_types.h:4-26`（摘除 `BPF_STRUCT_OPS_TYPE(sched_ext_ops)`，commit **dfea5e50fd23**）；四次包含点 `kernel/bpf/bpf_struct_ops.c:76/81/89/116`；`bpf_struct_ops_find()/bpf_struct_ops_find_value()` 只遍历该表；`kernel/sched/ext.c:2792-2813`（提前 `-EOPNOTSUPP`，commit **83f9166efbd4**），调用点 `ext.c:3198`（`bpf_scx_reg`）；`ext.c:3220-3229`（`bpf_sched_ext_ops` 仍定义但已无人引用）；`ext.c:3232-3238` + `drivers/tty/sysrq.c:528-529`（sysrq 'S'） | 用 bpftool/Scene 加载 sched_ext struct_ops（现已被干净拒绝）；★ 加载**其它**已注册类型（`bpf_dummy_ops`/`tcp_congestion_ops`）的 struct_ops 对象 | 主路径已封死：无类型注册 → 程序装载与 map value 查找双双 -EINVAL，即使绕过也撞上 `scx_ops_enable` 的 -EOPNOTSUPP；sysrq 'S' 因 `scx_ops_helper` 恒 NULL 而只打印一行。残留：卡死根因若在共享 verifier/struct_ops 代码，非 sched_ext 类型仍可能挂死 | 按 T-06 用最小 `bpf_dummy_ops` 对象验证共享路径；若仍挂死则需把拦截下沉到共享层。另：`CONFIG_SCHED_CLASS_EXT=y` **必须保留**（`include/linux/sched.h:1559` 用 `ANDROID_KABI_USE(3, struct sched_ext_entity *scx)`，厂商 .ko 依赖），关掉它才是危险操作 | 高（机制）／中（残留） |
| **B-04** | **P3** | CONFIG_HZ 250→300，并可能给全部厂商预编译 .ko 带来 ~17% 定时器偏移 | `arch/arm64/configs/gki_defconfig:831-832`（`CONFIG_HZ=300`/`CONFIG_HZ_300=y`）；基线 `git show 7a244ff18620:arch/arm64/configs/gki_defconfig | grep CONFIG_HZ` = 空；OPPO 分支同为空；`kernel/Kconfig.hz:6-11,51-56`（choice default HZ_250）；commit 1df7a34f6453 | 所有 jiffies 相关路径，尤其厂商 .ko 内部**常量实参**的 `msecs_to_jiffies()`/`HZ` 内联计算 | 内核自身：tick 频次 **+20%**，空闲态因 NO_HZ 影响很小，活跃态略多 timer/IPI 开销。厂商 .ko：HZ 在模块编译期由 `generated/autoconf.h` 固化；**只有编译期常量实参**的 `msecs_to_jiffies()` 会被内联折叠（`include/linux/jiffies.h:363-372` → `_msecs_to_jiffies()` :308-311，用模块自己的 HZ），**非常量实参**走导出的 `__msecs_to_jiffies()`（`kernel/time/time.c:552,561`，按内核 HZ，正确）→ 失配只影响常量实参调用点与直接 `HZ/n` 的写法，方向是**时长 −16.7%**（tick +20% 的另一面）。**不拒载**：HZ 不在 vermagic/CRC 中。/proc ABI 不受影响（USER_HZ 恒 100） | 无实测收益即回退这两行；若保留，请在变更记录里显式登记"厂商 .ko 定时器偏移"这一副作用 | 中 |
| **B-05** | **P3（已修正）** | `/proc/sys/walt/*` 由厂商预编译 .ko 提供（源码不在本树），本方向改动对它零影响 | **设备侧实测（Lead，今日 15:0x）**：`/proc/sys/walt/sched_fmax_cap` 存在且可写，值 `2265600 3148800 2956800 3302400`（与 Scene powercfg.sh 写入一致），`sched_sbt_enable=0`，`/proc/sys/kernel/sched_util_clamp_max=1024`；静态侧：`sched_fmax_cap`/`sys/walt` 全树命中 0（本树与 OPPO 分支皆 0）⇒ 实现只能来自**非本树的厂商 .ko**；`git diff --name-status 7a244ff18620..HEAD -- kernel/oplus_cpu drivers/soc/oplus drivers/cpufreq drivers/cpuidle drivers/devfreq` = 空 | 用户态（Scene / ColorOS）读写 `/proc/sys/walt/{sched_fmax_cap,sched_boost,sched_assist}` | 内核侧语义/默认值/可用性**零改动**；提供该接口的厂商 .ko 在 opt47 上**已成功加载并生效**（本身即"厂商 .ko 不拒载"的正向证据）。残余风险只剩"源码不在本树、无法静态审"，与本次 40 个提交无关 | 本方向无处置；T-05 改为"对比默认值是否与刷本内核前一致" | 高（本方向零改动）／接口归属：设备实测=高 |
| **B-06** | **P3** | 常驻执行的 sched_ext 任务退出钩子未被 opt45 摘除 | `kernel/fork.c:962` 无条件调 `sched_ext_free(tsk)` → `kernel/sched/ext.c:2356-2362` 无条件 `list_del_init(&p->scx->tasks_node)`；`include/linux/sched/ext.h:640`（CONFIG_SCHED_CLASS_EXT 下为真函数，非空 inline） | **每一次任务退出**（不是只在启用 sched_ext 后） | "拒绝启用"只封了装载/启用路径，这条每任务退出的锁+链表操作仍然常驻（2022 backport 代码）。若该 backport 在此处有问题，表现会是任务退出崩溃而不是装载挂死。经验事实：opt45+ 已正常开机运行，故当前无实害 | 保持不动（摘除它会改 .c 结构且收益不明）；按 T-09 做一次 fork/exit 压力 + dmesg 检查以留证 | 中 |
| **B-07** | **P3** | UBSAN/INIT_ON_ALLOC/INIT_STACK/KFENCE 全关 + `CC_OPTIMIZE_FOR_PERFORMANCE`/`LTO_CLANG_THIN` 组合（Lead 追问项） | `gki_defconfig:797`(`CC_OPTIMIZE_FOR_PERFORMANCE=y`)、:831-833、:749-750/849-852（`# CONFIG_UBSAN is not set`、`# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set`、`# CONFIG_INIT_STACK_ALL_ZERO is not set`、`CONFIG_INIT_STACK_NONE=y`、`CONFIG_KFENCE_SAMPLE_INTERVAL=0`）；commits **4e03a7d25409 / 48e095183986 / 1df7a34f6453** | 全部内核代码路径 | 代码生成上是"更快更小"（UBSAN 插桩移除；`CC_OPTIMIZE_FOR_PERFORMANCE` 只是把 `-O2` 的隐式默认显式化，本身无行为变化）；但同方向删掉了"未定义行为/未初始化内存/越界立即崩"的安全网，在 `PANIC_ON_OOPS=y` 下以前会立刻暴露的问题现在可能变成静默数据损坏 → **加固弱化**，且与 B-04 的 `drm_format_info_plane_*` 等显式校验互为补充关系 | 属 config/安全方向统一评述；本报告只登记关联：UBSAN_LOCAL_BOUNDS 关闭后越界读不再有内建兜底 | 高 |

---

## 3) 严重度定义（与总任务一致）

- **P0** = 可变砖 / 掉基带 / 数据永久损坏 / 无法开机
- **P1** = 严重功能失效或频繁重启挂死
- **P2** = 性能或功耗显著劣化
- **P3** = 隐患或加固弱化

本方向**未发现 P0**；B-01 若实测待机耗电显著回归，将升级为 P1。

---

## 4) 无法确认 / 需要实测清单（设备离线，以下全部未执行）

统一入口（设备离线时 `adb devices` 输出为空，不要尝试唤醒/重启设备；设备脚本必须先 push 再 su 执行，勿内联嵌套引号）：
```
ADB="C:\Users\xutengfa\Downloads\platform-tools\adb.exe"
& $ADB devices
```

| ID | 要确认的事 | 命令（root） | 判定标准 |
|---|---|---|---|
| **T-01** | 实际运行内核的完整 config（决定 B-04 的 HZ 偏移是否成立，也顺带验证"gki_defconfig 是否等于实际构建"） | `zcat /proc/config.gz | grep -E 'CONFIG_(HZ|PANIC_TIMEOUT|UBSAN=|INIT_ON_ALLOC_DEFAULT_ON|INIT_STACK|KFENCE_SAMPLE|SCHED_CLASS_EXT|CC_OPTIMIZE|LTO_CLANG|KASAN=)'` | HZ=300 → 实际构建与 defconfig 一致；厂商 .ko 若在 250 下编译，则只有其**常量实参**的 msecs 换算点偏差 **−16.7%**。HZ=250 → 说明实际构建 ≠ gki_defconfig，需先纠正基线。若 KASAN=y 等与 defconfig 不符，同样说明实际构建 ≠ gki_defconfig |
| **T-02** | panic 行为是否被 cmdline/用户态覆盖（决定 B-02 的真实后果） | `cat /proc/cmdline; cat /proc/sys/kernel/panic` | cmdline 带 `panic=0` 或用户态把它改成 0 → 实际"永不重启"，B-02 需升级并把 B-01 的"硬挂死"结论改写 |
| **T-03** | 待机耗电是否回归（**B-01 核心**） | 同场景对比 opt47 与上一版本：灭屏 8h 前后 `dumpsys battery` 差值；`cat /sys/kernel/debug/suspend_stats/{success,fail,last_failed_dev,last_failed_errno}`；`dmesg | grep -iE 'suspend|runtime|genpd'`；`cat /sys/kernel/debug/pm_genpd/*/state` | 掉电明显变多 / suspend 失败数增加 / last_failed_dev 非空 → 回滚 `kernel/power/main.c:920`（试 `WQ_FREEZABLE | WQ_UNBOUND`） |
| **T-04** | 是否真能进入深睡、是否有设备卡住 suspend | 灭屏 30 分钟后 `cat /sys/kernel/debug/suspend_stats/last_failed_dev; cat /sys/power/state`；`dmesg | grep -iE 'PM: suspend|Freezing|genpd'` | last_failed_dev 非空 = 有设备从 suspend 返回失败 |
| **T-05** | `/proc/sys/walt/*` 的**默认值是否与刷本内核之前一致**（存在性与可写性已由 Lead 实测确认，见 B-05） | `ls -l /proc/sys/walt/ ; for f in $(ls /proc/sys/walt/); do echo "--- $f"; cat /proc/sys/walt/$f 2>&1; done`；再与旧内核（opt44/官核）同项输出 diff | 默认值/可选项个数未变 → 本方向对该接口无影响（预期）；若变 → 变化来自厂商 .ko 侧，不可能是本树 40 个提交（本树没有该实现） |
| **T-06** | 共享 struct_ops 路径是否也会硬挂死（B-03 残留） | 先在电脑侧准备最小 `bpf_dummy_ops`（或 `tcp_congestion_ops`）struct_ops 对象，push 后 `su -c 'sh /data/local/tmp/x.sh'`，脚本内执行 `bpftool struct_ops list` 与 `bpftool prog loadall <obj> /sys/fs/bpf/t`；★**有硬挂死风险，需备好长按电源/等待看门狗，建议单独一次实验** | 干净报错 → 拦截有效、根因在 sched_ext 专用代码；仍挂死 → 根因在共享层，需扩大拦截范围 |
| **T-07** | 厂商预编译 .ko 是否依赖本次 B 方向改动涉及的符号 | 用厂商符号表/Module.symvers 比对 `pm_wq`、`thermal_zone_device_unregister`（`EXPORT_SYMBOL_GPL`）、以及 static 的 `thermal_set_governor`/`regulator_lock_two`（static 不可能被模块引用） | 预期：本方向改动**未改任何既有导出符号的类型/集合**（`pm_wq` 类型未变；thermal/regulator 两处均为 static；psi 的签名改动只涉及**未导出**的 `psi_trigger_create`）→ 不应新增拒载 |
| **T-08** | sched_ext 拒载的用户体验 | `su -c` 脚本：`bpftool struct_ops list; dmesg | grep -i sched_ext; dmesg | grep -i 'enable refused'` | 应看到 `sched_ext: enable refused (opt45 T0)` 或干净的 -EOPNOTSUPP，且设备不黑屏 |
| **T-09** | sched_ext 常驻退出钩子（B-06）是否引发 splat | `for i in $(seq 1 20000); do /system/bin/true; done`（或 `stress-ng --fork 8 --timeout 60s`），随后 `dmesg | grep -iE 'scx|sched_ext|BUG|WARNING'` | 无 splat → 该 backport 的常驻路径无害（预期） |
| **T-10** | GPU/显示无法从内核侧改动解释（结论的前置） | `dmesg | grep -iE 'kgsl|drm|dsi|panel|mdss' | tail -50`；必要时复现花屏/掉帧时抓 `/sys/kernel/debug/dri/*/state` | 本次 40 提交对 kgsl/drm-msm/panel/techpack **零改动**，若出现花屏/掉帧，应优先排查用户态（Scene + extreme_gt 伪造温度、解锁频点）与 vendor 分区，而不是本次内核改动 |

---

## 5) 已复核且未发现问题清单（避免重复劳动）

- **L-01（Q3 必答）P13/P16 的 `/proc/loadavg` 爆表：已正确收口，且"不只是显示问题"**。`kernel/sched/loadavg.c:80-83` 的 `nr_active += (int)this_rq->nr_uninterruptible;` 服务的是 `calc_load_fold_active()` → 真实负载均值 `avenrun[3]`（`loadavg.c:60-61` **`EXPORT_SYMBOL(avenrun)`**），因此 P13 那半边回移（`(long)` cast，commit d4fe9dd3640e）污染的是**负载均值本身**（实测 1.7179e10 = 4×(2^32-1) 精确吻合），用户态与厂商模块读到的都是错的。P16（commit a54a45ae5455）退回 `(int)` **正确**：本树 `struct rq.nr_uninterruptible` 是 `unsigned int`（`kernel/sched/sched.h:1080`；`kernel/sched/core.c:3860/6755` 会 `--/++`，可短暂为 0xFFFFFFFF），此时 `(int)` 恰好还原 -1 语义；上游 6.1.147 的 `(long)` 必须与"把该字段改为 unsigned long"成对使用，而后者会改 `struct rq` 布局、实测使拒载模块 1→47（含直接操作 `runqueues` 的 `oplus_bsp_sched_ext.ko`/`oplus_bsp_game_opt.ko`）→ **拒绝改 .h 的决策正确**。结论：现状正常，无遗留；代价是与上游该修复永久分叉（P3，可接受）。
- **kernel/sched 其余改动均为 ACK/stable 回移，逐块核对无冲突残留**：`cpudeadline.c/.h`+`deadline.c`（`cpudl_clear(cp,cpu,online)` 与 `rq_online/offline_dl` 配套；`pick_next_pushable_dl_task()` 前移；`find_lock_later_rq()` 的 migration-disabled/throttled 判定）、`rt.c`（`rto_next_cpu()` 不向自身发 IPI；`tg_rt_schedulable()` 改 u64 防溢出）、`fair.c`（`update_newidle_cost()` 预取 `next_decay`；`newidle_balance()` 处理空 `sd`）、`cpufreq_schedutil.c`（`sugov_update_rate_limit_us()` 64 位乘法；`limits_changed` 的 READ_ONCE/WRITE_ONCE 与 `smp_mb()/smp_wmb()` 配对）、`core.c`/`sched.h`（`to_ratio()` 返回 u64）。以上只改 .c 或同批改头文件，未改导出符号语义，**没有任何 CPU 频率/热控策略本身被改写**。
- **psi 的签名改动没有 CRC 风险**：`psi_trigger_create()` 3 参→5 参（`include/linux/psi.h:26`、`kernel/sched/psi.c:1251`、调用方 `kernel/cgroup/cgroup.c:3816` 同步），`struct psi_trigger` 增 `of` 字段（`include/linux/psi_types.h`），但 `psi.c` 只导出 `psi_memstall_enter/leave`（`psi.c:1042/1072`）→ `psi_trigger_create` **未导出**，厂商 .ko 无法引用，无 modversions 漂移。
- **`drivers/base/power/main.c` 的 `__pm_runtime_disable(dev, false)` → `pm_runtime_disable(dev)`（commit 14f326fc160d，实测位置 1384-1392 行附近）**：`check_resume=true` 会让 `__pm_runtime_disable()` 先 `pm_runtime_barrier()` 冲刷挂起请求再禁用 runtime PM，方向是"更安全"（消除 suspend 期间设备被 runtime resume 的竞态），与 B-01 属同一上游系列，无独立缺陷。
- **`drivers/base/power/domain.c` genpd detach 补 `pm_runtime_disable()`（commit c2a84f3a54c0）**：只对 genpd 自建虚拟设备（`dev->bus == &genpd_bus_type`）生效，修 attach/detach 的 runtime PM 计数不平衡，语义自洽。
- **`drivers/thermal/thermal_core.c`（commit c2a84f3a54c0）安全**：把 `thermal_set_governor(tz, NULL)` 从 `thermal_zone_device_unregister()` 移到 `thermal_release()`（:763），并补进注册失败路径（:1269）。本树 `thermal_set_governor()`（:97-118）只调 `unbind_from_tz` 并把 `tz->governor` 置 NULL，**没有 module_put/引用计数** → 不存在双重释放或 module 引用下溢；unregister 仍以 `device_unregister()` 收尾，release 恰好一次。**厂商 thermal-engine / thermal HAL 走的 `/sys/class/thermal/thermal_zone*/{type,temp,policy,...}` 与 default governor 语义未改**，且本次未改任何 thermal 头文件（无 CRC 影响）。唯一可感知差异：governor 的解绑推迟到设备 release（对反复注册/注销热区的厂商模块才有意义）。
- **`kernel/power/wakelock.c` 的 `--len`、`wakeup.c`/`wakeup_reason.c` 新增 EXPORT**：前者修 `pm_show_wakelocks()` 尾部多一个空格（纯显示）；后两者只**新增** `pm_system_cancel_wakeup`/`clear_wakeup_reasons` 导出，不动既有 CRC、不改语义。
- **`drivers/regulator/core.c` 失败路径 `regulator_lock_two(rdev, rdev->supply->rdev, &ww_ctx)`（commit c2a84f3a54c0）自洽**：`ww_ctx` 在同函数栈上已声明（`core.c:2073`），同函数另有一处同型调用（:2148）；"加锁→摘指针→解锁→put"顺序正确，避免了原来的 `_regulator_put()` 路径。
- **`drivers/gpu/drm/drm_gem_framebuffer_helper.c` 改用 `drm_format_info_plane_width/height()`**：对单平面/无子采样格式等价，对多平面 YUV 更严谨（不再用 hsub/vsub 去切非色度平面），是收紧而非放宽，不构成花屏/掉帧风险。
- **范围确认为"零改动"（可直接排除）**：`drivers/cpufreq/`、`drivers/cpuidle/`、`drivers/devfreq/`、`drivers/opp/`、`drivers/gpu/msm`(kgsl)、`drivers/gpu/drm/msm`(DP/DSI/panel)、`drivers/soc/qcom/`、`drivers/interconnect/`、`drivers/clk/qcom/`、`kernel/oplus_cpu/`、`drivers/soc/oplus/`、`techpack/`。判据：`git diff --name-status 7a244ff18620..HEAD -- <这些目录>` 无输出；本方向在该区间只命中 `drivers/thermal/thermal_core.c` 与 `drivers/gpu/drm/drm_gem_framebuffer_helper.c`。→ **GPU/显示/面板/CPU 调频/热控策略不会因本次内核改动而变化**；设备侧的 Scene + extreme_gt（伪造温度、解锁频点）属用户态，其"绕过热控"的后果需要 thermal HAL 侧证据（T-04/T-10），不在本报告结论范围。
- **厂商 walt/sched 扩展 .ko 在 opt47 上工作正常（正向证据）**：`/proc/sys/walt/sched_fmax_cap` 存在、可读可写，读到 `2265600 3148800 2956800 3302400`，与设备侧 Scene `powercfg.sh` 的写入值一致；`sched_sbt_enable=0`；`/proc/sys/kernel/sched_util_clamp_max=1024`（= 上游 ACK 该 sysctl 的最大值）。三点结论：① 提供 `/proc/sys/walt/*` 的厂商 .ko 在本次内核上**加载成功**，说明 B 方向改动（尤其 `pm_wq`、thermal、以及各 .c 类 sched 回移）**没有新增模块拒载**；② 该接口实现源码不在本树，无法静态审，本方向只能声明"未触碰"；③ 设备侧能读到 Scene 写入值，说明这条"用户态→内核"的限频通路在本版本上是通的，不需要按空操作处理。（数据来源：Lead 设备侧实测，今日 15:0x。）
- **未纳入本报告**：`block/ssg-iosched.c`（opt15-P21 SSG 电梯）与 `block/kyber-iosched.c` —— 虽与"调度"同名，但属 I/O 调度/storage 方向，请交给对应方向评述。

---

## 6) 方法学与局限

- 证据全部来自离线 git 对象与源码：`git log --oneline 7a244ff18620..HEAD`（40 条）、`git diff --name-status/diff 7a244ff18620..HEAD -- <目录>`、`git show <commit>`、对 `common/` 树的 `grep -rn`/`git grep`；每个 hunk 做"归属提交 → 提交说明 → 代码自身语义"三段核对。
- 只有 3 处属机主手工落地的"冲突块"（`b45c37a0c6b4` 的 `kernel/power/main.c`；`c2a84f3a54c0` 的 thermal/regulator/drm；`14f326fc160d` 的 `drivers/base/power/main.c` 与 psi），已逐个复核自洽性。
- 上游依据来自公开检索（未能在本机 fetch 全文，仅取到补丁标题/日期，见下），因此 B-01 保持"中"置信度，并把"回滚成本极低（1 行）"作为处置建议：
  - [PM: WQ_UNBOUND added to pm_wq workqueue（2025-09-19，Marco Crivellari）](https://lists.openwall.net/linux-kernel/2025/09/19/1064)
  - [PATCH v2: PM: sleep: Do not flag runtime PM workqueue as freezable（2025-12-05，Rafael J. Wysocki）](https://lists.openwall.net/linux-kernel/2025/12/05/976) / [同系列 v1（2025-12-01）](https://lkml.iu.edu/2512.0/01301.html)
  - [PM: Reconcile different driver options for runtime PM integration with system sleep（LWN 系列 0/9）](https://lwn.net/Articles/1026995)
- 设备全程离线（`adb devices` 为空），所有"影响"均为静态推理，已按条标注置信度与"需要什么证据"；未做任何实测、未改内核树、未刷机、未改设备状态。
