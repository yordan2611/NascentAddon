# Nascent

A World of Warcraft addon for the "Forever" client (`_forever_`, product `wowf`). The
client's interface number is **16001**; keep `## Interface:` in `Nascent.toc` on that
value.

## Naming

The addon's official name is **Nascent**. Nothing shown in game may say `NascentAddon`:
the TOC file, `## Title`, chat output, slash command (`/nascent`), comm prefix
(`Nascent`) and SavedVariables (`NascentDB`) all use `Nascent`. In code, show `ns.NAME`
to the player, never `addonName`.

`NascentAddon` survives only as the name of this repository and its folder on disk. The
game loads the addon through a junction named `Nascent`:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Nascent
  -> C:\nascentaddon\NascentAddon
```

The junction name must match the TOC file name (`Nascent.toc`), or the game will not
load the addon.

## Layout

- `Nascent.toc` — manifest; every new Lua file must be listed here, in load order.
- `Core.lua` — namespace (`ns.NAME`, `ns.VERSION`, `ns.Print`), AceDB setup (`ns.db`),
  the `/nascent` slash command, and the `Nascent loaded` login message.
- `Comm.lua` — version check over addon messages (below).
- `Libs/` — embedded libraries, committed to the repo: LibStub, CallbackHandler-1.0,
  AceComm-3.0 (with ChatThrottleLib), AceSerializer-3.0, AceDB-3.0. Copied unmodified
  from https://github.com/WoWUIDev/Ace3; do not edit them. Luacheck skips this folder.
- `.luacheckrc` — lint config with the WoW globals whitelist.

## Comm protocol

`Comm.lua` sends an AceSerializer-encoded table with AceComm under the prefix `Nascent`:
`{ proto, version, kind, sid, test }`. The full description is in the header comment of
`Comm.lua`.

- `PROTOCOL` in `Comm.lua` is the wire-format version. Bump it when the message layout
  changes.
- `proto` and `version` are the envelope. They must keep their meaning in every future
  protocol version, so that an old copy can still learn it is out of date.
- The addon version comes from `## Version` in the TOC and must be `major.minor.patch`.
- Every value read from a received message must be type-checked before use; other
  players' messages are untrusted input.

## Workflow

1. Make the change.
2. Run luacheck (below) and fix every warning before handing back.
3. Ask the user to `/reload` in game. If a file was added, removed or renamed, or the
   TOC changed, `/reload` is not enough: ask for a full exit and restart of the game.
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
entries (highest `session`, latest `time`) that mention `Nascent`. Never edit this
file.

## Rules learned the hard way

- **Verify an API exists before using it.** Do not assume a function, widget method,
  template, event, or constant exists in this client because it exists in another WoW
  version. Two ways to verify:
  - Search the other installed addons in
    `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. Prefer the
    ones whose TOC lists only interface 16001 (ForeverCore, NaowhForever, NodeSight,
    ShortestPathForever, ForeverDungeonJournal). An unguarded call there is good
    evidence; a call wrapped in `if X then` is not.
  - Ask the user to test in game and report the result, for example
    `/dump SomeFunction`, `/dump C_Some.Thing ~= nil`, or
    `/dump (select(4, GetBuildInfo()))`. `nil` means it does not exist; do not use it.
- **Characters have a first name and a surname.** `UnitName(unit)` returns the first
  name only. Use `local first, surname = UnitFullName(unit)` and join them with a space
  (`"First Surname"`) for anything that addresses a player, such as a whisper target;
  a whisper to the first name alone fails with "No player named ... is currently
  playing". There is no realm suffix on this client, so never split a name on `-` or
  on a space to "strip the realm".
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
- Print to chat with `ns.Print`, which adds the coloured `Nascent:` tag.
- Report honestly: luacheck passing does not mean the addon works in game. Say what was
  linted and what still needs an in-game test.
