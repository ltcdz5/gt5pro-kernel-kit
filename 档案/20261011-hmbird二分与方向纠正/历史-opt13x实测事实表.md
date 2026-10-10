# 历史 opt13x 实测事实表（t19 交付）

- 作者：analyst · 2026-10-11 03:40 · **只读**历史材料，未碰设备、未改源码
- 材料：F:\工作区\_audit\ 下的 run*.log / run_opt*.log / t1*.log / kmsg*.log / matrix/ / *.md / HANDOFF.md
- 规则：**每一格都要有出处；找不到就写「无记录」；不用推断填表。**
- 重要前提：**run*.log 的编号 ≠ opt 编号**（例：`run110.log` 刷的是 opt109、`run112.log` 刷的是 opt110、
  `run137.log` 刷的是 opt132、`run138.log` 刷的是 opt133）。下表一律以 run 日志里的 `kernel=` 行为准。
- 「形态」分类：`存活` / `启用后 N 秒挂` / `写入即挂` / `卡 N 秒后恢复` / `自禁恢复` / `未测`

---

## 0. 一句话结论

**那条二分假设（「opt138 及之前不挂，opt139 起才挂」）证据不足，且现有证据倾向于不成立。**
理由三条（详见 §3）：
1. **opt138 实测跑完过测试且四格矩阵全过**（含 hmbird=1+gov=scx），但**同一版本在 20:46 的 hmbird+scx 现场硬挂过**；
2. 更早的族里 **opt118 / opt121 / opt127 都是「同版本一次过、一次挂」** ⇒ 故障是**偶发/条件相关**，不是版本开关；
3. opt139/140/141 三次测试用的是**三个不同脚本**（t139.sh/t140.sh/t141.sh）且 **governor 都是 performance**，
   而 opt137 的 402s 通过记录是 **governor=uag**；**没有任何一次是在相同条件下对比的**。

---

## 1. 表 A：opt137 → opt142（必答范围）

