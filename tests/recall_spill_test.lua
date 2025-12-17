local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

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
        return test_utils.track(created, entity)
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 9000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        -- Ensure the chunk is generated; item spilling won't work reliably otherwise.
        test_utils.ensure_chunks(surface, base_pos, 1)

        original_global_enabled = test_utils.disable_global_enabled()

        -- Fully reset mod state for isolation.
        test_utils.reset_storage()

        -- Use a character anchor so we can reliably fill the inventory.
        anchor_id, anchor_entity, anchor_data = test_utils.create_test_anchor({
            surface = surface,
            force = force,
            position = base_pos,
            name = "character",
            inventory_id = defines.inventory.character_main,
            seed = { { name = "spiderling", count = 1 } },
            anchor_id_prefix = "test_anchor_recall_spill",
            track = track,
        })
    end)

    after_each(function()
        test_utils.teardown_anchor(anchor_id, anchor_data)
        test_utils.restore_global_enabled(original_global_enabled)
        test_utils.destroy_tracked(created)
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
