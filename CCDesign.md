# Currency Catalog — Design & Status (CCDesign.md)

This file is the project's institutional memory. It exists so that any new
Claude session (or human) can pick up the addon cold and keep working in the
same spirit without re-deriving decisions from the code. Keep it current: when
a design decision changes or a release ships, update this file in the same
commit.

Last updated: 2026-11-23. Current release: **v1.2.3** (v1.2.4 maintenance update committed, awaiting in-game test before tagging). Author: Shannon (GitHub `SJLDeveloper`).

---

## 1. What the addon is

Currency Catalog is a World of Warcraft **Retail** addon that answers one
question: *"What can I buy with this currency, and where?"*

- It learns **live**, by scanning every vendor the player opens. There is no
  bundled database and no external data source. Coverage grows as you play.
- It records only items whose cost includes a **non-gold currency** (Valorstones,
  Timewarped Badges, Resonance Crystals, etc.). Gold-only items are ignored.
- It opens a window **docked to the right of the character sheet**, showing one
  currency at a time: your balance, a searchable item list, and a sort/group
  dropdown.
- Clicking an item opens a **detail panel** listing every vendor known to sell
  it, with zone and coordinates. Clicking a vendor sets a **TomTom** waypoint,
  or Blizzard's built-in map pin / super-track when TomTom isn't installed.
- A small **coin icon on each row of the Currency tab** (character sheet) opens
  the catalog pre-filtered to that currency. `/cc` toggles the window.

Shannon's own one-line description: "catalogs metacurrencies and maintains
links to and appropriate lists of items you've discovered that use that
metacurrency."

## 2. Project philosophy and working rules

These were set explicitly by Shannon and should be treated as standing policy.

1. **Maintenance, not rewrite.** v1.2.3 works well and largely as intended. The
   job is to keep it working as WoW patches change APIs, fix Lua errors as they
   appear, and make small improvements. Do not restructure for its own sake.
2. **Defensive against Blizzard.** Blizzard UI internals change every patch.
   Every hook into Blizzard frames is wrapped in `pcall`; every API is
   feature-detected (`C_X and C_X.Fn`) with a legacy fallback where one exists;
   a failed hook must never prevent the addon from loading. `/cc` must always
   work even if the Currency-tab icons break.
3. **Handle "secret" values.** On some restricted/instanced units, `UnitGUID`,
   `UnitName`, and tooltip text return *secret* values that throw when indexed,
   concatenated, or matched. Any code touching those must go through `pcall`
   (see `npcIDFromGUID`, `recordVendor`, `getNPCTitle` in `Scanner.lua`).
4. **No external deps required.** TomTom is `OptionalDeps`, never required.
5. **Version bump = two places.** `ns.version` in `Core.lua` and `## Version`
   in `CurrencyCatalog.toc` move together. `## Interface:` tracks the live
   client build (`/run print((select(4, GetBuildInfo())))`).
6. **Don't touch other addons.** When a live `Interface/AddOns` folder is
   connected, only `AddOns/CurrencyCatalog/` may be read or written. Everything
   else there is off-limits unless Shannon explicitly asks.

## 3. Repository and workflow

