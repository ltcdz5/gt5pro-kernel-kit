# fengchi-boot 模块说明

配套「自编内核」使用的风驰自启模块。**只对特定自编内核有效**，单独刷没有任何作用。

## 版本

| 版本 | 说明 |
|---|---|
| **v2.7**（现役，versionCode 18） | 修「dmesg 真状态源恒空」：旧版把整份 dmesg（本 boot 约 2.1 MB）当作参数交给外部 `/system/bin/printf` ⇒ 恒 `E2BIG`（`Argument list too long`，`MAX_ARG_STRLEN`=131072）⇒ 真状态恒为空 ⇒ `HMBIRD_REQUIRE_REAL_STATE=1` 时保守拒绝切 scx（表现为「风驰只开一半」）。改为**单次快照落临时文件 + `grep` 读文件**，并把「读取失败」与「可读但本 boot 尚无信号行」拆成两种语义（哨兵 `FAIL`）。 |
| v2.6（versionCode 17） | D4 fail-closed 真正落地（未验证内核 / 低于 `MIN_OPT` 一律禁止半开）；真状态解析改为两路 dmesg 信号按时间序取最新 |
| v2.5（versionCode 16） | 按独立复核修 D1~D8；新增 `MIN_OPT` / `ALLOW_UNKNOWN_KERNEL` / `SAFE_RESTORE` 等闸门 |
| v2.0（versionCode 11） | 早前版本（本目录历史上只有这一版） |

★改 dmesg 解析时注意★：`dmesg` 全文**不能**放进变量再当参数传给外部命令（会 `E2BIG`），必须走管道或临时文件。

## 它做什么（全自动，装完重启即可）

1. **准备官方调度环境**：打开 `gameswitch` / `oiface` / `horae` 等开关，并拉起 `oiface`、`horae`、`gameopt_hal_service`、`vendor.urcc-hal-aidl`（风驰依赖它们）；
2. **按依赖顺序加载厂商模块栈**：`oplus_bsp_game_opt` → `oplus_bsp_sched_assist` → `oplus_bsp_sched_ext`，**风驰用的 `scx` 调速器就是最后那个注册的**；
3. **恢复 MGLRU**：写回 `/sys/kernel/mm/lru_gen/enabled=Y`、`min_ttl_ms=1000`；
4. **可选：拉起关键线程通路**（见下）；
5. **启动看门狗 + 守护**：守护检测到游戏就切 `scx`、打开 `ct_enable`；离开游戏满 `IDLE_DELAY` 秒后切回官方默认并还原 `ct_enable`。看门狗每 20 秒检查一次，守护万一挂了会**自动重启**。

## 文件清单

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块信息（管理器里显示的名字/版本/作者）|
| `service.sh` | **开机主脚本**：做上面 1~5 步 |
| `fengchi-watch.sh` | **看门狗**：守护挂了自动拉起（自身单实例）|
| `fengchi-gov.sh` | **守护**：轮询游戏状态，负责切/切回调速器、开关 `ct_enable`、心跳日志 |
| `fengchi.conf` | **配置文件**（见下）|
| `README.md` | 本说明 |

## 日志（都在 Download 目录，用文件管理器直接看）

| 文件 | 内容 |
|---|---|
| `/sdcard/Download/fengchi-boot.log` | 开机过程：环境、模块加载、MGLRU、关键线程、看门狗/守护是否起来 |
| `/sdcard/Download/fengchi-gov.log` | 运行记录：切到 scx、开/关 ctb、切回、看门狗重启、心跳 |

日志超过 `LOG_MAX` 行自动截断；`HEARTBEAT_MIN` 分钟会打一条心跳（便于确认它还活着）。

## 配置项（`fengchi.conf`）

| 配置 | 默认 | 说明 |
|---|---|---|
| `IDLE_GOV` | `uag` | 没有游戏时切回的调速器（OPPO 官方默认）；可填 `walt`；留空=不切回 |
| `SCX_GOV` | `scx` | 检测到游戏时切换到的调速器（正常不要改）|
| `POLL_SEC` | `4` | 轮询间隔（秒）|
| `IDLE_DELAY` | `10` | **离开游戏后延迟多少秒**再切回（避免切出去看一眼就来回切）|
| `HEARTBEAT_MIN` | `30` | 心跳日志间隔（分钟），`0`=关闭 |
| `LOG_DIR` | `/sdcard/Download` | 日志目录 |
| `LOG_MAX` | `2000` | 日志最大行数，超过保留最后 500 行 |
| `OPGS` | `1` | 是否自动拉起第三方**关键线程组件** |
| `CTB` | `1` | 是否在游戏时**自动打开 `ct_enable`**（退出还原）|

### 模式开关与闸门（v2.5 起新增，非必要不要改）

