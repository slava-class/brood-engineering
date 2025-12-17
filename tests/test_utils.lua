local spider = require("scripts/spider")

local M = {}

---@param msg string
local function default_report(msg)
    if type(log) == "function" then
        pcall(function()
            log(msg)
        end)
    end
    pcall(function()
        if game and game.print then
            game.print(msg)
        end
    end)
end

M.report = default_report

function M.reset_storage()
    storage.anchors = {}
    storage.spider_to_anchor = {}
    storage.entity_to_spider = {}
    storage.assigned_tasks = {}
    storage.assignment_limits = {}
    storage.pending_tile_deconstruct = {}
end

---@return boolean original
function M.disable_global_enabled()
    local original = storage.global_enabled
    storage.global_enabled = false
    return original
end

---@param original boolean
function M.restore_global_enabled(original)
    storage.global_enabled = original
end

---@param surface LuaSurface
---@param position MapPosition
---@param radius integer
function M.ensure_chunks(surface, position, radius)
    if not surface then
        return
    end
    surface.request_to_generate_chunks(position, radius)
    surface.force_generate_chunk_requests()
end

---@param created LuaEntity[]
---@param entity LuaEntity?
---@return LuaEntity? entity
function M.track(created, entity)
    if created and entity and entity.valid then
        created[#created + 1] = entity
    end
    return entity
end

---@param created LuaEntity[]
function M.destroy_tracked(created)
    for _, e in ipairs(created or {}) do
        if e and e.valid then
            pcall(function()
                e.destroy({ raise_destroyed = false })
            end)
        end
    end
end

---@param entity LuaEntity
---@return integer? inv_id
local function default_inventory_id(entity)
    if not (entity and entity.valid) then
        return nil
    end
    if entity.type == "character" then
        return defines.inventory.character_main
    end
    return defines.inventory.chest
end

---@class TestUtilsCreateAnchorOpts
---@field surface LuaSurface
---@field force LuaForce
---@field position MapPosition
---@field name string
---@field anchor_id_prefix string
---@field player_index integer?
---@field inventory_id integer?
---@field seed { name: string, count: integer, quality?: string }[]?
---@field track fun(entity: LuaEntity): LuaEntity?

---@param opts TestUtilsCreateAnchorOpts
---@return string anchor_id
---@return LuaEntity anchor_entity
---@return table anchor_data
---@return LuaInventory? inventory
function M.create_test_anchor(opts)
    assert(opts and opts.surface and opts.force and opts.position and opts.name and opts.anchor_id_prefix)

    local entity = opts.surface.create_entity({
        name = opts.name,
        position = opts.position,
        force = opts.force,
    })
    assert(entity and entity.valid)
    if opts.track then
        entity = opts.track(entity) or entity
    end

    local anchor_id = ("%s_%d_%d"):format(tostring(opts.anchor_id_prefix), game.tick, math.random(1, 1000000))
    local anchor_data = {
        type = "test",
        entity = entity,
        player_index = opts.player_index or nil,
        surface_index = opts.surface.index,
        position = { x = entity.position.x, y = entity.position.y },
        spiders = {},
    }
    storage.anchors = storage.anchors or {}
    storage.anchors[anchor_id] = anchor_data

    local inv_id = opts.inventory_id or default_inventory_id(entity)
    local inventory = inv_id and entity.get_inventory(inv_id) or nil
    if inventory and inventory.valid and opts.seed then
        for _, stack_def in ipairs(opts.seed) do
            inventory.insert(stack_def)
        end
    end

    return anchor_id, entity, anchor_data, inventory
end

---@param anchor_id string?
---@param anchor_data table?
function M.teardown_anchor(anchor_id, anchor_data)
    if anchor_data and anchor_data.spiders then
        local spider_ids = {}
        for spider_id, _ in pairs(anchor_data.spiders) do
            spider_ids[#spider_ids + 1] = spider_id
        end
        for _, spider_id in ipairs(spider_ids) do
            pcall(function()
                spider.recall(spider_id)
            end)
        end
    end

    if anchor_id and storage.anchors then
        storage.anchors[anchor_id] = nil
    end
end

---@param anchor_id string?
function M.remove_anchor(anchor_id)
    if anchor_id and storage.anchors then
        storage.anchors[anchor_id] = nil
    end
end

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

---@class TestUtilsWaitUntilOpts
---@field timeout_ticks integer
---@field timeout_slack_ticks integer?
---@field description string?
---@field report fun(msg: string)?
---@field main_loop_interval integer?
---@field progress_interval integer?
---@field on_progress fun(ctx: table): string?
---@field state table?
---@field on_tick fun(ctx: table)?
---@field condition fun(ctx: table): boolean
---@field on_timeout fun(ctx: table): string?

---@param opts TestUtilsWaitUntilOpts
function M.wait_until(opts)
    assert(type(opts) == "table", "wait_until expects opts table")
    assert(type(opts.timeout_ticks) == "number" and opts.timeout_ticks > 0, "wait_until requires timeout_ticks > 0")
    assert(type(opts.condition) == "function", "wait_until requires condition(ctx) function")

    local report = opts.report or default_report
    local start_tick = game.tick
    local deadline_tick = start_tick + opts.timeout_ticks
    local state = opts.state or {}

    local progress_interval = opts.progress_interval
    if progress_interval == nil then
        progress_interval = 600
    end

    local slack = opts.timeout_slack_ticks
    if slack == nil then
        slack = 60
    end

    async(opts.timeout_ticks + slack)
    on_tick(function()
        local tick = game.tick
        local ctx = {
            tick = tick,
            start_tick = start_tick,
            deadline_tick = deadline_tick,
            elapsed_ticks = tick - start_tick,
            state = state,
        }

        if opts.main_loop_interval then
            M.run_main_loop_periodic(opts.main_loop_interval)
        end

        if opts.on_tick then
            local ok, err = pcall(opts.on_tick, ctx)
            if not ok then
                error(err)
            end
        end

        if opts.on_progress and progress_interval and progress_interval > 0 then
            if ((tick - start_tick) % progress_interval) == 0 then
                local ok, msg = pcall(opts.on_progress, ctx)
                if ok and msg and msg ~= "" then
                    report(msg)
                end
            end
        end

        local ok_cond, done_now_or_err = pcall(opts.condition, ctx)
        if not ok_cond then
            error(done_now_or_err)
        end
        if done_now_or_err == true then
            done()
            return false
        end

        if tick >= deadline_tick then
            local extra = nil
            if opts.on_timeout then
                local ok_timeout, info = pcall(opts.on_timeout, ctx)
                if ok_timeout and info and info ~= "" then
                    extra = info
                end
            end

            local prefix = "Timed out"
            if opts.description and opts.description ~= "" then
                prefix = prefix .. " (" .. tostring(opts.description) .. ")"
            end
            local msg = ("%s after %d ticks (tick=%d)"):format(prefix, opts.timeout_ticks, tick)
            if extra then
                msg = msg .. ": " .. tostring(extra)
            end
            error(msg)
        end

        return true
    end)
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
