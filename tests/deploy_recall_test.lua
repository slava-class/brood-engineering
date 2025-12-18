local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

describe("deploy and recall", function()
    local ctx

    before_each(function()
        ctx = test_utils.setup_anchor_test({
            base_pos = { x = 3000 + math.random(0, 50), y = math.random(-20, 20) },
            clean_radius = 40,
            clear_radius = 12,
            anchor_name = "wooden-chest",
            anchor_inventory_id = defines.inventory.chest,
            anchor_seed = { { name = "spiderling", count = 1 } },
            anchor_id_prefix = "test_anchor_deploy",
        })
    end)

    after_each(function()
        test_utils.teardown_anchor_test(ctx)
    end)

    test("deploy consumes spiderling and registers spider", function()
        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        assert.are_equal(1, inventory.get_item_count("spiderling"))

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        assert.are_equal(0, inventory.get_item_count("spiderling"))
        assert.are_equal(ctx.anchor_id, storage.spider_to_anchor[spider_id])

        local deployed_data = ctx.anchor_data.spiders[spider_id]
        assert.is_not_nil(deployed_data)
        assert.are_equal("deployed_idle", deployed_data.status)
        assert.is_true(deployed_data.entity and deployed_data.entity.valid)
        assert.are_equal("spiderling", deployed_data.entity.name)
        assert.are_equal(ctx.anchor_entity.unit_number, deployed_data.entity.follow_target.unit_number)
    end)

    test("recall returns spiderling and cleans tracking", function()
        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)
        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local deployed_data = ctx.anchor_data.spiders[spider_id]
        local entity_id = deployed_data and deployed_data.entity_id
        local deployed_entity = deployed_data and deployed_data.entity

        spider.recall(spider_id)

        assert.are_equal(1, inventory.get_item_count("spiderling"))
        assert.is_nil(ctx.anchor_data.spiders[spider_id])
        assert.is_nil(storage.spider_to_anchor[spider_id])
        if entity_id then
            assert.is_nil(storage.entity_to_spider[entity_id])
        end
        if deployed_entity then
            assert.is_false(deployed_entity.valid)
        end
    end)
end)
