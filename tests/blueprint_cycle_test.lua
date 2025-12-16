local constants = require("scripts/constants")
local spider = require("scripts/spider")
local blueprint_fixtures = require("tests/fixtures/blueprints")
local blueprint_test_utils = require("tests/blueprint_test_utils")

describe("blueprint build/deconstruct cycle", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local original_global_enabled
    local original_idle_timeout_ticks
    local original_no_work_recall_timeout_ticks

    local report = blueprint_test_utils.report
    local collect_blueprints = blueprint_test_utils.collect_blueprints
    local import_any_blueprint_item = blueprint_test_utils.import_any_blueprint_item

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    local function clear_area(position, radius)
        local tiles = {}
        for y = position.y - radius, position.y + radius do
            for x = position.x - radius, position.x + radius do
                tiles[#tiles + 1] = { name = "grass-1", position = { x = x, y = y } }
            end
        end
        surface.set_tiles(tiles, true)

        local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
        local area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
        for _, entity in ipairs(surface.find_entities_filtered({ area = area })) do
            if entity and entity.valid then
                if anchor_unit_number and entity.unit_number and entity.unit_number == anchor_unit_number then
                    goto continue
                end
                if entity.type == "spider-vehicle" then
                    goto continue
                end
                entity.destroy({ raise_destroyed = false })
            end
            ::continue::
        end
    end

    ---@param inv LuaInventory
    ---@param items table<string, integer>
    local function snapshot_counts(inv, items)
        local snap = {}
        for key, _ in pairs(items) do
            local name, quality = key:match("^(.-)\x1f(.*)$")
            snap[key] = inv.get_item_count({ name = name, quality = quality })
        end
        return snap
    end

    ---@param inv LuaInventory
    ---@param snap table<string, integer>
    local function assert_counts_equal(inv, snap)
        for key, expected in pairs(snap) do
            local name, quality = key:match("^(.-)\x1f(.*)$")
            local got = inv.get_item_count({ name = name, quality = quality })
            assert.is_true(
                got == expected,
                ("inventory mismatch for %s quality=%s got=%d expected=%d"):format(name, quality, got, expected)
            )
        end
    end

    ---@param blueprint LuaItemStack
    ---@return BlueprintEntity[]?
    local function get_entities(blueprint)
        local ok, ents = pcall(function()
            return blueprint.get_blueprint_entities()
        end)
        if not ok then
            return nil
        end
        return ents
    end

    ---@param blueprint LuaItemStack
    ---@return Tile[]?
    local function get_tiles(blueprint)
        local ok, tiles = pcall(function()
            return blueprint.get_blueprint_tiles()
        end)
        if not ok then
            return nil
        end
        return tiles
    end

    ---@param entity_defs BlueprintEntity[]?
    ---@param tile_defs Tile[]?
    ---@param offset MapPosition
    ---@return LuaEntity[] ghosts
    ---@return table<string, integer> required_items
    ---@return BoundingBox bounds
    ---@return { name: string, position: TilePosition }[] tile_targets
    local function place_ghosts_and_requirements(entity_defs, tile_defs, offset)
        local ghosts = {}
        local required = {}
        local tile_targets = {}

        local min_x, max_x = offset.x, offset.x
        local min_y, max_y = offset.y, offset.y

        ---@param plan BlueprintInsertPlan
        local function accumulate_insert_plan(plan)
            if not plan then
                return
            end
            local id = plan.id or {}
            local item_name = id.name
            if not item_name then
                return
            end

            local item_quality = id.quality or "normal"

            local count = 0
            local positions = plan.items
            if type(positions) == "table" then
                if type(positions.grid_count) == "number" then
                    count = count + positions.grid_count
                end
                if type(positions.in_inventory) == "table" then
                    count = count + #positions.in_inventory
                end
            end
            if count < 1 then
                count = 1
            end

            local key = tostring(item_name) .. "\x1f" .. tostring(item_quality)
            required[key] = (required[key] or 0) + count
        end

        for _, def in ipairs(entity_defs or {}) do
            local name = def.name
            local pos = {
                x = offset.x + (def.position and def.position.x or 0),
                y = offset.y + (def.position and def.position.y or 0),
            }

            if pos.x < min_x then
                min_x = pos.x
            end
            if pos.x > max_x then
                max_x = pos.x
            end
            if pos.y < min_y then
                min_y = pos.y
            end
            if pos.y > max_y then
                max_y = pos.y
            end

            local ghost = track(surface.create_entity({
                name = "entity-ghost",
                inner_name = name,
                position = pos,
                force = force,
                direction = def.direction,
                expires = false,
            }))
            assert.is_true(ghost and ghost.valid, "failed to create ghost for " .. tostring(name))

            local quality = def.quality
            local quality_name = type(quality) == "table" and quality.name or quality or "normal"
            pcall(function()
                if quality_name and quality_name ~= "normal" then
                    ghost.quality = quality_name
                end
            end)

            ghosts[#ghosts + 1] = ghost

            local prototype = prototypes and prototypes.entity and prototypes.entity[name] or nil
            assert.is_true(prototype ~= nil, "missing prototype for " .. tostring(name))
            local items = prototype.items_to_place_this or {}
            for _, item in ipairs(items) do
                local item_name = item.name
                local count = item.count or 1
                local key = tostring(item_name) .. "\x1f" .. tostring(quality_name or "normal")
                required[key] = (required[key] or 0) + count
            end

            if type(def.items) == "table" then
                for _, plan in ipairs(def.items) do
                    accumulate_insert_plan(plan)
                end
            end
        end

        for _, tile in ipairs(tile_defs or {}) do
            local name = tile.name
            local tile_proto = prototypes and prototypes.tile and prototypes.tile[name] or nil
            local items = tile_proto and tile_proto.items_to_place_this or nil
            if items and items[1] and items[1].name then
                local pos = {
                    x = offset.x + (tile.position and tile.position.x or 0),
                    y = offset.y + (tile.position and tile.position.y or 0),
                }

                if pos.x < min_x then
                    min_x = pos.x
                end
                if pos.x > max_x then
                    max_x = pos.x
                end
                if pos.y < min_y then
                    min_y = pos.y
                end
                if pos.y > max_y then
                    max_y = pos.y
                end

                local ghost = track(surface.create_entity({
                    name = "tile-ghost",
                    inner_name = name,
                    position = pos,
                    force = force,
                }))
                assert.is_true(ghost and ghost.valid, "failed to create tile ghost for " .. tostring(name))
                ghosts[#ghosts + 1] = ghost
                tile_targets[#tile_targets + 1] =
                    { name = name, position = { x = math.floor(pos.x), y = math.floor(pos.y) } }

                local item_name = items[1].name
                local count = items[1].count or 1
                local key = tostring(item_name) .. "\x1f" .. "normal"
                required[key] = (required[key] or 0) + count
            else
                report(("[Brood][BlueprintCycle] skipping non-buildable tile %s"):format(tostring(name)))
            end
        end

        local pad = 6
        local bounds = { { min_x - pad, min_y - pad }, { max_x + pad, max_y + pad } }
        return ghosts, required, bounds, tile_targets
    end

    ---@param area BoundingBox
    local function any_build_ghosts(area)
        local entity_ghosts = surface.find_entities_filtered({ area = area, type = "entity-ghost", force = force })
        if entity_ghosts and #entity_ghosts > 0 then
            return true
        end
        local tile_ghosts = surface.find_entities_filtered({ area = area, type = "tile-ghost", force = force })
        return tile_ghosts and #tile_ghosts > 0
    end

    ---@param area BoundingBox
    local function any_deconstruct_targets(area)
        local targets = surface.find_entities_filtered({ area = area, to_be_deconstructed = true, force = force })
        for _, e in ipairs(targets or {}) do
            if e and e.valid and e.type ~= "deconstructible-tile-proxy" then
                return true
            end
        end
        return false
    end

    ---@param area BoundingBox
    local function any_tile_proxies(area)
        local proxies = surface.find_entities_filtered({ area = area, type = "deconstructible-tile-proxy" })
        return proxies and #proxies > 0
    end

    ---@param area BoundingBox
    local function any_marked_tiles(area)
        local tile_force = force
        if type(tile_force) == "table" then
            tile_force = tile_force[1]
        end
        local ok, tiles_or_err = pcall(surface.find_tiles_filtered, {
            area = area,
            force = tile_force,
            to_be_deconstructed = true,
        })
        local tiles = (ok and tiles_or_err) or {}
        if not ok then
            tiles = {}
        end
        for _, tile in ipairs(tiles) do
            if tile and tile.valid and tile.to_be_deconstructed then
                local ok2, marked = pcall(function()
                    return tile.to_be_deconstructed()
                end)
                if ok2 and marked then
                    return true
                end
            end
        end
        return false
    end

    ---@param area BoundingBox
    local function order_deconstruct_everything(area)
        local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
        local entities = surface.find_entities_filtered({ area = area, force = force })
        for _, e in ipairs(entities or {}) do
            if e and e.valid then
                if anchor_unit_number and e.unit_number and e.unit_number == anchor_unit_number then
                    goto continue
                end
                if e.type == "spider-vehicle" then
                    goto continue
                end
                pcall(function()
                    e.order_deconstruction(force)
                end)
            end
            ::continue::
        end
    end

    ---@param tile_targets { name: string, position: TilePosition }[]
    local function order_deconstruct_tiles(tile_targets)
        for _, target in ipairs(tile_targets or {}) do
            local tile = surface.get_tile(target.position)
            if tile and tile.valid then
                pcall(function()
                    tile.order_deconstruction(force)
                end)
            end
        end
    end

    ---@param tile_targets { name: string, position: TilePosition }[]
    ---@param expected_name string
    local function all_tiles_are(tile_targets, expected_name)
        for _, target in ipairs(tile_targets or {}) do
            local tile = surface.get_tile(target.position)
            if not (tile and tile.valid and tile.name == expected_name) then
                return false
            end
        end
        return true
    end

    ---@param tile_targets { name: string, position: TilePosition }[]
    local function all_tiles_match_targets(tile_targets)
        for _, target in ipairs(tile_targets or {}) do
            local tile = surface.get_tile(target.position)
            if not (tile and tile.valid and tile.name == target.name) then
                return false
            end
        end
        return true
    end

    ---@param spider_ids string[]
    local function all_spiders_idle_near_anchor(spider_ids)
        local ad = storage.anchors and storage.anchors[anchor_id] or nil
        if not (ad and ad.spiders) then
            return false
        end
        for _, spider_id in ipairs(spider_ids) do
            local sd = ad.spiders[spider_id]
            if not (sd and sd.status == "deployed_idle" and spider.is_near_anchor(sd, ad)) then
                return false
            end
        end
        return true
    end

    ---@param area BoundingBox
    local function count_built_entities(area)
        local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
        local entities = surface.find_entities_filtered({ area = area })
        local count = 0
        for _, e in ipairs(entities or {}) do
            if e and e.valid then
                if anchor_unit_number and e.unit_number and e.unit_number == anchor_unit_number then
                    goto continue
                end
                if e.type == "spider-vehicle" then
                    goto continue
                end
                if e.type == "entity-ghost" then
                    goto continue
                end
                if e.type == "deconstructible-tile-proxy" then
                    goto continue
                end
                count = count + 1
            end
            ::continue::
        end
        return count
    end

    ---@param area BoundingBox
    local function assert_area_empty_except_anchor_and_spiders(area)
        local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
        local entities = surface.find_entities_filtered({ area = area })
        local leftovers = {}
        for _, e in ipairs(entities or {}) do
            if e and e.valid then
                if anchor_unit_number and e.unit_number and e.unit_number == anchor_unit_number then
                    goto continue
                end
                if e.type == "spider-vehicle" then
                    goto continue
                end
                leftovers[#leftovers + 1] = ("%s(%s)"):format(tostring(e.name), tostring(e.type))
                if #leftovers >= 8 then
                    break
                end
            end
            ::continue::
        end
        assert.is_true(#leftovers == 0, "leftover entities in blueprint area: " .. table.concat(leftovers, ", "))
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 7600 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        surface.request_to_generate_chunks(base_pos, 2)
        surface.force_generate_chunk_requests()

        original_global_enabled = storage.global_enabled
        storage.global_enabled = false

        original_idle_timeout_ticks = constants.idle_timeout_ticks
        original_no_work_recall_timeout_ticks = constants.no_work_recall_timeout_ticks
        -- Disable automatic recalls during these end-to-end cycle tests so we can assert
        -- "return to anchor" explicitly without the mod recalling spiders mid-phase.
        constants.idle_timeout_ticks = 60 * 60 * 60
        constants.no_work_recall_timeout_ticks = 60 * 60 * 60

        storage.anchors = {}
        storage.spider_to_anchor = {}
        storage.entity_to_spider = {}
        storage.assigned_tasks = {}
        storage.assignment_limits = {}
        storage.pending_tile_deconstruct = {}

        -- Ensure the area is deterministic and safe (no biters, no leftover ghosts/tasks).
        local clean_radius = 120
        local clean_area = {
            { base_pos.x - clean_radius, base_pos.y - clean_radius },
            { base_pos.x + clean_radius, base_pos.y + clean_radius },
        }
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                type = { "entity-ghost", "tile-ghost", "item-request-proxy" },
            }))
        do
            if e and e.valid then
                e.destroy({ raise_destroyed = false })
            end
        end
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                to_be_deconstructed = true,
            }))
        do
            if e and e.valid and e.cancel_deconstruction then
                e.cancel_deconstruction(force)
            end
        end
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                to_be_upgraded = true,
            }))
        do
            if e and e.valid and e.cancel_upgrade then
                e.cancel_upgrade(force)
            end
        end
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                force = "enemy",
            }))
        do
            if e and e.valid then
                e.destroy({ raise_destroyed = false })
            end
        end

        clear_area(base_pos, 25)

        anchor_entity = track(surface.create_entity({
            name = "character",
            position = base_pos,
            force = force,
        }))

        local inv = anchor_entity.get_inventory(defines.inventory.character_main)
        if inv then
            inv.clear()
        end

        anchor_id = "test_anchor_blueprint_cycle_" .. game.tick .. "_" .. math.random(1, 1000000)
        anchor_data = {
            type = "test",
            entity = anchor_entity,
            player_index = nil,
            surface_index = surface.index,
            position = { x = anchor_entity.position.x, y = anchor_entity.position.y },
            spiders = {},
        }
        storage.anchors[anchor_id] = anchor_data
    end)

    after_each(function()
        if anchor_data and anchor_data.spiders then
            local spider_ids = {}
            for spider_id, _ in pairs(anchor_data.spiders) do
                spider_ids[#spider_ids + 1] = spider_id
            end
            for _, spider_id in ipairs(spider_ids) do
                spider.recall(spider_id)
            end
        end

        if anchor_id and storage.anchors then
            storage.anchors[anchor_id] = nil
        end
        storage.global_enabled = original_global_enabled
        constants.idle_timeout_ticks = original_idle_timeout_ticks
        constants.no_work_recall_timeout_ticks = original_no_work_recall_timeout_ticks

        for _, e in ipairs(created) do
            if e and e.valid then
                e.destroy({ raise_destroyed = false })
            end
        end
    end)

    test(
        "builds ghosts from blueprint using spiderlings, then deconstructs and restores inventory (small fixture)",
        function()
            local fixture = nil
            for _, f in ipairs(blueprint_fixtures or {}) do
                if f and f.name == "brood_test_book" then
                    fixture = f
                    break
                end
            end

            assert.is_true(fixture ~= nil, "missing brood_test_book fixture")
            assert.is_true(type(fixture.data) == "string" and fixture.data ~= "", "brood_test_book fixture is empty")

            local inv, stack, imported, err = import_any_blueprint_item(fixture.data)
            assert.is_true(imported, "failed to import brood_test_book: " .. tostring(err or "unknown"))

            local blueprints = collect_blueprints(stack, 3)
            assert.is_true(blueprints and #blueprints > 0, "no blueprints found in brood_test_book")

            local anchor_inv = anchor_entity.get_inventory(defines.inventory.character_main)
            assert.is_true(anchor_inv and anchor_inv.valid)
            anchor_inv.clear()

            -- Deploy multiple spiders so the cycle stays fast.
            local spiders_to_deploy = math.min(constants.max_spiders_per_anchor or 1, 3)
            anchor_inv.insert({ name = "spiderling", count = spiders_to_deploy })

            local spider_ids = {}
            for _ = 1, spiders_to_deploy do
                local spider_id = spider.deploy(anchor_id)
                assert.is_not_nil(spider_id)
                spider_ids[#spider_ids + 1] = spider_id
            end

            -- Build far enough away that we can clear the build area without touching the anchor/spiders.
            local build_origin = { x = base_pos.x + 80, y = base_pos.y }

            local ticks_per_blueprint = 60 * 45
            async(ticks_per_blueprint * (#blueprints + 1))
            local phase = "start"
            local idx = 1
            local bounds = nil
            local required = nil
            local snap = nil
            local tile_targets = {}
            local expected_tile_after_deconstruct = "grass-1"

            local function start_blueprint(bp_info)
                clear_area(build_origin, 40)
                anchor_inv.clear()

                local bp = bp_info.stack
                local entities = get_entities(bp) or {}
                local tiles = get_tiles(bp) or {}
                assert.is_true(#entities > 0 or #tiles > 0, "blueprint has no entities or tiles")

                local created_ghosts, req, area, targets = place_ghosts_and_requirements(entities, tiles, build_origin)
                assert.is_true(created_ghosts and #created_ghosts > 0, "no ghosts created from blueprint")
                bounds = area
                required = req
                tile_targets = targets or {}

                for key, count in pairs(required) do
                    local name, quality = key:match("^(.-)\x1f(.*)$")
                    local stack_def = { name = name, count = count, quality = quality }
                    local inserted = anchor_inv.insert(stack_def)
                    assert.is_true(
                        inserted == count,
                        ("failed to insert %s quality=%s count=%d inserted=%d"):format(
                            name,
                            quality,
                            count,
                            inserted or 0
                        )
                    )
                end

                snap = snapshot_counts(anchor_inv, required)
                report(
                    ("[Brood][BlueprintCycle] started #%d path=%s required_items=%d"):format(
                        idx,
                        tostring(bp_info.path),
                        (function()
                            local c = 0
                            for _ in pairs(required) do
                                c = c + 1
                            end
                            return c
                        end)()
                    )
                )
            end

            start_blueprint(blueprints[idx])
            phase = "building"

            on_tick(function()
                if (game.tick % constants.main_loop_interval) == 0 then
                    remote.call("brood-engineering-test", "run_main_loop")
                end
                if (game.tick % 600) == 0 then
                    local entity_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "entity-ghost", force = force })
                    local tile_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "tile-ghost", force = force })
                    local status = {}
                    local ad = storage.anchors and storage.anchors[anchor_id] or nil
                    local ad_spider_count = ad
                            and ad.spiders
                            and (function()
                                local n = 0
                                for _ in pairs(ad.spiders) do
                                    n = n + 1
                                end
                                return n
                            end)()
                        or 0
                    for _, sid in ipairs(spider_ids) do
                        local sd = ad and ad.spiders and ad.spiders[sid] or nil
                        status[#status + 1] = ("%s=%s"):format(tostring(sid), sd and sd.status or "nil")
                    end
                    report(
                        ("[Brood][BlueprintCycle] phase=%s idx=%d anchor_valid=%s anchor_in_storage=%s spider_count=%d ghosts=%d tile_ghosts=%d spiders={%s}"):format(
                            tostring(phase),
                            idx,
                            tostring(anchor_entity and anchor_entity.valid),
                            tostring(ad ~= nil),
                            ad_spider_count,
                            #(entity_ghosts or {}),
                            #(tile_ghosts or {}),
                            table.concat(status, ",")
                        )
                    )
                end

                if phase == "building" then
                    if not any_build_ghosts(bounds) then
                        assert.is_true(
                            count_built_entities(bounds) > 0,
                            "no entities built (ghosts cleared unexpectedly)"
                        )
                        if tile_targets and #tile_targets > 0 then
                            assert.is_true(all_tiles_match_targets(tile_targets))
                        end
                        phase = "wait_idle_after_build"
                    end
                    return true
                end

                if phase == "wait_idle_after_build" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        order_deconstruct_everything(bounds)
                        order_deconstruct_tiles(tile_targets)
                        phase = "deconstructing"
                    end
                    return true
                end

                if phase == "deconstructing" then
                    if
                        (not any_deconstruct_targets(bounds))
                        and (not any_marked_tiles(bounds))
                        and (not any_tile_proxies(bounds))
                    then
                        phase = "wait_idle_after_deconstruct"
                    end
                    return true
                end

                if phase == "wait_idle_after_deconstruct" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        phase = "verify_inventory"
                    end
                    return true
                end

                if phase == "verify_inventory" then
                    assert_area_empty_except_anchor_and_spiders(bounds)
                    assert_counts_equal(anchor_inv, snap)
                    assert.is_true(all_tiles_are(tile_targets, expected_tile_after_deconstruct))

                    -- Reset for next blueprint in the book.
                    anchor_inv.clear()
                    idx = idx + 1
                    if idx > #blueprints then
                        inv.destroy()
                        done()
                        return false
                    end

                    start_blueprint(blueprints[idx])
                    phase = "building"
                    return true
                end

                return true
            end)
        end
    )

    test(
        "builds ghosts (including tile ghosts) from a blueprint using spiderlings, then deconstructs and restores inventory (tile+entity fixture)",
        function()
            local fixture = nil
            for _, f in ipairs(blueprint_fixtures or {}) do
                if f and f.name == "brood_test_tile_blueprint" then
                    fixture = f
                    break
                end
            end

            assert.is_true(fixture ~= nil, "missing brood_test_tile_blueprint fixture")
            assert.is_true(
                type(fixture.data) == "string" and fixture.data ~= "",
                "brood_test_tile_blueprint fixture is empty"
            )

            local inv, stack, imported, err = import_any_blueprint_item(fixture.data)
            assert.is_true(imported, "failed to import brood_test_tile_blueprint: " .. tostring(err or "unknown"))

            local blueprints = collect_blueprints(stack, 1)
            assert.is_true(blueprints and #blueprints > 0, "no blueprints found in brood_test_tile_blueprint")

            local anchor_inv = anchor_entity.get_inventory(defines.inventory.character_main)
            assert.is_true(anchor_inv and anchor_inv.valid)
            anchor_inv.clear()

            local spiders_to_deploy = 1
            anchor_inv.insert({ name = "spiderling", count = spiders_to_deploy })

            local spider_ids = {}
            for _ = 1, spiders_to_deploy do
                local spider_id = spider.deploy(anchor_id)
                assert.is_not_nil(spider_id)
                spider_ids[#spider_ids + 1] = spider_id
            end

            -- Build far enough away that we can clear the build area without touching the anchor/spiders.
            local build_origin = { x = base_pos.x + 80, y = base_pos.y }

            async(60 * 60)
            local phase = "building"
            local bounds = nil
            local snap = nil
            local tile_targets = {}
            local expected_tile_after_deconstruct = "grass-1"

            do
                clear_area(build_origin, 20)
                anchor_inv.clear()

                local bp = blueprints[1].stack
                local entities = get_entities(bp) or {}
                local tiles = get_tiles(bp) or {}
                local _, required, area, targets = place_ghosts_and_requirements(entities, tiles, build_origin)
                bounds = area
                tile_targets = targets or {}

                for key, count in pairs(required or {}) do
                    local name, quality = key:match("^(.-)\x1f(.*)$")
                    local stack_def = { name = name, count = count, quality = quality }
                    local inserted = anchor_inv.insert(stack_def)
                    assert.is_true(inserted == count)
                end

                snap = snapshot_counts(anchor_inv, required or {})
            end

            on_tick(function()
                if (game.tick % constants.main_loop_interval) == 0 then
                    remote.call("brood-engineering-test", "run_main_loop")
                end
                if (game.tick % 600) == 0 then
                    local entity_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "entity-ghost", force = force })
                    local tile_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "tile-ghost", force = force })
                    local status = {}
                    local ad = storage.anchors and storage.anchors[anchor_id] or nil
                    local ad_spider_count = ad
                            and ad.spiders
                            and (function()
                                local n = 0
                                for _ in pairs(ad.spiders) do
                                    n = n + 1
                                end
                                return n
                            end)()
                        or 0
                    for _, sid in ipairs(spider_ids) do
                        local sd = ad and ad.spiders and ad.spiders[sid] or nil
                        status[#status + 1] = ("%s=%s"):format(tostring(sid), sd and sd.status or "nil")
                    end
                    report(
                        ("[Brood][BlueprintCycle] phase=%s anchor_valid=%s anchor_in_storage=%s spider_count=%d ghosts=%d tile_ghosts=%d spiders={%s}"):format(
                            tostring(phase),
                            tostring(anchor_entity and anchor_entity.valid),
                            tostring(ad ~= nil),
                            ad_spider_count,
                            #(entity_ghosts or {}),
                            #(tile_ghosts or {}),
                            table.concat(status, ",")
                        )
                    )
                end

                if phase == "building" then
                    if not any_build_ghosts(bounds) then
                        assert.is_true(all_tiles_match_targets(tile_targets))
                        phase = "wait_idle_after_build"
                    end
                    return true
                end

                if phase == "wait_idle_after_build" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        order_deconstruct_everything(bounds)
                        order_deconstruct_tiles(tile_targets)
                        phase = "deconstructing"
                    end
                    return true
                end

                if phase == "deconstructing" then
                    if
                        (not any_deconstruct_targets(bounds))
                        and (not any_marked_tiles(bounds))
                        and (not any_tile_proxies(bounds))
                    then
                        phase = "wait_idle_after_deconstruct"
                    end
                    return true
                end

                if phase == "wait_idle_after_deconstruct" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        phase = "verify"
                    end
                    return true
                end

                if phase == "verify" then
                    assert.is_true(all_tiles_are(tile_targets, expected_tile_after_deconstruct))
                    assert_area_empty_except_anchor_and_spiders(bounds)
                    assert_counts_equal(anchor_inv, snap or {})
                    inv.destroy()
                    done()
                    return false
                end

                return true
            end)
        end
    )

    test(
        "handles missing items by leaving ghosts, then completes after items are added (tile+entity fixture)",
        function()
            local fixture = nil
            for _, f in ipairs(blueprint_fixtures or {}) do
                if f and f.name == "brood_test_tile_blueprint" then
                    fixture = f
                    break
                end
            end

            assert.is_true(fixture ~= nil, "missing brood_test_tile_blueprint fixture")
            assert.is_true(
                type(fixture.data) == "string" and fixture.data ~= "",
                "brood_test_tile_blueprint fixture is empty"
            )

            local inv, stack, imported, err = import_any_blueprint_item(fixture.data)
            assert.is_true(imported, "failed to import brood_test_tile_blueprint: " .. tostring(err or "unknown"))

            local blueprints = collect_blueprints(stack, 1)
            assert.is_true(blueprints and #blueprints > 0, "no blueprints found in brood_test_tile_blueprint")

            local anchor_inv = anchor_entity.get_inventory(defines.inventory.character_main)
            assert.is_true(anchor_inv and anchor_inv.valid)
            anchor_inv.clear()

            local spiders_to_deploy = 1
            anchor_inv.insert({ name = "spiderling", count = spiders_to_deploy })

            local spider_ids = {}
            for _ = 1, spiders_to_deploy do
                local spider_id = spider.deploy(anchor_id)
                assert.is_not_nil(spider_id)
                spider_ids[#spider_ids + 1] = spider_id
            end

            local build_origin = { x = base_pos.x + 80, y = base_pos.y }

            async(60 * 60)
            local phase = "building_missing_items"
            local bounds = nil
            local required = nil
            local snap = nil
            local tile_targets = {}
            local expected_tile_after_deconstruct = "grass-1"
            local missing_key = nil
            local missing_count = 0
            local missing_min_tick = game.tick + (constants.main_loop_interval * 4)
            local missing_deadline = game.tick + (60 * 20)

            do
                clear_area(build_origin, 20)
                anchor_inv.clear()

                local bp = blueprints[1].stack
                local entities = get_entities(bp) or {}
                local tiles = get_tiles(bp) or {}
                local _, req, area, targets = place_ghosts_and_requirements(entities, tiles, build_origin)
                bounds = area
                required = req or {}
                tile_targets = targets or {}

                snap = {}
                local required_key_count = 0
                for key, count in pairs(required) do
                    snap[key] = count
                    required_key_count = required_key_count + 1
                end
                assert.is_true(required_key_count >= 2, "fixture must require at least 2 distinct items for this test")

                for key, _ in pairs(required) do
                    local name = key:match("^(.-)\x1f")
                    if name == "stone-furnace" then
                        missing_key = key
                        break
                    end
                end
                if not missing_key then
                    for key, _ in pairs(required) do
                        missing_key = key
                        break
                    end
                end
                missing_count = required[missing_key] or 0
                assert.is_true(missing_key ~= nil and missing_count > 0, "failed to select a missing required item")

                for key, count in pairs(required) do
                    if key ~= missing_key then
                        local name, quality = key:match("^(.-)\x1f(.*)$")
                        local stack_def = { name = name, count = count, quality = quality }
                        local inserted = anchor_inv.insert(stack_def)
                        assert.is_true(
                            inserted == count,
                            ("failed to insert %s quality=%s count=%d inserted=%d"):format(
                                name,
                                quality,
                                count,
                                inserted or 0
                            )
                        )
                    end
                end
            end

            on_tick(function()
                if (game.tick % constants.main_loop_interval) == 0 then
                    remote.call("brood-engineering-test", "run_main_loop")
                end
                if (game.tick % 600) == 0 then
                    local entity_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "entity-ghost", force = force })
                    local tile_ghosts =
                        surface.find_entities_filtered({ area = bounds, type = "tile-ghost", force = force })
                    local status = {}
                    local ad = storage.anchors and storage.anchors[anchor_id] or nil
                    local ad_spider_count = ad
                            and ad.spiders
                            and (function()
                                local n = 0
                                for _ in pairs(ad.spiders) do
                                    n = n + 1
                                end
                                return n
                            end)()
                        or 0
                    for _, sid in ipairs(spider_ids) do
                        local sd = ad and ad.spiders and ad.spiders[sid] or nil
                        status[#status + 1] = ("%s=%s"):format(tostring(sid), sd and sd.status or "nil")
                    end
                    report(
                        ("[Brood][BlueprintCycle] phase=%s anchor_valid=%s anchor_in_storage=%s spider_count=%d ghosts=%d tile_ghosts=%d spiders={%s}"):format(
                            tostring(phase),
                            tostring(anchor_entity and anchor_entity.valid),
                            tostring(ad ~= nil),
                            ad_spider_count,
                            #(entity_ghosts or {}),
                            #(tile_ghosts or {}),
                            table.concat(status, ",")
                        )
                    )
                end

                if phase == "building_missing_items" then
                    if game.tick > missing_deadline then
                        assert.is_true(false, "timed out waiting for ghosts to remain with missing items")
                    end
                    if game.tick >= missing_min_tick then
                        assert.is_true(
                            any_build_ghosts(bounds),
                            "expected ghosts to remain when required items are missing"
                        )

                        local name, quality = missing_key:match("^(.-)\x1f(.*)$")
                        assert.is_true(anchor_inv.get_item_count({ name = name, quality = quality }) == 0)

                        local inserted = anchor_inv.insert({ name = name, count = missing_count, quality = quality })
                        assert.is_true(
                            inserted == missing_count,
                            ("failed to insert missing %s quality=%s count=%d inserted=%d"):format(
                                name,
                                quality,
                                missing_count,
                                inserted or 0
                            )
                        )

                        report(
                            ("[Brood][BlueprintCycle] inserted missing item %s quality=%s count=%d"):format(
                                tostring(name),
                                tostring(quality),
                                missing_count
                            )
                        )
                        phase = "building"
                    end
                    return true
                end

                if phase == "building" then
                    if not any_build_ghosts(bounds) then
                        assert.is_true(
                            count_built_entities(bounds) > 0,
                            "no entities built after missing items were added"
                        )
                        if tile_targets and #tile_targets > 0 then
                            assert.is_true(all_tiles_match_targets(tile_targets))
                        end
                        phase = "wait_idle_after_build"
                    end
                    return true
                end

                if phase == "wait_idle_after_build" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        order_deconstruct_everything(bounds)
                        order_deconstruct_tiles(tile_targets)
                        phase = "deconstructing"
                    end
                    return true
                end

                if phase == "deconstructing" then
                    if
                        (not any_deconstruct_targets(bounds))
                        and (not any_marked_tiles(bounds))
                        and (not any_tile_proxies(bounds))
                    then
                        phase = "wait_idle_after_deconstruct"
                    end
                    return true
                end

                if phase == "wait_idle_after_deconstruct" then
                    if all_spiders_idle_near_anchor(spider_ids) then
                        phase = "verify"
                    end
                    return true
                end

                if phase == "verify" then
                    assert.is_true(all_tiles_are(tile_targets, expected_tile_after_deconstruct))
                    assert_area_empty_except_anchor_and_spiders(bounds)
                    assert_counts_equal(anchor_inv, snap or {})
                    inv.destroy()
                    done()
                    return false
                end

                return true
            end)
        end
    )
end)
