# 内核审核 · D 方向（config / ABI·CRC / 厂商 .ko 兼容 / 变砖与回滚）

- 被审树：`/home/builder/kwork/cctv18/repo/local/kernel_workspace/common`，HEAD = `5ddf8408b29a`（v1.1-opt47），基线 = `7a244ff18620`
- 设备：Realme GT5 Pro（RMX3888 / SM8650 / ColorOS 16）。**审核时设备离线**，设备侧证据全部取自机主自己留在 Windows 上的开机日志与镜像（见每条证据的绝对路径）。只读审核：未改内核树、未刷机、未动设备。
- 构建/工具资产根目录：`C:\Users\xutengfa\Desktop\gt5pro-kernel\`

---

## 1) 结论摘要（按严重度）

1. **【P1·实机已复现】厂商 `bluetooth.ko` 因 modversions CRC 漂移被拒载，opt47 的蓝牙整整一套（7 个模块）都没装起来。** 原因符号 `sk_filter_trim_cap`（厂商期望 `0xf5845708`，本内核 `0x43b2b8f0`）。证据：`C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg-opt47-baseline.txt:3504-3505、:3513`；对照 `C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg_stock.txt`（原厂开机日志，0 条失败、bluetooth.ko 正常装载）。这**不是本次审核新引入**：用 `gate_vko_crc.py` 跑 Sep 30 的 opt12 symvers，报的是同一个模块、同一个符号、同样的两个值 ⇒ 从 opt12 起一直存在，opt45/opt47 与它无关。
2. **【P2·实机已复现】厂商 `oplus_bsp_game_opt.ko` 缺 5 个 `__tracepoint_android_vh_scx_*`，拒载（err -2）。** 证据：`...\logs\dmesg-opt47-baseline.txt:5850-5853`（select_cpu_dfl / check_preempt_curr_scx / scx_cpu_exclusive）与 `:6203-6206`（含 scx_consume_dsq_allowed）。与 opt45（`83f9166efbd4` / `dfea5e50fd23`）**没有因果关系**：这两个提交只动 `kernel/sched/ext.c`（+17 行早退）与 `kernel/bpf/bpf_struct_ops_types.h`，且 `android_vh_scx_*` 在本树与全历史里都**从未存在**（`grep -rn android_vh_scx_ --include=*.c --include=*.h` 无命中；`git log -S android_vh_scx_select_cpu_dfl --all` 为空）。机主自己在 `F:\工作区\_gk2.sh` 里做的 genksyms 标定实验正是想把这批 hook 补回去。
3. **【P3·证据链矛盾，必须记账】kernel 的 `CONFIG_HZ` 已从 250 变成 300**（`stock_config.gz`=250、`opt2b.config.txt`=250 vs `opt15-p2.config`/`opt15-p4-final.config`/opt47 成品=300；由 `1df7a34f6453`=opt15-P5 录进 defconfig）。**但"厂商 .ko 是 HZ=250 编的"这一步我无法证实**：我原本想用 `U __msecs_to_jiffies`/`U jiffies_to_msecs` 判 HZ，实测 `include/linux/jiffies.h:293-296` 把这两个声明放在 `#if` **之外无条件 extern**，所以它们在 .ko 里出现**不能**推出 HZ（这条捷径已自我否证）。若 `stock_config.gz` 真是原厂内核的 /proc/config.gz，则厂商 .ko 与它同源（`dmesg_stock.txt:2` 横幅 `-o-g6ed3e67335d5` 与厂商 .ko 安装路径一致）⇒ HZ 失配成立，厂商定时器/超时全部短 16.7%；若厂商 .ko 其实按 300 编，则 opt47 反而与原厂对齐。**这是本次审核最需要设备/反汇编补证的一条**（见 §4 U-03）。
4. **【P3】加固整体弱化（opt13/opt37 有意为之）+ 一处意外反向**：`INIT_ON_ALLOC_DEFAULT_ON` 关、`INIT_STACK_ALL_ZERO`→`INIT_STACK_NONE`、UBSAN 全关（含 `UBSAN_TRAP`）、`KFENCE_SAMPLE_INTERVAL` 500→0；**外加 `SLAB_MERGE_DEFAULT` 从原厂 not set 被追加块改回 y**（Kconfig 明确警告 `gki_defconfig:843: warning: override`）——这不是减脂主题的一部分，属复制粘贴携带。
5. **【P3·交付物错配】`Anykernel3--lz4-zstd-bbg-v20260929.zip` 不是 opt47。** 它的 `Image` 横幅 = `6.1.141-android14-11-o-ltcdz5-up0914 … #9 … Tue Sep 29 13:58:50 2026`；opt47 成品 = `C:\Users\xutengfa\Desktop\gt5pro-kernel\images\boot-v1.1-opt47-repacked.img`（横幅 `… -v1.1-opt47 … #74-ack304-v1.1-opt47 … Sun Oct 4 18:13:06`，md5 `4ad29d109c597f018e30f2f908d5031a`）。设备现役 = opt47（`kernel-kit\README.md:163`「设备现役（已刷）＝v1.1-opt47」+ `dmesg-opt47-baseline.txt` 的横幅 + `kernel-kit\CHANGELOG.md:54-61`）。

