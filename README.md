# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon. It collects a cache of equippable items, built by scanning item IDs, and a log of
where each looted item came from, with kill and looted-corpse counts for drop rates. From that data, merged with what
other players contributed, it suggests the best known gear your character can use and where it drops. It never acts for
the player, it records nothing while you are in combat, and its advice commands do not answer in combat.

## Install

From the repository root:

```sh
make install
```

This links the repository's `Tandem/` folder into the client as
`<World of Warcraft>/_classic_beta_/Interface/AddOns/Tandem`, so edits to Lua files take effect after `/reload` in game.
Running it again when the link is already in place does nothing.

To remove it:

```sh
make uninstall
```

### Finding the client

`make install`, `make uninstall` and `make import` locate the `World of Warcraft` folder with `scripts/wow-dir.sh`. A
folder qualifies only if it contains `<FLAVOR>/Interface/AddOns`. The search order is:

1. `WOW_DIR`, if set. If it does not qualify, the install fails rather than searching further.
2. `/Applications/World of Warcraft`, `~/Applications/World of Warcraft` and `/Users/Shared/World of Warcraft`.
3. Spotlight (`mdfind`) for any folder named `World of Warcraft`.

If nothing qualifies, the script exits with an error that lists every place it searched.

### Overrides

| Variable  | Default                | Meaning                                                                           |
| --------- | ---------------------- | --------------------------------------------------------------------------------- |
| `WOW_DIR` | auto-detected          | The `World of Warcraft` folder that contains `_classic_beta_`, not the flavor dir |
| `FLAVOR`  | `_classic_beta_`       | The client flavor folder inside `WOW_DIR`                                         |
| `MODE`    | `link`                 | `copy` copies the addon instead of linking it                                     |
| `DATA`    | `data`                 | The folder `make import` writes contributions to                                  |
| `OUT`     | `Tandem/Data/Loot.lua` | The merged file `make import` writes for the addon                                |

`WOW_DIR` and `FLAVOR` apply to `make install`, `make uninstall` and `make import`; `MODE` only to the first two.

Quote `WOW_DIR`, because the folder name contains spaces:

```sh
make install WOW_DIR="/Volumes/Games/World of Warcraft"
```

If the client does not pick up the linked folder, install a copy instead:

```sh
make uninstall
make install MODE=copy
```

A copy does not follow your edits; run `make install MODE=copy` again after each change. To remove a copy, run
`make uninstall MODE=copy`. `make install` refuses to replace an existing copy with a link until that copy is removed.

## Commands

Scan the next 100 item IDs at 10 per second, then look at what was collected:

```text
/tandem scan 10/s
/tandem count
```

| Command                               | What it does                                                     |
| ------------------------------------- | ---------------------------------------------------------------- |
| `/tandem`                             | Prints the commands, as does any unknown subcommand              |
| `/tandem count`                       | Prints what has been collected so far                            |
| `/tandem scan [<n>/s\|<n>/m] [<cap>]` | Scans `<cap>` IDs up from the cursor, `<n>` per second or minute |
| `/tandem scan from <id>`              | Sets the scan cursor to `<id>`; does not start a scan            |
| `/tandem scan stop`                   | Stops the running scan and prints its summary                    |
| `/tandem gear [<slot>] [all]`         | Lists the best known gear you can use, per slot or in one slot   |
| `/tandem rank <item link\|id>`        | Ranks an item in its slot and lists where it drops               |
| `/tandem export`                      | Shows what `make import` would collect from this account         |

`gear`, `rank` and `export` print `Tandem: not available in combat` and do nothing while you are in combat.

### `/tandem scan`

The rate defaults to `10/s` and must lie between `1/m` and `50/s`. The cap defaults to `100` IDs, at most `100000`.
The two tokens may come in either order, so `/tandem scan 500 5/s` and `/tandem scan 5/s 500` are the same. An invalid
or repeated token prints the command list and starts nothing.

The scan resumes where the last one stopped: each ID it queries moves the cursor up by one, with no upper limit. IDs
already in the cache are skipped. The rate is a ceiling: the scan waits while 10 queries are still waiting for a server
reply, and a query unanswered after 5 seconds counts as a timeout. In combat the scan pauses and resumes by itself.

```text
Tandem: scanning 100 IDs from ID 1
Tandem: scan stopped, IDs 1-100 in 10.6s, 100 processed, 0 skipped
  41 hits (12 equippable), 59 misses, 12 deferred, 0 timeouts
```

