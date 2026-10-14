-- Merged from data/contributions/ by `make import`; do not edit.
-- Rows are filled in functions of 2000 so no function exceeds Lua's constant limit.
local _, ns = ...
local S = { contributors = 1, items = {}, loot = {}, kills = {}, corpses = {}, names = {} }
ns.Shipped = S
-- S.loot rows: { item, kind, id, map, count, x1, y1, ... up to 5 pairs }, sorted by item, kind, id, map
do
    local function fill(t)
        t[1] = { 159, "c", 476, 1429, 1, 612, 556 }
        t[2] = { 765, "o", 1617, 1429, 1, 503, 592 }
        t[3] = { 2449, "o", 1619, 1429, 2, 524, 574, 552, 570 }
        t[4] = { 2589, "c", 476, 1429, 1, 612, 556 }
    end
    fill(S.loot)
end
S.names["zhTW"] = {}
do
    local function fill(t)
        t[476] = "狗頭人地卜師"
    end
    fill(S.names["zhTW"])
end
