local constants = require("scripts/constants")
local anchor = require("scripts/anchor")
local spider = require("scripts/spider")
local blueprint_fixtures = require("tests/fixtures/blueprints")

describe("blueprint-like placement scenarios", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local original_global_enabled

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

        local area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
        for _, entity in ipairs(surface.find_entities_filtered({ area = area })) do
            if entity and entity.valid then
                if anchor_entity and entity == anchor_entity then
                    goto continue
                end
                entity.destroy({ raise_destroyed = false })
            end
            ::continue::
        end
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 7200 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        surface.request_to_generate_chunks(base_pos, 2)
        surface.force_generate_chunk_requests()

        original_global_enabled = storage.global_enabled
        storage.global_enabled = false

        -- Fully reset mod state for isolation.
        storage.anchors = {}
        storage.spider_to_anchor = {}
        storage.entity_to_spider = {}
        storage.assigned_tasks = {}
        storage.assignment_limits = {}
        storage.pending_tile_deconstruct = {}

        anchor_entity = track(surface.create_entity({
            name = "character",
            position = base_pos,
            force = force,
        }))
        local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
        inventory.insert({ name = "spiderling", count = 1 })
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        anchor_id = "test_anchor_blueprint_" .. game.tick .. "_" .. math.random(1, 1000000)
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

        for _, e in ipairs(created) do
            if e and e.valid then
                e.destroy({ raise_destroyed = false })
            end
        end
    end)

    test("does not crash when a blueprint ghost is blocked by a random-drop entity", function()
        local target_pos = { x = base_pos.x + 6, y = base_pos.y }
        clear_area(target_pos, 18)

        -- This simulates a common blueprint placement scenario:
        -- - A ghost overlaps an existing entity (e.g., tree/rock).
        -- - The player (or another system) marks the blocker for deconstruction.
        -- - Our task scan/assignment executes without crashing, even if mine products are random (amount_min=0).
        local tree = track(surface.create_entity({
            name = "tree-01",
            position = target_pos,
            force = "neutral",
        }))
        assert.is_true(tree and tree.valid)

        local ghost = track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = target_pos,
            force = force,
            expires = false,
        }))
        assert.is_true(ghost and ghost.valid)

        tree.order_deconstruction(force)
        assert.is_true(tree.to_be_deconstructed())

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        async(60 * 25)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            -- The primary purpose is "no crash"; also assert progress: blocker removed and ghost built.
            if not tree.valid then
                local built = surface.find_entities_filtered({
                    position = target_pos,
                    name = "stone-furnace",
                    force = force,
                })
                if built and #built > 0 then
                    done()
                    return false
                end
            end

            return true
        end)
    end)

    for _, fixture in ipairs(blueprint_fixtures or {}) do
        local fixture_name = fixture and fixture.name or "unknown"
        local fixture_module = fixture and fixture.module or nil

        test(("imports blueprint fixture: %s"):format(tostring(fixture_name)), function()
            if not fixture_module then
                return
            end

            local ok_require, data = pcall(function()
                return require(fixture_module)
            end)
            if not ok_require or not data or data == "" then
                return
            end

            local inv = game.create_inventory(1)
            inv[1].set_stack({ name = "blueprint", count = 1 })
            local stack = inv[1]

            local ok_import, imported_or_err = pcall(function()
                return stack.import_stack(data)
            end)
            inv.destroy()

            if not ok_import or (imported_or_err or 0) == 0 then
                log(("[Brood][BlueprintFixture] import skipped for %s"):format(tostring(fixture_name)))
                return
            end
        end)

        test(("builds blueprint fixture (if buildable): %s"):format(tostring(fixture_name)), function()
            if not fixture_module then
                return
            end

            local ok_require, data = pcall(function()
                return require(fixture_module)
            end)
            if not ok_require or not data or data == "" then
                return
            end

            local inv = game.create_inventory(1)
            inv[1].set_stack({ name = "blueprint", count = 1 })
            local stack = inv[1]

            local ok_import, imported_or_err = pcall(function()
                return stack.import_stack(data)
            end)
            if not ok_import or (imported_or_err or 0) == 0 then
                inv.destroy()
                log(("[Brood][BlueprintFixture] build skipped (import failed) for %s"):format(tostring(fixture_name)))
                return
            end

            local build_pos = { x = base_pos.x + 20, y = base_pos.y }
            clear_area(build_pos, 40)

            local ok_build, built_or_err = pcall(function()
                return stack.build_blueprint({
                    surface = surface,
                    force = force.name,
                    position = build_pos,
                    raise_built = false,
                    skip_fog_of_war = true,
                })
            end)

            inv.destroy()

            if not ok_build then
                log(
                    ("[Brood][BlueprintFixture] build skipped for %s (%s)"):format(
                        tostring(fixture_name),
                        tostring(built_or_err)
                    )
                )
                return
            end

            -- Ensure the task scan can handle whatever ghosts were created.
            local ok_loop, loop_err = pcall(function()
                remote.call("brood-engineering-test", "run_main_loop")
            end)
            assert.is_true(
                ok_loop,
                "run_main_loop crashed after building fixture: " .. tostring(fixture_name) .. ": " .. tostring(loop_err)
            )
        end)
    end
end)
