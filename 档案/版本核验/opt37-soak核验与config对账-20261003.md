# opt37 soak 核验 + `/proc/config.gz` 对账（2026-10-03 16:4x）

> 机主插上手机后的**首次真机核验**。两条最重要的悬案（config 有没有真进运行内核、
> 有没有异常重启）**都已结案**。

---

## 一、★ `/proc/config.gz` 对账 —— **完全通过**

子代理最担心的那条是：「opt37 只改了 `gki_defconfig`（进 git）+ `out/.config`（**不进 git**），
而 builder 有两条 config 路径 ⇒ **没有证据表明线上镜像吃到了它**」。

**`CONFIG_IKCONFIG=y` + `CONFIG_IKCONFIG_PROC=y`（原厂也开着）⇒ `/proc/config.gz` 是运行内核的真值。**
实测结果：

### 应关的全关了（`is not set` 形态）
```
# CONFIG_UBSAN is not set                        ✓
# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set     ✓
# CONFIG_INIT_STACK_ALL_ZERO is not set          ✓
# CONFIG_ZRAM_MEMORY_TRACKING is not set         ✓
# CONFIG_RCU_NOCB_CPU_DEFAULT_ALL is not set     ✓
# CONFIG_CONT_PTE_HUGEPAGE is not set            ✓  ← 独立证实 HybridSwap 没编
# CONFIG_ZRAM_WRITEBACK is not set               ✓
```

### 应开的全开着（`=y` 形态）
```
CONFIG_INIT_STACK_NONE=y
CONFIG_COMPAT=y
CONFIG_CFI_CLANG=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_SHADOW_CALL_STACK=y
CONFIG_KASAN_HW_TAGS=y
CONFIG_HZ=300 / CONFIG_HZ_300=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_KFENCE_SAMPLE_INTERVAL=0
CONFIG_PANIC_ON_OOPS=y / CONFIG_PANIC_TIMEOUT=30
CONFIG_MQ_IOSCHED_SSG=y / CONFIG_LRU_GEN=y / CONFIG_LRU_GEN_ENABLED=y
```

⇒ **结论：opt37 的 config 改动确实进了运行内核；
被 `olddefconfig` 打掉的 `COMPAT`/`LTO`/`CFI`/`SCS`/`KASAN_HW_TAGS` 也都修回来并生效了。**
⚠️ 方法论：`/proc/config.gz` 里**关闭的项写成 `# CONFIG_X is not set`**，
所以"grep `^CONFIG_X=` 找不到"**就是"它是 n"的证据** —— 别误判成"没生效"。

---

## 二、soak 核验：**无异常重启，全部有主**

### 重启史（时间戳已换算）
| # | 记录 | 时刻 | 是谁 |
|---|---|---|---|
| 1 | `reboot` | **12:02:48** | **机主换模块**（Scene 内存优化 → noactive） |
| 3 | `1791000168` | 12:02:48 | 同上的时间戳 |
| 4 | `bootloader` | **04:08:29** | Lead 刷 **opt37** |
| 6 | `bootloader` | **03:17:18** | Lead 刷 opt36 |
| 8 | `bootloader` | **02:59:09** | Lead 刷 opt35 |

⇒ **没有一次"无来由重启"** ✓
旁证：`sys.boot.reason = reboot,`、`persist.sys.oplus.abnormalreboot_type = userspace request,`
⇒ **用户态主动重启**，不是内核。

### 健康桩子
```
uname -r = 6.1.141-android14-11-o-ltcdz5-version1-opt37
uptime   = 4 小时 37 分（自 12:02 那次）
lsmod    = 621        ✓
wlan0    = UP         ✓
SSG      = [ssg]      ✓
SELinux  = Enforcing   MGLRU = 0x0003   /data 88% 占用
pstore   = 0    真 oops = 0    KASAN = 0    UBSAN = 0    WARNING = 0
```

---

## 三、★ 那 9 次 PMIC 异常重启：**早于我们，不是我们造成的**

```
persist.sys.oplus.total_abnormalreboot_count = total_9_dump_0_pmic_9
                                                     ↑      ↑      ↑
                                                  9 次异常  0 dump  9 次 PMIC

persist.sys.system.abnormalboot = 2026-09-03 01:11:39:low battery poweroff
                                  ↑ 唯一有日期的异常启动记录 ⇒ 一个月前、低电量关机
persist.sys.oplus.clear_dump_pmic_count = no_clear   ← 计数器从未清零（累计值）
init.svc.clear_pmic_history = stopped                ← 有专门清它的服务
```

**判据**：我们**第一次刷机是 09-28**，而唯一有日期的异常启动是 **09-03**；
且本次会话全部重启都有主（机主 1 次 + 我们 3 次刷机）。
⇒ **那 9 次 PMIC 是历史累计、早于我们。**

### 📌 记为基线（以后若上升才是警报）
```
persist.sys.oplus.total_abnormalreboot_count = total_9_dump_0_pmic_9
（2026-10-03 16:41 采）
```

---

## 四、⚠️ 又躲过一个子串坑 + 又发现一个测量错误

### 子串坑
`dmesg | grep -ic 'pmic|watchdog|hard reset'` 命中 **407 行**，看着像"硬复位"。
实际全是 `OPLUS_CHG[ADSP]([handle_notification]): PD_CONNECT_HARD_RESET`
⇒ **USB Power Delivery 充电协议协商**，与系统复位无关。
（这是本项目第 4 次踩"子串当命中"：`libproce`**`ssg`**`roup`、`integrity`/`interact`、`HARD_RESET`…）

### 测量错误
我用 `ps -eLo comm | grep -c '^rcuo'` 数 `rcuo` 得到 **0**；
正确方法 `ps -A | grep -c rcuo` 得到 **10**（`rcuog/0` + `rcuop/0..7`）。
⇒ **换命令前先确认它真的能数到**（`comm` 字段在 `-L` 下的格式与预期不同）。

---

## 五、顺带核实的两条（更正文档的现场验证）

| 项 | 实测值 | 说明 |
|---|---|---|
| `vm.page-cluster` | **0** | 内核 `swap_setup()` 在 16 GB 机器上会设 **3** ⇒ 读到 0 说明**厂商用户态改过** ⇒ 证实"厂商故意禁掉换入预读" |
| `vm.swappiness` | **150** | 与 page_cluster 无关（证实更正1） |
| cmdline | **`rcu_nocbs=0-7`** | ⇒ 证实 `RCU_NOCB_CPU_DEFAULT_ALL` 被 bootarg 支配（更正2） |

### 顺带观察：本机 zram 换入换出量很大（4.6 小时）
```
pswpout = 18,740,351 页（≈73 GB）    pswpin = 10,221,428 页（≈40 GB）
pgmajfault = 10,694,401              zram mm_stat: orig 11.7 GB → comp 4.3 GB → mem 4.5 GB
```
⇒ 换入 1022 万次，每次只读 1 页（`page_cluster=0` ⇒ 无预读）。
**但这是厂商刻意选择**（`mm/swap_state.c:729-733` 注释：zram 上预读会导致 swap leak），
且 zram 读是内存操作、代价低 ⇒ **维持 0，不改**。

### 当前压力（低）
```
PSI cpu    some avg10 = 15.02%   full = 0.00%     ← 有 CPU 排队但无饥饿
PSI io     some avg10 =  0.18%   full = 0.00%
PSI memory some avg10 =  0.46%   full = 0.24%     ← 内存压力很低
D 状态进程: smcinvoke_adci_thread / crtc_commit:208 / usbtemp_kthread（手机常态）
```
