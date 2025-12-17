local M = {}

---@param surface LuaSurface
---@param position MapPosition
---@param radius integer
---@param opts { anchor_entity?: LuaEntity, skip_spiders?: boolean }?
function M.clear_area(surface, position, radius, opts)
    if not (surface and (surface.valid == nil or surface.valid)) then
        return
    end
    if not position or not radius then
        return
    end

    local tiles = {}
    for y = position.y - radius, position.y + radius do
        for x = position.x - radius, position.x + radius do
            tiles[#tiles + 1] = { name = "grass-1", position = { x = x, y = y } }
        end
    end
    surface.set_tiles(tiles, true)

    local anchor_entity = opts and opts.anchor_entity or nil
    local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
    local skip_spiders = opts and opts.skip_spiders == true

    local area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
    for _, entity in ipairs(surface.find_entities_filtered({ area = area })) do
        if entity and entity.valid then
            if anchor_unit_number and entity.unit_number and entity.unit_number == anchor_unit_number then
                goto continue
            end
            if skip_spiders and entity.type == "spider-vehicle" then
                goto continue
            end
            entity.destroy({ raise_destroyed = false })
        end
        ::continue::
    end
end

function M.run_main_loop()
    return remote.call("brood-engineering-test", "run_main_loop")
end

---@param interval_ticks integer
function M.run_main_loop_periodic(interval_ticks)
    if not interval_ticks or interval_ticks < 1 then
        return
    end
    if (game.tick % interval_ticks) == 0 then
        M.run_main_loop()
    end
end

---@param enabled boolean|nil
function M.set_debug_logging_override(enabled)
    if not (remote and remote.call) then
        return
    end
    pcall(function()
        remote.call("brood-engineering-test", "set_debug_logging_override", enabled)
    end)
end

---@param fn fun()
function M.with_debug_logging(fn)
    M.set_debug_logging_override(true)
    local ok, err = pcall(fn)
    M.set_debug_logging_override(false)
    if not ok then
        error(err)
    end
end

return M
