local spider = require("scripts/spider")
local utils = require("scripts/utils")
local test_utils = require("tests/test_utils")

describe("spider state transitions", function()
    local ctx
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local spider_id
    local spider_entity
    local task_target
    local task

    local function track(entity)
        return test_utils.track(created, entity)
    end

    before_each(function()
        ctx = test_utils.setup_anchor_test({
            base_pos_factory = function()
                return { x = 2000 + math.random(0, 50), y = math.random(-20, 20) }
            end,
            anchor_name = "wooden-chest",
            anchor_inventory_id = defines.inventory.chest,
            anchor_seed = {},
            anchor_id_prefix = "test_anchor",
        })

        surface = ctx.surface
        force = ctx.force
        base_pos = ctx.base_pos
        created = ctx.created
        anchor_id = ctx.anchor_id
        anchor_entity = ctx.anchor_entity
        anchor_data = ctx.anchor_data

        spider_entity = track(surface.create_entity({
            name = "spiderling",
            position = { x = base_pos.x + 5, y = base_pos.y },
            force = force,
        }))

        spider_id = "test_spider_" .. game.tick .. "_" .. math.random(1, 1000000)
        local spider_entity_id = utils.get_entity_id(spider_entity)
        local spider_data = {
            entity = spider_entity,
            entity_id = spider_entity_id,
            anchor_id = anchor_id,
            status = "deployed_idle",
            task = nil,
            idle_since = nil,
        }

        anchor_data.spiders[spider_id] = spider_data
        storage.spider_to_anchor[spider_id] = anchor_id
        storage.entity_to_spider[spider_entity_id] = spider_id

        ctx.defer(function()
            if anchor_data and anchor_data.spiders then
                anchor_data.spiders[spider_id] = nil
            end
            if storage.spider_to_anchor then
                storage.spider_to_anchor[spider_id] = nil
            end
            if storage.entity_to_spider then
                storage.entity_to_spider[spider_entity_id] = nil
            end
        end)

        task_target = track(surface.create_entity({
            name = "stone-furnace",
            position = { x = base_pos.x + 15, y = base_pos.y },
            force = force,
        }))

        task = {
            id = "test_task_" .. game.tick,
            entity = task_target,
            behavior_name = "build_entity",
        }
    end)

    after_each(function()
        test_utils.teardown_anchor_test(ctx)
        ctx = nil
    end)

    test("assign_task sets moving_to_task and tracks assignment", function()
        spider.assign_task(spider_id, task)
        local anchor_data = storage.anchors[anchor_id]
        local spider_data = anchor_data.spiders[spider_id]

        assert.are_equal("moving_to_task", spider_data.status)
        assert.is_not_nil(spider_data.task)
        assert.are_equal(task.id, spider_data.task.id)
        assert.are_equal(spider_id, storage.assigned_tasks[task.id])
        assert.is_not_nil(spider_entity.autopilot_destination)
        assert.is_nil(spider_entity.follow_target)
    end)

    test("clear_task returns to idle and clears tracking", function()
        spider.assign_task(spider_id, task)
        spider.clear_task(spider_id)
        local anchor_data = storage.anchors[anchor_id]
        local spider_data = anchor_data.spiders[spider_id]

        assert.are_equal("deployed_idle", spider_data.status)
        assert.is_nil(spider_data.task)
        assert.is_nil(storage.assigned_tasks[task.id])
        assert.is_not_nil(spider_entity.follow_target)
        assert.are_equal(anchor_entity.unit_number, spider_entity.follow_target.unit_number)

        after_ticks(1, function()
            local destinations = spider_entity.autopilot_destinations
            assert.is_true(not destinations or #destinations == 0)
        end)
    end)

    test("arrive_at_task and complete_task clear assignment and follow anchor", function()
        spider.assign_task(spider_id, task)
        spider.arrive_at_task(spider_id)
        local anchor_data = storage.anchors[anchor_id]
        local spider_data = anchor_data.spiders[spider_id]
        assert.are_equal("executing", spider_data.status)

        spider.complete_task(spider_id)
        assert.are_equal("deployed_idle", spider_data.status)
        assert.is_nil(spider_data.task)
        assert.is_nil(storage.assigned_tasks[task.id])
        assert.is_not_nil(spider_entity.follow_target)
        assert.are_equal(anchor_entity.unit_number, spider_entity.follow_target.unit_number)
    end)
end)
