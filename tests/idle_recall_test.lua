local constants = require("scripts/constants")
local spider = require("scripts/spider")

describe("idle recall after finishing work", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local task_entity
    local original_global_enabled

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 4000 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        original_global_enabled = storage.global_enabled
        -- Keep the main loop disabled during setup to avoid races with task creation.
        storage.global_enabled = false

        -- Fully reset mod state for isolation.
        storage.anchors = {}
        storage.spider_to_anchor = {}
        storage.entity_to_spider = {}
        storage.assigned_tasks = {}
        storage.assignment_limits = {}
        storage.pending_tile_deconstruct = {}

        -- Clean any preexisting work in the area to keep this test isolated.
        local clean_radius = 120
        local clean_area = {
            { base_pos.x - clean_radius, base_pos.y - clean_radius },
            { base_pos.x + clean_radius, base_pos.y + clean_radius },
        }
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                type = { "entity-ghost", "tile-ghost", "item-request-proxy" },
            }))
        do
            if e and e.valid then
                e.destroy()
            end
        end
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                to_be_deconstructed = true,
            }))
        do
            if e and e.valid and e.cancel_deconstruction then
                e.cancel_deconstruction(force)
            end
        end
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                to_be_upgraded = true,
            }))
        do
            if e and e.valid and e.cancel_upgrade then
                e.cancel_upgrade(force)
            end
        end

        -- Ensure the area is safe from biters/worms so anchors/spiders
        -- aren't destroyed during the test.
        for _, e in
            pairs(surface.find_entities_filtered({
                area = clean_area,
                force = "enemy",
            }))
        do
            if e and e.valid then
                e.destroy()
            end
        end

        anchor_entity = track(surface.create_entity({
            name = "wooden-chest",
            position = base_pos,
            force = force,
        }))

        local inventory = anchor_entity.get_inventory(defines.inventory.chest)
        inventory.insert({ name = "spiderling", count = 1 })

        anchor_id = "test_anchor_idle_" .. game.tick .. "_" .. math.random(1, 1000000)
        anchor_data = {
            type = "test",
            entity = anchor_entity,
            player_index = nil,
            surface_index = surface.index,
            position = { x = anchor_entity.position.x, y = anchor_entity.position.y },
            spiders = {},
        }
        storage.anchors[anchor_id] = anchor_data

        -- A single nearby deconstruction task to trigger deploy + full task execution.
        local task_pos = { x = base_pos.x + 2, y = base_pos.y }
        task_entity = track(surface.create_entity({
            name = "stone-furnace",
            position = task_pos,
            force = force,
        }))
        task_entity.order_deconstruction(force)
        assert.is_true(task_entity.to_be_deconstructed())
    end)

    after_each(function()
        if anchor_data and anchor_data.spiders then
            local spider_ids = {}
            for spider_id, _ in pairs(anchor_data.spiders) do
                spider_ids[#spider_ids + 1] = spider_id
            end
            for _, spider_id in ipairs(spider_ids) do
                spider.recall(spider_id)
            end
        end

        if anchor_id and storage.anchors then
            storage.anchors[anchor_id] = nil
        end
        storage.global_enabled = original_global_enabled

        for _, e in ipairs(created) do
            if e and e.valid then
                e.destroy()
            end
        end
    end)

    test("deploys, completes nearby task, then recalls after ~2s of no work", function()
        local inventory = anchor_entity.get_inventory(defines.inventory.chest)

        -- Keep the scheduled main loop disabled and drive it manually on the
        -- same cadence as on_nth_tick for determinism.
        storage.global_enabled = false

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        -- Condition-based async test: assign → execute → idle → recall.
        async(constants.no_work_recall_timeout_ticks + constants.main_loop_interval * 80)

        local phase = "waiting_assigned"
        local phase_started_at = game.tick
        local idle_since_tick

        local function set_phase(next_phase)
            phase = next_phase
            phase_started_at = game.tick
        end

        local function phase_age()
            return game.tick - phase_started_at
        end

        on_tick(function()
            local tick = game.tick
            if (tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            if phase == "waiting_assigned" then
                local spider_data = anchor_data.spiders[spider_id]
                if spider_data and spider_data.status == "moving_to_task" then
                    set_phase("waiting_completed")
                end
                if phase_age() > constants.main_loop_interval * 30 then
                    local status = spider_data and spider_data.status or "nil"
                    local task_id = spider_data and spider_data.task and spider_data.task.id or "nil"
                    error(
                        ("Timed out waiting for assignment (tick=%d, status=%s, task=%s)"):format(tick, status, task_id)
                    )
                end
            elseif phase == "waiting_completed" then
                local spider_data = anchor_data.spiders[spider_id]
                if spider_data and spider_data.status == "deployed_idle" and not spider_data.task then
                    assert.is_false(task_entity.valid)
                    idle_since_tick = tick

                    -- Nudge the anchor slightly; spider should keep following while idle.
                    anchor_entity.teleport({ x = base_pos.x + 1, y = base_pos.y })
                    set_phase("waiting_recall")
                end
                if phase_age() > 60 * 12 then
                    local status = spider_data and spider_data.status or "nil"
                    local task_id = spider_data and spider_data.task and spider_data.task.id or "nil"
                    local spider_entity = spider_data and spider_data.entity
                    local speed = spider_entity and spider_entity.valid and (spider_entity.speed or 0) or 0
                    local dests = spider_entity and spider_entity.valid and spider_entity.autopilot_destinations or nil
                    local dest_count = dests and #dests or 0
                    local dist = math.huge
                    if spider_entity and spider_entity.valid and spider_data and spider_data.task then
                        local target = spider_data.task.entity or spider_data.task.tile
                        if target and target.valid then
                            local dx = spider_entity.position.x - target.position.x
                            local dy = spider_entity.position.y - target.position.y
                            dist = math.sqrt(dx * dx + dy * dy)
                        end
                    end
                    error(
                        ("Timed out waiting for completion (tick=%d, status=%s, task=%s, speed=%.3f, dests=%d, dist=%.2f)"):format(
                            tick,
                            status,
                            task_id,
                            speed,
                            dest_count,
                            dist
                        )
                    )
                end
            elseif phase == "waiting_recall" then
                local spider_data = anchor_data.spiders[spider_id]

                if not spider_data then
                    assert.are_equal(1, inventory.get_item_count("spiderling"))
                    done()
                    return false
                end

                if spider_data.status == "deployed_idle" and spider_data.entity and spider_data.entity.valid then
                    local ft = spider_data.entity.follow_target
                    if ft and ft.valid then
                        assert.are_equal(anchor_entity.unit_number, ft.unit_number)
                    end
                end

                if
                    idle_since_tick
                    and tick - idle_since_tick
                        > (constants.no_work_recall_timeout_ticks + constants.main_loop_interval * 10)
                then
                    error("Spider was not recalled within expected no-work window")
                end
            end

            return true
        end)
    end)
end)
