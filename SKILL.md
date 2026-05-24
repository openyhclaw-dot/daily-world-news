---
name: daily-world-news
description: >
  Daily news curation with two pillars: world affairs (9 regions, multi-country perspectives)
  and tech news (RSS + GitHub + Reddit + web search with quality scoring).
  Generates combined podcast audio and delivers to Telegram.
  Use when: running daily news cron, manually generating news, creating podcast, or sending news to Telegram.
  NOT for: general web research, non-news content, or historical analysis.
---

# Daily World News + Tech Digest

Two-pillar daily pipeline: **時事** (world) + **科技** (tech) → combined podcast.
All deterministic work is wrapped in `scripts/run.sh`. Do NOT read any `guidelines/*.md` or `config/*.md` — every rule you need is inlined below.

---

## PHASE 0 — Preflight (1 bash call)

```
bash scripts/run.sh preflight
```

- If exit code = **42** → already delivered today, STOP the entire run.
- On success, stdout prints `TODAY=YYYY-MM-DD` / `YESTERDAY=YYYY-MM-DD`. Use those.
- This call: idempotency check, loads secrets, installs deps, fetches `summaries/${TODAY}-market.json`.

## PHASE 1 — 科技新聞

1. `bash scripts/run.sh tech-gather` — produces `summaries/${TODAY}-raw-tech.json` (already scored, deduped, filtered to score≥5) and `summaries/${TODAY}-dedup-tech.txt` (compact past-3-days digest).
2. Read ONLY these two files. Do not read prior tech summaries directly.
3. Optional: web_search for gaps listed in `raw-tech.json.web_search_queries`. Skip if raw-tech is rich enough.
4. Apply New Development Test against the dedup digest (see Rules below).
5. Write `summaries/${TODAY}-tech.md` using **Tech format** below.
6. Fact-check: version numbers, benchmarks, 融資金額, release state (released/announced/coming-soon).
7. Send to Telegram, split at 3800 chars.

## PHASE 2 — 時事新聞

1. `bash scripts/run.sh world-prep` — produces `summaries/${TODAY}-dedup-world.txt`.
2. Read that digest only.
3. Gather: 15–25 web_search queries across 9 regions. Every story MUST have ≥1 real URL.
4. Apply dedup rules + counter-perspective + data-evidence mandates (see Rules).
5. Write `summaries/${TODAY}.md` using **World format** below.
6. Fact-check: 人名/職稱, 數字, 日期, 因果, 引述.
7. Send to Telegram, split at 3800 chars.

## PHASE 3 — Combined Podcast

1. Bump `episode-counter.txt` → EP number.
2. Write `summaries/${TODAY}-podcast.md` (6000–10000 字, min 4000 字 / 12000 bytes). Structure:
   開場 30s → 時事【新事區 + 延續區 + 深度區】→ 自然過場(口語，**不要 `[🎵 轉場]` 標記**) → 科技【新事區 + 延續區 + 深度區】→ 結尾 30s.
   時事新事區 5-7 min / 延續區 60-90s / 深度區 0 或 1-2 min（僅當有類別變化事件）.
   科技新事區 4-6 min / 延續區 45-60s / 深度區 0 或 1-2 min（同上條件）.
   總長維持 13-19 min. **Podcast 不含市場快報區段**（市場數據只留在 Telegram 時事/科技 digest），釋出的時間用來加深時事與科技的分析。三區制與類別變化事件清單見 Rules。Style in Rules.
3. `bash scripts/run.sh audio` — validates + generates `summaries/${TODAY}.mp3` (TTS retry 2x on 503).

## PHASE 4 — Validate (gate)

```
bash scripts/run.sh finalize
```

純跑 `validate.py`（人名一致性、來源連結、市場資料規則、與昨天 dedup）。fail → sys.exit(1)，後面 phase 全部不跑。**這個 phase 不做 git ops**——commit/push 移到 PHASE 5 結束後做，這樣才能把 publish 階段重生的 `feed.xml` 一起捕進當日 commit。

## PHASE 5 — Publish (auto by cron / manual on demand)

```
bash scripts/run.sh publish
```

執行內容：upload-r2 mp3 → generate-rss → upload feed.xml → 推 Apple Podcasts 連結到 Telegram → `git add -A` + `git commit -m "📰 每日新聞摘要 ${TODAY}"` + **`git push` 推回 GitHub**（必做，不可略過）。push 失敗必須檢查原因並重試，不能只靠 `|| echo "push skipped"` 默默放過。

