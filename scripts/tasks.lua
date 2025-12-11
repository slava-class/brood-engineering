-- scripts/tasks.lua
-- Task finding and assignment logic for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local tasks = {}

-- Behaviors are loaded lazily
local behaviors_list

--- Get behaviors list (lazy load)
---@return table[]
local function get_behaviors()
    if not behaviors_list then
        behaviors_list = require("scripts/behaviors/init")
    end
    return behaviors_list
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
---@return table? task { id, entity/tile, behavior }
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
                            behavior = behavior,
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
                            behavior = behavior,
                            priority = behavior.priority,
                        }
                    end
                end
            end
        end
    end
    
    -- Sort by priority
    table.sort(result, function(a, b) return a.priority < b.priority end)
    
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

--- Execute a task
---@param spider_data table
---@param task table
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean success
function tasks.execute(spider_data, task, inventory, anchor_data)
    if not task or not task.behavior then
        return false
    end
    
    local target = task.entity or task.tile
    if not target or not target.valid then
        return false
    end
    
    -- Double-check we can still execute
    if not task.behavior.can_execute(target, inventory) then
        return false
    end
    
    -- Execute the behavior
    local success = task.behavior.execute(spider_data, target, inventory, anchor_data)
    
    -- Clear assignment tracking regardless of success
    if task.id then
        storage.assigned_tasks[task.id] = nil
    end
    
    return success
end

--- Clean up stale task assignments
function tasks.cleanup_stale()
    local spider_module = require("scripts/spider")
    
    for task_id, spider_id in pairs(storage.assigned_tasks) do
        local spider_data = spider_module.get(spider_id)
        
        -- Remove if spider doesn't exist or has different task
        if not spider_data or not spider_data.task or spider_data.task.id ~= task_id then
            storage.assigned_tasks[task_id] = nil
        end
    end
end

return tasks
