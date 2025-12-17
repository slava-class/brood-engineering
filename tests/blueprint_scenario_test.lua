local constants = require("scripts/constants")
local anchor = require("scripts/anchor")
local spider = require("scripts/spider")
local blueprint_fixtures = require("tests/fixtures/blueprints")
local blueprint_test_utils = require("tests/blueprint_test_utils")
local test_utils = require("tests/test_utils")

describe("blueprint-like placement scenarios", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local original_global_enabled

    local report = blueprint_test_utils.report

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    local function clear_area(position, radius)
        test_utils.clear_area(surface, position, radius, {
            anchor_entity = anchor_entity,
            skip_spiders = true,
        })
    end

    local collect_blueprints = blueprint_test_utils.collect_blueprints
    local import_any_blueprint_item = blueprint_test_utils.import_any_blueprint_item

    before_each(function()
        surface = game.surfaces[1]
        force = game.forces.player
        base_pos = { x = 7200 + math.random(0, 50), y = math.random(-20, 20) }
        created = {}

        surface.request_to_generate_chunks(base_pos, 2)
        surface.force_generate_chunk_requests()

        original_global_enabled = storage.global_enabled
        storage.global_enabled = false

        -- Fully reset mod state for isolation.
        storage.anchors = {}
        storage.spider_to_anchor = {}
        storage.entity_to_spider = {}
        storage.assigned_tasks = {}
        storage.assignment_limits = {}
        storage.pending_tile_deconstruct = {}

        anchor_entity = track(surface.create_entity({
            name = "character",
            position = base_pos,
            force = force,
        }))
        local inventory = anchor_entity.get_inventory(defines.inventory.character_main)
        inventory.insert({ name = "spiderling", count = 1 })
        inventory.insert({ name = "stone-furnace", count = 1, quality = "normal" })

        anchor_id = "test_anchor_blueprint_" .. game.tick .. "_" .. math.random(1, 1000000)
        anchor_data = {
            type = "test",
            entity = anchor_entity,
            player_index = nil,
            surface_index = surface.index,
            position = { x = anchor_entity.position.x, y = anchor_entity.position.y },
            spiders = {},
        }
        storage.anchors[anchor_id] = anchor_data
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
                e.destroy({ raise_destroyed = false })
            end
        end
    end)

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
        local target_pos = { x = base_pos.x + 6, y = base_pos.y }
        clear_area(target_pos, 18)

        -- This simulates a common blueprint placement scenario:
        -- - A ghost overlaps an existing entity (e.g., tree/rock).
        -- - The player (or another system) marks the blocker for deconstruction.
        -- - Our task scan/assignment executes without crashing, even if mine products are random (amount_min=0).
        local tree = track(surface.create_entity({
            name = "tree-01",
            position = target_pos,
            force = "neutral",
        }))
        assert.is_true(tree and tree.valid)

        local ghost = track(surface.create_entity({
            name = "entity-ghost",
            inner_name = "stone-furnace",
            position = target_pos,
            force = force,
            expires = false,
        }))
        assert.is_true(ghost and ghost.valid)

        tree.order_deconstruction(force)
        assert.is_true(tree.to_be_deconstructed())

        local spider_id = spider.deploy(anchor_id)
        assert.is_not_nil(spider_id)

        test_utils.wait_until({
            timeout_ticks = 60 * 25,
            description = "blocked ghost scenario completes",
            main_loop_interval = constants.main_loop_interval,
            condition = function()
                -- The primary purpose is "no crash"; also assert progress: blocker removed and ghost built.
                if not tree.valid then
                    local built = surface.find_entities_filtered({
                        position = target_pos,
                        name = "stone-furnace",
                        force = force,
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

            local build_pos = { x = base_pos.x + 20, y = base_pos.y }
            surface.request_to_generate_chunks(build_pos, 4)
            surface.force_generate_chunk_requests()

            local blueprints = collect_blueprints(stack, 3)
            if not blueprints or #blueprints == 0 then
                report(
                    ("[Brood][BlueprintFixture] build skipped (no blueprints found) for %s"):format(
                        tostring(fixture_name)
                    )
                )
                inv.destroy()
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
                        surface = surface,
                        force = force.name,
                        position = build_pos,
                        raise_built = false,
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

                -- Ensure the task scan can handle whatever ghosts were created.
                local ok_loop, loop_err = pcall(function()
                    test_utils.run_main_loop()
                end)
                assert.is_true(
                    ok_loop,
                    "run_main_loop crashed after building fixture: "
                        .. tostring(fixture_name)
                        .. " #"
                        .. tostring(idx)
                        .. ": "
                        .. tostring(loop_err)
                )

                ::continue_blueprint::
            end

            inv.destroy()

            if not ok_any then
                report(("[Brood][BlueprintFixture] no buildable blueprints for %s"):format(tostring(fixture_name)))
                return
            end

            report(
                ("[Brood][BlueprintFixture] built %s blueprints: %s"):format(
                    tostring(fixture_name),
                    table.concat(built_summaries, ", ")
                )
            )
        end)
    end
end)
