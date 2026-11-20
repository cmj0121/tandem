# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon that tells you when an item beats what you wear. It judges each item in your bags,
in the loot window and among quest rewards from what the client says about it right now: its slot, required level,
armor or weapon type, tooltip requirements and stats, weighted for your class and talent tree. An upgrade gets a red
border and a green up arrow on its bag or loot button, one line in chat and a green line in its tooltip. Tandem also
marks the best quest reward choice and flags out-of-date spell ranks on your action bars. On request it arranges your
screen around the action bars, with an XP bar, a bag row, a mute button, an eat and drink button, a map info line and,
for a Shaman, a weapon enchant proc rate. It pins WoW Forever's Library Books your level reaches on
the world map and tells you in chat when you pass one. It never acts for the player: it only advises, and it saves
nothing but your own stat weights, what your class trainer teaches, its layout state and mode, your class macro pick,
your weapon enchant proc counts and whether book hints are on.

## Install

From the repository root:

```sh
make install
```

This links the repository's `Tandem/` folder into the client as
`<World of Warcraft>/_forever_/Interface/AddOns/Tandem`, so edits to Lua files take effect after `/reload` in game.
Running it again when the link is already in place does nothing.

To remove it:

```sh
make uninstall
```

### Finding the client

`make install` and `make uninstall` locate the `World of Warcraft` folder with `scripts/wow-dir.sh`. A folder
qualifies only if it contains `<FLAVOR>/Interface/AddOns`. The search order is:

1. `WOW_DIR`, if set. If it does not qualify, the install fails rather than searching further.
2. `/Applications/World of Warcraft`, `~/Applications/World of Warcraft` and `/Users/Shared/World of Warcraft`.
3. Spotlight (`mdfind`) for any folder named `World of Warcraft`.

If nothing qualifies, the script exits with an error that lists every place it searched.

### Overrides

| Variable  | Default       | Meaning                                                                             |
| --------- | ------------- | ----------------------------------------------------------------------------------- |
| `WOW_DIR` | auto-detected | The `World of Warcraft` folder that contains `_forever_`, not the flavor dir        |
| `FLAVOR`  | `_forever_`   | The client flavor folder inside `WOW_DIR`; `_classic_beta_` targets the beta client |
| `MODE`    | `link`        | `copy` copies the addon instead of linking it                                       |

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

