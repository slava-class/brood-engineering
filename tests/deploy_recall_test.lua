local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

describe("deploy and recall", function()
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
        base_pos = { x = 3000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = test_utils.disable_global_enabled()
        test_utils.reset_storage()

        anchor_id, anchor_entity, anchor_data = test_utils.create_test_anchor({
            surface = surface,
            force = force,
            position = base_pos,
            name = "wooden-chest",
            inventory_id = defines.inventory.chest,
            seed = { { name = "spiderling", count = 1 } },
            anchor_id_prefix = "test_anchor_deploy",
            track = track,
        })
    end)

    after_each(function()
        test_utils.teardown_anchor(anchor_id, anchor_data)
        test_utils.restore_global_enabled(original_global_enabled)
        test_utils.destroy_tracked(created)
    end)

    test("deploy consumes spiderling and registers spider", function()
        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        assert.are_equal(1, inventory.get_item_count("spiderling"))

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        assert.are_equal(0, inventory.get_item_count("spiderling"))
        assert.are_equal(anchor_id, storage.spider_to_anchor[spider_id])

        local deployed_data = anchor_data.spiders[spider_id]
        assert.is_not_nil(deployed_data)
        assert.are_equal("deployed_idle", deployed_data.status)
        assert.is_true(deployed_data.entity and deployed_data.entity.valid)
        assert.are_equal("spiderling", deployed_data.entity.name)
        assert.are_equal(anchor_entity.unit_number, deployed_data.entity.follow_target.unit_number)
    end)

    test("recall returns spiderling and cleans tracking", function()
        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)
        assert.are_equal(0, inventory.get_item_count("spiderling"))

        local deployed_data = anchor_data.spiders[spider_id]
        local entity_id = deployed_data and deployed_data.entity_id
        local deployed_entity = deployed_data and deployed_data.entity

        spider.recall(spider_id)

        assert.are_equal(1, inventory.get_item_count("spiderling"))
        assert.is_nil(anchor_data.spiders[spider_id])
        assert.is_nil(storage.spider_to_anchor[spider_id])
        if entity_id then
            assert.is_nil(storage.entity_to_spider[entity_id])
        end
        if deployed_entity then
            assert.is_false(deployed_entity.valid)
        end
    end)
end)
