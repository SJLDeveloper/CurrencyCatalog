# Currency Catalog

A World of Warcraft (Retail) addon that catalogs everything you can buy with
**non-gold currencies**, learned automatically as you visit vendors, and shows
it in a window docked beside your character sheet. Click an item to see who
sells it, and click a vendor to drop a TomTom (or built-in) waypoint.

## What it does

- **Live scanning.** Every time you open a vendor, it records each item that
  costs a non-gold currency, the amount, and the vendor's NPC, zone, and map
  coordinates.
- **Catalog window.** Docks to the right of the character sheet. Pick a currency
  on the left, search/scroll items on the right.
- **Item to vendor.** Click any item to open a detail panel listing every vendor
  that sells it (with location).
- **Waypoints.** Click a vendor to set a TomTom waypoint. If TomTom isn't
  installed, it uses Blizzard's built-in map pin / super-tracking instead.
- **Currency-row icon.** Adds a small coin icon next to each currency on the
  character sheet's Currency tab; clicking it opens the catalog filtered to that
  currency.

## Install

1. Create a folder named `CurrencyCatalog` inside
   `World of Warcraft\_retail_\Interface\AddOns\` and copy all the files from
   this repository into it (so you end up with
   `...\AddOns\CurrencyCatalog\CurrencyCatalog.toc`).
2. Restart the game, or `/reload` if already logged in.
3. (Optional) Install **TomTom** for arrow-style navigation.

### Set the interface version

If the addon shows as "out of date", either tick **Load out of date AddOns**
on the character-select AddOns screen, or update the first line of
`CurrencyCatalog.toc`. To find your current build number, log in and run:

```
/run print((select(4, GetBuildInfo())))
```

Put that number on the `## Interface:` line.

## Usage

- Open your character sheet, go to the **Currency** tab, and click the coin icon
  next to a currency.
- `/cc` or `/currencycatalog` — toggle the catalog window.
- `/cc stats` — print how many items/vendors have been catalogued.
- `/cc wipe` — clear all scanned item/vendor data (currencies are kept).

## Notes & limitations

- The catalog only knows about vendors you've actually opened. It fills in over
  time as you play. (This was the intended design — no external database.)
- A vendor's coordinates are captured the first time you open it in the world.
  Vendors reached through a UI with no physical NPC may not have a location.
- Only **currency** costs are catalogued. Item-for-item trades (e.g. paying with
  another item) are intentionally skipped; that's a straightforward future add.
- Per-row currency icons depend on Blizzard's Currency tab layout, which changes
  between patches. If a patch breaks them, the **Open Catalog** button and `/cc`
  always work.

## Files

| File | Purpose |
|------|---------|
| `CurrencyCatalog.toc` | Addon manifest / load order |
| `Core.lua` | Saved variables, helpers, slash commands |
| `Scanner.lua` | Merchant + vendor-location scanning |
| `TomTom.lua` | Waypoint integration (TomTom + fallback) |
| `UI.lua` | Catalog window, currency/item lists, detail panel |
| `CurrencyButton.lua` | Currency-tab icon + footer button |

Version 1.2.3
