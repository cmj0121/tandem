# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon. It collects a cache of equippable items, built by scanning item IDs, and a log of
where each item came from: the creatures and objects it dropped from, with kill and looted-corpse counts for drop rates,
the quests that reward it and the vendors that sell it. From that data, merged with what other players contributed, it
suggests the best known gear your character can use and where to get it. It never acts for
the player, it records nothing while you are in combat, and neither its advice commands nor its gear window are
available in combat. Out of combat, it also adds lines to the tooltips of the items it knows.

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
| `/tandem rank <item link\|id>`        | Ranks an item in its slot and lists where to get it              |
| `/tandem export`                      | Shows what `make import` would collect from this account         |
| `/tandem browse [<slot>]`             | Opens or closes a window of all known gear, in every slot or one |
| `/tandem minimap [on\|off]`           | Shows or hides the minimap button; with no argument, toggles it  |
| `/tandem check`                       | Lists, per feature, which client APIs it needs are found         |
| `/tandem map <item link\|id>`         | Opens the world map with a pin on each known place of the item   |
| `/tandem map clear`                   | Removes the map pins                                             |

`gear`, `rank`, `export`, `browse`, `check` and `map` print `Tandem: not available in combat` and do nothing while you are in combat.
`minimap` works in combat too.

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

Before the first scan, `found IDs` reads `none` and the last line reads `Last run: never`. `Loot entries` counts drops,
quest rewards and vendor items together. `Unsaved records` counts items, loot drops, quest rewards, vendor items, npc and
quest names, kills and looted corpses added since the addon loaded; they are lost if the client exits without saving.

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

