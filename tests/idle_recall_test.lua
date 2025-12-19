local constants = require("scripts/constants")
local spider = require("scripts/spider")
local fapi = require("scripts/fapi")
local test_utils = require("tests/test_utils")

test_utils.describe_anchor_test("idle recall after finishing work", function()
    return test_utils.anchor_opts.chest({
        x_base = 4000,
        radii = "idle",
        spiderlings = 1,
    })
end, function(ctx)
    local task_entity

    before_each(function()
        -- Ensure the immediate area around the anchor/task is clear and traversable
        -- so spider movement doesn't depend on map generation randomness.
        test_utils.clear_area(ctx.surface, ctx.base_pos, 25, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })

        local task_pos = ctx.pos({ x = 2, y = 0 })
        test_utils.clear_area(ctx.surface, task_pos, 15, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })

        -- A single nearby deconstruction task to trigger deploy + full task execution.
        task_entity = ctx.spawn({
            name = "stone-furnace",
            position = task_pos,
        })
        task_entity.order_deconstruction(ctx.force)
        assert.is_true(task_entity.to_be_deconstructed())
    end)

    test("deploys, completes nearby task, then recalls after ~2s of no work", function()
        local inventory = ctx.anchor_inventory
        assert(inventory and inventory.valid)

        -- Keep the scheduled main loop disabled and drive it manually on the
        -- same cadence as on_nth_tick for determinism.
        storage.global_enabled = false

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        test_utils.phase_machine({
            timeout_ticks = constants.no_work_recall_timeout_ticks + constants.main_loop_interval * 80,
            description = "idle recall",
            main_loop_interval = constants.main_loop_interval,
            state = {
                idle_since_tick = nil,
            },
            initial = "waiting_assigned",
            phase_timeouts = {
                waiting_assigned = constants.main_loop_interval * 30,
                -- Allow an extra main-loop window so we don't fail if the spider becomes "close enough"
                -- just after the last scheduled `run_main_loop` tick.
                waiting_completed = 60 * 12 + constants.main_loop_interval * 2,
            },
            phases = {
                waiting_assigned = function()
                    local spider_data = test_utils.find_spider_data(ctx, spider_id)
                    if spider_data and spider_data.status == "moving_to_task" then
                        return "waiting_completed"
                    end
                    return nil
                end,
                waiting_completed = function(pm_ctx)
                    local tick = pm_ctx.tick
                    local spider_data = test_utils.find_spider_data(ctx, spider_id)

                    if spider_data and spider_data.status == "deployed_idle" and not spider_data.task then
                        assert.is_false(task_entity.valid)
                        pm_ctx.state.idle_since_tick = tick

                        -- Nudge the anchor slightly; spider should keep following while idle.
                        fapi.teleport(ctx.anchor_entity, { x = ctx.base_pos.x + 1, y = ctx.base_pos.y })
                        return "waiting_recall"
                    end

                    return nil
                end,
                waiting_recall = function(pm_ctx)
                    local tick = pm_ctx.tick
                    local spider_data = test_utils.find_spider_data(ctx, spider_id)

                    if not spider_data then
                        return "verify"
                    end

                    if spider_data.status == "deployed_idle" and spider_data.entity and spider_data.entity.valid then
                        test_utils.assert_spider_following_anchor(ctx, spider_id)
                    end

                    if
                        pm_ctx.state.idle_since_tick
                        and tick - pm_ctx.state.idle_since_tick
                            > (constants.no_work_recall_timeout_ticks + constants.main_loop_interval * 10)
                    then
                        error("Spider was not recalled within expected no-work window")
                    end

                    return nil
                end,
                verify = function()
                    assert.are_equal(1, inventory.get_item_count("spiderling"))
                    return true
                end,
            },
            on_timeout = function(pm_ctx)
                local spider_data = test_utils.find_spider_data(ctx, spider_id)
                local status = spider_data and spider_data.status or "nil"
                local task_id = spider_data and spider_data.task and spider_data.task.id or "nil"
                return ("phase=%s status=%s task=%s"):format(
                    tostring(pm_ctx.phase),
                    tostring(status),
                    tostring(task_id)
                )
            end,
        })
    end)
end)
