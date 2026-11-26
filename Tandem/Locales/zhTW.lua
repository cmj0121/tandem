local _, ns = ...

if GetLocale() ~= "zhTW" then
    return
end

local L = ns.L

L["%s loaded"] = "%s 已載入"
L["%s: saved data uses newer schema %d; recording is off until the addon is updated"] =
    "%s：存檔資料使用較新的結構版本 %d；在更新插件前暫停記錄"
L["%s: saved data was unreadable and has been reset"] = "%s：存檔資料無法讀取，已重設"
L["%s: saved data upgraded from schema %d to %d"] = "%s：存檔資料已從結構版本 %d 升級到 %d"
L["%s: dropped %d invalid or unused saved entries"] = "%s：已捨棄 %d 筆無效或不再使用的存檔資料"

L["Tandem commands:"] = "Tandem 指令："
L["none"] = "無"

L["  /tandem check - list the client APIs each feature needs"] = "  /tandem check - 列出各功能需要的用戶端 API"
L["Tandem API check:"] = "Tandem API 檢查："
L["%s: %s (%s)"] = "%s：%s（%s）"
L["ok"] = "可用"
L["missing"] = "缺少"
L["Item tooltip"] = "物品提示框"
L["Quest reward pick"] = "任務獎勵建議"
L["Upgrade alert"] = "升級提醒"
L["Item stats"] = "物品屬性"
L["Stat search"] = "屬性搜尋"
L["Talent spec"] = "天賦專精"
L["Trainer record"] = "訓練師紀錄"
L["Action bar borders"] = "快捷列邊框"
L["Upgrade borders"] = "升級邊框"
L["Layout"] = "介面配置"
L["XP bar"] = "經驗條"
L["Bag button"] = "背包按鈕"
L["Fishing rod"] = "魚竿"
L["Fishing macro"] = "釣魚巨集"
L["Map info"] = "地圖資訊"
L["Book pins"] = "圖書館書籍地圖標記"
L["Book alert"] = "圖書館書籍提醒"
L["Mute button"] = "靜音按鈕"
L["Sound"] = "聲音"
L["Sound on"] = "聲音開啟"
L["Sound off"] = "聲音關閉"
L["Click to mute"] = "點擊靜音"
L["Click to unmute"] = "點擊取消靜音"
L["Role button"] = "切換按鈕"
L["Layout mode"] = "版面模式"
L["Damage"] = "輸出"
L["Healer"] = "治療"
L["Click for the healer layout"] = "點擊切換為治療版面"
L["Click for the damage layout"] = "點擊切換為輸出版面"
L["Tandem: healer layout"] = "Tandem：治療版面"
L["Tandem: damage layout"] = "Tandem：輸出版面"
L["Eat button"] = "飲食按鈕"
L["Eat and drink"] = "吃喝"
L["Left-click: eat %s"] = "左鍵：吃 %s"
L["Right-click: drink %s"] = "右鍵：喝 %s"
L["Eating…"] = "進食中…"
L["Drinking…"] = "喝水中…"
L["Class macro button"] = "職業巨集按鈕"
L["Class macros"] = "職業巨集"
L["Cure macro"] = "驅散巨集"
L["Craft button"] = "製造按鈕"
L["Cast an item-making spell or open a profession once to fill this list"] = "施放一次製造物品的法術或打開一次專業技能，就會填入這個清單"
L["Makes %s"] = "製造 %s"
L["The first click opens the profession; the next one makes it"] = "第一次點擊會打開專業技能，再點一次才會製造"
L["Left click: make"] = "左鍵：製造"
L["Right click: use"] = "右鍵：使用"
L["Click to choose what the button makes"] = "點擊選擇按鈕要製造的物品"
L["Poison"] = "中毒"
L["Disease"] = "疾病"
L["No one in your party has a %s effect"] = "你和隊友身上都沒有%s效果"
L["Party debuffs show again after combat"] = "戰鬥結束後才會再顯示隊伍的減益效果"
L["Drag to place this macro on your action bar"] = "拖曳即可把這個巨集放到快捷列"
L["Drag out of combat to place this macro"] = "離開戰鬥後才能拖曳放置這個巨集"
L["Character macros full: no room for this macro"] = "角色巨集已滿：沒有空間放這個巨集"
L["Click to choose the button's macro"] = "點擊選擇按鈕要用的巨集"
L["Choosing waits until combat ends"] = "要等戰鬥結束才能選擇"
L["Left-click cures poison, right-click cures disease"] = "左鍵解除中毒，右鍵解除疾病"
L["Left-click casts Call of the Elements, right-click casts Call of the Ancestors"] = "左鍵施放元素召喚，右鍵施放先祖召喚"
L["Left-click or your key casts Lesser Healing Wave, right-click or Shift with your key casts Healing Wave"] =
    "左鍵或按鍵施放次級治療波，右鍵或 Shift+按鍵施放治療波"
