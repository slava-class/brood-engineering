-- scripts/behaviors/deconstruct_tile.lua
-- Remove tiles marked for deconstruction

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "deconstruct_tile",
    priority = constants.priorities.deconstruct_tile,
}

local function debug_enabled()
    return settings
        and settings.global
        and settings.global["brood-debug-logging"]
        and settings.global["brood-debug-logging"].value
end

---@param msg string
local function dlog(msg)
    if not debug_enabled() then return end
    local tick = (game and game.tick) or -1
    utils.log(string.format("[TileDecon][t=%d] %s", tick, msg))
end

---@param anchor_data table?
---@param msg string
local function dprint(anchor_data, msg)
    if not debug_enabled() then return end
    local player_index = anchor_data and anchor_data.player_index
    if not player_index then return end
    local player = game and game.get_player(player_index)
    if player and player.valid then
        player.print("[Brood][TileDecon] " .. msg)
    end
end

---@param value any
---@return string
local function serialize(value)
    if serpent and serpent.line then
        local ok, out = pcall(serpent.line, value, { comment = false, nocode = true })
        if ok and out then return out end
    end
    return tostring(value)
end

local function is_marked(tile)
    if not tile or not tile.valid then return false end
    if not tile.to_be_deconstructed then return false end
    -- Factorio binds LuaObject methods, so the common call form is `tile.to_be_deconstructed()`.
    -- Some environments may still require passing `tile` as the first arg; support both.
    local ok, marked = pcall(tile.to_be_deconstructed)
    if not ok then
        ok, marked = pcall(tile.to_be_deconstructed, tile)
    end
    if not ok then
        dlog("is_marked pcall failed: " .. tostring(marked))
        return false
    end
    return marked or false
end

