# NascentAddon

A World of Warcraft addon. The client's interface number is **16001**; keep `## Interface:` in `NascentAddon.toc` on that value.

## Layout

- `NascentAddon.toc` — manifest; every new Lua file must be listed here, in load order.
- `Core.lua` — entry point (prints `Nascent loaded` on `PLAYER_LOGIN`).
- `.luacheckrc` — lint config with the WoW globals whitelist.

## Workflow

1. Make the change.
2. Run luacheck (below) and fix every warning before handing back.
3. Ask the user to `/reload` in game.
4. Read the BugGrabber file (below) and fix anything it captured.

### Luacheck — run after every change

```bash
luacheck .
```

If `luacheck` is not on PATH in the current shell, call it directly:
`& "$env:LOCALAPPDATA\Programs\luacheck\luacheck.exe" .`

The run must end with `0 warnings / 0 errors`. Do not silence a warning by adding a
name to `read_globals` in `.luacheckrc` unless that API has been verified to exist
(next section).

### Error capture — BugGrabber

Lua errors are captured by the !BugGrabber addon into its SavedVariables file:

```
C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\495068229#1\SavedVariables\!BugGrabber.lua
```

WoW only writes SavedVariables on `/reload` or logout, so the file is stale until the
user reloads. After the user says they reloaded, read this file and look at the newest
entries (highest `session`, latest `time`) that mention `NascentAddon`. Never edit this
file.

## Rules learned the hard way

- **Verify an API exists before using it.** Do not assume a function, widget method,
  template, event, or constant exists in this client because it exists in another WoW
  version. If there is any doubt, ask the user to test in game and report the result,
  for example `/dump SomeFunction`, `/dump C_Some.Thing ~= nil`, or
  `/dump (select(4, GetBuildInfo()))`. `nil` means it does not exist; do not use it.
- **`unpack`, not `table.unpack`.** WoW runs Lua 5.1; `table.unpack` is nil. The same
  goes for other 5.2+ features (`goto`, integer division, bit operators, `table.pack`).
- **`SetFont` before `SetText`.** A FontString with no font object throws
  "Font not set" on `SetText`. Set the font (or create the FontString with a font
  template such as `GameFontNormal`) first, then set text.
- **`InCombatLockdown()` before `StartMoving()`.** Moving, showing, hiding, or
  re-anchoring protected frames in combat is blocked and raises an error. Guard drag
  handlers: `if InCombatLockdown() then return end`.
- **BackdropTemplate quirks.** `SetBackdrop` is not on a plain frame in clients that
  moved it into a mixin; the frame must be created with `"BackdropTemplate"`. In clients
  without the mixin, passing that template name fails instead. Create frames with
  `BackdropTemplateMixin and "BackdropTemplate" or nil`, and when combining templates
  use a comma-separated string. Confirm with `/dump BackdropTemplateMixin ~= nil` before
  relying on either behaviour.
- **No `VCENTER`.** It is not a valid value for `SetJustifyV`. Vertical justification
  is `"TOP"`, `"MIDDLE"`, or `"BOTTOM"`; horizontal is `"LEFT"`, `"CENTER"`, `"RIGHT"`.

## Conventions

- Start each file with `local addonName, ns = ...` and share state through `ns`, not
  new globals. Any intentional global (SavedVariables, slash command keys, named
  frames) must be added to `globals` in `.luacheckrc`.
- Report honestly: luacheck passing does not mean the addon works in game. Say what was
  linted and what still needs a `/reload` test.
