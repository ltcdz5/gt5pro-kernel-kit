# P31：f2fs 解压路径改缓存 + bootconfig 三修复 + qcom_geni 串口（2026-10-03）

> 现役 **P31**。承接 P30。

---

## 〇、现役

| 项 | 值 |
|---|---|
| 版本 | `6.1.141-android14-11-o-ltcdz5-opt15` / **`#58-ack303-p31`** |
| 镜像 | `boot-opt15-p31-repacked.img` md5 **`4ba157e8f58c85cda7fc4f252ec6e989`** |
| 裸内核 | `perf31/Image.p31` md5 `2e928c8d56a2f770cc0bc248c5bbeb78`（38357504 B） |
| 源码 | commit `b96307adfd`，tag `opt15-p31` |
| 规模 | **4 文件 / +13 −6** |
| 刷后 | `lsmod` 621、`wlan0` UP、SSG `[ssg]`、蓝牙 `state ON`/`crashed 0`、真 oops **0**、`pstore` **0**、ping 正常 |
| 回退首选 | **P30** `23114044fb9d31041e7fe3801d198d82` |

---

## 一、内容

### A. f2fs：让解压路径彻底不再为 layout 碰 `dic->inode`
P30 已在 `f2fs_free_dic()`（晚释放/workqueue）改用缓存字段。P31 把剩下两处也换掉：
```
compress.c:340   lz4_decompress_pages()      f2fs_compress_layout(dic->inode) → dic->dic_layout
compress.c:1376  f2fs_decompress_cluster()   同上
```
多处可在**软中断**里执行（`in_task()==false` 时整条解压链下沉，fixed-input 簇可达这两处）。
inode 此时仍被**上锁的 pagecache 页 + VFS 读路径**钉住 ⇒ **不构成 UAF**，
但既然缓存已就绪，换掉可让解压路径完全不碰 `dic->inode`。

### B. `dic_layout` 显式化
原先靠 `f2fs_kmem_cache_alloc(..., GFP_F2FS_ZERO, ...)` 零填充拿到 0（= `COMPRESS_FIXED_INPUT`），
是**隐含依赖**。已在字段处补注释说明它由 `f2fs_alloc_dic()` 显式赋值设置、**不依赖零填充**。未改逻辑。

### C. `lib/bootconfig.c` 三个上游修复
```
7c25edef09bb   fix off-by-one in xbc_verify_tree() unclosed node
8e0b204c47e1   check xbc_init_node() return in override path
e01dc9b8e267   fix snprintf truncation check in xbc_node_compose
```
**价值**：bootconfig 是 Android 启动配置解析（`/proc/bootconfig`、boot 参数），
解析 bug 可能影响启动参数读取。

### D. `drivers/tty/serial/qcom_geni_serial.c`
```
6bfa51973214   ANDROID: serial: qcom-geni: Add support for ...
```
**本机串口就是 qcom_geni**（设备 `lsmod` 可见 `msm_geni_serial`）。

### 未纳入
```
047b9b395380   xfrm: esp: ipv4: fix up flags setting  →  skip
```
**原因（已更正）**：`git apply --check` 的**真正失败**是
`error: patch failed: net/ipv4/ip_output.c:1463` + `patch does not apply`
⇒ **上下文冲突**（上游那次 `tx_flags`→`flags` 重命名本树没有）。

⚠️ **最初误判为"100755 权限导致"是错的** —— 见下面第二条坑。价值也低（1 行 flags 修正）。

---

## 二、⚠️ 本轮新踩的坑（必须记住）

### 坑：`has type 100755, expected 100644` **只是 warning，不是根因**（本条先写错过，已更正）

我最初看到 `git apply --check` 的**第一行**：
```
warning: net/ipv4/ip_output.c has type 100755, expected 100644
```
就断定"mode 不匹配导致补丁打不上"。**这是错的。**

**受控实验（本机 git 2.43.0）**：
| 场景 | 结果 |
|---|---|
| mode 不匹配 + **内容匹配** | 只打印 warning，`--check` 与真实 `apply` **都 exit 0**，内容正常写入 |
| mode 不匹配 + **内容不匹配** | `error: patch failed: <file>:<line>` ⇒ **真正的失败在这** |
| **只 `chmod 644`**（工作区644/索引100755） | `git apply --index`/`--3way` 报 `does not match index`，**exit 0 → exit 1** ⇒ **制造的问题更严重** |

⇒ **判"补丁打不上"要读到最后一条 `error:`，别抓第一行 warning。**（与"报错 ≠ 功能坏"同族）

**本机清点（2026-10-03）**：**281 个 `.c/.h` 是 100755**（来自提交里的 mode），
其中 **34 个**被已抓补丁碰过；**108/1935 个补丁**会打印这条 warning。碰得最多的：
`drivers/android/vendor_hooks.c`(46)、`include/trace/hooks/mm.h`(30)、`mm/page_alloc.c`(11)。

**想消除 warning 的安全办法**：
- **`git config core.filemode false`**（零文件改动，推荐）
- 或 `chmod 644` + `git update-index --chmod=-x` + **提交一次纯 mode 变更**
- ⛔ **禁止只 `chmod`**（会打断 `--index`/`--3way`）

### 坑：`340` 行与 `2316` 行的 `if` 文本**完全相同**

两处都是 `if (f2fs_compress_layout(dic->inode) == COMPRESS_FIXED_INPUT)`，
但**只有 340 该改**（解压路径），**2316 绝对不该改**（在 `f2fs_alloc_dic` 内部，
改了会在赋值前引用缓存 ⇒ 真 bug）。

⇒ **必须按行号索引替换 + 逐行断言，不能用字符串 replace。**
（这是 `fixer-f2fs` 自己发现的，处置正确。）

---

## 三、验证

```
make rc=0  错误=0
闸门1  新增=50 消失=1 | 命中厂商 新增=0 消失=0   PASS
闸门2  会拒绝装载的模块 = 1  (system_dlkm/bluetooth.ko, sk_filter_trim_cap)
横幅   #58-ack303-p31
```

## 四、P31 相对 P30 的增量为"更干净"，不是修新 bug
- A 是把同类隐患清零（那两处**本来不构成 UAF**）
- B 是消除隐含依赖
- C/D 是真实上游修复（bootconfig / qcom 串口）

---

## 五、版本号规范（2026-10-03 机主定，P35 起启用）

```
6.1.141-android14-11-o-ltcdz5-version1-opt35
                                  └─新增─┘
```
详见 `版本号规范-20261003.md`。**P31~P34 仍用旧格式**。
