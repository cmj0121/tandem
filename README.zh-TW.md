# Tandem

> 與你的 WoW 玩家協作

[English](README.md) | 繁體中文

Tandem 是一個 World of Warcraft addon。它收集透過掃描物品 ID 建立的可裝備物品快取、每件拾取物品的來源紀錄，以及用來
計算掉落率的擊殺數與拾取屍體數。它把這些資料與其他玩家貢獻的資料合併，建議你的角色能使用的最佳已知裝備，以及它們從
哪裡掉落。它絕不會替玩家執行任何動作，戰鬥中不會記錄任何資料，建議類指令在戰鬥中也不會回應。

## 安裝

在儲存庫根目錄執行：

```sh
make install
```

這會把儲存庫的 `Tandem/` 資料夾連結到用戶端，成為
`<World of Warcraft>/_classic_beta_/Interface/AddOns/Tandem`，因此修改 Lua 檔案後，在遊戲中執行 `/reload` 即可生效。
連結已存在時再次執行不會有任何動作。

移除方式：

```sh
make uninstall
```

### 尋找用戶端

`make install`、`make uninstall` 與 `make import` 會透過 `scripts/wow-dir.sh` 找出 `World of Warcraft` 資料夾。只有
包含 `<FLAVOR>/Interface/AddOns` 的資料夾才符合條件。搜尋順序如下：

1. `WOW_DIR`（若有設定）。若它不符合條件，安裝會直接失敗，不會繼續搜尋。
2. `/Applications/World of Warcraft`、`~/Applications/World of Warcraft` 和 `/Users/Shared/World of Warcraft`。
3. 透過 Spotlight（`mdfind`）搜尋任何名為 `World of Warcraft` 的資料夾。

若沒有任何資料夾符合條件，腳本會以錯誤結束，並列出所有搜尋過的位置。

### 覆寫設定

| 變數      | 預設值                 | 說明                                                                               |
| --------- | ---------------------- | ---------------------------------------------------------------------------------- |
| `WOW_DIR` | 自動偵測               | `World of Warcraft` 資料夾，也就是包含 `_classic_beta_` 的那層，而非 flavor 資料夾 |
| `FLAVOR`  | `_classic_beta_`       | `WOW_DIR` 內的用戶端 flavor 資料夾                                                 |
| `MODE`    | `link`                 | 設為 `copy` 時改為複製 addon，而非建立連結                                         |
| `DATA`    | `data`                 | `make import` 寫入貢獻檔的資料夾                                                   |
| `OUT`     | `Tandem/Data/Loot.lua` | `make import` 為 addon 寫入的合併檔                                                |

`WOW_DIR` 與 `FLAVOR` 適用於 `make install`、`make uninstall` 與 `make import`；`MODE` 只適用於前兩者。

由於資料夾名稱含有空格，`WOW_DIR` 須加上引號：

```sh
make install WOW_DIR="/Volumes/Games/World of Warcraft"
```

若用戶端無法讀取連結的資料夾，請改為安裝複本：

```sh
make uninstall
make install MODE=copy
```

複本不會跟著你的修改更新；每次修改後都要再執行一次 `make install MODE=copy`。要移除複本，請執行
`make uninstall MODE=copy`。在既有複本移除之前，`make install` 會拒絕以連結取代它。

## 指令

以每秒 10 個的速率掃描接下來的 100 個物品 ID，再查看收集到的資料：

```text
/tandem scan 10/s
/tandem count
```

| 指令                                  | 作用                                                              |
| ------------------------------------- | ----------------------------------------------------------------- |
| `/tandem`                             | 印出指令列表；任何未知的子指令也一樣                              |
| `/tandem count`                       | 印出目前收集到的資料                                              |
| `/tandem scan [<n>/s\|<n>/m] [<cap>]` | 從掃描位置往上掃描 `<cap>` 個物品 ID，速率為每秒或每分鐘 `<n>` 個 |
| `/tandem scan from <id>`              | 把掃描位置設為 `<id>`；不會開始掃描                               |
| `/tandem scan stop`                   | 停止進行中的掃描並印出摘要                                        |
| `/tandem gear [<slot>] [all]`         | 列出你能使用的最佳已知裝備，可列出所有部位或單一部位              |
| `/tandem rank <item link\|id>`        | 列出物品在其部位中的排名，以及它從哪裡掉落                        |
| `/tandem export`                      | 顯示 `make import` 會從這個帳號收集哪些資料                       |