| 版本 | commit | 镜像 md5（我本地重算，与日志记录一致） | 是否上机 | 启用后形态 | 证据出处 | 当时 running |
|---|---|---|---|---|---|---|
| **opt137** | `e468f12d0793`（Stage CE；报告-CE-审核.md:1） | `ce40636d5fedff2de9e2c4f0b6ad9354`（run_opt137.log:2、报告-CE-审核.md:3，本地重算一致） | **是**（run_opt137.log:4-6：20:00:43 flash、20:01:07 kernel=opt137、20:01:08 start t141） | **存活**：BASE 60s → ENABLE rc=0 → 3 轮 8 核满载+磁盘 IO → 「关闭前 scx=1 **up=402 gov=uag**」→ 关闭 rc=0；异常计数 panic/WALT-BUG **= 0** | HANDOFF.md:1348-1371（20:07 实测记录）；run_opt137.log:6 只有 `start t141`、**无 DONE/END**（脚本自身日志不完整） | 无记录（t141.sh 不采 running） |
| **opt138** | `e11941647420`（Stage CF；报告-CF-审核.md） | `8ab99eda95f1e1ccf9f94910f4929768`（run_opt138.log:2、报告-CF-审核.md:265，本地重算一致） | **是**（run_opt138.log:5-7：20:36:46 flash、20:37:13 kernel=opt138、20:37:13 start t142） | **两种记录都在案**：<br>(a) 20:37–20:39 **脚本跑完**：`DONE marker after 105s` ⇒ 该次未挂；<br>(b) 20:46 **硬挂复位**（同内核，governor=**scx**）；<br>(c) 00:37–00:47 四格矩阵（含 h1_scx）60 样本**卡死=否** | (a) run_opt138.log:7；(b) HANDOFF.md:1408-1417（fengchi 日志 `[20:46:31] game -> scx` → 写 scx_enable=1 → 卡死 → `[20:53:57] watchdog: 守护不在，正在重启`）；(c) 报告-矩阵测试.md:5,66-71,106 + matrix/matrix.log | 无记录（opt138 时代脚本不采 running；矩阵采的是每核占用） |
| **opt139** | `0e3eec16d723` | `2e942fb51a7fbd9f47bee83d864617e3`（本地重算；run139.log 未记录 md5） | **是**（run139.log:5-6：01:40:58 kernel=opt139、01:41:03 start t139） | **启用成功后、8 核满载阶段硬挂**：t139.log 共 50 行，最后一行是 `=== 8-thread load 30s ===`，之后再无任何行；run139.log **无 DONE、无 pull、无 END** | t139.log:1-50（启用 01:41:07、util 诊断、idle baseline 八核 21–99%、然后进负载即断）；run139.log:6 | 无记录（t139.sh 不采 running） |
| **opt140** | `97bef96e73ee` | `b64e18e692cc87595fb4384b30ee9fb1`（本地重算；run140.log 未记录 md5） | **是**（run140.log:5-11：flash 成功、kernel=opt140、`DONE after 65s`、t140.log 3841B 已拉回） | **存活**：idle baseline → `--- still alive at 24s of load ---` → `--- SURVIVED 45s of 8-thread load ---` → 正常 disable → `T140_DONE` | t140.log 全文（含 `hmbird-dbg: BB util ...` 与 8 核 94–100% busy）；run140.log:7-11 | 无记录（t140.sh 不采 running） |
| **opt141** | `a5d5835a23d5` | `0277b6a12515fda9e1124b8126fb7470`（与任务书/夜间报告一致；本地重算一致） | **是**（run141.log:5-6：02:05:53 kernel=opt141、02:05:58 start t141） | **启用后约 8 秒内硬挂**：t141.log 只有 6 行 —— 02:06:03 `scx=1 p0=performance`、随后第一行空闲快照 `t=0s running=48 load1=8.76`，之后日志终止；run141.log **无 DONE、无 pull、无 END** | t141.log:1-7（该文件 432B）；run141.log:6 | **48**（t141.log:7，启用后第一个快照；基线 running=1~3） |
| **opt142** | `d0a46fbc52e7`（rev2；另有 rev1 镜像 `Image.opt142.rev1-58073e5c.bin` md5 `58073e5c2e4aa9604095f80647cdbf5b`） | `6bd5892488b218b6c1fe5e043df196bd`（本地重算；run142.log:3 记的 `boot md5=031e28...` 是**刷机前设备上 opt141 的 boot 分区** md5，不是本镜像） | **是**（run142.log:7-9：flash 成功、`booted kernel=...opt142 uptime=19`、`t142 started (foreground)`） | **存活但停摆，最后由 hmbird 自禁恢复**：enable 60.555s → 任务饥饿（`type(4) ux_page_pool_fi[1119] failed to run for 58.016s`）→ 121.858s `slim_walt_enable(0) from kthread_worker_fn` + `hmbird disabled finished`。**无 panic、无 WALT-BUG、无 psi** | dmesg_142.txt:17575（enable）、:18718（stall）、:18719-18720（自禁）；t142.log:165/246/327（t1/t2/t3 快照）；run142.log:11 `device unreachable at 55s (hang/reboot)`、:12 `done=False`、:13 `up_after=126` | **1 → 3 → 16 → 22**（t142.log:165/246/327 的 pre1/pre2/t1/t2/t3） |

### 1.1 表 A 的条件差异（关键：三次测试根本不是同一套条件）

