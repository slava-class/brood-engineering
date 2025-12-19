local build_entity = require("scripts/behaviors/build_entity")
local fapi = require("scripts/fapi")
local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("disable while moving clears assignments", function()
    return test_utils.anchor_opts.chest({
        x_base = 14000,
        radii = "idle",
        anchor_seed = {
            { name = "spiderling", count = 1, quality = "normal" },
            { name = "stone-furnace", count = 1, quality = "normal" },
        },
    })
end, function(ctx)
    test("disabling while moving_to_task clears storage.assigned_tasks", function()
        storage.global_enabled = true

        local inv = ctx.anchor_inventory
        assert(inv and inv.valid)
        inv.clear()
        inv.insert({ name = "spiderling", count = 1, quality = "normal" })
        inv.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        do
            local spider_data = test_utils.get_spider_data(ctx, spider_id)
            local spider_entity = spider_data and spider_data.entity
            assert(spider_entity and spider_entity.valid)

            local near_anchor_pos = fapi.find_non_colliding_position(ctx.surface, "spiderling", ctx.base_pos, 10, 0.5)
                or ctx.base_pos
            assert.is_true(fapi.teleport(spider_entity, near_anchor_pos, ctx.surface))
        end

        local task_pos = ctx.pos({ x = 60, y = 0 })
        test_utils.ensure_chunks(ctx.surface, task_pos, 2)
        ctx.clear_area(task_pos, 20)
        local ghost = ctx.spawn_ghost({
            inner_name = "stone-furnace",
            position = task_pos,
            expires = false,
        })
        local task_id = build_entity.get_task_id(ghost)

        spider.assign_task(spider_id, {
            id = task_id,
            entity = ghost,
            tile = nil,
            behavior_name = "build_entity",
        })
        do
            local spider_data = test_utils.get_spider_data(ctx, spider_id)
            assert.are_equal("moving_to_task", spider_data.status)
            assert.is_true(storage.assigned_tasks and storage.assigned_tasks[task_id] == spider_id)
        end

        local spider_data = test_utils.get_spider_data(ctx, spider_id)
        local entity_id = spider_data.entity_id
        assert(type(entity_id) == "number")

        test_utils.press_brood_toggle(1)

        assert.is_false(storage.global_enabled)
        assert.is_true(ghost and ghost.valid and ghost.type == "entity-ghost")

        assert.is_nil(storage.assigned_tasks[task_id])
        assert.is_nil(storage.spider_to_anchor[spider_id])
        assert.is_nil(storage.entity_to_spider[entity_id])
        assert.is_nil(test_utils.find_spider_data(ctx, spider_id))
    end)
end)
