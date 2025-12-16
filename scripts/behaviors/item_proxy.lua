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
    if not id then
        return nil
    end

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
    if not items then
        return {}
    end
    if items.in_inventory then
        return items.in_inventory
    end
    if items[1] then
        return items
    end
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
    if not proxy or not proxy.valid then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    -- Don't handle proxies for entities being upgraded
    local target = proxy.proxy_target
    if not target or not target.valid then
        return false
    end
    if target.to_be_upgraded() then
        return false
    end

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
            if
                item and utils.inventory_has_space(inventory, { name = item.name, count = 1, quality = item.quality })
            then
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
    if not proxy or not proxy.valid then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    local target = proxy.proxy_target
    if not target or not target.valid then
        return false
    end

    local did_something = false

    -- Handle removals first (to make space for inserts)
    local removal_plan = proxy.removal_plan
    if removal_plan then
        for plan_index, plan in ipairs(removal_plan) do
            local item = normalize_item_id(plan and plan.id)
            local items_to_remove = plan and plan.items or nil
            local positions = get_inventory_positions(items_to_remove)

            -- Drop empty/stale plans.
            if not (positions and positions[1]) then
                table.remove(removal_plan, plan_index)
                proxy.removal_plan = removal_plan
                return true
            end

            if item then
                local slot = positions[1]
                if not slot or slot.inventory == nil or slot.stack == nil then
                    table.remove(positions, 1)
                    proxy.removal_plan = removal_plan
                    return true
                end

                local remaining = slot.count or 1
                if remaining <= 0 then
                    table.remove(positions, 1)
                    proxy.removal_plan = removal_plan
                    return true
                end

                ---@diagnostic disable-next-line: param-type-mismatch
                local target_inv = target.get_inventory(slot.inventory)
                if not (target_inv and target_inv.valid) then
                    return false
                end

                local stack_index = slot.stack + 1 -- InventoryPosition.stack is 0-based.
                local target_stack = target_inv[stack_index]
                if not target_stack then
                    return false
                end

                if not target_stack.valid_for_read then
                    -- Nothing to remove; clear this request entry so the proxy can resolve.
                    table.remove(positions, 1)
                    if not (positions and positions[1]) then
                        table.remove(removal_plan, plan_index)
                    end
                    proxy.removal_plan = removal_plan
                    return true
                end

                local stack_quality = get_stack_quality(target_stack)
                if target_stack.name ~= item.name or stack_quality ~= item.quality then
                    -- Don't remove unexpected items; leave the plan intact.
                    goto next_plan
                end

                if
                    not utils.inventory_has_space(inventory, { name = item.name, count = 1, quality = item.quality })
                then
                    return false
                end

                local moved = inventory.insert({ name = item.name, count = 1, quality = item.quality })
                if moved and moved > 0 then
                    target_stack.count = target_stack.count - moved
                    if target_stack.count <= 0 then
                        target_stack.clear()
                    end

                    remaining = remaining - moved
                    slot.count = remaining
                    if remaining <= 0 then
                        table.remove(positions, 1)
                    end
                    if not (positions and positions[1]) then
                        table.remove(removal_plan, plan_index)
                    end

                    proxy.removal_plan = removal_plan
                    did_something = true
                    break
                end
            end

            ::next_plan::
        end
    end

    -- Handle insertions
    local insert_plan = proxy.insert_plan
    if insert_plan then
        for plan_index, plan in ipairs(insert_plan) do
            local item = normalize_item_id(plan and plan.id)
            local items = plan and plan.items or nil
            local positions = get_inventory_positions(items)

            -- Drop empty/stale plans.
            if not (positions and positions[1]) then
                table.remove(insert_plan, plan_index)
                proxy.insert_plan = insert_plan
                return true
            end

            if item then
                local slot = positions[1]
                if not slot or slot.inventory == nil or slot.stack == nil then
                    table.remove(positions, 1)
                    proxy.insert_plan = insert_plan
                    return true
                end

                local remaining = slot.count or 1
                if remaining <= 0 then
                    table.remove(positions, 1)
                    proxy.insert_plan = insert_plan
                    return true
                end

                ---@diagnostic disable-next-line: param-type-mismatch
                local target_inv = target.get_inventory(slot.inventory)
                if not (target_inv and target_inv.valid) then
                    return false
                end

                local stack_index = slot.stack + 1 -- InventoryPosition.stack is 0-based.
                local target_stack = target_inv[stack_index]
                if not target_stack then
                    return false
                end

                if target_stack.valid_for_read then
                    local stack_quality = get_stack_quality(target_stack)
                    if target_stack.name == item.name and stack_quality == item.quality then
                        -- If the slot already contains enough of the requested item, treat it as satisfied
                        -- and clear the request without consuming more from the anchor.
                        local satisfied = math.min(remaining, target_stack.count)
                        remaining = remaining - satisfied
                        slot.count = remaining
                        if remaining <= 0 then
                            table.remove(positions, 1)
                            if not (positions and positions[1]) then
                                table.remove(insert_plan, plan_index)
                            end
                            proxy.insert_plan = insert_plan
                            return true
                        end
                    else
                        -- Wrong item in the requested slot; leave the plan intact.
                        goto next_insert_plan
                    end
                end

                if inventory.get_item_count(item) <= 0 then
                    goto next_insert_plan
                end

                local inserted = 0
                if target_stack.valid_for_read then
                    local stack_size = target_stack.prototype and target_stack.prototype.stack_size or 0
                    if stack_size <= 0 or target_stack.count >= stack_size then
                        goto next_insert_plan
                    end
                    target_stack.count = target_stack.count + 1
                    inserted = 1
                else
                    local ok = target_stack.set_stack({ name = item.name, count = 1, quality = item.quality })
                    if ok then
                        inserted = 1
                    end
                end

                if inserted > 0 then
                    inventory.remove({ name = item.name, count = inserted, quality = item.quality })
                    remaining = remaining - inserted
                    slot.count = remaining
                    if remaining <= 0 then
                        table.remove(positions, 1)
                    end
                    if not (positions and positions[1]) then
                        table.remove(insert_plan, plan_index)
                    end

                    proxy.insert_plan = insert_plan
                    did_something = true
                    break
                end
            end

            ::next_insert_plan::
        end
    end

    -- Check if proxy is satisfied (will auto-destroy if so)
    -- If we did something, consider it a success
    if did_something and proxy and proxy.valid then
        local requests = proxy.item_requests
        local has_requests = requests and next(requests) ~= nil
        local has_insert = insert_plan and insert_plan[1]
        local has_remove = removal_plan and removal_plan[1]
        if not has_requests and not has_insert and not has_remove then
            proxy.destroy({ raise_destroy = false })
        end
    end
    return did_something
end

--- Get unique ID for a proxy
---@param proxy LuaEntity
---@return string
function behavior.get_task_id(proxy)
    return "item_proxy_" .. utils.get_entity_id(proxy)
end

return behavior
