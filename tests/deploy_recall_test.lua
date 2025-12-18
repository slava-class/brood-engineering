local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("deploy and recall", function()
    return {
        base_pos = test_utils.random_base_pos(3000),
        clean_radius = 40,
        clear_radius = 12,
        anchor_name = "wooden-chest",
        anchor_inventory_id = defines.inventory.chest,
        anchor_seed = { { name = "spiderling", count = 1 } },
        anchor_id_prefix = "test_anchor_deploy",
    }
end, function(ctx)
    test("deploy consumes spiderling and registers spider", function()
        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        assert.are_equal(1, inventory.get_item_count("spiderling"))

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        assert.are_equal(0, inventory.get_item_count("spiderling"))
        assert.are_equal(ctx.anchor_id, storage.spider_to_anchor[spider_id])

        local deployed_data = test_utils.get_spider_data(ctx, spider_id)
        assert.are_equal("deployed_idle", deployed_data.status)
        assert.is_true(deployed_data.entity and deployed_data.entity.valid)
        assert.are_equal("spiderling", deployed_data.entity.name)
        test_utils.assert_spider_following_anchor(ctx, spider_id)
    end)

    test("recall returns spiderling and cleans tracking", function()
        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)
        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local deployed_data = test_utils.get_spider_data(ctx, spider_id)
        local entity_id = deployed_data.entity_id
        local deployed_entity = deployed_data.entity

        spider.recall(spider_id)

        assert.are_equal(1, inventory.get_item_count("spiderling"))
        assert.is_nil(test_utils.find_spider_data(ctx, spider_id))
        assert.is_nil(storage.spider_to_anchor[spider_id])
        if entity_id then
            assert.is_nil(storage.entity_to_spider[entity_id])
        end
        if deployed_entity then
            assert.is_false(deployed_entity.valid)
        end
    end)
end)
