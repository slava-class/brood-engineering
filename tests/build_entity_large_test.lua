local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

describe("build large entity ghosts", function()
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

    local function clear_build_area(position, radius)
        test_utils.clear_area(surface, position, radius, { anchor_entity = anchor_entity, skip_spiders = true })
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 7000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = test_utils.disable_global_enabled()
        test_utils.reset_storage()

        anchor_id, anchor_entity, anchor_data = test_utils.create_test_anchor({
            surface = surface,
            force = force,
            position = base_pos,
            name = "wooden-chest",
            inventory_id = defines.inventory.chest,
            seed = { { name = "spiderling", count = 10 } },
            anchor_id_prefix = "test_anchor_build_large",
            track = track,
        })
    end)

    after_each(function()
        test_utils.teardown_anchor(anchor_id, anchor_data)
        test_utils.restore_global_enabled(original_global_enabled)
        test_utils.destroy_tracked(created)
    end)

    test("builds a stone furnace ghost (2x2)", function()
        local ghost_pos = { x = base_pos.x + 10, y = base_pos.y }

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 8)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = ghost_pos,
            direction = defines.direction.north,
            force = force,
            expires = false,
        }))

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 30,
            description = "stone furnace built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local furnace = surface.find_entity("stone-furnace", ghost_pos)
                if furnace and furnace.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "stone-furnace", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds an assembling machine ghost (3x3)", function()
        local ghost_pos = { x = base_pos.x + 14, y = base_pos.y }

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "assembling-machine-2", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 10)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "assembling-machine-2",
            position = ghost_pos,
            direction = defines.direction.north,
            force = force,
            expires = false,
        }))

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 30,
            description = "assembling machine built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local machine = surface.find_entity("assembling-machine-2", ghost_pos)
                if machine and machine.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "assembling-machine-2", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds an oil refinery ghost (5x5)", function()
        local ghost_pos = { x = base_pos.x + 18, y = base_pos.y }

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "oil-refinery", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 12)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "oil-refinery",
            position = ghost_pos,
            direction = defines.direction.north,
            force = force,
            expires = false,
        }))

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 40,
            description = "oil refinery built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local refinery = surface.find_entity("oil-refinery", ghost_pos)
                if refinery and refinery.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "oil-refinery", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)

    test("builds a rocket silo ghost (9x9)", function()
        local ghost_pos = { x = base_pos.x + 32, y = base_pos.y }

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "rocket-silo", count = 1, quality = "normal" })

        clear_build_area(ghost_pos, 15)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "rocket-silo",
            position = ghost_pos,
            direction = defines.direction.north,
            force = force,
            expires = false,
        }))

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 40,
            description = "rocket silo built",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local silo = surface.find_entity("rocket-silo", ghost_pos)
                if silo and silo.valid then
                    assert.are_equal(0, inventory.get_item_count({ name = "rocket-silo", quality = "normal" }))
                    return true
                end
                return false
            end,
        })
    end)
end)
