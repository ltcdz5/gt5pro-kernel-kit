# 内核审核 C：网络 / 外设 / 安全边界（含基带）

- 审核对象：Realme GT5 Pro（RMX3888 / SM8650 / Android 16 / ColorOS 16），自编内核 v1.1-opt47
- 内核树：`/home/builder/kwork/cctv18/repo/local/kernel_workspace/common`
- 基线 `7a244ff18620` → HEAD `5ddf8408b29a`（tag `v1.1-opt47`），范围内 205 文件变更
- 设备状态：本次审核设备离线，**全部结论为静态分析**；需实测项见第 4 节
- 只读审核：未改内核树、未刷机、未改设备状态

---

## 1) 结论摘要（按严重度排序）

1. **P3（未发现 P0/P1/P2）｜Baseband-guard（CONFIG_BBG=y）不是掉基带/IMS/VoNR 风险源。**
   它的所有拦截钩子都先做 `if (likely(current_process_trusted())) return 0;`，
   而"untrusted"只会被 `bb_bprm_set_creds()` 打给 **SELinux 域 = su / magisk / ksu 及其子孙**的进程。
   系统侧（init、qseecom/remoteproc、modem 固件加载、update_engine）恒为 trusted ⇒ 直接放行。
   另外所有钩子都有 `S_ISBLK()` 或块设备 dentry 前置判断，modem 固件加载不走块设备写入。
   证据：`Baseband-guard/tracing/tracing.h:18-22`、`tracing/tracing.c:34-96`、
   `baseband_guard.c:213-230`、`:381-399`。
   **结论：BBG 不会导致掉基带 / 信号 / VoNR / IMS / OTA 异常。**
2. **P3｜opt45 把 BBG 从悬空 gitlink 改成合法子模块：行为零变化。**
   链接仍是软链 `security/baseband-guard -> ../Baseband-guard`，子模块工作区干净
   （`git -C Baseband-guard rev-parse HEAD` = `a5b57f15d6b5`，`git status --porcelain` 为空），
   没有任何 C 代码改动 ⇒ 产物与运行行为不变。仅让 clone/子模块状态合法化。
3. **P3（潜在 P1，概率低）｜i2c 适配器注册竞态（opt47）只修了一半**：漏了上游前置提交
   `e984010cda7d` 引入的 `device_initialize(&adap->dev)`，导致 IDR 在
   `device_register()`（其内部才做 device_initialize）之前就公布了 kobject 未初始化的 device。
   窄窗口内 `i2c_get_adapter()` 会 `WARN` 且引用被吞 → 潜在过早释放/UAF。
   见 C-01。
4. **P3｜BBG 的 rename/setattr 保护是死代码**：`is_protected_blkdev()` 判空写反，
   有效 dentry 一律返回"未受保护"。属加固弱化（来自上游 BBG 子模块，非机主手写）。见 C-02。
5. **P3｜netfilter 四项修复（opt38）与 AF_PACKET 修复（opt41）、USB gadget 修复（opt42）经逐条
   核对均正确且完整**：ipset 空桶条件与上游 `ad92ee87462f` 逐字一致；AF_PACKET 修法与上游
   `ad9a0374ee6d` 代码一致且本树 `sock_queue_err_skb()` 确实安装 `sock_rmem_free` 析构；
   USB `bRequestType & USB_DIR_IN` 与 ACK/mainline 完全一致。**未发现"只修一半"留下的新崩溃面。**

---

## 2) 发现清单

字段说明：ID | 严重度 | 标题 | 证据 | 触发条件 | 影响 | 建议 | 置信度

### C-01 | **P3（命中即 P1）** | i2c 适配器注册竞态：IDR 提前公布 kobject 尚未初始化的 device

- **证据**
  - 本树 `drivers/i2c/i2c-core-base.c:1493-1515`：
    `dev_set_name()` → `idr_replace(&i2c_adapter_idr, adap, adap->nr)` → `device_register(&adap->dev)`。
  - 上游 ACK（`git show remotes/ack/a14-lts:drivers/i2c/i2c-core-base.c`）同一函数：
    `dev_set_name()` → `adap->dev.bus/type` → **`device_initialize(&adap->dev)`** →
    `idr_replace()` → **`device_add()`**。
  - `git log -S"device_initialize(&adap->dev)" -- drivers/i2c/i2c-core-base.c` 唯一来源 =
    `e984010cda7d`（`i2c: core: fix adapter debugfs creation`，签名区标注
    `Stable-dep-of: ba14d7cf2fe7`，即上游竞态修复 `1febb174815b` 的前置）。
  - opt47 提交信息原文：「未取的部分：e984010cda7d 的 adap->debugfs 会给 struct i2c_adapter
    加成员，而 i2c_add_adapter() 等是导出符号 => CRC 会漂移 => 正中闸门2，故不取。」
    —— 该提交同时含**与结构体无关**的 `device_initialize()` + `device_add()` 拆分，被一并丢弃。
