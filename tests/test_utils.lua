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

---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce|string|nil
function M.assert_no_entity_ghosts(surface, area, force)
    local filter = { area = area, type = "entity-ghost" }
    if force ~= nil then
        filter.force = force
    end
    local ghosts = surface.find_entities_filtered(filter)
    if not ghosts or #ghosts == 0 then
        return
    end

    local preview = {}
    for i = 1, math.min(#ghosts, 6) do
        local e = ghosts[i]
        local inner = nil
        pcall(function()
            inner = e.ghost_name
        end)
        if not inner then
            pcall(function()
                inner = e.inner_name
            end)
        end
        preview[#preview + 1] = ("%s @ %.1f,%.1f"):format(
            tostring(inner or "?"),
            e.position and e.position.x or 0,
            e.position and e.position.y or 0
        )
    end
    error(("expected no entity ghosts, found %d: %s"):format(#ghosts, table.concat(preview, ", ")))
end

---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce|string|nil
function M.assert_no_tile_ghosts(surface, area, force)
    local filter = { area = area, type = "tile-ghost" }
    if force ~= nil then
        filter.force = force
    end
    local ghosts = surface.find_entities_filtered(filter)
    if not ghosts or #ghosts == 0 then
        return
    end

    local preview = {}
    for i = 1, math.min(#ghosts, 6) do
        local e = ghosts[i]
        local inner = nil
        pcall(function()
            inner = e.ghost_name
        end)
        if not inner then
            pcall(function()
                inner = e.inner_name
            end)
        end
        preview[#preview + 1] = ("%s @ %.1f,%.1f"):format(
            tostring(inner or "?"),
            e.position and e.position.x or 0,
            e.position and e.position.y or 0
        )
    end
    error(("expected no tile ghosts, found %d: %s"):format(#ghosts, table.concat(preview, ", ")))
end

---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce|string|nil
function M.assert_no_ghosts(surface, area, force)
    M.assert_no_entity_ghosts(surface, area, force)
    M.assert_no_tile_ghosts(surface, area, force)
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

---@class TestUtilsDeploySpidersOpts
---@field count integer
---@field inventory LuaInventory?
---@field item_name string?

---@param anchor_id string
---@param opts TestUtilsDeploySpidersOpts
---@return string[] spider_ids
function M.deploy_spiders(anchor_id, opts)
    assert(type(anchor_id) == "string" and anchor_id ~= "", "deploy_spiders requires anchor_id")
    assert(type(opts) == "table", "deploy_spiders requires opts table")
    assert(type(opts.count) == "number" and opts.count >= 1, "deploy_spiders requires count >= 1")

    local count = math.floor(opts.count)
    local inventory = opts.inventory
    local item_name = opts.item_name or "spiderling"

    if inventory and inventory.valid then
        local existing = inventory.get_item_count(item_name)
        local missing = count - existing
        if missing > 0 then
            local inserted = inventory.insert({ name = item_name, count = missing })
            assert(
                inserted == missing,
                ("failed to insert %s for deploy: missing=%d inserted=%d"):format(
                    tostring(item_name),
                    missing,
                    inserted or 0
                )
            )
        end
    end

    local spider_ids = {}
    for _ = 1, count do
        local spider_id = spider.deploy(anchor_id)
        assert(spider_id ~= nil, "spider.deploy returned nil")
        spider_ids[#spider_ids + 1] = spider_id
    end
    return spider_ids
end

---@param entity LuaEntity
---@param inventory_id integer
---@return LuaInventory
function M.anchor_inventory(entity, inventory_id)
    assert(entity and entity.valid, "anchor_inventory requires a valid entity")
    assert(type(inventory_id) == "number", "anchor_inventory requires inventory_id number")
    local inv = entity.get_inventory(inventory_id)
    assert(inv and inv.valid, "anchor inventory missing/invalid")
    return inv
end

---@class TestUtilsSetupAnchorTestOpts
---@field surface LuaSurface?
---@field force LuaForce?
---@field base_pos MapPosition?
---@field base_pos_factory fun(): MapPosition?
---@field ensure_chunks_radius integer?
---@field clean_radius integer?
---@field clear_radius integer?
---@field anchor_name string
---@field anchor_inventory_id integer?
---@field anchor_seed { name: string, count: integer, quality?: string }[]?
---@field anchor_id_prefix string
---@field player_index integer?

---@class TestUtilsAnchorTestCtx
---@field surface LuaSurface
---@field force LuaForce
---@field base_pos MapPosition
---@field created LuaEntity[]
---@field track fun(entity: LuaEntity): LuaEntity?
---@field cleanup fun()[]
---@field defer fun(fn: fun()): fun()
---@field spawn fun(spec: table): LuaEntity
---@field pos fun(offset: MapPosition): MapPosition
---@field spawn_ghost fun(spec: { inner_name: string, position?: MapPosition, offset?: MapPosition, direction?: defines.direction, expires?: boolean, force?: LuaForce|string }): LuaEntity
---@field spawn_tile_ghost fun(spec: { inner_name: string, position?: MapPosition, offset?: MapPosition, force?: LuaForce|string }): LuaEntity
---@field spawn_item_request_proxy fun(spec: { target: LuaEntity, position?: MapPosition, offset?: MapPosition, force?: LuaForce|string, modules?: BlueprintInsertPlan[]?, insert_plan?: BlueprintInsertPlan[]?, removal_plan?: BlueprintInsertPlan[]? }): LuaEntity
---@field anchor_id string
---@field anchor_entity LuaEntity
---@field anchor_data table
---@field original_global_enabled boolean

---@param opts TestUtilsSetupAnchorTestOpts
---@return TestUtilsAnchorTestCtx
function M.setup_anchor_test(opts)
    assert(type(opts) == "table", "setup_anchor_test expects opts table")
    assert(type(opts.anchor_name) == "string" and opts.anchor_name ~= "", "setup_anchor_test requires anchor_name")
    assert(
        type(opts.anchor_id_prefix) == "string" and opts.anchor_id_prefix ~= "",
        "setup_anchor_test requires anchor_id_prefix"
    )

    local surface = opts.surface or game.surfaces[1]
    local force = opts.force or game.forces.player
    assert(surface, "setup_anchor_test requires a surface")
    assert(force, "setup_anchor_test requires a force")

    local base_pos = opts.base_pos
    if not base_pos and opts.base_pos_factory then
        base_pos = opts.base_pos_factory()
    end
    assert(type(base_pos) == "table" and type(base_pos.x) == "number" and type(base_pos.y) == "number")

    local created = {}
    local cleanup = {}
    local ctx = {
        surface = surface,
        force = force,
        base_pos = base_pos,
        created = created,
        track = nil,
        cleanup = cleanup,
        defer = nil,
        spawn = nil,
        anchor_id = nil,
        anchor_entity = nil,
        anchor_data = nil,
        original_global_enabled = false,
    }
    ctx.track = function(entity)
        return M.track(created, entity)
    end
    ctx.defer = function(fn)
        assert(type(fn) == "function", "ctx.defer expects a function")
        cleanup[#cleanup + 1] = fn
        return fn
    end
    ctx.pos = function(offset)
        assert(type(offset) == "table", "ctx.pos expects an offset table")
        return { x = ctx.base_pos.x + (offset.x or 0), y = ctx.base_pos.y + (offset.y or 0) }
    end
    ctx.spawn = function(spec)
        assert(type(spec) == "table", "ctx.spawn expects a spec table")
        local create_def = {}
        for k, v in pairs(spec) do
            create_def[k] = v
        end

        create_def.force = create_def.force or ctx.force
        create_def.surface = nil

        if create_def.position == nil and type(spec.offset) == "table" then
            create_def.position = {
                x = ctx.base_pos.x + (spec.offset.x or 0),
                y = ctx.base_pos.y + (spec.offset.y or 0),
            }
        end
        create_def.offset = nil

        local entity = ctx.surface.create_entity(create_def)
        assert(entity and entity.valid, "ctx.spawn failed to create entity")
        return ctx.track(entity) or entity
    end
    ctx.spawn_ghost = function(spec)
        assert(type(spec) == "table", "ctx.spawn_ghost expects a spec table")
        assert(type(spec.inner_name) == "string" and spec.inner_name ~= "", "ctx.spawn_ghost requires inner_name")
        return ctx.spawn({
            name = "entity-ghost",
            inner_name = spec.inner_name,
            position = spec.position,
            offset = spec.offset,
            direction = spec.direction or defines.direction.north,
            expires = spec.expires == nil and false or spec.expires,
            force = spec.force,
        })
    end
    ctx.spawn_tile_ghost = function(spec)
        assert(type(spec) == "table", "ctx.spawn_tile_ghost expects a spec table")
        assert(type(spec.inner_name) == "string" and spec.inner_name ~= "", "ctx.spawn_tile_ghost requires inner_name")
        return ctx.spawn({
            name = "tile-ghost",
            inner_name = spec.inner_name,
            position = spec.position,
            offset = spec.offset,
            force = spec.force,
        })
    end
    ctx.spawn_item_request_proxy = function(spec)
        assert(type(spec) == "table", "ctx.spawn_item_request_proxy expects a spec table")
        assert(spec.target and spec.target.valid, "ctx.spawn_item_request_proxy requires a valid target")
        return ctx.spawn({
            name = "item-request-proxy",
            position = spec.position or (spec.target and spec.target.position),
            offset = spec.offset,
            force = spec.force,
            target = spec.target,
            modules = spec.modules,
            insert_plan = spec.insert_plan,
            removal_plan = spec.removal_plan,
        })
    end

    ctx.original_global_enabled = M.disable_global_enabled()
    M.reset_storage()

    if opts.ensure_chunks_radius and opts.ensure_chunks_radius > 0 then
        M.ensure_chunks(surface, base_pos, opts.ensure_chunks_radius)
    end

    if opts.clean_radius and opts.clean_radius > 0 then
        local r = opts.clean_radius
        local area = { { base_pos.x - r, base_pos.y - r }, { base_pos.x + r, base_pos.y + r } }
        M.sanitize_area(surface, area, { force = force })
    end

    if opts.clear_radius and opts.clear_radius > 0 then
        M.clear_area(surface, base_pos, opts.clear_radius)
    end

    ctx.anchor_id, ctx.anchor_entity, ctx.anchor_data = M.create_test_anchor({
        surface = surface,
        force = force,
        position = base_pos,
        name = opts.anchor_name,
        anchor_id_prefix = opts.anchor_id_prefix,
        player_index = opts.player_index,
        inventory_id = opts.anchor_inventory_id,
        seed = opts.anchor_seed,
        track = ctx.track,
    })

    return ctx
end

---@param ctx TestUtilsAnchorTestCtx?
function M.teardown_anchor_test(ctx)
    if not ctx then
        return
    end
    if ctx.cleanup then
        for i = #ctx.cleanup, 1, -1 do
            pcall(ctx.cleanup[i])
        end
    end
    M.teardown_anchor(ctx.anchor_id, ctx.anchor_data)
    M.restore_global_enabled(ctx.original_global_enabled)
    M.destroy_tracked(ctx.created)
end

---@param ctx TestUtilsAnchorTestCtx
---@return table|nil anchor_data
function M.find_anchor_data(ctx)
    if not (ctx and ctx.anchor_id and storage.anchors) then
        return nil
    end
    return storage.anchors[ctx.anchor_id]
end

---@param ctx TestUtilsAnchorTestCtx
---@return table anchor_data
function M.get_anchor_data(ctx)
    local ad = M.find_anchor_data(ctx)
    assert(ad ~= nil, "anchor missing from storage")
    return ad
end

---@param ctx TestUtilsAnchorTestCtx
---@param spider_id string
---@return table|nil spider_data
function M.find_spider_data(ctx, spider_id)
    local ad = M.find_anchor_data(ctx)
    if not (ad and ad.spiders) then
        return nil
    end
    return ad.spiders[spider_id]
end

---@param ctx TestUtilsAnchorTestCtx
---@param spider_id string
---@return table spider_data
function M.get_spider_data(ctx, spider_id)
    local sd = M.find_spider_data(ctx, spider_id)
    assert(sd ~= nil, "spider missing from anchor data: " .. tostring(spider_id))
    return sd
end

---@param ctx TestUtilsAnchorTestCtx
---@param spider_id string
---@param expected_status string
function M.assert_spider_status(ctx, spider_id, expected_status)
    local sd = M.get_spider_data(ctx, spider_id)
    assert.are_equal(expected_status, sd.status)
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

    ---@param ctx table
    ---@return TestUtilsPhaseMachineCtx
    local function to_pm_ctx(ctx)
        local phase = state.phase
        return {
            tick = ctx.tick,
            start_tick = ctx.start_tick,
            deadline_tick = ctx.deadline_tick,
            elapsed_ticks = ctx.elapsed_ticks,
            state = state,
            phase = phase,
            phase_started_tick = state.phase_started_tick or ctx.start_tick,
            phase_elapsed_ticks = ctx.tick - (state.phase_started_tick or ctx.start_tick),
        }
    end

    M.wait_until({
        timeout_ticks = opts.timeout_ticks,
        timeout_slack_ticks = opts.timeout_slack_ticks,
        description = opts.description,
        report = opts.report,
        main_loop_interval = opts.main_loop_interval,
        progress_interval = opts.progress_interval,
        on_progress = function(ctx)
            local pm_ctx = to_pm_ctx(ctx)
            if opts.on_progress then
                return opts.on_progress(pm_ctx)
            end
            return ("[Test][PhaseMachine] phase=%s elapsed=%d/%d"):format(
                tostring(pm_ctx.phase),
                pm_ctx.elapsed_ticks,
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

            local pm_ctx = to_pm_ctx(ctx)

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
                return opts.on_timeout(to_pm_ctx(ctx))
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
