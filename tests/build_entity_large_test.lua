local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("build large entity ghosts", function()
    return {
        base_pos = test_utils.random_base_pos(7000),
        clean_radius = 60,
        clear_radius = 20,
        anchor_name = "wooden-chest",
        anchor_inventory_id = defines.inventory.chest,
        anchor_seed = { { name = "spiderling", count = 10 } },
        anchor_id_prefix = "test_anchor_build_large",
    }
end, function(ctx)
    local function clear_build_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, { anchor_entity = ctx.anchor_entity, skip_spiders = true })
    end

    test("builds a stone furnace ghost (2x2)", function()
        local ghost_pos = ctx.pos({ x = 10, y = 0 })

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 8)

        ctx.spawn_ghost({
            inner_name = "stone-furnace",
            position = ghost_pos,
            direction = defines.direction.north,
        })

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 30,
            description = "stone furnace built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local furnace = ctx.surface.find_entity("stone-furnace", ghost_pos)
                if furnace and furnace.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "stone-furnace", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds an assembling machine ghost (3x3)", function()
        local ghost_pos = ctx.pos({ x = 14, y = 0 })

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "assembling-machine-2", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 10)

        ctx.spawn_ghost({
            inner_name = "assembling-machine-2",
            position = ghost_pos,
            direction = defines.direction.north,
        })

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 30,
            description = "assembling machine built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local machine = ctx.surface.find_entity("assembling-machine-2", ghost_pos)
                if machine and machine.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "assembling-machine-2", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds an oil refinery ghost (5x5)", function()
        local ghost_pos = ctx.pos({ x = 18, y = 0 })

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "oil-refinery", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 12)

        ctx.spawn_ghost({
            inner_name = "oil-refinery",
            position = ghost_pos,
            direction = defines.direction.north,
        })

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 40,
            description = "oil refinery built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local refinery = ctx.surface.find_entity("oil-refinery", ghost_pos)
                if refinery and refinery.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "oil-refinery", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds a rocket silo ghost (9x9)", function()
        local ghost_pos = ctx.pos({ x = 32, y = 0 })

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "rocket-silo", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 15)

        ctx.spawn_ghost({
            inner_name = "rocket-silo",
            position = ghost_pos,
            direction = defines.direction.north,
        })

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 40,
            description = "rocket silo built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local silo = ctx.surface.find_entity("rocket-silo", ghost_pos)
                if silo and silo.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "rocket-silo", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)
end)