- **触发条件**：`idr_replace()` 与 `device_register()`→`device_initialize()` 之间，另一线程调用
  `i2c_get_adapter(nr)`（`i2c-core-base.c:2483-2498`，内部 `get_device(&adapter->dev)`）。
  窗口仅几条指令；`/dev/i2c-N` 此时尚不存在（i2c-dev 的 bus notifier 在 `device_add` 中触发，
  那时 kobject 已初始化，故**不是** notifier 自身命中）。实际并发 `i2c_get_adapter()` 主要来自
  其它驱动的 probe，概率低。
- **影响**：命中时 `kobject_get()` 见 `state_initialized == 0` → `WARN(1)`；refcount 由 0 起算，
  随后 `device_initialize()` 把 kref 复位为 1，那次额外引用被吞 ⇒ 潜在过早释放/UAF ⇒
  最坏 oops/重启（本树 `CONFIG_PANIC_ON_OOPS=y`）。
- **建议**：把 `device_initialize(&adap->dev)` 前置到 `idr_replace()` 之前，`device_register()` 改
  `device_add()`（纯函数体改动，不碰结构体、不动导出符号 CRC），并按 C-05 补 `err_put_adap` 失败路径。
- **置信度**：代码事实 **高**；"实际能否撞上" **中**（缺设备实测）。
- 注：v1 曾标 P2，按任务书定义（P2=性能功耗劣化）复核后下调为 P3——命中后才是 P1。

### C-02 | P3 | BBG `is_protected_blkdev()` 判空写反 → rename / setattr 保护失效

- **证据**：`Baseband-guard/baseband_guard.c:232-241`
  `static inline int is_protected_blkdev(struct dentry *dentry) { struct inode *inode; if (!IS_ERR_OR_NULL(dentry)) return 0; ... }`
  调用者 `baseband_guard.c:324-352`（`bb_inode_rename` / `bb_inode_setattr`）都已先用
  `if (!old_dentry) return 0;` 排除空指针，所以该函数**恒返回 0**；
  `block_add()`（`:248`）永不执行，`blocked_devs` 哈希恒空。
- **触发条件**：任何 su 域进程 `rename()` / `chmod()` / `truncate()` 受保护块设备或其
  `/dev/block/by-name/*` 软链（BBG 设计上要拦的场景）。
- **影响**：BBG 自称修掉的「rename 绕过 / setattr 绕过」实际未生效。防写入
  （`file_permission`）、防破坏性 ioctl（`file_ioctl`: `BLKDISCARD/BLKZEROOUT/BLKPG…`）、
  防在 `/dev/block/by-name` 建软链（`inode_symlink`）仍然有效。属加固弱化，不导致砖。
- **建议**：改为 `if (IS_ERR_OR_NULL(dentry)) return 0;`。注意其后紧跟 `d_backing_inode(dentry)`，
  改方向后要确认无调用者传 NULL（`security_inode_setattr()` 自身已解引用 dentry ⇒ NULL 不可达）。
- **置信度**：高（代码事实）。缺陷源自上游子模块 vc-teahouse/Baseband-guard（a5b57f15），**非机主手写**。

### C-03 | P3 | BBG 白名单外块设备写入对 root（su 域）返回 -EPERM

- **证据**：`baseband_guard.h:1` `#define BB_ENFORCING 1`；`baseband_guard.h:14-24` 白名单
  = boot, init_boot, dtbo, vendor_boot, userdata, cache, metadata, misc, vbmeta,
  vbmeta_system, vbmeta_vendor（`CONFIG_BBG_BLOCK_BOOT` 未设 ⇒ boot/init_boot 在白名单内；
  `CONFIG_BBG_BLOCK_RECOVERY` 默认 y ⇒ **recovery 不在白名单**）；
  zram 额外特判（`baseband_guard.c:128-136`）；`baseband_guard.c:205-211` `deny()` 返回 `-EPERM`。
- **触发条件**：su/magisk/ksu 域进程写 `/dev/block/by-name/{modem,super,system,vendor,persist,recovery,…}`
  或 `/dev/block/sd*`。
- **影响**：root 下整分区备份/还原（如备份 `persist`、`modem`）会 EPERM，日志见
  `dmesg | grep "baseband_guard: deny"`。**不影响**：modem 自身固件加载（内核
  remoteproc/qcom_pil 从文件系统读镜像并写保留内存，不写块设备）、fastboot/recovery 刷机、
  OTA（update_engine 非 su 域）。
- **建议**：如需 root 下备份 modem/persist，把分区名加进 `allowlist_names[]`；否则保持现状
  （这是 BBG 的设计目的）。另建议评估 `bbg_log_deny_detail()`（`baseband_guard.c:173-203`）
  打印调用者 argv 的必要性（隐私/日志噪音）。
