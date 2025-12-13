-- scripts/behaviors/item_proxy.lua
-- Handle item-request-proxy entities (insert/remove items from machines)

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "item_proxy",
    priority = constants.priorities.item_proxy,
}

---@param id table?
---@return {name:string, quality:string}?
local function normalize_item_id(id)
    if not id then return nil end

    local name = id.name
    if type(name) == "table" then
        name = name.name
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local quality = id.quality
    if type(quality) == "table" then
        quality = quality.name
    end
    if type(quality) ~= "string" or quality == "" then
        quality = "normal"
    end

    return { name = name, quality = quality }
end

---@param items table?
---@return table[]
local function get_inventory_positions(items)
    if not items then return {} end
    if items.in_inventory then return items.in_inventory end
    if items[1] then return items end
    return {}
end

---@param stack LuaItemStack
---@return string
local function get_stack_quality(stack)
    local quality = stack and stack.quality or nil
    if type(quality) == "table" then
        quality = quality.name
    end
    if type(quality) ~= "string" or quality == "" then
        quality = "normal"
    end
    return quality
end

--- Find item-request-proxy entities
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    return surface.find_entities_filtered({
        area = area,
        force = force,
        type = "item-request-proxy",
    })
end

--- Check if we can handle this proxy
---@param proxy LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(proxy, inventory)
    if not proxy or not proxy.valid then return false end
    if not inventory or not inventory.valid then return false end

    -- Don't handle proxies for entities being upgraded
    local target = proxy.proxy_target
    if not target or not target.valid then return false end
    if target.to_be_upgraded() then return false end

    -- Check insert plan
    local insert_plan = proxy.insert_plan
    if insert_plan and insert_plan[1] then
        for _, plan in pairs(insert_plan) do
            local item = normalize_item_id(plan and plan.id)
            if item and utils.inventory_has_item(inventory, item) then
                return true
            end
        end
    end

    -- Check removal plan
    local removal_plan = proxy.removal_plan
    if removal_plan and removal_plan[1] then
        for _, plan in pairs(removal_plan) do
            local item = normalize_item_id(plan and plan.id)
            if item and utils.inventory_has_space(inventory, { name = item.name, count = 1, quality = item.quality }) then
                return true
            end
        end
    end

    return false
end

--- Handle the item proxy
---@param spider_data table
---@param proxy LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, proxy, inventory, anchor_data)
    if not proxy or not proxy.valid then return false end
    if not inventory or not inventory.valid then return false end

    local target = proxy.proxy_target
    if not target or not target.valid then return false end

    local did_something = false

    -- Handle removals first (to make space for inserts)
    local removal_plan = proxy.removal_plan
    if removal_plan then
        for _, plan in pairs(removal_plan) do
            local item = normalize_item_id(plan and plan.id)
            local items_to_remove = plan and plan.items or nil
            local positions = get_inventory_positions(items_to_remove)

            if item and positions and positions[1] then
                for _, slot in pairs(positions) do
                    if not slot or slot.inventory == nil or slot.stack == nil then
                        goto continue
                    end

                    ---@diagnostic disable-next-line: param-type-mismatch
                    local target_inv = target.get_inventory(slot.inventory)
                    if not (target_inv and target_inv.valid) then
                        goto continue
                    end

                    local stack_index = slot.stack + 1 -- InventoryPosition.stack is 0-based.
                    local stack = target_inv[stack_index]
                    if not (stack and stack.valid_for_read) then
                        goto continue
                    end

                    local stack_quality = get_stack_quality(stack)
                    if stack.name ~= item.name or stack_quality ~= item.quality then
                        goto continue
                    end

                    local requested = slot.count or 1
                    local to_move = math.min(requested, stack.count)
                    if to_move <= 0 then
                        goto continue
                    end

                    if not utils.inventory_has_space(inventory, { name = item.name, count = to_move, quality = item.quality }) then
                        goto continue
                    end

                    local moved = inventory.insert({ name = item.name, count = to_move, quality = item.quality })
                    if moved and moved > 0 then
                        stack.count = stack.count - moved
                        did_something = true
                    end

                    ::continue::
                end
            end
        end
    end

    -- Handle insertions
    local insert_plan = proxy.insert_plan
    if insert_plan then
        for _, plan in pairs(insert_plan) do
            local item = normalize_item_id(plan and plan.id)
            local items = plan and plan.items or nil
            local positions = get_inventory_positions(items)

            if item and positions and positions[1] then
                for _, slot in pairs(positions) do
                    if not slot or slot.inventory == nil or slot.stack == nil then
                        goto continue
                    end

                    local requested = slot.count or 1
                    if requested <= 0 then
                        goto continue
                    end

                    local available = inventory.get_item_count(item)
                    if available <= 0 then
                        goto continue
                    end

                    local to_insert = math.min(available, requested)
                    if to_insert <= 0 then
                        goto continue
                    end

                    ---@diagnostic disable-next-line: param-type-mismatch
                    local target_inv = target.get_inventory(slot.inventory)
                    if not (target_inv and target_inv.valid) then
                        goto continue
                    end

                    local stack_index = slot.stack + 1 -- InventoryPosition.stack is 0-based.
                    local target_stack = target_inv[stack_index]
                    if not target_stack then
                        goto continue
                    end

                    local inserted = 0
                    if target_stack.valid_for_read then
                        local stack_quality = get_stack_quality(target_stack)
                        if target_stack.name ~= item.name or stack_quality ~= item.quality then
                            goto continue
                        end

                        local stack_size = target_stack.prototype and target_stack.prototype.stack_size or 0
                        local free = stack_size - target_stack.count
                        if free > 0 then
                            inserted = math.min(to_insert, free)
                            target_stack.count = target_stack.count + inserted
                        end
                    else
                        local ok = target_stack.set_stack({ name = item.name, count = to_insert, quality = item.quality })
                        if ok then
                            inserted = to_insert
                        end
                    end

                    if inserted > 0 then
                        inventory.remove({ name = item.name, count = inserted, quality = item.quality })
                        did_something = true
                    end

                    ::continue::
                end
            end
        end
    end

    -- Check if proxy is satisfied (will auto-destroy if so)
    -- If we did something, consider it a success
    return did_something
end

--- Get unique ID for a proxy
---@param proxy LuaEntity
---@return string
function behavior.get_task_id(proxy)
    return "item_proxy_" .. utils.get_entity_id(proxy)
end

return behavior
