-- scripts/behaviors/deconstruct_entity.lua
-- Deconstruct marked entities behavior

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "deconstruct_entity",
    priority = constants.priorities.deconstruct_entity,
}

---@param inventory LuaInventory
---@param stack LuaItemStack
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function insert_or_spill(inventory, stack, spill_surface, spill_position)
    if not (inventory and inventory.valid) then
        return
    end
    if not (stack and stack.valid_for_read) then
        return
    end

    local inserted = inventory.insert(stack)
    if inserted and inserted > 0 then
        stack.count = stack.count - inserted
    end

    if stack.valid_for_read and spill_surface and spill_position then
        local safe_stack = utils.safe_item_stack(stack)
        if safe_stack then
            utils.spill_item_stack(spill_surface, spill_position, safe_stack, {
                allow_belts = false,
                enable_looted = true,
                max_radius = 0,
            })
        end
        stack.clear()
    end
end

---@param from_inv LuaInventory
---@param to_inv LuaInventory
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function transfer_inventory(from_inv, to_inv, spill_surface, spill_position)
    if not (from_inv and from_inv.valid) then
        return
    end
    if not (to_inv and to_inv.valid) then
        return
    end

    for i = 1, #from_inv do
        local stack = from_inv[i]
        if stack and stack.valid_for_read then
            insert_or_spill(to_inv, stack, spill_surface, spill_position)
        end
    end
end

