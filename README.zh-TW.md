# Tandem

> 與你的 WoW 玩家協作

[English](README.md) | 繁體中文

Tandem 是一個 World of Warcraft addon。它收集透過掃描物品 ID 建立的可裝備物品快取，以及每件物品的來源紀錄：掉落它的
生物與物件（附上用來計算掉落率的擊殺數與拾取屍體數）、以它為獎勵的任務，以及販售它的商人。它把這些資料與其他玩家
貢獻的資料合併，建議你的角色能使用的最佳已知裝備，以及到哪裡取得。它絕不會替玩家執行任何動作，戰鬥中不會記錄任何
資料，建議類指令與裝備視窗在戰鬥中也都無法使用。在戰鬥外，它也會在它認得的物品提示框中加上幾行說明。

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
| `/tandem rank <item link\|id>`        | 列出物品在其部位中的排名，以及到哪裡取得                          |
| `/tandem export`                      | 顯示 `make import` 會從這個帳號收集哪些資料                       |
| `/tandem browse [<slot>]`             | 開啟或關閉一個視窗，列出所有部位或單一部位的所有已知裝備          |
| `/tandem minimap [on\|off]`           | 顯示或隱藏小地圖按鈕；不加參數時切換顯示                          |

戰鬥中執行 `gear`、`rank`、`export` 與 `browse` 時，只會印出 `Tandem: not available in combat`，不做任何事。
`minimap` 在戰鬥中也能使用。

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

第一次掃描前，`found IDs` 會顯示 `none`，最後一行會顯示 `Last run: never`。`Loot entries` 把掉落、任務獎勵與商人物品
一起計算。`Unsaved records` 計算的是 addon 載入後新增的物品、掉落次數、任務獎勵、商人物品、NPC 與任務名稱、擊殺數與
拾取屍體數；用戶端未存檔就結束時，這些資料會遺失。

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