---

## 2) 头条表：本次改动对厂商模块的**破坏面全表**（stock 能装 / opt47 装不上）

比对方法（可复现）：两份开机日志里取 `Loaded kernel module <路径>` 的 basename 做集合差。
- 原厂：`C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg_stock.txt`（横幅 `6.1.141-android14-11-o-g6ed3e67335d5 #1 SMP PREEMPT Mon Aug 10 17:46:19 UTC 2026`）→ 成功装载 **200** 个 .ko，**失败行 0**。
- opt47：`C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg-opt47-baseline.txt`（横幅 `#74-ack304-v1.1-opt47`，:2）→ 成功装载 **193** 个 .ko。
- 集合差：**只有下列 7 个（且全部属蓝牙家族）**；反方向（opt47 有、stock 没有）**为空**。

| 模块（.ko） | stock | opt47 | 直接原因（日志原文） | 对应功能 |
|---|---|---|---|---|
| `system_dlkm/kernel/net/bluetooth/bluetooth.ko` | 装载 | **拒载** | `bluetooth: disagrees about version of symbol sk_filter_trim_cap` → `Unknown symbol sk_filter_trim_cap (err -22)` → `Failed to insmod ... Invalid argument`（:3504-3505、:3513） | 蓝牙协议栈核心；**下面 5 个都依赖它** |
| `kernel/drivers/bluetooth/btsdio.ko` | 装载 | 拒载 | `unable to load .../btsdio.ko`、`Invalid argument`（:3515-3516） | SDIO 蓝牙传输 |
| `kernel/net/bluetooth/rfcomm/rfcomm.ko` | 装载 | 拒载 | `Device or resource busy`（:3520-3521） | 串口蓝牙 / RFCOMM |
| `kernel/drivers/bluetooth/hci_uart.ko` | 装载 | 拒载 | `Device or resource busy`（:3524-3525） | HCI over UART |
| `kernel/drivers/bluetooth/btqca.ko` | 装载 | 拒载 | `Device or resource busy`（:3528-3529） | 高通 QCA 蓝牙固件下载 |
| `kernel/drivers/bluetooth/btbcm.ko` | 装载 | 拒载 | `Device or resource busy`（:3532-3533） | Broadcom 蓝牙 |
| `kernel/net/bluetooth/hidp/hidp.ko` | 装载 | 拒载 | `Device or resource busy`（:3544-3545） | 蓝牙 HID（键鼠） |
| `vendor_dlkm/oplus_bsp_game_opt.ko` | 装载 | **拒载** | 缺 `__tracepoint_android_vh_scx_{select_cpu_dfl,check_preempt_curr_scx,scx_cpu_exclusive,scx_consume_dsq_allowed}`（err -2，:5850-5853、:6203-6206）；`C:\...\logs\modules-opt47.txt`（620 行）里**无**该模块 | 游戏调度/性能调优（厂商侧功能真空） |

> 计数口径提醒：Lead 独立算出的「opt47 失败 17 行 / stock 0 行、失败模块=7 个蓝牙家族模块」与上表一致；本表**多列一个** `oplus_bsp_game_opt.ko` —— 它的失败是 `Unknown symbol` 行（模块级 8 行 ×2 次尝试），不一定出现在 modprobe 的 `Failed to insmod` 计数里，但 `modules-opt47.txt` 里它确实不存在，原厂日志里它是 `oplus_bsp_game_opt(O+)` 正常装载。故**破坏面 = 7 蓝牙 + 1 游戏调优 = 8 个模块**。
> 另：`modules-opt47.txt` 实载 620 个模块（`/proc/modules`），机主的验收线写的是 621；这个差值与本表的 8 个失败模块口径不同（开机阶段日志只覆盖 200 个 .ko），建议统一口径后再下结论（见 U-02）。

---

## 3) 发现清单