- **置信度**：高（代码事实）／中（"设备上实际拦到哪些调用"需实测 dmesg）。

### C-04 | P3 | opt45 子模块化改造：行为零变化（结论性一条）

- **证据**：`846c9c1ba805`（删除 160000 gitlink + 61 个 `.rej/.orig` 残留）、
  `6d61a69692ef`（新增 `.gitmodules`，gitlink 指向 `a5b57f15d6b5`，`git show --stat` 仅 2 文件）；
  `readlink security/baseband-guard` = `../Baseband-guard`（120000 软链，未变）；
  子模块工作区与 gitlink 一致且干净；`security/Makefile` 的 `obj-$(CONFIG_BBG) += baseband-guard/` 未变。
- **旁注**：`Baseband-guard/Makefile:27` 构建期执行 `git fetch --unshallow`（需网络；离线时静默
  失败，只影响内核里打印的 `BBG_VERSION` 字符串，不影响功能）。
- **置信度**：高。

### C-05 | P3 | i2c 注册失败路径：device 引用泄漏（上游已修，本树未取）

- **证据**：`drivers/i2c/i2c-core-base.c:1511-1515` `device_register()` 失败 → `goto err_remove_irq_domain`
  → 直接到 `1559-1567`，**无 `put_device()`**；上游 ACK 该路径为 `goto err_put_adap` →
  `init_completion + put_device + wait_for_completion`（对应 `01326c7d1453`）。
  基线（`goto out_list`）同样没有 put，故非 opt47 新增。
- **影响**：仅 `device_add` 失败时泄漏一个 device/kobject；无功能失效。
- **建议**：随 C-01 一并补上（同一处函数体改动）。
- **置信度**：高。

### C-06 | P3 | ipset dump 的 RCU 段内包含可能睡眠的销毁路径 + 注释引用不存在的函数

- **证据**：`net/netfilter/ipset/ip_set_core.c:1487-1498`（`ip_set_dump_done`）、
  `1697-1707`（`ip_set_dump_do` 的 `release_refcount:`）。全树 `ip_set_ref_netlink` 仅这 2 个使用点，
  **均已包住 ⇒ 无漏网点**（数组替换/释放点：`ip_set_core.c:1146-1152`
  `rcu_assign_pointer(inst->ip_set_list, list); synchronize_net(); kvfree(tmp);` 与 `2418`）。
  - 问题 A（文档）：新注释引用的 `ip_set_net_resize()` **本树不存在**，实际逻辑内联在
    `ip_set_create()`；不影响编译与行为。
  - 问题 B（隐患）：RCU 段内还调 `set->variant->uref(set, cb, false)`；对 hash 类型即
    `mtype_uref()`（`ip_set_hash_gen.h`），其 false 分支在 `atomic_dec_and_test(&t->uref) &&
    atomic_read(&t->ref)` 时执行 `mtype_ahash_destroy(set, t, false)` →
    `ip_set_free()`=`kvfree()`（实测该函数内无 `del_timer_sync`，只有 `kfree` + `ip_set_free`）。
- **影响**：本树 `CONFIG_PREEMPT=y` ⇒ PREEMPT_RCU，RCU 读段内睡眠不是硬性 atomic 违规，
  也不会自死锁；最坏是拖长宽限期（另一 CPU 的 `synchronize_net()` 多等一会儿）。不构成新 UAF。
- **建议**：RCU 段内只做 `set = ip_set_ref_netlink(inst, index)` 并取引用，把 `uref(false)`/`put`
  移到锁外；顺手修掉注释里的函数名。
- **置信度**：RCU 正确性 **高**；"是否真会睡眠" **中**（已确认无 del_timer_sync，仅 kvfree 路径）；
  实际触发窗口 **低**。

### C-07 | P3（交付卫生） | 树根残留 4 个补丁文件，且其中含已被拆除的"谎报 config" hack 文本

- **证据**：`ls -la *.patch` → `001-lz4.patch`(380KB)、`002-zstd.patch`(1.4MB)、
  `config.patch`(1.2KB)、`cve-2026-43499-rtmutex-6.1.patch`(2KB)；
  `grep -rn "001-lz4.patch|config.patch|cve-2026-43499" --include=Makefile --include=*.sh .` = 无引用。
  `config.patch` 内容为往 `kernel/Makefile` 注入 `config_fix`，把 `/proc/config.gz` 里的
  `CONFIG_IP6_NF_NAT=y` 改显示成 `n`（欺骗性 hack）。