The numbers are an example. The summary prints when the cap is reached and every reply is in, or on
`/tandem scan stop`. Other messages:

- `Tandem: scan paused in combat`, once per combat.
- `Tandem: scan already running` for a second `scan` while one runs.
- `Tandem: no scan running` for `scan stop` with nothing to stop.
- `Tandem: next scan starts at ID <id>` after `scan from <id>`, or `Tandem: stop the scan before moving the cursor`
  while a scan runs.

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

Before the first scan, `found IDs` reads `none` and the last line reads `Last run: never`. `Unsaved records` counts
items, loot drops, npc names, kills and looted corpses added since the addon loaded; they are lost if the client exits
without saving.

`Kills` and `looted corpses` are this account's own counts (see [Drop rates](#drop-rates)). The line after them says
whether kills are being counted. When the client does not allow it, it reads
`Drop rates use looted corpses: kill counting is <status>`, where `<status>` is one of:

- `unavailable`: the client has no combat log API.
- `blocked`: the client refused to register for the combat log.
- `secret`: the combat log hides who killed what; kill counting turned itself off for this session.

### `/tandem gear`

`/tandem gear` prints, for each slot, the best item you can use that has a known source, then the same note as
`rank`:

```text
Best known gear for level 12 Warrior:
Head: none known
Chest: [Tough Leather Armor], ilvl 14 (upgrade)
...
Ranked by item level, then quality; stats are not considered
```

`/tandem gear <slot>` prints what you wear in that slot, then up to 10 items with their required level:

```text
Best Chest for level 12 Warrior:
Equipped: [Recruit's Vest], ilvl 5
1. [Tough Leather Armor], ilvl 14, level 9 (upgrade)
2. [Rough Leather Vest], ilvl 10, level 5 (upgrade)
Ranked by item level, then quality; stats are not considered
```

The items and numbers are an example. Items print as item links: click one to see the game's tooltip with its icon and
stats. An item the client has not loaded yet prints as `[item #<id>]` and shows its name the next time.

The slot tokens are `head neck shoulder back chest wrist hands waist legs feet finger trinket mainhand offhand twohand
ranged`. They are English on every client; the printed slot names follow the client language. An unknown token prints
`Tandem: unknown slot <token>; use one of: ...`.

By default `gear` lists only items with a known source: a loot entry in your data or in the shipped data. Add `all`, as
in `/tandem gear all` or `/tandem gear chest all`, to include the other cached items, marked `(no known source)`. The
item cache also holds items that cannot be obtained in game.

### `/tandem rank`

`/tandem rank` takes an item link, shift-clicked into chat, or an item ID. It prints the item's rank in its slot among
the items you can use that have a known source, counting the item itself when it is not one of them, whether you can
use it yourself, and up to 5 places it drops:

```text
[Tough Leather Armor] (upgrade): rank 2 of 14 for Chest
  Kobold Miner, Elwynn Forest - drops: 3, 4.2% per looted corpse (upper bound)
  Defias Thug, Elwynn Forest - drops: 1
Ranked by item level, then quality; stats are not considered
```

- An item you cannot use is still ranked, counted in the total, followed by `you cannot use it: level <n> required` or
  `your class cannot use it`, and never marked as an upgrade.
- A one-hand weapon is ranked as a main-hand weapon.
- An item with no known source is ranked too, followed by `no known source`.
- An item that is not cached prints `Tandem: item <id> is not known; scan or loot it first`. Shirts, tabards, bags and
  ammunition print `<item> does not go in a ranked slot`.
- A source with no recorded name prints as `npc #<id>` or `object #<id>`; a map the client does not name prints as
  `unknown map`. More than 5 sources end with `and <n> more sources`.

### `/tandem export`

```text
Tandem export: 42 loot entries, 7 npc names, 120 items, 15 kills, 12 looted corpses
Unsaved records: 16 (saved on /reload or logout)
To contribute: type /reload, then run make import
```