---

## Rules (inlined — do not fetch)

### Tech scoring (already done by gather_tech.py)
Base 5; +3 priority source; +3 multi-source; +2 <24h; +3 Reddit>500 / +1 >200; +3 GitHub trending; −5 yesterday dup; −2 unknown source. Min publish = 5. `raw-tech.json` is already filtered.

### 三區制（新事 / 延續 / 深度）— Podcast 專用

dedup digest 不是「TODO 清單」，是「黑名單」。看到一則候選先做這個 router：

1. 該故事**不在過去 3 天 dedup digest** → 進【新事區】，正常深度 2-4 段.
2. 該故事**已在 dedup digest（任何一天）** → 進【延續區】，硬上限 1 句更新；無新 fact 可講 → 直接刪掉，不要寫「沒有新進展」這種廢話.
3. 例外：當天該故事發生「**類別變化事件**」（見下方清單）→ 進【深度區】，每集**最多 1 則**；其餘符合條件的故事仍降級到延續區.

**延續區寫法**：合併成 1 段，每則 1 句，中性連接詞串起來（「另外」「同時」「比較短的幾條」）。範例：「伊朗第 57 天，威特科夫跟 Araghchi 的會面延到禮拜天；歐盟 900 億貸款今天蓋章；杜特蒂的開審日確定 5 月 12；BOJ 利率決議倒數 2 天，市場押注降到 38%。」

**Telegram digest（非 podcast）夾帶的舊規則仍適用**：標題相似度 >85% → 合併. 跨區塊: 時事保留政治角度、科技保留技術角度.

### 類別變化事件清單（深度區唯一通行證）

只有以下事件**今天**發生才能讓延續故事進深度區。寫之前先在心裡對清單，不在的不准升級。不確定 → 走延續區，不要冒險升級。

- **司法**：判決宣判 / 起訴正式提交 / 引渡執行 / 死刑執行 / 重大法案通過
- **戰爭/衝突**：開戰 / 停火協議簽署 / 停火正式破裂 / 單一事件 ≥50 人傷亡 / 領袖被擊殺被捕 / 領土易手 / 核設施被攻擊
- **政治**：選舉結果公布 / 政變成功失敗 / 領袖辭職下台 / 內閣總辭 / 彈劾通過
- **經濟**：央行利率決議公布（與市場預期相反才算）/ 主要指標單日波動 ≥5% / 主權違約 / 重大企業破產 / 跨國併購正式完成
- **災害**：自然災害死亡 ≥100 / 核事故 / 流行病跨國爆發
- **外交**：斷交 / 復交 / 重大條約簽署 / 領袖首訪敵對國
- **科技**：旗艦級產品發表（GPT-5 / Codex 5 等級）/ 融資 ≥10 億美元公布 / IPO 上市或下市 / 重大資安事件（用戶數 ≥1000 萬）/ SpaceX-NASA 級別發射

### Counter-perspective (mandatory)
- 時事格式 A: 每則重大新聞必含至少一個反對觀點，格式 `🔻 [來源/立場]：[觀點]`.
- 科技: LLM/AI Agent 進展加一句風險/批評視角；加密貨幣同時提看多/看空 + 具體數字.

### Data evidence
涉及經濟/軍事/氣候/科技 → 必附具體數字 + 機構縮寫 (IMF/UN/WHO/WTO/WMO/OECD). 無官方數據寫「數據待核實」，禁杜撰.

### Market date correction (僅適用於加密貨幣 / 金價 / 原油)
僅 BTC、ETH、Gold、WTI/Brent 這幾個指標會被引用，從 `-market.json` 讀。

1. 只報 `is_fresh == true`（`age_hours ≤ 24`）；超過就省略或寫「數據待更新」。
2. `date == $TODAY` 才能用「今天」「目前」；否則明說「昨天（日期）」或「最新報價」。
3. 加密貨幣 `age_hours < 6` 可用「目前」「此刻」；6–24h 用「最新報價」；> 24h 省略。
4. 金價 / 原油沿用同規則；遇假日/週末若 stale，直接寫「上週五收盤（日期）」或省略。
5. 寫完逐項對照 `date` / `age_hours`，確認全部 ≤ 24 且敘述與日期一致。