- **已核实**：该 hack **当前未生效**——`grep -n "config_fix" kernel/Makefile` 无结果（`d56788d59a1f`
  「拆除 builder 注入的 config_fix」已生效），且 `arch/arm64/configs/gki_defconfig` 里
  `CONFIG_IP6_NF_NAT=y` 与 `CONFIG_IP6_NF_TARGET_MASQUERADE=y` 都是真的。
- **影响**：不影响产物；但发布源码快照时会被误认为"仍在谎报 config"，且 1.8MB 垃圾文件混在树根。
- **建议**：删除这 4 个文件（保留到 `other_patch/` 或 kernel-kit）。**不要**把它们留在内核树根。
- **置信度**：高。

---

## 3) 必答问题逐条回答

### Q1｜Baseband-guard 到底做什么？会不会影响 modem？opt45 修复是否改变行为？

- **做什么**：一个 LSM（`CONFIG_BBG=y`，LK2026-10-07 树中为顶层子模块 + `security/baseband-guard`
  软链），注册 `file_permission / file_ioctl / file_ioctl_compat / inode_setattr / inode_rename /
  inode_symlink / bprm_creds_for_exec / cred_transfer / cred_prepare` 九个钩子，
  目的是"阻止被 root 滥用的脚本格式化/破坏功能分区"。它把
  **SELinux 域为 `u:r:su:s0` / `u:r:magisk:s0` / `u:r:ksu:s0` 的进程（及其 fork/exec 后代，
  经 cred blob 继承）标记为 untrusted**，其余进程 trusted 且一律放行。
- **对 modem/IMS/VoNR 的影响：无。** 论证链：
  1. `current_process_trusted()` 默认返回 1（blob 由 `kzalloc` 零初始化，`is_untrusted_process=0`）,
     `bb_file_permission` 等都是 `if (likely(current_process_trusted())) return 0;`；
  2. 只有 su/magisk/ksu 域被置位；modem 固件加载由内核 `remoteproc`/`qcom_pil` 在自己的
     内核线程/工作队列中执行（无 su 域），且它读 `/vendor/firmware_mnt` 镜像写保留内存，
     **根本不做块设备写入**（钩子还有 `S_ISBLK` 前置判断）；
  3. OTA（update_engine）域也不是 su，不受影响。
- **对机主实际的副作用**：见 C-03（root 下备份/还原 modem、persist、super 等会 EPERM）；
  以及 C-02（rename/setattr 保护是死代码）。
- **opt45 的行为变化：无**（见 C-04）。
- **配置依赖（重要但已满足）**：`security/Kconfig` 的 LSM 默认串被改为含 `baseband_guard`；
  `Baseband-guard/Makefile:49-61` 在 `CONFIG_BBG=y` 但 `CONFIG_LSM` 缺 `baseband_guard` 时
  `$(error)` 中止构建。既然 opt47 构建成功 ⇒ `CONFIG_LSM` 必然含 `baseband_guard`，
  且 LSM blob 偏移机制（`security/security.c` `lsm_set_blob_size()` 把"需求大小"改写成"偏移"）
  保证 selinux 仍在 blob 偏移 0（`security/Kconfig` 默认串里 selinux 在 baseband_guard 之前）
  ⇒ **不会破坏 `cred->security` 布局，也不会让厂商 .ko 拒载**。

### Q2｜netfilter 四项（opt38）+ AF_PACKET cmsg（opt41）修复是否完整？是否留下新泄露/崩溃面？

| 项 | 修复 | 完整性判定 | 证据 |
|---|---|---|---|
| ipset dump UAF | 2 处 `rcu_read_lock/unlock` | **完整**（全树只有 2 个 `ip_set_ref_netlink` 使用点，均已包住） | `ip_set_core.c:1487-1498/1697-1707` |
| 同项隐患 | RCU 段内含 `uref(false)→mtype_ahash_destroy→kvfree` | P3 隐患，非新 UAF（PREEMPT_RCU 下不触发 atomic 报错） | C-06 |
| tcp_sack 非对齐读 | `get_unaligned_be32` | **完整且零风险**（arm64 上等价指令） | `nf_conntrack_proto_tcp.c:409` |
| exp_seq_show 对已释放 master 解引用 | 优先 `expect->helper`，回退判 `nfct_help()` | **完整**（字段存在 `nf_conntrack_expect.h:34`；对照点 `nf_conntrack_netlink.c:3050` 同模式） | `nf_conntrack_expect.c:658-676` |
| ipset 空桶永不释放 | `if (k == n->pos)` | **完整，与上游逐字一致**（上游 `ad92ee87462f`；ACK `a14-lts` 同款） | `ip_set_hash_gen.h:1089` |
| AF_PACKET 时间戳越界读（opt41） | `pkt_type == PACKET_OUTGOING && skb->destructor == sock_rmem_free` | **完整，与上游代码一致**；本树 `sock_queue_err_skb()` 确实安装该析构 | `net/socket.c:813-815`、`net/core/skbuff.c:4834`、`include/net/sock.h:1912`、上游 `ad9a0374ee6d` |

