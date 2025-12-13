local tasks = require("scripts/tasks")
local build_entity = require("scripts/behaviors/build_entity")

describe("tasks", function()
    local surface
    local force
    local base_pos
    local created = {}

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 1000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        storage.assigned_tasks = {}
    end)

    after_each(function()
        for _, e in ipairs(created) do
            if e and e.valid then e.destroy() end
        end
    end)

    test("picks unblock_deconstruct over build ghosts", function()
        local pos = { x = base_pos.x, y = base_pos.y }

        local chest = track(surface.create_entity({
            name = "wooden-chest",
            position = { x = pos.x + 3, y = pos.y },
            force = force,
        }))
        local inventory = chest.get_inventory(defines.inventory.chest)

        local entity = track(surface.create_entity({
            name = "stone-furnace",
            position = pos,
            force = force,
        }))
        entity.order_deconstruction(force)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            force = force,
            expires = false,
        }))

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        local task = tasks.find_best(surface, area, { force.name, "neutral" }, inventory)

        assert.is_not_nil(task)
        assert.are_equal("unblock_deconstruct", task.behavior_name)
    end)

    test("skips already-assigned tasks", function()
        local pos = { x = base_pos.x + 15, y = base_pos.y }

        local chest = track(surface.create_entity({
            name = "wooden-chest",
            position = { x = pos.x + 3, y = pos.y },
            force = force,
        }))
        local inventory = chest.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        local ghost = track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            force = force,
            expires = false,
        }))

        local task_id = build_entity.get_task_id(ghost)
        storage.assigned_tasks[task_id] = "spider_x"

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        local task = tasks.find_best(surface, area, { force.name, "neutral" }, inventory)
        assert.is_nil(task)

        storage.assigned_tasks[task_id] = nil
        local task2 = tasks.find_best(surface, area, { force.name, "neutral" }, inventory)
        assert.is_not_nil(task2)
        assert.are_equal("build_entity", task2.behavior_name)
    end)

    test("exist_executable_in_area ignores blocked ghosts", function()
        local pos = { x = base_pos.x + 30, y = base_pos.y }

        local chest = track(surface.create_entity({
            name = "wooden-chest",
            position = { x = pos.x + 3, y = pos.y },
            force = force,
        }))
        local inventory = chest.get_inventory(defines.inventory.chest)

        track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = pos,
            force = force,
            expires = false,
        }))

        local area = { { pos.x - 3, pos.y - 3 }, { pos.x + 3, pos.y + 3 } }
        assert.is_true(tasks.exist_in_area(surface, area, { force.name, "neutral" }))
        assert.is_false(tasks.exist_executable_in_area(surface, area, { force.name, "neutral" }, inventory))
    end)
end)
