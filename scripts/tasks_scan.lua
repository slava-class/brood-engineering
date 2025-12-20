-- scripts/tasks_scan.lua
-- Legacy scan-based task discovery (currently unused).

local tasks_scan = {}

-- Behaviors list
local behaviors_list = require("scripts/behaviors/init")

--- Get behaviors list
---@return table[]
local function get_behaviors()
    return behaviors_list
end

---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param cb fun(behavior: table, targets: table): boolean? stop
local function for_each_behavior_targets(surface, area, force, cb)
    for _, behavior in ipairs(get_behaviors()) do
        local targets = behavior.find_tasks(surface, area, force)
        if targets and #targets > 0 then
            if cb(behavior, targets) then
                return true
            end
        end
    end
    return false
end

--- Check if a task is already assigned
---@param task_id string
---@return boolean
function tasks_scan.is_assigned(task_id)
    return storage.assigned_tasks[task_id] ~= nil
end

--- Find the best task for a spider in an area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table? task { id, entity/tile, behavior_name }
function tasks_scan.find_best(surface, area, force, inventory)
    -- Try each behavior in priority order
    local best_task = nil
    for_each_behavior_targets(surface, area, force, function(behavior, targets)
        if not (targets and #targets > 0) then
            return false
        end

        do
            -- Shuffle targets for fairness
            for i = #targets, 2, -1 do
                local j = math.random(i)
                targets[i], targets[j] = targets[j], targets[i]
            end

            for _, target in ipairs(targets) do
                local task_id = behavior.get_task_id(target)

                -- Skip if already assigned
                if not tasks_scan.is_assigned(task_id) then
                    -- Check if we can execute
                    if behavior.can_execute(target, inventory) then
                        best_task = {
                            id = task_id,
                            entity = target.object_name == "LuaEntity" and target or nil,
                            tile = target.object_name == "LuaTile" and target or nil,
                            -- Store only a serialisable identifier, not the behavior table itself
                            behavior_name = behavior.name,
                        }
                        return true
                    end
                end
            end
        end

        return false
    end)

    return best_task
end

--- Find all tasks in an area (for batch processing)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table[] tasks
function tasks_scan.find_all(surface, area, force, inventory)
    local result = {}

    for_each_behavior_targets(surface, area, force, function(behavior, targets)
        for _, target in ipairs(targets) do
            local task_id = behavior.get_task_id(target)

            if not tasks_scan.is_assigned(task_id) then
                if behavior.can_execute(target, inventory) then
                    result[#result + 1] = {
                        id = task_id,
                        entity = target.object_name == "LuaEntity" and target or nil,
                        tile = target.object_name == "LuaTile" and target or nil,
                        -- Store only a serialisable identifier, not the behavior table itself
                        behavior_name = behavior.name,
                        priority = behavior.priority,
                    }
                end
            end
        end
        return false
    end)

    -- Sort by priority
    table.sort(result, function(a, b)
        return a.priority < b.priority
    end)

    return result
end

--- Check if any tasks exist in an area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return boolean
function tasks_scan.exist_in_area(surface, area, force)
    return for_each_behavior_targets(surface, area, force, function(_, targets)
        return targets and #targets > 0
    end)
end

--- Check if any executable tasks exist in an area (i.e., can_execute passes)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return boolean
function tasks_scan.exist_executable_in_area(surface, area, force, inventory)
    return for_each_behavior_targets(surface, area, force, function(behavior, targets)
        for _, target in ipairs(targets) do
            if behavior.can_execute(target, inventory) then
                return true
            end
        end
        return false
    end)
end

return tasks_scan