| ID | 严重度 | 标题 | 证据（绝对路径 file:line / commit / 日志） | 触发条件 | 影响 | 建议 | 置信度 |
|---|---|---|---|---|---|---|---|
| D-01 | **P1** | `bluetooth.ko` CRC 漂移（`sk_filter_trim_cap`）拒载 → 整套蓝牙 7 模块失效 | `C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg-opt47-baseline.txt:3504-3505,3513-3516,3518-3533,3542-3545,3576-3580`；对照 `C:\...\logs\dmesg_stock.txt`（0 失败、bluetooth.ko 正常）；`C:\...\kernel-kit\tools\gate_vko_crc.py` 用 `/home/builder/opt13base/vmlinux.symvers.opt12` 复跑：`bluetooth.ko (1 个符号不符) sk_filter_trim_cap 厂商期望=0xf5845708 本内核=0x43b2b8f0` | 每次开机 modprobe bluetooth.ko | 蓝牙音频/耳机、蓝牙键鼠、车载蓝牙、BLE 全部不可用 | 找到改变 `sk_filter_trim_cap` **声明**（genksyms 视角）的那次结构体/原型改动并回退；用 `gate_vko_crc.py` 对每次构建做回归（该工具可读厂商 .ko 的 `__versions` 真值，不需要厂商提供 symvers） | **高**（实机日志 + 工具复现） |
| D-02 | **P2** | `oplus_bsp_game_opt.ko` 缺 5 个 `android_vh_scx_*` tracepoint | `C:\...\logs\dmesg-opt47-baseline.txt:5850-5853`、`:6203-6206`；引用方扫描：`vendor-ko\vendor_dlkm\oplus_bsp_game_opt.ko`（select_cpu_dfl / check_preempt_curr_scx / scx_cpu_exclusive / scx_consume_dsq_allowed / scx_sched_lpm_disallowed_time）与 `vendor-ko\vendor_dlkm\qcom_lpm.ko`（仅 scx_sched_lpm_disallowed_time，实测能装）；树内 `grep -rn android_vh_scx_ include/ kernel/` 无命中；`git log -S android_vh_scx_select_cpu_dfl --all` 为空 | 每次开机 | 游戏优化/调度模块缺失 | 二选一：① 按 `F:\工作区\_gk2.sh` 的标定链补回 `DECLARE_HOOK + EXPORT_SYMBOL_GPL` 并验证 CRC 与 `game_opt.ko` 记录的期望值一致；② 明确接受缺失并写入台账 | **高** |
| D-03 | **P3** | `CONFIG_HZ` 250 → 300（跨模块时序常量变更，且**任何 CRC 闸门都看不见**） | 250 侧：`C:\...\kernel-kit\refs\stock_config.gz`（`CONFIG_HZ_250=y/ CONFIG_HZ=250`）、`C:\...\kernel-kit\refs\opt2b.config.txt`、`C:\...\kernel-kit\configs\opt15c.config`；300 侧：`C:\...\kernel-kit\configs\opt15-p2.config`、`configs\opt15-p4-final.config`、opt47 成品内置 config（`scripts/extract-ikconfig images/boot-v1.1-opt47-repacked.img` 第 451-455 行）；defconfig `/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/arch/arm64/configs/gki_defconfig:831-832`；引入提交 `1df7a34f6453`（opt15-P5） | 启动即生效 | 机制：厂商 .ko 里 `msecs_to_jiffies()`/`jiffies_to_msecs()` 若被常量折叠就是**编进 .ko 的 HZ**，HZ 不进 modversions CRC ⇒ 全部闸门看不见。**方向仍取决于厂商 .ko 的实际 HZ（未证实）** | ① 设备在线时取一次 `su -c 'zcat /proc/config.gz | grep CONFIG_HZ'`；② 或对任一厂商 .ko 反汇编一个常量参数的 `msecs_to_jiffies` 调用点，看是 `/4`（250）还是 300 的魔数；③ 结论出来前不要把这个 config 项当作"已对齐原厂" | 中（config 事实高；影响方向未定） |
| D-04 | **P3** | 加固减法四项（有意） | defconfig `gki_defconfig:833,848-852`；提交 `4e03a7d25409`(opt13)、`48e095183986`(opt37)；原厂对照 `stock_config.gz`：`INIT_ON_ALLOC_DEFAULT_ON=y`、`INIT_STACK_ALL_ZERO=y`、`UBSAN=y/UBSAN_TRAP=y/UBSAN_BOUNDS=y`、`KFENCE_SAMPLE_INTERVAL=500` | 启动即生效 | 堆/栈信息泄漏面变大；KFENCE 不再抽样=少一类内存错误早发现。属性能取舍，非功能失效 | 保留但写进台账的"已知安全弱化" | 高 |
| D-05 | **P3** | `SLAB_MERGE_DEFAULT` 被追加块反向打开（原厂 not set），**非有意** | `gki_defconfig:119` 已是 `# ... is not set`，`:843` 又写 `=y`；`make LLVM=1 ARCH=arm64 O=/tmp/dcfg gki_defconfig` 实测警告：`gki_defconfig:843: warning: override: reassigning to symbol SLAB_MERGE_DEFAULT`；成品 config 第 962 行 `=y` | 启动即生效 | 允许 slab cache 合并 ⇒ 堆喷射/跨 cache 利用更容易 | 删掉追加块里的这一行（正文 119 行已经是对的值），顺手清掉重复项 | 高 |
| D-06 | **P3** | `PANIC_TIMEOUT` -1 → 30 | 提交 `1df7a34f6453`；`gki_defconfig:761`；成品 config 第 7481 行；原厂 `CONFIG_PANIC_TIMEOUT=-1` | `PANIC_ON_OOPS=y` 下任何 oops | 从"永久卡死需长按"变成"30 秒自动重启"。**方向是好的**（pstore 仍留日志）；副作用是 boot 早期 panic 会成重启循环，抓日志窗口变短 | 保留 | 高 |
| D-07 | **P3** | defconfig 里的无效/重复行 | `gki_defconfig:826` `CONFIG_KSU_SUSFS=n`（Kconfig 无此写法）；`:831-832` `CONFIG_HZ=300` 与 `CONFIG_HZ_300=y` 重复；`:840` `SECTION_MISMATCH_WARN_ONLY=y` 与第 746 行 `# ... is not set` 冲突（Kconfig 亦报 override） | 构建期 | 静默失效/静默覆盖，后人复盘看不出真实意图；`SECTION_MISMATCH_WARN_ONLY` 把段错配从编译错误降级为警告 | 清一遍 defconfig，一项只留一处权威赋值 | 高 |
| D-08 | **P3** | 交付物与 HEAD 不同源（Sep 29 zip ≠ opt47） | `/home/builder/kwork/cctv18/repo/local/kernel_workspace/AnyKernel3/Image` 横幅 `...-o-ltcdz5-up0914 ... #9 ... Tue Sep 29 13:58:50 2026`（`strings`）；zip `/home/builder/kwork/cctv18/repo/local/kernel_workspace/Anykernel3--lz4-zstd-bbg-v20260929.zip`（9/29 13:59）；opt47 成品横幅 `#74-ack304-v1.1-opt47 ... Sun Oct 4 18:13:06` | 误刷旧件 | 会把设备刷回 up0914 的旧内核（落后约 30 个提交，含 sched_ext 挂死修复之前的状态） | 台账里把 Sep29 zip 标为历史件；**现役件判定依据 = 横幅构建号 `#74-ack304-v1.1-opt47` + `images\清单.txt` 的 md5 `4ad29d109c597f018e30f2f908d5031a`**（`kernel-kit\README.md:163` 同值） | 高 |
| D-09 | **P3** | 构建可复现性：BBG 是**未初始化**的 submodule；LTO 从原厂 NONE 改成 THIN | `/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/.gitmodules`（仅 `Baseband-guard` → `https://github.com/vc-teahouse/Baseband-guard.git`）；`git submodule status` = `-a5b57f15d6b597a1bd157c42330fe80020b1d628`（前导 `-` = 未 checkout）；原厂 `LTO_NONE=y` vs 成品 config 第 740-746 行 `LTO_CLANG=y/LTO_CLANG_THIN=y` | 重新 clone 后构建 | 只凭仓库无法复现构建（缺 BBG 源码，而 defconfig 里 `CONFIG_BBG=y`）；LTO 改变代码布局（`CFI_CLANG` 两侧都是 y，不影响 CRC） | 把 BBG pin 到 `a5b57f15` 并存一份离线副本；LTO 保留需给跑分/功耗依据 | 高（仓库事实）/中（影响） |
| D-10 | **P3** | 增补 LSM：`CONFIG_SECURITY_LANDLOCK`/`SECURITY_PATH`，且 `CONFIG_LSM` 插入 `baseband_guard` | 成品 config 第 6892、6870、**6901** 行：`CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,baseband_guard,smack,tomoyo,apparmor,bpf"`；原厂同串**不含** `baseband_guard`；BBG 源：`/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/Baseband-guard/baseband_guard.c:215-232`（只拦 `MAY_WRITE`）、`baseband_guard.h:11-28`（allowlist）、`tracing/tracing.c:46-95`（只对 su/magisk/ksu 域标 untrusted） | 根进程写块设备 | BBG 语义：**只**拦 untrusted（su/magisk/ksu）进程对**非 allowlist 块设备**的写与破坏性 ioctl，allowlist 内含 boot/init_boot/userdata/…，**不含 modem/recovery** ⇒ 用 root 脚本 dd 备份/烧 modem、或在 recovery 里以 su 域补分区会被 `-EPERM`；fastboot 刷机不经内核故不受影响。实机日志见 `dmesg-opt47-baseline.txt` 的 `baseband_guard: pid ... marked as untrusted` | 明确写进救砖预案（见 D-11/U-04）：BBG 在 `boot_a` 里，刷回原厂 boot_a 即消失 | 高（代码）/中（对预案的实际影响，需设备实测） |
| D-11 | **P2**（预案风险） | 回滚路径**本身完好**，但有两条会咬人的坑 | 资产：`C:\...\images\boot_a.img`（原厂，192 MiB，md5 `a33ff9988e5ffa6a40a13b1c8dad4abb`，`images\清单.txt`）、`init_boot_a.img`（root 所在，md5 `ea76e56955df78905caba1f0ba0a9090`）；流程：`C:\...\kernel-kit\救砖与回退-标准流程-20261001.md`「止损」段（`flash boot_a boot_a.img` + `set_active a` + `reboot`）；`dmesg-opt47-baseline.txt` 里 `verifiedbootstate=orange`（BL 已解锁，能刷） | 需要回退时 | ① 只写 boot_a ⇒ 刷回原厂 boot_a 一定能救（内核不改任何持久分区；本次审核**没有发现任何让原厂 boot_a 也救不回来的改动**）；② 但 `README-回退件已压缩.txt` 说明 42 个件里 25 个已压成 `.img.gz`，而救砖流程正文的核验命令只匹配 `*.img`，**照旧流程会漏件**；③ `getprop ro.boot.verifiedbootstate` 被第三方模块伪造成 `green`，判解锁只能看 `/proc/cmdline` | 按该文件自己的 2026-10-04 时效声明执行：核验只用 `images\清单.txt`（含压缩件），判解锁只用 `/proc/cmdline`；回退首选 `boot-v1.1-opt42-repacked.img`（md5 `4bd362b0a17513474de217ea9beb8ae3`，`kernel-kit\README.md:176`） | 高 |
| D-12 | **P3** | 已发布的"源码快照"与开发树 HEAD 不是同一个 commit | `C:\...\kernel-kit\CHANGELOG.md:69`「源码仓库 main 与分支 opt47 均为 `b195003b`」vs `kernel-kit\README.md:187`「开发树 opt47 = `5ddf8408`」 | 复盘/复现 | 审核报告里引用的 commit 与发布快照对不上，别人按发布快照复现会得到不同内容 | 在台账里写清两个仓库的对应关系（同一内容两种 commit id / 或明确谁是哪一版）；离线无法核对 `b195003b` | 中 |

