local spider = require("scripts/spider")
local utils = require("scripts/utils")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("spider state transitions", function()
    return test_utils.anchor_opts.chest({
        x_base = 2000,
        anchor_seed = {},
    })
end, function(ctx)
    local spider_id
    local spider_entity
    local task_target
    local task

    before_each(function()
        spider_entity = ctx.spawn({
            name = "spiderling",
            offset = { x = 5, y = 0 },
        })

        spider_id = "test_spider_" .. game.tick .. "_" .. math.random(1, 1000000)
        local spider_entity_id = utils.get_entity_id(spider_entity)
        local spider_data = {
            entity = spider_entity,
            entity_id = spider_entity_id,
            anchor_id = ctx.anchor_id,
            status = "deployed_idle",
            task = nil,
            idle_since = nil,
        }

        ctx.anchor_data.spiders[spider_id] = spider_data
        storage.spider_to_anchor[spider_id] = ctx.anchor_id
        storage.entity_to_spider[spider_entity_id] = spider_id

        ctx.defer(function()
            if ctx.anchor_data and ctx.anchor_data.spiders then
                ctx.anchor_data.spiders[spider_id] = nil
            end
            if storage.spider_to_anchor then
                storage.spider_to_anchor[spider_id] = nil
            end
            if storage.entity_to_spider then
                storage.entity_to_spider[spider_entity_id] = nil
            end
            if storage.assigned_tasks and task and task.id then
                storage.assigned_tasks[task.id] = nil
            end
        end)

        task_target = ctx.spawn({
            name = "stone-furnace",
            offset = { x = 15, y = 0 },
        })

        task = {
            id = "test_task_" .. game.tick,
            entity = task_target,
            behavior_name = "build_entity",
        }
    end)

    test("assign_task sets moving_to_task and tracks assignment", function()
        spider.assign_task(spider_id, task)
        local spider_data = test_utils.get_spider_data(ctx, spider_id)

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

        local spider_data = test_utils.get_spider_data(ctx, spider_id)
        assert.are_equal("deployed_idle", spider_data.status)
        assert.is_nil(spider_data.task)
        assert.is_nil(storage.assigned_tasks[task.id])
        test_utils.assert_spider_following_anchor(ctx, spider_id)

        after_ticks(1, function()
            local destinations = spider_entity.autopilot_destinations
            assert.is_true(not destinations or #destinations == 0)
        end)
    end)

    test("arrive_at_task and complete_task clear assignment and follow anchor", function()
        spider.assign_task(spider_id, task)
        spider.arrive_at_task(spider_id)
        test_utils.assert_spider_status(ctx, spider_id, "executing")

        spider.complete_task(spider_id)
        test_utils.assert_spider_status(ctx, spider_id, "deployed_idle")
        local spider_data = test_utils.get_spider_data(ctx, spider_id)
        assert.is_nil(spider_data.task)
        assert.is_nil(storage.assigned_tasks[task.id])
        test_utils.assert_spider_following_anchor(ctx, spider_id)
    end)
end)
