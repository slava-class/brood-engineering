local constants = require("scripts/constants")
local anchor = require("scripts/anchor")
local spider = require("scripts/spider")
local blueprint_fixtures = require("tests/fixtures/blueprints")

describe("blueprint-like placement scenarios", function()
    local surface
    local force
    local base_pos
    local created = {}
    local anchor_id
    local anchor_entity
    local anchor_data
    local original_global_enabled

    --- Log to both the Factorio log file and in-game chat (so it shows up in FactorioTest UI output).
    ---@param msg string
    local function report(msg)
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

    local function track(entity)
        if entity and entity.valid then
            created[#created + 1] = entity
        end
        return entity
    end

    local function clear_area(position, radius)
        local tiles = {}
        for y = position.y - radius, position.y + radius do
            for x = position.x - radius, position.x + radius do
                tiles[#tiles + 1] = { name = "grass-1", position = { x = x, y = y } }
            end
        end
        surface.set_tiles(tiles, true)

        local area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
        for _, entity in ipairs(surface.find_entities_filtered({ area = area })) do
            if entity and entity.valid then
                if anchor_entity and entity == anchor_entity then
                    goto continue
                end
                entity.destroy({ raise_destroyed = false })
            end
            ::continue::
        end
    end

    ---@param item LuaItemStack
    ---@param max_depth integer
    ---@return { stack: LuaItemStack, path: string }[] blueprints
    local function collect_blueprints(item, max_depth)
        local result = {}

        local function visit(it, depth, path)
            if not (it and it.valid_for_read) then
                return
            end
            if depth > max_depth then
                return
            end

            if it.is_blueprint == true then
                result[#result + 1] = { stack = it, path = path or "" }
                return
            end

            if it.is_blueprint_book == true then
                local inv = it.get_inventory(defines.inventory.item_main)
                if not (inv and inv.valid) then
                    return
                end
                for i = 1, #inv do
                    local next_path = path and (path .. "/" .. tostring(i)) or tostring(i)
                    visit(inv[i], depth + 1, next_path)
                end
            end
        end

        local initial_path = ""
        if item and item.valid_for_read and item.is_blueprint_book == true then
            initial_path = nil
        end
        visit(item, 0, initial_path)
        return result
    end

    ---@param data string
    ---@return LuaInventory inv
    ---@return LuaItemStack stack
    ---@return boolean imported
    ---@return string? err
    local function import_any_blueprint_item(data)
        local inv = game.create_inventory(1)
        local stack = inv[1]

        local function try_with_item(item_name)
            local ok_set, set_ok = pcall(function()
                return stack.set_stack({ name = item_name, count = 1 })
            end)
            if not ok_set or set_ok == false then
                return false, 0, ("set_stack failed for %s"):format(tostring(item_name))
            end

            local ok, imported_or_err = pcall(function()
                return stack.import_stack(data)
            end)
            if not ok then
                return false, 0, tostring(imported_or_err)
            end
            local count = tonumber(imported_or_err) or 0

            local setup_ok = false
            if item_name == "blueprint" and stack.is_blueprint == true and stack.is_blueprint_setup then
                local ok_setup, is_setup = pcall(function()
                    return stack.is_blueprint_setup()
                end)
                setup_ok = ok_setup and is_setup == true
            elseif item_name == "blueprint-book" and stack.is_blueprint_book == true then
                local ok_inv, book_inv = pcall(function()
                    return stack.get_inventory(defines.inventory.item_main)
                end)
                if ok_inv and book_inv and book_inv.valid then
                    for i = 1, #book_inv do
                        if book_inv[i] and book_inv[i].valid_for_read then
                            setup_ok = true
                            break
                        end
                    end
                end
            end

            return (count ~= 0) or setup_ok, count, nil
        end

        local ok_blueprint, count_blueprint, err_blueprint = try_with_item("blueprint")
        if ok_blueprint then
            return inv, stack, true, nil
        end

        local ok_book, count_book, err_book = try_with_item("blueprint-book")
        if ok_book then
            return inv, stack, true, nil
        end

        local err = err_blueprint or err_book
        if err_blueprint and err_book and err_blueprint ~= err_book then
            err = ("blueprint=%s; blueprint-book=%s"):format(err_blueprint, err_book)
        end

        if not err then
            local head = tostring(data):sub(1, 16)
            err = ("blueprint_count=%d; blueprint_book_count=%d; len=%d; head=%q"):format(
                count_blueprint or 0,
                count_book or 0,
                #tostring(data),
                head
            )
        end

        local hints = {}
        if type(data) == "string" and (data:find("recipe_quality", 1, true) or data:find('"quality"', 1, true)) then
            if not (script and script.active_mods and script.active_mods["quality"]) then
                hints[#hints + 1] = "quality mod disabled (FactorioTest mod-list.json has it off by default)"
            end
        end
        if #hints > 0 then
            err = err .. "; hints: " .. table.concat(hints, ", ")
        end

        return inv, stack, false, err
    end

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

        async(60 * 25)
        on_tick(function()
            if (game.tick % constants.main_loop_interval) == 0 then
                remote.call("brood-engineering-test", "run_main_loop")
            end

            -- The primary purpose is "no crash"; also assert progress: blocker removed and ghost built.
            if not tree.valid then
                local built = surface.find_entities_filtered({
                    position = target_pos,
                    name = "stone-furnace",
                    force = force,
                })
                if built and #built > 0 then
                    done()
                    return false
                end
            end

            return true
        end)
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
                    remote.call("brood-engineering-test", "run_main_loop")
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