`gear` 預設只列出有已知來源的物品，也就是在你的資料或隨附資料中有掉落、任務獎勵或商人紀錄（見
[任務獎勵與商人](#任務獎勵與商人)）。加上 `all`，例如 `/tandem gear all` 或
`/tandem gear chest all`，就會一併列出其他快取中的物品，並標示 `(no known source)`。物品快取中也有遊戲裡取得不到的
物品。標記為已棄用的物品（見[已棄用的物品](#已棄用的物品)）不論是否加上 `all` 都不會列出。

### `/tandem rank`

`/tandem rank` 接受物品連結（在聊天輸入框中 Shift 點擊物品）或物品 ID。它會印出物品在其部位中、於你能使用且有已知來源的
物品之間的排名（物品本身不在其中時也會計入），你自己能否使用它，以及最多 5 個取得來源：

```text
[Tough Leather Armor] (upgrade): rank 2 of 14 for Chest
  Corina Steele, Elwynn Forest - vendor
  Kobold Miner, Elwynn Forest - drops: 3, 4.2% per looted corpse (upper bound)
  Defias Thug, Elwynn Forest - drops: 1
Ranked by item level, then quality; stats are not considered
```

任務獎勵顯示為 `<quest>, <map> - quest reward`，商人物品顯示為 `<npc>, <map> - vendor`，不附掉落次數或掉落率。它們
排在掉落之前；只有另一陣營看過的則排在最後，並以 `(Horde only)` 或 `(Alliance only)` 結尾；見
[任務獎勵與商人](#任務獎勵與商人)。

- 你無法使用的物品仍會排名並計入總數，後面接著 `you cannot use it: level <n> required` 或
  `your class cannot use it`，且不會標示為升級。
- 單手武器以主手武器排名。
- 標記為已棄用的物品（見[已棄用的物品](#已棄用的物品)）會與其他物品比較排名（其他物品絕不包含已棄用的物品），第一行
  之後接著 `this item is deprecated`。
- 沒有已知來源的物品同樣會排名，後面接著 `no known source`。
- 不在快取中的物品會印出 `Tandem: item <id> is not known; scan or loot it first`。襯衣、外袍、背包與彈藥會印出
  `<item> does not go in a ranked slot`。
- 釣魚的掉落，也就是物件 35591（Fishing Bobber，釣魚浮標），會印成 `Fishing`。其他沒有記錄名稱的來源會印成
  `npc #<id>`、`object #<id>` 或 `quest #<id>`；用戶端沒有提供名稱的地圖會印成 `unknown map`。超過 5 個來源時，最後會印出
  `and <n> more sources`。

### `/tandem browse`

`/tandem browse` 會開啟標題為 `Tandem gear` 的視窗，依[裝備如何排名](#裝備如何排名)所述的順序，由好到差列出所有已知
物品；再執行一次即可關閉視窗。`/tandem browse <slot>` 會開啟視窗並顯示單一部位，視窗已開啟時則切換到該部位。部位參數與
`gear` 相同，未知的參數會印出同樣的 `Tandem: unknown slot <token>; use one of: ...`。用戶端尚未提供你的職業或等級時，
會印出 `Tandem: your class or level is not known yet; try again in a moment`，不會開啟視窗。

不輸入指令也能開啟視窗：點擊小地圖 addon 收納選單（小地圖旁列出各 addon 的按鈕）中的 **Tandem**；WoW Forever 有這個
選單。滑鼠移到這一項上會顯示提示框，`Tandem` 下方是 `Click to browse known gear`。點擊會以 `All slots` 開啟視窗，視窗
已開啟時則關閉它。戰鬥中點擊只會印出 `Tandem: not available in combat`，不會開啟視窗；尚未取得你的職業或等級時，會印出
`Tandem: your class or level is not known yet; try again in a moment`，也不會開啟視窗。

小地圖邊緣還有一個圓形 Tandem 按鈕，點擊效果相同；有收納選單時兩者並存，沒有收納選單的用戶端則由它代替。按鈕預設
顯示，移動之前位於左下方。它的提示框還會多一行 `Drag to move this button`：用滑鼠左鍵拖曳即可讓它沿著小地圖移動。
它的位置以角度存在 `TandemDB.ui`，`/reload` 或下次登入後會還原。

用 `/tandem minimap off` 或在視窗中取消勾選 `Show minimap button` 即可隱藏按鈕，用 `/tandem minimap on` 或勾選同一個
方塊即可讓它重新出現；只輸入 `/tandem minimap` 則切換顯示。指令會印出 `Tandem: minimap button hidden` 或
`Tandem: minimap button shown`，不論用哪一種方式，方塊都會跟著同步。這個選擇存在 `TandemDB.ui`，下次登入時套用。

視窗上方：

- 部位下拉選單：`All slots`，接著是各部位名稱。選擇 `All slots` 時，每件物品只列出一次，歸在它的第一個部位，因此單手
  武器只會以主手武器出現一次。你的職業在目前等級能雙持時，這類單手武器在這裡會同時與兩隻手比較：任一手穿戴著它時
  標示 `(equipped)`；它的物品等級高於兩手中（已知物品等級者）較低的那一手時標示 `(upgrade)`。在 `Main hand` 與
  `Off hand` 部位中，則只與該手比較。
- 品質下拉選單：`All qualities`，接著是 `Poor`、`Common`、`Uncommon`、`Rare`、`Epic` 與 `Legendary`，各以其品質顏色
  顯示。選擇一種品質後，只列出該品質的物品。
- 列出的物品數量，顯示為 `<n> items`。

其下有三個勾選框：

- `Usable only`：第一次開啟視窗時已勾選。取消勾選後，你的職業或等級無法使用的物品也會列出，並以半透明顯示。
- `Hide deprecated`：第一次開啟視窗時已勾選。取消勾選後，標記為已棄用的物品（見[已棄用的物品](#已棄用的物品)）也會
  列出，名稱後面以灰色接著 `(deprecated)` 標示。
- `Show minimap button`：小地圖按鈕顯示時為勾選；取消勾選即可隱藏按鈕，效果與 `/tandem minimap off` 相同。

每次開啟視窗時都會設定部位：`All slots`，或 `/tandem browse <slot>` 指定的部位。品質選擇、`Usable only` 與
`Hide deprecated` 在用戶端執行期間會保留，但不會存檔：`/reload` 或登出後，品質回到 `All qualities`，兩個勾選框也都
再次勾選。

勾選框下方是掃描列，執行與 [`/tandem scan`](#tandem-scan) 相同的掃描：

- `Rate` 與 `Cap` 輸入框，第一次開啟視窗時顯示 `10/s` 與 `100`。規則與指令參數相同：速率為 `<n>/s` 或 `<n>/m`，
  介於 `1/m` 與 `50/s` 之間；上限為 `1` 到 `100000`。空白的輸入框使用預設值。按 Enter 或 Escape 會離開輸入框，
  不會關閉視窗。輸入的內容會保留到 `/reload` 或登出為止，但不會存檔；之後輸入框會再次顯示 `10/s` 與 `100`。
- `Start`：以這些數值從掃描位置開始掃描。掃描進行中時，不論是從這裡還是以 `/tandem scan` 開始，按鈕都會顯示
  `Stop`，點擊後會像 `/tandem scan stop` 一樣停止掃描。
- 狀態列。掃描進行中顯示 `Scanning: <n> of <cap> IDs, <hits> found, next ID <id>`，視窗開啟期間每秒更新；
  其他時候顯示 `<n> known items, next scan from ID <id>`。

從掃描列開始的掃描會印出與指令相同的聊天訊息，例如 `Tandem: scanning <n> IDs from ID <id>` 與摘要。數值無效時會印出
指令的用法說明，不會開始掃描：

```text
  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)
```

戰鬥中，`Start` 與 `Stop` 只會印出 `Tandem: not available in combat`，不做任何事。掃描結束時（達到上限或被停止），
已開啟的視窗會重新列出物品，因此掃描找到的物品不必重新開啟視窗就會出現。

每一列顯示：

- 物品圖示；用戶端沒有提供時顯示問號。
- 以品質顏色顯示的物品名稱，後面以灰色接著[裝備如何排名](#裝備如何排名)中的標示：`(equipped)`、`(upgrade)` 或
  `(no known source)`。與 `gear ... all` 一樣，視窗也會列出沒有已知來源的物品。半透明的物品絕不會標示 `(upgrade)`。
- 物品等級，接著是一個等級。通常是物品的需求等級。你的等級不足以使用該物品時，改以紅色顯示你從幾級起可以使用：取
  物品需求等級與你的職業學會該護甲或武器類型的等級中較高者，例如獵人看鎖甲會顯示 `40`。你的職業完全無法使用的物品
  只會以半透明顯示，不會變紅。

用戶端尚未載入的物品會以品質顏色顯示為 `item #<id>`。視窗會向用戶端要求這些物品，資料送達後名稱很快就會補上，不必
重新開啟視窗。物品紀錄中已標記為已棄用的物品（不論在你的資料或隨附資料中），不論名稱是否已載入都會隱藏。尚未標記的
物品由於名稱還不知道，即使勾選了 `Hide deprecated` 仍會列出。若送達的名稱表示它已棄用，該列會顯示
灰色的 `(deprecated)` 標示，並在下次重新列出清單時（例如你變更篩選條件時）離開清單，而不會在滑鼠底下突然跳走。

滑鼠移到一列上會顯示遊戲的物品提示框。點擊一列即可選取它：底部的窗格會顯示物品連結與最多 5 個取得來源，格式與
順序都與 `rank` 相同；來源更多時，最後會顯示 `and <n> more sources`。沒有選取任何物品時，窗格顯示
`Select an item to see where it drops`。

把物品放到視窗上即可查詢它：從背包或角色資訊視窗拿起物品，拖到清單或視窗背景上，或拿著它在那裡點擊。物品會離開
游標並留在原處。下拉選單會切換到該物品的部位，選取該物品並捲動到它那一列，窗格顯示它的來源。你無法使用該物品時，
`Usable only` 會取消勾選，讓它那一列以半透明列出；可使用的物品則不會改變這個勾選框。同樣地，已棄用的物品會取消勾選
`Hide deprecated`，品質與所選品質不同的物品會把品質下拉選單改回 `All qualities`。沒有排名部位的物品（例如襯衣）
會把清單切換到 `All slots`，它不會列在清單中，但窗格仍會顯示它的來源，篩選條件也維持不變。不在快取中的物品不會選取
任何物品，也不會改變部位；窗格顯示 `Tandem: item <id> is not known; scan or loot it first`。游標上的其他東西（例如法術）會被忽略，並留在
游標上。戰鬥中放上的物品只會印出 `Tandem: not available in combat`，並留在游標上。

視窗在戰鬥中無法使用。`/tandem browse` 會印出 `Tandem: not available in combat`，不會開啟視窗；已開啟的視窗會在戰鬥
開始時關閉，之後也不會自動重新開啟。按 Escape 也能關閉視窗。用滑鼠左鍵拖曳即可移動視窗。視窗位置存在
`TandemDB.ui`，`/reload` 或下次登入後會還原；在你第一次移動它之前，視窗會在畫面中央開啟。

視窗開啟時寬 640、高 620。拖曳右下角的拖曳點即可調整大小，範圍從 520 × 480 到 1200 × 1000；畫面較小時，上限為畫面
大小。清單與物品名稱會隨視窗變寬，窗格則留在底部。每次移動視窗或調整大小時，大小都會與位置一起存在 `TandemDB.ui`，
`/reload` 或下次登入後會還原，並限制在上述範圍內。用戶端無法調整框架大小時，不會有拖曳點，視窗維持預設大小。

`zhTW` 用戶端的視窗文字會顯示為中文。

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

`gear` 只列出、`rank` 只拿來比較的，都是你的職業與等級能使用的物品；勾選 `Usable only` 時，瀏覽視窗也一樣。物品可使用的條件：

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
- `(no known source)`：沒有它的掉落、任務獎勵或商人紀錄（只出現在 `gear ... all` 與瀏覽視窗）。

### 物品提示框

在戰鬥外，滑鼠移到 Tandem 認得的物品上時，遊戲提示框底部會多出幾行。只要物品的提示框是遊戲的主提示框就會出現，
例如背包、角色資訊視窗與瀏覽視窗中的物品，以及在聊天視窗點擊物品連結時開啟的提示框。顯示你穿戴物品的比較提示框則
不會加上任何內容。

- 以 Tandem 藍色顯示 `Tandem: rank <n> of <total> for <slot>`，後面接著[裝備如何排名](#裝備如何排名)中的標示：
  `(equipped)`、`(upgrade)` 或 `(no known source)`。排名與 `/tandem rank` 印出的相同。單手武器以主手武器排名；你的
  職業在目前等級能雙持時，會像瀏覽視窗的 `All slots` 一樣同時與兩隻手比較。沒有排名部位的物品（例如襯衣）沒有排名
  這一行。
- 你無法使用該物品時，以紅色顯示 `Tandem: you cannot use it: level <n> required` 或
  `Tandem: your class cannot use it`。
- 以淺灰色顯示該物品的第一個來源，順序與 `rank` 相同：
  - 你的陣營看過的任務獎勵或商人：`Tandem: reward from <quest>, <map>` 或 `Tandem: sold by <npc>, <map>`，不附掉落率；
  - 否則是掉落次數最多的來源：`Tandem: drops from <source>, <map>`；已知掉落率時接著 `(<rate>% per kill)` 或
    `(up to <rate>%)`（見[掉落率](#掉落率)）；
  - 否則是只有另一陣營看過的任務獎勵或商人，格式同上，後面接著 `(Horde only)` 或 `(Alliance only)`。

  還有其他已知來源時再接著 `(+<n> more)`。來源名稱的顯示方式與 `rank` 相同。沒有已知來源的物品沒有這一行。

例如：

```text
Tandem: rank 2 of 14 for Chest (upgrade)
Tandem: sold by Corina Steele, Elwynn Forest (+2 more)
```

只會掉落的物品則例如顯示 `Tandem: drops from Kobold Miner, Elwynn Forest (up to 4.2%) (+1 more)`。

標記為已棄用的物品只會有一行灰色的 `Tandem: deprecated item`，沒有其他內容。Tandem 不認得的物品不會加上任何內容；
戰鬥中也不會加上任何一行，聊天視窗也不會印出任何訊息。用戶端尚未提供你的職業或等級時，同樣不會加上任何內容。
`zhTW` 用戶端會顯示中文。

### 任務獎勵與商人

除了掉落，Tandem 也會記錄以物品為獎勵的任務，以及販售物品的商人：

- 任務獎勵：任務視窗顯示獎勵時，不論是在任務發布者處（`QUEST_DETAIL`）或交回任務時（`QUEST_COMPLETE`），每件獎勵與
  可選獎勵物品都會記錄在該任務底下，並記下任務名稱。
- 商人物品：商人視窗開啟時（`MERCHANT_SHOW`），以及之後每次 `MERCHANT_UPDATE`（因為物品連結可能較晚送達），商人列出的
  每件物品都會記錄在該商人底下，並記下商人名稱。

只記錄可裝備的物品。不在物品快取中的物品也會一併存入快取，立即存入或在用戶端送達物品資料後存入，因此不必掃描就會
出現在 `gear` 與瀏覽視窗中。戰鬥中、因存檔資料使用較新 schema 而停止記錄時、用戶端缺少任務或商人 API 時，或用戶端
沒有提供你的陣營時，都不會記錄任何資料。

每個任務或商人在每個帳號中對每件物品只記錄一次：再次看到不會增加任何東西，所以計數維持 1。它保留你第一次看到它時
的地圖與座標（任務發布者、交回任務處或商人所在處），不論在哪張地圖看到都只列出一次。在隨附資料中，它的計數是看過它
的貢獻者人數；這個計數只用來排列這類來源之間的順序，絕不會印出。任務獎勵與商人物品沒有掉落率，也不記錄價格。

每筆紀錄也會記下哪些陣營看過它（聯盟、部落或兩者），取自開啟視窗的角色的陣營。來源依下列順序列出，同一組內依計數
排序：

1. 你的陣營看過的任務獎勵與商人物品。
2. 掉落。
3. 只有另一陣營看過的任務獎勵與商人物品，標示 `(Horde only)` 或 `(Alliance only)`。

用戶端沒有提供你的陣營時，不會標示任何來源，所有任務獎勵與商人物品都排在最前面。

| 來源     | `rank` 與瀏覽視窗窗格           | 物品提示框                           |
| -------- | ------------------------------- | ------------------------------------ |
| 任務獎勵 | `<quest>, <map> - quest reward` | `Tandem: reward from <quest>, <map>` |
| 商人物品 | `<npc>, <map> - vendor`         | `Tandem: sold by <npc>, <map>`       |

任務名稱取自你的資料，其次是隨附資料中用戶端語言的任務名稱，再其次是用戶端的任務紀錄，都沒有時顯示 `quest #<id>`。
商人名稱與其他 NPC 相同，沒有時顯示 `npc #<id>`。`zhTW` 用戶端的這幾行與陣營標示會顯示為中文，例如
`Tandem：由 <npc> 販售，<map>（僅限部落）`。

任務或商人來源表示已知物品可以從那裡取得，不代表你現在就能取得：商人可能限量販售或需要聲望，任務可能屬於任務鏈、
只能完成一次，或需要特定職業或等級。

### 已棄用的物品

名稱以 `Deprecated` 開頭的物品（不分大小寫，忽略開頭的空格）會被標記為已棄用。物品快取不儲存名稱，因此這個標記存在
物品紀錄中，作為選用的第七個欄位。掃描把物品存入快取時就會設定；之後只要 Tandem 看到用戶端已持有的已知物品名稱，
也會設定：瀏覽視窗中的列、物品提示框，以及放到視窗上的物品。標記一件只存在於隨附資料中的物品時，會在你自己的 `items`
中存一份已標記的紀錄，讓下次 `make import` 隨附這個標記；它會計入你的已知物品數與 `Unsaved records`。

`/tandem gear` 絕不會列出已標記的物品，`/tandem rank` 會印出 `this item is deprecated`，瀏覽視窗在勾選
`Hide deprecated` 時隱藏它們、否則標示 `(deprecated)`，它們的物品提示框則顯示 `Tandem: deprecated item`。物品紀錄中
已標記的物品（不論在你的資料或隨附資料中）不論用戶端是否已載入名稱都是如此。尚未標記、且用戶端尚未載入名稱的物品
不會被當作已棄用，與其他物品一樣處理。

### 掉落率

只有生物會印出掉落率，依每個 NPC 的下列兩種計數之一計算：

- 擊殺：你角色的最後一擊，在用戶端允許時從戰鬥紀錄讀取（`/tandem count` 會顯示是否允許）。寵物或隊友的擊殺不計入。
  戰鬥中的擊殺會在戰鬥結束後才儲存。WoW Forever 1.60.1 不允許：`CombatLogGetCurrentEventInfo` 與
  `C_CombatLog.GetCurrentEventInfo` 都不存在，註冊戰鬥紀錄事件也會被擋下，因此 `count` 顯示 `unavailable`。經驗值
  也無法用來計算擊殺：Forever 不會把 `CHAT_MSG_COMBAT_XP_GAIN` 傳給 addon，即使聊天視窗中會出現經驗值訊息；而
  `PLAYER_XP_UPDATE` 無法對應到被擊殺的怪物，因為事件抵達時目標已不再顯示為死亡。因此 Forever 上沒有擊殺數，所有掉落率
  都以拾取屍體計算。
- 拾取屍體：你開啟過拾取視窗的每一具不同的屍體，只有金錢的屍體也算。沒有東西可拾取的屍體無法開啟，因此以拾取屍體
  計算的掉落率是上限。

該 NPC 有擊殺數時使用擊殺數，否則使用拾取屍體數，並標明使用哪一種。你自己的資料與隨附資料絕不相加：掉落率的掉落次數
與分母都取自其中一份，也就是在看過這件物品從該 NPC 掉落的資料中，分母較大的那一份。掉落次數超過分母時（例如拾取了
別人擊殺的怪物），不顯示掉落率，而不是顯示超過 100% 的數字。寶箱、採集點與釣魚等物件沒有掉落率，任務獎勵與商人
物品也沒有。

### 隨附資料

addon 隨附 `Tandem/Data/Loot.lua`，由 `make import` 從 `data/contributions/` 底下的所有貢獻合併而成：掉落紀錄（掉落、
任務獎勵與商人物品）、依語系分組的 NPC 與任務名稱、看過每筆任務獎勵與商人物品的陣營、擊殺數、拾取屍體數與物品快取。
指令會把它與你自己的 `TandemDB` 一起使用。每筆掉落紀錄的掉落次數取你的
數值與隨附數值中較大者，因為你的資料可能已經包含在隨附檔案中。擊殺數與拾取屍體數不這樣混用：掉落率的掉落次數與分母
取自同一份資料，詳見[掉落率](#掉落率)。兩邊都有的任務獎勵或商人物品會合併成一個來源，帶有兩邊的陣營。物品紀錄則以
你自己的快取為準。沒有這個
檔案時，指令只使用你自己的資料。

## 收集的資料

所有資料都存在一個帳號共用的表 `TandemDB`，存檔位置為
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`。

| Key       | 內容                                                                                                  |
| --------- | ----------------------------------------------------------------------------------------------------- |
| `items`   | 每個可裝備物品 ID：物品等級、需求等級、品質、裝備部位、class、subclass；已棄用時第七個欄位為 `1`      |
| `scan`    | 掃描位置、不可裝備數量、找到的最小與最大 ID、每 1000 個 ID 區塊的命中數、上次掃描                     |
| `loot`    | 依物品、來源與地圖分組：NPC、物件、任務或商人 ID、地圖 ID、掉落次數、最多 5 個不同的座標；陣營        |
| `npcs`    | 以 NPC ID 對應的 NPC 名稱，包含商人                                                                   |
| `quests`  | 以任務 ID 對應的任務名稱                                                                              |
| `kills`   | 依 NPC ID：你的角色對該 NPC 的最後一擊次數                                                            |
| `corpses` | 依 NPC ID：你拾取過的該 NPC 不同屍體數                                                                |
| `ui`      | `window`：瀏覽視窗錨點、相對錨點、x、y、寬、高；`minimap`：按鈕角度；`minimapHidden`：隱藏時為 `true` |

- 存在但不可裝備的物品只計入 `scan.nonEquippable`，不會儲存。
- `scan.lastRun` 保存上次掃描的開始時間、ID 範圍、速率、經過秒數，以及摘要印出的各項計數。
- 每次在戰鬥外開啟拾取視窗時，每個來源都會記錄一次。來源可能是生物（`kind = "c"`，NPC ID）或遊戲物件
  （`kind = "o"`，物件 ID）；`kind = "?"` 表示用戶端沒有提供來源。用戶端沒有回報地圖與座標時，這兩項會留空。
- 任務獎勵（`kind = "q"`，任務 ID）或商人物品（`kind = "v"`，商人的 NPC ID）只記錄一次，計數為 `1`，帶有一個座標與
  `factions`：`1` 為聯盟、`2` 為部落、`3` 為兩者（見[任務獎勵與商人](#任務獎勵與商人)）。
- 同一次登入期間再次開啟的屍體或物件（例如沒拾取完的屍體）不會增加掉落紀錄，也不會增加拾取屍體數。addon 會記住最近
  200 個來源；`/reload` 後會忘記，所以重新載入後再開啟同一具屍體會重複計算。
- 只有在拾取的屍體是你的目標或位於滑鼠游標下時，才會記錄 NPC 名稱。
- `ui` 只記錄瀏覽視窗與小地圖按鈕的位置、視窗大小，以及按鈕是否隱藏；角度在你拖曳按鈕後才儲存，大小在你移動視窗
  或調整大小時儲存，`minimapHidden` 只在按鈕隱藏時存在。它不計入 `Unsaved records`，無效的位置、角度或旗標會在載入時
  捨棄。無效的大小只會單獨捨棄，位置仍會保留。

`TandemDB.schemaVersion` 為 `3`。schema 2 的存檔資料會在載入時遷移，並新增空的 `quests`。較新 schema 的存檔資料會
原樣保留，在 addon 更新之前不會記錄任何資料。

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
8. 在戰鬥外，與一位任務獎勵有可裝備物品的任務發布者對話，再開啟一位販售武器或護甲的商人。`/tandem count` 的掉落紀錄
   會增加，`Unsaved records` 也會增加。關閉商人視窗再開啟一次：掉落紀錄不變。接著執行 `/reload`，確認 `loot` 中有
   `kind = "q"` 與 `kind = "v"` 的紀錄，`quests` 中有該任務的名稱。

請回報步驟 3 與 7 的摘要、步驟 8 是否有記錄到資料、`/tandem count` 的輸出、任何 Lua 錯誤，以及
`SavedVariables/Tandem.lua` 檔案。

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

### 檢查瀏覽視窗

1. 在戰鬥外執行 `/tandem browse`。畫面中央會開啟標題為 `Tandem gear` 的視窗：部位下拉選單顯示 `All slots`，品質
   下拉選單顯示 `All qualities`，`Usable only` 與 `Hide deprecated` 已勾選，右上角顯示物品數量，中間是清單，底部窗格
   顯示 `Select an item to see where it drops`。
2. 取消勾選 `Usable only` 並選擇 `All slots`，讓清單有最多約 1.5k 列。用清單右側的捲軸與滑鼠滾輪捲動清單；兩者都能
   順暢捲到底再捲回來。記下是否有出現捲軸。
3. 在下拉選單中選擇 `Chest`。只會列出胸部物品，數量改變；你穿戴的物品若是已知物品，會標示 `(equipped)`。以
   `/tandem browse` 關閉視窗，再執行 `/tandem browse chest`：視窗開啟時下拉選單已選取 `Chest`。
4. 滑鼠移到一列上：遊戲的提示框顯示物品屬性，滑鼠移開後提示框關閉。
5. 點擊一列：該列會被標示，底部窗格顯示物品連結與掉落來源。超過 5 個來源的物品最後會顯示 `and <n> more sources`，
   你釣到的物品會列出 `Fishing`，沒有掉落紀錄的物品會顯示 `no known source`。
6. 顯示為 `item #<id>` 的列很快就會變成物品名稱，不必重新開啟視窗。
7. 取消勾選 `Usable only` 時，你的職業或等級無法使用的物品以半透明顯示。等級不足的物品會以紅色顯示你從幾級起可以
   使用，例如 20 級獵人看鎖甲顯示 `40`；你的職業永遠無法使用的物品不會變紅。再勾選 `Usable only`：這些物品會消失，
   數量也會減少。
8. 把視窗拖到別處，輸入 `/reload`，再執行 `/tandem browse`：視窗會在你留下的位置開啟。
9. 按 Escape：視窗關閉。
10. 開啟視窗後開始戰鬥：戰鬥一開始視窗就會關閉。仍在戰鬥中時執行 `/tandem browse`：只會印出
    `Tandem: not available in combat`，不會開啟任何視窗。
11. 在戰鬥外開啟小地圖旁的 addon 收納選單：其中列有 **Tandem**。滑鼠移到這一項上：提示框顯示 `Tandem` 與
    `Click to browse known gear`，滑鼠移開後提示框關閉。點擊這一項：視窗以 `All slots` 開啟。再點擊一次：視窗關閉。
    小地圖邊緣也會顯示 Tandem 按鈕，沒有收納選單的用戶端上也一樣；用它確認同樣的行為，並確認它的提示框還會顯示
    `Drag to move this button`。把它沿著小地圖拖到別處，輸入 `/reload`，確認它仍在你留下的位置。執行
    `/tandem minimap off`：聊天視窗顯示 `Tandem: minimap button hidden`，按鈕消失，視窗中的 `Show minimap button`
    變成未勾選。輸入 `/reload`：按鈕仍然隱藏。勾選 `Show minimap button`：按鈕重新出現。
12. 開啟視窗。下拉選單下方的輸入框顯示 `10/s` 與 `100`，按鈕顯示 `Start`，狀態列顯示
    `<n> known items, next scan from ID <id>`，數字與 `/tandem count` 的已知物品數及掃描位置相同。
13. 在 `Cap` 輸入 `20` 並點擊 `Start`。聊天視窗顯示 `Tandem: scanning 20 IDs from ID <id>`，按鈕顯示 `Stop`，
    狀態列每秒往上數。摘要印出時，按鈕再次顯示 `Start`，狀態列顯示新的掃描位置，清單也會重新整理。
14. 在 `Cap` 輸入 `1000`，點擊 `Start` 再點擊 `Stop`：摘要印出，按鈕顯示 `Start`。關閉視窗，執行 `/tandem scan 20`，
    並在掃描進行中重新開啟視窗：狀態列顯示它的進度。
15. 在 `Rate` 輸入 `abc`，或在 `Cap` 輸入 `0`，然後點擊 `Start`：聊天視窗顯示
    `/tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)`，不會開始掃描。點擊一個輸入框後
    按 Escape：輸入框失去焦點，視窗仍然開著。再按一次 Escape：視窗關閉。
16. 開啟視窗，從背包拿起一件物品放到清單上。物品留在背包中並離開游標，下拉選單切換到它的部位，它那一列被選取，
    窗格顯示它的掉落來源。用角色資訊視窗中的物品再試一次；再勾選 `Usable only`，放上一件你的職業無法使用的已知物品：
    勾選框會取消勾選，該列以半透明顯示。
17. 放上一件不在快取中的物品，例如任務物品：窗格顯示 `Tandem: item <id> is not known; scan or loot it first`。
18. 從法術書拿起一個法術放到視窗上：什麼都不會改變，法術仍留在游標上。
19. 拖曳右下角的拖曳點：視窗會放大縮小，但不會小於 520 × 480 或大於 1200 × 1000，清單與物品名稱隨寬度變化。把視窗
    拉寬、移動它，輸入 `/reload`，再執行 `/tandem browse`：視窗以相同的位置與大小開啟。
20. 在品質下拉選單選擇 `Rare`：只列出藍色（精良）的物品，數量減少。再選回 `All qualities`。選擇 `Rare` 時放上
    一件普通品質的物品：下拉選單顯示 `All qualities`。
21. 取消勾選 `Hide deprecated`：名稱以 `Deprecated` 開頭的物品出現，以灰色標示 `(deprecated)`，數量增加。再勾選
    一次：它們消失。勾選時放上一件已棄用的物品：勾選框會取消勾選。
22. 在你的職業能雙持時選擇 `All slots`，看一把單手武器：你副手穿戴著它時標示 `(equipped)`，它勝過你兩把武器中較弱的
    那把時標示 `(upgrade)`。
23. 以一件已棄用物品的 ID 執行 `/tandem gear` 與 `/tandem rank <id>`：`gear` 絕不會列出它，`rank` 會在排名那一行之後
    印出 `this item is deprecated`。

請回報捲軸是否出現、步驟 2 捲動的感覺、步驟 11 收納選單與小地圖按鈕是否都有出現、步驟 19 是否有拖曳點、任何 Lua
錯誤，以及任何在視窗中放不下的文字（視窗最小時也一樣）。

### 檢查物品提示框

1. 在戰鬥外，滑鼠移到背包中一件 Tandem 認得、且有排名部位的物品上。在遊戲的說明文字下方，一行藍色文字顯示
   `Tandem: rank <n> of <total> for <slot>`，並帶有與瀏覽視窗中同一件物品相同的 `(equipped)`、`(upgrade)` 或
   `(no known source)`。
2. 滑鼠移到一件你無法使用的物品上：一行紅色文字顯示 `Tandem: you cannot use it: level <n> required` 或
   `Tandem: your class cannot use it`。
3. 滑鼠移到一件你從怪物身上拾取的物品上：一行灰色文字顯示 `Tandem: drops from <source>, <map>`，已知掉落率時附上
   掉落率，還有其他來源時附上 `(+<n> more)`。它與 `/tandem rank` 列出的第一個來源一致。
4. 滑鼠移到一件商人販售的物品，或你看過的任務獎勵上：灰色文字顯示 `Tandem: sold by <npc>, <map>` 或
   `Tandem: reward from <quest>, <map>`，不附掉落率，即使該物品也會掉落。`/tandem rank` 也把同一個來源列在第一個，
   顯示為 `- vendor` 或 `- quest reward`。
5. 滑鼠移到角色資訊視窗中的物品與瀏覽視窗的列上：它們也有相同的幾行。把一件物品 Shift 點擊到聊天視窗並點擊該連結：
   開啟的提示框也有這幾行。旁邊顯示的比較提示框則沒有。
6. 滑鼠移到一件已棄用的物品上，例如取消勾選 `Hide deprecated` 後列出的物品：唯一的 Tandem 文字是灰色的
   `Tandem: deprecated item`。
7. 滑鼠移到一件 Tandem 不認得的物品上，例如任務物品：不會加上任何 Tandem 文字。
8. 開始戰鬥，在戰鬥中滑鼠移到同樣的物品上：不會加上任何 Tandem 文字，聊天視窗也不會印出任何訊息。

請回報任何提示框說明與 `/tandem rank` 不一致的物品、步驟 5 中聊天連結的提示框是否有出現這幾行，以及任何 Lua 錯誤。

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
API 進行的掃描、以模擬的拾取、戰鬥紀錄、地圖與單位 API 進行的掉落、擊殺與屍體紀錄、以模擬的任務與商人 API
進行的任務獎勵與商人物品紀錄、以模擬的職業、等級與已穿戴
物品進行的裝備建議、以模擬的框架、元件與提示框進行的瀏覽視窗，以及以模擬的提示框 API 進行的物品提示框說明。這些測試只能證明邏輯正確；用戶端實際的 API 要在遊戲中檢查。`scripts/import_test.sh` 以拋棄式的
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
wrote data/contributions/3f2a9c81d0b4.lua (enUS: 42 loot entries, 7 npc names, 3 quest names, 120 items, 15 kills, 12 looted corpses)
wrote Tandem/Data/Loot.lua (1 contributors, 120 items, 42 loot rows)
```

ID 與數字僅為範例。`make import` 會讀取偵測到的用戶端中每一個
`<World of Warcraft>/<FLAVOR>/WTF/Account/*/SavedVariables/Tandem.lua`，並寫入：

| 檔案                          | 內容                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------- |
| `data/contributions/<id>.lua` | 單一帳號的 `loot`、`npcs`、`quests`、`items`、`kills`、`corpses` 及其語系，每次匯入都會覆寫 |
| `Tandem/Data/Loot.lua`        | 由所有貢獻合併，由 addon 載入                                                               |

合併檔會加總掉落次數、擊殺數與拾取屍體數，每筆掉落紀錄保留最多 5 個座標，NPC 與任務名稱依語系分組，物品快取則取
聯集。任務獎勵或商人物品不論各份貢獻在哪張地圖看到，都合併成一列：保留最小的地圖 ID 與該地圖的座標，加總計數（因此
計數就是看過它的貢獻者人數），並把陣營合併到 `S.factions`，key 為 `"<item>:<kind>:<id>:<map>"`；兩份
貢獻對同一件物品的紀錄不同時，以檔名排序在前的那份為準；但只要任何一份貢獻把該物品標記為已棄用，它就會被標記。它也以 `contributors` 記錄合併了多少份貢獻。舊版的
`data/loot.lua` 不再寫入。在匯入擊殺、屍體、物品與任務之前寫成的貢獻檔仍可讀取。

- `<id>` 是帳號資料夾名稱 SHA-256 的前 12 個十六進位字元。資料夾名稱，也就是帳號號碼，絕不會被寫入或印出；同一個
  帳號永遠得到相同的 ID。
- 語系取自 `WTF/Config.wtf` 的 `SET textLocale` 這一行，沒有時為 `enUS`。NPC 名稱與任務名稱以用戶端語言儲存，因此
  `Tandem/Data/Loot.lua` 把它們分別放在 `names[<locale>]` 與 `questNames[<locale>]` 底下。
- `scan` 與 `ui` 只留在本機。`items` 會匯入，因為只在自己掃描的幾百件物品之間排名意義不大。
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