L["Switches to the nearest enemy when your target is missing, dead or friendly (it may be one not yet fighting), "
    .. "starts attacking and casts Stormstrike"] =
    "目標不存在、已死亡或為友方時自動切換到最近的敵人（可能是還沒開打的怪），開始攻擊並施放風暴打擊"
L["Left-click casts Astral Recall, or uses your Hearthstone while it is on cooldown; right-click uses your "
    .. "Hearthstone; in combat both use your Hearthstone"] =
    "左鍵施放星界傳送，冷卻中則使用爐石；右鍵使用爐石；戰鬥中兩鍵都使用爐石"
L["No Hearthstone in your bags"] = "背包裡沒有爐石"
L["%dd %dh"] = "%d天 %d時"
L["%dh %dm"] = "%d時 %d分"
L["%dm"] = "%d分"
L["Played: %s"] = "遊玩時間：%s"
L["This level: %s"] = "本等級：%s"
L["This session: %s"] = "本次上線：%s"
L["Weapon procs"] = "武器觸發"
L["  /tandem layout [on|off] - arrange bars, unit frames and chat for Tandem, or restore your layout"] =
    "  /tandem layout [on|off] - 為 Tandem 排列快捷列、頭像框與聊天框，或還原你的版面"
L["Tandem: layout on"] = "Tandem：介面配置已開啟"
L["Tandem: layout off"] = "Tandem：介面配置已關閉"
L["Tandem: layout off; your previous layout is back"] = "Tandem：介面配置已關閉；已還原你先前的版面"
L["Tandem: the layout needs Edit Mode, which this client lacks"] = "Tandem：介面配置需要編輯模式，但此用戶端沒有"
L["Tandem: the layout cannot be saved: saved data uses a newer schema"] =
    "Tandem：無法儲存介面配置：存檔資料使用較新的結構版本"
L["Tandem: the layout will change after combat"] = "Tandem：介面配置將在戰鬥結束後變更"
L["Tandem: no free account layout slot; delete one in Edit Mode"] = "Tandem：沒有空的帳號版面欄位；請在編輯模式中刪除一個"
L["Tandem: the layout could not be changed"] = "Tandem：無法變更介面配置"
L["  /tandem minimap [on|off] - show or hide the minimap button"] = "  /tandem minimap [on|off] - 顯示或隱藏小地圖按鈕"
L["  /tandem books [on|off|near] - show library book pins on the world map, or name the nearest book"] =
    "  /tandem books [on|off|near] - 在世界地圖上標記圖書館書籍，或列出最近的一本"
L["Tandem: minimap button shown"] = "Tandem：已顯示小地圖按鈕"
L["  /tandem debug [on|off|snap] - record layout traces for the developer; /reload saves them"] =
    "  /tandem debug [on|off|snap] - 為開發者記錄版面追蹤資料；/reload 後寫入存檔"