戰鬥中執行 `gear`、`rank` 與 `export` 時，只會印出 `Tandem: not available in combat`，不做任何事。

### `/tandem scan`

速率預設為 `10/s`，必須介於 `1/m` 與 `50/s` 之間。上限預設為 `100` 個 ID，最多 `100000`。兩個參數順序不拘，因此
`/tandem scan 500 5/s` 與 `/tandem scan 5/s 500` 相同。參數無效或重複時會印出指令列表，不會開始掃描。

掃描會從上次停下的位置繼續：每查詢一個 ID，掃描位置就往上加一，沒有上限。已在快取中的 ID 會略過。速率是上限：
有 10 個查詢還在等伺服器回覆時，掃描會等待；超過 5 秒沒有回覆的查詢算作逾時。戰鬥中掃描會暫停，戰鬥結束後自動繼續。

```text
Tandem: scanning 100 IDs from ID 1
Tandem: scan stopped, IDs 1-100 in 10.6s, 100 processed, 0 skipped
  41 hits (12 equippable), 59 misses, 12 deferred, 0 timeouts
```

數字僅為範例；`zhTW` 用戶端會印出中文。達到上限且所有回覆都已收到時，或執行 `/tandem scan stop` 時，會印出摘要。
其他訊息：

- `Tandem: scan paused in combat`：每次戰鬥印出一次。
- `Tandem: scan already running`：掃描進行中又執行 `scan` 時。
- `Tandem: no scan running`：沒有掃描可停止時執行 `scan stop`。
- `Tandem: next scan starts at ID <id>`：執行 `scan from <id>` 之後；掃描進行中則印出
  `Tandem: stop the scan before moving the cursor`。

### `/tandem count`

```text
Tandem: 12 known items, 29 non-equippable
Scan cursor: 101, found IDs: 25-98
Loot entries: 3, npc names: 1
Kills: 4, looted corpses: 3
Drop rates use kills where counted, else looted corpses
Unsaved records: 16 (saved on /reload or logout)
Last run: IDs 1-100 at 10/s in 10.6s, 100 processed, 0 skipped
  41 hits (12 equippable), 59 misses, 12 deferred, 0 timeouts
```

第一次掃描前，`found IDs` 會顯示 `none`，最後一行會顯示 `Last run: never`。`Unsaved records` 計算的是 addon 載入後
新增的物品、掉落次數、NPC 名稱、擊殺數與拾取屍體數；用戶端未存檔就結束時，這些資料會遺失。

