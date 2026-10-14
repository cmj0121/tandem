local _, ns = ...

if GetLocale() ~= "zhTW" then
    return
end

local L = ns.L

L["%s loaded"] = "%s 已載入"
L["%s: saved data uses newer schema %d; recording is off until the addon is updated"] =
    "%s：存檔資料使用較新的結構版本 %d；在更新插件前暫停記錄"
L["%s: saved data was unreadable and has been reset"] = "%s：存檔資料無法讀取，已重設"
L["%s: dropped %d invalid saved entries"] = "%s：已捨棄 %d 筆無效的存檔資料"

L["Tandem commands:"] = "Tandem 指令："
L["  /tandem count - show collected data"] = "  /tandem count - 顯示已收集的資料"
L["  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)"] =
    "  /tandem scan [<n>/s|<n>/m] [<上限>] - 掃描物品 ID（預設 10/s、100 個 ID）"
L["  /tandem scan from <id> - set the next item ID to scan"] = "  /tandem scan from <id> - 設定下一個要掃描的物品 ID"
L["  /tandem scan stop - stop the scan"] = "  /tandem scan stop - 停止掃描"
L["Tandem: scanner not available"] = "Tandem：掃描器無法使用"
L["Tandem: %d known items, %s non-equippable"] = "Tandem：已知 %d 件物品，%s 件不可裝備"
L["none"] = "無"
L["Scan cursor: %s, found IDs: %s"] = "掃描位置：%s，找到的 ID：%s"
L["Loot entries: %d, npc names: %d"] = "掉落紀錄：%d 筆，NPC 名稱：%d 個"
L["Unsaved records: %d (saved on /reload or logout)"] = "未儲存紀錄：%d 筆（/reload 或登出時儲存）"
L["Last run: IDs %s-%s at %s in %ss, %s processed, %s skipped"] =
    "上次掃描：ID %s-%s，速率 %s，耗時 %s 秒，處理 %s 個，略過 %s 個"
L["  %s hits (%s equippable), %s misses, %s deferred, %s timeouts"] =
    "  命中 %s 個（可裝備 %s 個），未命中 %s 個，延後 %s 個，逾時 %s 個"
L["Last run: never"] = "上次掃描：從未執行"
L["Recording is off: saved data uses a newer schema"] = "記錄已停用：存檔資料使用較新的結構版本"