The counts are this account's saved data plus what is not saved yet. `export` only prints: it does not reload the UI or
write anything. See [Importing loot logs](#importing-loot-logs).

## Gear advice

### How gear is ranked

Items are sorted by item level, then by quality, then by item ID. Stats are not considered, so a caster item can rank
high for a warrior. Each command that ranks says so on its last line.

An item is listed only if your class and level can use it:

- Required level: your level must reach the item's required level.
- Armor and weapon types follow the Classic class tables. Cloth and miscellaneous items are open to every class.
  Hunters and shamans wear mail from level 40, warriors and paladins plate from level 40. Shamans' two-hand axes and
  maces need a talent, so they are never suggested. Fishing poles are never suggested.
- Dual wield: warriors and hunters from level 20, rogues from level 10. Their one-hand weapons are listed under both
  `mainhand` and `offhand`, and only they can use off-hand-only weapons. Shields and held-in-off-hand items go in
  `offhand`.
- Rings and trinkets are each one slot, compared against the lower item level of the two you wear.

Marks after an item:

- `(equipped)`: you wear it.
- `(upgrade)`: its item level is above what you wear in that slot; an empty slot counts as item level 0. No mark is
  given when the client does not reveal what you wear, and none in `offhand` while you wield a two-hand weapon.
- `(no known source)`: no loot entry for it (`gear ... all` only).

### Drop rates

A rate is printed only for creatures, from one of two counts per npc:

- Kills: your character's killing blows, read from the combat log when the client allows it (`/tandem count` says
  whether it does). Kills by pets or party members are not counted. Kills in combat are stored when combat ends.
- Looted corpses: each distinct corpse you open a loot window on, gold-only corpses included. Corpses with nothing to
  loot cannot be opened, so a rate per looted corpse is an upper bound.

The rate uses kills when there are any for that npc, else looted corpses, and says which. Your own data and the shipped
data are never added together: the rate takes both its drops and its count from one of them, the one with the larger
count among those that saw this item drop from that npc. When the drops exceed the count, for example after looting
kills made by others, no rate is shown rather than one above 100%. Objects such as chests and nodes get no rate.

### Shipped data

