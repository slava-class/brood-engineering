local tasks = require("scripts/tasks")
local build_entity = require("scripts/behaviors/build_entity")
local test_utils = require("tests/test_utils")

test_utils.describe_surface_test("tasks", nil, function(ctx)
    before_each(function()
        storage.assigned_tasks = {}
    end)

    test("picks unblock_deconstruct over build ghosts", function()
        local pos = ctx.base_pos

        local chest = ctx.spawn({
            name = "wooden-chest",
            offset = { x = 3, y = 0 },
        })
        local inventory = chest.get_inventory(defines.inventory.chest)

        local entity = ctx.spawn({
            name = "stone-furnace",
            position = pos,
        })
        entity.order_deconstruction(ctx.force)

        ctx.spawn({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            expires = false,
        })

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        local task = tasks.find_best(ctx.surface, area, { ctx.force.name, "neutral" }, inventory)

        assert.is_not_nil(task)
        assert.are_equal("unblock_deconstruct", task.behavior_name)
    end)

    test("skips already-assigned tasks", function()
        local pos = ctx.pos({ x = 15, y = 0 })

        local chest = ctx.spawn({
            name = "wooden-chest",
            position = ctx.pos({ x = 18, y = 0 }),
        })
        local inventory = chest.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        local ghost = ctx.spawn({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            expires = false,
        })

        local task_id = build_entity.get_task_id(ghost)
        storage.assigned_tasks[task_id] = "spider_x"

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        local task = tasks.find_best(ctx.surface, area, { ctx.force.name, "neutral" }, inventory)
        assert.is_nil(task)

        storage.assigned_tasks[task_id] = nil
        local task2 = tasks.find_best(ctx.surface, area, { ctx.force.name, "neutral" }, inventory)
        assert.is_not_nil(task2)
        assert.are_equal("build_entity", task2.behavior_name)
    end)

    test("exist_executable_in_area ignores blocked ghosts", function()
        local pos = ctx.pos({ x = 30, y = 0 })

        local chest = ctx.spawn({
            name = "wooden-chest",
            position = ctx.pos({ x = 33, y = 0 }),
        })
        local inventory = chest.get_inventory(defines.inventory.chest)

        ctx.spawn({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            expires = false,
        })

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        assert.is_true(tasks.exist_in_area(ctx.surface, area, { ctx.force.name, "neutral" }))
        assert.is_false(tasks.exist_executable_in_area(ctx.surface, area, { ctx.force.name, "neutral" }, inventory))
    end)

    test("does not crash when mine products have 0 minimum", function()
        local pos = ctx.pos({ x = 45, y = 0 })

        local chest = ctx.spawn({
            name = "wooden-chest",
            position = ctx.pos({ x = 48, y = 0 }),
        })
        local inventory = chest.get_inventory(defines.inventory.chest)

        -- Trees can have random mine products (often `amount_min = 0`).
        local tree = ctx.spawn({
            name = "tree-01",
            position = pos,
            force = "neutral",
        })
        assert.is_true(tree and tree.valid)

        tree.order_deconstruction(ctx.force)
        assert.is_true(tree.to_be_deconstructed())

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        local ok, result = pcall(function()
            return tasks.find_all(ctx.surface, area, { ctx.force.name, "neutral" }, inventory)
        end)
        assert.is_true(ok)
        assert.is_true(type(result) == "table")
    end)
end)