| 版本 | 测试脚本 | 记录的 governor | 负载 | 结果 |
|---|---|---|---|---|
| opt137 | 脚本名为 `t141`（run_opt137.log:6） | **uag**（HANDOFF.md:1364 `gov=uag`） | BASE 60s + 3 轮 8 核满载+磁盘 IO | 存活 402s |
| opt138 | 脚本名为 `t142`（run_opt138.log:7） | **无记录**（run 日志不采 governor） | 未知（脚本已被 02:35 的 t142.sh 覆盖） | 脚本跑完 105s |
| opt138（20:46 那次） | 风驰守护（非测试脚本） | **scx**（HANDOFF.md:1409） | 进游戏 | **硬挂复位** |
| opt139 | `t139.sh` | **performance**（t139.log:3-6） | idle 5s + 8 线程 30s | 负载阶段挂 |
| opt140 | `t140.sh` | **performance**（t140.log:2-5） | idle 6s + 8 线程 45s | 存活 |
| opt141 | `t141.sh` | **performance**（t141.log:2,4） | 先 idle 30s | 启用后 ~8s 挂 |
| opt142 | `t142.sh` | **无记录**（t142.sh 的 knobs() 只读 p_ctrl/iso/iso_free/wd/sw，不读 governor） | idle 快照 + 8 线程 | 停摆→自禁 |

⇒ **没有任何一次是在「同脚本 + 同 governor + 同负载」下对比的。** 这是下面 §3 结论的直接依据。

---

## 2. 表 B：更早的「启用即挂」族（只列有 run 日志可证的）

| 版本 | 是否上机（证据） | 形态 | 证据出处 |
|---|---|---|---|
| opt104 | 是（run104.log:5 `kernel=...opt104`） | **启用测试期间设备消失（硬挂）** | run104.log 末两行：`[02:23:16] DEVICE_GONE during enable test` / `=== RUN104 END ===` |
| opt106 | 是（run107.log:5 `kernel=...opt106`） | 无明确记录（run 日志既无 DONE 也无 GONE） | run107.log:5-8（start t108 → 12:25:02 ROLLED_BACK） |
| opt107 | 是（run108.log:5 `kernel=...opt107`） | **存活 ≥43s 后掉线**：t108.log 心跳到 `hb28 up=65`（启用写于 up=32） | t108.log 全文（28 条心跳，无 TASKDUMP）；run108.log:7 `kernel=adb.exe: no devices/emulators found`（start 后 3 分钟） |
| opt109 | 是（run110.log:7 / run111.log:7 `kernel=...opt109`） | 两次不同：<br>(a) run110：**启用后 ~14s 挂**（`=== TASKDUMP1 up=41 ===` 后日志终止）<br>(b) run111：**写入即挂**（`E-enabling up=42` 之后再无任何行，pull timeout） | t110.log 全文；t111.log 全文；run111.log:9 `t111.log pull timeout` |
| opt110 | 是（run112.log:7 `kernel=...opt110`） | **存活 ≥7s**（启用写于 up=43，心跳到 `hb24 up=49`），之后无记录（回滚失败，设备仍停在 opt110） | t112.log 全文；run112.log:7-9 |
| opt111 | 是（run113.log:5 `kernel=...opt111`） | **卡 20 秒后恢复**（形态独特）：`hb21 up=42` → `hb22 up=62` → 继续到 `hb29 up=77` | t113.log 全文 |
| opt112 | 是（run114/115/116.log） | **无「启用后」记录**：t114/t115/t117.log 全程 `scx=0`（从未启用） | t114.log、t115.log、t117.log 全文 |
| opt115 | 是（run121.log:5 `kernel=...opt115`） | **软挂**（心跳到 `hb12 up=36` 终止） | t121.log 全文；run121.log:8-9 `NO DONE marker（可能软挂）`/`done=False` |
| opt117 | 是（run124.log:5 `kernel=...opt117`） | **软挂**（心跳到 `hb10 up=37` 终止） | t124.log 全文；run124.log:8-9 `NO DONE marker（可能软挂）` |
| opt118 | 是（run125.log:5 / run126.log:5） | ★**同版本一过一挂**★：run125 `DONE marker after 15s`；run126 `NO DONE marker（可能软挂）` | run125.log:8-9；run126.log:8-9 |
| opt120 | 是（run127.log:5 `kernel=...opt120`） | **软挂** | run127.log:8-9 `NO DONE marker（可能软挂）` |
| opt121 | 是（run128.log:5 / run129.log:5） | ★**同版本一过一挂**★：run128 `DONE marker after 100s`；run129 `NO DONE marker（可能软挂）` | run128.log:8-9；run129.log:8-9 |
| opt122 | 是（run130.log:5 `kernel=...opt122`） | **软挂** | run130.log:8-9 `NO DONE marker（可能软挂）` |
| opt123 | 是（run131.log:5 `kernel=...opt123`） | **软挂**（输出截断，模式同上） | run131.log:8-9 `NO DONE marker（可能软挂）` |
| opt127 | 是（run133.log:5 / run134.log:5） | ★**同版本一过一挂**★：run133 `NO DONE marker（可能软挂）`；run134 `DONE marker after 310s` | run133.log:8-9；run134.log:8-9 |
| opt128 | 是（run135.log:5 `kernel=...opt128`） | **软挂** | run135.log:8-9 `NO DONE marker（可能软挂）` |
| opt129 | 是（run136.log:5 `kernel=...opt129`） | **软挂** | run136.log:8-9 `NO DONE marker（可能软挂）` |
| opt132 | 是（run_opt132.log:5） | **通过**：`DONE marker after 270s`，并成功回滚到 opt58 | run_opt132.log:9,12 |
| opt133 | **未测**：flash 失败（找不到 repacked 文件），设备仍是 opt129 | — | run138.log:5-6（`flash fastboot: error: cannot load ...opt133-repacked.img` / `kernel=...opt129`） |
| opt135 | 上机了但**版本串不符**：刷 opt135 后 `uname -r` 报 **opt134** | 无结论（无 DONE/END） | run_opt135.log:5-7 |

