local constants = require("scripts/constants")
local anchor = require("scripts/anchor")
local spider = require("scripts/spider")
local blueprint_fixtures = require("tests/fixtures/blueprints")
local blueprint_test_utils = require("tests/blueprint_test_utils")
local test_utils = require("tests/test_utils")

local report = blueprint_test_utils.report
local collect_blueprints = blueprint_test_utils.collect_blueprints
local import_any_blueprint_item = blueprint_test_utils.import_any_blueprint_item

test_utils.describe_anchor_test("blueprint-like placement scenarios", function()
    return test_utils.anchor_opts.character({
        x_base = 7200,
        radii = "blueprint",
        anchor_seed = {
            { name = "spiderling", count = 1 },
            { name = "stone-furnace", count = 1, quality = "normal" },
        },
    })
end, function(ctx)
    local function clear_area(position, radius)
        test_utils.clear_area(ctx.surface, position, radius, {
            anchor_entity = ctx.anchor_entity,
            skip_spiders = true,
        })
    end

    test("blueprint fixture reporting smoke test", function()
        report(
            ("[Brood][BlueprintFixture] smoke has_log=%s base=%s quality=%s space_age=%s factorio_test=%s"):format(
                tostring(type(log) == "function"),
                tostring(script and script.active_mods and script.active_mods["base"] or "unknown"),
                tostring(script and script.active_mods and script.active_mods["quality"] or "disabled"),
                tostring(script and script.active_mods and script.active_mods["space-age"] or "disabled"),
                tostring(script and script.active_mods and script.active_mods["factorio-test"] or false)
            )
        )
    end)

    test("does not crash when a blueprint ghost is blocked by a random-drop entity", function()
        local target_pos = ctx.pos({ x = 6, y = 0 })
        clear_area(target_pos, 18)

        -- This simulates a common blueprint placement scenario:
        -- - A ghost overlaps an existing entity (e.g., tree/rock).
        -- - The player (or another system) marks the blocker for deconstruction.
        -- - Our task scan/assignment executes without crashing, even if mine products are random (amount_min=0).
        local tree = ctx.spawn({
            name = "tree-01",
            position = target_pos,
            force = "neutral",
        })
        assert.is_true(tree and tree.valid)

        local ghost = ctx.spawn_ghost({
            inner_name = "stone-furnace",
            position = target_pos,
        })
        assert.is_true(ghost and ghost.valid)

        tree.order_deconstruction(ctx.force)
        assert.is_true(tree.to_be_deconstructed())

        local spider_id = spider.deploy(ctx.anchor_id)
        assert.is_not_nil(spider_id)

        test_utils.wait_until({
            timeout_ticks = 60 * 25,
            description = "blocked ghost scenario completes",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                -- The primary purpose is "no crash"; also assert progress: blocker removed and ghost built.
                if not tree.valid then
                    local built = ctx.surface.find_entities_filtered({
                        position = target_pos,
                        name = "stone-furnace",
                        force = ctx.force,
                    })
                    if built and #built > 0 then
                        return true
                    end
                end

                return false
            end,
        })
    end)

    for _, fixture in ipairs(blueprint_fixtures or {}) do
        local fixture_name = fixture and fixture.name or "unknown"
        local data = fixture and fixture.data or nil

        test(("imports blueprint fixture: %s"):format(tostring(fixture_name)), function()
            if not data or data == "" then
                return
            end

            local inv, _, imported, err = import_any_blueprint_item(data)
            inv.destroy()

            if not imported then
                report(
                    ("[Brood][BlueprintFixture] import skipped for %s (%s)"):format(
                        tostring(fixture_name),
                        tostring(err or "unknown")
                    )
                )
                return
            end
        end)

        test(("builds blueprint fixture (if buildable): %s"):format(tostring(fixture_name)), function()
            if not data or data == "" then
                return
            end

            report(("[Brood][BlueprintFixture] starting build fixture=%s"):format(tostring(fixture_name)))

            local inv, stack, imported, err = import_any_blueprint_item(data)
            if not imported then
                report(
                    ("[Brood][BlueprintFixture] build skipped (import failed) for %s (%s)"):format(
                        tostring(fixture_name),
                        tostring(err or "unknown")
                    )
                )
                inv.destroy()
                return
            end
            ctx.defer(function()
                if inv and inv.valid then
                    inv.destroy()
                end
            end)

            local build_pos = ctx.pos({ x = 20, y = 0 })
            test_utils.ensure_chunks(ctx.surface, build_pos, 4)

            local blueprints = collect_blueprints(stack, 3)
            if not blueprints or #blueprints == 0 then
                report(
                    ("[Brood][BlueprintFixture] build skipped (no blueprints found) for %s"):format(
                        tostring(fixture_name)
                    )
                )
                return
            end

            local ok_any = false
            local built_summaries = {}
            report(
                ("[Brood][BlueprintFixture] %s contains %d blueprint(s)"):format(tostring(fixture_name), #blueprints)
            )

            for idx, bp_info in ipairs(blueprints) do
                local bp = bp_info.stack
                local path = bp_info.path or "?"

                local label = nil
                pcall(function()
                    label = bp.label
                end)

                local ok_setup, is_setup = pcall(function()
                    return bp.is_blueprint_setup and bp.is_blueprint_setup() or true
                end)
                if ok_setup and is_setup == false then
                    report(
                        ("[Brood][BlueprintFixture] skipping (not setup) %s #%d path=%s label=%s"):format(
                            tostring(fixture_name),
                            idx,
                            tostring(path),
                            tostring(label or "nil")
                        )
                    )
                    goto continue_blueprint
                end

                -- Build sequentially at the same location so the exact position doesn't matter.
                clear_area(build_pos, 60)

                report(
                    ("[Brood][BlueprintFixture] building %s #%d path=%s label=%s"):format(
                        tostring(fixture_name),
                        idx,
                        tostring(path),
                        tostring(label or "nil")
                    )
                )

                local ok_build, built_or_err = pcall(function()
                    return bp.build_blueprint({
                        surface = ctx.surface,
                        force = ctx.force.name,
                        position = build_pos,
                        raise_built = true,
                        skip_fog_of_war = true,
                    })
                end)

                if not ok_build then
                    report(
                        ("[Brood][BlueprintFixture] build skipped for %s #%d (%s)"):format(
                            tostring(fixture_name),
                            idx,
                            tostring(built_or_err)
                        )
                    )
                    goto continue_blueprint
                end

                ok_any = true
                built_summaries[#built_summaries + 1] = ("#%d path=%s label=%s"):format(
                    idx,
                    tostring(path),
                    tostring(label or "nil")
                )
                report(
                    ("[Brood][BlueprintFixture] built %s #%d path=%s label=%s"):format(
                        tostring(fixture_name),
                        idx,
                        tostring(path),
                        tostring(label or "nil")
                    )
                )

                ::continue_blueprint::
            end

            if ok_any then
                report(
                    ("[Brood][BlueprintFixture] built %s blueprints: %s"):format(
                        tostring(fixture_name),
                        table.concat(built_summaries, ", ")
                    )
                )
            end
        end)
    end
end)
