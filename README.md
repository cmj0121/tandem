# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon that tells you when an item beats what you wear. It judges each item in your bags,
in the loot window and among quest rewards from what the client says about it right now: its slot, required level,
armor or weapon type, tooltip requirements and stats, weighted for your class and talent tree. An upgrade gets a red
border and a green up arrow on its bag or loot button, one line in chat and a green line in its tooltip. Tandem also
marks the best quest reward choice and flags out-of-date spell ranks on your action bars. On request it arranges your
screen around the action bars, with an XP bar, a bag row and, for a Shaman, a class area. It never acts for the
player: it only advises, and it saves nothing but your own stat weights, what your class trainer teaches and whether
its layout is on.

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

`check` and `weights` print `Tandem: not available in combat` and do nothing while you are in combat. `layout` waits
for combat to end instead; `minimap` works in combat too.

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
`Action bar borders`, `Upgrade borders`, `Layout`, `XP bar`, `Bag button` and `Shaman area`. A feature whose API is
missing stays off instead of raising an error.
`Upgrade borders` needs the `Upgrade alert` APIs and the default bag buttons, `ContainerFrame1Item1` or
`ContainerFrameCombinedBags`. Item stats are read from the tooltip, so without `Stat search` no item is judged.

Then one `Probe: <path> present|missing` line each for `LootButton1`, `LootFrame.ScrollBox`, `LootFrame_Update`,
`ContainerFrame1Item1.IconBorder`, `ContainerFrame1Item1.NewItemTexture`, `ContainerFrame1Item1.UpgradeIcon`,
`Enum.EditModeSystem.ChatFrame`, `MainStatusTrackingBarContainer`, `BagsBar`, `C_UnitAuras.GetAuraDataBySpellName`,
`UnitBuff`, `Enum.EditModeSystem.MicroMenu`, `Enum.EditModeSystem.Minimap` and `Enum.EditModeSystem.AuraFrame`. They
tell which bag, loot, Edit Mode and aura parts the client has, and turn nothing on or off.

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

Each change then shows the weights as they now are. Your choices are saved per character (`Name-Realm`) and per tree,
so they survive switching talents. Other messages:

- `Tandem: usage /tandem weights [spec <1|2|3|auto> | set <stat> <number> | reset]` for anything else; nothing changes.
- `Tandem: unknown stat <stat>; use one of: <keys>` for a stat key not in the list above.
- `Tandem: no built-in weights for <class>` for a class without built-in weights.
- `Tandem: weights cannot be saved: recording is off or your character is not known yet` on saved data of a newer
  schema, or while the client does not tell your name and realm.

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
- It beats what you wear in that slot: a higher stat score wins, and an equal score wins only with a higher item
  level. A lower score never wins, whatever the item level.