L["Tandem: debug recording on; /reload saves it to disk"] = "Tandem：開始除錯記錄；/reload 後寫入存檔"
L["Tandem: debug recording off (%d lines kept)"] = "Tandem：停止除錯記錄（保留 %d 行）"
L["Tandem: minimap button hidden"] = "Tandem：已隱藏小地圖按鈕"
L["Layout: on"] = "介面配置：開啟"
L["Layout: off"] = "介面配置：關閉"
L["Click to turn the layout on/off"] = "點擊以開啟或關閉介面配置"
L["Drag to move this button"] = "拖曳以移動此按鈕"
L["General bags"] = "一般背包"
L["%d/%d free"] = "剩餘 %d/%d"
L["Profession bag"] = "專業背包"
L["Reagent bag"] = "材料包"
L["Click to open your bags"] = "點擊開啟背包"
L["Bags"] = "背包"
L["%s: %d/%d free"] = "%s：剩餘 %d/%d"
L["Reload UI"] = "重新載入介面"
L["Click to reload the interface"] = "點擊重新載入介面"
L["Procs %d / hits %d (%s)"] = "觸發 %d / 命中 %d（%s）"
L["Miss %d / dodge %d / parry %d / block %d"] = "未命中 %d / 閃躲 %d / 招架 %d / 格擋 %d"
L["Counted from your melee hits on your target; exact when solo"] = "依你對目標的近戰命中計算；單人時才準確"
L["Right-click to start counting again"] = "右鍵重新計算"
L["Equip %s"] = "裝備 %s"
L["Put back %s"] = "換回 %s"
L["Equip your weapon"] = "請裝備你的武器"
L["Bags full: no room for your off hand"] = "背包已滿：沒有空間放副手"
L["Click to equip your fishing rod"] = "點擊裝備魚竿"
L["Click to put your weapons back"] = "點擊換回武器"
L["In combat the button runs the swap it showed before combat"] = "戰鬥中，按鈕執行的是戰鬥前顯示的切換"
L["Drag to place the fishing macro on your action bar"] = "拖曳即可把釣魚巨集放到快捷列"
L["Character macros full: no room for the fishing macro"] = "角色巨集已滿：沒有空間放釣魚巨集"
L["Rested +%d%%"] = "休息 +%d%%"
L["Probe: %s %s"] = "探測：%s %s"
L["present"] = "存在"
L["Tandem: upgrade for %s: %s (score %s over %s)"] = "Tandem：%s的升級：%s（分數 %s，高於 %s）"
L["Tandem: upgrade over what you wear (score %s over %s)"] = "Tandem：比身上裝備更好（分數 %s，高於 %s）"
L["Tandem: cooking recipes that use this"] = "Tandem：使用此材料的食譜"
L["%s: %s"] = "%s：%s"
L[", "] = "、"
L["item %d"] = "物品 %d"
L["... and %d more"] = "……還有 %d 個"
L["  /tandem weights - show the stat weights of your talent tree"] = "  /tandem weights - 顯示你的天賦系的屬性權重"
L["  /tandem weights spec <1|2|3|auto> - pick the talent tree, or follow your talents"] =
    "  /tandem weights spec <1|2|3|auto> - 選擇天賦系，或依你的天賦自動判斷"
L["  /tandem weights set <stat> <number> - set your own weight for a stat (0 ignores it)"] =
    "  /tandem weights set <屬性> <數字> - 自訂某項屬性的權重（0 表示忽略）"
L["  /tandem weights reset - drop your own weights for the active tree"] =
    "  /tandem weights reset - 刪除目前天賦系的自訂權重"
L["Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]"] =
    "Tandem：用法 /tandem weights [spec <1|2|3|auto> | set <屬性> <數字> | reset]"
L["Tandem: %s %s weights, tree %d (%s)"] = "Tandem：%s%s的屬性權重，第 %d 系（%s）"
L["auto"] = "自動"
L["manual"] = "手動"
L["  * your own weight; /tandem weights reset drops them"] = "  * 你自訂的權重；/tandem weights reset 可刪除"
L["Tandem: no built-in weights for %s"] = "Tandem：%s沒有內建權重"
L["Tandem: weights follow your talents"] = "Tandem：權重依你的天賦自動判斷"
L["Tandem: weights use tree %d"] = "Tandem：權重使用第 %d 系"
L["Tandem: unknown stat %s; use one of: %s"] = "Tandem：未知的屬性 %s；請使用其中之一：%s"
L["Tandem: %s weight set to %s"] = "Tandem：%s 的權重設為 %s"
L["Tandem: own weights for tree %d dropped"] = "Tandem：已刪除第 %d 系的自訂權重"
L["Tandem: weights cannot be saved: recording is off or your character is not known yet"] =
    "Tandem：無法儲存權重：記錄已停用，或尚未取得你的角色"