| 配置 | 默认 | 说明 |
|---|---|---|
| `HMBIRD_CTL` | `1` | 游戏时是否开启内核 hmbird；`0` 时脚本**不对 hmbird 做任何写或在线探针** |
| `GOV_SWITCH` | `1` | 游戏时是否切 scx；`HMBIRD_CTL=0` 时被强制为 0（禁止半开）|
| `SCX_REQUIRE_HMBIRD` | `1` | **顺序闸门**：只有 hmbird 真状态在线后才允许切 scx（必须保持 1）|
| `SAFE_GOV_PRELOAD` / `SAFE_GOV` | `1` / `uag` | 进游戏时若 gov 已是 scx，先切回 `SAFE_GOV` 再开 hmbird，使内核 `orig_gov` 保持为空 |
| `SAFE_RESTORE` | `1` | 允许在退出游戏 / 启动清理时把 governor 拉回 `IDLE_GOV`（即使 `GOV_SWITCH=0`）|
| `HMBIRD_REQUIRE_REAL_STATE` | `1` | 要求 dmesg 里出现 `rc=0, enabled=1` 的真状态行才允许切 scx；读不到就保守拒绝 |
| `HMBIRD_SETTLE` / `HMBIRD_PROBE_SEC` | `1` / `60` | 疑似意图残留时先写 0 等待的秒数 / 真状态已确认后重新核对的间隔 |
| `MIN_OPT` | `160` | 内核 opt 号下限，低于它一律 fail-closed（不可用 `ALLOW_UNKNOWN_KERNEL` 豁免）|
| `ALLOW_UNKNOWN_KERNEL` | `0` | `uname -r` 解析不出 `-optN` 时是否放行 |
| `ALLOW_NO_HMBIRD_SCX` | `0` | ★危险★ 置 1 才允许「没有 hmbird 也切 scx」|
| `ALLOW_BARE_SCX_AT_IDLE` | `0` | ★危险★ 置 1 才允许退出游戏后保留裸 scx |
| `KEEP_SCX_ON_IDLE` | `0` | 已废弃语义：置 1 会被忽略并打 WARN（要保留必须配 `ALLOW_BARE_SCX_AT_IDLE=1`）|
| `REASSERT_SEC` | `30` | 低频重申间隔：只在真状态在线且 governor 掉出 scx 时补一次；`0`=关闭 |
| `VETO_OFF` | `0` | 是否在启动时关掉 opt161 的策略层否决（`/sys/module/kernel/parameters/hmbird_gov_veto`，内容是 `N`/`Y`）。置 1 会拆掉唯一一道安全垫 |

逐条注释（含每个闸门的依据行号）都在 `fengchi.conf` 里。

改完配置：**重启生效**，或手动执行 `sh /data/adb/modules/fengchi-boot/service.sh`。

## 关于关键线程（critical_task_boost）

SM8650 的 `game_opt` 缺少 ctn（critical task name）输入功能，厂商的 `critical_task_boost` 拿不到线程名。
社区组件的做法：用一个 kmodule 补出 `/proc/game_opt/task_boost/critical_task_name` 节点，再用一个用户态守护轮询 `game_pid`、从 COSA 数据库取线程名写进去。

本模块**不包含、也不修改**这些第三方组件，只在检测到它们（默认 `/data/adb/modules/scrc/kmodule/`）时**自动帮你拉起**（`OPGS=1`）。
另外：`ct_enable` 默认是 0（由厂商 ROM/COSA 决定），不开的话线程名不会被采用 —— 所以本模块在游戏时把它置 1、离开后**还原原值**（`CTB=1` 时生效）。

> Unity 游戏其实不太需要这项：厂商侧本来就硬编码了 `UnityMain` / `UnityGfxDevice`。

### 相关节点（`/proc/game_opt/task_boost/`）

| 节点 | 含义 |
|---|---|
| `critical_task_name` | 需要监控的线程名（空格分隔，最多两个；由第三方守护写入）|
| `ct_enable` | 关键线程功能总开关（本模块在游戏时置 1）|
| `htb_enable` / `htb_strategy` | 厂商高负载开关/策略 |
| `target_fps` / `expire_time_percentage` | 厂商目标帧率与超时比例 |

## 怎么确认生效

~~~
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor   # 游戏时 scx，退出后 uag
cat /proc/game_opt/task_boost/critical_task_name              # 游戏时能打印线程名
cat /proc/game_opt/task_boost/ct_enable                       # 游戏时 1，退出后还原
~~~

## 出问题怎么排查

1. 先看 `/sdcard/Download/fengchi-boot.log`（开机那几步有没有失败）；
2. 再看 `/sdcard/Download/fengchi-gov.log`（有没有切换记录、有没有看门狗重启）；
3. 检查守护是否活着：`cat /data/adb/fengchi-gov.pid` 再看 `/proc/<pid>` 是否存在；
4. 看门狗是否活着：`cat /data/adb/fengchi-watch.pid`；
5. 手动重跑一次：`sh /data/adb/modules/fengchi-boot/service.sh`。

## 前置条件（不满足就没用）

- 配套的自编内核（OPPO 系 OKI 基线，6.1.141 那种）；
- 设备树 hmbird 类型为 `HMBIRD_OGKI`；
- 厂商模块在位（`oplus_bsp_sched_ext.ko` 及其依赖）。

## 注意

- **不要**用任何工具去「固定」风驰调度（实测会导致硬挂机）；
- 建议**卸载「官方调度屏蔽」类模块**（例如 IMS_VAROS），否则官调属性被清空、风驰不工作；
- 可能与 Scene 的调度设置冲突（未做完整测试），建议先关掉 Scene 的调度/调速器设置。

## 卸载

在 KernelSU / Magisk 管理器里移除本模块并重启即可；残留日志在 Download 目录，可自行删除。