--- Find tiles marked for deconstruction
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaTile[]
function behavior.find_tasks(surface, area, force)
    -- Align with the proven working approach: use find_tiles_filtered with
    -- both `force` and `to_be_deconstructed` so the engine does the heavy lifting.
    -- Note: for tiles, `force` refers to the ordering force (who marked it),
    -- not the tile's "own" force; match spiderbots by using the primary force.
    local tile_force = force
    if type(tile_force) == "table" then
        tile_force = tile_force[1]
    end
    local ok, tiles_or_err = pcall(surface.find_tiles_filtered, {
        area = area,
        force = tile_force,
        to_be_deconstructed = true,
    })
    local tiles = (ok and tiles_or_err) or {}
    if not ok then
        dlog("find_tiles_filtered errored (force+flag): " .. tostring(tiles_or_err))
    end

    -- Some versions appear to require `force` for to_be_deconstructed, others ignore it.
    -- If we got nothing, try a couple of fallbacks.
    if #tiles == 0 then
        local ok2, tiles2_or_err = pcall(surface.find_tiles_filtered, {
            area = area,
            to_be_deconstructed = true,
        })
        if ok2 and tiles2_or_err then
            tiles = tiles2_or_err
        elseif not ok2 then
            dlog("find_tiles_filtered errored (flag-only): " .. tostring(tiles2_or_err))
        end
    end

    local result = {}
    for _, tile in pairs(tiles) do
        if is_marked(tile) then
            result[#result + 1] = tile
        end
    end

    if debug_enabled() and game and #result > 0 then
        storage._brood_debug = storage._brood_debug or {}
        local last = storage._brood_debug.tile_find_log_tick or -100000
        if (game.tick - last) >= 60 then
            storage._brood_debug.tile_find_log_tick = game.tick
            local sample = {}
            local sample_limit = math.min(#result, 12)
            for i = 1, sample_limit do
                local t = result[i]
                sample[#sample + 1] = string.format(
                    "%s(%s@%.0f,%.0f)",
                    utils.get_tile_key(t),
                    t.name,
                    t.position.x,
                    t.position.y
                )
            end
            dlog(string.format(
                "find_tasks found %d deconstruct-marked tiles: %s",
                #result,
                table.concat(sample, ", ")
            ))
        end
    end
    return result
end

---@param tile LuaTile
---@return Prototype.mineable_properties.products?
local function get_tile_products(tile)
    local tile_proto = tile and tile.valid and tile.prototype
    local mineable = tile_proto and tile_proto.mineable_properties
    return mineable and mineable.products or nil
end

---@param products Prototype.mineable_properties.products?
---@return table<string, integer>
local function get_expected_min_counts(products)
    local expected = {}
    if not products then return expected end
    for _, product in pairs(products) do
        if product.type == "item" then
            local count = product.amount or product.amount_min or product.amount_max or 1
            expected[product.name] = (expected[product.name] or 0) + count
        end
    end
    return expected
end

---@param expected table<string, integer>
---@return string
local function format_expected(expected)
    local parts = {}
    for name, count in pairs(expected) do
        parts[#parts + 1] = string.format("%sx%d", name, count)
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

---@param surface LuaSurface
---@param position MapPosition
---@param want table<string, integer>
---@return LuaEntity[]
local function find_item_drops(surface, position, want)
    local ok, drops = pcall(surface.find_entities_filtered, {
        area = {
            { position.x - 0.9, position.y - 0.9 },
            { position.x + 0.9, position.y + 0.9 },
        },
        type = "item-entity",
    })
    if not ok or not drops then return {} end

    local filtered = {}
    for _, e in pairs(drops) do
        local stack = e and e.valid and e.stack
        if stack and stack.valid_for_read and want[stack.name] then
            filtered[#filtered + 1] = e
        end
    end
    return filtered
end

---@param inventory LuaInventory
---@param drops LuaEntity[]
---@param want table<string, integer>
---@return table<string, integer> moved
local function sweep_drops_into_inventory(inventory, drops, want)
    local moved = {}
    if not (inventory and inventory.valid) then return moved end
    if not drops or #drops == 0 then return moved end

    for _, drop in ipairs(drops) do
        if utils.is_empty(want) then break end
        if not (drop and drop.valid) then goto next_drop end
        local stack = drop.stack
        if not (stack and stack.valid_for_read) then goto next_drop end

        local need = want[stack.name] or 0
        if need <= 0 then goto next_drop end

        local take = math.min(need, stack.count)
        local quality = stack.quality
        local quality_name = type(quality) == "table" and quality.name or quality
        local inserted = inventory.insert({ name = stack.name, count = take, quality = quality_name })
        if inserted > 0 then
            moved[stack.name] = (moved[stack.name] or 0) + inserted
            want[stack.name] = need - inserted
            if want[stack.name] <= 0 then
                want[stack.name] = nil
            end

            if inserted >= stack.count then
                drop.destroy({ raise_destroy = true })
            else
                stack.count = stack.count - inserted
            end
        end

        ::next_drop::
    end

    return moved
end

--- Check if we can deconstruct this tile
---@param tile LuaTile
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(tile, inventory)
    if not tile or not tile.valid then return false end
    if not inventory or not inventory.valid then return false end
    if not is_marked(tile) then return false end
    
    -- Check space for result
    local products = get_tile_products(tile)
    if products then
        for _, product in pairs(products) do
            if product.type == "item" then
                local count = product.amount or product.amount_max or product.amount_min or 1
                local stack = { name = product.name, count = count }
                if not utils.inventory_has_space(inventory, stack) then
                    dlog(string.format(
                        "can_execute: no space for %s (tile=%s at %.0f,%.0f)",
                        serialize(stack),
                        tile.name,
                        tile.position.x,
                        tile.position.y
                    ))
                    return false
                end
            end
        end
    end

    return true
end

--- Deconstruct the tile
---@param spider_data table
---@param tile LuaTile
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, tile, inventory, anchor_data)
    if not tile or not tile.valid then return false end
    if not inventory or not inventory.valid then return false end

    -- Always operate on the current tile instance at this position (LuaTile objects
    -- can become invalid if the tile changes).
    local surface = tile.surface
    local position = tile.position
    tile = (surface and (surface.valid == nil or surface.valid) and surface.get_tile(position)) or tile

    if not behavior.can_execute(tile, inventory) then return false end

    local before_name = tile.name
    local before_hidden = tile.hidden_tile

    -- Align with the confirmed working code: mine via the anchor/player entity,
    -- not the spiderling entity.
    local anchor_entity = anchor_data and anchor_data.entity or nil
    if not (anchor_entity and anchor_entity.valid and anchor_entity.mine_tile) then
        dlog(string.format(
            "execute: no valid anchor mine_tile (tile=%s at %.0f,%.0f anchor=%s)",
            tile.name,
            tile.position.x,
            tile.position.y,
            anchor_entity and (anchor_entity.name .. ":" .. (anchor_entity.type or "?")) or "nil"
        ))
        return false
    end

    local products = get_tile_products(tile)
    local expected = get_expected_min_counts(products)
    local before_counts = {}
    for name, _ in pairs(expected) do
        before_counts[name] = inventory.get_item_count(name)
    end

    if debug_enabled() then
        local spider_entity = spider_data and spider_data.entity or nil
        local spider_pos = spider_entity and spider_entity.valid and spider_entity.position or nil
        local dist_spider = spider_pos and utils.distance(spider_pos, tile.position) or -1
        local dist_anchor = utils.distance(anchor_entity.position, tile.position)
        dlog(string.format(
            "execute: spider=%s dist_spider=%.2f dist_anchor=%.2f anchor=%s:%s tile=%s key=%s expected=%s",
            spider_data and tostring(spider_data.entity_id) or "nil",
            dist_spider,
            dist_anchor,
            anchor_entity.name,
            anchor_entity.type or "?",
            tile.name,
            utils.get_tile_key(tile),
            format_expected(expected)
        ))
        if products then
            dlog("execute: raw products=" .. serialize(products))
        end
    end

    -- Factorio binds LuaObject methods, so the common call form is `anchor_entity.mine_tile(tile)`.
    local ok, success = pcall(anchor_entity.mine_tile, tile)
    if not ok then
        -- Backwards-compatibility: some environments might expect the entity as the first arg.
        ok, success = pcall(anchor_entity.mine_tile, anchor_entity, tile)
    end
    if not ok then
        dlog("execute: mine_tile pcall failed: " .. tostring(success))
        dprint(anchor_data, "mine_tile errored; check factorio-current.log for [TileDecon]")
        return false
    end

    if success then
        local after_tile = (surface and (surface.valid == nil or surface.valid) and surface.get_tile(position)) or nil
        if debug_enabled() then
            dlog(string.format(
                "execute: mine_tile ok=true success=true after_tile=%s",
                after_tile and after_tile.valid and after_tile.name or "nil"
            ))
        end

        local missing = {}
        for name, expected_count in pairs(expected) do
            local after = inventory.get_item_count(name)
            local delta = after - (before_counts[name] or 0)
            if delta < expected_count then
                missing[name] = expected_count - delta
            end
        end

        if not utils.is_empty(missing) and surface then
            if debug_enabled() then
                dlog("execute: inventory missing after mine_tile=" .. serialize(missing))
            end

            local want = {}
            for name, count in pairs(missing) do
                want[name] = count
            end

            local drops = find_item_drops(surface, position, want)
            if debug_enabled() and #drops > 0 then
                local drop_summary = {}
                for _, drop in ipairs(drops) do
                    local stack = drop and drop.valid and drop.stack
                    if stack and stack.valid_for_read then
                        local q = stack.quality
                        local qn = type(q) == "table" and q.name or q
                        drop_summary[#drop_summary + 1] = string.format("%sx%d[%s]", stack.name, stack.count, tostring(qn or "normal"))
                    end
                end
                table.sort(drop_summary)
                dlog("execute: drops near tile=" .. table.concat(drop_summary, ", "))
            end

            local moved = sweep_drops_into_inventory(inventory, drops, want)
            if debug_enabled() and (not utils.is_empty(moved)) then
                dlog("execute: swept drops into inventory=" .. serialize(moved))
            end

            if debug_enabled() and (not utils.is_empty(want)) then
                dlog("execute: still missing after sweep=" .. serialize(want))
            end

            if debug_enabled() then
                dprint(anchor_data, "tile mined but products spilled; see factorio-current.log ([TileDecon])")
            end
        end

        if after_tile and after_tile.valid and after_tile.name ~= before_name then
            -- Optional UI cleanup for player anchors (mirrors the working mod).
            if anchor_data and anchor_data.player_index then
                local player = game.get_player(anchor_data.player_index)
                if player and player.valid and player.clear_local_flying_texts then
                    local ok_clear = pcall(player.clear_local_flying_texts)
                    if not ok_clear then
                        pcall(player.clear_local_flying_texts, player)
                    end
                end
            end
            return true
        end
    else
        dlog("execute: mine_tile returned false")
    end

    -- Fallback: some entity types/contexts appear to clear the deconstruction mark
    -- without actually changing the tile. In that case, restore the hidden tile
    -- and grant the mined products manually.
    local replacement = before_hidden or (tile.prototype and tile.prototype.hidden_tile) or nil
    if not replacement or replacement == before_name then
        dlog(string.format(
            "fallback: no replacement tile (before=%s hidden=%s proto_hidden=%s)",
            tostring(before_name),
            tostring(before_hidden),
            tostring(tile.prototype and tile.prototype.hidden_tile)
        ))
        return false
    end

    local replaced = false
    pcall(function()
        if surface and (surface.valid == nil or surface.valid) then
            surface.set_tiles({ { name = replacement, position = position } }, true)
            local after_tile = surface.get_tile(position)
            replaced = (after_tile and after_tile.valid and after_tile.name == replacement) or false
        end
    end)

    if not replaced then
        dlog("fallback: set_tiles did not replace tile to " .. tostring(replacement))
        return false
    end

    if products then
        for _, product in pairs(products) do
            if product.type == "item" then
                local count = product.amount or product.amount_min or product.amount_max or 1
                if product.amount_min and product.amount_max then
                    count = math.random(product.amount_min, product.amount_max)
                end
                if product.probability and math.random() > product.probability then
                    goto continue_product
                end
                local inserted = inventory.insert({ name = product.name, count = count })
                if debug_enabled() and inserted < count then
                    dlog(string.format(
                        "fallback: inventory.insert short (item=%s want=%d inserted=%d)",
                        product.name,
                        count,
                        inserted
                    ))
                end
            end
            ::continue_product::
        end
    end

    -- Optional UI cleanup for player anchors (mirrors the working mod).
    if anchor_data and anchor_data.player_index then
        local player = game.get_player(anchor_data.player_index)
        if player and player.valid and player.clear_local_flying_texts then
            local ok_clear = pcall(player.clear_local_flying_texts)
            if not ok_clear then
                pcall(player.clear_local_flying_texts, player)
            end
        end
    end

    return true
end

--- Get unique ID for a tile
---@param tile LuaTile
---@return string
function behavior.get_task_id(tile)
    return utils.get_tile_key(tile)
end

return behavior