--- Find entities marked for deconstruction
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    local entities = surface.find_entities_filtered({
        area = area,
        force = force,
        to_be_deconstructed = true,
    })

    -- Tiles marked for deconstruction create hidden `deconstructible-tile-proxy` entities.
    -- Those must be handled by the tile behavior (mine_tile) so we don't double-count work
    -- and so we don't accidentally cancel the tile order by destroying the proxy.
    local result = {}
    for _, entity in ipairs(entities) do
        if entity and entity.valid and entity.type ~= "deconstructible-tile-proxy" then
            result[#result + 1] = entity
        end
    end
    return result
end

---@param quality any
---@return string
local function normalize_quality_name(quality)
    if type(quality) == "table" then
        return quality.name or "normal"
    end
    if type(quality) == "string" and quality ~= "" then
        return quality
    end
    return "normal"
end

---@param inventory LuaInventory
---@param item_entity LuaEntity
---@return boolean did_pick_up_any
local function pick_up_item_entity(inventory, item_entity)
    if not (inventory and inventory.valid) then
        return false
    end
    if not (item_entity and item_entity.valid and item_entity.type == "item-entity") then
        return false
    end

    local stack = item_entity.stack
    if not (stack and stack.valid_for_read) then
        return false
    end

    local inserted = inventory.insert(stack)
    if not (inserted and inserted > 0) then
        return false
    end

    if inserted >= stack.count then
        item_entity.destroy({ raise_destroy = true })
    else
        stack.count = stack.count - inserted
    end

    return true
end

---@param surface LuaSurface
---@param area BoundingBox
---@return LuaEntity[]
local function find_item_entities(surface, area)
    local ok, entities = pcall(function()
        return surface.find_entities_filtered({
            area = area,
            type = "item-entity",
        })
    end)
    if not ok or not entities then
        return {}
    end
    return entities
end

---@param inventory LuaInventory
---@param surface LuaSurface
---@param area BoundingBox
local function sweep_spills(inventory, surface, area)
    if not (inventory and inventory.valid) then
        return
    end
    if not (surface and (surface.valid == nil or surface.valid)) then
        return
    end

    local drops = find_item_entities(surface, area)
    for _, drop in ipairs(drops) do
        pick_up_item_entity(inventory, drop)
    end
end

--- Get item products that would be returned when mining an entity
---@param entity LuaEntity
---@return Prototype.mineable_properties.products?
local function get_mine_products(entity)
    local prototype = entity.prototype
    local mineable = prototype and prototype.mineable_properties
    return mineable and mineable.products or nil
end

---@param product PrototypeProduct
---@return integer count
local function product_count_for_can_insert(product)
    local count = product and product.amount or nil
    if not count then
        count = product and (product.amount_max or product.amount_min) or nil
    end
    if not count or count < 1 then
        count = 1
    end
    return count
end

---@param product PrototypeProduct
---@return integer count
local function product_count_for_insert(product)
    local count = product and product.amount or nil
    if not count then
        count = product and product.amount_min or nil
    end
    if not count or count < 1 then
        count = product and product.amount_max or nil
    end
    if not count or count < 1 then
        count = 1
    end
    return count
end

---@param entity LuaEntity
---@return { name: string, count: integer }[]?
local function mineable_item_products_for_can_insert(entity)
    local products = get_mine_products(entity)
    if not products then
        return nil
    end
    local result = {}
    for _, product in pairs(products) do
        if product and product.type == "item" and product.name then
            result[#result + 1] = { name = product.name, count = product_count_for_can_insert(product) }
        end
    end
    return result
end

---@param entity LuaEntity
---@return { name: string, count: integer }[]?
local function mineable_item_products_for_insert(entity)
    local products = get_mine_products(entity)
    if not products then
        return nil
    end
    local result = {}
    for _, product in pairs(products) do
        if product and product.type == "item" and product.name then
            result[#result + 1] = { name = product.name, count = product_count_for_insert(product) }
        end
    end
    return result
end

---@param inventory LuaInventory
---@param name string
---@param count number
---@param quality_name string
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function insert_name_count(inventory, name, count, quality_name, spill_surface, spill_position)
    if not (inventory and inventory.valid) then
        return
    end
    if not (name and name ~= "" and count and count > 0) then
        return
    end

    local stack = { name = name, count = count }
    if quality_name and quality_name ~= "normal" then
        stack.quality = quality_name
    end

    local inserted = inventory.insert(stack)
    local remaining = count - (inserted or 0)
    if remaining <= 0 then
        return
    end

    if spill_surface and spill_position then
        local spilled = { name = name, count = remaining }
        if quality_name and quality_name ~= "normal" then
            spilled.quality = quality_name
        end
        utils.spill_item_stack(spill_surface, spill_position, spilled, {
            allow_belts = false,
            enable_looted = true,
            max_radius = 0,
        })
    end
end

---@param entity LuaEntity
---@param inventory LuaInventory
---@param quality_name string
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function insert_mined_products(entity, inventory, quality_name, spill_surface, spill_position)
    local products = mineable_item_products_for_insert(entity)
    if products and #products > 0 then
        for _, product in ipairs(products) do
            insert_name_count(inventory, product.name, product.count, quality_name, spill_surface, spill_position)
        end
        return
    end

    local prototype = entity.prototype
    local items_to_place = prototype and prototype.items_to_place_this or nil
    if items_to_place and #items_to_place > 0 then
        local it = items_to_place[1]
        if it and it.name then
            insert_name_count(inventory, it.name, it.count or 1, quality_name, spill_surface, spill_position)
        end
        return
    end

    -- Last resort: many entities have an item with the same name.
    insert_name_count(inventory, entity.name, 1, quality_name, spill_surface, spill_position)
end

---@param entity LuaEntity
---@param inventory LuaInventory
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function insert_transport_line_contents(entity, inventory, spill_surface, spill_position)
    if not (entity and entity.valid) then
        return
    end
    if not (inventory and inventory.valid) then
        return
    end
    if not entity.get_transport_line then
        return
    end

    for line_index = 1, 4 do
        local ok_line, line = pcall(function()
            return entity.get_transport_line(line_index)
        end)
        if ok_line and line and line.valid and line.get_contents then
            local ok_contents, contents = pcall(function()
                return line.get_contents()
            end)
            if ok_contents and contents then
                for _, entry in ipairs(contents) do
                    if entry and entry.name and entry.count and entry.count > 0 then
                        insert_name_count(
                            inventory,
                            entry.name,
                            entry.count,
                            entry.quality or "normal",
                            spill_surface,
                            spill_position
                        )
                    end
                end
            end
            pcall(function()
                if line.clear then
                    line.clear()
                end
            end)
        end
    end
end

---@param entity LuaEntity
---@param to_inv LuaInventory
---@param spill_surface LuaSurface?
---@param spill_position MapPosition?
local function transfer_all_entity_inventories(entity, to_inv, spill_surface, spill_position)
    if not (entity and entity.valid) then
        return
    end
    if not (to_inv and to_inv.valid) then
        return
    end

    for _, inv_id in pairs(defines.inventory) do
        if type(inv_id) == "number" then
            local ok, inv = pcall(function()
                return entity.get_inventory(inv_id)
            end)
            if ok and inv and inv.valid then
                transfer_inventory(inv, to_inv, spill_surface, spill_position)
            end
        end
    end
end

--- Check if we can deconstruct this entity (have space for results)
---@param entity LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(entity, inventory)
    if not entity or not entity.valid then
        return false
    end
    if not entity.to_be_deconstructed() then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end
    if entity.type == "deconstructible-tile-proxy" then
        return false
    end

    -- Cliffs need explosives
    if entity.type == "cliff" then
        -- Check for cliff explosives of any quality.
        -- `prototypes.quality` is a `LuaCustomTable<string, LuaQualityPrototype>` keyed by name.
        -- Docs: `mise run docs -- open runtime/classes/LuaPrototypes.md#quality`
        for quality_name, _ in pairs(prototypes.quality) do
            local item = { name = "cliff-explosives", quality = quality_name }
            if utils.inventory_has_item(inventory, item) then
                return true
            end
        end
        return false
    end

    -- Item-on-ground: make sure we can at least insert one item.
    if entity.type == "item-entity" then
        local stack = entity.stack
        return stack and stack.valid_for_read and inventory.can_insert(stack) or false
    end

    -- Check space for mined products (best-effort; mining may still spill extras).
    local quality_name = normalize_quality_name(entity.quality)
    local products = mineable_item_products_for_can_insert(entity)
    if products and #products > 0 then
        for _, product in ipairs(products) do
            local stack = { name = product.name, count = product.count, quality = quality_name }
            if not inventory.can_insert(stack) then
                return false
            end
        end
        return true
    end

    local prototype = entity.prototype
    local items_to_place = prototype and prototype.items_to_place_this or nil
    if items_to_place and #items_to_place > 0 then
        local it = items_to_place[1]
        if it and it.name then
            local count = it.count or 1
            if not count or count < 1 then
                count = 1
            end
            local stack = { name = it.name, count = count, quality = quality_name }
            return inventory.can_insert(stack)
        end
    end

    return true
end

--- Deconstruct the entity
---@param spider_data table
---@param entity LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, entity, inventory, anchor_data)
    if not entity or not entity.valid then
        return false
    end
    if not entity.to_be_deconstructed() then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end
    if entity.type == "deconstructible-tile-proxy" then
        return false
    end

    -- Handle cliffs specially
    if entity.type == "cliff" then
        -- Find and consume cliff explosives
        for quality_name, _ in pairs(prototypes.quality) do
            local item = { name = "cliff-explosives", quality = quality_name }
            if utils.inventory_has_item(inventory, item) then
                inventory.remove({ name = "cliff-explosives", count = 1, quality = quality_name })
                entity.destroy({ raise_destroy = true })
                return true
            end
        end
        return false
    end

    -- Handle item-on-ground (picking up items)
    if entity.type == "item-entity" then
        return pick_up_item_entity(inventory, entity)
    end

    -- Two explicit mining paths:
    -- 1) If the anchor is a LuaControl (character/player/vehicle), prefer `LuaControl.mine_entity` for engine-accurate mining.
    -- 2) Otherwise (e.g., container anchors/tests), deterministically emulate mining by transferring inventories/transport-lines,
    --    inserting mined products, and destroying the entity.
    --
    -- Docs: `mise run docs -- open runtime:method:LuaControl.mine_entity`
    -- Docs: `mise run docs -- open runtime:attribute:LuaEntityPrototype.items_to_place_this`
    local surface = entity.surface
    local box = entity.bounding_box
    local area
    if box and box.left_top and box.right_bottom then
        area = {
            { box.left_top.x - 1.5, box.left_top.y - 1.5 },
            { box.right_bottom.x + 1.5, box.right_bottom.y + 1.5 },
        }
    else
        local pos = entity.position
        area = { { pos.x - 2, pos.y - 2 }, { pos.x + 2, pos.y + 2 } }
    end

    local spill_surface = surface
    local spill_position = nil
    if anchor_data and anchor_data.entity and anchor_data.entity.valid then
        spill_position = anchor_data.entity.position
    elseif entity and entity.valid then
        spill_position = entity.position
    end

    local quality_name = normalize_quality_name(entity.quality)

    local control = nil
    if anchor_data and anchor_data.entity and anchor_data.entity.valid and anchor_data.entity.mine_entity then
        control = anchor_data.entity
    elseif anchor_data and anchor_data.player_index then
        local player = game and game.get_player(anchor_data.player_index)
        if player and player.valid and player.mine_entity then
            control = player
        end
    end

    if control then
        local ok, mined = pcall(function()
            return control.mine_entity(entity, true)
        end)
        if ok and mined == true then
            if surface and area then
                sweep_spills(inventory, surface, area)
            end
            return not (entity and entity.valid)
        end
    end

    -- Deterministic fallback (container/test anchors).
    if surface and area then
        sweep_spills(inventory, surface, area)
    end
    insert_transport_line_contents(entity, inventory, spill_surface, spill_position)
    transfer_all_entity_inventories(entity, inventory, spill_surface, spill_position)
    insert_mined_products(entity, inventory, quality_name, spill_surface, spill_position)
    entity.destroy({ raise_destroy = true })

    return not (entity and entity.valid)
end

--- Get unique ID for an entity
---@param entity LuaEntity
---@return string
function behavior.get_task_id(entity)
    return "deconstruct_entity_" .. utils.get_entity_id(entity)
end

return behavior