结论：**没有"只修一半"留下新的泄露/崩溃面**；唯一新增隐患是 C-06 的 RCU 段内睡眠（低危）。

### Q3｜USB gadget `bRequestType` 位域误判（opt42）影响哪些场景？位域语义是否正确？

- **语义正确**：`USB_DIR_OUT == 0x00`，旧代码 `ctrl->bRequestType == USB_DIR_OUT` 只在整字节为 0
  时判 OUT，其它 OUT 请求（如 RNDIS 的 `0x21`）被误当 IN 分支 `*temp = cpu_to_le16(USB_COMP_EP0_BUFSIZ)`
  ——把**对端给的 wLength 就地改写成 4096** 后继续下发。修后
  `if (ctrl->bRequestType & USB_DIR_IN) { clamp } else { goto done; }` 与 ACK/mainline 完全一致
  （`drivers/usb/gadget/composite.c:1702-1719` vs `remotes/ack/a14-lts` 同函数，逐行相同）。
- **实际影响面很小**：`USB_COMP_EP0_BUFSIZ = 4096`（`include/linux/usb/composite.h:41`），
  只有 `wLength > 4096` 的控制请求才进这段；这类请求本身就是协议违规。修后它们被
  `goto done;` ⇒ `value = -EOPNOTSUPP` ⇒ UDC stall ep0（规范做法）。
  - 充电识别：走 USB PD/typec（`drivers/usb/typec/*`，独立于 gadget composite），**不受影响**。
  - ADB(`f_fs`)/MTP/RNDIS：正常主机不会发 `wLength > 4096` 的 OUT 控制请求 ⇒ **无可见变化**；
    此前那种"clamp 后继续"的行为反而会破坏函数层对 wLength 的信任。
  - 结论：这是**堵住外部输入校验缺失**，不是功能回归。上游自 2021 年就是此形态。
- 同提交里的 LZ4 `Permtable` 越界读（`lib/lz4/lz4armv8/lz4armv8.S`）属压缩库/存储路径，
  按分工由 A/B 方向复核；此处只登记"该提交含第二处改动"。

### Q4｜i2c 适配器注册竞态（opt47）是否真闭环？失败路径是否补全？厂商 i2c 驱动是否受影响？

- **主线闭环**：是。`i2c_add_adapter()/__i2c_add_numbered_adapter()` 现在用 `idr_alloc(NULL)` 占位，
  `i2c_register_adapter()` 在 `device_register()` 之前 `idr_replace(adap)`（持 `core_lock`），
  于是 `i2c_get_adapter()` 要么拿不到（NULL），要么拿到**已初始化**的适配器。
  这正确对应上游 `1febb174815b`（`ba14d7cf2fe7`）的意图。
- **未闭环的部分**：上游把 `device_initialize()` 放在 `idr_replace()` **之前**（由前置提交
  `e984010cda7d` 引入），本树没有 ⇒ 见 C-01（窄窗口 + kobject 未初始化）。
  另上游同系列 `d69ce5908c0a`（注册失败挂死）、`01326c7d1453`（失败 NULL-deref）、
  `04187406258e`（irq domain 泄漏）中，本树只取了 `04187406258e` 的内容（本树原已有该形态），
  `01326c7d1453` 未取 ⇒ C-05（device 泄漏）。
- **失败路径补漏**：`dev_set_name()` 失败 → `err_remove_irq_domain` → `i2c_host_notify_irq_teardown()`，
  该路径在 `i2c_setup_host_notify_irq_domain()`（`:1486`）之后，**补拆是对的**；
  `device_register()` 失败同样会拆 irq domain（此前漏拆）。这部分补全正确。
- **厂商 i2c 驱动影响**：**无结构体、无导出符号变化**（`i2c_add_adapter` 等仍是 `EXPORT_SYMBOL`
  且签名不变），厂商 .ko（触控/相机/传感器）只需重新调用同一个导出函数；
  适配器对外可见时间由"进注册函数即可见"变为"完全初始化后可见"，这正是修复目标，
  对自注册自己 adapter 的厂商驱动是**行为改善**而非破坏。
  `i2c_get_adapter()` 的返回语义（拿到即带引用）未变。
- **置信度**：代码事实高；C-01 的"是否真撞上"中。

### Q5｜SELinux / LSM / security 是否有偏离上游的放权、去加固、关调试？

- **结论：没有发现放权/去加固/关调试。** 范围内 `security/` 变更只有 8 个文件：
  `security/Kconfig`（LSM 默认串加 `baseband_guard`）、`security/Makefile`（`obj-$(CONFIG_BBG)`）、
  `security/inode.c`、`security/keys/{internal.h,keyctl.c,keyctl_pkey.c,keyring.c,request_key_auth.c}`、
  `security/selinux/ss/conditional.c`。
