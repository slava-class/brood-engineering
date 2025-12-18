local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local tasks = require("scripts/tasks")
local constants = require("scripts/constants")
local deconstruct_entity = require("scripts/behaviors/deconstruct_entity")
local test_utils = require("tests/test_utils")

describe("tile deconstruction", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local original_global_enabled

    local function track(entity)
        return test_utils.track(created, entity)
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 6000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = test_utils.disable_global_enabled()
        test_utils.reset_storage()

        -- Use a character anchor so `mine_tile` is available (matches in-game behavior).
        anchor_id, anchor_entity, anchor_data = test_utils.create_test_anchor({
            surface = surface,
            force = force,
            position = base_pos,
            name = "character",
            inventory_id = defines.inventory.character_main,
            seed = { { name = "spiderling", count = 1 } },
            anchor_id_prefix = "test_anchor_tile",
            track = track,
        })
    end)

    after_each(function()
        test_utils.teardown_anchor(anchor_id, anchor_data)
        test_utils.restore_global_enabled(original_global_enabled)
        test_utils.destroy_tracked(created)
    end)

    test("removes deconstruct-marked stone-path tile", function()
        local tile_pos = { x = base_pos.x + 2, y = base_pos.y }
        surface.set_tiles({ { name = "grass-1", position = tile_pos } }, true)
        surface.set_tiles({ { name = "stone-path", position = tile_pos } }, true)

        local tile = surface.get_tile(tile_pos)
        tile.order_deconstruction(force)
        do
            local ok, marked = pcall(function()
                return tile.to_be_deconstructed()
            end)
            if ok then
                assert.is_true(marked)
            end
        end

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        test_utils.wait_until({
            timeout_ticks = 60 * 20,
            description = "single tile deconstruct",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local current_tile = surface.get_tile(tile_pos)
                if current_tile and current_tile.valid and current_tile.name ~= "stone-path" then
                    local inventory = test_utils.anchor_inventory(anchor_entity, defines.inventory.character_main)
                    if inventory.get_item_count("stone-brick") >= 1 then
                        assert.are_equal("grass-1", current_tile.name)
                        return true
                    end
                end

                return false
            end,
        })
    end)

    test("auto-deploy mines multiple deconstruct-marked tiles without double-counting proxies", function()
        local tile_positions = {
            { x = base_pos.x + 2, y = base_pos.y },
            { x = base_pos.x + 3, y = base_pos.y },
            { x = base_pos.x + 2, y = base_pos.y + 1 },
            { x = base_pos.x + 3, y = base_pos.y + 1 },
        }

        for _, tile_pos in ipairs(tile_positions) do
            surface.set_tiles({ { name = "grass-1", position = tile_pos } }, true)
            surface.set_tiles({ { name = "stone-path", position = tile_pos } }, true)

            local tile = surface.get_tile(tile_pos)
            tile.order_deconstruction(force)
        end

        -- Gotcha: tile deconstruction orders create `deconstructible-tile-proxy` entities marked
        -- `to_be_deconstructed`. Ensure the entity behavior ignores them so we don't double-count
        -- work (and deploy extra spiders).
        local proxy_entities = surface.find_entities_filtered({
            area = { { base_pos.x - 10, base_pos.y - 10 }, { base_pos.x + 10, base_pos.y + 10 } },
            type = "deconstructible-tile-proxy",
        })
        assert.is_true(proxy_entities and #proxy_entities > 0)
        local entity_tasks = deconstruct_entity.find_tasks(
            surface,
            { { base_pos.x - 10, base_pos.y - 10 }, { base_pos.x + 10, base_pos.y + 10 } },
            { force.name, "neutral" }
        )
        for _, e in ipairs(entity_tasks) do
            assert.is_true(e.type ~= "deconstructible-tile-proxy")
        end

        local inventory = test_utils.anchor_inventory(anchor_entity, defines.inventory.character_main)
        inventory.insert({ name = "spiderling", count = 50 })

        local anchor_area = anchor.get_expanded_work_area(anchor_data)
        local force_filter = anchor.get_force(anchor_data)
        local available = tasks.find_all(surface, anchor_area, force_filter, inventory)

        assert.are_equal(#tile_positions, #available)
        for _, task in ipairs(available) do
            assert.are_equal("deconstruct_tile", task.behavior_name)
        end

        test_utils.run_main_loop()

        local deployed = 0
        for _ in pairs(anchor_data.spiders) do
            deployed = deployed + 1
        end
        assert.are_equal(#tile_positions, deployed)

        test_utils.wait_until({
            timeout_ticks = 60 * 20,
            description = "multi tile deconstruct",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                for _, tile_pos in ipairs(tile_positions) do
                    local current_tile = surface.get_tile(tile_pos)
                    if current_tile and current_tile.valid and current_tile.name == "stone-path" then
                        return false
                    end
                end

                local final_inventory = test_utils.anchor_inventory(anchor_entity, defines.inventory.character_main)
                if final_inventory.get_item_count("stone-brick") < #tile_positions then
                    return false
                end

                for _, tile_pos in ipairs(tile_positions) do
                    assert.are_equal("grass-1", surface.get_tile(tile_pos).name)
                end
                return true
            end,
        })
    end)
end)
