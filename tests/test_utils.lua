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

---@class TestUtilsSanitizeAreaOpts
---@field force LuaForce?
---@field anchor_entity LuaEntity?
---@field skip_spiders boolean?
---@field destroy_types string[]?
---@field destroy_enemy boolean?
---@field cancel_deconstruction boolean?
---@field cancel_upgrade boolean?

---@param surface LuaSurface
---@param area BoundingBox
---@param opts TestUtilsSanitizeAreaOpts?
function M.sanitize_area(surface, area, opts)
    if not (surface and (surface.valid == nil or surface.valid)) then
        return
    end
    if not area then
        return
    end

    local force = opts and opts.force or nil
    local anchor_entity = opts and opts.anchor_entity or nil
    local anchor_unit_number = anchor_entity and anchor_entity.valid and anchor_entity.unit_number or nil
    local skip_spiders = opts and opts.skip_spiders == true

    local destroy_enemy = true
    if opts and opts.destroy_enemy == false then
        destroy_enemy = false
    end

    local cancel_deconstruction = true
    if opts and opts.cancel_deconstruction == false then
        cancel_deconstruction = false
    end

    local cancel_upgrade = true
    if opts and opts.cancel_upgrade == false then
        cancel_upgrade = false
    end

    if cancel_deconstruction and force then
        for _, e in
            pairs(surface.find_entities_filtered({
                area = area,
                to_be_deconstructed = true,
            }))
        do
            if e and e.valid and e.cancel_deconstruction then
                pcall(function()
                    e.cancel_deconstruction(force)
                end)
            end
        end
    end

    if cancel_upgrade and force then
        for _, e in
            pairs(surface.find_entities_filtered({
                area = area,
                to_be_upgraded = true,
            }))
        do
            if e and e.valid and e.cancel_upgrade then
                pcall(function()
                    e.cancel_upgrade(force)
                end)
            end
        end
    end

    local destroy_types = (opts and opts.destroy_types) or { "entity-ghost", "tile-ghost", "item-request-proxy" }
    if destroy_types and #destroy_types > 0 then
        for _, e in
            pairs(surface.find_entities_filtered({
                area = area,
                type = destroy_types,
            }))
        do
            if e and e.valid then
                if anchor_unit_number and e.unit_number and e.unit_number == anchor_unit_number then
                    goto continue_destroy
                end
                if skip_spiders and e.type == "spider-vehicle" then
                    goto continue_destroy
                end
                pcall(function()
                    e.destroy({ raise_destroyed = false })
                end)
            end
            ::continue_destroy::
        end
    end

    if destroy_enemy then
        for _, e in
            pairs(surface.find_entities_filtered({
                area = area,
                force = "enemy",
            }))
        do
            if e and e.valid then
                pcall(function()
                    e.destroy({ raise_destroyed = false })
                end)
            end
        end
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

---@class TestUtilsPhaseMachineCtx
---@field tick integer
---@field start_tick integer
---@field deadline_tick integer
---@field elapsed_ticks integer
---@field state table
---@field phase string
---@field phase_started_tick integer
---@field phase_elapsed_ticks integer

---@alias TestUtilsPhaseMachineStepResult boolean|string|{ done?: boolean, phase?: string }|nil

---@class TestUtilsPhaseMachineOpts
---@field timeout_ticks integer
---@field timeout_slack_ticks integer?
---@field description string?
---@field report fun(msg: string)?
---@field main_loop_interval integer?
---@field progress_interval integer?
---@field on_progress fun(ctx: TestUtilsPhaseMachineCtx): string?
---@field on_transition fun(ctx: TestUtilsPhaseMachineCtx, from: string, to: string)?
---@field on_timeout fun(ctx: TestUtilsPhaseMachineCtx): string?
---@field state table?
---@field initial string
---@field phases table<string, fun(ctx: TestUtilsPhaseMachineCtx): TestUtilsPhaseMachineStepResult>
---@field phase_timeouts table<string, integer>?

---@param opts TestUtilsPhaseMachineOpts
function M.phase_machine(opts)
    assert(type(opts) == "table", "phase_machine expects opts table")
    assert(type(opts.initial) == "string" and opts.initial ~= "", "phase_machine requires initial phase name")
    assert(type(opts.phases) == "table", "phase_machine requires phases table")

    local state = opts.state or {}
    if type(state) ~= "table" then
        state = {}
    end
    if type(state.phase) ~= "string" or state.phase == "" then
        state.phase = opts.initial
    end
    if type(state.phase_started_tick) ~= "number" then
        state.phase_started_tick = game.tick
    end

    local phase_timeouts = opts.phase_timeouts or {}

    M.wait_until({
        timeout_ticks = opts.timeout_ticks,
        timeout_slack_ticks = opts.timeout_slack_ticks,
        description = opts.description,
        report = opts.report,
        main_loop_interval = opts.main_loop_interval,
        progress_interval = opts.progress_interval,
        on_progress = opts.on_progress or function(ctx)
            return ("[Test][PhaseMachine] phase=%s elapsed=%d/%d"):format(
                tostring(state.phase),
                ctx.elapsed_ticks,
                opts.timeout_ticks
            )
        end,
        state = state,
        on_tick = function(ctx)
            local phase = state.phase
            local phase_fn = opts.phases[phase]
            assert(type(phase_fn) == "function", "missing phase handler for " .. tostring(phase))

            local phase_timeout = phase_timeouts[phase]
            if type(phase_timeout) == "number" and phase_timeout > 0 then
                local elapsed_in_phase = ctx.tick - (state.phase_started_tick or ctx.start_tick)
                if elapsed_in_phase >= phase_timeout then
                    error(
                        ("phase %s timed out after %d ticks (tick=%d)"):format(tostring(phase), phase_timeout, ctx.tick)
                    )
                end
            end
        end,
        condition = function(ctx)
            local phase = state.phase
            local phase_fn = opts.phases[phase]
            assert(type(phase_fn) == "function", "missing phase handler for " .. tostring(phase))

            local pm_ctx = {
                tick = ctx.tick,
                start_tick = ctx.start_tick,
                deadline_tick = ctx.deadline_tick,
                elapsed_ticks = ctx.elapsed_ticks,
                state = state,
                phase = phase,
                phase_started_tick = state.phase_started_tick or ctx.start_tick,
                phase_elapsed_ticks = ctx.tick - (state.phase_started_tick or ctx.start_tick),
            }

            local result = phase_fn(pm_ctx)
            if result == true then
                return true
            end
            if type(result) == "table" and result.done == true then
                return true
            end

            local next_phase = nil
            if type(result) == "string" and result ~= "" then
                next_phase = result
            elseif type(result) == "table" and type(result.phase) == "string" and result.phase ~= "" then
                next_phase = result.phase
            end

            if next_phase and next_phase ~= phase then
                local old = phase
                state.phase = next_phase
                state.phase_started_tick = ctx.tick
                if opts.on_transition then
                    opts.on_transition(pm_ctx, old, next_phase)
                end
            end

            return false
        end,
        on_timeout = function(ctx)
            if opts.on_timeout then
                local phase = state.phase
                local pm_ctx = {
                    tick = ctx.tick,
                    start_tick = ctx.start_tick,
                    deadline_tick = ctx.deadline_tick,
                    elapsed_ticks = ctx.elapsed_ticks,
                    state = state,
                    phase = phase,
                    phase_started_tick = state.phase_started_tick or ctx.start_tick,
                    phase_elapsed_ticks = ctx.tick - (state.phase_started_tick or ctx.start_tick),
                }
                return opts.on_timeout(pm_ctx)
            end
            return nil
        end,
    })
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
