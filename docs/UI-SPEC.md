# NascentAddon — UI Spec (living draft)

Source of truth for the main window. The layout follows a reference screenshot from another
addon's settings window: a title bar, a searchable sidebar of collapsible categories, a
scrolling stack of cards and a footer. Only the shape is borrowed; colours, font and names are
Nascent's own.
Build with plain frames + textures + FontStrings. Follow CLAUDE.md rules on top of this file.

```
+------------------------------------------------------+
| [N] Nascent                                        X |  title bar
+-------------+----------------------------------------+
| Search...   | +-- Card title ----------------------+ |
| • General v | | body                               | |
|   Home      | +------------------------------------+ |
|   Settings  | +-- Card title ----------------------+ |
| • Cat. Two v| | label                              | |
|   Section   | | [control]                          | |
|             | +------------------------------------+ |
+-------------+----------------------------------------+
| v0.1.0                                          grip |  footer
+------------------------------------------------------+
```

## 1. Colors (WoW RGB 0–1)

| Token | Hex | r, g, b | Use |
|---|---|---|---|
| bg.window | #050505 | 0.020, 0.020, 0.020 | content area behind the cards, buttons, inputs |
| bg.sidebar | #000000 | 0, 0, 0 | title bar, sidebar, footer, cards, tooltip |
| border.outer | #000000 | 0, 0, 0 | 1px outermost edge |
| border.inner | #1E2350 | 0.118, 0.137, 0.314 | 1px inner edge, title bar bottom, footer top, sidebar right edge, card, button and input borders, tooltip border |
| divider | #12152E | 0.071, 0.082, 0.180 | line under a card title, scroll bar track |
| accent | #9099F9 | 0.565, 0.600, 0.976 | logo, category headers and bullets, card titles, selected item text + bar, scroll thumbs, slider fill, checked box. User-configurable (setting) |
| text.primary | #FFFFFF | 1, 1, 1 | addon name, hovered item, control labels, typed search text |
| text.secondary | #A9ACCB | 0.663, 0.675, 0.796 | idle items, body text, tooltip description |
| text.muted | #8D90B8 | 0.553, 0.565, 0.722 | version, idle close X, chevrons, search placeholder, hints under controls |
| hover.bg | #0A0C1C | 0.039, 0.047, 0.110 | item and button hover |
| close.hover | #FF6B6B | 1.000, 0.420, 0.420 | close X on hover (bg #140A0C = 0.078, 0.039, 0.047) |
| grip | #3A4180 | 0.227, 0.255, 0.502 | resize grip lines |

Selected item background: horizontal gradient accent at alpha 0.16 (left) → 0.02 (right).
Use a white texture + `SetGradient("HORIZONTAL", CreateColor(r,g,b,0.16), CreateColor(r,g,b,0.02))`.

## 2. Typography

