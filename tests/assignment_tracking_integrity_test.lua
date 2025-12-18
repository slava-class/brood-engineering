local tasks = require("scripts/tasks")
local test_utils = require("tests/test_utils")

test_utils.describe_surface_test("assignment tracking integrity", nil, function()
    before_each(function()
        storage.assigned_tasks = {}
        storage.spider_to_anchor = {}
        storage.anchors = {}
    end)

    test("tasks.execute clears storage.assigned_tasks on success", function()
        local target = { valid = true }
        local task = {
            id = "test_task_success",
            entity = target,
            behavior = {
                name = "test_behavior_success",
                can_execute = function()
                    return true
                end,
                execute = function()
                    return true
                end,
            },
        }

        storage.assigned_tasks[task.id] = "test_spider"
        assert.is_true(tasks.execute({}, task, {}, {}))
        assert.is_nil(storage.assigned_tasks[task.id])
    end)

    test("tasks.execute clears storage.assigned_tasks when behavior.execute fails", function()
        local target = { valid = true }
        local task = {
            id = "test_task_failure",
            entity = target,
            behavior = {
                name = "test_behavior_failure",
                can_execute = function()
                    return true
                end,
                execute = function()
                    -- Simulate the target becoming invalid mid-execution.
                    target.valid = false
                    return false
                end,
            },
        }

        storage.assigned_tasks[task.id] = "test_spider"
        assert.is_false(tasks.execute({}, task, {}, {}))
        assert.is_nil(storage.assigned_tasks[task.id])
    end)

    test("tasks.cleanup_stale removes assignments for missing/mismatched spiders", function()
        local anchor_id = "test_anchor"
        local spider_ok = "test_spider_ok"
        local spider_missing = "test_spider_missing"
        local spider_wrong_task = "test_spider_wrong_task"

        storage.anchors[anchor_id] = {
            spiders = {
                [spider_ok] = { task = { id = "task_ok" } },
                [spider_wrong_task] = { task = { id = "task_other" } },
            },
        }
        storage.spider_to_anchor[spider_ok] = anchor_id
        storage.spider_to_anchor[spider_wrong_task] = anchor_id
        storage.spider_to_anchor[spider_missing] = anchor_id

        storage.assigned_tasks.task_ok = spider_ok
        storage.assigned_tasks.task_missing_spider = spider_missing
        storage.assigned_tasks.task_wrong_task = spider_wrong_task
        storage.assigned_tasks.task_missing_anchor = "test_spider_missing_anchor"

        tasks.cleanup_stale()

        assert.are_equal(spider_ok, storage.assigned_tasks.task_ok)
        assert.is_nil(storage.assigned_tasks.task_missing_spider)
        assert.is_nil(storage.assigned_tasks.task_wrong_task)
        assert.is_nil(storage.assigned_tasks.task_missing_anchor)
    end)
end)
