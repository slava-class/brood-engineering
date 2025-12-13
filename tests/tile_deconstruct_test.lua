local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local constants = require("scripts/constants")

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
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 6000 + math.random(0, 50), y = math.random(-20, 20) }
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

        -- Use a character anchor so `mine_tile` is available (matches in-game behavior).
        anchor_entity = track(surface.create_entity({
            name = "character",
            position = base_pos,
            force = force,
        }))
        local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
        inventory.insert({ name = "spiderling", count = 1 })

        anchor_id = "test_anchor_tile_" .. game.tick .. "_" .. math.random(1, 1000000)
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
            if e and e.valid then e.destroy() end
        end
    end)

    test("removes deconstruct-marked stone-path tile", function()
        local tile_pos = { x = base_pos.x + 2, y = base_pos.y }
        surface.set_tiles({ { name = "grass-1", position = tile_pos } }, true)
        surface.set_tiles({ { name = "stone-path", position = tile_pos } }, true)

        local tile = surface.get_tile(tile_pos)
        tile.order_deconstruction(force)
        do
            local ok, marked = pcall(tile.to_be_deconstructed, tile)
            if ok then
                assert.is_true(marked)
            end
        end

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        async(60 * 20)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            local current_tile = surface.get_tile(tile_pos)
            if current_tile and current_tile.valid and current_tile.name ~= "stone-path" then
                local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
                if inventory.get_item_count("stone-brick") >= 1 then
                    assert.are_equal("grass-1", current_tile.name)
                    done()
                    return false
                end
            end

            return true
        end)
    end)
end)
