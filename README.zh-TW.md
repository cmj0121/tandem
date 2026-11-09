# Tandem

> 與你的 WoW 玩家協作

[English](README.md) | 繁體中文

Tandem 是一個 World of Warcraft addon，會在物品勝過你身上的裝備時告訴你。它依用戶端當下提供的資料判斷背包、拾取
視窗與任務獎勵中的每件物品：部位、需求等級、護甲或武器類型、提示框中的需求，以及依你的職業與天賦樹加權的屬性。升級
物品會在背包或拾取按鈕上出現紅色邊框與綠色向上箭頭，聊天視窗顯示一行訊息，提示框也多一行綠字。Tandem 也會標出最佳的
任務獎勵選擇，並標示快捷列上等級過時的法術。在你要求時，它會以快捷列為中心重新排列畫面，加上經驗條、背包圖示列，薩滿
還有職業區。它絕不會替玩家執行任何動作：它只提供建議，除了你自己的屬性權重、職業訓練師教授的內容，以及介面配置是否
開啟之外，不儲存任何資料。

## 安裝

在儲存庫根目錄執行：

```sh
make install
```

這會把儲存庫的 `Tandem/` 資料夾連結到用戶端，成為
`<World of Warcraft>/_forever_/Interface/AddOns/Tandem`，因此修改 Lua 檔案後，在遊戲中執行 `/reload` 即可生效。
連結已存在時再次執行不會有任何動作。

移除方式：

```sh
make uninstall
```

### 尋找用戶端

`make install` 與 `make uninstall` 會透過 `scripts/wow-dir.sh` 找出 `World of Warcraft` 資料夾。只有包含
`<FLAVOR>/Interface/AddOns` 的資料夾才符合條件。搜尋順序如下：

1. `WOW_DIR`（若有設定）。若它不符合條件，安裝會直接失敗，不會繼續搜尋。
2. `/Applications/World of Warcraft`、`~/Applications/World of Warcraft` 和 `/Users/Shared/World of Warcraft`。
3. 透過 Spotlight（`mdfind`）搜尋任何名為 `World of Warcraft` 的資料夾。

若沒有任何資料夾符合條件，腳本會以錯誤結束，並列出所有搜尋過的位置。

### 覆寫設定

| 變數      | 預設值      | 說明                                                                          |
| --------- | ----------- | ----------------------------------------------------------------------------- |
| `WOW_DIR` | 自動偵測    | `World of Warcraft` 資料夾，也就是包含 `_forever_` 的那層，而非 flavor 資料夾 |
| `FLAVOR`  | `_forever_` | `WOW_DIR` 內的用戶端 flavor 資料夾；設為 `_classic_beta_` 則指向 beta 用戶端  |
| `MODE`    | `link`      | 設為 `copy` 時改為複製 addon，而非建立連結                                    |

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