---

## 4) 严重度定义（沿用任务书）

- **P0** = 可变砖 / 掉基带 / 数据永久损坏 / 无法开机
- **P1** = 严重功能失效 或 频繁重启挂死
- **P2** = 性能或功耗显著劣化
- **P3** = 隐患 或 加固弱化
（D-11 的"预案风险"按 P2 记：它不会让设备变砖，但会在救砖窗口里让人做错决定。）

---

## 5) 无法确认 / 需要实测

| # | 事项 | 缺什么证据 | 现在能说到什么程度 |
|---|---|---|---|
| U-01 | **CRC 真值闸门无法在当前树复跑** | `gate_crc_drift.py`/`gate_vko_crc.py` 需要候选 `vmlinux.symvers`；树的 `out/` 已清理，且脚本默认基准 `/home/builder/opt5-baseline/Module.symvers` 与 `/home/builder/opt15/vmlinux.symvers.opt15` **已不存在**（全盘只剩 `/home/builder/opt11probe/vmlinux.symvers.opt11`、`opt12probe/vmlinux.symvers.opt12`、`opt13base/vmlinux.symvers.opt12`，最晚 Sep 30） | 可用 `C:\...\kernel-kit\tools\gate_vko_crc.py` + 厂商 `vendor-ko`（493 个 .ko，`__versions` 是厂商真值）对 **opt12 symvers** 复跑：只有 `bluetooth.ko`/`sk_filter_trim_cap` 一项 ⇒ 说明该漂移早于 opt45/opt47。**要对 opt47 下结论，需要一次能跑通 `make Image` 的构建产出 symvers**（不刷机、低风险） |
| U-02 | 621（or 620）个 .ko 的完整验收口径 | 设备在线 `lsmod`/`/proc/modules` 与 `dmesg` 全量 | 现成 `C:\...\logs\modules-opt47.txt` = 620 行；开机阶段日志只覆盖 200 个 .ko。两个口径要先统一，否则"少几个"会被误读 |
| U-03 | **厂商 .ko 实际编译用的 HZ**（D-03 的关键分支） | ① 设备在线读 `/proc/config.gz`；② 或用 `llvm-objdump` 反汇编任一厂商 .ko 里**常量参数**的 `msecs_to_jiffies` 调用点（HZ=250 会折叠成 `(m+3)/4`） | 已自证不能用 `U __msecs_to_jiffies`/`U jiffies_to_msecs` 判 HZ（`include/linux/jiffies.h:293-296` 无条件 extern）。config 侧事实确定（250→300），影响方向待定 |
| U-04 | recovery 里 BBG 会不会挡住补分区 | 设备在线，进 recovery 用 su 域对 modem 分区写一次 | 代码层面：BBG 只拦 untrusted（su/magisk/ksu）进程的块设备写与破坏性 ioctl；fastboot 不受影响。**恢复模式里 adb shell 的 SELinux 域未知**，必须实测 |
| U-05 | 蓝牙 CRC 漂移的**根因**是哪个结构体/原型改动 | 需要把 `sk_filter_trim_cap`/`struct sk_buff`/`struct sock` 相关的头改动与厂商基线做一次 genksyms 对平（`gate0_type_diff.py` 只能比较两份自建 abidw 快照，**没有原厂 abidw 基线**） | 已确认不是 lz4/zstd、不是 opt40 的 ext4 结构体改动导致（opt12 上就已漂移）；具体是 ACK backport 还是 OPPO 合并带来的，需要原厂 ABI 基线才能定 |
| U-06 | 其余 `__tracepoint_android_vh_*` 是否还有别的受害者 | 我做的全量扫描（130 个引用名 × `C:\...\logs\kallsyms-opt47.txt`）给出 129 个"内核无此符号"，**这是假阳性**：该 kallsyms dump 带 CRLF（行尾 `\r`），锚定匹配失效；反证是 `oplus_vip_binder`/`oplus_binder_strategy` 这些引用 binder hook 的模块在实机上**装载成功** | 只能按实机日志下结论：**唯一**因 tracepoint 缺失而挂的是 `oplus_bsp_game_opt.ko`（引用 5 个 scx hook）；`qcom_lpm.ko` 引用 1 个但装载正常。全量比对需要先把 kallsyms 规范化（`tr -d '\r'`）再跑 |