---

## 3. 三个必答问题

### Q1：opt138 究竟有没有上机？结果是什么？证据在哪一行？

**上了机，而且测了两次以上，结果不一致：**
1. **上机**：`run_opt138.log:5` `[20:36:46] flash Sending 'boot_a' ... OKAY`；`:7` `[20:37:13] kernel=6.1.141-android14-11-o-ltcdz5-v1.1-opt138`。
2. **第一次结果 = 未挂**：`run_opt138.log:7` `[20:39:07] DONE marker after 105s` —— 脚本 `t142` 跑完并写下 done 标记；
   但同一行之后的 `:8` 显示拉日志失败（`adb: error: failed to stat remote object '/data/local/tmp/t142.log t142-kmsg.log'`，两个路径被当成一个参数），
   **且 /data/local/tmp/t142.log 后来被 02:44 的 opt142 运行覆盖** ⇒ **opt138 那次的详细内容永久丢失**，只剩「跑完 105s」这一条。
3. **第二次结果 = 硬挂**：`HANDOFF.md:1408-1417` 的守护日志：`[20:46:31] game -> scx`（governor 切到 scx）→ 写 `scx_enable=1` → ★系统卡死★ → `[20:48:24] idle(12)s -> uag` → `[20:53:57] watchdog: 守护不在，正在重启`。
   ⇒ 这次是 **opt138 + hmbird=1 + governor=scx**（当时设备上就是 opt138：run_opt138.log:12 `ROLLED_BACK kernel=...opt138` 说明回滚失败、仍停在 opt138）。
