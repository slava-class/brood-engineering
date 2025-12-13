# TODO

## Module + Inventory Edge Cases (needs tests)

- Toggling off spiderlings doesn’t return all carried items to the anchor inventory.
- Module fill orders sometimes consume more modules than required (possibly taking full stacks).
- Other module-insertion edge cases to cover:
  - Mixed qualities and partially-filled module inventories.
  - Proxies that specify exact slots vs. “any slot” behavior.
  - Multiple proxies targeting the same entity / overlapping plans.
  - Removal plans (swap modules) and “wrong module already in slot”.
  - Entities with different module inventory ids/sizes (assemblers, refineries, beacons, etc.).

## Blueprint Requests Not Clearing (bug)

- After a module is inserted according to a blueprint, the blueprint/item-request-proxy still requests that module slot be filled.
- Reference implementation to inspect (don’t modify yet): `~/Library/Application Support/Factorio/mods/spiderbots_0.4.0/`