---

## 6) 已复核且未发现问题（避免重复劳动）

| # | 事项 | 复核方式与结论 |
|---|---|---|
| V-01 | **`disable_module_crc_check.patch` 未被应用**（Lead 独立复核一致） | `/home/builder/kwork/cctv18/repo/local/kernel_workspace/common/kernel/module/version.c:53-55` 仍是 `pr_warn("... disagrees about version of symbol %s"); return 0;`；`git log -- kernel/module/version.c` 在 `7a244ff18620..HEAD` 内零改动。补丁本体在 `/home/builder/kwork/cctv18/repo/droidspaces_patch/disable_module_crc_check.patch`（763 B），内容是把 `return 0` 改成 `return 1`。**当前树保留 CRC 校验 = 安全侧**。若应用：D-01 会从"拒载"变成"静默装载 + 类型不匹配调用"→ 随机 Oops，属最坏一类（P0 级）。结论：**不要应用**，用 `gate_vko_crc.py` 替代它 |
| V-02 | **构建可复现性：gki_defconfig → opt47 成品 config 逐符号一致** | `make LLVM=1 ARCH=arm64 HOSTCC=clang HOSTLD=ld.lld O=/tmp/dcfg gki_defconfig`（rc=0）与 `scripts/extract-ikconfig images/boot-v1.1-opt47-repacked.img`（7641 行）比对：**非注释行差异 0 条**。opt15-P5 的"把 config 增量录进 defconfig"成立，**没有"只改 .config 没改 defconfig"的漏项**（`PANIC_TIMEOUT`/`HZ`/`UBSAN`/`KFENCE` 全部一致） |
| V-03 | `MODULE_SIG` 未变强制 | 成品 config 第 818-831 行：`MODVERSIONS=y`、`MODULE_SIG=y`、`MODULE_SIG_ALL=y`、`# CONFIG_MODULE_SIG_FORCE is not set` ⇒ 厂商/未签名 .ko 都不会因签名被拒；与原厂一致 |
| V-04 | `DM_VERITY`/`FS_VERITY`/SELinux 未削弱 | 成品 config 第 2168/2170（DM_VERITY/FEC）、`FS_VERITY`、6877/6899（`SECURITY_SELINUX=y`、`DEFAULT_SECURITY_SELINUX=y`）。AVB `OK_NOT_SIGNED` + `verifiedbootstate=orange` 与本次改动无关 |
| V-05 | `ZRAM` 仍为 `m` | 成品 config 第 1952 行 `CONFIG_ZRAM=m`，与原厂一致；实机 `[HYB_ZRAM]: Added device: zram0` 正常 |
| V-06 | **5 个"消失的导出符号"不构成问题** | `git diff 7a244ff18620..HEAD | grep -E "^[+-].*EXPORT_SYMBOL"` = +105/-32；32 行里 lz4/zstd/HUF/FSE 是补丁换文件位置（最终树各仍存在）；真正消失的是 `ufshcd_dealloc_host`、`l2tp_{tunnel,session}_{inc,dec}_refcount`。核对结论：`ufshcd_dealloc_host` 无任何厂商 .ko 引用；4 个 l2tp 符号虽被 `C:\...\vendor-ko\system_dlkm\l2tp_ppp.ko` 以 UND 引用，但**实机上 `l2tp_ppp` 装载成功**（`dmesg-opt47-baseline.txt` 出现 10 次、`modules-opt47.txt` 有它）⇒ 这些符号由厂商预装的 `l2tp_core.ko` 提供（模块间解析），不由 vmlinux 提供。**无实证危害** |
| V-07 | `HEADERS_INSTALL`、`SECTION_MISMATCH_WARN_ONLY` | 前者与原厂不同（原厂 `y`）但与本机自编目标无关（不是为外部模块构建头文件而编译）；后者是 D-07 的一部分（降级为警告），无运行时影响 |
| V-08 | opt45 的两处手术**没有**动导出/结构体声明 | `git show --stat 83f9166efbd4` = `kernel/sched/ext.c |17 ++` + `scripts/setlocalversion`；`dfea5e50fd23` = `kernel/bpf/bpf_struct_ops_types.h |14 +/4 -`（从 struct_ops 类型表摘掉 sched_ext_ops）。两者都不涉及 `EXPORT_SYMBOL` 增删，也与 `android_vh_scx_*` 无关（后者的受害人 D-02 是"从未存在"，不是"被 opt45 删掉"） |
| V-09 | 回滚资产齐全且可核 | `C:\...\images\boot_a.img`（原厂，md5 `a33ff9988e5ffa6a40a13b1c8dad4abb`）、`init_boot_a.img`（root，md5 `ea76e56955df78905caba1f0ba0a9090`）、现役 opt47（md5 `4ad29d109c597f018e30f2f908d5031a`）、回退首选 opt42（md5 `4bd362b0a17513474de217ea9beb8ae3`）——`images\清单.txt`（2026-10-04 20:41 生成）逐件有 md5。**只写 boot_a ⇒ 没有发现让"刷回原厂 boot_a"失效的改动** |

