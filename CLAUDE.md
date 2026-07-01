# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Second Life (SL) multiplayer RPG HUD system called "Corruption RPG". Players wear the Sub HUD to track their "corruption" progression (XP, levels, titles). A separate Dom HUD tracks Dom stats. Scripts are written in LSL (Linden Scripting Language) and cannot be run locally — changes are uploaded to SL objects via the in-world script editor.

There is no build system, test runner, or linter. Development is: edit files locally → upload to SL object → test in-world.

## LSL Hard Constraints

- **No ternary operator** (`? :` does not exist) — always use `if/else`
- **64KB compiled Mono limit per script** — `CorruptionCore.lsl` is near this limit (~53KB); do not add code to it without removing comparable amounts
- **`llResetScript()` wipes all in-script globals** but does NOT clear Linkset Data (LSD)
- **`llSetText()` persists across resets** — must be explicitly cleared in `state_entry()` and `attach()` after ownership changes
- **`llGetOwnerKey(llGetKey())` is unreliable** on your own object — use `id == llGetKey()` instead for same-object filtering
- All cross-script booleans that must survive a reset (e.g. `isPendingRestore`) must be persisted in LSD before calling `llResetScript()`

## Repository Layout

```
CorruptionHUD Sub/   ← Sub HUD scripts (11 LSL files)
CorruptionHUD Dom/   ← Dom HUD scripts (8 LSL files, parallel structure)
index.html           ← Sub Media HUD main display (hash-driven, no server)
achievements.html    ← Sub achievements panel
leaderboard.html     ← Public rankings (Subs only; doms tab removed)
dom.html             ← Dom Media HUD display
dom-achievements.html
owner.html           ← Owner panel (dead — owner system removed; .bak kept)
```

HTML files are deployed to GitHub Pages at `https://raylapetal.github.io/corruption-media-hud/`.

## Sub HUD Script Map

The Sub HUD spans **two worn SL objects**:

**Monitor linkset** (the HUD prim itself — all scripts share Linkset Data):
| Script | Role |
|---|---|
| `CorruptionCore.lsl` | Central brain: XP/level/title, cum processing, state persistence |
| `CorruptionDB.lsl` | Supabase cloud backup + public leaderboard uploads |
| `CorruptionDialog.lsl` | All SL dialog menus, user input |
| `CorruptionImmersion.lsl` | Arousal engine, PA integration, Lovense haptics |
| `CorruptionMatch.lsl` | Mate-matching over MATCH_CHAN (feature-flagged off) |
| `CorruptionOverlay.lsl` | Floating text renderer (owns its own page rotation) |
| `CorruptionRewards.lsl` | Stateless achievement/goal evaluator — grants are sent to Core |
| `CorruptionVersion.lsl` | Version check on attach; notifies owner if a newer build is on the marketplace |
| `CumRelay.lsl` | Normalizes Spunked or INM cum events → Core's 10-slot packet |

**Separate worn Media HUD object**:
| Script | Role |
|---|---|
| `CorruptionMediaHUD.lsl` | Drives the media-face HTML display; handles URL endpoint for page interactions |

## Key Communication Channels

| Constant | Value | Direction |
|---|---|---|
| `HUD_CHAN` | -87432 | Core → all (region say + linkset link_message) |
| `DOM_HUD_CHAN` | -87440 | DomCore broadcast |
| `MATCH_CHAN` | -87460 | Region handshake between sub and dom HUDs |
| `CUM_EVENT` | 90100 | CumRelay → Core: cum deltas + instigator key |
| `DB_RESTORE` | 88003 | CorruptionDB → Core: cloud restore complete ("1"=found, "0"=fresh) |
| `DB_FLUSH` | 88004 | Core → CorruptionDB: upload snapshot immediately |
| `MENU_CMD` | 88002 | Dialog → Core: menu action |
| `MENU_STATE` | 88001 | Core → Dialog: full state broadcast |

Scripts within the same linkset communicate via `llMessageLinked(LINK_SET, ...)`. Scripts in separate worn objects (Media HUD) communicate via `llRegionSay`/`llRegionSayTo`.

## Broadcast Format (HUD_CHAN)

`updateDisplay()` in Core builds a pipe-separated string: `"hud|<field1>|<field2>|..."`. **Field indices are fixed** — every consumer (Overlay, DB, Rewards, MediaHUD, Dom HUD) addresses fields by number. Adding new fields must be **append-only** at the end of the string. Key indices:

- 1=xp, 2=level, 3=prestige, 4=titleIdx, 5=totalPartners, 6=totalHits
- 15=selectedTitleIdx (integer index; **NOT a string** — consumers resolve name via TITLES array), 16=nextTitleIdx
- 22=achFlags, 26=notoriety, 37=difficulty, 38=lastPartnerName
- 32-36=live cum stacks (face/chest/pussy/ass/body)
- 41=hapticsOn, 49=immersionOn, 55-56=placeholder 0s (goal claimed bits now in Rewards/LSD), 57=adultBypass, 64=inmFlags

## Save Blob Format (LSD key `"inm_state"`)

`saveState()` writes a comma-separated string. `loadState()` reads it with `if (n >= N)` guards so old saves missing new fields load safely. **This format is append-only** — never reorder or remove fields; only add new ones at the end with matching `if (n >= N)` guards in `loadState()`.