The addon ships `Tandem/Data/Loot.lua`, merged by `make import` from every contribution under `data/contributions/`:
loot, npc names per language, kills, looted corpses and the item cache. Commands use it together with your own
`TandemDB`. For each loot entry's drop count they take the larger of your value and the shipped one, since your data
may already be in the shipped file. Kill and corpse counts are never mixed this way: a drop rate takes its drops and its
count from one dataset, as described under [Drop rates](#drop-rates). For an item record, your own cache wins.
Without the file, the commands use your own data only.

## What is collected

Everything goes into one account-wide table, `TandemDB`, saved as
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`.

| Key       | Content                                                                                     |
| --------- | ------------------------------------------------------------------------------------------- |
| `items`   | Per equippable item ID: item level, required level, quality, equip slot, class and subclass |
| `scan`    | Cursor, non-equippable count, min/max ID found, hits per 1000-ID block, last run            |
| `loot`    | Per item, source and map: npc or object ID, map ID, drops, up to 5 positions                |
| `npcs`    | Npc names by npc ID                                                                         |
| `kills`   | Per npc ID: your character's killing blows on that npc                                      |
| `corpses` | Per npc ID: distinct corpses of that npc you looted                                         |

- Items that exist but cannot be equipped are counted in `scan.nonEquippable`, not stored.
- `scan.lastRun` holds the last run's start time, ID range, rate, elapsed seconds and the counts the summary prints.
- A loot entry is recorded once per source each time a loot window opens outside combat. Its source is a creature
  (`kind = "c"`, npc ID) or a game object (`kind = "o"`, object ID); `kind = "?"` means the client did not say. Map
  and positions are left out when the client does not report them.
- A corpse or object opened again in the same session, such as one you left partly looted, adds no loot and no
  corpse. The addon remembers the last 200 sources; a `/reload` forgets them, so opening one again after a reload
  counts it twice.
- An npc's name is recorded only when the looted corpse is your target or under the mouse.

The client writes `Tandem.lua` only on logout or `/reload`. A crash or a forced quit loses everything collected since
the last save; `/tandem count` shows how many records are waiting. `/reload` after a long scan.

Known metric caveats:

- `nonEquippable` is cumulative across runs and counts the same ID again when a range is rescanned, because
  non-equippable items are not cached.
- `elapsed` includes time the scan spent paused in combat.

## Verify in game

1. Start the client. On the character select screen, open **AddOns** and check that **Tandem** is listed and enabled.
2. Enter the world. The chat window shows:

   ```text
   Tandem loaded
   ```

   On a Traditional Chinese (`zhTW`) client the line reads `Tandem 已載入`, and the AddOns list shows the notes in
   Chinese too. Every other client language gets English.

If the line is missing, check that the addon is enabled and that no Lua error was reported.

### Check data collection

The WoW Forever API is not verified yet, so check each step in game:

1. Log in. Chat shows `Tandem loaded` and no Lua error.
2. With no saved data yet, run `/tandem count`. It shows `0 known items`, `Scan cursor: 1`, `found IDs: none`, `0`
   loot entries and `Last run: never`.
3. Run `/tandem scan 10/s` and wait about 10 to 20 seconds, out of combat, for the two summary lines.
4. Run `/tandem count` again. The cursor is `101` and the last run matches the summary.
5. Type `/reload`, then open `WTF/Account/<account>/SavedVariables/Tandem.lua` and check that `TandemDB` holds `items`
   and `scan.lastRun`.
6. Target a mob, kill it and loot it while it is still targeted. If you were still in combat, close the loot window and
   loot it again once combat ends. `/tandem count` shows more loot entries and, for a mob not seen before, one more
   npc name. Then `/reload` and check `loot` and `npcs` in the file.
7. Run `/tandem scan from 200000`, then a small scan such as `/tandem scan 20`, to see whether IDs that high exist on
   Forever.

Report back the summary lines from steps 3 and 7, the `/tandem count` output, any Lua error, and the
`SavedVariables/Tandem.lua` file.

### Check gear advice

1. Run `/tandem count`. Note which `Drop rates use` line it prints: `kills where counted` means the combat log works on
   Forever; otherwise note the status (`unavailable`, `blocked` or `secret`).
2. Out of combat, kill a mob that drops more than one item and loot only part of it, leaving an item on the corpse.
   `/tandem count` shows one more looted corpse and, if kill counting is on, one more kill. Close the loot window and
   open the same corpse again: neither count changes, and the loot entries stay the same.
3. Run `/tandem gear`. Each slot shows an item or `none known`, and the last line is the stats note. Click an item:
   the game's tooltip opens with its icon and stats.
4. Run `/tandem gear chest`, or another slot you wear something in. The `Equipped:` line shows your item, and items
   with a higher item level are marked `(upgrade)`. Run `/tandem gear chest all` and look for `(no known source)`.
5. Shift-click an item you looted into `/tandem rank`. It prints a rank, its sources with drop counts and, for a
   creature, a rate per kill or per looted corpse. Try `/tandem rank` with a number too.
6. Run `/tandem gear finger` and `/tandem gear offhand`. Check that `(upgrade)` compares with your weaker ring, and
   that no off-hand item is marked while you wield a two-hand weapon.
7. Start a fight and, while in combat, run `/tandem gear`, `/tandem rank 25` and `/tandem export`. Each prints
   `Tandem: not available in combat` and nothing else.
8. Out of combat, run `/tandem export`. It prints the counts and `To contribute: type /reload, then run make import`,
   and the UI does not reload.

Report back the `/tandem count` lines from step 1, whether the counts in step 2 changed as described, and any item
that is listed for your class but cannot be equipped.

## Interface number

`Tandem/Tandem.toc` declares `## Interface: 16001`, confirmed in game on client `1.60.1`. When a client update changes
the number, the AddOns list marks Tandem as out of date and does not load it unless **Load out of date AddOns** is
ticked.

To read the client's current number, type in chat:

```text
/dump (select(4, GetBuildInfo()))
```

Put the printed number in the `## Interface:` line of `Tandem/Tandem.toc`. With a copy, run `make install MODE=copy`
again. Then restart the client: changes to a `.toc` file may not be picked up by `/reload`.

## Icon

The AddOns list shows `Tandem/Media/icon.tga` (64×64, 32-bit with alpha), set by `## IconTexture:` in
`Tandem/Tandem.toc`. Its source image and design history are in `assets/`. Restart the client after changing it.

## Development

```sh
make test
```

This syntax-checks every Lua file under `Tandem/` and `scripts/` with `luac -p`, runs `scripts/addon_test.lua`, and
runs `scripts/wow-dir_test.sh` and `scripts/import_test.sh`. The local `luac` is a newer Lua than the game's Lua 5.1, so
it catches syntax errors only.
`scripts/addon_test.lua` loads the files listed in `Tandem/Tandem.toc`, in order, with stubbed WoW API functions, and
checks the load line for the `enUS`, `zhTW` and an unsupported locale. It also tests `TandemDB` validation and
migration, `/tandem` parsing and output, the scan with a manual timer and stubbed item API, loot, kill and corpse
recording with stubbed loot, combat log, map and unit API, and the gear advice with stubbed class, level and equipped
items. These tests prove the logic only; the client's real API is checked in game.
`scripts/import_test.sh` runs `make import` and `scripts/import.lua` against throwaway saved-variables files and data
folders: two contributors, re-imports, rebuilds, rejected files and the sandbox.

### Importing loot logs

The loot log is crowdsourced: each player's `Tandem.lua` is imported into the repository's `data/` folder, merged into
`Tandem/Data/Loot.lua`, and both are committed. Log out or `/reload` in game first, because the client writes the file
only then. Run `/tandem export` to see what will be collected. Then, from the repository root:

```sh
make import
```

```text
wrote data/contributions/3f2a9c81d0b4.lua (enUS: 42 loot entries, 7 npc names, 120 items, 15 kills, 12 looted corpses)
wrote Tandem/Data/Loot.lua (1 contributors, 120 items, 42 loot rows)
```

The ID and the numbers are an example. `make import` reads every
`<World of Warcraft>/<FLAVOR>/WTF/Account/*/SavedVariables/Tandem.lua` of the detected client and writes:

| File                          | Content                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------- |
| `data/contributions/<id>.lua` | One account's `loot`, `npcs`, `items`, `kills`, `corpses` and locale, replaced on each import |
| `Tandem/Data/Loot.lua`        | Merged from every contribution and loaded by the addon                                        |

The merged file sums loot counts, kills and looted corpses, keeps up to 5 positions per loot entry, keeps npc names per
locale, and takes the union of the item caches; when two contributions disagree on an item, the one whose file name
sorts first wins. It also records how many contributions it merged, as `contributors`. `data/loot.lua` from earlier
versions is no longer written. Contributions written before kills, corpses and items were imported are still read.

- `<id>` is the first 12 hex digits of the SHA-256 of the account folder name. The folder name, the account number, is
  never written or printed, and the same account always gets the same ID.
- The locale is the `SET textLocale` line of `WTF/Config.wtf`, `enUS` when missing. Npc names are stored in the client
  language, so `Tandem/Data/Loot.lua` keeps them under `names[<locale>]`.
- `scan` stays local. `items` is imported, because ranking among a few hundred personally scanned items says little.
- Running it again is safe: each account's contribution is a full snapshot that replaces the last one, so counts are
  never added twice, and the same input gives byte-identical files.
- Each saved-variables file runs in an empty environment, with no functions to call and a limit on how long it may run,
  and its `TandemDB` is checked as the addon checks it on load. A file that fails to parse, raises an error, runs too
  long, is precompiled, has no `TandemDB` or comes from a newer addon version is skipped with a message such as
  `import: <file>: no TandemDB table, skipped`. Invalid entries are dropped with
  `import: <file>: <n> invalid entries ignored`.
- A skipped file does not stop the others. `scripts/import.lua` exits with status 1, and `make import` fails, when no
  file given to it was imported, or when `data/contributions/` holds no valid contribution to merge. `make import`
  also fails, before running the script, when no `Tandem.lua` exists.

Set `WOW_DIR`, `FLAVOR`, `DATA` or `OUT` as for `make install`, for example
`make import DATA=/tmp/tandem-data OUT=/tmp/tandem-data/Loot.lua`. Then review the changes under `data/` and
`Tandem/Data/` with `git diff` and commit them as usual. With the linked install, `/reload` in game picks up the new
`Tandem/Data/Loot.lua`; with a copy, run `make install MODE=copy` first.

`Tandem/Data/Loot.lua` is generated, so never resolve a merge conflict in it by hand. Resolve `data/contributions/`,
then rebuild the merged file from it without reading any saved variables:

```sh
lua scripts/import.lua data Tandem/Data/Loot.lua
```

On success it prints the `wrote Tandem/Data/Loot.lua` line, after a warning on stderr for each contribution it
skipped or trimmed. With no contribution to merge, it prints
`import: data/contributions: no contributions, Tandem/Data/Loot.lua not written` and exits with status 1.

### Translations

Strings go through `ns.L`, keyed by their English text. `Tandem/Locales/enUS.lua` creates the table: a key without a
translation returns itself, so a missing translation shows English. Each other locale file returns early unless
`GetLocale()` matches it, then sets its translations, as `Tandem/Locales/zhTW.lua` does. List a new locale file in
`Tandem/Tandem.toc` after `enUS.lua` and before `Tandem.lua`.

Each commit also runs `luacheck` through pre-commit, configured in `.luacheckrc` for Lua 5.1. It needs `luarocks`
installed (`brew install luarocks`); pre-commit installs `luacheck` itself. Run it on demand with:

```sh
pre-commit run luacheck --all-files
```

When the addon starts calling another WoW API function, add its name to `read_globals` in `.luacheckrc`.