---

## 附录 A：原始证据摘录（可逐字核对）

**A-1 蓝牙拒载（`C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg-opt47-baseline.txt`，同日 18:26 抓取；横幅见 :2）**
```
[    0.000000] Linux version 6.1.141-android14-11-o-ltcdz5-v1.1-opt47 ... #74-ack304-v1.1-opt47 SMP PREEMPT Sun Oct  4 18:13:06 CST 2026
[    1.339104] modprobe: Loading module /system_dlkm/lib/modules/6.1.141-android14-11-o-g6ed3e67335d5//kernel/net/bluetooth/bluetooth.ko with args ''
[    1.341568] bluetooth: disagrees about version of symbol sk_filter_trim_cap
[    1.341579] bluetooth: Unknown symbol sk_filter_trim_cap (err -22)
[    1.343178] modprobe: Failed to insmod '.../kernel/net/bluetooth/bluetooth.ko' with args '': Invalid argument
[    1.343197] modprobe: LoadWithAliases was unable to load kernel/drivers/bluetooth/btsdio.ko
[    1.343381] modprobe: LoadWithAliases was unable to load kernel/net/bluetooth/rfcomm/rfcomm.ko
[    1.343403] modprobe: LoadWithAliases was unable to load kernel/drivers/bluetooth/hci_uart.ko
[    1.343498] modprobe: LoadWithAliases was unable to load kernel/drivers/bluetooth/btqca.ko
[    1.343668] modprobe: LoadWithAliases was unable to load kernel/drivers/bluetooth/btbcm.ko
[    1.345588] modprobe: LoadWithAliases was unable to load kernel/net/bluetooth/hidp/hidp.ko
[    1.351933] bluetooth: disagrees about version of symbol sk_filter_trim_cap        <- 第二次尝试
[    1.352150] modprobe: Failed to load module kernel/net/bluetooth/bluetooth.ko: Invalid argument
```
原厂对照 `C:\Users\xutengfa\Desktop\gt5pro-kernel\logs\dmesg_stock.txt`：`[1.345535] modprobe: Loaded kernel module .../bluetooth.ko`，全文 0 条 `Unknown symbol|disagrees|Failed to insmod`。

