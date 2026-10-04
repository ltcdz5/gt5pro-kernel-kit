# ACK 第三轮（round 3）· 网络受阻 + CONFLICT 桶考古 · 2026-10-02

> 结论先行：**没能从 ACK 权威源拿到新提交（网络断了）**；转而处理 round 2 遗留的
> 104 条 CONFLICT，**捞出 6 条自洽安全修复并刷入**；
> 同时查明 **round 2 的一个方法论 bug**（按 sha 排序而非按日期）。

---

## 一、网络：今天到 ACK 的三条路全断

| 路径 | 结果 |
|---|---|
| PowerShell `Invoke-WebRequest` → `android.googlesource.com` `+log?format=JSON` | ⚠️ 时通时断（03:0x 通、15:0x 起 60~120s 超时） |
| WSL `git clone/ls-remote https://android.googlesource.com/...` | ❌ `gnutls_handshake() failed: TLS connection non-properly terminated` |
| WSL `git ls-remote https://gh-proxy.com/...aosp-mirror/kernel_common` | ❌ 同样 gnutls 失败 |
| harness `web_fetch` | ❌ `URL hostname resolves to a non-public IP address` |

**⇒ 这一轮无法收割新提交。**

### 已完成的准备（网络恢复即可直接跑）

- **权威分支确认**：`refs/heads/android14-6.1`（**不是** `-lts`）。
  证据：同一主题 "ipv6: fix a race in ip6_sock_set_v6only()" 在 `-lts` 上 sha 是 `e1828c7a8d81`、
  在 round2 收割线（`android14-6.1`）上是 `e23da16dec5a` —— **跨分支 sha 不可用作"是否已合并"的判据**，
  必须用「反向 apply」判定。
- **🔴 方法论 bug（本轮最重要的发现）**：round 2 的应用顺序是 **按 sha 排序**
  （`classify.tsv` 是排序产物），而**上游补丁链必须按提交日期打**。
  这解释了 CONFLICT 桶里大量"本不该冲突"的条目。
  **以后收割必须按 `committer date` 排序后再应用。**
- 候选清单已算好：`ack_round3_final.tsv` **257 条**（窗口 2026-06-01..09-30 非 merge，
  主题不在已合并集合，且按白名单过滤到本机关心的子系统：
  netfilter 37 / arm64 37 / f2fs 26 / net-sched 19 / crypto 17 / scsi 10 / xfrm 10 /
  eventpoll 9 / bpf 5 / tcp 4 / ipv6 4 …）。
  生成链路：`ack_lts_meta.csv`(29,971 条) → 窗口 1917 → 非 merge 1814 → 去已合并主题 1757
  → 白名单 257。

---

## 二、⚠️ `patch -F3`（fuzz）在本树上**不安全** —— 实证

`patch -p1 -F3` 会**报成功但把 hunk 塞进"文本相似、语义错误"的位置**：

```
include/ufs/ufshcd.h 打完 a89b76f4f76d 之后：
	UFSHCD_QUIRK_PERFORM_LINK_STARTUP_ONCE		= 1 << 19,
	 */                                    ← ★ 多出来的注释终结符（hunk 插进注释块中间）
	UFSHCD_QUIRK_SKIP_DEF_UNIPRO_TIMEOUT_SETTING = 1 << 13,
```
⇒ `include/ufs/ufshcd.h:602:3: error: expected identifier`

同类：`fs/ext4/xattr.c: unknown type name 'iloc'`、`fs/ext4/super.c: use of undeclared identifier 'i'`。

**⇒ 判据必须是「零容错 F0 + 补丁内容自检」**：
F0 应用后逐条检查补丁的每条 `+` 行是否真出现在目标文件里，不在就反向撤销。

---

## 三、CONFLICT 桶（104 条）的真实结构

```
patch -F3 可打 ......... 45 条（其中 30 条改的文件真参与本机编译、8 条碰编译头）
patch -F0 顺序可打 ..... 21 条
patch -F0/F1/F2 都打不上 74 条
```

### 为什么批量自动化不可行

21 条里很多是**补丁链的中间环**，前置在 round 2 那 **28 条 CRC 退料**里：

