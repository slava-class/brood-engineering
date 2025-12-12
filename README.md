# Brood Engineering

Autonomous construction spiders that build, deconstruct, and upgrade on your behalf.

## Overview

Brood Engineering adds small spiderlings that automatically perform construction tasks near you. Simply craft spiderlings, place them in your inventory, and they will:

- **Auto-deploy** when construction work is detected nearby
- **Build** ghost entities from your blueprints
- **Deconstruct** entities and tiles marked for deconstruction
- **Upgrade** entities marked for upgrade
- **Place tiles** including landfill and other floor types
- **Handle item proxies** (module insertion, configuration changes)
- **Auto-recall** when no work remains

## Getting Started

1. Research **Brood Engineering** (unlocked by catching a fish)
2. Craft **Spiderlings** (requires electronic circuits, iron plates, inserters, and a raw fish)
3. Place spiderlings in your inventory
4. Place blueprints or mark items for deconstruction
5. Watch your brood work!

## Controls

- **Alt+B** or **Shortcut Button**: Toggle all spiderlings on/off
  - When disabled, all deployed spiders return to your inventory
  - When enabled, spiders will deploy automatically when work exists

## How It Works

### Two-Tier Task Assignment

Spiderlings use a smart task assignment system:

1. **Anchor Assignment**: Your character scans a large area (40 tiles) for work and assigns tasks to idle spiders
2. **Self-Assignment**: Individual spiders scan their immediate area (8 tiles) and can pick up nearby tasks without returning to you

This prevents wasted trips when there's work near a spider's current location.

### Task Priority

Tasks are executed in priority order:

1. Deconstruct entities blocking ghost placement
2. Place foundation tiles (landfill)
3. Build entity ghosts
4. Upgrade entities
5. Handle item proxies
6. Deconstruct remaining entities
7. Place non-foundation tiles
8. Deconstruct tiles

### Auto-Deploy & Recall

- Spiders deploy from your inventory when work exists and you're below the maximum count
- Spiders recall to your inventory after being idle near you for 4 seconds
- All spiders teleport to you if you move far suddenly (teleportation, vehicle entry)

## Configuration

Access mod settings to configure:

- **Show Item Projectiles**: Visual effect showing items traveling from your inventory to building spiders

## Tips

- Spiders work faster when you're near the construction area
- Keep a stock of spiderlings in your inventory for automatic deployment
- The global toggle (Alt+B) is useful when you need spiders to stop immediately
- Spiders can pick up items on the ground that are marked for deconstruction

## Future Plans

This mod is designed with expansion in mind:

- **Webs/FOBs**: Deployable bases that act as spider anchors with their own inventory
- **Spider Castes**: Specialized spiders (builders, cutters, haulers, crafters)
- **Mother Zero**: Transform into the brood mother - a spidertron that cannot handcraft

## Compatibility

Built for Factorio 2.0. Should be compatible with most mods. If you encounter issues, please report them.

## Credits

Inspired by the Spiderbots mod by asher_sky. Rebuilt from scratch with a cleaner architecture for extensibility.

## Development

### Running tests (FactorioTest)

This repo includes a small in-game test suite under `tests/` that runs via FactorioTest.

Prerequisites:

- Factorio 2.0 installed locally.
- `bun` installed via `mise` (see `.mise.toml`).
- Node 18+ available on PATH (needed because FactorioTest CLI currently calls `npx fmtk` internally).

Setup:

1. Install tools: `mise install`
2. Install dev dependencies: `bun install`
3. Run tests: `bun run test:factorio -- --factorio-path /path/to/factorio`

Notes:

- The CLI creates an isolated data dir at `./factorio-test-data-dir` by default.
- Only `brood-engineering` and `factorio-test` are enabled unless you pass `--mods ...`.
- Extra args after `--` are forwarded to Factorio (e.g., `--disable-audio --graphics-quality low`).
- On macOS app bundles, FactorioTest CLI may generate an incorrect `read-data` path. If you see “There is no package core…”, edit `factorio-test-data-dir/config.ini` to use `read-data=__PATH__executable__/../data` (or an absolute path to `factorio.app/Contents/data`). The CLI will keep that line on subsequent runs.
