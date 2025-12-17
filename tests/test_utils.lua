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
