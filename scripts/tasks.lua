-- scripts/tasks.lua
-- Task finding and assignment logic for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local tasks = {}

-- Behaviors list
local behaviors_list = require("scripts/behaviors/init")
local behaviors_by_name = nil

--- Get behaviors list
---@return table[]
local function get_behaviors()
    return behaviors_list
end

---@param name string
---@return table? behavior
local function get_behavior_by_name(name)
    if not name then
        return nil
    end
    if not behaviors_by_name then
        behaviors_by_name = {}
        for _, behavior in ipairs(get_behaviors()) do
            if behavior and behavior.name then
                behaviors_by_name[behavior.name] = behavior
            end
        end
    end
    return behaviors_by_name[name]
end

--- Check if a task is already assigned
---@param task_id string
---@return boolean
function tasks.is_assigned(task_id)
    return storage.assigned_tasks[task_id] ~= nil
end

--- Find the best task for a spider in an area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table? task { id, entity/tile, behavior_name }
function tasks.find_best(surface, area, force, inventory)
    local behaviors = get_behaviors()

    -- Try each behavior in priority order
    for _, behavior in ipairs(behaviors) do
        local targets = behavior.find_tasks(surface, area, force)

        if targets and #targets > 0 then
            -- Shuffle targets for fairness
            for i = #targets, 2, -1 do
                local j = math.random(i)
                targets[i], targets[j] = targets[j], targets[i]
            end

            for _, target in ipairs(targets) do
                local task_id = behavior.get_task_id(target)

                -- Skip if already assigned
                if not tasks.is_assigned(task_id) then
                    -- Check if we can execute
                    if behavior.can_execute(target, inventory) then
                        return {
                            id = task_id,
                            entity = target.object_name == "LuaEntity" and target or nil,
                            tile = target.object_name == "LuaTile" and target or nil,
                            -- Store only a serialisable identifier, not the behavior table itself
                            behavior_name = behavior.name,
                        }
                    end
                end
            end
        end
    end

    return nil
end

--- Find all tasks in an area (for batch processing)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table[] tasks
function tasks.find_all(surface, area, force, inventory)
    local behaviors = get_behaviors()
    local result = {}

    for _, behavior in ipairs(behaviors) do
        local targets = behavior.find_tasks(surface, area, force)

        if targets then
            for _, target in ipairs(targets) do
                local task_id = behavior.get_task_id(target)

                if not tasks.is_assigned(task_id) then
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
        end
    end

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
function tasks.exist_in_area(surface, area, force)
    local behaviors = get_behaviors()

    for _, behavior in ipairs(behaviors) do
        local targets = behavior.find_tasks(surface, area, force)
        if targets and #targets > 0 then
            return true
        end
    end

    return false
end

--- Check if any executable tasks exist in an area (i.e., can_execute passes)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return boolean
function tasks.exist_executable_in_area(surface, area, force, inventory)
    local behaviors = get_behaviors()

    for _, behavior in ipairs(behaviors) do
        local targets = behavior.find_tasks(surface, area, force)
        if targets and #targets > 0 then
            for _, target in ipairs(targets) do
                if behavior.can_execute(target, inventory) then
                    return true
                end
            end
        end
    end

    return false
end

--- Execute a task
---@param spider_data table
---@param task table
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean success
function tasks.execute(spider_data, task, inventory, anchor_data)
    if not task then
        return false
    end

    local target = task.entity or task.tile
    if not target or not target.valid then
        return false
    end

    -- Resolve behavior from stored name (preferred) or fall back for compatibility
    local behavior

    if task.behavior_name then
        behavior = get_behavior_by_name(task.behavior_name)
    elseif task.behavior and task.behavior.name then
        -- Backwards compatibility with older saves that stored the behavior table
        behavior = task.behavior
    end

    if not behavior then
        return false
    end

    -- Double-check we can still execute
    if not behavior.can_execute(target, inventory) then
        return false
    end

    -- Execute the behavior
    local success = behavior.execute(spider_data, target, inventory, anchor_data)

    -- Clear assignment tracking regardless of success
    if task.id then
        storage.assigned_tasks[task.id] = nil
    end
    return success
end

--- Clean up stale task assignments
function tasks.cleanup_stale()
    for task_id, spider_id in pairs(storage.assigned_tasks) do
        local anchor_id = storage.spider_to_anchor[spider_id]
        local anchor_data = anchor_id and storage.anchors and storage.anchors[anchor_id] or nil
        local spider_data = anchor_data and anchor_data.spiders and anchor_data.spiders[spider_id] or nil

        -- Remove if spider doesn't exist or has different task
        if not spider_data or not spider_data.task or spider_data.task.id ~= task_id then
            storage.assigned_tasks[task_id] = nil
        end
    end
end

return tasks
