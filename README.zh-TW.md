# Tandem

> 與你的 WoW 玩家協作

[English](README.md) | 繁體中文

Tandem 是一個 World of Warcraft addon。目前它為後續階段收集資料：透過掃描物品 ID 建立的可裝備物品快取，以及每件拾取
物品的來源紀錄。它絕不會替玩家執行任何動作，戰鬥中也不會記錄任何資料。

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

`make install` 會透過 `scripts/wow-dir.sh` 找出 `World of Warcraft` 資料夾。只有包含
`<FLAVOR>/Interface/AddOns` 的資料夾才符合條件。搜尋順序如下：

1. `WOW_DIR`（若有設定）。若它不符合條件，安裝會直接失敗，不會繼續搜尋。
2. `/Applications/World of Warcraft`、`~/Applications/World of Warcraft` 和 `/Users/Shared/World of Warcraft`。
3. 透過 Spotlight（`mdfind`）搜尋任何名為 `World of Warcraft` 的資料夾。

若沒有任何資料夾符合條件，腳本會以錯誤結束，並列出所有搜尋過的位置。

### 覆寫設定

| 變數      | 預設值           | 說明                                                                               |
| --------- | ---------------- | ---------------------------------------------------------------------------------- |
| `WOW_DIR` | 自動偵測         | `World of Warcraft` 資料夾，也就是包含 `_classic_beta_` 的那層，而非 flavor 資料夾 |
| `FLAVOR`  | `_classic_beta_` | `WOW_DIR` 內的用戶端 flavor 資料夾                                                 |
| `MODE`    | `link`           | 設為 `copy` 時改為複製 addon，而非建立連結                                         |

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
Unsaved records: 16 (saved on /reload or logout)
Last run: IDs 1-100 at 10/s in 10.6s, 100 processed, 0 skipped
  41 hits (12 equippable), 59 misses, 12 deferred, 0 timeouts
```

第一次掃描前，`found IDs` 會顯示 `none`，最後一行會顯示 `Last run: never`。`Unsaved records` 計算的是 addon 載入後
新增的物品、掉落次數與 NPC 名稱；用戶端未存檔就結束時，這些資料會遺失。

## 收集的資料

所有資料都存在一個帳號共用的表 `TandemDB`，存檔位置為
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`。

| Key     | 內容                                                                              |
| ------- | --------------------------------------------------------------------------------- |
| `items` | 每個可裝備物品 ID：物品等級、需求等級、品質、裝備欄位、class 與 subclass          |
| `scan`  | 掃描位置、不可裝備數量、找到的最小與最大 ID、每 1000 個 ID 區塊的命中數、上次掃描 |
| `loot`  | 依物品、來源與地圖分組：NPC 或物件 ID、地圖 ID、掉落次數，以及最多 5 個不同的座標 |
| `npcs`  | 以 NPC ID 對應的 NPC 名稱                                                         |

- 存在但不可裝備的物品只計入 `scan.nonEquippable`，不會儲存。
- `scan.lastRun` 保存上次掃描的開始時間、ID 範圍、速率、經過秒數，以及摘要印出的各項計數。
- 每次在戰鬥外開啟拾取視窗時，每個來源都會記錄一次。來源可能是生物（`kind = "c"`，NPC ID）或遊戲物件
  （`kind = "o"`，物件 ID）；`kind = "?"` 表示用戶端沒有提供來源。用戶端沒有回報地圖與座標時，這兩項會留空。
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

這會以 `luac -p` 檢查 `Tandem/` 底下所有 Lua 檔案的語法，執行 `scripts/addon_test.lua`，並執行
`scripts/wow-dir.sh` 的測試。本機的 `luac` 版本比遊戲使用的 Lua 5.1 新，因此只能抓出語法錯誤。
`scripts/addon_test.lua` 會模擬 WoW API 函式，依 `Tandem/Tandem.toc` 列出的順序載入檔案，並檢查 `enUS`、`zhTW`
與一個不支援的語系下的載入訊息。它也測試 `TandemDB` 的驗證與遷移、`/tandem` 的解析與輸出、以手動計時器與模擬的物品
API 進行的掃描，以及以模擬的拾取、地圖與單位 API 進行的掉落紀錄。這些測試只能證明邏輯正確；用戶端實際的 API 要在
遊戲中檢查。

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