**A-2 `gate_vko_crc.py` 复跑（真值 = 厂商 .ko 的 `__versions`）**
```
$ python3 C:\...\kernel-kit\tools\gate_vko_crc.py /home/builder/opt13base/vmlinux.symvers.opt12 \
      C:\...\vendor-ko\vendor_dlkm C:\...\vendor-ko\system_dlkm
候选 vmlinux.symvers.opt12: vmlinux 导出 15388
厂商模块 493 个
解析成功 493 个；其中带非空 __versions 的 493 个
会拒绝装载的模块 = 1
  .../system_dlkm/bluetooth.ko   (1 个符号不符)
        sk_filter_trim_cap   厂商期望=0xf5845708  本内核=0x43b2b8f0
```

**A-3 config 关键差异（原厂 `stock_config.gz` vs opt47 成品内置 config）**

| CONFIG | 原厂 | opt47 | 备注 |
|---|---|---|---|
| `HZ` / `HZ_250`/`HZ_300` | 250 | 300 | D-03 |
| `INIT_ON_ALLOC_DEFAULT_ON` | y | not set | D-04 |
| `INIT_STACK_ALL_ZERO` / `INIT_STACK_NONE` | y / – | – / y | D-04 |
| `UBSAN`(+`TRAP`,`BOUNDS`,`ARRAY_BOUNDS`,`LOCAL_BOUNDS`,`SANITIZE_ALL`) | y | not set | D-04 |
| `KFENCE_SAMPLE_INTERVAL` | 500 | 0 | D-04 |
| `SLAB_MERGE_DEFAULT` | not set | **y** | D-05（非有意） |
| `PANIC_TIMEOUT` | -1 | 30 | D-06 |
| `LTO_NONE` / `LTO_CLANG_THIN` | y / not set | not set / y | D-09 |
| `HEADERS_INSTALL` | y | not set | 无运行时影响 |
| `SECTION_MISMATCH_WARN_ONLY` | not set | y | D-07 |
| `BBG`(+`BBG_BLOCK_RECOVERY`) | – | y / y | D-10（`BBG_BLOCK_BOOT` 未开） |
| `CONFIG_LSM` 串 | 不含 bbg | 含 `baseband_guard` | D-10 |
| `RCU_NOCB_CPU_CB_BOOST` | not set | y | 与 opt37 一致，未发现危害 |
| `MQ_IOSCHED_SSG`(+`_CGROUP`) | 无 | y | 电梯存在但非默认；属 B 方向 |
| `MODVERSIONS`/`MODULE_SIG`/`MODULE_SIG_FORCE` | y/y/– | y/y/not set | V-03 |
| `ZRAM` | m | m | V-05 |

