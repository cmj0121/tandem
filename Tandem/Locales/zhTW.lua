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