| Command                                | What it does                                                            |
| -------------------------------------- | ----------------------------------------------------------------------- |
| `/tandem`                              | Prints the commands, as does any unknown subcommand                     |
| `/tandem check`                        | Lists, per feature, which client APIs it needs are found                |
| `/tandem weights`                      | Shows the stat weights of your talent tree                              |
| `/tandem weights spec <1\|2\|3\|auto>` | Picks the talent tree the weights are for, or follows talents           |
| `/tandem weights set <stat> <number>`  | Sets your own weight for one stat of the active tree; 0 ignores it      |
| `/tandem weights reset`                | Drops your own weights for the active tree                              |
| `/tandem layout`                       | Prints whether Tandem's [layout](#layout) is on or off                  |
| `/tandem layout <on\|off>`             | Turns the layout on, or off to bring your previous layout back          |
| `/tandem minimap [on\|off]`            | Shows or hides the [minimap button](#minimap-button); alone, toggles it |
| `/tandem books`                        | Prints whether [library book](#library-books) hints are on or off       |
| `/tandem books <on\|off>`              | Turns the book pins and the nearby alert on or off                      |
| `/tandem books near`                   | Prints your map id and position and the nearest book you can reach      |
| `/tandem killers`                      | Lists the [enemy players](#killers) seen targeting you at your death    |
| `/tandem killers forget <name>`        | Drops one name from that list                                           |
| `/tandem killers clear`                | Empties that list                                                       |
| `/tandem debug [on\|off\|snap]`        | Records layout traces for the developer; see [Debug log](#debug-log)    |

`check` and `weights` print `Tandem: not available in combat` and do nothing while you are in combat. `layout` waits
for combat to end instead; `minimap`, `books` and `killers` work in combat
too.

### `/tandem check`

```text
Tandem API check:
Item tooltip: ok (TooltipDataProcessor.AddTooltipPostCall ok, Enum.TooltipDataType.Item ok)
Item stats: ok (C_Item.GetItemStats missing, GetItemStats ok)
...
Probe: LootButton1 present
Probe: LootFrame.ScrollBox missing
```

One line per feature, `ok` when every API it needs is found, followed by each API and whether it was found. Where
either of two APIs will do, both are listed and one found is enough. The features are `Item tooltip`,
`Quest reward pick`, `Upgrade alert`, `Item stats`, `Stat search`, `Talent spec`, `Trainer record`,
`Action bar borders`, `Upgrade borders`, `Layout`, `XP bar`, `Bag button`, `Fishing rod`, `Fishing macro`,
`Class macro button`, `Class macros`, `Cure macro`, `Mute button`, `Role button`, `Map info`,
`Weapon procs`, `Eat button`, `Book pins` and `Book alert`. A feature whose API is missing stays off instead of
raising an error. Without `Class macros` the [class macro button](#bag-row) still works, but its list opens and picks
only out of combat.
`Upgrade borders` needs the `Upgrade alert` APIs and the default bag buttons, `ContainerFrame1Item1` or
`ContainerFrameCombinedBags`. Item stats are read from the tooltip, so without `Stat search` no item is judged.

Then one `Probe: <path> present|missing` line each for `LootButton1`, `LootFrame.ScrollBox`, `LootFrame_Update`,
`ContainerFrame1Item1.IconBorder`, `ContainerFrame1Item1.NewItemTexture`, `ContainerFrame1Item1.UpgradeIcon`,
`Enum.EditModeSystem.ChatFrame`, `MainStatusTrackingBarContainer`, `BagsBar`, `Enum.EditModeSystem.MicroMenu`,
`Enum.EditModeSystem.Minimap`, `Enum.EditModeSystem.AuraFrame`, `Enum.EditModeActionBarSetting.HideBarArt`,
`MainActionBar.EndCaps`, `MainMenuBar.EndCaps`, `MainMenuBarArtFrame.LeftEndCap`, `MainMenuBarLeftEndCap`,
`Enum.EditModeSystem.ObjectiveTracker`, `Enum.EditModeUnitFrameSystemIndices.Party` and
`Enum.EditModeUnitFrameSystemIndices.Raid`. They tell which bag, loot, Edit Mode, unit frame and aura parts the client
has, and turn nothing on or off.

### `/tandem weights`

Each class has built-in stat weights for each of its three talent trees. `/tandem weights` shows the ones in use:

```text
/tandem weights
Tandem: Arms Warrior weights, tree 1 (auto)
str 1, agi 0.6, sta 0.5, armor 0.01, dps 3, ap 0.5, hit 10, crit 10
```

The first line names the active tree and its number in talent tab order, then `auto` when it follows your talents or
`manual` when you picked it. With `auto`, the tree is the one with the most talent points; below level 10, with no
points spent or when the `Talent spec` line of [`/tandem check`](#tandem-check) is `missing`, it is the class's usual
levelling tree (Arms, Retribution, Beast Mastery, Combat, Shadow, Enhancement, Frost, Affliction, Feral Combat). The
second line lists each weighted stat by its key, in this order:
`str agi sta int spi armor dps ap rap sp heal hit crit spellhit spellcrit mp5 def dodge parry block blockvalue`.
`sp` is spell damage and healing, `heal` healing only and `dps` a weapon's damage per second; hit and crit weights are
per 1%.

- `/tandem weights spec <1|2|3>` picks a tree; `/tandem weights spec auto` follows the talents again. It prints
  `Tandem: weights use tree <n>` or `Tandem: weights follow your talents`.
- `/tandem weights set <stat> <number>` sets your own weight for one stat of the active tree, printing
  `Tandem: <stat> weight set to <number>`. `0` ignores the stat; a stat the tree has no weight for is added. The number
  may have a sign and a decimal point, such as `-1` or `0.5`. Your own weights are marked `*`, followed by the line
  `* your own weight; /tandem weights reset drops them`.
- `/tandem weights reset` drops your own weights for the active tree, printing
  `Tandem: own weights for tree <n> dropped`. The other trees keep theirs.

Each change then shows the weights as they now are. Your choices are saved per character (`Name`) and per tree,
so they survive switching talents. Other messages:

- `Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]` for anything else; nothing changes.
- `Tandem: unknown stat <stat>; use one of: <keys>` for a stat key not in the list above.
- `Tandem: no built-in weights for <class>` for a class without built-in weights.
- `Tandem: weights cannot be saved: recording is off or your character is not known yet` on saved data of a newer
  schema, or while the client does not tell your character's name yet.

## Upgrade advice

### What counts as an upgrade

An item is an upgrade when both hold:

- You can equip it now. It goes in a slot, and:
  - your level reaches its required level;
  - your class can use its armor or weapon type, by the Classic class tables. Cloth and miscellaneous items are open
    to every class. Hunters and shamans wear mail from level 40, warriors and paladins plate from level 40. Shamans'
    two-hand axes and maces need a talent, so they never count. Fishing poles never count. Warriors and hunters
    dual-wield from level 20, rogues from level 10, and only they can use off-hand-only weapons;
  - its tooltip has no red requirement line, such as a class, a weapon skill you have not trained, a race, a
    profession or a reputation you lack.
- It beats what you wear in that slot: a higher stat score wins, and an equal score wins only with more armor.
  The item level and the required level never decide: a lower score never wins, and an equal score with no more
  armor is no upgrade, however high the item's level.

The stat score is each stat on the item times its weight for your class and talent tree (see
[`/tandem weights`](#tandem-weights)), added up. So a strength item beats a caster item for a warrior even at a lower
item level. A score of 0, an item whose stats your weights ignore, still counts.

- An empty slot scores 0 with 0 armor, so any usable item with a score above 0 or with armor beats it.
- A ring or trinket is compared with the weaker of the two you wear: the lower score, or at an equal score the one
  with less armor. A one-hander you can dual-wield is compared with your weaker hand in the same way.
- A two-hander is compared with your main hand and off hand together: their scores added up, with the off-hand
  weapon's dps at half weight, and their armor (a shield's) added up too. An empty hand adds 0. If you already wield a
  two-hander, it is compared with that one alone.
- An off-hand item is never an upgrade while you wield a two-hander.
- While a fishing rod is in your main hand, no main-hand, off-hand or two-hand item is an upgrade: the tooltip, the
  borders and the alert show no weapon upgrade until you put your weapons back.

Everything is read live from the client: item level, required level, slot and type from its item info, stats from the
item's own tooltip (this needs the `Stat search` line of [`/tandem check`](#tandem-check)). What you wear is read from
its equipment slot, a bag item from its bag slot, and a looted or hovered item from its link, so random-suffix items
("of the Monkey") and enchanted items count all their stats. When the client lacks those tooltip APIs, the stats of
the plain item are read instead. Stats read are kept for the session and never saved. An item the client has not
loaded yet is asked for and judged when it arrives (`GET_ITEM_INFO_RECEIVED`); until the stats of the item and of what
you wear are known, it is not judged. Nothing is judged while the client does not reveal what you wear, or does not
tell your class or level.

### Upgrade alert

When an upgrade lands in your bags (`BAG_UPDATE_DELAYED`, bags 0 to 4), chat shows one line:

```text
Tandem: upgrade for Chest: [Plate Chest] (score 24.5 over 18.0)
```

The line names the bag item's own link, suffix included. The second score is that of the item it beats.

- Each item is announced at most once per session, and only when it is new in the bags: the bags you log in with are
  read silently, and moving an item between bags says nothing.
- In combat the line waits and is printed when combat ends (`PLAYER_REGEN_ENABLED`); nothing is printed in combat.
- A weapon that lands in your bags while you fish waits too: it is judged at the first bag change after the rod is off,
  if it is still in your bags.
- The alert only advises: Tandem never equips anything.
- Nothing happens when the `Upgrade alert` line of [`/tandem check`](#tandem-check) is `missing`.

### Upgrade borders

An upgrade in your bags or in the loot window gets a red border on its button and a green up arrow in its top-left
corner.

- Only the default Blizzard bag buttons, separate or combined bags, and the default loot window's buttons get borders.
  Bag addons such as Bagnon or AdiBags, and auto-loot, which never shows the loot window, bypass those frames, so
  nothing is drawn there; the [upgrade alert](#upgrade-alert) in chat still tells you.
- Borders are brought up to date when a bag or the loot window opens, when your bags, equipment, skills or level
  change, and when the client loads an item's details. This works in combat too.
- An item whose stats or requirements are not known yet gets no border until they are.
- The border only advises: Tandem never equips or loots anything, and never changes what the buttons do.
- Nothing is drawn when the `Upgrade borders` line of [`/tandem check`](#tandem-check) is `missing`.

### Item tooltip

Out of combat, hovering an upgrade adds one green line to the bottom of the game's tooltip:

```text
Tandem: upgrade over what you wear (score 24.5 over 18.0)
```

This works wherever the item's tooltip is the game's main tooltip, such as in your bags, in the loot window and on a
quest reward, and in the tooltip that opens when you click an item link in chat. The comparison tooltips that show
what you wear are left alone. Any other item gets no line, and in combat no line is added. On a `zhTW` client the line
is in Chinese.

### Quest reward pick

When you hand in a quest that lets you choose one of two or more rewards (`QUEST_COMPLETE`), Tandem puts a small Tandem
icon on the top right of the best choice's button. The best choice is the one you can equip, as in
[What counts as an upgrade](#what-counts-as-an-upgrade), that beats every other such choice:

- by stat score, an equal score going to the one with more armor;
- never by item level or quality: a tie on score and armor, or a usable choice whose stats cannot be read, marks
  none.

It is not compared with what you wear: hover the choice to see whether its [item tooltip](#item-tooltip) calls it an
upgrade.

- No icon when two usable choices still tie, when no choice is usable, or when the quest offers a single choice.
- A choice the client has not loaded yet is asked for; the icon shows once every choice has arrived, while the reward
  window is still open.
- The icon only advises: Tandem never selects a reward, and you still click the one you want.
- The icon goes when the reward window closes (`QUEST_FINISHED`).
- Nothing happens in combat, while the client does not tell your class or level, or when the `Quest reward pick` line of
  [`/tandem check`](#tandem-check) is `missing`. Nothing is printed.

## Action bar borders

A spell on the default action bars gets a coloured border when its rank is out of date:

- **Red**: the button holds a lower rank of a spell you already know at a higher rank. Drag the higher rank from the
  spellbook onto the bar.
- **Yellow**: a higher rank than any you know is taught at your level or below, and you have not learned it. Visit
  your class trainer.

Red wins when both apply. Macros, items, empty slots and spells without ranks get no border.

- Yellow needs to know what your class trainer teaches: Tandem records it when you open a class trainer's window (see
  [Saved data](#saved-data)). Until you have opened your class's trainer, only red borders show.
- Only the default Blizzard bars get borders: the main bar, the bottom left and right, the right bars and, when the
  client has them, action bars 5 to 7. Bars from other addons do not.
- Borders follow bar, page, spell, level and trainer changes outside combat. In combat they stay as they are and are
  brought up to date when combat ends.
- Nothing is drawn when the `Action bar borders` line of [`/tandem check`](#tandem-check) is `missing`. Tandem only
  draws over the buttons and never changes what they cast.

## Library books

Tandem pins WoW Forever's Library Books on the world map and tells you in chat when you walk past one. Open the world
map on a zone: each book your level reaches shows as a book icon. Hover it for where the book lies; click it to set a
waypoint. Near a book, chat shows:

```text
Tandem: Library book nearby: Bewitchments and Glamours — Moonbrook, first house entering from the east
```

### Book pins

- Only books your level reaches show: each book is meant for level 1, 30 or 40, and a higher-level book appears once
  you reach its level. Zone maps get pins; continent and world maps show none.
- The tooltip gives the book's title, where it lies, `Level <n>+` and, for a book inside the other faction's capital
  (Ironforge or Orgrimmar), a red `Enemy city` line. Such a book still shows.
- Books that lie on top of each other, as the two in Blackrock Mountain do, share one pin whose tooltip lists each.
- A book inside a cave or a building with a separate way in also gets a dimmer pin at the entrance; its tooltip starts
  with `Entrance`.
- Your faction's hand-in NPC shows with a different book icon and `Takes library books`: Garion Wendell in the
  Stormwind Mage Tower for the Alliance, Owen Thadd in the Undercity Magic Quarter for the Horde. Next to it a label
  reads how many books you have [turned in](#turned-in-books) out of all of them, such as `12/36`.
- Click a pin to set a waypoint and track it, at the entrance first when the book has one. Chat shows
  `Tandem: waypoint set to <title>`, or `Tandem: a waypoint cannot be set here` when the client cannot set one there.
- Pins show whether the [layout](#layout) is on or not. Nothing is drawn when the `Book pins` line of
  [`/tandem check`](#tandem-check) is `missing`; the waypoint APIs are optional.

### Book alert

When you stand within 40 yards of a book your level reaches that you have not turned in, or of its entrance, chat
shows the line above, once per book per session: a book is named again only after you log in again or `/reload`.
Nothing is checked in combat; the check resumes when combat ends. Distances are taken in world coordinates, so
standing in a cave or Blackrock Mountain still counts against the book on the zone map; when the client gives no world
position, only a book on the same map within 0.7 map percent on both axes counts. It needs the `Book alert` line of
[`/tandem check`](#tandem-check).

### The books switch

`/tandem books off` hides every pin and stops the alert at once; `/tandem books on` brings them back. Each prints
`Tandem: library book hints on` or `Tandem: library book hints off`, as does `/tandem books` alone. The switch is
saved as `books` in the [layout](#saved-data) data and is on until you turn it off.

### Turned-in books

A book you have handed in to your librarian shows dimmed on the map, its tooltip gains a green `Turned in` line, its
entrance pin goes away and the alert no longer names it. The librarian's tooltip adds `Books turned in: <n>/<total>`
and, until you have every reward, `Next reward at <n> books` (10, 20, 25 or 35). Tandem reads this from the game's
quest flags, so books you turned in before installing it count too, and a book you hand in now dims at once. A book
you have looted but not yet handed in keeps its full pin and its alert.

### Where the book data comes from

The book list is a fixed table in `Tandem/Data/Books.lua`, taken from the Library Books guide on method.gg in
November 2026. Its positions and map ids have not been checked in game, so a pin can sit in the wrong place or on the
wrong map. To check one, stand at the book and run `/tandem books near`:

```text
Tandem: map 1436 Westfall at (45.40, 70.50)
Tandem: nearest book Bewitchments and Glamours (Moonbrook, first house entering from the east), map 1436, 0 yd
```

The second line gives the distance in map percent instead when the client has no world positions, or reads
`Tandem: no eligible book on this continent`. To check every map id, turn on the [debug log](#debug-log) and
`/reload`: at login it logs `books mapinfo id=<id> name=<name> type=<type>` (or `books mapinfo id=<id> missing`) for
each map the table uses and `books worldpos ok|missing`, each world map change logs `books map=<id> pins=<n>`, each
alert logs `books alert <key> map=<id> at (<x>, <y>)`, and the `/tandem books near` lines are logged too. For the
turned-in flags, login also logs `books turnedin <n>/<total> next=<n>|none` and one `books flag key=<key> quest=<id>
flagged=true|false` per book, and each hand-in logs `books turnin quest=<id> title=<title> book=<key>|none`.

## Killers

Forever has no combat log, so Tandem cannot tell who killed you. Instead, when you die it records each enemy player
who was targeting you in the last 10 seconds: their name and realm, class, level, how many of your deaths they were
seen at, and the time and zone of the last one. It is a best guess: a killer in stealth or out of range is missed, and
a bystander who only had you targeted is listed too. Each character keeps its own list of up to 50 names.

When one of them shows up later on a nameplate, as your target or focus, or under the mouse, Tandem warns you with
large red text at the top of the screen, a chat line and the raid warning sound, in combat too:

```text
Gank-Far is nearby (seen at your death 2 times)
```

The same player is announced at most once every 60 seconds. Turn on enemy nameplates to have them seen from further
away.

`/tandem killers` prints the list, newest first:

```text
Seen targeting you at your death:
Gank-Far  Rogue 60  x2  2026-11-18 21:04  Duskwood
```

Fields the client did not give are left out, and an empty list prints `No one recorded yet.`.
`/tandem killers forget <name>` drops one: `Name-Realm` names it exactly; a bare name means the one on your realm, else
the only one with that name. It prints `<name> removed from the list.`, `<name> is not on the list.`, or
`<name> matches several; use Name-Realm.`. `/tandem killers clear` empties the list and prints `Killer list cleared.`.
When your character is not known yet or the saved data is read-only, each prints `Killer list unavailable.`.

Right-click the [minimap button](#minimap-button) or Tandem's addon compartment entry to open the same list in a
window you can drag, closed with its close button, Escape or another right-click. Each row shows the class-coloured
name, class and level, the count, the date and the zone; scroll with the mouse wheel when there are more than 12. The
cross at the end of a row forgets that name, and `Clear` empties the list after a second click within 3 seconds, its
label reading `Click again to clear` meanwhile. The window follows every new death, `forget` and `clear`, shows
`No one recorded yet.` when the list is empty and `Killer list unavailable.` when it cannot be read.

## Target distance

Tandem shows how far a hostile target is, in yards, in a short coloured line on the screen under your own character,
in combat too:

| Text      | Colour |
| --------- | ------ |
| `0 - 5`   | red    |
| `5 - 20`  | green  |
| `20 - 30` | blue   |
| `30+`     | gray   |

The distance comes from item ranges the client checks for every class, so it needs no spell and no nameplate. When
the client gives no answer (a dead target, or right after login before the items have loaded), nothing shows, and a
friendly or neutral target you cannot attack shows nothing either. The line updates ten times a second and goes at
once when you lose or change the target.

## Instant Lightning Bolt

In combat, a Shaman sees the Maelstrom Weapon icon with a yellow glow just above the target distance line while
Maelstrom Weapon has made Lightning Bolt instant (five stacks), and it goes as soon as it is not or combat ends.
Tandem reads the bolt's cast time, which the client answers in combat too, so it needs no buff reading. It sits on
the right of the two icon slots. Out of combat the icon never shows.

## Stormstrike ready

In combat, a Shaman who knows Stormstrike sees its icon, with the same yellow glow, in the left slot above the target
distance line whenever Stormstrike is off cooldown, and it goes as soon as you cast it. The client hides cooldowns in
combat, so Tandem reads the cooldown's length out of combat and times it from your cast; until it has read one, it
counts 20 seconds. Out of combat the icon never shows.

## Layout

```text
/tandem layout on
Tandem: layout on
```

`/tandem layout on` arranges the screen around the action bars, using the account Edit Mode layout `Tandem`, which it
creates or updates. The layout is off until you turn it on. `/tandem layout off` brings back the layout you used
before, printing `Tandem: layout off; your previous layout is back`; if that layout was deleted or renamed, the first
preset layout is used instead. `/tandem layout` alone prints `Tandem: layout on` or `Tandem: layout off`.

- Each character has a layout mode, damage or healer, switched with the [role button](#bag-row); a new character
  starts in damage mode. The [healer variant](#what-moves) moves the party and raid frames to the centre.
- Switching to another layout in Edit Mode turns Tandem's layout off, as `off` would, but keeps the layout you chose.
- In combat the change waits: chat shows `Tandem: the layout will change after combat`, and it happens when combat
  ends.
- When the account layouts are full, `on` prints `Tandem: no free account layout slot; delete one in Edit Mode`.
- Without Edit Mode, or when the `Layout` line of [`/tandem check`](#tandem-check) is `missing`, `on` prints
  `Tandem: the layout needs Edit Mode, which this client lacks` and nothing moves.

### Minimap button

The Tandem icon on the minimap edge turns the layout on or off with a click and prints the same line as
`/tandem layout on` or `off`; in combat the change waits as above. Its tooltip shows whether the layout is on. Drag it
around the minimap to move it; the place is saved. `/tandem minimap off` hides it, `/tandem minimap on` shows it again
and `/tandem minimap` alone toggles it, printing `Tandem: minimap button hidden` or `Tandem: minimap button shown`.
Tandem's entry in the addon compartment menu does the same as a click. A right-click on either opens the
[killers window](#killers).

### What moves

```text
┌──────────────────────────────────────────────────────────────────┐
│              [==| XP 62% |(42.31, 67.80) · 1H20m]   [buffs][map] │
│      [player]                                [target][ToT]       │
│                                                                  │
│                      [ Shaman totem bar ]                        │
│ [chat]               [ main action bar  ]                        │
│ [chat]               [ action bar 2     ]              [bag row] │
│ [chat]               [ action bar 3     ]           [micro menu] │
└──────────────────────────────────────────────────────────────────┘
```

- The three bottom action bars stack at the bottom centre, 12 buttons in one row each, the main bar on top, without
  the gryphon art. A Shaman's totem bar keeps its own row just above the main bar, where Blizzard puts it.
- The player frame and the target frame sit in a row well above the bars, left and right of centre. The target of
  target is shown, next to the target frame.
- The [XP bar](#xp-bar) sits at the top centre of the screen, with the [map info](#map-info) line centred just below it.
- The chat window goes to the bottom left, about 380 by 120, when the client's Edit Mode has a chat system; without
  Edit Mode's chat size settings it only moves; without a chat system it stays put. On a narrow screen it narrows to
  the room left of the bars (down to 260 wide) and otherwise goes above the player frame.
- The micro menu goes to the bottom-right corner, with the [bag row](#bag-row) just above it. The quest tracker and
  Blizzard's damage meter stay where your previous layout had them.
- The minimap goes to the top right, with the buffs just left of it. The client's own coordinates on the minimap are
  hidden, since the [map info](#map-info) line shows them.
- The micro menu, minimap and buffs move only when the client's Edit Mode has their system (the buffs also need the
  minimap's); otherwise they stay where they are.
- The right action bars and action bars 5 to 7 are hidden.

In healer mode the screen is the same except for the unit frames:

```text
┌──────────────────────────────────────────────────────────────────┐
│              [==| XP 62% |(42.31, 67.80) · 1H20m]   [buffs][map] │
│                       [ party / raid ]                           │
│      [player]                                                    │
│                                                                  │
│                      [ main action bar  ]                        │
└──────────────────────────────────────────────────────────────────┘
```

- The party frames and the raid frames move to the centre, just above the row of the player frame, so the people you
  heal sit in front of you. A frame whose Edit Mode system the client lacks (the
  `Enum.EditModeUnitFrameSystemIndices.Party` or `.Raid` probe of [`/tandem check`](#tandem-check) is `missing`) stays
  where it was.
- The target frame is faded and does not take clicks, and the target of target is turned off.

The Tandem layout is shared by your characters, but each character's mode is its own: logging in with a character
whose mode differs from the one the layout was last built for builds it again for that character. Switching the mode
in combat waits for combat to end, like `/tandem layout on`.

Turning the layout off restores the target of target and minimap coordinates settings and every frame Tandem hid.
Tandem's own frames are display only and update in combat too.

### XP bar

A bar at the top centre of the screen, 30% of the screen wide, shows your experience with the percent on it, such as
`42%`, split into ten cells by thin lines like the classic XP bar. Hover it for value / max and the rested bonus:

```text
4200 / 9800 (42%)
Rested +15%
```

The bar is blue while you have rested experience and purple without. It is hidden at the maximum level, and it
replaces the default status bars, so a watched reputation bar is hidden too while the layout is on. It needs the
`XP bar` line of [`/tandem check`](#tandem-check).

### Bag row

Two icons sit at the bottom right. The rightmost reloads the interface when clicked (`/reload`). Left of it, one bag
icon shows the free / total slots of all your bags summed on its lower edge: general, profession (such as a herb or
soul bag) and reagent bags. A count turns yellow under 10 free slots and red when full. Hover it for each kind's free
/ total and bag names; click it to open all bags. The row replaces the default bag bar while the layout is on, and
needs the `Bag button` line of [`/tandem check`](#tandem-check); without a reload function on the client the reload
icon is left out.

At every login, layout on or off, Tandem turns on the client's combined bags (the `combinedBags` setting), so `B`
opens one window with all your bags. You can switch it off in the options; it comes back on at the next login.
Tandem also points every key bound to "Open all bags" or "Open backpack" (`B` is one of them) at its own opener,
which opens and closes the reagent bag together with the others, as the bag icon does.

The opener and the bag icon never open the bag windows from Tandem's own code: they click the default backpack button
and reagent bag slot for you, so Blizzard's code opens them. Opening bags from addon code taints them, and a later
right-click on a bag item then fails with "Interface action failed because of an AddOn". In combat the bag icon's
count still changes.

When you own a fishing rod, one more icon sits just left of the bag row. While you fight with your weapons it shows the
rod: click it to equip the rod. While the rod is worn it shows your main hand: click it to put back the main hand and
off hand the rod replaced (if you took the off hand off yourself, it is not put back). After a `/reload` while fishing,
clicking it puts back your best soulbound main hand from your bags; with none, the tooltip says `Equip your weapon`.
Hover it for what the click will equip; when you are about to equip the rod with an off hand worn and your general bags
have no free slot, a red `Bags full: no room for your off hand` line warns you first. Tandem only swaps on your click.
In combat the icon cannot change, so a click runs the swap it showed before the fight. It shows only while the layout is
on, and needs the `Fishing rod` line of [`/tandem check`](#tandem-check).

The first time Tandem sees a fishing rod, it makes a character macro named `Tandem Fishing`: while the rod is not worn
it equips it, while it is worn it casts Fishing, and its icon follows. Drag the rod icon to put the macro on an action
bar; its tooltip says `Drag to place the fishing macro on your action bar`. Tandem updates the macro out of combat when
your rod changes (a fight holds the change until it ends), and keeps the last rod it saw when you have none; with no rod
seen at all it names the plain Fishing Pole, which shows grey. When your character macro slots are full no macro is
made, and the tooltip says `Character macros full: no room for the fishing macro`. Once made, the macro is yours: Tandem
never deletes it. It needs the `Fishing macro` line of `/tandem check`; without it the rod icon still swaps, it just
cannot be dragged.

A Shaman gets one more icon left of the rod icon (or of the bag row, with no rod): the class macro button. Like the
totem bar's flyouts, a click casts the macro you picked, and the small arrow above it opens an upward list of every
entry you have learned:

- `Cure Poison` and `Cure Disease` cast that cure on the friend under your mouse, else on your friendly target, else on
  yourself.
- `Cure Poison / Cure Disease`, once you know both, casts Cure Poison on a left click and Cure Disease on a right click,
  on the same targets.
- `Stormstrike` switches to the nearest enemy when your target is missing, dead or friendly (it may be one not yet
  fighting), starts attacking and casts Stormstrike.
- `Astral Recall` casts Astral Recall on a left click, or uses your Hearthstone while Astral Recall is on cooldown; a
  right click always uses your Hearthstone. When the client hides the cooldown, a left click tries Astral Recall and
  falls back to the Hearthstone. The switch happens out of combat, so a cooldown that starts or ends in a fight takes
  effect once it ends. In combat both clicks use your Hearthstone, and cast Astral Recall only when the Hearthstone
  cannot be used, for example while it is on cooldown; the row's icon and tooltip show the Hearthstone until the fight
  ends. With no Hearthstone in your bags combat changes nothing, Astral Recall still casts, and the tooltip says
  `No Hearthstone in your bags`.

Click a row: it casts that entry, becomes the button's pick and the list closes. `Astral Recall` is the exception: it
casts and closes the list but never becomes the pick. The pick is saved per character, so
it outlasts a `/reload`; when its spell is no longer known, the first entry is used. This works in combat too when the
`Class macros` line of [`/tandem check`](#tandem-check) is `ok`. Without it the list opens and picks only out of
combat and closes when a fight starts. Hover the arrow: `Class macros` and `Click to choose the button's macro`, or
`Choosing waits until combat ends` when a pick has to wait.

When you or a party member carries a poison or a disease, each cure row lights up with the number of you who carry
one, and the button with the count over its whole list. In combat the client keeps debuffs secret from addons, so the
lights go dark until the fight ends. Hover the button or a row: the entry's title, what it does, for a cure who carries
which debuff (or `No one in your party has a Poison effect`; in combat `Party debuffs show again after combat`), and
`Drag to place this macro on your action bar` (`Drag out of combat to place this macro` in combat).

Drag the button or a row to put that entry's character macro, `Tandem Poison`, `Tandem Disease`, `Tandem Cure`,
`Tandem Stormstrike` or `Tandem Recall`, on an action bar. Tandem makes it on that first drag and keeps it current out
of combat; when your character macro slots are full the tooltip says `Character macros full: no room for this macro`.
Tandem only casts on your click. In combat the button cannot move, appear or hide, so a spell learned or a rod swapped
in a fight shows once it ends. It shows only while the layout is on, and needs the `Class macro button` line of
[`/tandem check`](#tandem-check) (dragging also needs `Cure macro`).

One more icon, left of the class macro button (or of the rod icon, or of the bag row, when those are hidden), mutes the game:
a click turns all sound off, the next click turns it back on, in combat too. It flips the client's
`Sound_EnableAllSound` setting, the same as the sound checkbox in the client's sound settings, so the choice outlasts
a `/reload` and turning the layout off. Its icon is a horn, in colour, or greyed out while the sound is off, and its
tooltip says `Sound on` or `Sound off` with `Click to mute` or `Click to unmute`. In combat it cannot move, so it
follows a class macro button or rod icon that came or went in the fight once it ends. It shows only while the layout is on,
and needs the `Mute button` line of [`/tandem check`](#tandem-check).

The role button, left of the mute icon (or of whatever icon is leftmost when the mute icon is hidden), switches this
character's [layout mode](#what-moves). It shows a sword in damage mode and a flash heal in healer mode; its tooltip
says `Layout mode`, `Damage` or `Healer`, and `Click for the healer layout` or `Click for the damage layout`. A click
switches to the other mode and prints `Tandem: healer layout` or `Tandem: damage layout`; in combat it prints
`Tandem: the layout will change after combat` and the switch, with its icon, happens when combat ends. It shows only
while the layout is on, and needs the `Role button` line of [`/tandem check`](#tandem-check).

The eat and drink button sits left of the role button (or of whatever icon is leftmost when the role button is hidden).
It shows only while the layout is on and you have food or drink in your bags, with the icon of the food it will eat,
else of the drink (while you eat, the drink), greyed while neither click has anything left to do. A left click eats the
food and a right click drinks the drink (only if you use mana); a click does nothing while you are already eating or
drinking that kind. Hover it: `Eat and drink`, then `Left-click: eat <name>` and `Right-click: drink <name>`, with
`Eating…` or `Drinking…` instead while you are. It picks the best food and drink in your bags: buff food (`Well Fed`)
first unless you are already Well Fed, then the one that restores the most, then a conjured item, then the smaller
stack. Food or drink you cannot use yet (level too low) is skipped, and potions and healthstones are never used. Tandem
only eats and drinks on your click. The button changes only out of combat, so food looted in a fight shows once it ends.
It needs the `Eat button` line of [`/tandem check`](#tandem-check).

### Map info

One line of small text centred just below the [XP bar](#xp-bar) shows where you are on the zone map, in
percent, and how long you have played at this level:

```text
(42.31, 67.80) · 1H20m
```

The time reads `1d5H` from a day up, `1H20m` from an hour up, else `20m`. Where the map has no position for you, as in
most instances, the coordinates read `(--, --)`. When the XP bar is hidden, as at the maximum level, the line sits
alone at the top centre of the screen. The line shows only while the layout is on and updates twice a second.
Hovering the bar still shows the XP tooltip. Hover the line
for the zone, the subzone, and your time played in total, at this level and this session:

```text
Elwynn Forest
Goldshire
Played: 12d 5h
This level: 1h 20m
This session: 45m
```

To get the times, Tandem asks the server for `/played` once per login, so Blizzard's two `Total time played` /
`Time played this level` chat lines print once each login; Tandem does not hide them. From then on it counts up
itself, and a level up resets this level to `0m` without asking again. Until the answer arrives the line shows only the
coordinates. It needs the `Map info` line of [`/tandem check`](#tandem-check).

While the layout is on, Tandem hides the client's own coordinates on the minimap so they don't show twice; turning
the layout off restores them.

### Weapon enchant procs

For a Shaman whose main hand carries Windfury, Flametongue or Frostbrand, an icon under the player frame, below its
totem icons, shows that enchant's icon and how often it procs: procs per melee hit that lands, as a percentage (`-`
before the first hit). Hover it for the enchant's name and its procs / hits; right-click it to start counting again.
The counts are kept per character and per enchant, across reloads and logins, so switching enchants keeps each one's
numbers.

The client gives addons no combat log, so the counts come from the damage your target takes, seen only while your
auto attack is on: a physical hit is a hit, a fire hit (Flametongue) or frost hit (Frostbrand) is a proc, and for
Windfury a second physical swing right after the first is its extra attack. Your own spells' hits, such as
Stormstrike or a shock, and Flame Shock's damage over time are left out. Another player's hits on the same target
also count, so the rate is exact only when you fight alone. It shows only while the layout is on and needs the
`Weapon procs` line of [`/tandem check`](#tandem-check).

Each part, the layout, XP bar, bag row and map info, stays dark when its `/tandem check` line is `missing`,
and the rest still works.

### Debug log

`/tandem debug on` starts recording, for the developer, what the bag opener decides on each press and a snapshot of
the frames near the bottom of the screen and Blizzard's status bars (2 seconds after login, on every layout change,
and on `/tandem debug snap`). Nothing is printed while it records. The log, at
most 300 lines, is saved in the `TandemDebug` saved variable when you `/reload` or log out. `/tandem debug off` stops
recording and prints how many lines it kept; `/tandem debug` alone toggles it, and `snap` turns recording on if
needed and takes a snapshot.

While it records, every "Interface action failed because of an AddOn" the client raises is logged with the addon, the
blocked function and the call stack, and also kept apart in `blocked` (the last 50), so the busy log cannot push it
out. `on` also sets the client's `taintLog` setting to `1`, so the client writes `Logs/taint.log` naming the code that
tainted the action; `off` sets it back to `0`.

Every Lua error raised while it records is kept in `errors` (the last 20) with its message, call stack and local
variables, and then shown by the client as before.

## Saved data

Tandem saves one account-wide table, `TandemDB`, as
`<World of Warcraft>/_forever_/WTF/Account/<account>/SavedVariables/Tandem.lua`.

| Key        | Content                                                                                                        |
| ---------- | -------------------------------------------------------------------------------------------------------------- |
| `weights`  | Per character (`Name`): chosen `spec` (1-3, absent = auto) and stat weight `overrides` per spec                |
| `trainers` | Per class (`MAGE`): per spell ID a class trainer teaches, its required `level` and its `rank` (absent if none) |
| `layout`   | [Layout](#layout) `on`, `previous` layout, old target of target and `coords`, the `minimap` `angle`, `hidden`  |
| `modes`    | Per character (`Name`): the [layout mode](#what-moves), `heal`; absent = damage                                |
| `picks`    | Per character (`Name`): the [class macro](#bag-row) entry picked, such as `poison` or `stormstrike`            |

- A class trainer's spells are recorded each time its window opens or updates outside combat, under your character's
  class: every spell it lists, learned or not, with the level it needs and the number in its rank text (`Rank 3` is
  `3`). Section headers, tradeskill trainers and spells the client gives no spell ID for are skipped, and nothing is
  recorded when the `Trainer record` line of [`/tandem check`](#tandem-check) is `missing`. A spell seen again keeps
  the lower level.
- On load, an invalid `spec`, override, stat key or value is dropped alone, as is a `trainers` spell ID or entry that
  is not valid; a character's entry that is not a table, or a class key that is not a class token or whose spells are
  not a table, is dropped.
- `layout.built` is `heal` while the `Tandem` Edit Mode layout is built for the healer mode, absent for damage; at
  login it is compared with the character's `modes` entry to rebuild the layout when they differ. A `modes` entry
  other than `heal` is dropped on load.
- A `picks` entry that is not a non-empty entry id is dropped on load.
- `layout.books` is the [library books](#the-books-switch) switch: `false` after `/tandem books off`, `true` after
  `/tandem books on`, absent (on) until you use either. A value that is not `true` or `false` is dropped on load.
- Each character is keyed by its name alone, without the realm: Forever's realm APIs return nothing and the realm it
  shows is only a pseudonym. Two characters with the same name on different realms therefore share one entry of
  `weights`, `modes`, `picks`, [weapon procs](#weapon-enchant-procs) and [killers](#killers).

`TandemDB.schemaVersion` is `8`. Saved data from an older schema is migrated on load: `weights`, `trainers`,
`layout`, `modes`, `picks`, `procs` and `killers` are kept and every other key, such as the item cache, loot log and
stats of earlier versions, is dropped. Chat then shows `Tandem: saved data upgraded from schema <n> to 8` and
`Tandem: dropped <n> invalid or unused saved entries`; schema 6 and 7 data is upgraded silently when nothing is dropped.
Saved data from a newer schema is kept as it is, and nothing is saved until the addon is updated.

Schema 8 renames every per-character entry from `Name-Realm` to `Name`, once, on the first load. When several old
entries share a name (the same name on different realms), the first in alphabetical order of `Name-Realm` is kept and
each other one counts as dropped. The step is one way: an older Tandem then finds a newer schema and saves nothing, so
to go back to one, restore a copy of `Tandem.lua` taken before updating.

The same file also holds `TandemDebug`, the [debug log](#debug-log): `on`, up to 300 `log` lines, 50 `blocked` and 20 `errors`,
only after you turn it on.

The client writes `Tandem.lua` only on logout or `/reload`.

## Verify in game

1. Start the client. On the character select screen, open **AddOns** and check that **Tandem** is listed and enabled.
2. Enter the world. The chat window shows:

   ```text
   Tandem loaded
   ```

   On a Traditional Chinese (`zhTW`) client the line reads `Tandem 已載入`, and the AddOns list shows the notes in
   Chinese too. Every other client language gets English.

If the line is missing, check that the addon is enabled and that no Lua error was reported.

### Check the client APIs

The tooltip, the quest reward pick, the upgrade alert and borders and the action bar borders use APIs that are not
verified on Forever. One pass of `/tandem check` tells which of them the client has:

1. Out of combat, run `/tandem check`. Chat shows `Tandem API check:` and twenty-four lines, one each for
   `Item tooltip`, `Quest reward pick`, `Upgrade alert`, `Item stats`, `Stat search`, `Talent spec`, `Trainer record`,
   `Action bar borders`, `Upgrade borders`, `Layout`, `XP bar`, `Bag button`, `Fishing rod`, `Fishing macro`,
   `Class macro button`, `Class macros`, `Cure macro`, `Mute button`, `Role button`, `Map info`,
   `Weapon procs`, `Eat button`, `Book pins` and `Book alert`, each followed by `ok` or `missing` and its APIs.
   Twenty `Probe:` lines follow, each `present` or `missing`.
2. Hand in a quest that offers a choice of rewards and, with the reward window open, run `/tandem check` again. Note
   whether the `Quest reward pick` line now finds `QuestInfoRewardsFrame.RewardButtons`,
   `QuestInfoRewardsFrameQuestInfoItem1` or `QuestRewardItem1`: the reward buttons may only exist once the window has
   been shown.
3. Start a fight and, while in combat, run `/tandem check`: it prints `Tandem: not available in combat` and nothing
   else.
4. If `Quest reward pick` is `ok` in step 2, run [Check the quest reward pick](#check-the-quest-reward-pick). If
   `Upgrade alert` is `ok`, run [Check the upgrade alert](#check-the-upgrade-alert). If `Talent spec` is `ok`, run
   `/tandem weights` on a character level 10 or more: its first line names the tree with the most talent points,
   followed by `(auto)`. If `Action bar borders` is `ok`, run
   [Check the action bar borders](#check-the-action-bar-borders). If `Upgrade borders` is `ok`, run
   [Check the upgrade borders](#check-the-upgrade-borders). If `Layout` is `ok`, run
   [Check the layout](#check-the-layout).

Report back every line of steps 1 and 2 as printed, the `Probe:` lines included, the first line of `/tandem weights`
from step 4, and any Lua error.

### Check the quest reward pick

1. Out of combat, hand in a quest that offers a choice of two or more rewards, at least one of which your class can
   use. In the reward window, a small Tandem icon sits on the top right of one choice's button. Nothing is printed and
   no reward is selected.
2. Note the stats and armor of each choice you can use: the marked one has the highest score for your weights, or at
   an equal score more armor; when two usable choices tie on both, no icon shows, whatever their item level or
   quality.
3. Close the reward window without choosing, then talk to the quest giver again: the icon shows again on the same
   choice.
4. For a quest whose usable choices tie, or that offers nothing your class can use, no icon shows.
5. If you can, open a reward window in combat: no icon shows and nothing is printed.

Report back the quest, the choices with their stats, item level and quality, which one was marked, whether the icon
sat well on the button or hid part of it, and any Lua error.

### Check the upgrade alert

1. Log in or run `/reload` with some gear in your bags: no `Tandem: upgrade for` line shows.
2. Out of combat, loot, buy or take from the mail an item your class can use whose tooltip shows
   `Tandem: upgrade over what you wear` (or any usable item with stats for an empty slot). Chat shows one line, nothing
   is equipped, and it reads `Tandem: upgrade for <slot>: <item link> (score <n> over <m>)`.
3. Move that item to another bag, sell it and buy it back, or drop and loot it again: no second line for it this
   session.
4. Get an item you cannot use, one with a red line in its tooltip (such as a weapon type you have not trained), one
   with a higher item level but a lower score, or one no better than what you wear: no line.
5. Get an item with the same score as what you wear but a higher item level: a line shows.
6. Loot an upgrade during a fight: nothing shows in combat; the line shows when the fight ends.
7. If you can, loot an upgrade the client has never shown before (a fresh drop): the line may come a moment later, once
   the item has loaded.

Report back each line as printed with the score of what you wore, any upgrade that got no line or any line for an
item that is not an upgrade, and any Lua error.

### Check the action bar borders

1. Out of combat, put a lower rank of a spell you know at a higher rank on the main bar (drag it from the spellbook
   with `Show all spell ranks` ticked, or pick it from its rank list). Its button gets a red border; the highest rank
   of the same spell has none. A macro or an item on the bar has none.
2. Put the same lower rank on the bottom left bar and on a right bar: those buttons are red too. If action bars 5 to 7
   are on, do the same there.
3. Swap the red button for the highest rank: the border goes at once.
4. On a character whose class trainer has a rank ready at your level, open the trainer, close it, and look at the
   spell's highest learned rank on the bar: its border is yellow. Learn the rank: the old button turns red.
5. Switch bar pages (Shift and the mouse wheel, or the arrows by the main bar): borders follow the spells on the new
   page.
6. Start a fight and, in combat, swap a red button for the highest rank: the border stays red. When combat ends, it
   goes.

Report back any button that is red or yellow without reason, or not when it should be, which bars got no borders at
all, and any Lua error.

### Check the upgrade borders

1. With the default bags, open your bags while they hold an item that the [upgrade alert](#upgrade-alert) would
   announce: its button has a red border and a green up arrow, and its tooltip has the green Tandem line. Items no
   better than what you wear, items you cannot use and items with a red line in their tooltip have none.
2. Equip the bordered item: its border goes, and the item you took off gets none.
3. Loot a corpse that drops an upgrade with auto-loot off: the item's button in the loot window has the border and
   arrow. Page through a loot window of more than one page: borders follow the items, not the buttons.
4. Level up, or learn a weapon skill at a trainer for a weapon in your bags: its border appears or goes to match.
5. Start a fight and loot or move an upgrade in your bags: the border still shows.
6. With a bag addon such as Bagnon or AdiBags, or with auto-loot on, no border shows; the chat alert still does.

Report back the `Upgrade borders` and `Probe:` lines of `/tandem check`, any bordered item that is not an upgrade or
upgrade without a border, whether the border sits well on the button, and any Lua error.

### Check the layout

1. Out of combat, run `/tandem layout on`. Chat shows `Tandem: layout on`. The three bottom action bars sit at the
   bottom centre without gryphons, the player and target frames in a row above them, the chat window bottom left,
   the micro menu in the bottom-right corner with the bag row above it, and the minimap top right with the buffs to its
   left (where the client lets Edit Mode move them); the right bars and the bag bar are gone. Target something: its
   target of target shows.
2. At the top centre, the XP bar, 30% of the screen wide in ten cells, shows its percent, purple, or blue when rested.
   Only one XP bar shows. Hover it: `<value> / <max> (<n>%)` and, when rested, `Rested +<n>%`. Kill something: it
   moves.
3. At the bottom right, the bag row shows your general free / total slots on a backpack icon and, to its left, one
   icon per profession bag. Click any icon: all bags open. Loot an item: the count drops by one. With a fishing rod
   in your bags, a rod icon sits left of the bag row: click it and the rod is equipped; click it again and your
   weapons are back. Drag the rod icon onto an action bar: a `Tandem Fishing` macro lands there; click it to equip the
   rod, click it again to cast Fishing. Left of the rod icon (or of the bag row, with no rod; on a Shaman, left of the
   class macro button), a horn icon sits: click it and all game sound goes off and the horn turns grey; click it
   again and the sound is back. Left of the horn, a sword icon sits: hover it for `Layout mode` and `Damage`.
4. On a Shaman, the totem bar sits in its own row just above the main bar, also after casting in combat.
5. On a Shaman who knows Cure Poison, the class macro button sits left of the rod icon (or of the bag row), with a
   small arrow above it. Click the arrow: a list of your learned entries opens upward. Hover a row: its title, what it
   does and `Drag to place this macro on your action bar`. Click the `Cure Poison` row: it casts, the list closes and
   the button shows its icon. Run `/reload`: the button still shows it. Drag the button onto an action bar: a
   `Tandem Poison` macro lands there. Out of combat, when you or a party member is poisoned, the `Cure Poison` row
   and the button light up with `1`.
6. Run `/tandem debug on`. Start a fight and, in combat, click the arrow and another row, such as `Stormstrike`: it
   casts and the button takes its icon. When the fight ends, run `/reload` and read the `log` of `TandemDebug` in
   [Saved data](#saved-data): it holds `flyout pick: <id> combat=true`, then `flyout pick saved: <id>`. When the
   `Class macros` line of `/tandem check` is `missing`, the list closes as the fight starts, the arrow does nothing
   until it ends, and no such line is logged.
7. Centred just below the XP bar, one line reads your coordinates and time at this level, such as
   `(42.31, 67.80) · 1H20m`; walk and the coordinates change. Hover it: the zone, the subzone if any, `Played:`,
   `This level:` and `This session:`. Hover the bar: the XP tooltip. Enter an instance: the coordinates
   read `(--, --)`. After the login, chat showed Blizzard's `/played` lines once.
8. Run `/reload`: everything is still in place.
9. Join a party, then click the sword icon: chat shows `Tandem: healer layout`, the icon turns to a flash heal, the
   party frames sit at the centre just above the player frame, and the target frame and target of target are gone.
   Run `/reload`: still the same. Log in with another character: its own mode (damage, unless you switched it) is
   built. Back on the first character, the healer layout is built again. In a fight, click the icon: chat shows
   `Tandem: the layout will change after combat`, and the damage layout, with the sword icon, comes when the fight
   ends.
10. Start a fight and run `/tandem layout off`: chat shows `Tandem: the layout will change after combat`. When the
    fight ends your previous layout is back, with its bars, bag bar, status bar, target of target and minimap
    coordinates as before.
11. Turn the layout on again, open Edit Mode and pick another layout: Tandem's XP bar, bag row, class macro button, mute
    button, role button and map info line go.

Report back the `Layout`, `XP bar`, `Bag button`, `Fishing rod`, `Fishing macro`, `Class macro button`,
`Class macros`, `Cure macro`, `Mute button`, `Role button`, `Map info` and `Probe:` lines of
`/tandem check`, the `flyout` lines of `TandemDebug` from step 6, any frame that landed in the wrong place or overlaps
another, anything not restored by `off`, and any Lua error.

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
runs `scripts/wow-dir_test.sh`. The local `luac` is a newer Lua than the game's Lua 5.1, so it catches syntax errors
only.

`scripts/addon_test.lua` loads the files listed in `Tandem/Tandem.toc`, in order, with stubbed WoW API functions, and
checks the load line for the `enUS`, `zhTW` and an unsupported locale. It also tests `TandemDB` validation and
migration, `/tandem` parsing and output, stat weights, tooltip stat reading, trainer recording, the upgrade judge with
stubbed class, level, equipped and bag items, the upgrade alert and borders, the quest reward pick, the action bar
borders, the item tooltip line, the layout, the XP bar, the bag row and the map info line. These
tests prove the logic only; the client's real API is checked in game.

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