| 报错 | 缺的前置 |
|---|---|
| `fs/ext4/inode.c: call to undeclared function 'ITAIL'` | `5a1cf5746074 ext4: introduce ITAIL helper`（退料） |
| `fs/ext4/extents.c: use of undeclared identifier 'ppath'` ×13 | `b5a010bc7dba ext4: get rid of ppath in ext4_find_extent()`（退料） |
| `fs/ext4/mballoc.c: undeclared 'ext4_get_allocation_groups_count'` | 同族（退料） |
| `include/net/netfilter/nf_conntrack_expect.h: no member named 'net'` ×53 | `a5f8255d1563 …store netns and zone in expectation`（打不上） |
| `net/sched/sch_api.c: redefinition of 'qdisc_warn_nonwc'` | `3c2a89948076` 的 `pkt_sched.h` 半边 |

**实测自动收敛器**（按报错文件排除补丁、重打重建、循环 6 轮）：**不收敛** ——
排除表增长到 8 条但错误集恒为 87 个/11 文件。因为错误来自**被跳过的前置**，
不是来自被应用的补丁。

**⇒ 这 104 条本质是人工活**（要逐条找前置、按日期重排、人工解冲突），不是本轮能自动完成的。

---

## 四、✅ round 3 实际产出：6 条落地

在 104 条里筛出**自洽**（不碰 ext4 `ppath`/`ITAIL` 族、不碰 `nf_conntrack_expect.h`、
不碰 `sch_api`/`devmap`/`ufshcd`）的候选，用「F0 → F1 → F2 + 内容自检」多趟重试：

| 补丁 | 内容 | 应用方式 | 风险 |
|---|---|---|---|
| **`bdf2724eefd4`** | netfilter: ctnetlink **use-after-free** in `ctnetlink_dump_exp_ct()` | F0 | 纯 `.c` |
| **`5466e7d0cd9e`** | crypto: authencesn 出站位解密 `hiseq` 位置错误 | F0 | 纯 `.c` |
| `28c7cfaf0c0a` | netfilter: xt_IDLETIMER 拒绝 rev0 复用 ALARM 标签 | F2+自检 | 纯 `.c` |
| `97b89d7ccecc` | scsi: core `scsi_alloc_sdev()` 错误处理 | F0 | 纯 `.c` |
| `906c6cddca0c` | tcp: `inet_use_bhash2_on_bind()` | F0 | 纯 `.c` |
| `80c178906d06` | bpf: `bpf_prog_test_run_xdp` | F0 | 纯 `.c` |

- **全部纯 `.c` ⇒ 零 CRC 风险**（不改任何头文件）
- `make rc=0`，1.5 分钟
- **闸门1 导出集合 PASS**（新增=22 消失=0，命中厂商 0/0）
- **闸门2 厂商 CRC 真值**：仅 `bluetooth.ko`（`sk_filter_trim_cap`，**基线就不符**，与 opt14/15/P5 完全一致）
- 提交 `e55a82a0c`，tag `opt15-p11`
- 镜像 `images\boot-opt15-p11-repacked.img`，md5 `57df6d0b77d2b7f8111d15e4d2481ec3`
- 横幅 `#46-ack138-p11`

### 顺序敏感性（记录，供后续参考）

`f132820f92ba`（tcp `dsack_dups` data-race）与 `906c6cddca0c` 改同一批 tcp 文件：
- 先打 `906c…` ⇒ `f132…` 打不上
- 先打 `f132…` ⇒ 仍然打不上（实测两种顺序都失败）
⇒ 该条需要人工解冲突，本轮放弃。

---

## 五、下一步（网络恢复后）

1. 按 **`ack_round3_final.tsv`（257 条）** 抓补丁：`+/<sha>^!/?format=TEXT`
2. **按 `committer date` 排序**应用（不要按 sha）
3. 判据：`git apply --check`（= F0）→ 反向 apply 判"已有" → 内容自检 → 编译 → **双闸门**
4. 104 条 CONFLICT 桶：需要**人工**逐条找前置；优先做有明确安全价值的
   （`c32fb7acf55b` act_connmark、`f381a33f34dd` nf_conncount 泄漏、`ca8b4d1d6304` nft_connlimit
   计数、`93d1964773ff` bpf `update_effective_progs`、`6e37143560e3` ext4 挂载选项字符串拷贝…）

---

*记录：2026-10-02 16:3x*
