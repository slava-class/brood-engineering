local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("recall spill behavior", function()
    return {
        base_pos = test_utils.random_base_pos(9000),
        ensure_chunks_radius = 1,
        clean_radius = 40,
        clear_radius = 16,
        anchor_name = "character",
        anchor_inventory_id = defines.inventory.character_main,
        anchor_seed = { { name = "spiderling", count = 1 } },
        anchor_id_prefix = "test_anchor_recall_spill",
    }
end, function(ctx)
    test("recall spills spiderling item when anchor inventory is full", function()
        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        assert.are_equal(1, inventory.get_item_count("spiderling"))

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local spider_data = test_utils.get_spider_data(ctx, spider_id)
        assert.is_true(spider_data.entity and spider_data.entity.valid)
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
                local drops = ctx.surface.find_entities_filtered(filter)
                for _, drop in ipairs(drops) do
                    local stack = drop and drop.valid and drop.stack
                    if stack and stack.valid_for_read and stack.name == "spiderling" then
                        return drop
                    end
                end
            end

            return nil
        end

        local drop = find_spiderling_drop(spider_pos, 25) or find_spiderling_drop(ctx.anchor_entity.position, 25)
        assert.is_true(drop ~= nil)
        ctx.track(drop)
    end)
end)
