# Tandem

> 與你的 WoW 玩家協作

[English](README.md) | 繁體中文

Tandem 是一個 World of Warcraft addon。目前它只是一個空殼：載入時會在聊天視窗印出一行訊息。

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

## 在遊戲中驗證

1. 啟動用戶端。在角色選擇畫面開啟 **AddOns**，確認 **Tandem** 有列出且已啟用。
2. 進入遊戲世界。聊天視窗會顯示：

   ```text
   Tandem loaded
   ```

   在繁體中文（`zhTW`）用戶端上，這行會顯示為 `Tandem 已載入`，AddOns 清單中的說明也會是中文。其他語言的用戶端則一律
   顯示英文。

若沒有出現這行訊息，請確認 addon 已啟用，且沒有回報任何 Lua 錯誤。

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
與一個不支援的語系下的載入訊息。

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
