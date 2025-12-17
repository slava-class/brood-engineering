local spider = require("scripts/spider")
local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

describe("module insertion", function()
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
        test_utils.clear_area(surface, position, radius, { anchor_entity = anchor_entity, skip_spiders = true })
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 8000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

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
            name = "wooden-chest",
            position = base_pos,
            force = force,
        }))

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "spiderling", count = 10 })

        anchor_id = "test_anchor_modules_" .. game.tick .. "_" .. math.random(1, 1000000)
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
                e.destroy()
            end
        end
    end)

    test("inserts modules into an assembling machine (3x3)", function()
        local target_pos = { x = base_pos.x + 18, y = base_pos.y }
        clear_area(target_pos, 12)

        local machine = track(surface.create_entity({
            name = "assembling-machine-2",
            position = target_pos,
            direction = defines.direction.north,
            force = force,
        }))
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        local requested = 2
        local supplied = 50
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = track(surface.create_entity({
            name = "item-request-proxy",
            position = machine.position,
            force = force,
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

        async(60 * 25)
        on_tick(function()
            test_utils.run_main_loop_periodic(constants.main_loop_interval)

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

                done()
                return false
            end

            return true
        end)
    end)

    test("inserts modules into an oil refinery (5x5)", function()
        local target_pos = { x = base_pos.x + 34, y = base_pos.y }
        clear_area(target_pos, 15)

        local refinery = track(surface.create_entity({
            name = "oil-refinery",
            position = target_pos,
            direction = defines.direction.north,
            force = force,
        }))
        assert.is_true(refinery and refinery.valid)

        local module_inventory = refinery.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        local requested = 3
        local supplied = 60
        inventory.insert({ name = "speed-module", count = supplied, quality = "normal" })

        local proxy = track(surface.create_entity({
            name = "item-request-proxy",
            position = refinery.position,
            force = force,
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

        async(60 * 25)
        on_tick(function()
            test_utils.run_main_loop_periodic(constants.main_loop_interval)

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

                done()
                return false
            end

            return true
        end)
    end)

    test("swaps a wrong module using removal_plan then clears proxy", function()
        local target_pos = { x = base_pos.x + 52, y = base_pos.y }
        clear_area(target_pos, 12)

        local machine = track(surface.create_entity({
            name = "assembling-machine-2",
            position = target_pos,
            direction = defines.direction.north,
            force = force,
        }))
        assert.is_true(machine and machine.valid)

        local module_inventory = machine.get_module_inventory()
        assert.is_true(module_inventory and module_inventory.valid)

        assert.is_true(module_inventory[1].set_stack({ name = "productivity-module", count = 1, quality = "normal" }))

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "speed-module", count = 10, quality = "normal" })

        local proxy = track(surface.create_entity({
            name = "item-request-proxy",
            position = machine.position,
            force = force,
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

        async(60 * 25)
        on_tick(function()
            test_utils.run_main_loop_periodic(constants.main_loop_interval)

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

                done()
                return false
            end

            return true
        end)
    end)
end)
