local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local constants = require("scripts/constants")

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
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    local function clear_build_area(position, radius)
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
                entity.destroy({ raise_destroy = false })
            end
            ::continue::
        end
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 7000 + math.random(0, 50), y = math.random(-20, 20) }
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

        anchor_id = "test_anchor_build_large_" .. game.tick .. "_" .. math.random(1, 1000000)
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

        remote.call("brood-engineering-test", "run_main_loop")

        async(60 * 30)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            local furnace = surface.find_entity("stone-furnace", ghost_pos)
            if furnace and furnace.valid then
                assert.are_equal(0, inventory.get_item_count({ name = "stone-furnace", quality = "normal" }))
                done()
                return false
            end

            return true
        end)
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

        remote.call("brood-engineering-test", "run_main_loop")

        async(60 * 30)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            local machine = surface.find_entity("assembling-machine-2", ghost_pos)
            if machine and machine.valid then
                assert.are_equal(0, inventory.get_item_count({ name = "assembling-machine-2", quality = "normal" }))
                done()
                return false
            end

            return true
        end)
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

        remote.call("brood-engineering-test", "run_main_loop")

        async(60 * 40)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            local refinery = surface.find_entity("oil-refinery", ghost_pos)
            if refinery and refinery.valid then
                assert.are_equal(0, inventory.get_item_count({ name = "oil-refinery", quality = "normal" }))
                done()
                return false
            end

            return true
        end)
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

        remote.call("brood-engineering-test", "run_main_loop")

        async(60 * 40)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            local silo = surface.find_entity("rocket-silo", ghost_pos)
            if silo and silo.valid then
                assert.are_equal(0, inventory.get_item_count({ name = "rocket-silo", quality = "normal" }))
                done()
                return false
            end

            return true
        end)
    end)
end)