- 逐项核实：
  - `security/inode.c` 删 `dget()/dput()` = opt11 的 stable 6.1.146..150 纯 .c backport
    （`4faf90660e27` 提交信息显式列出该文件），**不是机主自研**。
  - `security/keys/request_key_auth.c` 与本仓库 ACK 快照 `remotes/ack/a14-lts` **逐字节相同**
    （`diff -q` 结果 SAME）⇒ 纯上游 backport。
  - `security/selinux/ss/conditional.c` 由 `bbe1b4de1eba`（stable 6.1.151..188 批次）把
    `kmalloc_array` 改成 `kcalloc`（多零初始化）⇒ 方向是**更安全**，不是去加固。
  - defconfig 中 `CONFIG_SECURITY_SELINUX=y` 保留，新增 `CONFIG_SECURITY_LANDLOCK=y`、
    `CONFIG_SECURITY_PATH=y`（增加 LSM，不放权）；**未发现** `permissive`/`enforcing=0`/
    `androidboot.selinux=` 之类的放权改动（`grep -rn "selinux_enforcing|permissive|androidboot.selinux"` 无命中）。
- **BBG 是否可能误杀正常调用**：只在 su/magisk/ksu 域内可能（C-03 已量化）；系统域永不误杀。
  若要更保守，可评估把它从 `CONFIG_LSM` 默认串移除并改 `CONFIG_BBG=n`（但那就失去防格式化能力）。

### Q6｜有没有改动破坏厂商 .ko 的符号 / CRC 依赖（只写结论，闸门由 D 负责跑）

- 本方向**机主自研**改动共 6 个 net/ 文件 + 2 个 i2c/usb 文件 + BBG，逐条定性：
  - opt41：`include/net/sock.h` 只加 1 行函数**声明**；`net/core/skbuff.c` 把 `sock_rmem_free`
    去 `static`（**未加 EXPORT_SYMBOL**，只是 kallsyms 由 `t`→`T`）⇒ **不改任何已导出符号的 CRC**。
  - opt42：`drivers/usb/gadget/composite.c` 仅函数体内分支对调 ⇒ 无 CRC 影响。
  - opt47：`drivers/i2c/i2c-core-base.c` 仅函数体，未动 `struct i2c_adapter`（提交自述已声明
    为此拒收 `e984010cda7d` 的 debugfs 成员）⇒ 无 CRC 影响。
  - opt38：ipset/conntrack 四个 .c/.h 仅函数体/宏体，无结构体、无导出符号增删。
  - BBG：新增 LSM + 一个 cred blob（`cred->security` **分配尺寸**变大），不改导出符号、
    不改任何现有结构体布局；selinux blob 仍在偏移 0。
- **需要 D 闸门确认的一条残余风险**：defconfig 新增了一批 `=y` 的 netfilter/ipset/BPF_STREAM_PARSER
  （`IP_SET_*` 全系、`NETFILTER_XT_SET`、`NETFILTER_XT_MATCH_ADDRTYPE`、`IP6_NF_NAT`、
  `IP6_NF_TARGET_MASQUERADE`、`DEFAULT_BBR`、`NET_SCH_CAKE`、`DEFAULT_FQ`…）。
  若厂商 `system_dlkm/vendor_dlkm` 里存在**同名模块**（如 `ip_set*.ko`/`xt_set.ko`/`nf_nat*.ko`），
  内置后加载会因"duplicate exported symbol"失败。本机**无法静态验证**：host 上
  `/home/builder/kwork/kernel_manifest/workspace` 只有厂商**源码**（`vendor/oplus`、`vendor/qcom`），
  没有预编译 .ko，设备又离线。请 D 用其模块符号表工具确认。
  （机主的闸门记录写的是「闸门2 会拒绝装载的模块 = 1（system_dlkm/bluetooth.ko, sk_filter_trim_cap）」，
  未把 netfilter 列进去，倾向表明无冲突，但需 D 复核。）

### 附：netfilter/网络相关 config 变更的兼容性评估（Lead 线索 2）

- 新增项性质：`IP_SET=y + 15 个 ip_set 类型`、`NETFILTER_XT_SET=y`、`NETFILTER_XT_MATCH_ADDRTYPE=y`、
  `IP6_NF_NAT=y`、`IP6_NF_TARGET_MASQUERADE=y`、`BPF_STREAM_PARSER=y`、
  `TCP_CONG_{BBR,BRUTAL,VEGAS,WESTWOOD,HTCP,NV}=y`、`NET_SCH_CAKE=y`、`NET_SCH_ETS/PIE=y`。
  这些都是**内核侧功能使能**，iptables/ipset/netd 与之通过 netlink 通信并自行协商协议版本
  ⇒ **不产生用户态版本不兼容**；反而补上了 `IP6_NF_NAT`（此前被 `config_fix` 谎报为 n）。