4. **第三次结果 = 未复现**：`报告-矩阵测试.md:5,66-71,106` + `matrix/matrix.log`：2026-10-11 00:37–00:47 在 opt138 上四格 (h0_uag/h0_scx/h1_uag/**h1_scx**) 各 60 样本，**「卡死」列全为「否」**，异常计数全 0。

### Q2：「opt137/138 是 originally hung 的版本」这句话出自哪份文件的哪一行？

**在 _audit 全部 .md 语料里找不到这句话，也没有任何等价表述。**
- `grep -c originally`（全部 *.md）= **0**；`grep -c "functionally identical"` = **0**（我在 t19 里实际执行过）。
- 与之最接近的**实测**记录恰好相反：
  - opt137：`HANDOFF.md:1348` 标题「决定性成功：opt137 完整闭环实测通过」，`:1364` `关闭前: scx=1 up=402 gov=uag`，`:1369` `异常计数: panic/... = 0`。
  - opt138：`run_opt138.log:7` `DONE marker after 105s`；`报告-矩阵测试.md:106`「原始卡死（20:46，hmbird+scx 进游戏）在 opt138 上不可复现」。
- ⇒ 该句**无出处**（很可能是口头转述/记忆），**不是实测结论**。它能对应的唯一「挂」是 **20:46 那次**，而那次的条件是 **governor=scx**，
  与 opt137 的 402s 通过（governor=uag）**不是同一条件** —— 这才是「一句话看起来矛盾」的真正来源。

### Q3：每个版本的失败形态（形态不同 ⇒ 根因可能不同）

| 形态 | 版本（证据见 §1/§2） |
|---|---|
| **写入即挂**（enable 写后无任何后续心跳） | opt109（run111/t111） |
| **启用后 ~8 秒挂**（有 1 个快照，running=48） | **opt141**（t141.log:7） |
| **启用后 ~14 秒挂**（有 TASKDUMP 后终止） | opt109（run110/t110） |
| **负载阶段挂**（idle 正常、8 线程负载时死） | **opt139**（t139.log 末行） |
| **卡 N 秒后恢复**（心跳出现空档但继续） | opt111（t113.log：up=42→62 空档 20s，之后继续到 up=77） |
| **停摆后自禁恢复**（无 panic，watchdog 主动禁用） | **opt142**（dmesg_142.txt:18718-18720） |
| **存活**（测试跑完 / soak 通过） | **opt137**（402s）、**opt140**（45s 满载）、opt118（run125）、opt121（run128）、opt127（run134）、opt132（270s）、**opt138**（105s 脚本 + 四格矩阵） |
| **硬挂复位**（设备消失/重启） | opt104（DEVICE_GONE）、**opt138 的 20:46 那次** |
| **软挂**（NO DONE marker，`done=False`） | opt115、opt117、opt118(run126)、opt120、opt121(run129)、opt122、opt123、opt127(run133)、opt128、opt129 |
| **未测 / 记录无效** | opt133（flash 失败）、opt135（版本串报 opt134）、opt112（全程 scx=0 未启用）、opt106（无标记） |

⇒ **形态确实分三档**：①「写即挂/秒级挂」②「负载相关挂」③「停摆后自禁恢复」。
把这三档混为一谈是我们之前最大的方法论错误 —— 尤其 **opt142 的「自禁恢复」与 opt139/141 的「硬挂」不是同一种故障**。

---

## 4. 结论：那条二分假设

**证据不足（且现有证据倾向于「不成立」）。**

| 假设的两个分支 | 证据 |
|---|---|
| 「opt138 及之前不挂」 | **一半成立一半不成立**：opt137（uag）402s 通过、opt138 跑完 105s 脚本 + 四格矩阵全过 —— 但 **opt138 在 20:46（gov=scx）硬挂复位**；更早的 opt118/121/127 都出现过「一次过、一次挂」。⇒ 「不挂」不成立，只能写「**偶发/条件相关**」。 |
| 「opt139 起才挂」 | opt139（负载挂）、opt141（秒级挂）成立；**opt140 存活**、**opt142 只是停摆后自禁**。⇒ 也不是「opt139 起必挂」。 |
| 二分方向是否可用 | **当前不可用**：三次测试的脚本、governor、负载都不同（§1.1），单次样本无法区分「通过」与「偶发」（这正是审核在 `报告-矩阵测试-审核.md:161,188,222` 已经指出的方法论问题）。 |

**要把这条假设变成可用的判据，必须补齐三件事：**
1. **同一脚本**（建议就用 t142.sh，但要补采 governor）跑 opt138 与 opt139/opt141；
2. **同一 governor**（t142 没记 governor；opt139/140/141 是 performance，而 opt137 是 uag ⇒ 先统一到 uag 与 performance 各一组）；
3. **每配置 ≥3 次**（opt118/121/127 的一过一挂已经证明单次无意义）。

**另外一条零成本建议**：opt138 那次的 t142.log 已被覆盖，无法找回；但从现在起每次测试**先把 /data/local/tmp/t1xx.log 复制成带版本名的文件**（例如 `cp t142.log t142-opt138.log`）
并**把 governor 加进快照**（`cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor`），否则下一个人还会面对同样「日志归属不清」的问题。

---

## 附：本次用到的原始证据清单（可复核）

- run 日志：run104/105/106/107/108/109/110/111/112/113/114/115/116/117/118/120/121/124/125/126/127/128/129/130/131/133/134/135/136/137/138/139/140/141/142.log、run_opt132/133/135/137/138.log
- t 日志：t108/t110/t111/t112/t113/t114/t115/t117/t118/t119/t121/t124/t127/t128/t129/t130/t139/t140/t141/t142/t147.log（其中 t117/t118/t119/t121/t124/t127/t129/t130 全程 `scx=0` ⇒ **未启用**，不能当「启用后」证据）
- kmsg：kmsg107–kmsg119.log（本轮未逐条展开，属可选复核）
- 报告/纪要：HANDOFF.md（:1348-1371 opt137 实测、:1404-1430 opt138+scx 硬挂）、报告-CE-审核.md（opt137）、报告-CF-审核.md（opt138）、报告-矩阵测试.md + matrix/matrix.log（opt138 四格）、报告-矩阵测试-审核.md（:161/:188/:222 方法论批评）、报告-CD2-风驰全貌.md（opt138 现场快照）、报告-20261011-夜间-hmbird放置修复.md（opt139/140/141 汇总）
- 缺失/无效：**opt138 那次的 t142.log 内容已丢失**（被 02:44 的 opt142 运行覆盖）；**t139/t141 曾经缺失、现已找回**（t139.log 2038B、t141.log 432B，均在 2026-10-11 02:5x 后出现）；`run137.log`/`run138.log` 分别是 opt132/opt133 而不是 opt137/opt138。

---

## 附录 B（2026-10-11 03:5x，captain 三条更正 + 我自己的源码复核）—— **本表证据质量的重要修正**

### B1. /proc/hmbird_sched/hmbird_stats 的 21 个计数器是【硬编码 stub】⇒ 一切基于它们的推断作废

- **源码事实**：kernel/sched/hmbird_sched_proc_main.c:324-386 的 hmbird_stats_proc_show() 里，
  **第 326-356 行全是 seq_puts(m, "…:0, 0") 常量**（global stat / cpu_allow_fail / rt_cnt / key_task_cnt / switch_idx /
  timeout_cnt / total_dsp_cnt / move_rq_cnt / select_cpu / gdsq_cnt[0..9] / err_idx / pcp_timeout_cnt[0..7] /
  pcp_ldsq_cnt[0..7] / pcp_enql_cnt[0..7]），**只有 359-376 的 11 个字段是真变量**
  （SCX Enabled / Partial Enable / Slim Stats / Heartbeat / Misfit DS / Highres Tick Ctrl / Watchdog Enable /
  SCX Exit Type / SCX Rejected Tasks / Sched Ravg Window FPS / DT Version Type）。注册点 :514-516。
- **我给出的独立佐证（不需要设备）**：真正实现 stats_print()（kernel/sched/hmbird/hmbird.c:432）**第一行**会打印
  "-------------schedinfo stats :---------------"（:439）；而 t139.log / t142.log 里 /proc/hmbird_sched/hmbird_stats 的输出
  **没有这一行**、直接以 "global stat:0, 0" 开头 ⇒ **设备上可见的确实是 stub 版**。
  （另有第二份实现 kernel/sched/hmbird/hmbird_sched_proc.c:160-181 调 stats_print(buf,4096)，注册点 :457-459；
  同名 proc 路径 ⇒ 被 stub 版抢注。）
- **对本表的含义**：表 A/B 中我**没有**用这些计数器下结论；现在明确标注：
  **t139.log / t142.log 里的 hmbird_stats 块（含 gdsq_cnt[0..9]:0, 0）是 stub 输出，不能作为「DSQ 未被使用」或任何频次证据。**
- **连带撤回（我自己的 t2 报告）**：我在 t2 §7 建议「用 /proc/hmbird_sched/hmbird_stats 的 rq_nr/scxrq_nr 作 running 虚增判据」——**这是错的**：
  rq_nr/scxrq_nr 属于 **panic snapshot**（hmbird.c:4934-4944 get_hmbird_snapshot()，写入 struct panic_snapshot_t），
  **不是 proc 文件**；而且 hmbird_export.c:19-21,155-160 说明我们发布给 ROM 模块的 minidump 区是**全零的 4KB 缓冲**。
  ⇒ 该建议作废；要拿 rq->nr_running 必须**新加**一个真 proc 条目（属代码改动，不在本任务范围）。

### B2. /proc/hmbird_sched/slim_walt/ 与 slim_freq_gov/ 是 **ROM 模块**创建的 ⇒ 那里的 slim_walt_ctrl 不是我们内核那份

- captain 实测：这两个子目录存在（cat 返回 Is a directory），而**我们的树不创建子目录**（hmbird_sched_proc_main.c 只注册平级条目）
  ⇒ 目录只能来自 ROM 模块 oplus_bsp_sched_ext.ko（与 scx_gov_ctrl 是模块符号一致）。
- **对本表的直接影响**：t142.log 头部快照里的 sw=0，来自 t142.sh 的 knobs() 读的
  /proc/hmbird_sched/slim_walt/slim_walt_ctrl ⇒ **它反映的是模块自己那份 BSS**，与我们内核的
  slim_walt_ctrl（hmbird_sched_proc.c:33 / hmbird_misc.c:34，由 slim_walt_enable(1) 在 util_track.c:637 置 1）**无关**。
  ⇒ **凡把 sw= 当成「内核 slim_walt_ctrl」的推断一律作废**（opt139/140/141 的 util 生效是内核那份在起作用，与 sw= 读数无关）。
- 这也是「两份 slim_walt_ctrl 不共享」这条结论的**设备侧实证**（此前只有符号表证据）。

### B3. 「本机无 ftrace/kprobe」这条约束【作废】⇒ 未来取证清单更新

- captain 实测：kprobe 可用（echo 'p:hmbtest hmbird_update_task_ravg' > /sys/kernel/tracing/kprobe_events rc=0）；
  tracefs 可用（sched_switch 3 秒 20021 条）；**events/hmbird/ 存在**（hmbird_fatal_info / hmbird_update_history / scx_update_history）；
  events/schedwalt/（sched_enq_deq_task / sched_cpu_util / sched_load_to_gov …）与 events/sched_assist/ 存在；
  /sys/kernel/debug/sched/debug 可读（需先 mount debugfs）；sysrq 可用（需 sysrq=1）；/proc/kcore、/dev/mem 不可用。
- **对本表的含义**：历史格（opt139-142 等）**仍然是「无记录」**——不能用新能力回填过去；
  但从下一次测试起，**优先用 tracepoint 而不是 pr_info**，并且应把
  events/hmbird/hmbird_update_history + events/schedwalt/sched_enq_deq_task + events/sched/sched_switch
  三者同时打开（这正是 captain 正在做的决定性实验）。
- 建议把「同一次测试必须同时记录」的最小集合定为：
  policy*/scaling_governor（B2 的教训）+ procs_running（唯一没被 stub 化的全局量）+ tracepoint 三件套 + sysrq-l 的 CPU 栈。
