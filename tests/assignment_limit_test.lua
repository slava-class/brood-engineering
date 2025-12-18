local constants = require("scripts/constants")
local test_utils = require("tests/test_utils")

test_utils.describe_remote_test("assignment limiter", function(ctx)
    before_each(function()
        local original_max = constants.max_assignments_per_tick
        ctx.defer(function()
            constants.max_assignments_per_tick = original_max
        end)

        remote.call("brood-engineering-test", "reset_assignment_limits")
    end)

    test("caps assignments per anchor per tick", function()
        constants.max_assignments_per_tick = 2

        assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "s1", { id = "t1" }, "a1"))
        assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "s2", { id = "t2" }, "a1"))
        assert.is_false(remote.call("brood-engineering-test", "try_assign_task_capped", "s3", { id = "t3" }, "a1"))
        assert.are_equal(2, remote.call("brood-engineering-test", "get_assignment_count", "a1"))
    end)

    test("tracks caps independently per anchor", function()
        constants.max_assignments_per_tick = 1

        assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "s1", { id = "t1" }, "a1"))
        assert.is_false(remote.call("brood-engineering-test", "try_assign_task_capped", "s2", { id = "t2" }, "a1"))

        assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "try_a2", { id = "t3" }, "a2"))
        assert.is_false(remote.call("brood-engineering-test", "try_assign_task_capped", "try_a2b", { id = "t4" }, "a2"))

        assert.are_equal(1, remote.call("brood-engineering-test", "get_assignment_count", "a1"))
        assert.are_equal(1, remote.call("brood-engineering-test", "get_assignment_count", "a2"))
    end)

    test("resets cap on the next tick", function()
        constants.max_assignments_per_tick = 1

        assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "s1", { id = "t1" }, "a1"))
        assert.is_false(remote.call("brood-engineering-test", "try_assign_task_capped", "s2", { id = "t2" }, "a1"))

        after_ticks(1, function()
            assert.are_equal(0, remote.call("brood-engineering-test", "get_assignment_count", "a1"))
            assert.is_true(remote.call("brood-engineering-test", "try_assign_task_capped", "s3", { id = "t3" }, "a1"))
            assert.are_equal(1, remote.call("brood-engineering-test", "get_assignment_count", "a1"))
        end)
    end)
end)
