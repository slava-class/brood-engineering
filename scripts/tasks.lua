-- scripts/tasks.lua
-- Event-driven task queue and assignment logic for Brood Engineering

local tasks = {}

local behaviors_list = require("scripts/behaviors/init")
local behaviors_by_name = nil
local foundation_tiles = nil

local CHUNK_SIZE = 32

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

---@return table<string, boolean>
local function get_foundation_tiles()
    if not foundation_tiles then
        foundation_tiles = {}
        for name, tile in pairs(prototypes.tile) do
            if tile.is_foundation then
                foundation_tiles[name] = true
            end
        end
    end
    return foundation_tiles
end

---@param pos MapPosition
---@return integer cx
---@return integer cy
local function chunk_coords(pos)
    return math.floor(pos.x / CHUNK_SIZE), math.floor(pos.y / CHUNK_SIZE)
end

---@param cx integer
---@param cy integer
---@return string
local function chunk_key(cx, cy)
    return tostring(cx) .. ":" .. tostring(cy)
end

---@return table queue
local function ensure_queue()
    storage.task_queue = storage.task_queue or {}
    local queue = storage.task_queue
    queue.by_id = queue.by_id or {}
    queue.by_surface = queue.by_surface or {}
    queue.revision = queue.revision or 0
    return queue
end

---@param queue table
---@param surface_index uint32
---@return table
local function ensure_surface_queue(queue, surface_index)
    local surface_data = queue.by_surface[surface_index]
    if not surface_data then
        surface_data = { by_chunk = {} }
        queue.by_surface[surface_index] = surface_data
    end
    if not surface_data.by_chunk then
        surface_data.by_chunk = {}
    end
    return surface_data
end

---@param force LuaForce[]|LuaForce|string|nil
---@param task_force string|nil
---@return boolean
local function force_matches(force, task_force)
    if not task_force then
        return true
    end
    if type(force) == "table" and force.name then
        return force.name == task_force
    end
    if type(force) == "table" then
        for _, name in ipairs(force) do
            if name == task_force then
                return true
            end
        end
        return false
    end
    if type(force) == "string" then
        return force == task_force
    end
    return true
end

---@param target LuaEntity|LuaTile
---@return string|nil
local function target_kind(target)
    if not target then
        return nil
    end
    if target.object_name == "LuaEntity" then
        return "entity"
    end
    if target.object_name == "LuaTile" then
        return "tile"
    end
    return nil
end

---@param target LuaEntity|LuaTile
---@param opts { force_name?: string }?
---@return string|nil
local function resolve_force_name(target, opts)
    if opts and opts.force_name then
        return opts.force_name
    end
    local kind = target_kind(target)
    if kind == "entity" then
        return target.force and target.force.name or nil
    end
    return nil
end

---@param task table
---@return table
local function copy_task(task)
    return {
        id = task.id,
        entity = task.entity,
        tile = task.tile,
        behavior_name = task.behavior_name,
        priority = task.priority,
    }
end

---@param a BoundingBox
---@param b BoundingBox
---@return boolean
local function boxes_overlap(a, b)
    return a.left_top.x < b.right_bottom.x
        and a.right_bottom.x > b.left_top.x
        and a.left_top.y < b.right_bottom.y
        and a.right_bottom.y > b.left_top.y
end

---@param entity LuaEntity
---@param force ForceID|LuaForce|string|nil
---@return boolean
local function entity_blocks_any_ghost(entity, _force)
    if not (entity and entity.valid) then
        return false
    end

    local box = entity.bounding_box
    local ghosts = entity.surface.find_entities_filtered({
        area = box,
        type = "entity-ghost",
    })

    for _, ghost in ipairs(ghosts or {}) do
        if ghost and ghost.valid then
            local ghost_box = ghost.bounding_box
            if boxes_overlap(box, ghost_box) then
                return true
            end
        end
    end

    return false
end