L["Arms"] = "武器"
L["Fury"] = "狂怒"
L["Protection"] = "防護"
L["Holy"] = "神聖"
L["Retribution"] = "懲戒"
L["Beast Mastery"] = "野獸控制"
L["Marksmanship"] = "射擊"
L["Survival"] = "生存"
L["Assassination"] = "刺殺"
L["Combat"] = "戰鬥"
L["Subtlety"] = "敏銳"
L["Discipline"] = "戒律"
L["Shadow"] = "暗影"
L["Elemental"] = "元素"
L["Enhancement"] = "增強"
L["Restoration"] = "恢復"
L["Arcane"] = "秘法"
L["Fire"] = "火焰"
L["Frost"] = "冰霜"
L["Affliction"] = "痛苦"
L["Demonology"] = "惡魔學識"
L["Destruction"] = "毀滅"
L["Balance"] = "平衡"
L["Feral Combat"] = "野性戰鬥"
L["Tandem: not available in combat"] = "Tandem：戰鬥中無法使用"
L["Tandem: your class or level is not known yet; try again in a moment"] = "Tandem：尚未取得你的職業或等級，請稍後再試"
L["item #%d"] = "物品 #%d"

L["Head"] = "頭部"
L["Neck"] = "頸部"
L["Shoulder"] = "肩部"
L["Back"] = "背部"
L["Chest"] = "胸部"
L["Wrist"] = "手腕"
L["Hands"] = "手部"
L["Waist"] = "腰部"
L["Legs"] = "腿部"
L["Feet"] = "腳部"
L["Finger"] = "手指"
L["Trinket"] = "飾品"
L["Off hand"] = "副手"
L["Two-hand"] = "雙手"
L["Ranged"] = "遠程"

-- Library book location notes (library books D1); the titles stay English.
L["Tower of Azora, 3rd floor, on a table"] = "亞祖拉之塔三樓的桌上"
L["Moonbrook, first house entering from the east"] = "月溪鎮，從東邊進入的第一棟房子"
L["Sentinel Hill inn, behind the innkeeper"] = "哨兵嶺旅店，旅店老闆身後"
L["Raven Hill Crypt: westernmost entrance, stairs to the end, on a bench"] = "烏鴉嶺墓穴：走最西邊的入口，下樓梯到底，在長椅上"
L["Ogre cave, left path with two ogres"] = "食人魔洞穴，走有兩隻食人魔的左側通道"
L["Thelsamar inn, upper level, on a table (same book as Westfall's)"] = "塞爾薩瑪旅店二樓的桌上（與西部荒野的是同一本書）"
L["Lower level of the excavation site, along the right side"] = "挖掘場下層，沿著右側"
L["Hall of Explorers, large table"] = "探險者大廳的大桌子上"
L["Brill, alchemy shop shelf"] = "布瑞爾，鍊金術商店的書架上"
L["Amber Mill main building, shelf in the main hall"] = "安伯米爾主建築，大廳的書架上"
L["Top control room of the oil rig"] = "油井鑽台頂端的控制室"
L["Ratchet engineering building, table behind the flight master"] = "棘齒城工程建築，飛行管理員身後的桌上"
L["Final room of the Cavern of Mists (outside the Wailing Caverns dungeon)"] = "迷霧洞穴最深處的房間（在哀嚎洞穴副本外）"
L["Ruins, down the stairs before the water floor"] = "遺跡中，在淹水的樓層之前走下樓梯"
L["Barrel in the tent east of camp, by the large totem"] = "營地東邊帳篷裡的木桶，在大圖騰旁"
L["Large tablet at Darkbriar Lodge"] = "暗棘小屋的大石板"
L["Large table outside the basilisk cave"] = "蜥蜴洞穴外的大桌子上"
L["Grimtotem mound, main hut, left side"] = "恐怖圖騰土丘，主屋的左側"
L["Ogre tower at the crossroads (level 40 ogre guard)"] = "十字路口的食人魔塔（有 40 級食人魔守衛）"
L["Furnace in the middle of the murloc camp"] = "魚人營地中央的熔爐"
L["Hut on the east side of Witherbark Village"] = "枯木村東側的小屋"
L["Thunder Axe Fortress, large building in the inner ring"] = "雷斧堡壘，內圈的大型建築"
L["Crypt opening past the two-dwarf camp, next to two bodies"] = "經過兩名矮人的營地後的墓穴入口，在兩具屍體旁"
L["Scholomance (outside), upstairs at a table"] = "通靈學院（外面），樓上的桌子"
L["Second floor of the house next to the barn"] = "穀倉旁房子的二樓"
L["Inside Light's Hope Chapel"] = "聖光之願禮拜堂內"
L["Burnt-down house by the lake"] = "湖邊燒毀的房子"
L["Zone side of the bridge before Stratholme"] = "斯坦索姆前那座橋靠區域的一側"
L["Top level of the Temple of Atal'Hakkar, back side"] = "阿塔哈卡神廟頂層的後側"
L["Inside the half-circle wall, first pyramid on the left"] = "半圓形城牆內，左手邊第一座金字塔"
L["Timbermaw Hold cave, left of the bridge"] = "木喉要塞洞穴，橋的左側"
L["Everlook"] = "永望鎮"
L["Blackrock Mountain, tomb by the summoning stone, next to Franclorn Forgewright"] =
    "黑石山，召喚石旁的墓室，在弗朗克羅恩·鑄鐵旁"