The stat score is each stat on the item times its weight for your class and talent tree (see
[`/tandem weights`](#tandem-weights)), added up. So a strength item beats a caster item for a warrior even at a lower
item level. A score of 0, an item whose stats your weights ignore, still counts.

- An empty slot scores 0 at item level 0, so any usable item with stats beats it.
- A ring or trinket is compared with the weaker of the two you wear: the lower score, or at an equal score the lower
  item level. A one-hander you can dual-wield is compared with your weaker hand in the same way.
- An off-hand item is never an upgrade while you wield a two-hander.

Everything is read live from the client: item level, required level, slot and type from its item info, stats from its
tooltip (this needs the `Stat search` line of [`/tandem check`](#tandem-check)). Stats read are kept for the session
and never saved. An item the client has not loaded yet is asked for and judged when it arrives
(`GET_ITEM_INFO_RECEIVED`); until the stats of the item and of what you wear are known, it is not judged. Nothing is
judged while the client does not reveal what you wear, or does not tell your class or level.

### Upgrade alert

When an upgrade lands in your bags (`BAG_UPDATE_DELAYED`, bags 0 to 4), chat shows one line:

```text
Tandem: upgrade for Chest: [Plate Chest] (score 24.5 over 18.0)
```

The second score is that of the item it beats.

- Each item is announced at most once per session, and only when it is new in the bags: the bags you log in with are
  read silently, and moving an item between bags says nothing.
- In combat the line waits and is printed when combat ends (`PLAYER_REGEN_ENABLED`); nothing is printed in combat.
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

- by stat score when every usable choice has stats, an equal score going to the higher item level, then the better
  quality;
- by item level, then quality, when any usable choice has no stats.

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

## Layout

```text
/tandem layout on
Tandem: layout on
```

`/tandem layout on` arranges the screen around the action bars, using the account Edit Mode layout `Tandem`, which it
creates or updates. The layout is off until you turn it on. `/tandem layout off` brings back the layout you used
before, printing `Tandem: layout off; your previous layout is back`; if that layout was deleted or renamed, the first
preset layout is used instead. `/tandem layout` alone prints `Tandem: layout on` or `Tandem: layout off`.

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
Tandem's entry in the addon compartment menu does the same as a click.

### What moves

- The three bottom action bars stack at the bottom centre, 12 buttons in one row each, with room under them for the
  XP bar and the [class area](#shaman-class-area) just above them.
- The player frame sits as a wing left of the bars and the target frame as a wing right of them, both level with the
  top bar. The target of target is shown, next to the target frame.
- The chat window goes to the bottom left, about 380 by 120, when the client's Edit Mode has a chat system; without
  Edit Mode's chat size settings it only moves; without a chat system it stays put.
- The [bag row](#bag-row) sits in the bottom-right corner, with the micro menu above it.
- On a narrow screen, the chat window narrows to the room left of the player frame (down to 260 wide) and otherwise
  goes above the bars, and the micro menu goes above the bars when it does not fit right of the target frame.
- The minimap goes to the top right, with the buffs just left of it.
- The micro menu, minimap and buffs move only when the client's Edit Mode has their system (the buffs also need the
  minimap's); otherwise they stay where they are.
- The right action bars and action bars 5 to 7 are hidden.

Turning the layout off restores the target of target setting and every frame Tandem hid. Tandem's own frames are
display only and update in combat too.

### XP bar

A thin bar under the action bars shows your experience, with only the percent on it, such as `42%`. Hover it for
value / max and the rested bonus:

```text
4200 / 9800 (42%)
Rested +15%
```

The bar is blue while you have rested experience and purple without. It is hidden at the maximum level, and it
replaces the default status bar, so a watched reputation bar is hidden too while the layout is on. It needs the
`XP bar` line of [`/tandem check`](#tandem-check).

### Bag row

A row of icons at the bottom right shows free / total slots on each icon: your general bags first (rightmost), then
one icon per profession bag type to its left, with that bag's icon, such as a herb or soul bag. A count turns yellow
under 10 free slots and red when full. Hover an icon for its bags' names and free / total; click any icon to open all
bags. It replaces the default bag bar while the layout is on, and needs the `Bag button` line of
[`/tandem check`](#tandem-check).

### Shaman class area

For a Shaman, a rail of icons just above the action bars shows, centred, one icon for each of:

- each totem that is down, in Earth, Fire, Water, Air order, with its time left;
- each weapon enchant that is up, main hand then off hand, on the weapon's icon, with its time left;
- Lightning Shield, or Water Shield where the client has it, with its charges in the lower-right corner and its time
  left.

The time left reads `m:ss` above a minute, else whole seconds, and counts down; an icon goes when its time runs out.
Hover an icon for its name (the totem's, the shield's, or `Main hand` / `Off hand`) and time left. While any icon
shows, a thin blue mana line runs along the rail's bottom; with no icon, the whole rail hides.

It only shows state and timers: nothing in it can be clicked, and it never advises what to cast. Other classes get no
rail. It needs the `Shaman area` line of [`/tandem check`](#tandem-check).

Each part, the layout, XP bar, bag row and Shaman area, stays dark when its `/tandem check` line is `missing`, and
the rest still works.

## Saved data

Tandem saves one account-wide table, `TandemDB`, as
`<World of Warcraft>/_forever_/WTF/Account/<account>/SavedVariables/Tandem.lua`.

| Key        | Content                                                                                                        |
| ---------- | -------------------------------------------------------------------------------------------------------------- |
| `weights`  | Per character (`Name-Realm`): chosen `spec` (1-3, absent = auto) and stat weight `overrides` per spec          |
| `trainers` | Per class (`MAGE`): per spell ID a class trainer teaches, its required `level` and its `rank` (absent if none) |
| `layout`   | [Layout](#layout) `on`, `previous` layout, old target of target, the `minimap` button's `angle` and `hidden`   |

- A class trainer's spells are recorded each time its window opens or updates outside combat, under your character's
  class: every spell it lists, learned or not, with the level it needs and the number in its rank text (`Rank 3` is
  `3`). Section headers, tradeskill trainers and spells the client gives no spell ID for are skipped, and nothing is
  recorded when the `Trainer record` line of [`/tandem check`](#tandem-check) is `missing`. A spell seen again keeps
  the lower level.
- On load, an invalid `spec`, override, stat key or value is dropped alone, as is a `trainers` spell ID or entry that
  is not valid; a character's entry that is not a table, or a class key that is not a class token or whose spells are
  not a table, is dropped.

`TandemDB.schemaVersion` is `7`. Saved data from an older schema is migrated on load: `weights`, `trainers` and
`layout` are kept and every other key, such as the item cache, loot log and stats of earlier versions, is dropped.
Chat then shows `Tandem: saved data upgraded from schema <n> to 7` and
`Tandem: dropped <n> invalid or unused saved entries`; schema 6 data is upgraded silently when nothing is dropped.
Saved data from a newer schema is kept as it is, and nothing is saved until the addon is updated.

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

1. Out of combat, run `/tandem check`. Chat shows `Tandem API check:` and thirteen lines, one each for
   `Item tooltip`, `Quest reward pick`, `Upgrade alert`, `Item stats`, `Stat search`, `Talent spec`, `Trainer record`,
   `Action bar borders`, `Upgrade borders`, `Layout`, `XP bar`, `Bag button` and `Shaman area`, each followed by `ok`
   or `missing` and its APIs. Fourteen `Probe:` lines follow, each `present` or `missing`.
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
2. Note the stats, item level and quality of each choice you can use: the marked one has the highest score for your
   weights, or at an equal score the higher item level; when a usable choice has no stats, the highest item level,
   then the better quality.
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
   bottom centre with the player and target frames beside them, the chat window bottom left, the micro menu above
   the bag row in the bottom-right corner and the minimap top right with the buffs to its left (where the client
   lets Edit Mode move them); the right bars and the bag bar are gone. Target something: its target of target shows.
2. Under the bars, the thin XP bar shows only its percent, purple, or blue when rested. Hover it: `<value> / <max>
(<n>%)` and, when rested, `Rested +<n>%`. Kill something: it moves.
3. At the bottom right, the bag row shows your general free / total slots on a backpack icon and, to its left, one
   icon per profession bag. Click any icon: all bags open. Loot an item: the count drops by one.
4. On a Shaman, nothing shows above the bars at first. Drop a totem, apply a weapon enchant and cast Lightning
   Shield: an icon for each appears on the rail above the bars with its time left counting down, the shield with its
   charges, and a thin blue mana line under them. Hover one: its name. When one runs out, its icon goes; when the
   last goes, the rail and its mana line go. Clicking the rail does nothing.
5. Run `/reload`: everything is still in place.
6. Start a fight and run `/tandem layout off`: chat shows `Tandem: the layout will change after combat`. When the
   fight ends your previous layout is back, with its bars, bag bar, status bar and target of target as before.
7. Turn the layout on again, open Edit Mode and pick another layout: Tandem's XP bar, bag row and class area go.

Report back the `Layout`, `XP bar`, `Bag button`, `Shaman area` and `Probe:` lines of `/tandem check`, any frame that
landed in the wrong place or overlaps another, anything not restored by `off`, and any Lua error.

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
borders, the item tooltip line, the layout, the XP bar, the bag row and the Shaman class area. These tests prove
the logic only; the client's real API is checked in game.

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