---@param ghost LuaEntity
---@param force ForceID|LuaForce|string|nil
---@return LuaEntity[]
local function find_blocking_decon_entities_for_ghost(ghost, _force)
    if not (ghost and ghost.valid) then
        return {}
    end

    local surface = ghost.surface
    local box = ghost.bounding_box
    local decon_entities = surface.find_entities_filtered({
        area = box,
        to_be_deconstructed = true,
    })

    local blocking = {}
    for _, entity in ipairs(decon_entities or {}) do
        if entity and entity.valid and entity.type ~= "deconstructible-tile-proxy" then
            local entity_box = entity.bounding_box
            if boxes_overlap(entity_box, box) then
                blocking[#blocking + 1] = entity
            end
        end
    end

    return blocking
end

---@param task table
---@return boolean
local function is_task_active(task)
    if not task then
        return false
    end

    local target = task.entity or task.tile
    if not (target and target.valid) then
        return false
    end

    local name = task.behavior_name
    if name == "build_entity" then
        return target.object_name == "LuaEntity" and target.type == "entity-ghost"
    end
    if name == "build_tile" or name == "build_foundation" then
        return target.object_name == "LuaEntity" and target.type == "tile-ghost"
    end
    if name == "item_proxy" then
        return target.object_name == "LuaEntity" and target.type == "item-request-proxy"
    end
    if name == "deconstruct_entity" or name == "unblock_deconstruct" then
        if target.object_name ~= "LuaEntity" then
            return false
        end
        local ok, marked = pcall(function()
            return target.to_be_deconstructed()
        end)
        return ok and marked or false
    end
    if name == "upgrade" then
        if target.object_name ~= "LuaEntity" then
            return false
        end
        local ok, marked = pcall(function()
            return target.to_be_upgraded()
        end)
        return ok and marked or false
    end
    if name == "deconstruct_tile" then
        if target.object_name ~= "LuaTile" then
            return false
        end
        local ok, marked = pcall(function()
            return target.to_be_deconstructed()
        end)
        return ok and marked or false
    end

    return true
end

---@param surface_index uint32
---@param area BoundingBox
---@param cb fun(task: table): boolean? stop
---@return boolean
local function for_each_task_in_area(surface_index, area, cb)
    local queue = ensure_queue()
    local surface_data = queue.by_surface[surface_index]
    if not surface_data or not surface_data.by_chunk then
        return false
    end

    local min_x = math.min(area[1][1], area[2][1])
    local max_x = math.max(area[1][1], area[2][1])
    local min_y = math.min(area[1][2], area[2][2])
    local max_y = math.max(area[1][2], area[2][2])

    local min_cx, min_cy = chunk_coords({ x = min_x, y = min_y })
    local max_cx, max_cy = chunk_coords({ x = max_x, y = max_y })

    for cx = min_cx, max_cx do
        for cy = min_cy, max_cy do
            local bucket = surface_data.by_chunk[chunk_key(cx, cy)]
            if bucket then
                for task_id in pairs(bucket) do
                    local task = queue.by_id[task_id]
                    if task then
                        local pos = task.position
                        if
                            pos
                            and pos.x >= min_x
                            and pos.x <= max_x
                            and pos.y >= min_y
                            and pos.y <= max_y
                            and cb(task)
                        then
                            return true
                        end
                    else
                        bucket[task_id] = nil
                    end
                end
            end
        end
    end

    return false
end

--- Check if a task is already assigned
---@param task_id string
---@return boolean
function tasks.is_assigned(task_id)
    return storage.assigned_tasks[task_id] ~= nil
end

---@param behavior_name string
---@param target LuaEntity|LuaTile
---@param opts { force_name?: string }?
---@return boolean queued
function tasks.enqueue(behavior_name, target, opts)
    if not (target and target.valid) then
        return false
    end

    local behavior = get_behavior_by_name(behavior_name)
    if not behavior then
        return false
    end

    local task_id = behavior.get_task_id(target)
    local queue = ensure_queue()
    if queue.by_id[task_id] then
        return false
    end

    local pos = target.position
    if not pos then
        return false
    end

    local surface = target.surface
    local surface_index = surface and surface.index or nil
    if not surface_index then
        return false
    end

    local cx, cy = chunk_coords(pos)
    local key = chunk_key(cx, cy)

    local task = {
        id = task_id,
        behavior_name = behavior.name,
        entity = target.object_name == "LuaEntity" and target or nil,
        tile = target.object_name == "LuaTile" and target or nil,
        position = { x = pos.x, y = pos.y },
        surface_index = surface_index,
        chunk_key = key,
        priority = behavior.priority,
        force_name = resolve_force_name(target, opts),
    }

    queue.by_id[task_id] = task
    local surface_data = ensure_surface_queue(queue, surface_index)
    local bucket = surface_data.by_chunk[key]
    if not bucket then
        bucket = {}
        surface_data.by_chunk[key] = bucket
    end
    bucket[task_id] = true
    queue.revision = queue.revision + 1

    return true
end

---@param task_id string
---@return boolean removed
function tasks.remove(task_id)
    local queue = ensure_queue()
    local task = queue.by_id[task_id]
    if not task then
        return false
    end

    queue.by_id[task_id] = nil

    local surface_data = queue.by_surface[task.surface_index]
    if surface_data and surface_data.by_chunk then
        local bucket = surface_data.by_chunk[task.chunk_key]
        if bucket then
            bucket[task_id] = nil
            if next(bucket) == nil then
                surface_data.by_chunk[task.chunk_key] = nil
            end
        end
    end

    queue.revision = queue.revision + 1
    return true
end

---@param entity LuaEntity
function tasks.handle_built_entity(entity)
    if not (entity and entity.valid) then
        return
    end

    if entity.type == "entity-ghost" then
        tasks.enqueue("build_entity", entity)

        local force = entity.force or nil
        local blockers = find_blocking_decon_entities_for_ghost(entity, force)
        for _, blocker in ipairs(blockers) do
            tasks.enqueue("unblock_deconstruct", blocker)
        end
        return
    end

    if entity.type == "tile-ghost" then
        local foundations = get_foundation_tiles()
        local tile_name = entity.ghost_name
        if tile_name and foundations[tile_name] then
            tasks.enqueue("build_foundation", entity)
        else
            tasks.enqueue("build_tile", entity)
        end
        return
    end

    if entity.type == "item-request-proxy" then
        tasks.enqueue("item_proxy", entity)
    end
end

---@param entity LuaEntity
---@param player_index uint32?
function tasks.handle_marked_for_deconstruction(entity, player_index)
    if not (entity and entity.valid) then
        return
    end

    if entity.type == "deconstructible-tile-proxy" then
        local surface = entity.surface
        if surface then
            local tile = surface.get_tile(entity.position)
            if tile and tile.valid then
                tasks.enqueue("deconstruct_tile", tile, {
                    force_name = entity.force and entity.force.name or nil,
                })
            end
        end
        return
    end

    tasks.enqueue("deconstruct_entity", entity, {
        force_name = entity.force and entity.force.name or nil,
    })

    local force = entity.force
    if not force and player_index then
        local player = game.get_player(player_index)
        force = player and player.valid and player.force or nil
    end

    if entity_blocks_any_ghost(entity, force) then
        tasks.enqueue("unblock_deconstruct", entity, {
            force_name = entity.force and entity.force.name or nil,
        })
    end
end

---@param entity LuaEntity
function tasks.handle_cancelled_deconstruction(entity)
    if not (entity and entity.valid) then
        return
    end

    if entity.type == "deconstructible-tile-proxy" then
        local surface = entity.surface
        if surface then
            local tile = surface.get_tile(entity.position)
            if tile and tile.valid then
                local behavior = get_behavior_by_name("deconstruct_tile")
                if behavior then
                    tasks.remove(behavior.get_task_id(tile))
                end
            end
        end
        return
    end

    local behavior = get_behavior_by_name("deconstruct_entity")
    if behavior then
        tasks.remove(behavior.get_task_id(entity))
    end

    local unblock_behavior = get_behavior_by_name("unblock_deconstruct")
    if unblock_behavior then
        tasks.remove(unblock_behavior.get_task_id(entity))
    end
end

---@param entity LuaEntity
function tasks.handle_marked_for_upgrade(entity)
    if not (entity and entity.valid) then
        return
    end

    tasks.enqueue("upgrade", entity, {
        force_name = entity.force and entity.force.name or nil,
    })
end

---@param entity LuaEntity
function tasks.handle_cancelled_upgrade(entity)
    if not (entity and entity.valid) then
        return
    end

    local behavior = get_behavior_by_name("upgrade")
    if behavior then
        tasks.remove(behavior.get_task_id(entity))
    end
end

--- Enqueue item-request-proxy tasks in an area (event fallback).
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]|LuaForce|string|nil
---@return integer enqueued
function tasks.enqueue_item_proxies(surface, area, force)
    if not (surface and area) then
        return 0
    end

    local proxies = surface.find_entities_filtered({
        area = area,
        force = force,
        type = "item-request-proxy",
    })

    local count = 0
    for _, proxy in ipairs(proxies or {}) do
        if proxy and proxy.valid and tasks.enqueue("item_proxy", proxy) then
            count = count + 1
        end
    end

    return count
