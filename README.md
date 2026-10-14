# Tandem

> Cowork with your WoW player

English | [繁體中文](README.zh-TW.md)

Tandem is a World of Warcraft addon. It is an empty shell for now: it prints one line in chat when it loads.

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

`make install` locates the `World of Warcraft` folder with `scripts/wow-dir.sh`. A folder qualifies only if it
contains `<FLAVOR>/Interface/AddOns`. The search order is:

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

## Verify in game

1. Start the client. On the character select screen, open **AddOns** and check that **Tandem** is listed and enabled.
2. Enter the world. The chat window shows:

   ```text
   Tandem loaded
   ```

If the line is missing, check that the addon is enabled and that no Lua error was reported.

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

This syntax-checks the Lua files with `luac -p` and runs the tests for `scripts/wow-dir.sh`. The local `luac` is a
newer Lua than the game's Lua 5.1, so it catches syntax errors only.

Each commit also runs `luacheck` through pre-commit, configured in `.luacheckrc` for Lua 5.1. It needs `luarocks`
installed (`brew install luarocks`); pre-commit installs `luacheck` itself. Run it on demand with:

```sh
pre-commit run luacheck --all-files
```

When the addon starts calling another WoW API function, add its name to `read_globals` in `.luacheckrc`.
