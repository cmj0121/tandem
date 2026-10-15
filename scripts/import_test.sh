#!/bin/sh
# Tests for import.lua and `make import` using throwaway saved-variables files and data directories.
set -u

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
LUA=${LUA:-lua}

check() {
	if [ "$2" = "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$3" "$2"
		fails=$((fails + 1))
	fi
}

# contains <name> <file> <fixed string>
contains() {
	if grep -qF -- "$3" "$2"; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s\n     %s lacks: %s\n' "$1" "$2" "$3"
		fails=$((fails + 1))
	fi
}

import() {
	"$LUA" "$here/import.lua" "$@" >"$tmp/out" 2>"$tmp/err"
}

sv() {
	cat >"$tmp/$1"
}

# shipped <name> <out-file> <lua>: loads the generated file under a fake addon ns, then runs the assertions
# with S bound to ns.Shipped.
shipped() {
	printf 'local ns = {}\nassert(loadfile(arg[1]))("Tandem", ns)\nlocal S = ns.Shipped\n%s\n' "$3" >"$tmp/assert.lua"
	if "$LUA" "$tmp/assert.lua" "$2" 2>"$tmp/assert.err"; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s\n     %s\n' "$1" "$(cat "$tmp/assert.err")"
		fails=$((fails + 1))
	fi
}

sv a.lua <<'EOF'
TandemDB = {
	["schemaVersion"] = 2,
	["items"] = { [42] = { 20, 15, 3, "INVTYPE_CHEST", 4, 2 } },
	["npcs"] = { [448] = "Hogger", [100] = "Kobold" },
	["loot"] = {
		["25:c:448:1429"] = { ["item"] = 25, ["kind"] = "c", ["id"] = 448, ["map"] = 1429, ["count"] = 2,
			["coords"] = { { 500, 500 }, { 100, 900 }, { 300, 300 } } },
		["40:o:7:0"] = { ["item"] = 40, ["kind"] = "o", ["id"] = 7, ["map"] = 0, ["count"] = 1, ["coords"] = {} },
	},
	["kills"] = { [448] = 3 },
	["corpses"] = { [448] = 2 },
}
EOF

sv b.lua <<'EOF'
TandemDB = {
	["schemaVersion"] = 2,
	["items"] = { [42] = { 99, 60, 4, "INVTYPE_ROBE", 4, 1 }, [43] = { 10, 5, 2, "INVTYPE_FEET", 4, 1 } },
	["npcs"] = { [448] = "霍格" },
	["loot"] = {
		["25:c:448:1429"] = { ["item"] = 25, ["kind"] = "c", ["id"] = 448, ["map"] = 1429, ["count"] = 3,
			["coords"] = { { 500, 500 }, { 200, 200 }, { 900, 100 }, { 50, 50 } } },
		["25:c:448:12"] = { ["item"] = 25, ["kind"] = "c", ["id"] = 448, ["map"] = 12, ["count"] = 1, ["coords"] = {} },
	},
	["kills"] = { [448] = 4 },
	["corpses"] = { [448] = 1, [100] = 5 },
}
EOF

data="$tmp/data"
out="$tmp/addon/Data/Loot.lua"
import "$data" "$out" enUS aaaa "$tmp/a.lua" zhTW bbbb "$tmp/b.lua"
check "two contributors import" "$?" "0"
[ -f "$out" ]
check "the out file and its directory are created" "$?" "0"
[ ! -e "$data/loot.lua" ]
check "data/loot.lua is no longer written" "$?" "0"
contains "success line names the out file" "$tmp/out" "wrote $out (2 contributors, 2 items, 3 loot rows)"
contains "contribution line counts every block" "$tmp/out" \
	'(enUS: 2 loot entries, 2 npc names, 0 quest names, 1 items, 3 kills, 2 looted corpses)'
cp "$out" "$tmp/shipped1"
cp "$data/contributions/aaaa.lua" "$tmp/aaaa1"

import "$data" "$out" enUS aaaa "$tmp/a.lua" zhTW bbbb "$tmp/b.lua"
cmp -s "$out" "$tmp/shipped1"
check "second run gives a byte-identical out file" "$?" "0"
cmp -s "$data/contributions/aaaa.lua" "$tmp/aaaa1"
check "second run gives a byte-identical contribution" "$?" "0"
import "$data" "$out" zhTW bbbb "$tmp/b.lua" enUS aaaa "$tmp/a.lua"
cmp -s "$out" "$tmp/shipped1"
check "argument order does not change the out file" "$?" "0"
import "$data" "$out"
check "no saved variables rebuilds only" "$?" "0"
cmp -s "$out" "$tmp/shipped1"
check "a rebuild alone gives the same out file" "$?" "0"

contains "out file has the generated header" "$out" '-- Merged from data/contributions/ by `make import`; do not edit.'
contains "out file sets ns.Shipped" "$out" 'ns.Shipped = S'
contains "out file counts contributors" "$out" "contributors = 2,"
contains "loot counts are summed and coords are the sorted distinct union, capped at 5" "$out" \
	't[2] = { 25, "c", 448, 1429, 5, 50, 50, 100, 900, 200, 200, 300, 300, 500, 500 }'
contains "a single-source row is kept" "$out" 't[3] = { 40, "o", 7, 0, 1 }'
check "loot rows are sorted by item, kind, id, map" "$(grep -o '^        t\[[0-9]*\] = { [0-9]*, "[a-z?]", [0-9]*, [0-9]*' "$out" | tr -d ' ')" \
	"$(printf 't[1]={25,"c",448,12\nt[2]={25,"c",448,1429\nt[3]={40,"o",7,0')"
contains "items are one record per line" "$out" 't[42] = { 20, 15, 3, "INVTYPE_CHEST", 4, 2 }'
contains "enUS name" "$out" 't[448] = "Hogger"'
contains "zhTW name" "$out" 't[448] = "霍格"'
contains "names are grouped by locale" "$out" 'S.names["zhTW"] = {}'
contains "contribution keeps the locale" "$data/contributions/bbbb.lua" 'locale = "zhTW",'
contains "contribution keeps items" "$data/contributions/aaaa.lua" '[42] = { 20, 15, 3, "INVTYPE_CHEST", 4, 2 },'
contains "contribution keeps kills" "$data/contributions/aaaa.lua" '[448] = 3,'
contains "contribution keeps looted corpses" "$data/contributions/bbbb.lua" '[100] = 5,'
check "npc keys sort numerically" "$(grep -n '\[100\] = \|\[448\] = "Hogger"' "$data/contributions/aaaa.lua" | cut -d: -f2 | tr -d ' \n')" \
	'[100]="Kobold",[448]="Hogger",'
shipped "the out file loads under a fake addon ns" "$out" '
assert(S.contributors == 2 and #S.loot == 3)
assert(S.kills[448] == 7, "kills are summed")
assert(S.corpses[448] == 3 and S.corpses[100] == 5, "looted corpses are summed")
assert(S.items[42][1] == 20 and S.items[42][4] == "INVTYPE_CHEST", "the lexically first contributor wins an item")
assert(S.items[43][4] == "INVTYPE_FEET", "items are a union")
assert(S.names.enUS[100] == "Kobold" and S.names.zhTW[448] == "霍格")'
printf 'local env = {}\nassert(loadfile(arg[1], "t", env))("Tandem", {})\nassert(next(env) == nil)\n' >"$tmp/env.lua"
"$LUA" "$tmp/env.lua" "$out"
check "the out file sets no globals" "$?" "0"

# A grown snapshot of the same account replaces its contribution.
sed 's/\["count"\] = 2/["count"] = 10/; s/\[448\] = 3/[448] = 30/' "$tmp/a.lua" >"$tmp/a2.lua"
import "$data" "$out" enUS aaaa "$tmp/a2.lua"
check "re-import succeeds" "$?" "0"
shipped "re-import replaces the snapshot instead of adding" "$out" '
assert(S.contributors == 2 and S.loot[2][5] == 13 and S.kills[448] == 34)'

# Deprecated items: the flag is a 7th field, kept only as 1, and set on the merged record when any contributor has it.
sv dep-a.lua <<'EOF'
TandemDB = {
	schemaVersion = 2,
	items = {
		[50] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1 },
		[51] = { 12, 5, 2, "INVTYPE_FEET", 4, 1, 1 },
		[52] = { 1, 1, 1, "INVTYPE_HAND", 4, 1, 7 },
		[53] = { 20, 15, 2, "INVTYPE_WAIST", 4, 1, 1 },
	},
}
EOF
sv dep-b.lua <<'EOF'
TandemDB = {
	schemaVersion = 2,
	items = { [50] = { 99, 60, 4, "INVTYPE_HEAD", 4, 1, 1 }, [53] = { 30, 25, 3, "INVTYPE_WAIST", 4, 1 } },
}
EOF
dep="$tmp/dep"
import "$dep" "$dep/Loot.lua" enUS aaaa "$tmp/dep-a.lua" enUS bbbb "$tmp/dep-b.lua"
check "deprecated items import" "$?" "0"
check "a 7th field other than 1 is not an invalid entry" "$(cat "$tmp/err")" ""
contains "a flagged record is written with 7 fields" "$dep/contributions/aaaa.lua" \
	'[51] = { 12, 5, 2, "INVTYPE_FEET", 4, 1, 1 },'
contains "an unflagged record is written with 6 fields" "$dep/contributions/aaaa.lua" \
	'[50] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1 },'
contains "a 7th field other than 1 is stripped" "$dep/contributions/aaaa.lua" '[52] = { 1, 1, 1, "INVTYPE_HAND", 4, 1 },'
contains "a flagged record is shipped with 7 fields" "$dep/Loot.lua" 't[51] = { 12, 5, 2, "INVTYPE_FEET", 4, 1, 1 }'
contains "the first record wins and a later contributor's flag is ORed in" "$dep/Loot.lua" \
	't[50] = { 10, 5, 2, "INVTYPE_HEAD", 4, 1, 1 }'
contains "the first record's flag survives a later unflagged record" "$dep/Loot.lua" \
	't[53] = { 20, 15, 2, "INVTYPE_WAIST", 4, 1, 1 }'
shipped "flagged records load back" "$dep/Loot.lua" '
assert(S.items[50][7] == 1 and S.items[51][7] == 1 and S.items[52][7] == nil and #S.items[52] == 6)'

# Quest rewards (q) and vendor items (v): counts are summed, factions ORed into S.factions, quest names merged per
# locale into S.questNames; a bad q/v row drops only that row.
sv qa.lua <<'EOF'
TandemDB = {
	schemaVersion = 3,
	quests = { [100] = "Wanted: Hogger", [101] = "Zeta" },
	loot = {
		{ item = 60, kind = "q", id = 100, map = 1429, count = 1, coords = { { 100, 200 } }, factions = 1 },
		{ item = 61, kind = "v", id = 200, map = 12, count = 1, coords = {}, factions = 2 },
		{ item = 62, kind = "c", id = 448, map = 1429, count = 2, coords = {} },
		{ item = 63, kind = "q", id = 0, map = 1429, count = 1, coords = {}, factions = 1 },
		{ item = 64, kind = "v", id = 201, map = 12, count = 1, coords = {}, factions = 4 },
	},
}
EOF
sv qb.lua <<'EOF'
TandemDB = {
	schemaVersion = 3,
	quests = { [100] = "通緝：霍格" },
	loot = {
		{ item = 60, kind = "q", id = 100, map = 1429, count = 1, coords = { { 300, 400 } }, factions = 2 },
		{ item = 61, kind = "v", id = 200, map = 12, count = 1, coords = {}, factions = 2 },
	},
}
EOF
sv qc.lua <<'EOF'
TandemDB = { schemaVersion = 3, quests = { [100] = "Another Name" } }
EOF
qv="$tmp/qv"
import "$qv" "$qv/Loot.lua" enUS qa "$tmp/qa.lua" zhTW qb "$tmp/qb.lua" enUS qc "$tmp/qc.lua"
check "quest and vendor rows import" "$?" "0"
contains "bad q/v rows are reported" "$tmp/err" "qa.lua: 2 invalid entries ignored"
contains "contribution line counts quest names" "$tmp/out" '(enUS: 3 loot entries, 0 npc names, 2 quest names,'
contains "contribution keeps a q row's factions" "$qv/contributions/qa.lua" \
	'{ item = 60, kind = "q", id = 100, map = 1429, count = 1, coords = { { 100, 200 } }, factions = 1 },'
contains "contribution keeps quest names" "$qv/contributions/qa.lua" '[100] = "Wanted: Hogger",'
contains "a drop row carries no factions" "$qv/contributions/qa.lua" \
	'{ item = 62, kind = "c", id = 448, map = 1429, count = 2, coords = {} },'
contains "q rows keep the loot row shape" "$qv/Loot.lua" 't[1] = { 60, "q", 100, 1429, 2, 100, 200, 300, 400 }'
contains "factions are keyed by item:kind:id:map" "$qv/Loot.lua" 't["60:q:100:1429"] = 3'
contains "quest names are grouped by locale" "$qv/Loot.lua" 'S.questNames["zhTW"] = {}'
shipped "q/v rows, factions and quest names load back" "$qv/Loot.lua" '
assert(S.contributors == 3 and #S.loot == 3, "only the bad rows are dropped")
assert(S.loot[2][1] == 61 and S.loot[2][5] == 2 and S.loot[3][1] == 62 and S.loot[3][2] == "c")
assert(S.loot[1][5] == 2 and #S.loot[1] == 9, "q counts are summed; one coord from each contributor")
assert(S.factions["60:q:100:1429"] == 3, "factions are ORed")
assert(S.factions["61:v:200:12"] == 2, "the same faction twice stays one bit")
assert(S.factions["62:c:448:1429"] == nil, "drop rows have no factions")
assert(S.factions["63:q:0:1429"] == nil and S.factions["64:v:201:12"] == nil)
assert(S.questNames.enUS[100] == "Another Name" and S.questNames.enUS[101] == "Zeta", "lexically first name wins")
assert(S.questNames.zhTW[100] == "通緝：霍格" and next(S.names.enUS) == nil)'
import "$qv" "$qv/Loot.lua" zhTW qb "$tmp/qb.lua" enUS qa "$tmp/qa.lua" enUS qc "$tmp/qc.lua"
cp "$qv/Loot.lua" "$tmp/qv1"
import "$qv" "$qv/Loot.lua"
cmp -s "$qv/Loot.lua" "$tmp/qv1"
check "a q/v rebuild is byte-identical" "$?" "0"
cat >"$qv/contributions/zz.lua" <<'EOF'
return {
    locale = "enUS",
    loot = {
        { item = 61, kind = "v", id = 200, map = 12, count = 1, coords = {}, factions = 1 },
        { item = 65, kind = "v", id = 202, map = 12, count = 1, coords = {} },
        { item = 66, kind = "q", id = 102, map = 12, count = 1, coords = {}, factions = 0 },
    },
    quests = { [102] = "", [103] = "Kept" },
}
EOF
import "$qv" "$qv/Loot.lua"
check "a contribution with bad q/v rows rebuilds" "$?" "0"
contains "a contribution's bad q/v rows and names are reported" "$tmp/err" "zz.lua: 3 invalid entries ignored"
shipped "a contribution's bad q/v rows drop only those rows" "$qv/Loot.lua" '
assert(S.contributors == 4 and #S.loot == 3 and S.factions["61:v:200:12"] == 3 and S.loot[2][5] == 3)
assert(S.questNames.enUS[103] == "Kept" and S.questNames.enUS[102] == nil)'

# The same quest on different maps from different contributors is one row on the lowest map, with that map's
# coords, the counts summed and the factions ORed; drops on two maps stay two rows.
sv m1.lua <<'EOF'
TandemDB = {
	schemaVersion = 3,
	loot = {
		{ item = 70, kind = "q", id = 300, map = 1429, count = 1, coords = { { 100, 100 } }, factions = 1 },
		{ item = 71, kind = "c", id = 448, map = 1429, count = 1, coords = {} },
	},
}
EOF
sv m2.lua <<'EOF'
TandemDB = {
	schemaVersion = 3,
	loot = {
		{ item = 70, kind = "q", id = 300, map = 12, count = 1, coords = { { 500, 500 } }, factions = 2 },
		{ item = 71, kind = "c", id = 448, map = 12, count = 1, coords = {} },
	},
}
EOF
sv m3.lua <<'EOF'
TandemDB = {
	schemaVersion = 3,
	loot = { { item = 70, kind = "q", id = 300, map = 12, count = 1, coords = { { 600, 600 } }, factions = 2 } },
}
EOF
maps="$tmp/maps"
import "$maps" "$maps/Loot.lua" enUS m1 "$tmp/m1.lua" enUS m2 "$tmp/m2.lua" enUS m3 "$tmp/m3.lua"
check "a quest on two maps imports" "$?" "0"
contains "a quest on two maps is one row on the lower map with its coords and the summed count" "$maps/Loot.lua" \
	't[1] = { 70, "q", 300, 12, 3, 500, 500, 600, 600 }'
contains "the success line counts the collapsed row once" "$tmp/out" '(3 contributors, 0 items, 3 loot rows)'
shipped "a collapsed quest row keeps ORed factions under the lower map" "$maps/Loot.lua" '
assert(S.factions["70:q:300:12"] == 3 and S.factions["70:q:300:1429"] == nil)
assert(S.loot[2][1] == 71 and S.loot[2][4] == 12 and S.loot[3][1] == 71 and S.loot[3][4] == 1429)'
cp "$maps/Loot.lua" "$tmp/maps1"
rm "$maps/contributions/m2.lua"
import "$maps" "$maps/Loot.lua" enUS m2 "$tmp/m2.lua"
cmp -s "$maps/Loot.lua" "$tmp/maps1"
check "re-importing one contributor gives a byte-identical collapsed row" "$?" "0"

# Contributions written before kills, corpses and items existed still import.
old="$tmp/old"
mkdir -p "$old/contributions"
cat >"$old/contributions/0000.lua" <<'EOF'
-- Loot snapshot of one account, generated by `make import`; do not edit.
return {
    locale = "zhTW",
    loot = {
        ["159:c:476:1429"] = { item = 159, kind = "c", id = 476, map = 1429, count = 1, coords = { { 612, 556 } } },
    },
    npcs = {
        [476] = "狗頭人地卜師",
    },
}
EOF
import "$old" "$old/Loot.lua"
check "an old contribution rebuilds" "$?" "0"
check "an old contribution has nothing invalid" "$(cat "$tmp/err")" ""
shipped "an old contribution is shipped" "$old/Loot.lua" '
assert(S.contributors == 1 and next(S.items) == nil and next(S.kills) == nil and next(S.corpses) == nil)
assert(S.loot[1][1] == 159 and S.loot[1][2] == "c" and S.loot[1][6] == 612 and S.names.zhTW[476])'
import "$old" "$old/Loot.lua" enUS aaaa "$tmp/a.lua"
shipped "an old contribution merges with a new one" "$old/Loot.lua" '
assert(S.contributors == 2 and S.kills[448] == 3 and S.items[42] and S.names.zhTW[476] and S.names.enUS[448])'

# Hostile values: invalid entries are dropped, odd but valid strings and numbers survive as data.
sv hostile.lua <<'EOF'
TandemDB = {
	schemaVersion = 2,
	items = { [5] = { 1.5, 2, 3, "a\"]] os.exit(9) --[[\n\0", 4, 2 }, [6] = { 1, 2 }, [-1] = { 1, 2, 3, "X", 4, 2 } },
	npcs = { [9] = "\"]]\n" },
	kills = { [448] = -1, [0] = 3, x = "y", [7] = 2 ^ 60, [8] = 9223372036854775807 },
	corpses = "lots",
	loot = { { item = 1, kind = "c", id = 8, map = 1, count = 9223372036854775807 } },
}
EOF
sv small.lua <<'EOF'
TandemDB = {
	schemaVersion = 2,
	kills = { [8] = 5 },
	loot = { { item = 1, kind = "c", id = 8, map = 1, count = 5 } },
}
EOF
hostile="$tmp/hostile"
import "$hostile" "$hostile/Loot.lua" enUS hhhh "$tmp/hostile.lua"
check "hostile values still import" "$?" "0"
contains "hostile values are reported" "$tmp/err" "6 invalid entries ignored"
cp "$hostile/contributions/hhhh.lua" "$hostile/contributions/iiii.lua"
import "$hostile" "$hostile/Loot.lua" enUS jjjj "$tmp/small.lua"
shipped "hostile values load back as data" "$hostile/Loot.lua" '
assert(S.items[5][1] == 1.5 and S.items[5][4] == "a\"]] os.exit(9) --[[\n\0")
assert(S.items[6] == nil and S.items[-1] == nil and S.names.enUS[9] == "\"]]\n")
assert(S.kills[448] == nil and S.kills[0] == nil and S.kills.x == nil and next(S.corpses) == nil)
assert(S.kills[7] == 2 ^ 53, "sums are capped")
assert(S.kills[8] == 2 ^ 53, "a max integer plus a small count is capped, not wrapped")
assert(S.loot[1][5] == 2 ^ 53, "a max integer loot count plus a small one is capped, not wrapped")'

# The import above writes the max integer back as a float; a contribution holding the integer literal itself,
# summed after a small count, is what wraps in Lua 5.3+ without the cap.
wrap="$tmp/wrap"
mkdir -p "$wrap/contributions"
printf 'return { locale = "enUS", kills = { [8] = 5 }, loot = { { item = 1, kind = "c", id = 8, map = 1, count = 5 } } }\n' \
	>"$wrap/contributions/aa.lua"
printf 'return { locale = "enUS", kills = { [8] = 9223372036854775807 }, loot = { { item = 1, kind = "c", id = 8, map = 1, count = 9223372036854775807 } } }\n' \
	>"$wrap/contributions/zz.lua"
import "$wrap" "$wrap/Loot.lua"
check "an integer-literal contribution rebuilds" "$?" "0"
shipped "an integer-literal sum is capped, not wrapped" "$wrap/Loot.lua" '
assert(S.kills[8] == 2 ^ 53 and S.loot[1][5] == 2 ^ 53)'

# No contributions to rebuild from: an error, and the out file is left alone.
empty="$tmp/empty"
mkdir -p "$empty/contributions"
printf 'keep\n' >"$empty/Loot.lua"
import "$empty" "$empty/Loot.lua"
check "a rebuild with no contributions fails" "$?" "1"
contains "a rebuild with no contributions says so" "$tmp/err" "no contributions"
check "a rebuild with no contributions leaves the out file" "$(cat "$empty/Loot.lua")" "keep"
import "$tmp/none" "$tmp/none/Loot.lua"
check "a rebuild of a missing data dir fails" "$?" "1"
[ ! -e "$tmp/none/Loot.lua" ]
check "a rebuild of a missing data dir writes nothing" "$?" "0"

# A large shipped file stays within every function's constant limit (LuaJIT: 65536).
big="$tmp/big"
mkdir -p "$big/contributions"
cat >"$tmp/big.lua" <<'EOF'
local f = assert(io.open(arg[1], "w"))
f:write('return { locale = "enUS",\n    items = {\n')
for i = 1, 70000 do
    f:write(("        [%d] = { %d, %d, %d, \"INVTYPE_%d\", 4, %d },\n"):format(i, i, i + 100000, i % 5, i, i + 200000))
end
f:write('    },\n    loot = {\n')
for i = 1, 70000 do
    f:write(("        { item = %d, kind = \"c\", id = %d, map = %d, count = %d, coords = { { %d, %d } } },\n")
        :format(i, i + 300000, i + 400000, i + 500000, i, i + 600000))
end
f:write('    },\n}\n')
f:close()
EOF
"$LUA" "$tmp/big.lua" "$big/contributions/big.lua"
import "$big" "$big/Loot.lua"
check "a large contribution rebuilds" "$?" "0"
shipped "a large out file loads" "$big/Loot.lua" '
assert(S.items[70000][4] == "INVTYPE_70000" and #S.loot == 70000 and S.loot[70000][6] == 70000)'
if command -v luajit >/dev/null 2>&1; then
	lua=$LUA
	LUA=luajit
	shipped "a large out file loads under LuaJIT" "$big/Loot.lua" '
assert(S.items[70000][4] == "INVTYPE_70000" and #S.loot == 70000)'
	LUA=$lua
else
	printf 'skip a large out file loads under LuaJIT: no luajit\n'
fi

# Rejected inputs.
cp "$out" "$tmp/before"
reject() {
	import "$data" "$out" enUS bad "$tmp/$1"
	check "$2: exit 1" "$?" "1"
	check "$2: message" "$(grep -c "$1" "$tmp/err")" "1"
	[ ! -e "$data/contributions/bad.lua" ]
	check "$2: nothing written" "$?" "0"
	cmp -s "$out" "$tmp/before"
	check "$2: out file untouched" "$?" "0"
}

printf 'TandemDB = {' >"$tmp/syntax.lua"
reject syntax.lua "invalid Lua"
printf 'error("boom")\n' >"$tmp/runtime.lua"
reject runtime.lua "runtime error"
printf 'Other = {}\n' >"$tmp/nodb.lua"
reject nodb.lua "missing TandemDB"
printf 'TandemDB = 5\n' >"$tmp/notable.lua"
reject notable.lua "non-table TandemDB"
printf 'TandemDB = { schemaVersion = 4, loot = {} }\n' >"$tmp/newer.lua"
reject newer.lua "newer schema"
printf 'TandemDB = {}\nwhile true do end\n' >"$tmp/loop.lua"
reject loop.lua "endless loop"
"$LUA" - "$tmp/binary.lua" <<'EOF'
local f = io.open(arg[1], "wb")
f:write(string.dump(function() TandemDB = {} end))
f:close()
EOF
reject binary.lua "binary chunk"

printf 'os.execute("touch %s/pwned")\nTandemDB = {}\n' "$tmp" >"$tmp/exec.lua"
reject exec.lua "os.execute at top level"
printf 'io.open("%s/pwned", "w")\nTandemDB = {}\n' "$tmp" >"$tmp/io.lua"
reject io.lua "io.open at top level"
printf 'require("os").execute("touch %s/pwned")\nTandemDB = {}\n' "$tmp" >"$tmp/req.lua"
reject req.lua "require at top level"
[ ! -e "$tmp/pwned" ]
check "sandboxed files had no side effects" "$?" "0"

import "$data" "$out" enUS bad "$tmp/syntax.lua" enUS aaaa "$tmp/a2.lua"
check "a bad file among good ones is skipped, exit 0" "$?" "0"
cmp -s "$out" "$tmp/before"
check "skipping a bad file leaves the result unchanged" "$?" "0"

import "$data" "$out" en aaaa "$tmp/a.lua"
check "invalid locale rejected" "$?" "1"
import "$data" "$out" enUS ../x "$tmp/a.lua"
check "path-like contributor id rejected" "$?" "1"
import "$data" enUS aaaa "$tmp/a.lua"
check "a missing out file argument is a usage error" "$?" "2"
import "$data"
check "no out file is a usage error" "$?" "2"

# Broken contributions in the repo are skipped or cleaned when rebuilding.
printf 'os.exit(3)\n' >"$data/contributions/zzzz.lua"
printf 'return { locale = "enUS", kills = "x", items = { [1] = "y" } }\n' >"$data/contributions/yyyy.lua"
import "$data" "$out" enUS aaaa "$tmp/a2.lua"
check "a broken contribution does not stop the rebuild" "$?" "0"
contains "a broken contribution is reported" "$tmp/err" "zzzz.lua"
contains "invalid contribution entries are reported" "$tmp/err" "yyyy.lua: 2 invalid entries ignored"
rm "$data/contributions/zzzz.lua" "$data/contributions/yyyy.lua"
import "$data" "$out"
cmp -s "$out" "$tmp/before"
check "a broken contribution is left out" "$?" "0"

# make import: finds every account, hashes its folder name, reads the client locale.
wow="$tmp/World of Warcraft"
wtf="$wow/_classic_beta_/WTF"
mkdir -p "$wow/_classic_beta_/Interface/AddOns" "$wtf/Account/ACCOUNT ONE/SavedVariables" \
	"$wtf/Account/TWO#2/SavedVariables" "$wtf/Account/THREE/SavedVariables"
cp "$tmp/a.lua" "$wtf/Account/ACCOUNT ONE/SavedVariables/Tandem.lua"
cp "$tmp/b.lua" "$wtf/Account/TWO#2/SavedVariables/Tandem.lua"
printf 'SET gxWindow "1"\nSET textLocale "zhTW"\n' >"$wtf/Config.wtf"
one=$(printf %s "ACCOUNT ONE" | shasum -a 256 | cut -c1-12)
two=$(printf %s "TWO#2" | shasum -a 256 | cut -c1-12)
make -s -C "$here/.." import WOW_DIR="$wow" DATA="$tmp/mk" OUT="$tmp/mk/Loot.lua" >"$tmp/out" 2>"$tmp/err"
check "make import succeeds" "$?" "0"
check "make import writes one contribution per account" "$(ls "$tmp/mk/contributions" | tr '\n' ' ')" \
	"$(printf '%s.lua\n%s.lua\n' "$one" "$two" | sort | tr '\n' ' ')"
contains "make import reads textLocale" "$tmp/mk/contributions/$one.lua" 'locale = "zhTW",'
contains "make import prints what it wrote" "$tmp/out" "wrote $tmp/mk/Loot.lua (2 contributors"
make -s -n -C "$here/.." import WOW_DIR="$wow" >"$tmp/out" 2>"$tmp/err"
contains "make import writes Tandem/Data/Loot.lua by default" "$tmp/out" \
	'lua scripts/import.lua "data" "Tandem/Data/Loot.lua"'

rm "$wtf/Config.wtf"
make -s -C "$here/.." import WOW_DIR="$wow" DATA="$tmp/mk2" OUT="$tmp/mk2/Loot.lua" >"$tmp/out" 2>"$tmp/err"
contains "make import defaults to enUS" "$tmp/mk2/contributions/$one.lua" 'locale = "enUS",'

rm "$wtf/Account/ACCOUNT ONE/SavedVariables/Tandem.lua" "$wtf/Account/TWO#2/SavedVariables/Tandem.lua"
make -s -C "$here/.." import WOW_DIR="$wow" DATA="$tmp/mk3" OUT="$tmp/mk3/Loot.lua" >"$tmp/out" 2>"$tmp/err"
check "make import without saved variables fails" "$?" "2"

[ "$fails" -eq 0 ]
