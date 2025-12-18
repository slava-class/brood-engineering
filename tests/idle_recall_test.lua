local constants = require("scripts/constants")
local spider = require("scripts/spider")
local test_utils = require("tests/test_utils")

describe("idle recall after finishing work", function()
    local ctx
    local task_entity

    before_each(function()
        ctx = test_utils.setup_anchor_test({
            base_pos = { x = 4000 + math.random(0, 50), y = math.random(-20, 20) },
            ensure_chunks_radius = 2,
            clean_radius = 120,
            anchor_name = "wooden-chest",
            anchor_inventory_id = defines.inventory.chest,
            anchor_seed = { { name = "spiderling", count = 1 } },
            anchor_id_prefix = "test_anchor_idle",
        })

        -- Ensure the immediate area around the anchor/task is clear and traversable
        -- so spider movement doesn't depend on map generation randomness.
        test_utils.clear_area(ctx.surface, ctx.base_pos, 25, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })

        local task_pos = { x = ctx.base_pos.x + 2, y = ctx.base_pos.y }
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

    after_each(function()
        test_utils.teardown_anchor_test(ctx)
    end)

    test("deploys, completes nearby task, then recalls after ~2s of no work", function()
        local inventory = test_utils.anchor_inventory(ctx.anchor_entity, defines.inventory.chest)

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
                        ctx.anchor_entity.teleport({ x = ctx.base_pos.x + 1, y = ctx.base_pos.y })
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
                        local ft = spider_data.entity.follow_target
                        if ft and ft.valid then
                            assert.are_equal(ctx.anchor_entity.unit_number, ft.unit_number)
                        end
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