L["Blackrock Mountain, just past Lothos Riftwaker"] = "黑石山，剛經過洛索斯·天痕之處"
L["Tent with a Dark Iron dwarf next to it"] = "旁邊有一名黑鐵矮人的帳篷"
L["North of the flight path, before the ruins"] = "飛行點北方，遺跡之前"
L["Lost Rigger Cove, bookshelf amid the three buildings"] = "失落者海灣，三棟建築之間的書架"
L["Stormwind Mage Tower"] = "暴風城法師塔"
L["Undercity, Magic Quarter"] = "幽暗城，魔法區"

-- Library book pins and the books switch (library books D3, D4).
L["Tandem: library book hints on"] = "Tandem：圖書館書籍提示已開啟"
L["Tandem: library book hints off"] = "Tandem：圖書館書籍提示已關閉"
L["Tandem: the book hints switch cannot be saved: recording is off"] = "Tandem：無法儲存書籍提示開關：記錄已暫停"
L["Entrance"] = "入口"
L["Level %d+"] = "%d 級以上"
L["Enemy city"] = "敵對主城"
L["Click to set a waypoint"] = "點擊以設定路徑點"
L["Takes library books"] = "收取圖書館書籍"
L["Tandem: waypoint set to %s"] = "Tandem：已設定路徑點到 %s"
L["Tandem: a waypoint cannot be set here"] = "Tandem：無法在此設定路徑點"
L["Tandem: your map position is not known here"] = "Tandem：無法取得你在此處的地圖位置"
L["Tandem: map %d %s at (%.2f, %.2f)"] = "Tandem：地圖 %d %s，位置 (%.2f, %.2f)"
L["Tandem: nearest book %s (%s), map %d, %d yd"] = "Tandem：最近的書 %s（%s），地圖 %d，%d 碼"
L["Tandem: nearest book %s (%s), %.1f map percent away"] = "Tandem：最近的書 %s（%s），相距地圖 %.1f%%"
L["Tandem: no eligible book on this continent"] = "Tandem：這塊大陸上沒有符合等級的書"
L["Tandem: Library book nearby: %s — %s"] = "Tandem：附近有圖書館書籍：%s — %s"
-- Turned-in library books on the map (library books D6).
L["Turned in"] = "已繳交"
L["Books turned in: %d/%d"] = "已繳交書籍：%d/%d"
L["Next reward at %d books"] = "下一個獎勵：%d 本"
L["%s is nearby (seen at your death %d times)"] = "%s 就在附近（你死亡時見過 %d 次）"
L["  /tandem killers - list the enemy players seen targeting you at your death"] =
    "  /tandem killers - 列出你死亡時以你為目標的敵方玩家"