end

--- Find the best task for a spider in an area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table? task { id, entity/tile, behavior_name }
function tasks.find_best(surface, area, force, inventory)
    if not (surface and area) then
        return nil
    end

    local best_task = nil
    local best_priority = nil
    local ties = 0

    for_each_task_in_area(surface.index, area, function(task)
        if not force_matches(force, task.force_name) then
            return false
        end

        if not is_task_active(task) then
            tasks.remove(task.id)
            return false
        end

        if tasks.is_assigned(task.id) then
            return false
        end

        local behavior = get_behavior_by_name(task.behavior_name)
        if not behavior then
            tasks.remove(task.id)
            return false
        end

        local target = task.entity or task.tile
        if not behavior.can_execute(target, inventory) then
            return false
        end

        local priority = task.priority or behavior.priority or 0
        if best_priority == nil or priority < best_priority then
            best_priority = priority
            best_task = task
            ties = 1
        elseif priority == best_priority then
            ties = ties + 1
            if math.random(ties) == 1 then
                best_task = task
            end
        end

        return false
    end)

    return best_task and copy_task(best_task) or nil
end

--- Find all tasks in an area (for batch processing)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return table[] tasks
function tasks.find_all(surface, area, force, inventory)
    if not (surface and area) then
        return {}
    end

    local result = {}

    for_each_task_in_area(surface.index, area, function(task)
        if not force_matches(force, task.force_name) then
            return false
        end

        if not is_task_active(task) then
            tasks.remove(task.id)
            return false
        end

        if tasks.is_assigned(task.id) then
            return false
        end

        local behavior = get_behavior_by_name(task.behavior_name)
        if not behavior then
            tasks.remove(task.id)
            return false
        end

        local target = task.entity or task.tile
        if behavior.can_execute(target, inventory) then
            result[#result + 1] = copy_task(task)
        end
        return false
    end)

    table.sort(result, function(a, b)
        return (a.priority or 0) < (b.priority or 0)
    end)

    return result
end

--- Check if any tasks exist in an area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return boolean
function tasks.exist_in_area(surface, area, force)
    if not (surface and area) then
        return false
    end

    return for_each_task_in_area(surface.index, area, function(task)
        if not force_matches(force, task.force_name) then
            return false
        end

        if not is_task_active(task) then
            tasks.remove(task.id)
            return false
        end

        return true
    end)
end

--- Check if any executable tasks exist in an area (i.e., can_execute passes)
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@param inventory LuaInventory
---@return boolean
function tasks.exist_executable_in_area(surface, area, force, inventory)
    if not (surface and area) then
        return false
    end

    return for_each_task_in_area(surface.index, area, function(task)
        if not force_matches(force, task.force_name) then
            return false
        end

        if not is_task_active(task) then
            tasks.remove(task.id)
            return false
        end

        local behavior = get_behavior_by_name(task.behavior_name)
        if not behavior then
            tasks.remove(task.id)
            return false
        end

        local target = task.entity or task.tile
        return behavior.can_execute(target, inventory) or false
    end)
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

    local behavior

    if task.behavior_name then
        behavior = get_behavior_by_name(task.behavior_name)
    elseif task.behavior and task.behavior.name then
        behavior = task.behavior
    end

    if not behavior then
        return false
    end

    if not behavior.can_execute(target, inventory) then
        return false
    end

    local success = behavior.execute(spider_data, target, inventory, anchor_data)

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

--- Remove inactive tasks from the queue
function tasks.cleanup_invalid()
    local queue = ensure_queue()
    local stale = {}
    for task_id, task in pairs(queue.by_id) do
        if not is_task_active(task) then
            stale[#stale + 1] = task_id
        end
    end
    for _, task_id in ipairs(stale) do
        tasks.remove(task_id)
    end
end

return tasks