| 指令                                   | 作用                                                |
| -------------------------------------- | --------------------------------------------------- |
| `/tandem`                              | 印出指令列表；任何未知的子指令也一樣                |
| `/tandem check`                        | 逐項功能列出它需要的用戶端 API 是否存在             |
| `/tandem weights`                      | 顯示你的天賦系的屬性權重                            |
| `/tandem weights spec <1\|2\|3\|auto>` | 選擇權重所用的天賦系，或依天賦自動判斷              |
| `/tandem weights set <stat> <number>`  | 自訂目前天賦系某項屬性的權重；0 表示忽略            |
| `/tandem weights reset`                | 刪除目前天賦系的自訂權重                            |
| `/tandem layout`                       | 印出 Tandem 的[介面配置](#介面配置)是否開啟         |
| `/tandem layout <on\|off>`             | 開啟介面配置，或關閉並還原你先前的版面              |
| `/tandem minimap [on\|off]`            | 顯示或隱藏[小地圖按鈕](#小地圖按鈕)；不加參數則切換 |
| `/tandem debug [on\|off\|snap]`        | 為開發者記錄版面追蹤資料；見[除錯紀錄](#除錯紀錄)   |

戰鬥中執行 `check` 與 `weights` 時，只會印出 `Tandem: not available in combat`，不做任何事。`layout` 則會等到戰鬥
結束才執行；`minimap` 在戰鬥中也能使用。

### `/tandem check`

```text
Tandem API check:
Item tooltip: ok (TooltipDataProcessor.AddTooltipPostCall ok, Enum.TooltipDataType.Item ok)
Item stats: ok (C_Item.GetItemStats missing, GetItemStats ok)
...
Probe: LootButton1 present
Probe: LootFrame.ScrollBox missing
```

每項功能一行：它需要的 API 都找到時顯示 `ok`，後面列出每個 API 以及是否找到。兩個 API 擇一即可時，兩個都會列出，
找到其中一個就夠了。功能有 `Item tooltip`、`Quest reward pick`、`Upgrade alert`、`Item stats`、`Stat search`、
`Talent spec`、`Trainer record`、`Action bar borders`、`Upgrade borders`、`Layout`、`XP bar`、`Bag button` 與
`Shaman area`。缺少 API 的功能會保持關閉，而不會引發錯誤。`Upgrade borders` 需要 `Upgrade alert` 的 API 以及預設背包按鈕 `ContainerFrame1Item1` 或
`ContainerFrameCombinedBags`。物品屬性是從提示框讀取的，因此沒有 `Stat search` 時不會判斷任何物品。

接著是 `LootButton1`、`LootFrame.ScrollBox`、`LootFrame_Update`、`ContainerFrame1Item1.IconBorder`、
`ContainerFrame1Item1.NewItemTexture`、`ContainerFrame1Item1.UpgradeIcon`、`Enum.EditModeSystem.ChatFrame`、
`MainStatusTrackingBarContainer`、`BagsBar`、`C_UnitAuras.GetAuraDataBySpellName`、`UnitBuff`、
`Enum.EditModeSystem.MicroMenu`、`Enum.EditModeSystem.Minimap` 與 `Enum.EditModeSystem.AuraFrame` 各一行
`Probe: <path> present|missing`。它們顯示用戶端有哪些背包、拾取視窗、編輯模式與光環元件，不會開啟或關閉任何功能。

### `/tandem weights`

每個職業的三個天賦系各有一組內建的屬性權重。`/tandem weights` 顯示目前使用的權重：

```text
/tandem weights
Tandem: Arms Warrior weights, tree 1 (auto)
str 1, agi 0.6, sta 0.5, armor 0.01, dps 3, ap 0.5, hit 10, crit 10
```

第一行列出目前的天賦系與它在天賦頁中的編號，接著是 `auto`（依你的天賦判斷）或 `manual`（你自己選的）。`auto` 時
使用投入點數最多的天賦系；低於 10 級、尚未投入點數，或 [`/tandem check`](#tandem-check) 的 `Talent spec` 這行為
`missing` 時，使用該職業常見的練功天賦系（武器、懲戒、野獸控制、戰鬥、暗影、增強、冰霜、痛苦、野性戰鬥）。第二行
依下列順序，以屬性代碼列出每項有權重的屬性：
`str agi sta int spi armor dps ap rap sp heal hit crit spellhit spellcrit mp5 def dodge parry block blockvalue`。
`sp` 是法術傷害與治療，`heal` 只有治療，`dps` 是武器的每秒傷害；命中與致命一擊的權重以每 1% 計。

- `/tandem weights spec <1|2|3>` 選擇天賦系；`/tandem weights spec auto` 恢復依天賦判斷。會印出
  `Tandem: weights use tree <n>` 或 `Tandem: weights follow your talents`。
- `/tandem weights set <stat> <number>` 自訂目前天賦系某項屬性的權重，並印出 `Tandem: <stat> weight set to <number>`。
  `0` 表示忽略該屬性；天賦系原本沒有權重的屬性會被加入。數字可以帶正負號與小數點，例如 `-1` 或 `0.5`。自訂的權重
  標有 `*`，並接著一行 `* your own weight; /tandem weights reset drops them`。
- `/tandem weights reset` 刪除目前天賦系的自訂權重，並印出 `Tandem: own weights for tree <n> dropped`。其他天賦系的
  自訂權重保留。

每次變更後都會顯示目前的權重。你的選擇依角色（`Name-Realm`）與天賦系分別儲存，因此切換天賦後仍會保留。其他訊息：

- 其他任何輸入：`Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]`，不做任何變更。
- 不在上列的屬性代碼：`Tandem: unknown stat <stat>; use one of: <keys>`。
- 沒有內建權重的職業：`Tandem: no built-in weights for <class>`。
- 存檔資料使用較新的結構版本，或用戶端尚未提供你的名字與伺服器時：
  `Tandem: weights cannot be saved: recording is off or your character is not known yet`。

`zhTW` 用戶端的這些訊息與天賦系名稱會顯示為中文。

## 升級建議

### 什麼算升級

物品同時符合以下兩點才算升級：

- 你現在就能裝備它。它有對應的部位，而且：
  - 你的等級達到它的需求等級；
  - 依 Classic 的職業表，你的職業能使用它的護甲或武器類型。布甲與雜項物品所有職業都能使用。獵人與薩滿 40 級起
    可穿鎖甲，戰士與聖騎士 40 級起可穿鎧甲。薩滿的雙手斧與雙手錘需要天賦，因此絕不算數。釣魚竿也絕不算數。戰士與
    獵人 20 級起、盜賊 10 級起可以雙持，也只有他們能使用副手專用武器；
  - 它的提示框中沒有紅色的需求行，例如職業、尚未訓練的武器技能、種族、專業技能或聲望不符。
- 它勝過你在該部位穿戴的物品：屬性分數較高者勝；分數相同時，只有物品等級較高才算勝出。分數較低時，物品等級再高也
  不算。

屬性分數是物品上的每項屬性乘以你的職業與天賦樹對它的權重（見 [`/tandem weights`](#tandem-weights)）後加總。因此
即使物品等級較低，力量物品對戰士而言仍勝過法系物品。分數為 0（屬性全都不在你的權重中）的物品仍算有分數。

- 空部位的分數為 0、物品等級為 0，因此任何有屬性的可用物品都勝過它。
- 戒指與飾品與你穿戴的兩件中較弱的那件比較：分數較低者，分數相同時取物品等級較低者。可雙持的單手武器也以同樣方式
  與較弱的那隻手比較。
- 正在使用雙手武器時，副手物品絕不算升級。

所有資料都即時從用戶端讀取：物品等級、需求等級、部位與類型來自物品資訊，屬性來自提示框（需要
[`/tandem check`](#tandem-check) 的 `Stat search` 這行）。讀到的屬性只在本次登入期間保留，絕不儲存。用戶端尚未載入
的物品會向用戶端要求資料，送達時（`GET_ITEM_INFO_RECEIVED`）才判斷；在該物品與你身上裝備的屬性都得知之前，不會判斷
它。用戶端沒有提供你身上的裝備、你的職業或等級時，不會判斷任何物品。

### 升級提醒

當升級物品進入背包時（`BAG_UPDATE_DELAYED`，背包 0 到 4），聊天視窗會顯示一行：

```text
Tandem：胸部的升級：[Plate Chest]（分數 24.5，高於 18.0）
```

第二個分數是被它勝過的那件物品的分數。英文用戶端顯示為 `Tandem: upgrade for <slot>: <item link> (score <n> over <m>)`。

- 每件物品每次登入最多提醒一次，且只在它新進入背包時：登入時背包裡的物品會被靜默記下，在背包之間移動物品也不會提醒。
- 戰鬥中提醒會先保留，戰鬥結束時（`PLAYER_REGEN_ENABLED`）才印出；戰鬥中不會印出任何訊息。
- 提醒只是建議：Tandem 絕不會替你裝備任何東西。
- [`/tandem check`](#tandem-check) 的 `Upgrade alert` 這行為 `missing` 時，不會有任何動作。

### 升級邊框

背包或拾取視窗中的升級物品，其按鈕會有紅色邊框，左上角還有綠色向上箭頭。

- 只有預設 Blizzard 背包按鈕（分開或合併的背包）與預設拾取視窗的按鈕會有邊框。Bagnon、AdiBags 等背包 addon，以及
  從不顯示拾取視窗的自動拾取，都不經過這些視窗，因此不會畫出邊框；聊天視窗的[升級提醒](#升級提醒)仍會告訴你。
- 開啟背包或拾取視窗時、背包、裝備、技能或等級改變時，以及用戶端載入物品資料時，邊框都會更新。戰鬥中也一樣。
- 屬性或需求尚未得知的物品，在得知之前不會有邊框。
- 邊框只是建議：Tandem 絕不會替你裝備或拾取任何東西，也不會改變按鈕的作用。
- [`/tandem check`](#tandem-check) 的 `Upgrade borders` 這行為 `missing` 時，不會畫出任何邊框。

### 物品提示框

在戰鬥外，滑鼠移到升級物品上時，遊戲提示框底部會多一行綠字：

```text
Tandem：比身上裝備更好（分數 24.5，高於 18.0）
```

英文用戶端顯示為 `Tandem: upgrade over what you wear (score <score> over <worn score>)`。凡是物品提示框為遊戲主提示框
的地方都適用，例如背包、拾取視窗與任務獎勵，以及在聊天視窗點擊物品連結時開啟的提示框。顯示身上裝備的比較提示框
不受影響。其他物品不會多出任何一行，戰鬥中也不會加上。

### 任務獎勵建議

交回可以從兩件以上獎勵中選擇一件的任務時（`QUEST_COMPLETE`），Tandem 會在最佳選擇的按鈕右上角放一個小小的 Tandem
圖示。最佳選擇是你能裝備（同[什麼算升級](#什麼算升級)）、且勝過其他每一件這類選擇的那一件：

- 每件可用選擇都有屬性時，比屬性分數；分數相同時比物品等級，再比品質；
- 任何一件可用選擇沒有屬性時，比物品等級，再比品質。

它不會與你身上的裝備比較：滑鼠移到該選擇上，可在[物品提示框](#物品提示框)看到它是否算升級。

- 可用選擇仍然並列最佳、沒有任何可用選擇，或任務只提供一件選擇時，不會顯示圖示。
- 用戶端尚未載入的選擇會向用戶端要求資料；所有選擇都送達後，只要獎勵視窗仍開著，就會顯示圖示。
- 圖示只是建議：Tandem 絕不會替你選擇獎勵，仍要由你點選想要的那一件。
- 獎勵視窗關閉時（`QUEST_FINISHED`）圖示會消失。
- 戰鬥中、用戶端沒有提供你的職業或等級時，或 [`/tandem check`](#tandem-check) 的 `Quest reward pick` 這行為
  `missing` 時，都不會有任何動作，也不會印出任何訊息。

## 快捷列邊框

預設快捷列上的法術，等級過時時按鈕會加上彩色邊框：

- **紅色**：按鈕放的是較低等級，而你已學會同一法術更高的等級。從法術書把較高等級拖到快捷列上。
- **黃色**：有比你已學會的更高等級，在你目前等級或以下就能學，而你還沒學。去找你的職業訓練師。

兩者都符合時顯示紅色。巨集、物品、空格與沒有等級的法術不加邊框。

- 黃色需要知道你的職業訓練師教什麼：開啟職業訓練師視窗時 Tandem 會記錄下來（見[存檔資料](#存檔資料)）。在你開啟過
  你職業的訓練師之前，只會顯示紅色邊框。
- 只有 Blizzard 預設快捷列會加邊框：主快捷列、左下與右下、右側快捷列，以及用戶端有的話，快捷列 5 到 7。其他插件的
  快捷列不會。
- 在戰鬥外，邊框會隨快捷列、頁面、法術、等級與訓練師的變化更新。戰鬥中邊框維持原樣，戰鬥結束後才更新。
- [`/tandem check`](#tandem-check) 的 `Action bar borders` 這行為 `missing` 時不會畫任何邊框。Tandem 只在按鈕上
  畫框，從不改變按鈕施放的內容。

## 介面配置

```text
/tandem layout on
Tandem: layout on
```

`/tandem layout on` 會以快捷列為中心重新排列畫面，使用帳號共用的編輯模式版面 `Tandem`（不存在時建立，存在時更新）。
介面配置預設關閉，要你自己開啟。`/tandem layout off` 會還原你先前使用的版面，並印出
`Tandem: layout off; your previous layout is back`；若那個版面已被刪除或改名，則改用第一個預設版面。只輸入
`/tandem layout` 會印出 `Tandem: layout on` 或 `Tandem: layout off`。

- 在編輯模式中切換到其他版面，會像 `off` 一樣關閉 Tandem 的介面配置，但保留你選的版面。
- 戰鬥中的變更會等待：聊天視窗顯示 `Tandem: the layout will change after combat`，戰鬥結束時才變更。
- 帳號版面已滿時，`on` 會印出 `Tandem: no free account layout slot; delete one in Edit Mode`。
- 沒有編輯模式，或 [`/tandem check`](#tandem-check) 的 `Layout` 這行為 `missing` 時，`on` 會印出
  `Tandem: the layout needs Edit Mode, which this client lacks`，什麼都不會移動。

### 小地圖按鈕

小地圖邊緣的 Tandem 圖示，點擊即可開啟或關閉介面配置，並印出與 `/tandem layout on` 或 `off` 相同的訊息；戰鬥中的
變更同樣會等待。滑鼠提示會顯示介面配置是否開啟。沿著小地圖拖曳即可移動它，位置會被儲存。`/tandem minimap off`
隱藏它，`/tandem minimap on` 再次顯示，只輸入 `/tandem minimap` 則切換，並印出 `Tandem: minimap button hidden` 或
`Tandem: minimap button shown`。插件收納選單中的 Tandem 項目與點擊按鈕的作用相同。

在繁體中文（`zhTW`）用戶端上，這些訊息會以中文顯示。

### 移動了什麼

```text
┌──────────────────────────────────────────────────────────────────┐
│                        [====|====| XP 62% |====]  [增益][小地圖] │
│                                                                  │
│      [玩家]              [職業區]              [目標][ToT]       │
│                                                                  │
│                      [ 薩滿圖騰列       ]                        │
│ [聊天]               [ 主快捷列         ]                        │
│ [聊天]               [ 快捷列 2         ]           [背包圖示列] │
│ [聊天]               [ 快捷列 3         ]             [微型選單] │
└──────────────────────────────────────────────────────────────────┘
```

- 下方三條快捷列疊在畫面底部中央，每條一排 12 個按鈕，主快捷列在最上面，不顯示獅鷲裝飾。薩滿的圖騰列在主快捷列
  正上方保有自己的一排，也就是 Blizzard 放它的位置。
- 玩家頭像與目標頭像在快捷列上方較高處排成一列，分在中央左右兩側，[職業區](#薩滿職業區)在兩者之間。並會在目標
  頭像旁顯示目標的目標。
- [經驗條](#經驗條)位於畫面頂端中央。
- 用戶端的編輯模式有聊天系統時，聊天視窗移到左下角，大小約 380 × 120；編輯模式沒有聊天視窗大小設定時只移動位置；
  沒有聊天系統時維持原位。螢幕較窄時，聊天視窗會縮窄到快捷列左側剩下的空間（最窄 260），再不夠就移到玩家頭像上方。
- 微型選單移到右下角，[背包圖示列](#背包圖示列)緊接在它上方。任務追蹤與 Blizzard 的傷害統計維持你先前版面中的位置。
- 小地圖移到右上角，增益效果緊貼在它左側。
- 微型選單、小地圖與增益效果只在用戶端的編輯模式有對應系統時移動（增益效果還需要小地圖的系統）；否則維持原位。
- 右側快捷列與第 5 到 7 條快捷列會隱藏。

關閉介面配置時，目標的目標設定與 Tandem 隱藏的每個框架都會還原。Tandem 自己的框架只負責顯示，戰鬥中也會更新。

### 經驗條

畫面頂端中央有一條寬度為螢幕一半的經驗條，上面顯示百分比，例如 `42%`，並像經典版經驗條一樣以細線分成十格。滑鼠
移上去會顯示目前值 / 最大值與休息加成：

```text
4200 / 9800 (42%)
休息 +15%
```

有休息經驗時是藍色，沒有時是紫色。到達最高等級時會隱藏。它取代預設的狀態列（兩條都是），所以介面配置開啟時，追蹤中的聲望條也會
一起隱藏。它需要 [`/tandem check`](#tandem-check) 的 `XP bar` 這行。

### 背包圖示列

右下角有一排圖示，每個圖示下緣顯示剩餘 / 總格數：最右邊是一般背包，左邊每種專業背包類型各一個圖示，使用該背包的
圖示，例如草藥袋或靈魂碎片袋。剩餘少於 10 格時數字變黃，滿了變紅。滑鼠移到圖示上會列出那些背包的名稱與剩餘 /
總格數；點擊任一圖示會開啟所有背包。介面配置開啟時它取代預設的背包列，需要 [`/tandem check`](#tandem-check) 的
`Bag button` 這行。

每次登入時，不論介面配置是否開啟，Tandem 都會開啟用戶端的整合背包（`combinedBags` 設定），讓 `B` 以單一視窗開啟所有
背包。你可以在選項中關閉它；下次登入時會再度開啟。Tandem 也會把所有綁定「開啟所有背包」或「開啟背包」的按鍵（`B` 是其中之一）
指向自己的開啟按鈕，讓材料包與其他背包一起開關；材料包有格子時，背包圖示列最左側會多一個標題為 `材料包` 的圖示，
點擊任一圖示也會一併開啟它。

### 薩滿職業區

薩滿在玩家與目標頭像之間會有一排置中的圖示，每項一個：

- 每個已放下的圖騰，依大地、火焰、水、空氣的順序，附剩餘時間；
- 閃電之盾（用戶端有水之盾時也包括水之盾），右下角顯示層數，並附剩餘時間。

剩餘時間超過一分鐘時顯示 `m:ss`，否則顯示秒數，並持續倒數；時間到時圖示就會消失。滑鼠移到圖示上會顯示它的名稱
（圖騰或護盾的名稱）與剩餘時間。有圖示時，這排圖示底部有一條細的藍色法力線；沒有任何
圖示時，整排連同法力線一起隱藏。

它只顯示狀態與計時：裡面沒有任何可點擊的東西，也絕不建議你該施放什麼。其他職業沒有這排圖示。它需要
[`/tandem check`](#tandem-check) 的 `Shaman area` 這行。

介面配置、經驗條、背包圖示列與薩滿職業區各自在 `/tandem check` 那一行為 `missing` 時保持關閉，其他部分照常運作。

### 除錯紀錄

`/tandem debug on` 開始為開發者記錄：每次開啟背包時的判斷，以及畫面下方框架與 Blizzard
狀態列的快照（登入 2 秒後、每次切換介面配置時，以及執行 `/tandem debug snap` 時）。記錄時不會印出任何訊息。紀錄最多
300 行，在你 `/reload` 或登出時存進 `TandemDebug` 存檔變數。`/tandem debug off` 停止記錄並印出保留的行數；
`/tandem debug` 不加參數則切換開關；`snap` 會在需要時開啟記錄並拍一次快照。

## 存檔資料

Tandem 只儲存一個帳號共用的表 `TandemDB`，存檔位置為
`<World of Warcraft>/_forever_/WTF/Account/<account>/SavedVariables/Tandem.lua`。

| Key        | 內容                                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------------- |
| `weights`  | 每個角色（`Name-Realm`）：選定的 `spec`（1-3，不存在表示自動），以及各天賦的屬性權重 `overrides`        |
| `trainers` | 每個職業（`MAGE`）：職業訓練師教授的每個法術 ID，需求等級 `level` 與法術等級 `rank`（沒有時不存在）     |
| `layout`   | [介面配置](#介面配置)是否開啟 `on`、先前版面 `previous`、原本的目標的目標設定、`minimap` 按鈕位置與隱藏 |

- 每次在戰鬥外開啟或更新職業訓練師視窗時，都會以你角色的職業記錄它的法術：列出的每個法術（不論是否已學會）、需求
  等級，以及法術等級文字中的數字（`等級 3` 記為 `3`）。分類標題、專業技能訓練師，以及用戶端沒有提供法術 ID 的法術會
  略過；[`/tandem check`](#tandem-check) 的 `Trainer record` 這行為 `missing` 時不會記錄。再次看到同一個法術時保留
  較低的等級。
- 載入時，無效的 `spec`、override、屬性鍵或數值會單獨捨棄，無效的 `trainers` 法術 ID 或項目也是；角色的項目若不是表、
  職業鍵不是職業代號，或職業的法術不是表，則會整個捨棄。

`TandemDB.schemaVersion` 為 `7`。較舊 schema 的存檔資料會在載入時遷移：保留 `weights`、`trainers` 與 `layout`，
其他所有鍵（例如舊版的物品快取、掉落紀錄與屬性）都會捨棄。聊天視窗接著顯示
`Tandem：存檔資料已從結構版本 <n> 升級到 7` 與 `Tandem：已捨棄 <n> 筆無效或不再使用的存檔資料`；schema 6 的資料在
沒有捨棄任何項目時會靜默升級。較新 schema 的存檔資料會原樣保留，在 addon 更新之前不會儲存任何資料。

同一個檔案也存放 `TandemDebug`，即[除錯紀錄](#除錯紀錄)：`on` 與最多 300 行 `log`，只在你開啟後才有。

用戶端只在登出或 `/reload` 時寫入 `Tandem.lua`。

## 在遊戲中驗證

1. 啟動用戶端。在角色選擇畫面開啟 **AddOns**，確認 **Tandem** 有列出且已啟用。
2. 進入遊戲世界。聊天視窗會顯示：

   ```text
   Tandem loaded
   ```

   在繁體中文（`zhTW`）用戶端上，這行會顯示為 `Tandem 已載入`，AddOns 清單中的說明也會是中文。其他語言的用戶端則一律
   顯示英文。

若沒有出現這行訊息，請確認 addon 已啟用，且沒有回報任何 Lua 錯誤。

### 檢查用戶端 API

物品提示框、任務獎勵建議、升級提醒與升級邊框，以及快捷列邊框，都使用尚未在 Forever 上驗證的 API。執行一次
`/tandem check` 就能知道用戶端有哪些：

1. 在戰鬥外執行 `/tandem check`。聊天視窗顯示 `Tandem API check:` 與十三行，分別是 `Item tooltip`、
   `Quest reward pick`、`Upgrade alert`、`Item stats`、`Stat search`、`Talent spec`、`Trainer record`、
   `Action bar borders`、`Upgrade borders`、`Layout`、`XP bar`、`Bag button` 與 `Shaman area`，每行後面接著 `ok`
   或 `missing` 以及它的 API。之後是十四行 `Probe:`，各為 `present` 或 `missing`。
2. 交一個可以選擇獎勵的任務，在獎勵視窗開著時再執行一次 `/tandem check`。記下 `Quest reward pick` 這行現在是否找到
   `QuestInfoRewardsFrame.RewardButtons`、`QuestInfoRewardsFrameQuestInfoItem1` 或 `QuestRewardItem1`：獎勵按鈕
   可能要等視窗顯示過一次才會存在。
3. 開始戰鬥，在戰鬥中執行 `/tandem check`：只印出 `Tandem: not available in combat`。
4. 若步驟 2 中 `Quest reward pick` 為 `ok`，請進行[檢查任務獎勵建議](#檢查任務獎勵建議)。若 `Upgrade alert` 為
   `ok`，請進行[檢查升級提醒](#檢查升級提醒)。若 `Talent spec` 為 `ok`，在 10 級以上的角色執行 `/tandem weights`：
   第一行列出投入點數最多的天賦系，後面接著 `(auto)`。若 `Action bar borders` 為 `ok`，請進行
   [檢查快捷列邊框](#檢查快捷列邊框)。若 `Upgrade borders` 為 `ok`，請進行[檢查升級邊框](#檢查升級邊框)。若
   `Layout` 為 `ok`，請進行[檢查介面配置](#檢查介面配置)。

請回報步驟 1 與 2 印出的每一行（包括 `Probe:` 行）、步驟 4 中 `/tandem weights` 的第一行，以及任何 Lua 錯誤。

### 檢查任務獎勵建議

1. 在戰鬥外，交回一個提供兩件以上獎勵可選、且至少一件是你的職業可用的任務。獎勵視窗中，其中一件選擇的按鈕右上角
   有一個小小的 Tandem 圖示。聊天視窗不會印出任何訊息，也不會選取任何獎勵。
2. 記下你可用的每件選擇的屬性、物品等級與品質：有標記的那件依你的權重分數最高，分數相同時物品等級較高；有可用選擇
   沒有屬性時，則是物品等級最高、再比品質較好的那件。
3. 不選擇就關閉獎勵視窗，再與任務發布者對話一次：圖示再次出現在同一件選擇上。
4. 對可用選擇並列最佳、或沒有任何你的職業可用選擇的任務：不會顯示圖示。
5. 若可以，在戰鬥中開啟獎勵視窗：不會顯示圖示，也不會印出任何訊息。

請回報任務、各選擇的屬性、物品等級與品質、被標記的是哪一件、圖示在按鈕上的位置是否恰當或遮住了按鈕的一部分，以及任何
Lua 錯誤。

### 檢查升級提醒

1. 背包裡放著一些裝備時登入或執行 `/reload`：不會出現 `Tandem：…的升級` 這行。
2. 在戰鬥外，拾取、購買或從信箱取出一件你的職業可用、且提示框顯示 `Tandem：比身上裝備更好` 的物品（或空部位的任何
   有屬性的可用物品）。聊天視窗顯示一行，且不會裝備任何東西：`Tandem：<部位>的升級：<物品連結>（分數 <n>，高於 <m>）`。
3. 把該物品移到另一個背包、賣掉再買回，或丟棄後再拾取：本次登入不會再提醒它。
4. 取得一件你無法使用的物品、提示框中有紅色行的物品（例如尚未訓練的武器類型）、物品等級較高但分數較低的物品，或
   不比身上裝備好的物品：不會提醒。
5. 取得一件分數與身上裝備相同、但物品等級較高的物品：會提醒。
6. 在戰鬥中拾取一件升級：戰鬥中不會顯示；戰鬥結束時才顯示那一行。
7. 若可以，拾取一件用戶端從未顯示過的升級（新的掉落）：那一行可能在物品載入後稍晚才出現。

請回報印出的每一行與當時身上裝備的分數、沒有提醒的升級或提醒了不是升級的物品，以及任何 Lua 錯誤。

### 檢查快捷列邊框

1. 在戰鬥外，把一個你已學會更高等級的法術的較低等級放到主快捷列（勾選 `顯示所有法術等級` 後從法術書拖曳，或從它的
   等級清單選取）。它的按鈕出現紅色邊框；同一法術的最高等級沒有邊框。快捷列上的巨集或物品沒有邊框。
2. 把同一個較低等級放到左下快捷列與一條右側快捷列：這些按鈕也是紅色。若開啟了快捷列 5 到 7，也在那裡試一次。
3. 把紅色按鈕換成最高等級：邊框立刻消失。
4. 用一個職業訓練師有你目前等級可學新等級的角色，開啟訓練師視窗再關閉，看快捷列上該法術已學會的最高等級：邊框是
   黃色。學會這個等級：舊按鈕變成紅色。
5. 切換快捷列頁面（Shift 加滑鼠滾輪，或主快捷列旁的箭頭）：邊框跟著新頁面上的法術變化。
6. 開始戰鬥，在戰鬥中把紅色按鈕換成最高等級：邊框維持紅色。戰鬥結束後消失。

請回報任何無故變紅或變黃、或應該變色卻沒有的按鈕，完全沒有邊框的快捷列，以及任何 Lua 錯誤。

### 檢查升級邊框

1. 使用預設背包，在背包裡有一件[升級提醒](#升級提醒)會提醒的物品時開啟背包：它的按鈕有紅色邊框與綠色向上箭頭，提示框
   也有那行綠色的 Tandem 文字。不比身上裝備好的物品、你無法使用的物品，以及提示框中有紅色行的物品都沒有邊框。
2. 裝備有邊框的物品：它的邊框消失，換下來的物品也沒有邊框。
3. 關閉自動拾取，拾取一具掉落升級物品的屍體：拾取視窗中該物品的按鈕有邊框與箭頭。翻閱超過一頁的拾取視窗：邊框跟著
   物品，而不是跟著按鈕。
4. 升級，或在訓練師學會背包中某件武器的武器技能：它的邊框隨之出現或消失。
5. 開始戰鬥，拾取一件升級物品或在背包中移動它：邊框仍會顯示。
6. 使用 Bagnon 或 AdiBags 等背包 addon，或開啟自動拾取時：不會顯示邊框；聊天視窗的提醒仍會出現。

請回報 `/tandem check` 的 `Upgrade borders` 與 `Probe:` 行、任何有邊框卻不是升級或是升級卻沒有邊框的物品、邊框在
按鈕上的位置是否恰當，以及任何 Lua 錯誤。

### 檢查介面配置

1. 在戰鬥外執行 `/tandem layout on`。聊天視窗顯示 `Tandem: layout on`。下方三條快捷列位於底部中央且沒有獅鷲，玩家
   與目標頭像在其上方排成一列，聊天視窗在左下角，微型選單在右下角、背包圖示列在它上方，小地圖在右上角、增益效果在它
   左側（用戶端允許編輯模式移動它們時）；右側快捷列與背包列消失。選取一個目標：會顯示目標的目標。
2. 畫面頂端中央的經驗條寬度為螢幕一半、分成十格，顯示百分比，紫色，有休息經驗時為藍色。畫面上只有一條經驗條。滑鼠移上去：`<目前值> / <最大值> (<n>%)`，有休息
   經驗時還有 `休息 +<n>%`。殺一隻怪：經驗條會前進。
3. 右下角的背包圖示列在背包圖示上顯示一般背包的剩餘 / 總格數，左邊每種專業背包各一個圖示。點擊任一圖示：所有背包
   都會開啟。拾取一件
   物品：剩餘格數減一。
4. 薩滿的圖騰列在主快捷列正上方自成一排，戰鬥中施法後也不會移動；頭像之間一開始什麼都沒有。放下一個圖騰並施放
   閃電之盾：玩家與目標頭像之間各出現一個圖示，
   顯示倒數中的剩餘時間，護盾另顯示層數，下方有一條細的藍色法力線。滑鼠移到圖示上：顯示它的名稱。時間到時圖示
   消失；最後一個消失時，整排連同法力線一起消失。點擊這排圖示不會有任何反應。
5. 執行 `/reload`：一切都還在原位。
6. 開始戰鬥並執行 `/tandem layout off`：聊天視窗顯示 `Tandem: the layout will change after combat`。戰鬥結束時恢復
   你先前的版面，快捷列、背包列、狀態列與目標的目標設定都和之前一樣。
7. 再次開啟介面配置，打開編輯模式並選擇另一個版面：Tandem 的經驗條、背包圖示列與職業區都會消失。

請回報 `/tandem check` 的 `Layout`、`XP bar`、`Bag button`、`Shaman area` 與 `Probe:` 行、任何位置錯誤或與其他框架
重疊的框架、`off` 之後沒有還原的東西，以及任何 Lua 錯誤。

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
`scripts/wow-dir_test.sh`。本機的 `luac` 版本比遊戲使用的 Lua 5.1 新，因此只能抓出語法錯誤。

`scripts/addon_test.lua` 會模擬 WoW API 函式，依 `Tandem/Tandem.toc` 列出的順序載入檔案，並檢查 `enUS`、`zhTW`
與一個不支援的語系下的載入訊息。它也測試 `TandemDB` 的驗證與遷移、`/tandem` 的解析與輸出、屬性權重、從提示框讀取
屬性、訓練師紀錄、以模擬的職業、等級、已穿戴與背包物品進行的升級判斷、升級提醒與邊框、任務獎勵建議、快捷列邊框，
物品提示框的那一行、介面配置、經驗條、背包圖示列與薩滿職業區。這些測試只能證明邏輯正確；用戶端實際的 API 要在遊戲中檢查。

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