L["  /tandem killers forget <name> | clear - drop one name from that list, or all of them"] =
    "  /tandem killers forget <name> | clear - 從名單刪除一個名字，或全部清空"
L["Seen targeting you at your death:"] = "你死亡時以你為目標的玩家："
L["No one recorded yet."] = "尚無任何紀錄。"
L["%s is not on the list."] = "%s 不在名單上。"
L["%s matches several; use Name-Realm."] = "%s 符合多筆；請用 名字-伺服器。"
L["%s removed from the list."] = "已從名單刪除 %s。"
L["Killer list cleared."] = "已清空擊殺者名單。"
L["Killer list unavailable."] = "無法使用擊殺者名單。"
L["Killers"] = "擊殺者"
L["Clear"] = "清空"
L["Click again to clear"] = "再點一次以清空"
L["Name"] = "名稱"
L["Class"] = "職業"
L["Level"] = "等級"
L["Kills"] = "次數"
L["Last killed"] = "最後擊殺"
L["Zone"] = "地區"
L["Right-click to show the killer list"] = "右鍵點擊以顯示擊殺者名單"

-- Tooltip stat lines as the zhTW client shows them (see enUS.lua); a pattern that would also match a more specific
-- line comes after it.
ns.StatPatterns = {
    { "^%+(%d+) ?力量$", "str" },
    { "^%+(%d+) ?敏捷$", "agi" },
    { "^%+(%d+) ?耐力$", "sta" },
    { "^%+(%d+) ?智力$", "int" },
    { "^%+(%d+) ?精神$", "spi" },
    { "^(%d+) ?點護甲$", "armor" },
    { "^(%d+) ?點格擋$", "blockvalue" },
    { "每秒傷害 ?(%d+%.?%d*)", "dps" },
    { "^裝備：%+(%d+) ?遠程攻擊強度", "rap" },
    { "^裝備：%+(%d+) ?攻擊強度", "ap" },
    { "^裝備：.-傷害和治療效果提高最多(%d+)點", "sp" },
    { "^裝備：.-治療效果提高最多(%d+)點", "heal" },
    { "^裝備：使你的法術造成致命一擊的機率提高(%d+%.?%d*)%%", "spellcrit" },
    { "^裝備：使你的法術擊中.-機率提高(%d+%.?%d*)%%", "spellhit" },
    { "^裝備：使你造成致命一擊的機率提高(%d+%.?%d*)%%", "crit" },
    { "^裝備：使你擊中.-機率提高(%d+%.?%d*)%%", "hit" },
    { "^裝備：每5秒恢復(%d+)點法力", "mp5" },
    { "^裝備：防禦技能提高(%d+)點", "def" },
    { "^裝備：使你躲閃.-機率提高(%d+%.?%d*)%%", "dodge" },
    { "^裝備：使你招架.-機率提高(%d+%.?%d*)%%", "parry" },
    { "^裝備：.-盾牌格擋值提高(%d+)點", "blockvalue" },
    { "^裝備：使你.-格擋.-機率提高(%d+%.?%d*)%%", "block" },
}

-- Food and drink tooltip text and aura names as the zhTW client shows them (see enUS.lua).
ns.FoodText = {
    stop = "。",
    health = { "(%d+%.?%d*) ?點生命" },
    mana = { "(%d+%.?%d*) ?點法力" },
    wellFed = { "充分進食", "進食充分" },
    conjured = { "魔法製造的物品", "魔法製造物品" },
    seated = { "保持坐姿", "保持坐著" },
    use = { "使用：" },
    eating = { "進食", "食物", "食物和飲料", "茶點" },
    drinking = { "喝水", "飲料", "食物和飲料", "茶點" },
    wellFedAura = { "充分進食", "進食充分" },
}