- GitHub: `https://github.com/SJLDeveloper/CurrencyCatalog.git`, branch `main`.
- Layout is **flat**: the seven addon files sit at the repo root (no
  `CurrencyCatalog/` subfolder). Installing means creating
  `Interface\AddOns\CurrencyCatalog\` and copying the files in.
- Releases are **annotated git tags** `vX.Y.Z`. The older convention of dated
  "(lock-off)" snapshot folders is retired.
- Commit identity: `Shannon <66124490+SJLDeveloper@users.noreply.github.com>`.
  Commits made with Claude carry a `Co-Authored-By: Claude ...` trailer.
- `.gitignore` covers OS/editor junk and `*.zip`.

### Edit → test → release loop

1. Edit files in the repo.
2. Copy the seven addon files into the live
   `World of Warcraft/_retail_/Interface/AddOns/CurrencyCatalog/`.
3. Shannon runs `/reload` in game and reports behaviour or pastes the Lua error.
4. Iterate. Commit when it works.
5. When stable: bump version (two places), update §8 of this file, tag `vX.Y.Z`, push.

Drift check between repo and live install (bash):

    for f in Core.lua CurrencyButton.lua CurrencyCatalog.toc README.md Scanner.lua TomTom.lua UI.lua; do
      cmp -s "$f" "<AddOns>/CurrencyCatalog/$f" || echo "DIFFERS: $f"
    done

### Environment notes learned the hard way

- In Cowork sessions linked to Shannon's computer ("marigold"), git in the
  mounted repo needs **delete permission** on the folder or it leaves stale
  `.git/index.lock` / `HEAD.lock` / `tmp_obj_*` files behind. Request it at the
  start of any session that will commit; `rm -f .git/*.lock` if a prior session
  left one.
- Cowork sessions started from a local folder have **no per-session GitHub
  repository binding**, so `git push` from Claude fails even though the account
  GitHub connection is valid. Pushing requires either Shannon's own terminal or
  a Claude Code cloud session started with the repo selected.
  *Workaround that works (2026-11-17):* commit locally, `git bundle create cc.bundle main`
  in the repo, stage it to the cloud container, attach the repo there with push access,
  shallow-clone, `git fetch cc.bundle main:local-main`, push `local-main:main`, then delete
  the bundle and `git update-ref refs/remotes/origin/main <sha>` locally. Ref *deletions*
  (tags/branches) are blocked by the proxy and must be done from Shannon's terminal.
- The WTF/SavedVariables folder (`CurrencyCatalog.lua` saved data) has never
  been connected. Ask before requesting it.

## 4. Architecture

Load order (from the TOC): `Core.lua` → `Scanner.lua` → `TomTom.lua` → `UI.lua` → `CurrencyButton.lua`.
All files share one private namespace table `ns` via `local ADDON, ns = ...`.
Nothing is global except the saved variable `CurrencyCatalogDB`, the slash
commands, and a few named frames (`CurrencyCatalogFrame`, `CurrencyCatalogDetail`,
`CurrencyCatalogSearch`, `CurrencyCatalogItemScroll`, `CurrencyCatalogSortDrop`,
`CurrencyCatalogScanTip`).

### Core.lua (~160 lines) — bootstrap, helpers, slash commands
- `DB_DEFAULTS` + `applyDefaults()` fill missing keys without overwriting user data. `ns.db` is bound on `ADDON_LOADED`.
- `ns.Print(...)` — prefixed chat print.
- `ns.CurrencyIDFromListIndex(index, info)` — resolves a real currencyID from a Currency-tab list index; `GetCurrencyListInfo` does *not* reliably expose `currencyTypesID`, so it falls back to parsing the row's link.
- `ns.GetHeldCurrencies()` — `currencyID -> {name, icon, quantity}` for everything the player holds (lets the catalog show currencies before any vendor is scanned).
- `ns.GetCurrencyQuantity(id)`, `ns.RememberHeldCurrencies()`.
- `PLAYER_LOGIN`: remembers held currencies, calls `ns.OnLogin()` (defined in UI.lua), prints a "N vendors, M items known" greeting.
- Slash `/cc`, `/currencycatalog`: no arg = toggle UI; `stats`; `wipe` (clears items+vendors, keeps currencies); `debug` (dumps item classification for up to 40 items — groundwork for a category view).

### Scanner.lua (~250 lines) — the data source
- Listens to `MERCHANT_SHOW` and `MERCHANT_UPDATE`; waits 0.2s (item data can be momentarily unavailable), checks `MerchantFrame:IsShown()`, then `pcall(scanMerchant)`.
- `recordVendor()`:
  - npcID from `UnitGUID("npc")` via pcall'd `string.match(guid, "%-(%d-)%-%x+$")`.
  - Fallback keys when the GUID is secret/unavailable: `"loc:<mapID>:<x*1000>:<y*1000>"` (preferred, so distinct restricted vendors don't collide) or `"name:<name>"`.
  - Name sanitised through a pcall'd concat test (secret names throw on concat).
  - Title (the gray `<Quartermaster>` line) via `C_TooltipInfo.GetUnit("npc")` line 2, rejecting it if it contains the localized `LEVEL` word; falls back to a hidden `GameTooltip` scan. Keeps a previously captured title if the read fails.
  - Location from `C_Map.GetBestMapForUnit("player")` + `GetPlayerMapPosition`. Only stored when x,y > 0.
- `readCosts(index, basePrice)` iterates `GetMerchantItemCostInfo/GetMerchantItemCostItem`; keeps only cost links containing `currency:`; sums duplicates; also refreshes `ns.db.currencies[cid]` name/icon. **Item-based extended costs are deliberately skipped** (design choice; "easy to add later").
- `merchantItemInfo(index)` prefers `C_MerchantFrame.GetItemInfo(index)` (returns a table) and falls back to the removed global `GetMerchantItemInfo`.
- `scanMerchant()` stores per item: name, icon, link, quality, classID, subClassID, equipLoc, itemType, itemSubType, cosmetic (via `C_Item.IsCosmeticItem`), gold (copper), `costs`, and `vendors[npcID] = true`.
- **Pruning:** after a scan, any catalogued item that lists this vendor but wasn't offered is detached from the vendor; if no vendors remain the item is dropped. Pruning is skipped when the merchant filter isn't "all" (`GetMerchantFilter() ~= LE_LOOT_FILTER_ALL`) because the list may be partial. This keeps rotating stock and one-time purchases honest.

### TomTom.lua (~45 lines) — navigation
- `ns.NavigateToVendor(rec)`: requires `mapID, x, y`; prints a hint if missing.
- Prefers `TomTom:AddWaypoint(mapID, x, y, {title, from="Currency Catalog", persistent=false, minimap=true, world=true})` under pcall.
- Fallback: `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(...))` + `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`.

### UI.lua (~560 lines) — the window
- Constants: `ROW_H=26`, `ITEM_ROWS=14`, `FRAME_W=430` (wide enough for e.g. "Displaced Corrupted Mementos"), `LIST_TOP=132`, `FOOTER=36`; `FRAME_H` derived.
- Main frame `CurrencyCatalogFrame`: `BackdropTemplate`, opaque dark background, strata `HIGH`, movable. Header = selected currency icon + name + "You have: N". Search `EditBox` (`InputBoxTemplate`) + sort dropdown (`WowStyle1DropdownTemplate`, created under pcall so a template change can't break load). Item list is a `FauxScrollFrameTemplate` with 14 reusable row buttons.
- Sort modes (`ns.sortMode`): `"alpha"` and `"vendor"`. Vendor mode builds **Zone → Vendor → items** rows with collapsible headers (`[+]`/`[-]`, count on the right). Default collapse state: zones collapsed except the player's **current zone**; vendors collapsed. User toggles are remembered in `ns.collapsed.{zone,vendor,category}` for the session only.
- Row rendering (`updateItemScroll`) distinguishes header rows (gold text, indent 0/16) from item rows (icon, quality-coloured name, cost on the right, indent 32 in vendor mode). Item rows show the item tooltip on hover.
- Detail panel `CurrencyCatalogDetail` anchored to the frame's right: icon, quality-coloured name, "Cost:" line (all currencies + gold), and one `UIPanelButtonTemplate` per vendor showing `Name <Title>` / `Zone (x.x, y.y)` or "(location not captured — visit once)". Clicking a vendor button calls `ns.NavigateToVendor`.
- Docking: `ns.ShowUI()` anchors `TOPLEFT` to `CharacterFrame`'s `TOPRIGHT` (+6) when the character frame is shown; `ns.OnLogin()` hooks `CharacterFrame OnHide` to hide the catalog.
- Default currency when opened without a choice: the held currency with the largest balance.
- Public API: `ns.ShowUI`, `ns.HideUI`, `ns.ToggleUI`, `ns.OpenForCurrency(id)` (alias `ns.SelectCurrency`), `ns.RefreshUI` (no-op unless the frame is shown; Scanner calls it after each scan).

### CurrencyButton.lua (~160 lines) — Currency-tab integration
- Hooks `Blizzard_TokenUI` when it loads (`ADDON_LOADED` for `Blizzard_TokenUI`, or at `PLAYER_LOGIN` if already loaded).
- `decorateTokenFrame()` walks visible rows via the modern `TokenFrame.ScrollBox:GetFrames()` path, with a legacy `TokenFramePanel.buttons` fallback, and attaches an 18px coin button (`Interface\Icons\inv_misc_coin_02`) at the right edge of each currency row. `resolveCurrencyID(row)` tries `row.currencyTypesID`, the ScrollBox element data, then `ns.CurrencyIDFromListIndex`.
- Re-decorates on `ScrollBox.Event.OnUpdate`, `ScrollBox.Update`, `TokenFrame.Update`, and `TokenFrame OnShow` (all pcall-wrapped).
- `ensureFooterButton()` creates a "Catalog" `UIPanelButtonTemplate` above the list. **Currently disabled** — the call in `hookTokenFrame()` is commented out. Re-enable by uncommenting `pcall(ensureFooterButton)`.

## 5. Saved data (`CurrencyCatalogDB`, `version = 1`)

    currencies[currencyID] = { name, icon }
    vendors[npcID]         = { name, title, mapID, zone, x, y, last }
                             -- npcID: number, or string "loc:<map>:<x>:<y>" / "name:<name>"
    items[itemID]          = { name, icon, link, quality,
                               classID, subClassID, equipLoc, itemType, itemSubType, cosmetic,
                               costs = { [currencyID] = amount },
                               gold = copper | nil,
                               vendors = { [npcID] = true } }
    settings = { autoOpenWithCharFrame = false }   -- defined, not yet read by any code

Account-wide (not per character). `/cc wipe` clears `items` and `vendors` only.
If the shape ever changes, bump `version` and migrate in `applyDefaults`'s caller.

## 6. Blizzard API surface (check these first when a patch breaks something)

| Area | APIs |
|------|------|
| Currency | `C_CurrencyInfo.GetCurrencyListSize`, `.GetCurrencyListInfo`, `.GetCurrencyListLink`, `.GetCurrencyIDFromLink`, `.GetCurrencyInfo` |
| Merchant | `GetMerchantNumItems`, `GetMerchantItemLink`, `C_MerchantFrame.GetItemInfo` (fallback `GetMerchantItemInfo`), `GetMerchantItemCostInfo`, `GetMerchantItemCostItem`, `GetMerchantFilter`, `LE_LOOT_FILTER_ALL` |
| Items | `C_Item.GetItemInfoInstant`, `C_Item.GetItemInfo` (globals `GetItemInfoInstant`/`GetItemInfo` kept only as fallback; their shims were removed in 12.1.5), `C_Item.IsCosmeticItem`, `C_Item.GetItemQualityColor`, `GameTooltip:SetItemByID` |
| Units / tooltips | `UnitGUID`, `UnitName`, `C_TooltipInfo.GetUnit`, `TooltipUtil.SurfaceArgs`, hidden `GameTooltipTemplate` fallback, `LEVEL` global string |
| Map / nav | `C_Map.GetBestMapForUnit`, `.GetMapInfo`, `.GetPlayerMapPosition`, `.SetUserWaypoint`, `UiMapPoint.CreateFromCoordinates`, `C_SuperTrack.SetSuperTrackedUserWaypoint`, `TomTom:AddWaypoint` |
| UI templates | `BackdropTemplate`, `FauxScrollFrameTemplate` (+ `FauxScrollFrame_*` helpers), `WowStyle1DropdownTemplate` / `DropdownButton` with `SetupMenu`/`CreateRadio`, `InputBoxTemplate`, `UIPanelButtonTemplate`, `UIPanelCloseButton`, `BreakUpLargeNumbers`, `C_CurrencyInfo.GetCoinTextureString` (global `GetCoinTextureString` fallback only; shim removed in 12.1.5) |
| Blizzard frames hooked | `CharacterFrame` (OnHide), `TokenFrame` / `TokenFrame.ScrollBox` / legacy `TokenFramePanel.buttons`, `MerchantFrame` (IsShown only) |
| Events | `ADDON_LOADED`, `PLAYER_LOGIN`, `MERCHANT_SHOW`, `MERCHANT_UPDATE` |

Known fragile spots, in order of likelihood to break on a patch:
1. `CurrencyButton.lua` row decoration (TokenUI layout churn). Failure mode is cosmetic — icons vanish; `/cc` still works.
2. `WowStyle1DropdownTemplate` sort dropdown (guarded; failure = no dropdown, alpha sort only).
3. `C_MerchantFrame.GetItemInfo` field names (`name, texture, price, numAvailable, isPurchasable, hasExtendedCost`).
4. `C_TooltipInfo` line structure for vendor titles.

## 7. Known limitations and deliberate non-features

- Only vendors you have opened are known; a vendor's coordinates are captured the first time you open it in the world. Vendors reached via UI with no physical NPC may have no location.
- Item-for-item costs (e.g. "5× Mark of Honor") are skipped on purpose.
- Sort mode and collapse state are not persisted across sessions.
- `settings.autoOpenWithCharFrame` exists in the DB but nothing reads it.
- The "Catalog" header button on the Currency tab is written but disabled.
- A **category** grouping (by `classID`/`subClassID`/`cosmetic`) is prepared for — the scanner stores the fields, `/cc debug` dumps them, and `ns.collapsed.category` exists — but no `"category"` sort mode has been implemented. This is the most obvious next feature if Shannon wants one.

## 8. Status and history

| Version / commit | Date | Notes |
|------------------|------|-------|
| v1.2.3 (`4cfd9ae`) | 2026-09-03 | Current stable release. Deployed to live AddOns folder. Tagged `v1.2.3`. Stray duplicate `vv1.2.3` deleted locally 2026-11-17 but **still on GitHub** — remove with `git push origin :refs/tags/vv1.2.3` from Shannon's terminal (Claude's proxy blocks remote tag deletion). |
| `82857e2` | 2026-09-22 | Add `.gitignore`. Pushed. |
| `3f88027` | 2026-11-17 | README corrections (flat-layout install steps, removed disabled-button mention, version footer). No code change. |
| `4442cb8` | 2026-11-17 | Add `CCDesign.md`. |
| (housekeeping) | 2026-11-17 | Removed stray `vv1.2.3` tag; Lua syntax check of all five files clean; pushed `main` to GitHub (`v1.2.3` tag was already there). |
| v1.2.4 (`d5c0626`, untagged) | 2026-11-23 | Maintenance for Retail 12.1.5 (build 70783). TOC Interface 120100 → 120105. Replaced removed deprecation-shim globals: `GetItemInfoInstant`/`GetItemInfo` → `C_Item.*` (Scanner.lua), `GetCoinTextureString` → `C_CurrencyInfo.GetCoinTextureString` (UI.lua), each keeping the old global as fallback. Deployed to live AddOns folder; **needs `/reload` test** (open a currency vendor, confirm scan + detail-panel gold line), then tag `v1.2.4` and push. |

Current state: v1.2.4 deployed to live, awaiting Shannon's in-game verification. Live install matches repo HEAD.

Patch-tracking note: Blizzard removed the `Blizzard_Deprecated*` compatibility addons in 12.1.5, so **any** remaining use of a pre-C_ global that once had a shim will now be a nil call. When a future patch lands, grep the code for bare globals and compare against the wiki page `Patch_<ver>/API_changes`. Next known PTR: 12.1.7 (Interface 120107).

## 9. How to brief a fresh session

Paste or attach this file and say: *"Read CCDesign.md first; it is authoritative
for design intent and working rules. The code is in the repo root. Follow §2
and §3 before changing anything."* Then describe the bug or change. Expect the
session to read the relevant Lua file(s) rather than the whole codebase; the
file-by-file notes in §4 are meant to make that targeting fast.