### World format (summaries/${TODAY}.md)
```
# 🌍 每日世界新聞摘要 — YYYY年M月D日（週X）
> 📡 資料來源：[主要媒體]
> ⏰ 更新時間：UTC HH:MM

## 🔥 今日頭條（Top 3）
## 🇺🇸 美洲 / 🇪🇺 歐洲 / 🇯🇵🇰🇷🇨🇳 東亞 / 🇹🇼 台灣 / 🇮🇳 南亞&東南亞 / 🇸🇦 中東 / 🌍 非洲 / 🇦🇺 大洋洲 / 🌐 科技&財經
```
- 總計 15–20 則，區塊動態分配（不強制每區都有）.
- 3–5 則用**格式 A**（多元視角）, 其餘**格式 B**.
- 格式 A:
  ```
  • **[標題]**
    [摘要 1-2 句]
    🇺🇸 美國：[立場/措辭]
    🇨🇳 中國：[立場/措辭]
    💡 觀點差異：[一句話]
    📎 來源：
    https://...
    https://...
  ```
- 格式 B: `• **[標題]** — [2-3 句深入，含背景+影響]\n  📎 https://...`
- 按**國家**列觀點，不要東/西分類. 每則必含事件+背景+影響.

### Tech format (summaries/${TODAY}-tech.md)
```
# 🔬 每日科技新聞 — YYYY年M月D日（週X）
> 📡 資料來源：RSS {N} | GitHub {N} | Reddit {N} | Web Search {N}
> ⏰ JST HH:MM

## 🔥 科技頭條（Top 3）
## 🧠 LLM (max 6) / 🤖 AI Agent (max 5) / 💰 加密貨幣 (max 5) / 🔬 前沿科技 (max 6)
## 🚀 Space & Science (max 3) / 📱 Consumer Tech (max 3) / 🛡️ Cybersecurity (max 3) / 🧬 Biotech (max 2)
## 📦 GitHub Releases / 📝 Blog Picks (3)
## 📊 市場快照（加密貨幣 + 金價 + 原油）
```
- 市場快照只列 BTC、ETH、Gold、原油（從 `-market.json` 讀），其他指標（股指、FX）一律不寫.
- 單一 topic ≤ 40%，至少涵蓋 4 個 topic.
- 標準: `• 🔥{score} **[標題]** — [2-3 句] \n  📎 來源：[媒體](URL)`
- 多來源(score>10): `📎 來源：[A](URL) | [B](URL) | [C](URL)`
- GitHub: `• **owner/repo** \`vX.Y.Z\` — 重點\n  📎 <url>`
- Telegram: 不用 markdown 表格, 純 bullet + bold.

### Podcast style
轉角國際 / The Daily 風格的 podcast 主持人. 繁中口語. 用「你」稱呼聽眾. 有觀點有分析. 數字口語化（「跌了超過兩個百分點」而非「2.3%」）. **日期一律寫「M月D日」**（如「4月26日」「5月14到15日」「4月27到28日」），**禁止 `4/26` `5/14-15` 這種斜線格式**——TTS 會唸成「斜線」。 禁: emoji、markdown、`[🎵 轉場]`、「根據報導/據悉」、逐條念標題、重複昨天、**獨立的市場快報段**(禁止 podcast 出現「市場快報」「股市」「指數」等專門段落；股價/匯率/加密幣數字若要出現，只能順帶帶過，不另闢段落). **延續區寫法**：1 句講新 fact，**禁止重述背景**——不解釋 ICC 是什麼、Druzhba 是哪條管線、賴清德為什麼要去史瓦帝尼。假設聽眾聽過昨天那集（訂戶模型是「每天聽」，不是隨機路過）. **深度區**因為符合類別變化事件、值得重開，可以給最少必要背景（≤2 句），但不能完整重講前情提要. 結構: **開場 30s（只提最重要的 1-2 個重點，不要逐條預告）** → 時事 **7-11 min**【新事 5-7 min / 延續 60-90s / 深度 0 或 1-2 min】 → 自然過場 → 科技 **6-9 min**【新事 4-6 min / 延續 45-60s / 深度 0 或 1-2 min】 → 結尾 30s. 總長維持原本 13-19 分鐘區間。三區制 router 與類別變化事件清單見上方 Rules。

---

## Key invariants
- All dates = **JST (Asia/Tokyo)**
- 無 fabricated 新聞/URL — 每則必附 📎
- 時事/科技分開發 Telegram；podcast 不發音檔，publish 時 poll iTunes 後送 Apple Podcasts 連結
- 市場數據只保留 BTC / ETH / Gold / WTI / Brent；股指、FX 全面拿掉
- Podcast **不含市場快報段**；市場數據只出現在 Telegram 科技 digest 的「市場快照」，且必做日期校正