- 两处**行为默认值**变更（非缺陷，但属"显著行为变化"，建议 B/L 方向主导确认）：
  - `CONFIG_DEFAULT_BBR=y` ⇒ 默认拥塞控制由 cubic 变 bbr；
  - `CONFIG_NET_SCH_DEFAULT=y CONFIG_DEFAULT_FQ=y` ⇒ 默认 qdisc 由内核默认（GKI 通常 fq_codel）
    变为 `fq`。二者配套（BBR 需 fq 做 pacing），与 netd 显式设置 qdisc 的行为不冲突，
    但对只依赖默认 qdisc 的第三方脚本/模块会有可见差异。
- `CONFIG_IP_SET_MAX=65534`（默认 256）⇒ 每个 netns 启动时要分配约 512KB 指针数组，
  内存代价可忽略。
- `CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"` ⇒ 法规库内嵌进内核，
  之后 `/vendor/firmware` 的 regdb 更新**不会**生效（除非重新编译内核）。这是 opt3 的有意设计。

### 附：Lead 线索 3（`other_patch/` 三补丁）核实结果

| 补丁 | 是否在当前树 | 证据 |
|---|---|---|
| `69_hide_stuff.patch`（伪造 `/proc/pid/maps` 中 lineage/jit-zygote-cache 映射、`/proc/pid/map_files` 路径替换） | **未应用** | `grep -rn "show_vma_header_prefix_fake" fs/proc/` 无命中；`grep -rn "lineage" fs/proc/task_mmu.c fs/proc/base.c` 无命中 |
| `apk_sign.patch`（给 KernelSU Manager 追加两个硬编码签名白名单） | **未应用且无关** | 树中无 `kernel/apk_sign.c`、无 `check_v2_signature`、无任何 `config KSU` Kconfig；全树 `grep -rln "susfs"` 无命中 ⇒ 本树**不含** KernelSU/SUSFS |
| `config.patch`（让 `/proc/config.gz` 谎报 `CONFIG_IP6_NF_NAT=n`） | **未应用** | `grep -n "config_fix" kernel/Makefile` 无结果（`d56788d59a1f` 已拆除）；defconfig 里 `CONFIG_IP6_NF_NAT=y` 是真的 |
| `cve-2026-43499-rtmutex-6.1.patch` | **已应用**（在 `372750608ecd` 里） | `git show 372750608ecd -- kernel/locking/rtmutex.c`：`remove_waiter()` 用 `waiter->task` + `scoped_guard(raw_spinlock, …)`；`include/linux/cleanup.h` 在基线即存在（`git log 7a244ff18620..HEAD -- include/linux/cleanup.h` 只有基线那条 revert），所以能编译。属 A/B 方向（核心锁），此处只登记 |

---

## 4) 无法确认 / 需要实测

1. **`CONFIG_LSM` 实际值**：gki_defconfig 只写 `CONFIG_BBG=y`，靠 `security/Kconfig` 改过的
   default 兜底；构建通过反证其含 `baseband_guard`，但建议设备在线时取一次实证：
   `adb shell su -c 'zcat /proc/config.gz | grep -E "CONFIG_LSM=|CONFIG_BBG|CONFIG_BBG_BLOCK"'`
2. **BBG 在真机上究竟拦过什么**：`adb shell su -c 'dmesg | grep -i "baseband_guard"'`
   （重点看是否出现 `deny write to protected partition`）。
3. **C-01 的窄窗口是否真被撞到**：
   `adb shell su -c 'dmesg | grep -iE "not initialized, yet kobject_get|i2c-.*: can.t register device"'`
4. **C-06 是否造成 RCU 抖动**：`dmesg | grep -iE "rcu.*stall|scheduling while atomic"` 长期观察。
5. **厂商同名 netfilter/ipset 模块冲突**（Q6 残余风险）：需要 D 的模块符号表工具，
   或设备在线取 `/system_dlkm/lib/modules/*/modules.dep` 与 `vendor_dlkm` 模块名列表比对。
6. **`fq` 默认 qdisc + BBR 默认拥塞控制的实际体验**（省电/发热/吞吐）：需 B 方向 + 实测。
7. **AF_PACKET 复现**：需要带 `SO_TIMESTAMPING + SO_RXQ_OVFL` 的 AF_PACKET 测试程序；
   本树 `/proc/net/packet` 有 8 个 AF_PACKET socket（机主 opt41 记录），具备前置条件，
   但触发需构造丢包计数为奇数的场景。
8. **USB gadget 修改的回归面**：需要 PC 端（Windows/Linux）实测 ADB/MTP/RNDIS/PD 全部枚举流程，
   重点观察是否有主机发过 `wLength > 4096` 的 OUT 控制请求（`dmesg | grep -i "composite"`）。

