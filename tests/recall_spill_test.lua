local spider = require("scripts/spider")

describe("recall spill behavior", function()
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
        base_pos = { x = 9000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        -- Ensure the chunk is generated; item spilling won't work reliably otherwise.
        surface.request_to_generate_chunks(base_pos, 1)
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

        -- Use a character anchor so we can reliably fill the inventory.
        anchor_entity = track(surface.create_entity({
            name = "character",
            position = base_pos,
            force = force,
        }))

        local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
        inventory.insert({ name = "spiderling", count = 1 })

        anchor_id = "test_anchor_recall_spill_" .. game.tick .. "_" .. math.random(1, 1000000)
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

    test("recall spills spiderling item when anchor inventory is full", function()
        local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
        assert.are_equal(1, inventory.get_item_count("spiderling"))

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local spider_data = anchor_data.spiders[spider_id]
        assert.is_true(spider_data and spider_data.entity and spider_data.entity.valid)
        local spider_entity = spider_data.entity
        spider_entity.follow_target = nil
        local spider_pos = { x = spider_entity.position.x, y = spider_entity.position.y }

        -- Fill the anchor inventory so the spiderling can't be inserted on recall.
        inventory.insert({ name = "iron-plate", count = 100000, quality = "normal" })
        while inventory.can_insert({ name = "spiderling", count = 1, quality = "normal" }) do
            inventory.insert({ name = "iron-plate", count = 100000, quality = "normal" })
        end
        assert.is_false(inventory.can_insert({ name = "spiderling", count = 1, quality = "normal" }))

        spider.recall(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local function find_spiderling_drop(position, radius)
            local filters = {
                { name = "item-on-ground", position = position, radius = radius },
                { type = "item-entity", position = position, radius = radius },
            }

            for _, filter in ipairs(filters) do
                local drops = surface.find_entities_filtered(filter)
                for _, drop in ipairs(drops) do
                    local stack = drop and drop.valid and drop.stack
                    if stack and stack.valid_for_read and stack.name == "spiderling" then
                        return drop
                    end
                end
            end

            return nil
        end

        local drop = find_spiderling_drop(spider_pos, 25) or find_spiderling_drop(anchor_entity.position, 25)
        assert.is_true(drop ~= nil)
        track(drop)
    end)
end)
