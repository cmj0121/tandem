# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon. For now it collects data for a later stage: a cache of equippable items, built by
scanning item IDs, and a log of where each looted item came from. It never acts for the player, and it records nothing
while you are in combat.

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

| Variable  | Default          | Meaning                                                                                    |
| --------- | ---------------- | ------------------------------------------------------------------------------------------ |
| `WOW_DIR` | auto-detected    | The `World of Warcraft` folder, the one that contains `_classic_beta_`, not the flavor dir |
| `FLAVOR`  | `_classic_beta_` | The client flavor folder inside `WOW_DIR`                                                  |
| `MODE`    | `link`           | `copy` copies the addon instead of linking it                                              |
| `DATA`    | `data`           | The folder `make import` writes to                                                         |

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
Unsaved records: 16 (saved on /reload or logout)
Last run: IDs 1-100 at 10/s in 10.6s, 100 processed, 0 skipped
  41 hits (12 equippable), 59 misses, 12 deferred, 0 timeouts
```

Before the first scan, `found IDs` reads `none` and the last line reads `Last run: never`. `Unsaved records` counts
items, loot drops and npc names added since the addon loaded; they are lost if the client exits without saving.

## What is collected

Everything goes into one account-wide table, `TandemDB`, saved as
`<World of Warcraft>/_classic_beta_/WTF/Account/<account>/SavedVariables/Tandem.lua`.

| Key     | Content                                                                                     |
| ------- | ------------------------------------------------------------------------------------------- |
| `items` | Per equippable item ID: item level, required level, quality, equip slot, class and subclass |
| `scan`  | Cursor, non-equippable count, min/max ID found, hits per 1000-ID block, last run            |
| `loot`  | Per item, source and map: npc or object ID, map ID, drops, up to 5 positions                |
| `npcs`  | Npc names by npc ID                                                                         |

- Items that exist but cannot be equipped are counted in `scan.nonEquippable`, not stored.
- `scan.lastRun` holds the last run's start time, ID range, rate, elapsed seconds and the counts the summary prints.
- A loot entry is recorded once per source each time a loot window opens outside combat. Its source is a creature
  (`kind = "c"`, npc ID) or a game object (`kind = "o"`, object ID); `kind = "?"` means the client did not say. Map
  and positions are left out when the client does not report them.
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
migration, `/tandem` parsing and output, the scan with a manual timer and stubbed item API, and loot recording with
stubbed loot, map and unit API. These tests prove the logic only; the client's real API is checked in game.
`scripts/import_test.sh` runs `make import` and `scripts/import.lua` against throwaway saved-variables files and data
folders: two contributors, re-imports, rejected files and the sandbox.

### Importing loot logs

The loot log is crowdsourced: each player's `Tandem.lua` is imported into the repository's `data/` folder and committed.
Log out or `/reload` in game first, because the client writes the file only then. Then, from the repository root:

```sh
make import
```

```text
wrote data/contributions/3f2a9c81d0b4.lua (enUS: 42 loot entries, 7 npc names)
wrote data/loot.lua (1 contributors)
```

The ID and the numbers are an example. `make import` reads every
`<World of Warcraft>/<FLAVOR>/WTF/Account/*/SavedVariables/Tandem.lua` of the detected client and writes:

| File                          | Content                                                                            |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| `data/contributions/<id>.lua` | One account's `loot` and `npcs` with its locale, overwritten on each import        |
| `data/loot.lua`               | Merged from every contribution: summed counts, up to 5 positions, names per locale |

`data/loot.lua` also records how many contributions it merged, as `contributors`.

- `<id>` is the first 12 hex digits of the SHA-256 of the account folder name. The folder name, the account number, is
  never written or printed, and the same account always gets the same ID.
- The locale is the `SET textLocale` line of `WTF/Config.wtf`, `enUS` when missing. Npc names are stored in the client
  language, so `data/loot.lua` keeps them under `names[<locale>]`.
- Only `loot` and `npcs` are imported. `items` and `scan` stay local, since anyone can scan items again.
- Running it again is safe: each account's contribution is a full snapshot that replaces the last one, so counts are
  never added twice, and the same input gives byte-identical files.
- Each saved-variables file runs in an empty environment, with no functions to call and a limit on how long it may run,
  and its `TandemDB` is checked as the addon checks it on load. A file that fails to parse, raises an error, runs too
  long, is precompiled, has no `TandemDB` or comes from a newer addon version is skipped with a message such as
  `import: <file>: no TandemDB table, skipped`. Invalid entries are dropped with
  `import: <file>: <n> invalid entries ignored`.
- A skipped file does not stop the others. `scripts/import.lua` exits with status 1, and `make import` fails, only when
  no file was imported, including when no `Tandem.lua` exists.

Set `WOW_DIR`, `FLAVOR` or `DATA` as for `make install`, for example `make import DATA=/tmp/tandem-data`. Then review
the changes under `data/` with `git diff` and commit them as usual.

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
