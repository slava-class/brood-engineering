local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local tasks = require("scripts/tasks")
local constants = require("scripts/constants")
local deconstruct_entity = require("scripts/behaviors/deconstruct_entity")
local fapi = require("scripts/fapi")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("tile deconstruction", function()
    return test_utils.anchor_opts.character({
        x_base = 6000,
        radii = "small",
        spiderlings = 1,
    })
end, function(ctx)
    test("removes deconstruct-marked stone-path tile", function()
        local tile_pos = ctx.pos({ x = 2, y = 0 })
        fapi.set_tiles(ctx.surface, { { name = "grass-1", position = tile_pos } }, true)
        fapi.set_tiles(ctx.surface, { { name = "stone-path", position = tile_pos } }, true)

        local tile = ctx.surface.get_tile(tile_pos)
        tile.order_deconstruction(ctx.force)
        do
            local ok, marked = pcall(function()
                return tile.to_be_deconstructed()
            end)
            if ok then
                assert.is_true(marked)
            end
        end

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)

        test_utils.wait_until({
            timeout_ticks = 60 * 20,
            description = "single tile deconstruct",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local current_tile = ctx.surface.get_tile(tile_pos)
                if current_tile and current_tile.valid and current_tile.name ~= "stone-path" then
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
            ctx.pos({ x = 2, y = 0 }),
            ctx.pos({ x = 3, y = 0 }),
            ctx.pos({ x = 2, y = 1 }),
            ctx.pos({ x = 3, y = 1 }),
        }

        for _, tile_pos in ipairs(tile_positions) do
            fapi.set_tiles(ctx.surface, { { name = "grass-1", position = tile_pos } }, true)
            fapi.set_tiles(ctx.surface, { { name = "stone-path", position = tile_pos } }, true)

            local tile = ctx.surface.get_tile(tile_pos)
            tile.order_deconstruction(ctx.force)
        end

        -- Gotcha: tile deconstruction orders create `deconstructible-tile-proxy` entities marked
        -- `to_be_deconstructed`. Ensure the entity behavior ignores them so we don't double-count
        -- work (and deploy extra spiders).
        local proxy_entities = ctx.surface.find_entities_filtered({
            area = { { ctx.base_pos.x - 10, ctx.base_pos.y - 10 }, { ctx.base_pos.x + 10, ctx.base_pos.y + 10 } },
            type = "deconstructible-tile-proxy",
        })
        assert.is_true(proxy_entities and #proxy_entities > 0)
        local entity_tasks = deconstruct_entity.find_tasks(
            ctx.surface,
            { { ctx.base_pos.x - 10, ctx.base_pos.y - 10 }, { ctx.base_pos.x + 10, ctx.base_pos.y + 10 } },
            { ctx.force.name, "neutral" }
        )
        for _, e in ipairs(entity_tasks) do
            assert.is_true(e.type ~= "deconstructible-tile-proxy")
        end

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "spiderling", count = 50 })

        local anchor_area = anchor.get_expanded_work_area(ctx.anchor_data)
        local force_filter = anchor.get_force(ctx.anchor_data)
        local available = tasks.find_all(ctx.surface, anchor_area, force_filter, inventory)

        assert.are_equal(#tile_positions, #available)
        for _, task in ipairs(available) do
            assert.are_equal("deconstruct_tile", task.behavior_name)
        end

        test_utils.run_main_loop()

        local deployed = 0
        for _ in pairs(ctx.anchor_data.spiders) do
            deployed = deployed + 1
        end
        assert.are_equal(#tile_positions, deployed)

        test_utils.wait_until({
            timeout_ticks = 60 * 20,
            description = "multi tile deconstruct",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                for _, tile_pos in ipairs(tile_positions) do
                    local current_tile = ctx.surface.get_tile(tile_pos)
                    if current_tile and current_tile.valid and current_tile.name == "stone-path" then
                        return false
                    end
                end

                if inventory.get_item_count("stone-brick") < #tile_positions then
                    return false
                end

                for _, tile_pos in ipairs(tile_positions) do
                    assert.are_equal("grass-1", ctx.surface.get_tile(tile_pos).name)
                end
                return true
            end,
        })
    end)
end)