---

## 5) 已复核且未发现问题（避免重复劳动）

1. **`security/keys/request_key_auth.c`**：与 `remotes/ack/a14-lts` 逐字节相同（`diff -q` = SAME）。
2. **`security/selinux/ss/conditional.c`**：`kmalloc_array`→`kcalloc`，方向是**增加零初始化**（更安全），
   来源 `bbe1b4de1eba`（stable 1.151..188 批次）。
3. **`security/inode.c`**：删 `dget()/dput()` 是 opt11 的 stable backport（见 `4faf90660e27` 提交信息），
   非自研，不重复审。
4. **`net/netfilter/ipset/ip_set_hash_gen.h` 的 `k == n->pos`**：与上游 `ad92ee87462f` 逐字一致，
   语义已按 `for (i = 0, k = 0; …)` + 续算 `k` 推导确认为"整桶皆空"，**无问题**。
5. **`net/netfilter/nf_conntrack_expect.c` `expect->helper` 方案**：字段在
   `include/net/netfilter/nf_conntrack_expect.h:34` 存在，对照点 `nf_conntrack_netlink.c:3050` 存在，**无问题**。
6. **AF_PACKET opt41**：与上游 `ad9a0374ee6d`（upstream `1ee90b77b727`）实现一致；
   `sock_rmem_free` 全树只在 `skbuff.c:4834` 被安装为析构、在 `socket.c:814` 被比较 ⇒ 判据唯一，**无问题**。
7. **USB gadget opt42 item1**：与 `remotes/ack/a14-lts` 同函数逐行一致（ACK 已是修好形态），**无问题**。
8. **BBG 的 cred blob 机制**：`lsm_set_blob_size()` 会把 LSM 声明的 `lbs_cred` 改写成偏移，
   `bbg_cred()` 用 `cred->security + bbg_blob_sizes.lbs_cred` 是上游标准写法，**不是偏移量 bug**；
   且 `CONFIG_LSM` 中 selinux 在 baseband_guard 之前 ⇒ selinux 仍占偏移 0。
9. **`sock_rmem_free` 去 static**：**未**加 EXPORT_SYMBOL ⇒ 不新增/不改变模块 CRC 依赖，**无问题**。
10. **`other_patch/69_hide_stuff.patch` 与 `apk_sign.patch`**：均未应用，且本树无 KernelSU/SUSFS
    代码（`grep -rln "susfs"` 全树无命中）⇒ 与这两个补丁相关的"隐藏/签名白名单"风险**不存在**。
11. **`config.patch` 的 config 谎报 hack**：已确认不在 `kernel/Makefile`（`d56788d59a1f` 已拆），
    `/proc/config.gz` 不再被篡改；残留的 `config.patch` 只是死文件（见 C-07）。
12. **范围内文件来源统计**（命令与输出已核对）：`git diff --name-only 7a244ff18620..HEAD -- net | wc -l`
    = **178**，而 `git diff --name-only 5a22d459255f~1..HEAD -- net | wc -l` = **6**
    （即 opt38 之后只有 ipset×2、nf_conntrack×2、socket.c、skbuff.c(+sock.h) 这些自研改动），
    其余 172 个 `net/` 文件全部来自 ACK/stable 批次；
    对 `net drivers/usb drivers/i2c drivers/spi drivers/tty` 的全部新增行做了关键词扫描
    （`permissive|no_check|allow_all|#if 0|backdoor|bypass|skip.*check|disable.*check`）**无命中**。
13. **opt45 的两个 sched_ext 提交**（`83f9166efbd4`/`dfea5e50fd23`）属 B 方向，本方向不重复。
14. **`drivers/usb/gadget/function/{f_fs.c,u_ether.c,f_hid.c}`、`drivers/usb/typec/*`、
    `drivers/usb/core/{hcd.c,quirks.c}`、`drivers/usb/host/xhci*`、`drivers/tty/serial/*` 的变更**：
    由 ACK round4 批次提交（`c2a84f3a54c0`、`b45c37a0c6b4`）带入，非机主自研；
    本方向只核对了 gadget composite（opt42）与 AF_PACKET/i2c 几条自研线，其余按"上游 backport
    默认可信"处理（若 D 的闸门发现其中 CRCs 漂移再单独回看）。

---

## 6) 严重度定义（沿用任务书）

- **P0** = 可变砖 / 掉基带 / 数据永久损坏 / 无法开机
- **P1** = 严重功能失效或频繁重启挂死
- **P2** = 性能或功耗显著劣化
- **P3** = 隐患或加固弱化

**本方向最终评级：无 P0、无 P1、无 P2；P3 共 7 条（C-01…C-07），均为隐患/加固弱化/交付卫生。**
