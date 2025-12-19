local fapi = {}

---@class FapiDestroyOpts
---@field do_cliff_correction boolean? nil
---@field raise_destroy boolean? nil
---@field player PlayerIdentification? nil
---@field undo_index uint32? nil

---@param entity LuaEntity
---@param opts FapiDestroyOpts?
---@return boolean ok
function fapi.destroy(entity, opts)
    if not (entity and entity.valid) then
        return false
    end
    if not opts then
        return entity.destroy({})
    end
    return entity.destroy(opts)
end

---@param entity LuaEntity
---@return boolean ok
function fapi.destroy_quiet(entity)
    return fapi.destroy(entity, { raise_destroy = false })
end

---@param entity LuaEntity
---@return boolean ok
function fapi.destroy_raise(entity)
    return fapi.destroy(entity, { raise_destroy = true })
end

---@param surface LuaSurface
---@param entity_name EntityID
---@param center MapPosition
---@param radius number
---@param precision number
---@param force_to_tile_center boolean?
---@return MapPosition? position
function fapi.find_non_colliding_position(surface, entity_name, center, radius, precision, force_to_tile_center)
    if not surface then
        return nil
    end
    return surface.find_non_colliding_position(entity_name, center, radius, precision, force_to_tile_center)
end

---@class FapiSetTilesOpts
---@field remove_colliding_entities boolean|"abort_on_collision"|nil
---@field remove_colliding_decoratives boolean? nil
---@field raise_event boolean? nil
---@field player PlayerIdentification? nil
---@field undo_index uint32? nil

---@param surface LuaSurface
---@param tiles Tile[]
---@param correct_tiles boolean?
---@param opts FapiSetTilesOpts?
function fapi.set_tiles(surface, tiles, correct_tiles, opts)
    if not surface then
        return
    end
    if not opts then
        surface.set_tiles(tiles, correct_tiles)
        return
    end

    surface.set_tiles(
        tiles,
        correct_tiles,
        opts.remove_colliding_entities,
        opts.remove_colliding_decoratives,
        opts.raise_event,
        opts.player,
        opts.undo_index
    )
end

---@class FapiTeleportOpts
---@field raise_teleported boolean? nil
---@field snap_to_grid boolean? nil
---@field build_check_type defines.build_check_type? nil

---@param control LuaControl
---@param position MapPosition
---@param surface SurfaceIdentification?
---@param opts FapiTeleportOpts?
---@return boolean ok
function fapi.teleport(control, position, surface, opts)
    if not control then
        return false
    end
    local raise_teleported = opts and opts.raise_teleported or nil
    local snap_to_grid = opts and opts.snap_to_grid or nil
    local build_check_type = opts and opts.build_check_type or nil
    return control.teleport(position, surface, raise_teleported, snap_to_grid, build_check_type)
end

return fapi
