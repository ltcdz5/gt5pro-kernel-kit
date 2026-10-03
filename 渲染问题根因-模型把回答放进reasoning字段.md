# 渲染问题根因：某些模型把回答塞进 `reasoning_content`，正文通道为空

> 症状：机主只能看到"思考"块，看不到正文（我写的正文全部出现在思考里）。

---

## 一、DSH 的判定机制（在 `app.asar` 里查到的代码）

```js
const OPENAI_COMPLETIONS_REASONING_FIELDS = ["reasoning", "reasoning_content", "reasoning_text"];
...
const delta = deltaFields[foundReasoningField];
if (typeof delta === "string" && delta.length > 0) {
    const block = ensureThinkingBlock(thinkingSignature);
    block.thinking += delta;                 // ← 落在这三个字段里的文本【一律渲染成思考】
    stream.push({ type: "thinking_delta", ... });
}
```
⇒ **按字段名判定**，不是按内容语义。
⇒ 若上游把回答放在 `reasoning_content` 而 `content` 为空 ⇒ 用户只能看到思考。

### 附：`transcriptView`（不是本问题根因，但顺手记下）
`~/.dsh/profiles/desktop/cordis.patch.yml` 的 `ui-chat.transcriptView` 四档：
| 模式 | `foldCompletedTurns` | `stepGrouping` | `liveProcessDetail` | `settledReasoningPreview` |
|---|---|---|---|---|
| `compact` | true | `collapsed` | false | false |
| `standard` | true | `collapsed` | true | true |
| `detailed` | true | `history` | true | true |
| `verbose` | false | `none` | false | true |

（2026-10-03 曾从 `detailed` 改到 `standard` 又改到 `verbose`，均**未解决**本问题 —— 因为根因是字段，不是显示模式。）

---

## 二、★ 实测：哪些模型"正文为空"

方法：直连各 provider，`stream: false` 发一个会触发思考的提示，读 `choices[0].message` 各字段长度。
脚本：`C:\Users\USERNAME\AppData\Local\Temp\field_probe.py`（不打印密钥）。

| provider / 模型 | `content` | `reasoning*` | 判定 |
|---|---|---|---|
| **workbuddy-intl / hy4-preview-f** | **0** | 1379 | ⛔ **正文为空** |
| **workbuddy-cn / hy3** | **0** | 703 | ⛔ **正文为空** |
| qoder / Qwen3.8-Flash | 23 | 591 | ✅ 正常 |
| qoder / Qwen3.8-Max | 32 | 504 | ✅ 正常 |
| qoder / GLM-5.3-Flash | 129 | 3929 | ✅ 正常 |
| openrouter / nvidia/nemotron-3-ultra-550b:free | 32 | 518 | ✅ 正常 |
| workbuddy-{cn,intl} / deepseek-v4.1-flash | — | — | （本轮 429，未测到） |
| zcode2api / GLM-5.3 | — | — | 连接被拒（网关没起） |

---

## 三、结论与操作

**根因 = 模型侧字段放置，不是 DSH 配置。**
`hy4-preview-f` 与 `hy3`（走 `127.0.0.1:8788` 的 workbuddy 网关）把整段回答放在 `reasoning_content`。

**⇒ 要正常显示正文，就别用这两个模型；改用 `qoder` 的（Qwen3.8-Max 优先，上下文更宽）或 `openrouter/nemotron-3-ultra`。**

⚠️ 换模型是机主在界面上操作，我（agent）无法自行切换会话模型。

---

## 四、排查顺序（下次遇到"只看到思考"）

```
1) 先看是不是字段问题：跑 field_probe.py，看 content 长度是否为 0
   → 是 ⇒ 换模型（本文件第二节的表）
2) 若 content 正常但仍显示异常 ⇒ 再看 ui-chat.transcriptView（改成 verbose 试试）
3) 仍不行 ⇒ 查 provider 的 compat.thinkingFormat（asar 里支持
   'openai' | 'openrouter' | 'deepseek' | 'qwen' | ...），配错也会让解析错位
```
