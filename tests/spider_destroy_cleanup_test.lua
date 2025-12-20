local fapi = require("scripts/fapi")
local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("spider destroyed cleanup", function()
    return test_utils.anchor_opts.chest({
        x_base = 15000,
        radii = "small",
        anchor_seed = {
            { name = "spiderling", count = 1, quality = "normal" },
        },
    })
end, function(ctx)
    test("on_object_destroyed clears spider tracking + assigned task", function()
        local inv = ctx.anchor_inventory
        assert(inv and inv.valid)
        inv.clear()
        inv.insert({ name = "spiderling", count = 1, quality = "normal" })

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        local spider_data = test_utils.get_spider_data(ctx, spider_id)
        local spider_entity = spider_data and spider_data.entity
        assert(spider_entity and spider_entity.valid)

        local entity_id = spider_data.entity_id
        assert(type(entity_id) == "number")

        local task_id = "destroy_cleanup_" .. game.tick
        spider_data.task = { id = task_id }
        storage.assigned_tasks[task_id] = spider_id

        fapi.destroy_quiet(spider_entity)

        test_utils.wait_until({
            timeout_ticks = 60 * 10,
            description = "on_object_destroyed cleanup",
            condition = function()
                if storage.entity_to_spider[entity_id] ~= nil then
                    return false
                end
                if storage.spider_to_anchor[spider_id] ~= nil then
                    return false
                end
                if storage.assigned_tasks[task_id] ~= nil then
                    return false
                end
                return test_utils.find_spider_data(ctx, spider_id) == nil
            end,
        })
    end)
end)
