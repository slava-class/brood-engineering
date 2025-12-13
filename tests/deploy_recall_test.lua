local spider = require("scripts/spider")
local anchor = require("scripts/anchor")
local constants = require("scripts/constants")

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
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 3000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = storage.global_enabled
        storage.global_enabled = false

        storage.anchors = storage.anchors or {}
        storage.spider_to_anchor = storage.spider_to_anchor or {}
        storage.entity_to_spider = storage.entity_to_spider or {}
        storage.assigned_tasks = storage.assigned_tasks or {}

        anchor_entity = track(surface.create_entity({
            name = "wooden-chest",
            position = base_pos,
            force = force,
        }))
        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "spiderling", count = 1 })

        anchor_id = "test_anchor_deploy_" .. game.tick .. "_" .. math.random(1, 1000000)
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
        if anchor_id and storage.anchors then
            storage.anchors[anchor_id] = nil
        end
        storage.global_enabled = original_global_enabled

        for _, e in ipairs(created) do
            if e and e.valid then e.destroy() end
        end
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

	        -- Cleanup: recall so we don't leave orphaned spiders between tests/runs.
	        after_test(function()
	            spider.recall(spider_id)
	        end)
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
