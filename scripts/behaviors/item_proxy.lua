-- scripts/behaviors/item_proxy.lua
-- Handle item-request-proxy entities (insert/remove items from machines)

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "item_proxy",
    priority = constants.priorities.item_proxy,
}

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
            local item = plan.id
            if item and utils.inventory_has_item(inventory, item.name) then
                return true
            end
        end
    end

    -- Check removal plan
    local removal_plan = proxy.removal_plan
    if removal_plan and removal_plan[1] then
        for _, plan in pairs(removal_plan) do
            local item = plan.id
            if item and utils.inventory_has_space(inventory, item.name) then
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
            local item = plan.id.name
            local items_to_remove = plan.items

            if item and items_to_remove and utils.inventory_has_space(inventory, item) then
                -- Find the item in the target's inventories
                for i = 1, 11 do
                    ---@diagnostic disable-next-line: param-type-mismatch
                    local target_inv = target.get_inventory(i)

                    if target_inv and target_inv.valid then
                        for _, slot in pairs(items_to_remove) do
                            local stack = target_inv[slot.stack]
                            if stack and stack.valid_for_read then
                                local removed = inventory.insert(stack)
                                if removed > 0 then
                                    stack.count = stack.count - removed
                                    did_something = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Handle insertions
    local insert_plan = proxy.insert_plan
    if insert_plan then
        for _, plan in pairs(insert_plan) do
            local item = plan.id
            local items = plan.items
            local count = items and #items or 0

            if item and count > 0 then
                local item_name = type(item.name) == "string" and item.name or item.name
                local quality = item.quality
                if type(quality) == "table" then
                    quality = quality.name
                end
                quality = quality or "normal"

                local available = inventory.get_item_count({ name = item_name, quality = quality })
                local to_insert = math.min(available, count)

                if to_insert > 0 then
                    -- Try to insert into target
                    local inserted = target.insert({ name = item_name, count = to_insert, quality = quality })
                    if inserted > 0 then
                        inventory.remove({ name = item_name, count = inserted, quality = quality })
                        did_something = true
                    end
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
