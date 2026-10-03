# version1-opt36：UFS 三处修复（含 CVE-2026-43471）（2026-10-03）

> 现役 **version1-opt36**。承接 P35。**第一个使用新版本号规范的版本。**

---

## 〇、现役

| 项 | 值 |
|---|---|
| 版本串 | **`6.1.141-android14-11-o-ltcdz5-version1-opt36`** |
| banner（`uname -v`） | **`#61-ack304-version1-opt36 SMP PREEMPT`** |
| 镜像 | `boot-version1-opt36-repacked.img` md5 **`6610944ca925083835e2b5763c92f3f6`** |
| 裸内核 | `perf36/Image.p36` md5 `d7a5309d1234f416bfe2928c8946aa29`（38357504 B） |
| 源码 | commit `febd4235f`，tag `version1-opt36` |
| 规模 | **2 文件 / +19 −4** |
| 刷后 | `lsmod` **621**、`wlan0` UP、**UFS 报错 0**、`sda~sdf` 六 LUN 在、MCQ 启用、`/data` f2fs、SSG `[ssg]`、真 oops **0**、pstore **0**、蓝牙 `state ON`、ping 18.5ms |
| 回退首选 | **P35** `de044deceea1610a003a73f9a030ec3e` |

---

## 一、【1】CVE-2026-43471：`ufshcd_add_command_trace()` 空指针解引用

```c
drivers/ufs/core/ufshcd.c:498
	if (is_mcq_enabled(hba)) {
		struct ufs_hw_queue *hwq = ufshcd_mcq_req_to_hwq(hba, rq);

		hwq_id = hwq->id;          ← 未判空
	}
```
**helper 会返回 NULL**（`ufs-mcq.c:116`）：
```c
	return hctx ? &hba->uhq[hctx->queue_num] : NULL;
```
**最硬的内证**：同一 helper 在 `ufs-mcq.c:523` 是判空的 ——
```c
	hwq = ufshcd_mcq_req_to_hwq(hba, scsi_cmd_to_rq(cmd));
	if (!hwq)
		return 0;
```
⇒ **只有这一处漏了。**

**触发链**（如实记录，非无条件）：
1. MCQ 必开（本机 `ufs_qcom` + MCQ 已启用，实测 dmesg 有 mcq 记录）
2. `block/blk-mq.c` 的 `__blk_mq_free_request()` 会写 `rq->mq_hctx = NULL;`
3. 本树 `ufshcd_release_scsi_cmd()` 已不再清 `lrbp->cmd`（post-`549e91a9bbaa`），
   于是 tag 上残留的 `lrbp->cmd` 指向已完成、请求已释放的 `scsi_cmnd`
   ⇒ `mq_hctx == NULL` ⇒ `hwq == NULL` ⇒ 解引用
4. **前置**：需打开 `ufshcd_command` tracepoint
   （root 写 `/sys/kernel/tracing/events/ufs/ufshcd_command/enable`，或 perfetto/atrace 采集）
   ⇒ **不采集就不触发**，但对采集场景是真 NULL 解引用

**修法**：加 `if (hwq)` 判空（官方补丁即 "adds a NULL check"）。

---

## 二、【2】h8 exit 失败走 link recovery 而非 error handler

**上游** `35dabf4503b9` / **ACK** `565241067e73`（本树原来没有）。

**问题**：runtime resume 时 h8 exit 失败 ⇒ runtime 线程立刻 suspend，而
`ufshcd_uic_pwr_ctrl()` 无条件 `ufshcd_set_link_broken()` + `ufshcd_schedule_eh_work()`
⇒ 与 error handler **互等卡死**，且**无法恢复**。

**修法**（官方原文）：
```c
-	if (ret) {
+	if (ret && !hba->pm_op_in_progress) {
		ufshcd_set_link_broken(hba);
		ufshcd_schedule_eh_work(hba);
	}
...
+	if (ret && hba->pm_op_in_progress)
+		ret = ufshcd_link_recovery(hba);
```

---

## 三、【3】把 link recovery 搬到 wl_resume（【2】的后续重构）

**上游** `4a07d6ce4683`。**单独打不上**（依赖【2】），**必须成对应用**。
⇒ 两个都进，达到**最终上游形态**（只在 `wl_resume` 做 link recovery）。
⚠️ 这是本版最容易犯错的地方：只打一个会得到"半应用"的中间态。

---

## 四、验证

```
make rc=0  错误=0
闸门1（已换真基准：真 ELF 解析 4754 条）
     新增=50 消失=1 | 命中厂商 新增=0 消失=0   PASS
闸门2 会拒绝装载的模块 = 1  (system_dlkm/bluetooth.ko, sk_filter_trim_cap)
版本串 6.1.141-android14-11-o-ltcdz5-version1-opt36
横幅   #61-ack304-version1-opt36

刷后实测（本版改的是 UFS，重点看它）:
  UFS 报错 0；ufs_qcom 在；sda~sdf 六个 LUN 全在；MCQ 启用；/data f2fs 正常
  lsmod 621（版本串又变了，模块加载仍零损失）
  wlan0 UP / SSG [ssg] / pstore 0 / 真 oops 0 / 蓝牙 ON / ping 18.5ms
```

## 五、来源与复核
来自 `drivers/ufs/` 的限定范围勘探（只读子代理）。它给出线索，**我方逐条复核代码事实**：
helper 确实会返 NULL、同树 `ufs-mcq.c:523` 确实判空、两提交确实必须成对。
**方法论**：勘探员给线索，Lead 核事实 —— 今天已有四次"代理结论需复核"的先例。