**A-4 复核用命令**
```bash
# config 可复现性（只写 /tmp，不动树）
wsl -d Ubuntu-24.04 -u builder -- bash -lc "cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common && \
  export PATH=/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:\$PATH && \
  make LLVM=1 ARCH=arm64 HOSTCC=clang HOSTLD=ld.lld O=/tmp/dcfg gki_defconfig && \
  scripts/extract-ikconfig /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/boot-v1.1-opt47-repacked.img > /tmp/c.txt && \
  diff <(grep -v '^#' /tmp/dcfg/.config|sort) <(grep -v '^#' /tmp/c.txt|sort) | wc -l"
# CRC 真值闸门（当前树没 symvers；下面这行只用 Sep30 存档证明漂移早于 opt45）
python3 "C:\Users\xutengfa\Desktop\gt5pro-kernel\kernel-kit\tools\gate_vko_crc.py" \
  /home/builder/opt13base/vmlinux.symvers.opt12 \
  "C:\Users\xutengfa\Desktop\gt5pro-kernel\vendor-ko\vendor_dlkm" \
  "C:\Users\xutengfa\Desktop\gt5pro-kernel\vendor-ko\system_dlkm"
# 破坏面集合差
grep -oE "Loaded kernel module /[^ ]+\.ko" .../logs/dmesg_stock.txt | sed 's|.*/||' | sort -u > /tmp/S
grep -oE "Loaded kernel module /[^ ]+\.ko" .../logs/dmesg-opt47-baseline.txt | sed 's|.*/||' | sort -u > /tmp/O
comm -23 /tmp/S /tmp/O     # → 恰好 7 个蓝牙模块
```

*D 方向审核（只读）。报告中所有外部证据均给出 Windows 绝对路径；WSL 内部路径已标注 `/home/builder/...`。*
