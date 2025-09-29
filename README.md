# RP Crafting System

A fully featured FiveM crafting system for the ESX framework featuring configurable stations, recipe management, NUI-driven player and admin menus, queueing, durability, blueprints, and optional persistence via JSON or SQL.

## Features

- **Configurable crafting stations** with radius, job/grade/item requirements, and optional opening hours.
- **Custom HTML/CSS/JS NUI** for both player crafting and the admin control panel.
- **Proximity-based interaction** (`E` keyboard or controller `A`) using `RegisterKeyMapping` with floating 3D hints.
- **Advanced recipe rules** including tools, account money, society fees, cooldowns, quality rolls, metadata, durability, and optional minigame.
- **Queue based crafting** with cancel support, progress bar, prop animations, and server-side validation/anti-dupe logic.
- **Blueprint-aware UI** that hides locked recipes until the player owns the matching item.
- **Admin menu** (`/craftadmin`) to create, edit, delete, import/export stations and recipes, plus runtime toggles for the minigame, durability, animations, and craft fees.
- **Live sync** between server and clients with exports/events for integration with other resources.
- **Persistence layer** switchable between JSON files and MySQL (schema included).

## Installation

1. Ensure you are running the latest stable ESX build (Lua 5.4 enabled) and have `mysql-async` (or compatible) installed if using SQL persistence.
2. Clone or copy this resource into your server's `resources` directory as `rp_crafting`:

   ```bash
   git clone https://example.com/rp_crafting.git
   ```

3. Add the resource to your `server.cfg` after ESX:

   ```cfg
   ensure rp_crafting
   ```

4. Configure `config.lua` as needed (see below). Switch `Config.Persistence` to `sql` if you prefer database storage and import `data/schema.sql` into your database.

5. Restart your server or run `refresh` + `ensure rp_crafting`.

## Commands

| Command | Description | Permissions |
| ------- | ----------- | ----------- |
| `/craftadmin` | Opens the admin management menu. | ESX admin/superadmin/god |

Players interact with crafting stations using the mapped key:
- Keyboard: `E`
- Controller: `A`

Key mappings can be adjusted by players through the GTA controls menu.

## Configuration

`config.lua` exposes the primary toggles:

- `Config.Persistence` – `json` (default) or `sql`.
- `Config.Crafting` – Progress update cadence, cancel radius, default cooldown, minigame toggle, durability toggle, fee behaviour, queue limit, and society account options.
- `Config.Animations` – Enable/disable crafting animation + default dictionary/prop definitions.
- `Config.Hints` – Range/appearance for the floating 3D hint.
- `Config.Commands.Admin` – Command label for the admin menu.
- `Config.RateLimit` – Anti-spam protection for crafting/admin actions.

Toggling minigame, durability, animations, or fees at runtime can be done from the admin menu settings tab and are synced to all clients.

## Data Files & Persistence

- `data/stations.json` – Default stations (Vespucci Workbench, Sandy Kitchen, Mining Forge).
- `data/recipes.json` – Eight example recipes showcasing tools, fees, durability, blueprints, and metadata usage.
- `data/schema.sql` – SQL schema for `crafting_stations` and `crafting_recipes` tables.

When using JSON persistence, edits via the admin panel are written back to the JSON files. For SQL mode, updates are pushed via `REPLACE` queries.

## NUI Overview

The UI is fully keyboard/mouse and controller friendly. Tabs include:

- **Recipes** – Searchable/filterable list with icons, requirements, and craft queueing.
- **Queue** – Active queue view with cancel option.
- **Blueprints** – Reference of blueprint items associated with visible recipes.
- **Admin** – Station/recipe management, settings toggles, JSON import/export.

A timing-based minigame can be enabled per recipe or globally disabled. On failure, the craft queue is cancelled server-side and inputs refunded.

## Exports & Events

**Server exports:**

- `exports['rp_crafting']:AddRecipe(recipeTable)`
- `exports['rp_crafting']:RemoveRecipe(recipeId)`
- `exports['rp_crafting']:AddStation(stationTable)`
- `exports['rp_crafting']:RemoveStation(stationId)`

**Server events:**

- `crafting:started` – Fired when a craft begins (`source`, `recipeId`, `stationId`).
- `crafting:finished` – Fired on completion (`source`, `recipeId`, `true/false`).
- `crafting:cancelled` – Fired when a craft cancels (`source`).

**Client events:**

- `crafting:hint` – Broadcast when hints show/hide (boolean, station data).
- `crafting:openMenu` – Open the crafting menu optionally targeting a station ID.
- `crafting:client:sync` – Internal sync for station/recipe cache.

## Integration Notes

- All item/money changes occur server-side using ESX APIs (`xPlayer.removeInventoryItem`, `addInventoryItem`, `removeAccountMoney`, etc.).
- Society fees are sent to the configured ESX addon account. A fallback removes money from the configured player account if the society account is missing.
- Tool durability expects items with `metadata.durability`. Items without metadata are treated as infinite-use tools.
- Blueprints leverage regular ESX inventory items; simply give players the configured blueprint item to unlock recipes.

## Troubleshooting

- Ensure players stand within the configured station radius and remain on-foot or the craft will cancel.
- Admin operations require ESX groups `admin`, `superadmin`, or `god`.
- If using SQL persistence, confirm the tables exist and `mysql-async` is running.
- JSON files are overwritten by admin changes; maintain backups if editing manually.

## License

This resource is provided as-is for roleplay communities. Modify freely for your server needs.