Dom equivalent uses `"dom_state"` in the Dom linkset.

## Ownership Transfer Flow

This is the most fragile sequence in the codebase:

1. `changed(CHANGED_OWNER)` fires in Core → writes `"inm_pending_restore"="1"` to LSD (persists across the reset), deletes old state keys, calls `llResetScript()`
2. `state_entry()` reads the LSD flag → sets `isPendingRestore = TRUE`
3. `saveState()`, `updateDisplay()`, `broadcastState()` all check `isPendingRestore` and return early — no saves or broadcasts until the restore completes
4. `CorruptionDB.lsl` fires an HTTP GET to Supabase; on response it writes the blob to LSD and sends `DB_RESTORE "1"` (found) or `"0"` (fresh user) via link_message
5. Core's `DB_RESTORE` handler clears the flag, calls `loadState()`, then unblocks

**DomCore difference**: `changed(CHANGED_OWNER)` calls `llLinksetDataReset()` (nukes all LSD) then writes the pending flag — opposite order from Sub Core.

## Cloud Persistence (Supabase)

- Base URL: `https://nvaxbkqyggwfkowrtekx.supabase.co/rest/v1/`
- Sub table: `players` (keyed by `uuid`)
- Dom table: `doms` (keyed by `uuid`)
- Uploads use `POST` with `Prefer: resolution=merge-duplicates` (upsert)
- The `"save"` column holds the full comma-separated state blob for cross-device restore
- Uploads are debounced: 360s idle OR 1800s maximum since the last upload

## Matching System

`isMatchEnabled = FALSE` in `CorruptionDialog.lsl` feature-flags the Matching menu entry off. The system is mate-only (no owner/bond system — that was removed). `CorruptionMatch.lsl` handles scan/offer/reply handshake over `MATCH_CHAN` plus a passive proximity notifier.

## MediaHUD HTML Pages

Data is passed via the URL hash as a JSON object (`#<urlencoded-json>`). The LSL script calls `llSetLinkMedia(link, face, [PRIM_MEDIA_CURRENT_URL, url + "#" + llEscapeURL(json)])` to update the display. Pages use `window.addEventListener("hashchange", ...)` to re-render. The LSL script also holds an HTTPS endpoint (`gURL`) so pages can call back for panel toggles (`?ach=1`, `?sex=<0-3>`).

`ACH_COUNT` in `index.html` must match the number of achievement bits defined in `CorruptionRewards.lsl` (currently 27).

## Level System (25 levels)

`CorruptionCore.lsl` has 25 entries in `LEVEL_XP` (indices 0-24). **`TITLES` and `PRESTIGE_TITLES` now live in `CorruptionOverlay.lsl`** (moved to free Core heap). Core broadcasts `selectedTitleIdx` as an integer at field 15; consumers resolve the name themselves. Prestige titles are at `selectedTitleIdx` **25+** (index = `selectedTitleIdx - 25`).

- `PRESTIGE_GOAL = 5000000` — XP threshold of level 25 (prestige eligibility bar display)
- `ENDLESS_STEP = 800000` — per level past 25 (safety valve; prestige first)
- `clampTitle()`, `updateDisplay()`, `onLevelUp()` auto-advance, and `processMenuCmd("title")` all use `>= 25` for prestige title gating
- `CorruptionDialog.lsl` sends `"title|" + (string)(25 + pi)` for prestige title selections
- `loadState()` contains a one-time migration: old `selectedTitleIdx` 10-13 (pre-expansion prestige titles) maps to 25-28
- TITLES arrays are defined in: `CorruptionOverlay.lsl` (LSL), `index.html` (JS), `leaderboard.html` (JS) — all must stay in sync

## Additional LSL Gotchas (from broader project experience)

- **`jump` / `@label`** — LSL's only loop-break/continue mechanism; use `jump next` inside a `for` loop to implement `continue` since `break` does not exist
- **`llListReplaceList(src, repl, start, end)`** — `end` is inclusive; for stride-N records use `idx, idx + N - 1`
- **`llGetObjectDetails(key, [...])`** returns `[]` (empty list) if the avatar is no longer in the region — always guard before indexing: `if (d == []) return;`
- **Backward iteration for list deletion** — removing from a list while iterating forward corrupts indices; iterate backward, or adjust `i -= STRIDE` after forward removal
- **`(key)string` cast returns `NULL_KEY`** on an invalid UUID string — useful for detecting whether a string is a valid key without regex
- **`CHANGED_LINK`** fires for sit, unsit, AND prim attachment/detachment — don't assume the cause; check the actual seated avatar list
- **`llSetTimerEvent(0.0)`** disables the timer — don't omit the `.0` (integer arg does not compile)
- **`llAngleBetween(rotation, rotation)`** — returns a float in **radians**, not degrees; multiply by `RAD_TO_DEG` if you need degrees for display
- **`llListen` handle leak** — `llListen` returns a handle that must be stored and passed to `llListenRemove` when done; leaking handles consumes the ~65-slot per-script limit silently
- **Single-threaded, no re-entrant events** — events queue; a `timer` or `link_message` queued while another event handler runs won't interrupt it. Long-running handlers delay all queued events.
- **Settings block convention** — all user-tunable globals live in a clearly delimited block at the top of the script; never bury configurable values inside event handlers