`Kills` 與 `looted corpses` 是這個帳號自己的計數（見[掉落率](#掉落率)）。接下來那一行說明擊殺數是否有在計算。用戶端
不允許時，這行會顯示 `Drop rates use looted corpses: kill counting is <status>`，`<status>` 為下列之一：

- `unavailable`：用戶端沒有戰鬥紀錄 API。
- `blocked`：用戶端拒絕註冊戰鬥紀錄事件。
- `secret`：戰鬥紀錄隱藏了誰擊殺了什麼；擊殺計數在這次登入期間自動關閉。

### `/tandem gear`

`/tandem gear` 會為每個部位印出你能使用、且有已知來源的最佳物品，最後印出與 `rank` 相同的說明：

```text
Best known gear for level 12 Warrior:
Head: none known
Chest: [Tough Leather Armor], ilvl 14 (upgrade)
...
Ranked by item level, then quality; stats are not considered
```

`/tandem gear <slot>` 會印出你在該部位穿戴的物品，接著列出最多 10 件物品及其需求等級：

```text
Best Chest for level 12 Warrior:
Equipped: [Recruit's Vest], ilvl 5
1. [Tough Leather Armor], ilvl 14, level 9 (upgrade)
2. [Rough Leather Vest], ilvl 10, level 5 (upgrade)
Ranked by item level, then quality; stats are not considered
```

物品與數字僅為範例；`zhTW` 用戶端會印出中文。物品以物品連結印出：點擊即可看到遊戲的提示框，包含圖示與屬性。用戶端
尚未載入的物品會印成 `[item #<id>]`，下次就會顯示名稱。

部位參數為 `head neck shoulder back chest wrist hands waist legs feet finger trinket mainhand offhand twohand
ranged`。不論用戶端語言，參數一律使用英文；印出的部位名稱則依用戶端語言顯示。未知的參數會印出
`Tandem: unknown slot <token>; use one of: ...`。

`gear` 預設只列出有已知來源的物品，也就是在你的資料或隨附資料中有掉落紀錄。加上 `all`，例如 `/tandem gear all` 或
`/tandem gear chest all`，就會一併列出其他快取中的物品，並標示 `(no known source)`。物品快取中也有遊戲裡取得不到的
物品。

### `/tandem rank`

`/tandem rank` 接受物品連結（在聊天輸入框中 Shift 點擊物品）或物品 ID。它會印出物品在其部位中、於你能使用且有已知來源的
物品之間的排名（物品本身不在其中時也會計入），你自己能否使用它，以及最多 5 個掉落來源：

```text
[Tough Leather Armor] (upgrade): rank 2 of 14 for Chest
  Kobold Miner, Elwynn Forest - drops: 3, 4.2% per looted corpse (upper bound)
  Defias Thug, Elwynn Forest - drops: 1
Ranked by item level, then quality; stats are not considered
```

- 你無法使用的物品仍會排名並計入總數，後面接著 `you cannot use it: level <n> required` 或
  `your class cannot use it`，且不會標示為升級。
- 單手武器以主手武器排名。
- 沒有已知來源的物品同樣會排名，後面接著 `no known source`。
- 不在快取中的物品會印出 `Tandem: item <id> is not known; scan or loot it first`。襯衣、外袍、背包與彈藥會印出
  `<item> does not go in a ranked slot`。
- 沒有記錄名稱的來源會印成 `npc #<id>` 或 `object #<id>`；用戶端沒有提供名稱的地圖會印成 `unknown map`。超過 5 個
  來源時，最後會印出 `and <n> more sources`。

### `/tandem export`

```text
Tandem export: 42 loot entries, 7 npc names, 120 items, 15 kills, 12 looted corpses
Unsaved records: 16 (saved on /reload or logout)
To contribute: type /reload, then run make import
```

計數包含這個帳號已存檔的資料與尚未存檔的資料。`export` 只會印出訊息：它不會重新載入介面，也不會寫入任何資料。
見[匯入掉落紀錄](#匯入掉落紀錄)。

## 裝備建議

### 裝備如何排名

物品依物品等級排序，其次是品質，最後是物品 ID。不考慮屬性，因此法系物品也可能在戰士的排名中名列前茅。每個會排名的
指令都會在最後一行說明這點。

只有你的職業與等級能使用的物品才會列出：

- 需求等級：你的等級須達到物品的需求等級。
- 護甲與武器類型依照 Classic 的職業表。布甲與雜項物品所有職業都能使用。獵人與薩滿 40 級起可穿鎖甲，戰士與聖騎士
  40 級起可穿鎧甲。薩滿的雙手斧與雙手錘需要天賦，因此絕不會建議。釣魚竿也絕不會建議。
- 雙持：戰士與獵人 20 級起，盜賊 10 級起。他們的單手武器會同時列在 `mainhand` 與 `offhand`，也只有他們能使用副手專用
  武器。盾牌與副手持握物品歸在 `offhand`。
- 戒指與飾品各算一個部位，與你穿戴的兩件中物品等級較低的那件比較。

物品後的標示：

- `(equipped)`：你正穿戴著它。
- `(upgrade)`：它的物品等級高於你在該部位穿戴的物品；空部位視為物品等級 0。用戶端不提供你穿戴的物品時不會標示，
  手持雙手武器時 `offhand` 也不會標示。
- `(no known source)`：沒有它的掉落紀錄（只出現在 `gear ... all`）。

### 掉落率

只有生物會印出掉落率，依每個 NPC 的下列兩種計數之一計算：

- 擊殺：你角色的最後一擊，在用戶端允許時從戰鬥紀錄讀取（`/tandem count` 會顯示是否允許）。寵物或隊友的擊殺不計入。
  戰鬥中的擊殺會在戰鬥結束後才儲存。
- 拾取屍體：你開啟過拾取視窗的每一具不同的屍體，只有金錢的屍體也算。沒有東西可拾取的屍體無法開啟，因此以拾取屍體
  計算的掉落率是上限。

該 NPC 有擊殺數時使用擊殺數，否則使用拾取屍體數，並標明使用哪一種。你自己的資料與隨附資料絕不相加：掉落率的掉落次數
與分母都取自其中一份，也就是在看過這件物品從該 NPC 掉落的資料中，分母較大的那一份。掉落次數超過分母時（例如拾取了
別人擊殺的怪物），不顯示掉落率，而不是顯示超過 100% 的數字。寶箱、採集點等物件沒有掉落率。

### 隨附資料

addon 隨附 `Tandem/Data/Loot.lua`，由 `make import` 從 `data/contributions/` 底下的所有貢獻合併而成：掉落紀錄、依語系
分組的 NPC 名稱、擊殺數、拾取屍體數與物品快取。指令會把它與你自己的 `TandemDB` 一起使用。每筆掉落紀錄的掉落次數取你的
數值與隨附數值中較大者，因為你的資料可能已經包含在隨附檔案中。擊殺數與拾取屍體數不這樣混用：掉落率的掉落次數與分母
取自同一份資料，詳見[掉落率](#掉落率)。物品紀錄則以你自己的快取為準。沒有這個
檔案時，指令只使用你自己的資料。

## 收集的資料

所有資料都存在一個帳號共用的表 `TandemDB`，存檔位置為
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`。

| Key       | 內容                                                                              |
| --------- | --------------------------------------------------------------------------------- |
| `items`   | 每個可裝備物品 ID：物品等級、需求等級、品質、裝備部位、class 與 subclass          |
| `scan`    | 掃描位置、不可裝備數量、找到的最小與最大 ID、每 1000 個 ID 區塊的命中數、上次掃描 |
| `loot`    | 依物品、來源與地圖分組：NPC 或物件 ID、地圖 ID、掉落次數，以及最多 5 個不同的座標 |
| `npcs`    | 以 NPC ID 對應的 NPC 名稱                                                         |
| `kills`   | 依 NPC ID：你的角色對該 NPC 的最後一擊次數                                        |
| `corpses` | 依 NPC ID：你拾取過的該 NPC 不同屍體數                                            |

- 存在但不可裝備的物品只計入 `scan.nonEquippable`，不會儲存。
- `scan.lastRun` 保存上次掃描的開始時間、ID 範圍、速率、經過秒數，以及摘要印出的各項計數。
- 每次在戰鬥外開啟拾取視窗時，每個來源都會記錄一次。來源可能是生物（`kind = "c"`，NPC ID）或遊戲物件
  （`kind = "o"`，物件 ID）；`kind = "?"` 表示用戶端沒有提供來源。用戶端沒有回報地圖與座標時，這兩項會留空。
- 同一次登入期間再次開啟的屍體或物件（例如沒拾取完的屍體）不會增加掉落紀錄，也不會增加拾取屍體數。addon 會記住最近
  200 個來源；`/reload` 後會忘記，所以重新載入後再開啟同一具屍體會重複計算。
- 只有在拾取的屍體是你的目標或位於滑鼠游標下時，才會記錄 NPC 名稱。

用戶端只在登出或 `/reload` 時寫入 `Tandem.lua`。當機或強制結束會遺失上次存檔後收集的所有資料；`/tandem count`
會顯示有多少筆紀錄尚未儲存。長時間掃描後請執行 `/reload`。

已知的計數限制：

- `nonEquippable` 會跨掃描累計，重新掃描同一範圍時會再計算一次，因為不可裝備的物品不會存入快取。
- `elapsed` 包含掃描因戰鬥暫停的時間。

## 在遊戲中驗證

1. 啟動用戶端。在角色選擇畫面開啟 **AddOns**，確認 **Tandem** 有列出且已啟用。
2. 進入遊戲世界。聊天視窗會顯示：

   ```text
   Tandem loaded
   ```

   在繁體中文（`zhTW`）用戶端上，這行會顯示為 `Tandem 已載入`，AddOns 清單中的說明也會是中文。其他語言的用戶端則一律
   顯示英文。

若沒有出現這行訊息，請確認 addon 已啟用，且沒有回報任何 Lua 錯誤。

### 檢查資料收集

WoW Forever 的 API 行為尚未驗證，請在遊戲中逐步確認：

1. 登入遊戲。聊天視窗顯示 `Tandem loaded`，且沒有 Lua 錯誤。
2. 在還沒有存檔資料時執行 `/tandem count`。應顯示 `0 known items`、`Scan cursor: 1`、`found IDs: none`、`0` 筆
   掉落紀錄，以及 `Last run: never`。
3. 執行 `/tandem scan 10/s`，在戰鬥外等待約 10 到 20 秒，直到出現兩行摘要。
4. 再執行一次 `/tandem count`。掃描位置為 `101`，上次掃描的數字與摘要一致。
5. 輸入 `/reload`，接著開啟 `WTF/Account/<account>/SavedVariables/Tandem.lua`，確認 `TandemDB` 中有 `items` 與
   `scan.lastRun`。
6. 選取一隻怪物為目標，擊殺後在仍選取著它的情況下拾取。若當時仍在戰鬥中，請關閉拾取視窗，待戰鬥結束後再拾取一次。
   `/tandem count` 的掉落紀錄會增加；若是第一次遇到的怪物，NPC 名稱也會多一個。接著執行 `/reload`，確認檔案中的
   `loot` 與 `npcs`。
7. 執行 `/tandem scan from 200000`，再進行一次小規模掃描，例如 `/tandem scan 20`，確認 Forever 上是否存在這麼大的 ID。

請回報步驟 3 與 7 的摘要、`/tandem count` 的輸出、任何 Lua 錯誤，以及 `SavedVariables/Tandem.lua` 檔案。

### 檢查裝備建議

1. 執行 `/tandem count`。記下它印出哪一行 `Drop rates use`：`kills where counted` 表示戰鬥紀錄在 Forever 上可用；
   否則記下狀態（`unavailable`、`blocked` 或 `secret`）。
2. 在戰鬥外擊殺一隻會掉落多件物品的怪物，只拾取一部分，在屍體上留下一件物品。`/tandem count` 的拾取屍體數會加一；
   若擊殺計數有開啟，擊殺數也會加一。關閉拾取視窗後再開啟同一具屍體：兩個計數都不變，掉落紀錄也不變。
3. 執行 `/tandem gear`。每個部位顯示一件物品或 `none known`，最後一行是屬性說明。點擊一件物品：會開啟遊戲的提示框，
   顯示圖示與屬性。
4. 執行 `/tandem gear chest`，或其他你有穿戴物品的部位。`Equipped:` 這行顯示你的物品，物品等級較高的物品標示為
   `(upgrade)`。執行 `/tandem gear chest all`，找找看 `(no known source)`。
5. 把一件你拾取過的物品 Shift 點擊到 `/tandem rank` 之後。它會印出排名、來源與掉落次數；若來源是生物，還有每次擊殺
   或每具拾取屍體的掉落率。也試試在 `/tandem rank` 後接數字。
6. 執行 `/tandem gear finger` 與 `/tandem gear offhand`。確認 `(upgrade)` 是與你較弱的戒指比較，且手持雙手武器時
   沒有任何副手物品被標示。
7. 開始戰鬥，在戰鬥中執行 `/tandem gear`、`/tandem rank 25` 與 `/tandem export`。每個都只印出
   `Tandem: not available in combat`。
8. 在戰鬥外執行 `/tandem export`。它會印出計數與 `To contribute: type /reload, then run make import`，且介面不會
   重新載入。

請回報步驟 1 的 `/tandem count` 輸出、步驟 2 的計數是否如上所述變化，以及任何列給你的職業卻無法裝備的物品。

## Interface number

`Tandem/Tandem.toc` 宣告了 `## Interface: 16001`，已在用戶端 `1.60.1` 的遊戲中確認。用戶端更新後若這個數字改變，
AddOns 清單會將 Tandem 標示為過期，除非勾選 **Load out of date AddOns**，否則不會載入它。

要查詢用戶端目前的數字，請在聊天視窗輸入：

```text
/dump (select(4, GetBuildInfo()))
```

把印出的數字填入 `Tandem/Tandem.toc` 的 `## Interface:` 這一行。若使用的是複本，請再執行一次
`make install MODE=copy`。接著重新啟動用戶端：`.toc` 檔案的變更不一定會被 `/reload` 讀取。

## 圖示

AddOns 清單顯示的是 `Tandem/Media/icon.tga`（64×64、32-bit 含 alpha），由 `Tandem/Tandem.toc` 的 `## IconTexture:`
指定。原始圖檔與設計紀錄放在 `assets/`。修改圖示後要重新啟動用戶端。

## 開發

```sh
make test
```

這會以 `luac -p` 檢查 `Tandem/` 與 `scripts/` 底下所有 Lua 檔案的語法，執行 `scripts/addon_test.lua`，並執行
`scripts/wow-dir_test.sh` 與 `scripts/import_test.sh`。本機的 `luac` 版本比遊戲使用的 Lua 5.1 新，因此只能抓出語法錯誤。
`scripts/addon_test.lua` 會模擬 WoW API 函式，依 `Tandem/Tandem.toc` 列出的順序載入檔案，並檢查 `enUS`、`zhTW`
與一個不支援的語系下的載入訊息。它也測試 `TandemDB` 的驗證與遷移、`/tandem` 的解析與輸出、以手動計時器與模擬的物品
API 進行的掃描、以模擬的拾取、戰鬥紀錄、地圖與單位 API 進行的掉落、擊殺與屍體紀錄，以及以模擬的職業、等級與已穿戴
物品進行的裝備建議。這些測試只能證明邏輯正確；用戶端實際的 API 要在遊戲中檢查。`scripts/import_test.sh` 以拋棄式的
SavedVariables 檔案與資料夾執行 `make import` 和 `scripts/import.lua`，涵蓋兩位貢獻者、重複匯入、重建、被拒絕的
檔案與沙箱。

### 匯入掉落紀錄

掉落紀錄採群眾收集：每位玩家的 `Tandem.lua` 匯入儲存庫的 `data/` 資料夾，再合併成 `Tandem/Data/Loot.lua`，兩者都要
commit。用戶端只在登出或 `/reload` 時寫入這個檔案，所以請先在遊戲中登出或執行 `/reload`。可以先執行 `/tandem export`
查看會收集哪些資料。接著在儲存庫根目錄執行：

```sh
make import
```

```text
wrote data/contributions/3f2a9c81d0b4.lua (enUS: 42 loot entries, 7 npc names, 120 items, 15 kills, 12 looted corpses)
wrote Tandem/Data/Loot.lua (1 contributors, 120 items, 42 loot rows)
```

ID 與數字僅為範例。`make import` 會讀取偵測到的用戶端中每一個
`<World of Warcraft>/<FLAVOR>/WTF/Account/*/SavedVariables/Tandem.lua`，並寫入：

| 檔案                          | 內容                                                                              |
| ----------------------------- | --------------------------------------------------------------------------------- |
| `data/contributions/<id>.lua` | 單一帳號的 `loot`、`npcs`、`items`、`kills`、`corpses` 及其語系，每次匯入都會覆寫 |
| `Tandem/Data/Loot.lua`        | 由所有貢獻合併，由 addon 載入                                                     |

合併檔會加總掉落次數、擊殺數與拾取屍體數，每筆掉落紀錄保留最多 5 個座標，NPC 名稱依語系分組，物品快取則取聯集；兩份
貢獻對同一件物品的紀錄不同時，以檔名排序在前的那份為準。它也以 `contributors` 記錄合併了多少份貢獻。舊版的
`data/loot.lua` 不再寫入。在匯入擊殺、屍體與物品之前寫成的貢獻檔仍可讀取。

- `<id>` 是帳號資料夾名稱 SHA-256 的前 12 個十六進位字元。資料夾名稱，也就是帳號號碼，絕不會被寫入或印出；同一個
  帳號永遠得到相同的 ID。
- 語系取自 `WTF/Config.wtf` 的 `SET textLocale` 這一行，沒有時為 `enUS`。NPC 名稱以用戶端語言儲存，因此
  `Tandem/Data/Loot.lua` 把它們放在 `names[<locale>]` 底下。
- `scan` 只留在本機。`items` 會匯入，因為只在自己掃描的幾百件物品之間排名意義不大。
- 重複執行是安全的：每個帳號的貢獻都是完整的快照，會取代上一份，因此掉落次數不會重複加總，相同的輸入也會產生逐位元組
  相同的檔案。
- 每個 SavedVariables 檔案都在空的環境中執行，沒有任何函式可呼叫，執行時間也有上限；它的 `TandemDB` 會以 addon
  載入時相同的方式檢查。無法解析、發生錯誤、執行過久、為預先編譯的檔案、沒有 `TandemDB`，或由較新版本 addon 寫入的
  檔案會被略過，並印出 `import: <file>: no TandemDB table, skipped` 之類的訊息。無效的項目會被捨棄，並印出
  `import: <file>: <n> invalid entries ignored`。
- 略過一個檔案不會影響其他檔案。在交給它的檔案都沒有匯入時，或 `data/contributions/` 中沒有任何有效的貢獻可合併時，
  `scripts/import.lua` 會以狀態碼 1 結束，`make import` 也會失敗。找不到任何 `Tandem.lua` 時，`make import` 會在執行
  腳本之前就失敗。

`WOW_DIR`、`FLAVOR`、`DATA` 與 `OUT` 的設定方式與 `make install` 相同，例如
`make import DATA=/tmp/tandem-data OUT=/tmp/tandem-data/Loot.lua`。之後以 `git diff` 檢查 `data/` 與 `Tandem/Data/`
底下的變更，再照常 commit。使用連結安裝時，在遊戲中執行 `/reload` 即可讀取新的 `Tandem/Data/Loot.lua`；使用複本時，
請先執行 `make install MODE=copy`。

`Tandem/Data/Loot.lua` 是產生出來的檔案，合併衝突絕不要手動解決。先解決 `data/contributions/` 的衝突，再從它重建
合併檔，不讀取任何 SavedVariables：

```sh
lua scripts/import.lua data Tandem/Data/Loot.lua
```

成功時會印出 `wrote Tandem/Data/Loot.lua` 這一行；在此之前，每個被略過或有項目被捨棄的貢獻檔都會在 stderr 印出
警告。沒有任何貢獻可合併時，會印出
`import: data/contributions: no contributions, Tandem/Data/Loot.lua not written` 並以狀態碼 1 結束。

### 翻譯

字串都透過 `ns.L` 取得，以英文原文作為 key。`Tandem/Locales/enUS.lua` 建立這個表：沒有翻譯的 key 會直接傳回自己，
因此缺少的翻譯會顯示英文。其他語系檔在 `GetLocale()` 不符時會直接返回，符合時才填入翻譯，例如
`Tandem/Locales/zhTW.lua`。新增語系檔時，要在 `Tandem/Tandem.toc` 中把它列在 `enUS.lua` 之後、`Tandem.lua` 之前。

每次 commit 時，pre-commit 也會執行 `luacheck`，設定在 `.luacheckrc`，以 Lua 5.1 為準。它需要先安裝 `luarocks`
（`brew install luarocks`），`luacheck` 本身則由 pre-commit 自動安裝。也可以手動執行：

```sh
pre-commit run luacheck --all-files
```

addon 開始呼叫新的 WoW API 函式時，要把函式名稱加進 `.luacheckrc` 的 `read_globals`。
