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
L["Cure buttons"] = "驅散按鈕"
L["Cure macro"] = "驅散巨集"
L["Poison"] = "中毒"
L["Disease"] = "疾病"
L["No one in your party has a %s effect"] = "你和隊友身上都沒有%s效果"
L["Click to cast it on your mouseover, your target or yourself"] = "點擊對滑鼠指向的隊友、你的目標或你自己施放"
L["Drag to place the cure macro on your action bar"] = "拖曳即可把驅散巨集放到快捷列"
L["Character macros full: no room for the cure macro"] = "角色巨集已滿：沒有空間放驅散巨集"
L["%dd %dh"] = "%d天 %d時"
L["%dh %dm"] = "%d時 %d分"
L["%dm"] = "%d分"
L["Played: %s"] = "遊玩時間：%s"
L["This level: %s"] = "本等級：%s"
L["This session: %s"] = "本次上線：%s"
L["Shaman area"] = "薩滿區"
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