Font: Expressway (ship .ttf in `Media/Fonts/` and register with LibSharedMedia as "Expressway";
check the font's license before public release). Fallback if missing: `Fonts\\ARIALN.TTF`.
Always `SetFont` before `SetText`.

| Role | Size | Color | Case |
|---|---|---|---|
| Addon name (title bar) | 15 | text.primary | as written ("Nascent") |
| Category header | 14 | accent | as written |
| Sidebar item | 13 | text.secondary / white (hover) / accent (selected) | as written |
| Search text | 13 | text.primary; placeholder text.muted | as written |
| Card title | 14 | accent | as written |
| Control label | 13 | text.primary | sentence case |
| Body | 13 | text.secondary | sentence case |
| Hint (under a control) | 13 | text.muted | sentence case |
| Tooltip title | 14 | text.primary | as written |
| Tooltip desc | 13 | text.secondary | sentence case |
| Version (footer) | 12 | text.muted | as written |

Rule: no uppercase transforms. Minimum size 12.

## 3. Layout (px at UI scale 1)

Main window `NascentMainFrame`: 795 × 806 by default (the size the user picked in game), strata MEDIUM, `SetToplevel(true)`, `SetClampedToScreen(true)`.
Border = 1px outer black + 1px inner border.inner, drawn with plain textures. Everything below sits
inside that 2px border.

### Title bar, full width, height 30
- bg.sidebar, 1px border.inner along its bottom. It is the drag handle.
- Logo 18 × 18 (`Media/logo_n.tga`, tinted accent), left inset 10, vertically centered.
- Addon name 6 right of the logo.
- Close button 22 × 22, right inset 4, hit rect expanded by 4 on every side. X icon 10 × 10,
  text.muted → close.hover with its bg on hover.

### Footer, full width, height 22
- bg.sidebar, 1px border.inner along its top.
- Version ("v" + version) left inset 10, vertically centered.
- Resize grip 12 × 12 at the bottom-right, inset 5 (inside the footer).

### Sidebar (left), width 180, between title bar and footer
- bg.sidebar, 1px border.inner on its right edge.
- Search box at the top, inset 6, height 24: bg.window, 1px border.inner, text inset 8,
  placeholder "Search..." while empty. Typing filters items by name (case-insensitive substring);
  categories with no match are hidden, the rest are forced open. Enter opens the first match,
  Escape clears the box. Nothing matched → "No matches" (text.muted) at the top of the list.
- Below it, the category list, which scrolls (see Scrolling), bottom inset 6.
- Category header: height 26. Bullet 4 × 4 accent at left inset 10, name 8 right of it, chevron
  10 × 10 at right inset 10 (down = open, right = folded; text.muted, white on hover). Click folds
  or unfolds the category; the folded set is saved. Folding does nothing while searching.
- Item row: height 24, no gaps, label inset 24 from the left, 8 from the right, truncated with "…"
  (`SetWordWrap(false)` + `SetMaxLines(1)`). Full name and a description in the tooltip.
  - States: idle (text.secondary, no bg) · hover (hover.bg, white text) · selected (gradient bg,
    accent text, accent bar 2 px wide on the left edge).

### Content (right), between title bar and footer, fills remaining width
- bg.window, padding 8, scrolls (see Scrolling).
- The selected item's page is a stack of cards, 8 apart, each the full content width.
- Card: bg.sidebar, 1px border.inner. Header 30 high with the title at left inset 10, then a 1px
  divider line. Body padding 10; items stacked 8 apart:
  - text: wraps to the card's inner width;
  - control: label (control label style), 4 gap, then the control;
  - button row: buttons 26 high sharing the width equally, 6 apart.
- Button: bg.window, 1px border.inner, label 13 text.primary centered; hover.bg on hover.
- No page title: the cards' titles name the content.

### Scrolling
- Plain `ScrollFrame` + scroll child; no `UIPanelScrollFrameTemplate` (see section 6).
- Mouse wheel scrolls 40 px per notch.
- Scroll bar 3 wide, 3 right of the scroll area: track divider, thumb accent, at least 20 high.
  Hidden when everything fits. Click or drag on the bar moves the thumb's middle to the cursor.

### Tooltip
- Custom, not GameTooltip default look: bg black, 1px border.inner, padding 8 × 12, max width 240.
- Anchored LEFT to the hovered item row's RIGHT, x offset +8.
- Title + one-line description. Shown on item OnEnter, hidden on OnLeave.

### Pages
- Home (category General): "Welcome to Nascent" (greeting with the character's full name in
  accent, version), "Quick actions" (Check for updates, Reload UI, slash command hint),
  "Getting started".
- Settings (category General): see section 5.
- Placeholder categories and sections until the real ones are decided: one card each.

## 4. Behavior

- Esc closes: `tinsert(UISpecialFrames, "NascentMainFrame")` (frame must be named). While the search box has focus, Esc clears it instead.
- Movable: drag by the title bar. `RegisterForDrag("LeftButton")`; guard `StartMoving()` with `if InCombatLockdown() then return end`. Save position to SavedVariables on drag stop and restore on load.
- Resizable: `SetResizable(true)`, `SetResizeBounds(640, 460, 1400, 1000)`; grip calls `StartSizing("BOTTOMRIGHT")`. Save size.
- Remember last selected section and the folded categories in SavedVariables; reopen on them.
- Open via: `/nascent` (and `/nas`), addon compartment entry (TOC `## AddonCompartmentFunc`), optional minimap button (LibDBIcon, can be hidden), keybinding (Bindings.xml, "Toggle Nascent").
- Sounds: `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` on item, category, button and checkbox clicks; `SOUNDKIT.IG_MAINMENU_CLOSE` on close; `SOUNDKIT.IG_MAINMENU_OPEN` on open.
- Combat: option "Hide in combat" (PLAYER_REGEN_DISABLED / ENABLED). Anything protected → print a short friendly message instead of erroring.
  The window hides when combat starts and comes back when it ends. Off by default.
- `/nas minimap` and `/nas combat` are shortcuts for the two Settings checkboxes.

## 5. Settings section
UI scale (separate `SetScale`, 0.7–1.5), window opacity (bg alpha 0.6–1.0), font size offset (−2…+4 applied to every role), accent color picker (ColorPickerFrame), minimap button on/off, hide in combat on/off.

As built:
- Two cards. "Appearance": UI scale, Window opacity, Font size (hint under it), Accent color.
  "Behavior": Show minimap button, Hide in combat (hint under it). Each is a card control: label
  above, control below.
- Slider: 200 × 16, track 4 high (border.inner), fill accent, thumb 8 × 16 white, value text 12 to the right. Scale and opacity step 5%, font size step 1.
- UI scale and font size apply when the slider is released; opacity applies while dragging.
- The font size offset never takes a role below the minimum size 12. Changing it re-lays out the sidebar and the cards.
- Opacity applies to the title bar, sidebar, footer, content area and card backgrounds; text, borders and the tooltip stay opaque.
- Accent: swatch 32 × 16 opens the colour picker; "Reset" beside it restores #9099F9. The accent also colours the chat tag and the minimap button.
- Checkbox: 16 × 16, bg.window fill, 1px border.inner, accent square when checked.

## 6. Platform constraints (WoW Forever = Mainline 12.1.5-era API, Midnight addon restrictions)
- Lua 5.1: `unpack`, not `table.unpack`.
- Verify every API exists before use (`/dump` or `/api search`); Forever may lack newer retail APIs.
- `SetFont` before any `SetText` on raw FontStrings.
- `VCENTER` is not a valid anchor point.
- `UIPanelScrollFrameTemplate` steals keyboard focus — prefer ScrollBox/custom scroll.
- `GetNumMacroIcons()` and related icon APIs were removed.
- `StartMoving()`/`StartSizing()` need an `InCombatLockdown()` guard.
- Secret values / combat data restrictions apply — no computing on combat data.
- A Lua error at file load silently disables the whole addon: run luacheck before every /reload.

## 7. Assets needed
- `Media/logo_n.tga` — the N shard alone, white on transparent (tinted in-game), 128 × 128, power-of-two.
  Generate it from this SVG (e.g. Node + sharp → PNG → TGA, 32-bit with alpha, uncompressed):
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="220 255 840 810"><polygon fill="#FFFFFF" points="228,467 453,449 614,449 736,685 899,261 845,737 1051,849 830,867 665,867 544,630 381,1056 436,579"/></svg>`
  (viewBox isn't square: center the shape on a square transparent canvas with a few px of padding.)
- Icons white on transparent (tinted in-game): close X, resize grip, chevron down, chevron right.
- `Media/Fonts/Expressway.ttf`.
- Present: `logo_n.tga`, `icon_close.tga`, `icon_grip.tga`, `icon_chevron_down.tga`, `icon_chevron_right.tga`, `Fonts/Expressway.ttf`.
  The font is git-ignored (local only) until its licence is checked; copies built from the public repo use the fallback font.

## 8. Cheapest items (category Inventory)

Shows the least valuable stacks in the general bags (bags with a family, such as herb or soul
bags, are skipped) so the player can make room. Own implementation of the idea behind
DeleteCheapestItem Reloaded; no code from it.

What is listed:
- Qualities picked on the page (default Poor, Common, Uncommon), optionally no soulbound items.
- Never: ignored items, locked slots, items without a sell price, quest items, keys, ammunition,
  quivers, fishing poles, profession tools (mining pick, skinning knife, enchanting rods, ...).
- Value = unit price × stack count. Unit price = vendor price, or Auctionator's price when
  "Use auction prices" is on and Auctionator knows the item. Sorted cheapest first.

List row (shared by the pop-up and the page): height 36, 1px divider between rows, hover.bg on
hover with the item's bag tooltip (GameTooltip) plus two muted hint lines (Shift-click to link,
right-click to ignore, Shift-click Delete). Icon 26 at inset 6; name in the item's quality colour
with "x<count>" muted; under it, 12 muted: "Vendor <coins>", "(<coins> each)" for stacks, and
"Auction <coins>" when known. Buttons 58 × 22 on the right, 6 apart, from the right: Ignore,
Delete, and Sell while a vendor is open (leftmost, label in the accent: the main action there).
With "Confirm before deleting" on, the first Delete click turns the label into "Confirm"
(close.hover) with a 2px close.hover bar along its bottom that empties over the 4 s; a second
click within 4 s deletes. Shift-click on Delete deletes without confirming.
Clicks on the row: the chat-link modifier (Shift by default) or Ctrl inserts the item link in
chat (ChatFrameUtil.InsertLink); right-click ignores the item.
While loot is waiting, a row worth more than the most wanted waiting item gets a 12 close.hover
tag "Worth more than the loot" at the right of the name line (not when that item is a quest item
or has no price yet).
Nothing listed → a body-text line saying why: how many sellable stacks were left out for an
unticked quality, the ignore list or Skip soulbound, or that nothing can be sold. In the pop-up a
"Change what is listed" text button under it opens this page.

Pop-up `NascentCheapestFrame`: 480 wide, height from its contents; strata HIGH, toplevel,
clamped, movable by the title bar, Esc closes, follows the UI scale and window opacity. Title bar
like the main window's (logo, "Cheapest items", close X) with "<n> free" (12) left of the close X,
muted, close.hover at 0. Body bg.window, padding 8. While the loot window holds items: a 30-high
line on bg.sidebar with a divider edge, "Waiting to loot" (12 muted), the most wanted item's
icon 20, name in its quality colour, "x<n>" muted and its value (or "quest item"), and
"+<n> more" right; hover shows the loot tooltip. 8 below it, up to "Rows in the pop-up" rows
(3–10, default 5). Footer: "<n> stacks listed, worth <coins>" left; "Options" text button right
(opens this page), and left of it, while a vendor is open, "Sell all Poor (<n>)".

Position: saved as its top-left corner when dragged. When it opens by itself while looting and
"Place it beside the loot window" is on (default), it goes beside the loot window
(PlumberLootWindow or LootFrame, 12 apart, on the right unless that runs off screen); dragging it
then turns the option off and keeps the new spot. Otherwise it opens at the saved spot.

Opens when: the game reports the inventory is full (ERR_INV_FULL / ERR_BAG_FULL) and "Open when
your bags are full" is on (default); a loot window opens with at most "this many free slots"
(0 = off, default); `/nas cheap`; "Open pop-up" on the page. A pop-up that opened by itself (the
first two) closes with the loot window. The loot window is tracked by LootFrame's OnShow/OnHide as
well as LOOT_READY / LOOT_OPENED / LOOT_CLOSED, as LOOT_OPENED does not always fire on Forever.

Actions: none in combat, none while the cursor holds something, and each re-checks that the slot
still holds the listed stack. Delete picks the stack up and calls DeleteCursorItem; for items the
game asks about, the game's own dialog decides. Sell uses the vendor. Ignore adds the item to a
per-character list. After a delete during looting, "Keep looting after deleting" (default on)
loots at once everything that fits (the freed slot and any other free slots, plus room on existing
stacks; quest items first, then highest vendor value), as the server handles the delete before the
loot requests. When the game's own delete dialog is shown, it loots on the first bag update that
shows a free slot instead. `/nas debug` prints a trace of the loot state and these steps.
Sell all Poor sells every Poor stack with a sell price that is not ignored, one every 0.15 s,
and stops if the vendor closes or combat starts. The "Delete cheapest item" keybinding
(Bindings.xml, category Nascent) is Delete on the first listed stack, with the same confirmation.

Page cards: "In your bags" (up to 10 rows, Open pop-up / Refresh / Sell all Poor, a muted hint
about the clicks and the keybinding), "What is listed" (quality grid
of checkboxes 3 per row with names in quality colours, Skip soulbound items), "Pop-up" (also
Place it beside the loot window),
"Deleting" (Confirm before deleting, Keep looting after deleting, Use auction prices),
"Ignored items" (rows 28 high: icon 18, name, Remove; Clear all).
