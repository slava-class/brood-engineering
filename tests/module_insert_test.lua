local spider = require("scripts/spider")
local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("module insertion", function()
    return test_utils.anchor_opts.chest({
        x_base = 8000,
        radii = "medium",
        spiderlings = 10,
    })
end, function(ctx)
    local function clear_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })
    end

    test("inserts modules into an assembling machine (3x3)", function()
        local target_offset = { x = 18, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 12)

        local machine = ctx.spawn({
            name = "assembling-machine-2",
            offset = target_offset,
            direction = defines.direction.north,
        })
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        local requested = 2
        local supplied = 50
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = ctx.spawn_item_request_proxy({
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
        })
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
        local target_offset = { x = 34, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 15)

        local refinery = ctx.spawn({
            name = "oil-refinery",
            offset = target_offset,
            direction = defines.direction.north,
        })
        assert.is_true(refinery and refinery.valid)

        local module_inventory = refinery.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        local requested = 3
        local supplied = 60
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = ctx.spawn_item_request_proxy({
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
        })
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
        local target_offset = { x = 52, y = 0 }
        local target_pos = ctx.pos(target_offset)
        clear_area(target_pos, 12)

        local machine = ctx.spawn({
            name = "assembling-machine-2",
            offset = target_offset,
            direction = defines.direction.north,
        })
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        assert.is_true(module_inventory[1].set_stack({ name = "productivity-module", count = 1, quality = "normal" }))

        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        inventory.insert({ name = "speed-module", count = 10, quality = "normal" })

        local proxy = ctx.spawn_item_request_proxy({
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
        })
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
