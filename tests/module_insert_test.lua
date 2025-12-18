local spider = require("scripts/spider")
local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

describe("module insertion", function()
    local ctx

    local function clear_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })
    end

    before_each(function()
        ctx = test_utils.setup_anchor_test({
            base_pos = { x = 8000 + math.random(0, 50), y = math.random(-20, 20) },
            clean_radius = 60,
            clear_radius = 20,
            anchor_name = "wooden-chest",
            anchor_inventory_id = defines.inventory.chest,
            anchor_seed = { { name = "spiderling", count = 10 } },
            anchor_id_prefix = "test_anchor_modules",
        })
    end)

    after_each(function()
        test_utils.teardown_anchor_test(ctx)
    end)

    test("inserts modules into an assembling machine (3x3)", function()
        local target_pos = { x = ctx.base_pos.x + 18, y = ctx.base_pos.y }
        clear_area(target_pos, 12)

        local machine = ctx.track(ctx.surface.create_entity({
            name = "assembling-machine-2",
            position = target_pos,
            direction = defines.direction.north,
            force = ctx.force,
        }))
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        local requested = 2
        local supplied = 50
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = ctx.track(ctx.surface.create_entity({
            name = "item-request-proxy",
            position = machine.position,
            force = ctx.force,
            target = machine,
            modules = {
                {
                    id = { name = "speed-module", quality = "normal" },
                    items = {
                        in_inventory = {
                            { inventory = defines.inventory.assembling_machine_modules, stack = 0, count = 1 },
                            { inventory = defines.inventory.assembling_machine_modules, stack = 1, count = 1 },
                        },
                    },
                },
            },
        }))
        assert.is_true(proxy and proxy.valid)

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 25,
            description = "assembling machine module insert",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local count = module_inventory.get_item_count({ name = "speed-module", quality = "normal" })
                assert.is_true(count <= requested)
                if count == requested then
                    assert.are_equal(
                        supplied - requested,
                        inventory.get_item_count({ name = "speed-module", quality = "normal" })
                    )
                    assert.is_true(not proxy.valid or (not proxy.item_requests or next(proxy.item_requests) == nil))
                    assert.is_true(not proxy.valid or not (proxy.insert_plan and proxy.insert_plan[1]))
                    assert.is_true(not proxy.valid or not (proxy.removal_plan and proxy.removal_plan[1]))

                    return true
                end

                return false
            end,
        })
    end)

    test("inserts modules into an oil refinery (5x5)", function()
        local target_pos = { x = ctx.base_pos.x + 34, y = ctx.base_pos.y }
        clear_area(target_pos, 15)

        local refinery = ctx.track(ctx.surface.create_entity({
            name = "oil-refinery",
            position = target_pos,
            direction = defines.direction.north,
            force = ctx.force,
        }))
        assert.is_true(refinery and refinery.valid)

        local module_inventory = refinery.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        local requested = 3
        local supplied = 60
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = ctx.track(ctx.surface.create_entity({
            name = "item-request-proxy",
            position = refinery.position,
            force = ctx.force,
            target = refinery,
            modules = {
                {
                    id = { name = "speed-module", quality = "normal" },
                    items = {
                        in_inventory = {
                            { inventory = defines.inventory.assembling_machine_modules, stack = 0, count = 1 },
                            { inventory = defines.inventory.assembling_machine_modules, stack = 1, count = 1 },
                            { inventory = defines.inventory.assembling_machine_modules, stack = 2, count = 1 },
                        },
                    },
                },
            },
        }))
        assert.is_true(proxy and proxy.valid)

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 25,
            description = "oil refinery module insert",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local count = module_inventory.get_item_count({ name = "speed-module", quality = "normal" })
                assert.is_true(count <= requested)
                if count == requested then
                    assert.are_equal(
                        supplied - requested,
                        inventory.get_item_count({ name = "speed-module", quality = "normal" })
                    )
                    assert.is_true(not proxy.valid or (not proxy.item_requests or next(proxy.item_requests) == nil))
                    assert.is_true(not proxy.valid or not (proxy.insert_plan and proxy.insert_plan[1]))
                    assert.is_true(not proxy.valid or not (proxy.removal_plan and proxy.removal_plan[1]))

                    return true
                end

                return false
            end,
        })
    end)

    test("swaps a wrong module using removal_plan then clears proxy", function()
        local target_pos = { x = ctx.base_pos.x + 52, y = ctx.base_pos.y }
        clear_area(target_pos, 12)

        local machine = ctx.track(ctx.surface.create_entity({
            name = "assembling-machine-2",
            position = target_pos,
            direction = defines.direction.north,
            force = ctx.force,
        }))
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        assert.is_true(module_inventory[1].set_stack({ name = "productivity-module", count = 1, quality = "normal" }))

        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        inventory.insert({ name = "speed-module", count = 10, quality = "normal" })

        local proxy = ctx.track(ctx.surface.create_entity({
            name = "item-request-proxy",
            position = machine.position,
            force = ctx.force,
            target = machine,
            modules = {
                {
                    id = { name = "speed-module", quality = "normal" },
                    items = {
                        in_inventory = {
                            { inventory = defines.inventory.assembling_machine_modules, stack = 0, count = 1 },
                        },
                    },
                },
            },
            removal_plan = {
                {
                    id = { name = "productivity-module", quality = "normal" },
                    items = {
                        in_inventory = {
                            { inventory = defines.inventory.assembling_machine_modules, stack = 0, count = 1 },
                        },
                    },
                },
            },
        }))
        assert.is_true(proxy and proxy.valid)

        test_utils.run_main_loop()

        test_utils.wait_until({
            timeout_ticks = 60 * 25,
            description = "module swap via removal plan",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                local speed = module_inventory.get_item_count({ name = "speed-module", quality = "normal" })
                local prod = module_inventory.get_item_count({ name = "productivity-module", quality = "normal" })
                assert.is_true(speed <= 1)
                assert.is_true(prod <= 1)

                if speed == 1 and prod == 0 then
                    assert.are_equal(9, inventory.get_item_count({ name = "speed-module", quality = "normal" }))
                    assert.are_equal(1, inventory.get_item_count({ name = "productivity-module", quality = "normal" }))
                    assert.is_true(not proxy.valid or (not proxy.item_requests or next(proxy.item_requests) == nil))
                    assert.is_true(not proxy.valid or not (proxy.insert_plan and proxy.insert_plan[1]))
                    assert.is_true(not proxy.valid or not (proxy.removal_plan and proxy.removal_plan[1]))

                    return true
                end

                return false
            end,
        })
    end)
end)