By default `gear` lists only items with a known source: a drop, quest reward or vendor entry in your data or in the
shipped data (see [Quest rewards and vendors](#quest-rewards-and-vendors)). Add `all`, as
in `/tandem gear all` or `/tandem gear chest all`, to include the other cached items, marked `(no known source)`. The
item cache also holds items that cannot be obtained in game. Items flagged deprecated (see
[Deprecated items](#deprecated-items)) are never listed, with or without `all`.

### `/tandem rank`

`/tandem rank` takes an item link, shift-clicked into chat, or an item ID. It prints the item's rank in its slot among
the items you can use that have a known source, counting the item itself when it is not one of them, whether you can
use it yourself, and up to 5 places to get it:

```text
[Tough Leather Armor] (upgrade): rank 2 of 14 for Chest
  Corina Steele, Elwynn Forest - vendor
  Kobold Miner, Elwynn Forest - drops: 3, 4.2% per looted corpse (upper bound)
  Defias Thug, Elwynn Forest - drops: 1
Ranked by item level, then quality; stats are not considered
```

Quest rewards read `<quest>, <map> - quest reward` and vendor items `<npc>, <map> - vendor`, with no count or
rate. They come before drops, except those seen only by the other faction, which come last and end with
`(Horde only)` or `(Alliance only)`; see [Quest rewards and vendors](#quest-rewards-and-vendors).

- An item you cannot use is still ranked, counted in the total, followed by `you cannot use it: level <n> required` or
  `your class cannot use it`, and never marked as an upgrade.
- A one-hand weapon is ranked as a main-hand weapon.
- An item flagged deprecated (see [Deprecated items](#deprecated-items)) is ranked against the other items, which never
  include a deprecated one, and `this item is deprecated` follows the first line.
- An item with no known source is ranked too, followed by `no known source`.
- An item that is not cached prints `Tandem: item <id> is not known; scan or loot it first`. Shirts, tabards, bags and
  ammunition print `<item> does not go in a ranked slot`.
- Loot from fishing, object 35591 (the Fishing Bobber), prints as `Fishing`. Any other source with no recorded name
  prints as `npc #<id>`, `object #<id>` or `quest #<id>`; a map the client does not name prints as `unknown map`. More
  than 5 sources end with `and <n> more sources`.

### `/tandem browse`

`/tandem browse` opens a window titled `Tandem gear` that lists every known item, best first, ranked as described in
[How gear is ranked](#how-gear-is-ranked); run it again to close the window. `/tandem browse <slot>` opens the window on
one slot, or switches the open window to it. It takes the slot tokens of `gear`, and an unknown token prints the same
`Tandem: unknown slot <token>; use one of: ...` line. When the client has not told the addon your class or level yet,
it prints `Tandem: your class or level is not known yet; try again in a moment` and opens nothing.

The window also opens without a command, from **Tandem** in the minimap's addon compartment, the button by the minimap
that lists addons; WoW Forever has one. Hovering the entry shows a tooltip, `Tandem` over `Click to browse known gear`.
A click opens the window on `All slots`, or closes it when it is open. In combat the click prints
`Tandem: not available in combat` and opens nothing; while your class or level is not known yet it prints
`Tandem: your class or level is not known yet; try again in a moment` and opens nothing.

A round Tandem button on the edge of the minimap does the same, next to the compartment entry or in its place on a client
without one. It is shown by default, at the lower left until you move it. Its tooltip adds `Drag to move this button`:
drag it with the left mouse button to move it around the minimap. Its place is kept in `TandemDB.ui` as an angle and
restored after a `/reload` or the next login.

Hide the button with `/tandem minimap off` or by unticking `Show minimap button` in the window, and bring it back with
`/tandem minimap on` or the same box; `/tandem minimap` alone toggles it. The command prints
`Tandem: minimap button hidden` or `Tandem: minimap button shown`, and the box follows whichever you use. The choice is
kept in `TandemDB.ui` and applied at the next login.

Along the top of the window:

- A slot dropdown: `All slots`, then each slot by name. `All slots` lists each item once, under its first slot, so a
  one-hand weapon appears once, as a main-hand weapon. When your class dual-wields at your level, such a one-hander is
  marked against both hands there: `(equipped)` when you wear it in either hand, and `(upgrade)` when its item level is
  above the lower of the two hands whose item level is known. In the `Main hand` and `Off hand` views it is compared
  with that hand only.
- A quality dropdown: `All qualities`, then `Poor`, `Common`, `Uncommon`, `Rare`, `Epic` and `Legendary`, each in its
  quality colour. Picking a quality lists only the items of that quality.
- The number of listed items, as `<n> items`.

Under them, three boxes:

- `Usable only`, ticked when the window is first opened. Untick it to also list the items your class or level cannot
  use; they are dimmed.
- `Hide deprecated`, ticked when the window is first opened. Untick it to also list the items flagged deprecated (see
  [Deprecated items](#deprecated-items)); their name is followed by a grey `(deprecated)` mark.
- `Show minimap button`, ticked while the minimap button is shown; untick it to hide the button, as
  `/tandem minimap off` does.

The slot is set each time the window opens: `All slots`, or the slot given to `/tandem browse <slot>`. The quality
choice, `Usable only` and `Hide deprecated` are kept while the client runs but never saved: after a `/reload` or logout
the quality reads `All qualities` and both boxes are ticked again.

Below the boxes, a scan bar runs the same scan as [`/tandem scan`](#tandem-scan):

- `Rate` and `Cap` boxes, which read `10/s` and `100` when the window is first opened. They follow the rules of the
  command's tokens: a rate of `<n>/s` or `<n>/m` between `1/m` and `50/s`, and a cap from `1` to `100000`. An empty box
  takes the default. Enter or Escape leaves a box without closing the window. What you type is kept until a `/reload`
  or logout but never saved; after one, the boxes read `10/s` and `100` again.
- `Start`, which scans from the cursor with those values. While a scan runs, whether started here or with
  `/tandem scan`, the button reads `Stop` and stops it as `/tandem scan stop` does.
- A status line. While a scan runs it reads `Scanning: <n> of <cap> IDs, <hits> found, next ID <id>` and is updated
  every second while the window is open; otherwise it reads `<n> known items, next scan from ID <id>`.

A scan started from the bar prints the same chat lines as the command, such as `Tandem: scanning <n> IDs from ID <id>`
and the summary. An invalid value prints the command's usage line and starts nothing:

```text
  /tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)
```

In combat, `Start` and `Stop` print `Tandem: not available in combat` and do nothing. When a scan ends, by reaching its
cap or by being stopped, an open window lists the items again, so items the scan found show up without reopening it.

Each row shows:

- The item's icon, or a question mark when the client gives none.
- Its name in its quality colour, followed in grey by the marks of [How gear is ranked](#how-gear-is-ranked):
  `(equipped)`, `(upgrade)` or `(no known source)`. Like `gear ... all`, the window lists items with no known source too.
  A dimmed item is never marked `(upgrade)`.
- Its item level, then a level. Normally that is the item's required level. When your level is too low to use the
  item, it is the level from which you could, in red: the higher of the item's required level and the level your class
  learns that armor or weapon type, so mail for a hunter shows `40`. An item your class cannot use at all is dimmed but
  never red.

An item the client has not loaded yet shows as `item #<id>` in its quality colour. The window asks the client for it,
and the names fill in a moment after they arrive, without reopening the window. An item already flagged deprecated in
its record, in your data or in the shipped data, is hidden whether its name is loaded or not. One not flagged yet is
listed even while `Hide deprecated` is ticked, since its name is not known yet. If the name that arrives marks it
deprecated, the row
shows the grey `(deprecated)` mark and leaves the list the next time the list is rebuilt, for example when you change a
filter, rather than jumping away under the mouse.

Hover a row to see the game's tooltip for the item. Click a row to select it: the pane at the bottom shows the item's
link and up to 5 places to get it, in the same lines and order as `rank`, ending with `and <n> more sources` when there
are more. With nothing selected, the pane reads `Select an item to see where it drops`. The `Show on map` button at
the pane's top right does what `/tandem map` does for the selected item; it is greyed out while nothing is selected, and
selecting another item removes the pins of the earlier one.

Drop an item on the window to look it up: pick it up from your bags or your character sheet, then drag it onto the list
or the window's background, or click there with it. The item leaves the cursor and stays where it was. The dropdown
switches to the item's slot, the item is selected and scrolled to, and the pane shows its sources. When you cannot
use the item, `Usable only` is unticked so that its row is listed, dimmed; a usable item leaves the box as it is. In
the same way, a deprecated item unticks `Hide deprecated`, and an item of another quality than the chosen one sets the quality
dropdown back to `All qualities`. An item with no ranked slot, such as a shirt, switches the list to `All slots`, where
it is not listed, and the pane still shows its sources; the filters stay as they are. An item that is not cached
selects nothing and leaves the slot as it is; the pane reads `Tandem: item <id> is not known; scan or loot it first`.
Anything else on the cursor, such as a spell, is ignored and stays on the cursor. In combat a dropped item prints
`Tandem: not available in combat` and stays on the cursor.

The window is not available in combat. `/tandem browse` prints `Tandem: not available in combat` and opens nothing, and
an open window closes when combat starts; it stays closed afterwards. Escape closes it too. Drag the window with the
left mouse button to move it. Its position is kept in `TandemDB.ui` and restored after a `/reload` or the next login;
until you first move it, it opens in the middle of the screen.

The window opens 640 wide and 620 high. Drag the grip at its bottom right corner to resize it, from 520 × 480 up to
1200 × 1000, or the size of the screen when that is smaller. The list and the item names widen with the window, and the
pane stays at the bottom. Whenever you move or resize the window, its size is kept in `TandemDB.ui` with the position
and restored after a `/reload` or the next login, brought back within those bounds. On a client that cannot resize
frames, there is no grip and the window keeps its default size.

### `/tandem export`

```text
Tandem export: 42 loot entries, 7 npc names, 120 items, 15 kills, 12 looted corpses
Unsaved records: 16 (saved on /reload or logout)
To contribute: type /reload, then run make import
```

The counts are this account's saved data plus what is not saved yet. `export` only prints: it does not reload the UI or
write anything. See [Importing loot logs](#importing-loot-logs).

### `/tandem check`

```text
Tandem API check:
Item tooltip: ok (TooltipDataProcessor.AddTooltipPostCall ok, Enum.TooltipDataType.Item ok)
Item stats: ok (C_Item.GetItemStats missing, GetItemStats ok)
```

One line per feature, `ok` when every API it needs is found, followed by each API and whether it was found. Where
either of two APIs will do, both are listed and one found is enough. The features are `Item tooltip`,
`Quest sources`, `Vendor sources`, `Map pins`, `Map waypoint`, `Quest reward pick`, `Upgrade alert` and `Item stats`.
A feature whose API is missing stays off instead of raising an error.

### `/tandem map`

`/tandem map <item link|id>` takes an item ID or a shift-clicked item link, as `rank` does. It opens the world map on
the map of the item's first source, in the order `rank` lists them, that has a known place, and puts a pin on each
place where the item was seen: up to 50, each place once. A pin shows only while its own map is shown, so switch the
map to see the pins of the other sources. Hover a pin to see the source's name; click it to set the game's waypoint
there and track it, which prints `Tandem: waypoint set to <source>`.

Pinning another item replaces the pins, and `/tandem map clear` removes them, printing `Tandem: map pins cleared`.
Pins are not projected onto the continent or world map, and they grow and shrink with the map's zoom.

When nothing can be pinned, it says why and opens nothing:

- `Tandem: map pins are not available on this client; see /tandem check` when the `Map pins` APIs are missing.
- `Tandem: item <id> is not known; scan or loot it first` for an item with neither a record nor a source.
- `Tandem: no known map position for item <id>` when no source has a place, such as one seen on an unknown map.

A click on a pin prints `Tandem: this map does not take a waypoint` on a map that refuses waypoints, and
`Tandem: waypoints are not available on this client; see /tandem check` when the `Map waypoint` APIs are missing.
In combat the command, the button and a pin click print `Tandem: not available in combat` and do nothing.

## Gear advice

### How gear is ranked

Items are sorted by item level, then by quality, then by item ID. Stats are not considered, so a caster item can rank
high for a warrior. Each command that ranks says so on its last line.

`gear` lists, and `rank` ranks against, only items your class and level can use; the browse window does too while
`Usable only` is ticked. An item is usable when:

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
- `(no known source)`: no drop, quest reward or vendor entry for it (`gear ... all` and the browse window only).

### Item tooltip

Out of combat, hovering an item that Tandem knows adds lines to the bottom of the game's tooltip. This works wherever
the item's tooltip is the game's main tooltip, such as in your bags, on your character sheet and in the browse window,
and in the tooltip that opens when you click an item link in chat. The comparison tooltips that show what you wear are
left alone.

- In Tandem blue, `Tandem: rank <n> of <total> for <slot>`, followed by the marks of
  [How gear is ranked](#how-gear-is-ranked): `(equipped)`, `(upgrade)` or `(no known source)`. The rank is the one
  `/tandem rank` prints. A one-hand weapon is ranked as a main-hand weapon; when your class dual-wields at your level,
  it is marked against both hands, as in the browse window's `All slots`. An item with no ranked slot, such as a shirt,
  gets no rank line.
- In red, when you cannot use the item, `Tandem: you cannot use it: level <n> required` or
  `Tandem: your class cannot use it`.
- In light grey, the item's first source, in the order of `rank`:
  - a quest reward or vendor your faction has seen: `Tandem: reward from <quest>, <map>` or
    `Tandem: sold by <npc>, <map>`, with no rate;
  - else the source it dropped from most often: `Tandem: drops from <source>, <map>`, then `(<rate>% per kill)` or
    `(up to <rate>%)` when a rate is known (see [Drop rates](#drop-rates));
  - else a quest reward or vendor seen only by the other faction, as above followed by `(Horde only)` or
    `(Alliance only)`.

  Then `(+<n> more)` when other sources are known. Sources are named as in `rank`. An item with no known source has no
  such line.

For example:

```text
Tandem: rank 2 of 14 for Chest (upgrade)
Tandem: sold by Corina Steele, Elwynn Forest (+2 more)
```

An item that only drops reads, for example, `Tandem: drops from Kobold Miner, Elwynn Forest (up to 4.2%) (+1 more)`.

An item flagged deprecated gets one grey line, `Tandem: deprecated item`, and nothing else. An item Tandem does not
know adds nothing, and in combat no line is added and nothing is printed. Nothing is added either while the client has
not told the addon your class or level. On a `zhTW` client the lines are in Chinese.

### Quest rewards and vendors

Besides drops, Tandem records the quests that reward an item and the vendors that sell it:

- Quest rewards: when a quest window shows its rewards, at the quest giver (`QUEST_DETAIL`) or on turn-in
  (`QUEST_COMPLETE`), each reward and choice item is recorded under that quest, with the quest's title.
- Vendor items: when a merchant window opens (`MERCHANT_SHOW`), and again on each `MERCHANT_UPDATE` since item links can
  arrive late, each item the merchant lists is recorded under that merchant, with its name.

Only equippable items are recorded. One missing from the item cache is cached too, at once or as soon as the client
sends its details, so it appears in `gear` and the browse window without a scan. Nothing is recorded in combat, while
recording is off for a newer schema, when the client lacks the quest or merchant API, or when it does not tell your
faction.

Each quest or vendor is recorded once per item per account: seeing it again adds nothing, so its count stays 1. It keeps
the map and position where you first saw it, at the quest giver, the turn-in or the merchant, and it is listed once
whatever map it was seen on. In the shipped data its count is the number of contributors who saw it; that count only
orders such sources among themselves and is never printed. Quest rewards and vendor items get no rate and no price.

Each entry also records which factions have seen it, Alliance, Horde or both, from the faction of the characters that
opened the window. Sources are listed in this order, by count within each group:

1. Quest rewards and vendor items your faction has seen.
2. Drops.
3. Quest rewards and vendor items seen only by the other faction, marked `(Horde only)` or `(Alliance only)`.

While the client does not tell your faction, no source is marked and all quest rewards and vendor items come first.

| Source       | `rank` and the browse pane      | Item tooltip                         |
| ------------ | ------------------------------- | ------------------------------------ |
| Quest reward | `<quest>, <map> - quest reward` | `Tandem: reward from <quest>, <map>` |
| Vendor item  | `<npc>, <map> - vendor`         | `Tandem: sold by <npc>, <map>`       |

A quest is named from your data, else from the shipped quest names in the client language, else from the client's
quest log, else `quest #<id>`. A vendor is named like any npc, else `npc #<id>`. On a `zhTW` client the lines and the
faction mark are in Chinese, such as `（僅限部落）`.

A quest or vendor source means the item is known to come from there, not that you can get it now: a vendor may have
limited stock or ask for reputation, and a quest may follow a chain, be one-off, or need a class or level.

### Deprecated items

Items whose name starts with `Deprecated`, in any case and after any leading spaces, are flagged deprecated. The item
cache stores no names, so the flag is stored with the item record, as an optional seventh field. It is set when a scan
caches the item, and later whenever Tandem sees a name the client already holds for a known item: rows of the browse
window, the item tooltip, and an item dropped on the window. Flagging an item known only from the shipped data stores a
flagged copy of its record in your own `items`, so the next `make import` ships the flag; it counts in your known items
and in `Unsaved records`.

`/tandem gear` never lists a flagged item, `/tandem rank` says `this item is deprecated`, the browse window hides them
while `Hide deprecated` is ticked and otherwise marks them `(deprecated)`, and their item tooltip reads
`Tandem: deprecated item`. This holds for an item already flagged in its record, in your data or in the shipped data,
whether or not the client has loaded its name. An item not flagged yet whose name the client has not loaded is not
known to be deprecated and is treated as any other.

### Drop rates

A rate is printed only for creatures, from one of two counts per npc:

- Kills: your character's killing blows, read from the combat log when the client allows it (`/tandem count` says
  whether it does). Kills by pets or party members are not counted. Kills in combat are stored when combat ends.
  WoW Forever 1.60.1 does not allow it: `CombatLogGetCurrentEventInfo` and `C_CombatLog.GetCurrentEventInfo` are
  absent and registering for the combat log is blocked, so `count` reports `unavailable`. Experience gives no kill
  count either: Forever does not deliver `CHAT_MSG_COMBAT_XP_GAIN` to addons, although the experience line shows in
  chat, and `PLAYER_XP_UPDATE` cannot be tied to the killed mob, because when it arrives the target no longer reads as
  dead. So Forever has no kill count, and every rate there is per looted corpse.
- Looted corpses: each distinct corpse you open a loot window on, gold-only corpses included. Corpses with nothing to
  loot cannot be opened, so a rate per looted corpse is an upper bound.

The rate uses kills when there are any for that npc, else looted corpses, and says which. Your own data and the shipped
data are never added together: the rate takes both its drops and its count from one of them, the one with the larger
count among those that saw this item drop from that npc. When the drops exceed the count, for example after looting
kills made by others, no rate is shown rather than one above 100%. Objects such as chests, nodes and fishing get no
rate, nor do quest rewards and vendor items.

### Shipped data

The addon ships `Tandem/Data/Loot.lua`, merged by `make import` from every contribution under `data/contributions/`:
loot (drops, quest rewards and vendor items), npc and quest names per language, the factions that saw each quest reward
and vendor item, kills, looted corpses and the item cache. Commands use it together with your own
`TandemDB`. For each loot entry's drop count they take the larger of your value and the shipped one, since your data
may already be in the shipped file. Kill and corpse counts are never mixed this way: a drop rate takes its drops and its
count from one dataset, as described under [Drop rates](#drop-rates). A quest reward or vendor item seen in both
becomes one source with the factions of both. For an item record, your own cache wins.
Without the file, the commands use your own data only.

## What is collected

Everything goes into one account-wide table, `TandemDB`, saved as
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`.

| Key       | Content                                                                                                           |
| --------- | ----------------------------------------------------------------------------------------------------------------- |
| `items`   | Per equippable item ID: item level, required level, quality, equip slot, class, subclass; a 7th `1` if deprecated |
| `scan`    | Cursor, non-equippable count, min/max ID found, hits per 1000-ID block, last run                                  |
| `loot`    | Per item, source and map: npc, object, quest or merchant ID, map ID, drops, up to 5 positions; factions           |
| `npcs`    | Npc names by npc ID, merchants included                                                                           |
| `quests`  | Quest titles by quest ID                                                                                          |
| `kills`   | Per npc ID: your character's killing blows on that npc                                                            |
| `corpses` | Per npc ID: distinct corpses of that npc you looted                                                               |
| `ui`      | `window`: anchor, relative point, x, y, width, height; `minimap`: button angle; `minimapHidden`: `true` if hidden |

- Items that exist but cannot be equipped are counted in `scan.nonEquippable`, not stored.
- `scan.lastRun` holds the last run's start time, ID range, rate, elapsed seconds and the counts the summary prints.
- A loot entry is recorded once per source each time a loot window opens outside combat. Its source is a creature
  (`kind = "c"`, npc ID) or a game object (`kind = "o"`, object ID); `kind = "?"` means the client did not say. Map
  and positions are left out when the client does not report them.
- A quest reward (`kind = "q"`, quest ID) or vendor item (`kind = "v"`, the merchant's npc ID) is recorded once, with
  count `1`, one position and `factions`: `1` Alliance, `2` Horde, `3` both (see
  [Quest rewards and vendors](#quest-rewards-and-vendors)).
- A corpse or object opened again in the same session, such as one you left partly looted, adds no loot and no
  corpse. The addon remembers the last 200 sources; a `/reload` forgets them, so opening one again after a reload
  counts it twice.
- An npc's name is recorded only when the looted corpse is your target or under the mouse.
- `ui` holds only where the browse window and the minimap button sit, the window's size and whether the button is
  hidden; the angle is saved once you drag the button, the size whenever you move or resize the window, and `minimapHidden` only
  while the button is hidden. It is not counted in `Unsaved records`, and an invalid position, angle or flag is
  dropped on load. An invalid size is dropped alone, and the position is kept.

`TandemDB.schemaVersion` is `3`. Saved data from schema 2 is migrated on load, gaining an empty `quests`. Saved data
from a newer schema is kept as it is, and nothing is recorded until the addon is updated.

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
8. Out of combat, talk to a quest giver whose quest rewards equippable items, and open a vendor that sells weapons or
   armor. `/tandem count` shows more loot entries, and `Unsaved records` rises. Close and reopen the vendor: the loot
   entries stay the same. Then `/reload` and check that `loot` holds entries with `kind = "q"` and `kind = "v"`, and
   `quests` the quest's title.

Report back the summary lines from steps 3 and 7, whether step 8 recorded anything, the `/tandem count` output, any
Lua error, and the `SavedVariables/Tandem.lua` file.

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

### Check the browse window

1. Out of combat, run `/tandem browse`. A window titled `Tandem gear` opens in the middle of the screen: the slot
   dropdown reads `All slots`, the quality dropdown `All qualities`, `Usable only` and `Hide deprecated` are ticked,
   the item count is at the top right, the list fills the middle, and the pane at the bottom reads
   `Select an item to see where it drops`.
2. Untick `Usable only` and pick `All slots`, so the list holds up to about 1.5k rows. Scroll it with the scroll bar on its
   right and with the mouse wheel over it; both move smoothly to the end and back. Note whether a scroll bar shows at
   all.
3. Pick `Chest` in the dropdown. Only chest items are listed, the count changes, and the item you wear, if it is a
   known item, is marked `(equipped)`. Close the window with `/tandem browse`, then run `/tandem browse chest`: it opens
   with `Chest` selected in the dropdown.
4. Hover a row: the game's tooltip shows the item's stats, and it closes when the mouse leaves.
5. Click a row: it is highlighted, and the bottom pane shows the item's link and where it drops. An item with more than
   5 sources ends with `and <n> more sources`, an item you fished lists `Fishing`, and an item with no loot entry shows
   `no known source`.
6. Rows that read `item #<id>` change to the item's name within a moment, without reopening the window.
7. With `Usable only` unticked, items your class or level cannot use are dimmed. An item your level is too low for
   shows in red the level from which you could use it, such as `40` for mail on a level 20 hunter; an item your class
   can never use is not red. Tick `Usable only` again: they disappear and the count drops.
8. Drag the window elsewhere, type `/reload`, then run `/tandem browse`: it opens where you left it.
9. Press Escape: the window closes.
10. Open the window and start a fight: it closes as combat starts. While still in combat, run `/tandem browse`: it
    prints `Tandem: not available in combat` and nothing opens.
11. Out of combat, open the addon compartment by the minimap: it lists **Tandem**. Hover the entry: a tooltip reads
    `Tandem` and `Click to browse known gear`, and it closes when the mouse leaves. Click the entry: the window opens on
    `All slots`. Click it again: the window closes. A Tandem button shows on the minimap's edge as well, also on a
    client without the compartment; check the same with it, and that its tooltip also reads `Drag to move this button`.
    Drag it around the minimap, type `/reload`, and check that it is where you left it. Run `/tandem minimap off`: chat
    shows `Tandem: minimap button hidden`, the button disappears, and `Show minimap button` in the window is unticked.
    Type `/reload`: the button stays hidden. Tick `Show minimap button`: the button comes back.
12. Open the window. Below the dropdown, the boxes read `10/s` and `100`, the button reads `Start`, and the status line
    reads `<n> known items, next scan from ID <id>`, with the known items and the scan cursor of `/tandem count`.
13. Type `20` in `Cap` and click `Start`. Chat shows `Tandem: scanning 20 IDs from ID <id>`, the button reads `Stop`,
    and the status line counts up every second. When the summary prints, the button reads `Start` again, the status
    line shows the new cursor, and the list is refreshed.
14. Type `1000` in `Cap`, click `Start`, then `Stop`: the summary prints and the button reads `Start`. Close the window,
    run `/tandem scan 20` and reopen the window while it runs: the status line shows its progress.
15. Type `abc` in `Rate`, or `0` in `Cap`, and click `Start`: chat shows
    `/tandem scan [<n>/s|<n>/m] [<cap>] - scan item IDs (default 10/s, 100 IDs)` and no scan starts. Click in a box
    and press Escape: the box loses focus and the window stays open. Press Escape again: the window closes.
16. Open the window, pick up an item from your bags and drop it on the list. It stays in your bag and leaves the
    cursor, the dropdown switches to its slot, its row is selected, and the pane shows where it drops. Do the same
    with an item from your character sheet, and with a known item your class cannot use while `Usable only` is ticked:
    the box unticks and the row is dimmed.
17. Drop an item that is not cached, such as a quest item: the pane reads
    `Tandem: item <id> is not known; scan or loot it first`.
18. Pick up a spell from your spellbook and drop it on the window: nothing changes and the spell stays on the cursor.
19. Drag the grip at the bottom right corner: the window grows and shrinks, but not below 520 × 480 or above
    1200 × 1000, and the list and item names follow its width. Make it wider, move it, type `/reload`, then run
    `/tandem browse`: it opens at the same place and size.
20. Pick `Rare` in the quality dropdown: only blue (rare) items are listed, and the count drops. Pick
    `All qualities` again. With `Rare` picked, drop a common item on the window: the dropdown reads `All qualities`.
21. Untick `Hide deprecated`: items whose name starts with `Deprecated` appear, marked `(deprecated)` in grey, and the
    count rises. Tick it again: they disappear. With it ticked, drop a deprecated item on the window: the box unticks.
22. Pick `All slots` while your class can dual-wield, and look at a one-hand weapon: it is marked `(equipped)` when
    you wear it in your off hand, and `(upgrade)` when it beats the weaker of your two weapons.
23. Run `/tandem gear` and `/tandem rank <id>` with the ID of a deprecated item: `gear` never lists it, and `rank`
    prints `this item is deprecated` after the rank line.

Report back whether the scroll bar showed, how scrolling felt in step 2, whether the compartment entry and the minimap
button showed in step 11, whether the grip showed in step 19, any Lua error, and any text that does not fit in the
window, at its smallest size too.

### Check the item tooltip

1. Out of combat, hover an item in your bags that Tandem knows and that goes in a ranked slot. Below the game's lines,
   a blue line reads `Tandem: rank <n> of <total> for <slot>`, with `(equipped)`, `(upgrade)` or `(no known source)`
   as the browse window shows for the same item.
2. Hover an item you cannot use: a red line reads `Tandem: you cannot use it: level <n> required` or
   `Tandem: your class cannot use it`.
3. Hover an item you looted from a mob: a grey line reads `Tandem: drops from <source>, <map>`, with a rate when one is
   known and `(+<n> more)` when it has other sources. It matches the first source `/tandem rank` lists.
4. Hover an item a vendor sells, or a quest reward you have seen: the grey line reads `Tandem: sold by <npc>, <map>` or
   `Tandem: reward from <quest>, <map>`, with no rate, even when the item also drops. `/tandem rank` lists the same
   source first, as `- vendor` or `- quest reward`.
5. Hover the items on your character sheet and the rows of the browse window: they get the same lines. Shift-click an
   item into chat and click the link: the tooltip that opens gets them too. A comparison tooltip shown next to it gets
   none.
6. Hover a deprecated item, such as one listed after unticking `Hide deprecated`: the only Tandem line is
   `Tandem: deprecated item`, in grey.
7. Hover an item Tandem does not know, such as a quest item: no Tandem line is added.
8. Start a fight and hover the same items while in combat: no Tandem line is added and nothing is printed in chat.

Report back any item whose tooltip line does not match `/tandem rank`, whether the line showed on the chat link
tooltip in step 5, and any Lua error.

### Check the client APIs

The tooltip, the quest and vendor sources and the map pins, and the quest reward pick and upgrade alert still to come,
use APIs that are not verified on Forever. One pass of `/tandem check` tells which of them the client has:

1. Out of combat, run `/tandem check`. Chat shows `Tandem API check:` and eight lines, one each for `Item tooltip`,
   `Quest sources`, `Vendor sources`, `Map pins`, `Map waypoint`, `Quest reward pick`, `Upgrade alert` and
   `Item stats`, each followed by `ok` or `missing` and its APIs.
2. Hand in a quest that offers a choice of rewards and, with the reward window open, run `/tandem check` again. Note
   whether the `Quest reward pick` line now finds `QuestInfoRewardsFrame.RewardButtons`,
   `QuestInfoRewardsFrameQuestInfoItem1` or `QuestRewardItem1`: the reward buttons may only exist once the window has
   been shown.
3. Open the world map and run `/tandem check` once more: the `Map pins` line stays the same.
4. Start a fight and, while in combat, run `/tandem check`: it prints `Tandem: not available in combat` and nothing
   else.
5. If `Item tooltip` is `ok`, run the steps of [Check the item tooltip](#check-the-item-tooltip). If `Quest sources` or
   `Vendor sources` is `ok`, run step 8 of [Check data collection](#check-data-collection) and step 4 of the tooltip
   check. If `Map pins` is `ok`, run [Check the map pins](#check-the-map-pins).

Report back every line of steps 1 and 2 as printed, and any Lua error.

### Check the map pins

1. Out of combat, run `/tandem rank <item link>` for an item you looted from a mob, so you know its sources and maps.
2. Run `/tandem map <item link>` with the same link. The world map opens on the map of the first listed source with a
   known place, and small Tandem icons mark where the item was seen. Nothing is printed.
3. Hover a pin: the tooltip shows the source's name and `Click to set a waypoint`. Click it: chat shows
   `Tandem: waypoint set to <source>`, the waypoint appears on the map and the minimap, and it is tracked.
4. Switch the world map to another zone and back: the pins show only on their own map. If the item has a source on
   another map, open that map and check its pins.
5. Open `/tandem browse`, select an item and click `Show on map`: the map opens with that item's pins. Select another
   item: the pins are gone.
6. Run `/tandem map clear`: chat shows `Tandem: map pins cleared` and the pins are gone.
7. Run `/tandem map` for an item that has no known place, such as one only seen on map 0: chat shows
   `Tandem: no known map position for item <id>` and the map does not open.
8. Start a fight and, while in combat, run `/tandem map <item link>` and click a pin left on the map: each prints
   `Tandem: not available in combat` and nothing else happens.

Report back whether the pins sit on the right spots, whether they hide behind other map icons, whether the waypoint
was set, the map ID of any map that refused it, and any Lua error.

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
recording with stubbed loot, combat log, map and unit API, quest reward and vendor recording with stubbed quest and
merchant API, the gear advice with stubbed class, level and equipped
items, the browse window with stubbed frames, widgets and tooltip, and the item tooltip line with a stubbed tooltip
API. These tests prove the logic only; the client's
real API is checked in game.
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
wrote data/contributions/3f2a9c81d0b4.lua (enUS: 42 loot entries, 7 npc names, 3 quest names, 120 items, 15 kills, 12 looted corpses)
wrote Tandem/Data/Loot.lua (1 contributors, 120 items, 42 loot rows)
```

The ID and the numbers are an example. `make import` reads every
`<World of Warcraft>/<FLAVOR>/WTF/Account/*/SavedVariables/Tandem.lua` of the detected client and writes:

| File                          | Content                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------ |
| `data/contributions/<id>.lua` | One account's `loot`, `npcs`, `quests`, `items`, `kills`, `corpses` and locale |
| `Tandem/Data/Loot.lua`        | Merged from every contribution and loaded by the addon                         |

The merged file sums loot counts, kills and looted corpses, keeps up to 5 positions per loot entry, keeps npc and quest
names per locale, and takes the union of the item caches. A quest reward or vendor item becomes one row whatever map
each contribution saw it on: it keeps the lowest map ID and that map's positions, sums the counts, so the count is the
number of contributors who saw it, and combines the factions in `S.factions`, keyed `"<item>:<kind>:<id>:<map>"`.
When two contributions disagree on an item, the one whose file name sorts first wins, except that the item is flagged
deprecated when any contribution flags it. It also records how many contributions it merged, as `contributors`.
`data/loot.lua` from earlier versions is no longer written. Contributions written before kills, corpses, items and
quests were imported are still read.

- `<id>` is the first 12 hex digits of the SHA-256 of the account folder name. The folder name, the account number, is
  never written or printed, and the same account always gets the same ID.
- The locale is the `SET textLocale` line of `WTF/Config.wtf`, `enUS` when missing. Npc names and quest titles are
  stored in the client language, so `Tandem/Data/Loot.lua` keeps them under `names[<locale>]` and
  `questNames[<locale>]`.
- `scan` and `ui` stay local. `items` is imported, because ranking among a few hundred personally scanned items says little.
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
