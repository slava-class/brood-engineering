local M = {}
local test_utils = require("tests/test_utils")

M.report = test_utils.report

---@class BlueprintProgressLineOpts
---@field prefix string?
---@field phase string
---@field idx integer?
---@field surface LuaSurface
---@field area BoundingBox
---@field force LuaForce
---@field anchor_id string
---@field anchor_entity LuaEntity?
---@field spider_ids string[]?

---@param opts BlueprintProgressLineOpts
---@return string?
function M.progress_line(opts)
    if not (opts and opts.surface and opts.area and opts.force and opts.anchor_id) then
        return nil
    end

    local prefix = opts.prefix or "[Brood][BlueprintCycle]"

    local entity_ghosts = opts.surface.find_entities_filtered({
        area = opts.area,
        type = "entity-ghost",
        force = opts.force,
    })
    local tile_ghosts = opts.surface.find_entities_filtered({
        area = opts.area,
        type = "tile-ghost",
        force = opts.force,
    })

    local ad = storage.anchors and storage.anchors[opts.anchor_id] or nil

    local ad_spider_count = 0
    if ad and ad.spiders then
        for _ in pairs(ad.spiders) do
            ad_spider_count = ad_spider_count + 1
        end
    end

    local status = {}
    for _, sid in ipairs(opts.spider_ids or {}) do
        local sd = ad and ad.spiders and ad.spiders[sid] or nil
        status[#status + 1] = ("%s=%s"):format(tostring(sid), sd and sd.status or "nil")
    end

    local idx_part = ""
    if opts.idx ~= nil then
        idx_part = (" idx=%d"):format(tonumber(opts.idx) or 0)
    end

    return ("%s phase=%s%s anchor_valid=%s anchor_in_storage=%s spider_count=%d ghosts=%d tile_ghosts=%d spiders={%s}"):format(
        tostring(prefix),
        tostring(opts.phase),
        idx_part,
        tostring(opts.anchor_entity and opts.anchor_entity.valid),
        tostring(ad ~= nil),
        ad_spider_count,
        #(entity_ghosts or {}),
        #(tile_ghosts or {}),
        table.concat(status, ",")
    )
end

---@param item LuaItemStack
---@param max_depth integer
---@return { stack: LuaItemStack, path: string }[] blueprints
function M.collect_blueprints(item, max_depth)
    local result = {}

    local function visit(it, depth, path)
        if not (it and it.valid_for_read) then
            return
        end
        if depth > max_depth then
            return
        end

        if it.is_blueprint == true then
            result[#result + 1] = { stack = it, path = path or "" }
            return
        end

        if it.is_blueprint_book == true then
            local inv = it.get_inventory(defines.inventory.item_main)
            if not (inv and inv.valid) then
                return
            end
            for i = 1, #inv do
                local next_path = path and (path .. "/" .. tostring(i)) or tostring(i)
                visit(inv[i], depth + 1, next_path)
            end
        end
    end

    local initial_path = ""
    if item and item.valid_for_read and item.is_blueprint_book == true then
        initial_path = nil
    end
    visit(item, 0, initial_path)
    return result
end

---@param data string
---@return LuaInventory inv
---@return LuaItemStack stack
---@return boolean imported
---@return string? err
function M.import_any_blueprint_item(data)
    local inv = game.create_inventory(1)
    local stack = inv[1]

    ---@param item_name string
    ---@return boolean ok
    ---@return integer count
    ---@return string? err
    local function try_with_item(item_name)
        local ok_set, set_ok = pcall(function()
            return stack.set_stack({ name = item_name, count = 1 })
        end)
        if not ok_set or set_ok == false then
            return false, 0, ("set_stack failed for %s"):format(tostring(item_name))
        end

        local ok, imported_or_err = pcall(function()
            return stack.import_stack(data)
        end)
        if not ok then
            return false, 0, tostring(imported_or_err)
        end
        local count = tonumber(imported_or_err) or 0

        local setup_ok = false
        if item_name == "blueprint" and stack.is_blueprint == true and stack.is_blueprint_setup then
            local ok_setup, is_setup = pcall(function()
                return stack.is_blueprint_setup()
            end)
            setup_ok = ok_setup and is_setup == true
        elseif item_name == "blueprint-book" and stack.is_blueprint_book == true then
            local ok_inv, book_inv = pcall(function()
                return stack.get_inventory(defines.inventory.item_main)
            end)
            if ok_inv and book_inv and book_inv.valid then
                for i = 1, #book_inv do
                    if book_inv[i] and book_inv[i].valid_for_read then
                        setup_ok = true
                        break
                    end
                end
            end
        end

        return (count ~= 0) or setup_ok, count, nil
    end

    local ok_blueprint, count_blueprint, err_blueprint = try_with_item("blueprint")
    if ok_blueprint then
        return inv, stack, true, nil
    end

    local ok_book, count_book, err_book = try_with_item("blueprint-book")
    if ok_book then
        return inv, stack, true, nil
    end

    local err = err_blueprint or err_book
    if err_blueprint and err_book and err_blueprint ~= err_book then
        err = ("blueprint=%s; blueprint-book=%s"):format(err_blueprint, err_book)
    end

    if not err then
        local head = tostring(data):sub(1, 16)
        err = ("blueprint_count=%d; blueprint_book_count=%d; len=%d; head=%q"):format(
            count_blueprint or 0,
            count_book or 0,
            #tostring(data),
            head
        )
    end

    local hints = {}
    if type(data) == "string" and (data:find("recipe_quality", 1, true) or data:find('"quality"', 1, true)) then
        if not (script and script.active_mods and script.active_mods["quality"]) then
            hints[#hints + 1] = "quality mod disabled (FactorioTest mod-list.json has it off by default)"
        end
    end
    if #hints > 0 then
        err = err .. "; hints: " .. table.concat(hints, ", ")
    end

    return inv, stack, false, err
end

return M
