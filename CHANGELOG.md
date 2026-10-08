# 版本变更日志（CHANGELOG）

**设备**：真我 GT5 Pro（pineapple / RMX3888，SM8650）· Android 16 · GKI 6.1.141 OKI
**版本串格式**：6.1.141-android14-11-o-ltcdz5-v族.次-opt构建序（见《版本号规范-20261003.md》）
**发布节奏与记录规则**：见《发布规范-20261004.md》
**状态词表**：★现役 ／ ✅交付（有上机核验台账） ／ 🖼产出镜像（images/清单.txt 可证） ／ 📦留档 ／ ⛔否证（禁止使用）

---

## 一、发布记录

### 已发布：v1.1-opt42（Release 在源码仓库，2026-10-04；观察期经一次作废重算，见下表）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt42 |
| git | tag v1.1-opt42 = 77aa56a8024c |
| 镜像 | boot-v1.1-opt42-repacked.img，md5 4bd362b0a17513474de217ea9beb8ae3（201,326,592 B） |
| 裸内核 | perf42/Image.opt42，md5 2e20e2c1b7dea60cdfee3d58a730a79f |
| 回退首选 | boot-v1.1-opt41-repacked.img，md5 8e449caedeb1791923393c9c4eb2245f |
| 源码快照 | 仓库 ltcdz5/gt5pro-kernel-src：**main 与 opt42 均为 a4428da6**（main 已于 2026-10-04 快进到现役 ⇒ 默认分支即现役源码） |
| Release | **建在源码仓库**：[gt5pro-kernel-src 的 tag v1.1-opt42](https://github.com/ltcdz5/gt5pro-kernel-src/releases/tag/v1.1-opt42) ⇒ 直接指向该版源码快照 a4428da6（**不建在工具仓库**） |
| 上机时刻 | 2026-10-04 01:12 刷入，现役 |
| 观察期状态 | **作废重算过 1 次**（《发布规范》§二 的首次实际应用）。原窗口 2026-10-04 01:12 → 10-05 01:12；**Scene 更新为 N1 2026.10 Alpha11**（lastUpdateTime = 2026-10-04 02:08）⇒ 外围更新即作废重算 ⇒ **新窗口 2026-10-04 02:15 → 10-05 02:15**。<br>发布本身经机主 2026-10-04 决定**提前发布**（按 §二属例外，记录在案）。 |
| 复核（2026-10-04 16:01） | 内核仍为 v1.1-opt42；槽位 _a；lsmod 621；oops 0；disagrees 0；连续运行 **13h46m**（ro.boot.bootreason = bootloader，非崩溃）⇒ 无异常重启。<br>**Alpha11 下限频器工作正常**（max 787200 / 1075200 / 960000 / 902400 ≠ 硬件最高）⇒ 导致上次事故的 LP 失效 bug **未复发**。 |
| 档位观察（**已确认符合预期 ⇒ 结案**） | **policy0 max = min = 787200**、p2 钉在 960000 上限（两次采样一致）；对比 2026-10-04 02:33 的 p0 max = 1132800 ⇒ 13 小时内被压低。限频器**在写值**，故**不属「失效」判据命中**（失效 = max 全为硬件最高）。<br>**机主 2026-10-04 确认：符合预期（即当前 Scene 档位）⇒ 不需处置。** |

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
| 代码审核 | 8 处改动逐条与上游修法一致（见《档案/闸门与ABI/审核-opt37到opt42代码审核-20261004.md》） |
| 上机健康（2026-10-04 02:33 实测） | 内核 6.1.141-android14-11-o-ltcdz5-v1.1-opt42；槽位 _a；governor uag x4；oops 0；lsmod 621 |
| 频率控制 | 限频器 max 1132800/960000/960000/902400；下限 min 787200/729600/729600/787200 ⇒ Scene LP 正常 |

---

### ★已发布：v1.1-opt47（2026-10-04 22:5x 发布；观察期 4.6 小时 —— **机主决定提前**）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt47（banner #74-ack304-v1.1-opt47） |
| git | 分支 opt47 = **5ddf8408**（基于 opt45） |
| 内容 | ① **i2c 适配器注册竞态**修复（`idr_alloc` 改存 NULL + 注册完成前 `idr_replace` 发布真指针；ACK `1febb174815b`）② `dev_set_name` 判返回值 ③ 失败路径补拆 Host Notify IRQ domain（取自 ACK `e984010cda7d` 的附带收益；**未取**它的 `adap->debugfs` 结构体改动） |
| 镜像 | boot-v1.1-opt47-repacked.img，md5 **4ad29d109c597f018e30f2f908d5031a**（201,326,592 B）；裸 Image f7dcb69f3828a62f95687bc4da262195 |
| 闸门1 | 新增=50 消失=1 ｜ 命中厂商 0/0 ｜ **遮蔽=0** → PASS |
| 闸门2 | 会拒绝装载 = **1**（仅 bluetooth 基线）⇒ 非蓝牙拒载 = 0 |
| 上机（18:20 刷入） | 内核/banner 正确、槽位 `_a`、**lsmod 621**、oops 0、**i2c 客户端设备 23 个已挂上**（⇒ 适配器确实已发布且可用） |
| 观察期 | 2026-10-04 18:20 → **2026-10-04 22:5x（发布时刻）≈ 4.6 小时**；⚠️ **未满 24 小时 —— 机主明确决定提前发布**，已记录在案并写进 Release 正文 |
| 与前身关系 | **supersede 掉 opt45-p2**（opt47 已含 opt45 的全部改动）⇒ opt45-p2 在本台账记为「未发布」 |
| 回退件 | opt42（4bd362b0a17513474de217ea9beb8ae3，已发布版）/ opt45-p2（4edea16d3046577b83dd3c8cf82be154） |
| **发布（2026-10-04 22:5x）** | **已发布**：Release 建在源码仓库 → https://github.com/ltcdz5/gt5pro-kernel-src/releases/tag/v1.1-opt47 |
| 源码快照 | 源码仓库 **main 与分支 opt47 均为 `b195003b`**；注释 tag **`v1.1-opt47`** |
| 逐版补丁 | `history` 分支 `build-history/0034..0038`（5 个，git format-patch 导出、**保留原始 SHA**；索引已更新为 38 个） |
| 发布前自检 | `tools/preflight.ps1` 全绿：双闸门 / 镜像 md5 / 清单 / 文档一致性 / 内容边界 / 归档索引 / 孤儿检查 均 PASS |

> 本版依据：ACK `android14-6.1-lts` 自 2026-10-02 起无新提交；10-02 当天的两条 i2c 修复经如实测「我们树两条都缺」，
> 其中第二条（`e984010cda7d`）整体不能取（会给 `struct i2c_adapter` 加成员 ⇒ 导出符号 CRC 漂移），只取它的两个附带收益。

### 探针版 v1.1-opt45（T0，**非发布**；⚠️ 已被 v1.1-opt47 supersede）—— 2026-10-04

| 项 | 值 |
|---|---|
| 目的 | 路线 C/T0：**让 sched_ext 干净失败**，不再硬挂死整机；同时作为「挂点定位」的第一枚探针 |
| 基线 | 从 **v1.1-opt42（交付版）** 建分支，**不含** opt43（scx 实验）/opt44（gov_override） |
| 改动 | 仅 kernel/sched/ext.c 的 scx_ops_enable() 开头插 14 行注释 + 3 行（mutex_unlock + pr_info + return -EOPNOTSUPP）；setlocalversion → -v1.1-opt45 |
| 镜像 | boot-v1.1-opt45-repacked.img，md5 **053cfb501c599fa3a6480c10ec498073**（裸 Image 16282506a336ccb8331618f4e70f5c9f） |
| 闸门 1 | 新增=50 消失=1 ｜ 命中厂商 0/0 ｜ **遮蔽=0** → PASS（与 opt42 完全相同 ⇒ 导出集合零变化） |
| 闸门 2 | 会拒绝装载 = **1**（只有 bluetooth / sk_filter_trim_cap 基线）⇒ 非蓝牙拒载 = 0 |
| 上机（16:41 刷入） | uname -r 正确、banner #71-ack304-v1.1-opt45、槽位 _a、**lsmod 621**、oops 0 |
| **测试结果（决定性）** | ① bt btftool struct_ops register（T0 应拦下）→ **仍然硬挂死**（uptime 归零、bootreason=reboot）<br>② 只 prog loadall（**不注册**）→ **同样硬挂死**<br>③ 对照：普通 array map 创建 + 普通 socket filter 程序加载 → **全部正常**（无挂死） |
| 结论 | **挂点在 BPF 对象加载 / struct_ops map 建立阶段，根本到不了 scx_ops_enable**（T0 的 pr_info 从未触发）<br>⇒ 路线 A 的「逐段短路二分」表作废（它切的全是 enable 内部）；B1 的「回移 efe231d9de 解锁」也打不到点上<br>⇒ 挂死是 **struct_ops 特有**，与普通 BPF 无关 |
| 观察期 | 若把 opt45 当交付版，窗口从 **2026-10-04 16:41** 起算（10-05 16:41 满）；但它是**探针版**，不作为发布候选 |

**探针 2（同日 17:20 刷入，banner #72）—— 把拦截层上移到 BPF 类型表**

| 项 | 值 |
|---|---|
| 改动 | 仅 kernel/bpf/bpf_struct_ops_types.h：不再注册 BPF_STRUCT_OPS_TYPE(sched_ext_ops)（保留 T0 那句早退，作第二层） |
| 镜像 | boot-v1.1-opt45-p2-repacked.img，md5 **4edea16d3046577b83dd3c8cf82be154**（裸 Image 60d964f748c5f1c56750833c6eb2b6ad） |
| 闸门 1 | 新增=50 消失=1 ｜ 命中厂商 0/0 ｜ **遮蔽=0** → PASS（导出集合与 opt42 完全一致） |
| 闸门 2 | 会拒绝装载 = 1（仅 bluetooth 基线）⇒ 非蓝牙 = 0 |
| 上机 | uname/banner 正确、槽位 _a、lsmod **621**、oops 0、disagrees 0 |
| **关键测试** | ① bpftool prog loadall simple.bpf.o → **rc=255 干净报错，uptime 不变、不挂死**<br>② bpftool struct_ops register simple.bpf.o → **rc=255 干净报错，不挂死**<br>报错原文：libbpf: struct_ops init_kern: struct bpf_struct_ops_sched_ext_ops is not found in kernel BTF |
| 结论 | ✅ **路线 C 的目标达成，且落在正确的层**：任何 sched_ext 的 BPF 调度器在这台机器上都是「一行干净报错」，不再是「整机硬挂死 + 看门狗重启」 |
| 遗留 | 限频器读数（刷入后 7 分钟时 max 仍=硬件最高）需复测，判断是 Scene 尚未接管还是又失效 |

> ⚠️ 本轮同时确认：**挂死在 BPF 加载阶段，与 scx_ops_enable 无关** —— T0 那层永远到不了，所以「逐段短路二分」（路线 A）在这种情形下无效；正确做法是在 **BPF struct_ops 类型表**上拦截。

## 二、全量版本明细（opt5 → v1.1-opt46）

> 改动摘要取 **git commit 标题原文**（不改写）；日期为 tag/提交日期。

| 版本 | git ref | 提交 | 日期 | 改动摘要 | 状态 |
|---|---|---|---|---|---|
| v1.1-opt47 | 分支 opt47 | 5ddf8408 | 10-04 | ACK 10-02 两条 i2c 修复：适配器注册竞态（`idr_alloc` 存 NULL + 注册完成前 `idr_replace`）+ `dev_set_name` 判返回值 + 失败路径补拆 IRQ domain | 🎯 设备现役·交付候选（观察期 10-04 18:20 → 10-05 18:20） |
| v1.1-opt46 | 分支 opt46 | 46457461 | 10-04 | BBRv3 全套移植（上游作者 20 补丁，2228 行换掉 tcp_bbr.c） | ⛔ 闸门2 判死 367/493（见第三节 §7） |
| v1.1-opt45 | 分支 opt45（交付清理 846c9c1b） | dfea5e50 → 846c9c1b | 10-04 | 摘掉 sched_ext 的 BPF struct_ops 类型（+ `scx_ops_enable` 早退作第二层）⇒ sched_ext 加载干净报错、不再硬挂死整机 | ⛔ **已被 v1.1-opt47 supersede**（内容已并入 opt47，见 §一）⇒ **未发布** |
| v1.1-opt44 | tag v1.1-opt44 | 66b2bf8c | 10-04 | 新增可写 governor 入口 gov_override（为已放弃的 LSE 解锁第三方 governor） | ⛔ 未交付（见第三节 §4） |
| v1.1-opt43 | tag v1.1-opt43 | 5ed2774c | 10-04 | scx 部分接管实验：去掉 enable 的无条件 switch_all | ⛔ 硬挂死，已否证（见第三节 §3） |
| v1.1-opt42 | tag v1.1-opt42 | 77aa56a8 | 10-03 | USB gadget bRequestType 位域误判 + LZ4 armv8 Permtable 越界读 | ★已发布（回退首选） |
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
| opt15-p20 | tag opt15-p20 | d8e827ea | 10-02 | 补齐 945be0af8244 posix-cpu-timers UAF 修复的**缺失那半**（生产者 `smp_store_release(&tsk->sighand, NULL)`）⇒ 三处配套齐全，**该 UAF 修复完整** | 🖼 |
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
| opt5 | 分支 opt5-state | 6f55c321 | 09-29 | regdb 内嵌 + 799 行干净 defconfig + ltcdz5 后缀 | ✅ |

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

### 7. v1.1-opt46 —— BBRv3 移植，**闸门2 判死**（367/493 模块会拒载）

**做了什么**：把上游作者本人（Mubashir Adnan Qureshi, Google）的 BBRv3 20 补丁系列（176 KB）用 git am -3 全套到分支 opt46（基于 opt45）：
20/20 全部套上，仅 net/ipv4/Kconfig 一处冲突（取 v3 描述 + 保留本树 TCP_CONG_BRUTAL 块）；**make rc=0**（22 文件 / +2200 −550，新增 net/ipv4/tcp_plb.c 并进 Makefile）。

**为什么判死**（同一条命令的对照）：

| 镜像 | 闸门1 | 闸门2（会拒绝装载的模块） |
|---|---|---|
| opt5 基准 / opt42 / opt44 | — | **1**（只有 bluetooth / sk_filter_trim_cap 基线） |
| opt46（BBRv3） | 新增=53 消失=1，命中厂商 0/0，遮蔽=0 → PASS | **367 / 493** |

- 共有符号 CRC 漂移 **2546 / 15437**（skb_pull、__alloc_skb、__dev_queue_xmit、__fib_lookup、wake_up_process …，连不相关的调度符号都被带变）
- 受害名单含 cnss2 / icnss2 / cfg80211 / mac80211（WiFi）、bluetooth / btqca、oplus_bsp_tp_*（触控）、hybridswap_zram / lz4k、sched_ext、game_opt ⇒ 刷上去 lsmod 会从 621 大幅掉落

**根因（逐行看过 diff，两点都不是「能折中」的）**：

1. include/net/inet_connection_sock.h：**ICSK_CA_PRIV_SIZE 104 → 144**
   —— 该成员是 struct inet_connection_sock 的**最后一个成员**，且它被 struct tcp_sock 内嵌 ⇒ TCP 侧 CRC 全线漂移。
   上游之所以要提这个数，是因为 **BBRv3 的 struct bbr 状态根本装不进 104B** ⇒ 这是「**装不下**」，不是写法问题。
2. include/net/netns/ipv4.h：struct netns_ipv4 新增 5 个 PLB 字段 ⇒ **struct net 变大** ⇒ 级联整个 net 子系统。

（唯一 ABI 安全处：include/linux/tcp.h 的位域复用 unused:5 → fast_ack_mode:2 + tlp_orig_data_app_limited:1 + unused:2，尺寸不变。）

**复现命令**：

    cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common   # 分支 opt46
    git checkout opt46
    python3 kernel-kit/tools/gate_new_exports.py out/vmlinux.symvers
    python3 kernel-kit/tools/gate_vko_crc.py out/vmlinux.symvers <vendor-ko 目录>
    # 期望：闸门2 = 367；同一条命令打 opt44 的 vmlinux.symvers 应为 1
    # 漂移计数：out/vmlinux.symvers vs perf44 的 symvers → 2546 / 15437

**留档要求**：分支 opt46 **保留不删**（否证档）；**编号不复用**（下一个正常版本从 opt47 起）；out/ 产物标 ⛔ 不可用（防误刷）。

**由此得到的通用硬约束（重要）**：改动「会被导出函数用作签名」的结构体（struct sock / tcp_sock / task_struct / net …）
⇒ genksyms 沿指针类型图递归展开 ⇒ CRC 成批漂移 ⇒ 厂商模块成批拒载。
上游「大版本特性移植」（BBRv3 / 新版 sched_ext / 风驰 hmbird）在本约束下**不可行**；
可持续的增量只有 **纯函数体修复 + config 层改动 + 删/禁类改动**。

---

## 四、字段来源与核对方式

| 字段 | 来源 | 怎么核 |
|---|---|---|
| 改动摘要 | git commit 标题原文 | git log --oneline |
| git ref / 提交 | tag 与分支 | git for-each-ref refs/tags、git branch -vv |
| 日期 | tag 创建日 | git for-each-ref --sort=creatordate |
| 状态 | 上机核验台账 + images/清单.txt | 见 kernel-kit 下各类 -上机核验-*.md |
| 镜像 md5 | images/清单.txt | 改文件后重跑 tools/images_出清单.sh |
| 否证原因 | 定案文档 | 档案/事故与更正/判砖实验-a4a5.md、档案/事故与更正/⛔事故-scx加载硬挂死-20261003.md、governor只读之谜-*.md、抖音功耗异常-根因定位与结案-*.md |
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

> ✅ images/清单.txt 已于 **2026-10-04 重生成**（49 行）：收录 opt40~opt45-p2 全部镜像，**不含 opt46**（BBRv3 判死、未产出镜像）。
> （此前 10-03 18:16 那版未收录 opt43 之后；按机主当日指示延后，现已随 v1.1-opt45 交付准备一并补齐。）

---

## 五、仓库级事件（非内核改动）

- **2026-10-04 · ACK 取证工具重写为 v2（修 fail-open）**：`tools/b1_fetch_ack.sh` 实测有三个缺陷 ——
  ① **源错了**：v1 走 `gh-proxy + aosp-mirror/kernel_common`，而该 GitHub 镜像**已冻结在 2025-11-19**
  ⇒ 收获窗口永远停在那儿，以往「ACK 没有新东西」的判断可能是**假象**；权威源 `android.googlesource.com/kernel/common`
  （分支 `android14-6.1-lts`）实测 tip = **4056c236e4c8**（Greg Kroah-Hartman，2026-10-02 11:49），仍在合（commit 标题含「Steps on the way to 6.1.178」）。
  ② **fail-open**：v1 用 `| tail -4` 吞掉 git 错误，取不到也照常往下走 ⇒ v2 改为 fail-closed：
  非零退出 / **任意一行 stderr** / 空结果 / tip 日期早于已知收获日（2026-10-02）⇒ 立即 `exit 3`。
  ③ **粒度粗**：v1 只到文件级 ⇒ v2 增加 `hunks` 子命令（文件 + hunk 数 + 增删计数）与「纯 .c 修复」筛选。
  新增子命令：`verify`（只校验源与新鲜度）/ `fetch` / `new`（上次收获日之后的新提交）/ `log` / `hunks`；
  v1 原样留档为 `tools/b1_fetch_ack.v1-ghproxy.sh`（不删，便于对照「为什么当年会误判」）。
  **结论修正**：stable 6.1.y 确实在 188 封顶，但 **ACK 没有封顶，是工具/限流封顶** ⇒ 这条线仍可持续投入，收益是**安全修复**（不是性能）。
- **2026-10-04 · 公开仓库内容边界清理**：按机主要求，移出 23 个与本项目无关的文件
  （第三方 GPU 模块原件 18 + 他人内核对照件 5），并把文档里对它们的产品名与细节匿名化（保留方法与结论）。
  随后**删除并重建 kernel-kit 仓库、历史重置为单提交** —— 原因：早期提交里含这些内容，
  仅删 HEAD 无法让它们从历史消失。旧提交 SHA 已不可访问；被清理资料移至机主本地归档。
  规则已固化为《发布规范-20261004》§八。
- **2026-10-04 · 第二批（机主追加「一起清」）**：再移出 2 个 —— 第三方 root 模块的审计文档、
  他人调研报告的**原文**（按 §八"不搬运原文"）；修掉 10 处引用。随后同样删库重建、历史重置为单提交。
  **验证**：远端 clone 全历史 grep 零命中；旧提交 SHA 返回 No commit found。
  被清理资料统一存于本地 archive/非本项目归档/（三批合计 25 个文件）。
- **2026-10-04 · 台账勘误（重要）**：`945be0af8244` posix-cpu-timers UAF 修复曾被标为「未补全、值得补」。
  实查三处配套**全在 opt42 树里**（`exit.c:214` 生产者 `smp_store_release` / `signal.c:1415` 消费者
  `smp_acquire__after_ctrl_dep` / `posix-cpu-timers.c` 锁定助手），该修复**早在 opt15-P20 即已完整**。
  误判源头是 P20 标题「生产者半边」的歧义措辞 —— 本意是「厂商漏掉的那半正是生产者」，
  却被读成「只补了一半」。已把未结案清单该项标 ✅ 已解决，并把「结论性措辞必须自解释」
  写进《发布规范》§七 第 6 条。
- **2026-10-04 · 闸门加固（对抗性评审发现，两处真实缺陷）**：
  ① `gate_new_exports.py` **补上「遮蔽」这一侧** —— 内核新导出 ∩ 某厂商模块**自己导出**的同名符号 ⇒ **FAIL**；
     模块侧基准从「本地 493 个 .ko」换成「**设备 622 模块的 4623 条 __ksymtab 导出名**」
     （ship 在 refs/mod-exports-622mods-4623.txt）。
  ② **判据顺序更正为「先判遮蔽、再谈补缺」** —— 原「①∩模块导出 ②被强引用且无人提供」的交集写法
     会同时命中同一条符号（`test_task_ux` 就是活例）。
  ③ 记下闸门 2 的盲区（对"内核未导出"的条目是 `continue` ⇒ 无法在改动前预警）与**刷机双判据**
     （Unknown symbol = 0 **且** disagrees about version = 0）。
  **正对照**：opt42 真实 vmlinux.symvers ⇒ 遮蔽 = 0、命中厂商 0/0、PASS（新规则不产生假阳性）。**验证方式**：本地 `ack3_gap/0060~0062__945be0af8244__*.patch`
  与树内三处逐行对得上。

---

*最近更新：2026-10-04（补齐 opt5 → v1.1-opt42 全量 changelog；建立发布规范；补写全部错误实验的机制级原因；修正 opt8 误标为「未上机」；内容边界清理与仓库重建）。*

---

## 六、v1.1-opt48（现役；观察期中，**尚未建 Release**）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt48 |
| git | 1c0304970586（源码快照分支：`opt48`） |
| 镜像 | boot-v1.1-opt48-repacked.img，md5 ae3989451bf046d61762677573f07d28（201,326,592 B） |
| 回退首选 | boot-v1.1-opt47-repacked.img，md5 4ad29d109c597f018e30f2f908d5031a |
| 上机时刻 | 2026-10-08 00:17 刷 boot_a，槽位 _a，现役 |
| 观察期 | 起算 2026-10-08 00:17；**因外围更新作废重算**（Scene 更新为 `N1 2026.10 Alpha13`，lastUpdateTime 2026-10-08 02:50）⇒ 新窗口 **2026-10-08 02:52 → 10-09 02:52** |
| 状态 | ★现役（观察中，按《发布规范》§二 未建 Release、未对外宣告） |

**本版改动**（13 文件 +122 −38）

1. f2fs：merged IPU 写提交补漏（新增 `f2fs_submit_all_merged_ipu_writes`）+ 压缩日志上限校验；
2. i2c：适配器注册竞态（`device_initialize`/`idr_replace`/`device_add` 顺序 + 新增 `i2c_deregister_clients`）；
3. rpmsg：char 设备 UAF；
4. arm64：`VM_FAULT_RETRY_VMA` 仅重试一次（`tried_vma_lock`）；
5. pKVM：`pvmfw_relinquished` 条件修正；
6. config/杂项：移除误入的 `CONFIG_SLAB_MERGE_DEFAULT`；`fwnode_init()` 补 `dev/flags` 清零。

**闸门与上机验收**

- 闸门 1（导出对账）：15437 / 新增 **0** / 消失 **0**；
- 闸门 2（厂商模块 CRC）：会拒绝装载 = **1**（仅 `bluetooth.ko`）；
- 上机：`/proc/version` = opt48、slot `_a`、`lsmod` = 621、`oops/BUG/panic` = 0/0/0、`disagrees about version` = 0；
- 连续运行核验（2026-10-08 12:55，uptime 36,164 s）：`kernel BUG / BUG: / WARNING: / Oops / panic / RCU stall / soft lockup / Unable to handle / Internal error / hung_task` **全 0**；`/sys/fs/pstore` 为空 ⇒ 凌晨 02:52 的 `ro.boot.bootreason=reboot` 为机主更新 Scene 的手动重启，**非崩溃**；5 条 `warn_alloc` 全部来自厂商驱动（`oplus_bsp_zsmalloc`/`hybridswap_zram`、`oplus_bsp_waker_identify`）在高内存压力下的大块分配告警，不在本版改动路径上。

**配套归档**：`档案/内核审核-20261007/`（总报告 + A/B/C/D 方向报告 + 2 份修复补丁）

---


## 七、2026-10-08 内核侧记录（opt49）
- **配置对照（出厂 × opt49）**：见 档案/性能功耗/配置对照-stock-vs-opt49-20261008.md —— 结论：KASAN/KFENCE/DEBUG_LIST/SCHED_DEBUG/SCHEDSTATS/BUG_ON_DATA_CORRUPTION 与出厂逐项一致（非本项目引入，按安全线默认不动）；我们相对出厂已少开 UBSAN、INIT_STACK_ALL_ZERO、KFENCE_SAMPLE_INTERVAL=0（现成的性能优势）；待议：HMBIRD_SCHED（出厂有我们无）、HZ 250 对 300、PANIC_TIMEOUT -1 对 30。
- **opt49（已构建待刷；镜像 md5 f285f54b2af95af56677d96f96f1b377 / 201,326,592 B）**：保留 NTFS3_FS(+LZX_XPRESS)、SQUASHFS(+XZ)、CIFS；**撤掉 MODULE_FORCE_LOAD 与 KSM** —— 闸门2 实测这两项会改核心结构布局（struct module / struct mm_struct）⇒ 厂商模块 modversions CRC 全数失效（实测 621 个全不匹配），「改结构 = 砖」被闸门拦下；另定案厂商源码缺陷：net/l2tp/l2tp_core.c 调用全树无定义的 l2tp_session_inc_refcount（modpost undefined）⇒ defconfig 显式 # CONFIG_L2TP is not set / # CONFIG_PPPOL2TP is not set（运行时由厂商 l2tp_core.ko / l2tp_ppp.ko 提供）。闸门结果：**闸门2 = 仅 bluetooth.ko 不匹配（非蓝牙拒载 0）**；**闸门1（替代法）= 候选 15443 / 基线 15437 ⇒ 新增 6、消失 0、无遮蔽**（cifs_arc4_* / cifs_md4_* / dns_query，全部来自 CIFS+DNS_RESOLVER，均未被厂商模块导出）。

## 八、v1.1-opt49-crc（现役；蓝牙修复版）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt49（内核版本串不变，仅覆写 1 个 CRC 值） |
| 镜像 | boot-v1.1-opt49-crc-repacked.img，md5 c40ee988904f2ea29720b0100b0ad124（201,326,592 B） |
| 回退首选 | boot-v1.1-opt49-repacked.img，md5 f285f54b2af95af56677d96f96f1b377 |
| 做法 | 构建后用 `tools/patch_crc_sk_filter_trim_cap.py` 把内核 `__kcrctab` 里 `sk_filter_trim_cap` 的值 0x43b2b8f0 → 0xf5845708（镜像内该值唯一出现 ⇒ 定点、4 字节、可审计） |
| 依据（为何不是盲改） | ① 从出厂 `boot_a.img` 抠出的 BTF 与我们的 BTF 逐块对比：`struct sk_buff`(221/221)、`struct sock`(142/142)、`struct sock_common`(70/70) **完全一致**；② 出厂镜像内 `0xf5845708` 唯一出现（0x161b8d8），我们的镜像内 `0x43b2b8f0` 唯一出现；③ 闸门2 显示 `bluetooth.ko` 除该符号外其余 96 个符号全部匹配 ⇒ **无真实 ABI 差异** |
| 排除的歧路 | 垫片说（`#ifdef __GENKSYMS__` 去掉后 CRC 变成 0xe69729c9，仍不等于期望值 ⇒ 不是它，已还原）；结构体说（BTF 证明布局一致） |
| 上机核验（2026-10-08 16:4x） | `bluetooth/hci_uart/btqca/btbcm/rfcomm/hidp/btsdio` **全部装载**；`sk_filter_trim_cap` 告警 **0**；`disagrees about version` 总数 **0**（原为 4）；`Unknown symbol` 4（只剩 gameopt 的 scx hook，已知）；oops/BUG/panic 0；**蓝牙 `state: ON`、`enabled: true`、地址已出** |
| ⚠️ 判据更新 | 「模块装载数 = 621」→ **628**（修复带来的新增装载，属预期增益）；「disagrees about version = 0」现在是**真 0**（原基线含蓝牙那 4 条） |

**发布记录（2026-10-08）**

- 源码快照分支：**`opt49`** = `8e2a46773322c680a450db8a52c83edc291b83bf`（内容 = 该版源码树 + LICENSE + NOTICE.md + 中文 README）
- Release：**`v1.1-opt49`**（建在**源码仓库**；按机主决定**提前发布**——属《发布规范》§二 的例外，记录在案；观察期本应到 10-09 16:41）
- 附件：`boot-v1.1-opt49-crc-repacked.img`（md5 `c40ee988904f2ea29720b0100b0ad124`）、`GT5Pro-RMX3888-v1.1-opt49-crc-AK3.zip`（md5 `13966f4df5e14c6289b4aff60b4380d9`）
- **AK3（自本版起提供）**：包内带 `horae_once-v1.0.zip`、`quiet_logs-v1.0.zip` 两个附加模块，刷内核后自动用 `ksud module install`（Magisk 回退 `magisk --install-module`）安装
- **蓝牙实测（机主）**：opt49-crc 刷入后 `bluetooth / hci_uart / btqca / btbcm / rfcomm / hidp / btsdio` 全部装载、`disagrees about version` = **0**、**蓝牙耳机连接与使用正常** ✓（本轮修复的最终验收）

## 九、v1.1-opt50（现役；厂商钩子回移版）

| 项 | 值 |
|---|---|
| 版本串 | 6.1.141-android14-11-o-ltcdz5-v1.1-opt50 |
| 镜像 | boot-v1.1-opt50-repacked.img，md5 4a2829cf415756107d3785157e7289cd（201,326,592 B）|
| 回退首选 | boot-v1.1-opt49-crc-repacked.img，md5 c40ee988904f2ea29720b0100b0ad124 |
| AK3 | GT5Pro-RMX3888-v1.1-opt50-AK3.zip（含 horae_once / quiet_logs 自动安装）|

**本轮改动**
1. 回移 5 个 OPPO 厂商钩子（android_vh_scx_select_cpu_dfl / android_vh_check_preempt_curr_scx / android_vh_scx_cpu_exclusive / android_vh_scx_consume_dsq_allowed / android_vh_scx_sched_lpm_disallowed_time），原型取自 OPPO/realme 官方源与社区补丁（Suxiaoqinx/scxe、oppo-source/android_kernel_oppo_sm8750、reigadegr/sun_action::patchs/6.1/6.1sched_ext.diff）。
   - 效果：**oplus_bsp_game_opt 由"被拒载"变为"可装载"**（设备 insmod 实测 = 1），游戏场景的调度/频率干预恢复。
   - 验收：刷机前比对 gameopt 的 124 个期望符号 ⇒ 缺失 0 / CRC 不符 0；5 个钩子 CRC 与模块期望值逐项一致。
2. CONFIG_HZ 300 → 250（与出厂对齐；tick 更少、厂商模块时间换算一致）。
3. 蓝牙 sk_filter_trim_cap CRC 定点覆写（延续 opt49-crc，构建后重新应用）。

**上机核验（2026-10-08 18:1x）**：版本串 v1.1-opt50、槽位 _a、HZ=250、gameopt 可装载、蓝牙 state:ON、Oops/BUG:/Kernel panic/Unknown symbol/disagrees about version **全 0**。

**过程坑（已修）**：① 首版构建被污染 —— skbuff.h 用 cp -a 还原后 mtime 早于目标文件，make 未重编，Image 内是"去垫片"的 0xe69729c9；touch 后重建恢复为 0x43b2b8f0 再定点覆写。② 构建脚本漏写 gki_defconfig ⇒ HZ 改动未生效；补上后 HZ=250。

**仍未做**：oplus_bsp_sched_ext（缺 19 个 hmbird/walt/scx 私有符号）与 HMBIRD_SCHED 底座 ⇒ 单独立项；KASAN/KFENCE/DEBUG_LIST/SCHED_DEBUG/SCHEDSTATS/BUG_ON_DATA_CORRUPTION 与出厂一致 ⇒ 按安全线默认不动。

