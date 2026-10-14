local tests = {
    "tests/test_timer_core.lua",
    "tests/test_session.lua",
    "tests/test_persistence.lua",
    "tests/test_display.lua",
    "tests/test_splits.lua",
    "tests/test_batch.lua",
    "tests/test_recording_bridge.lua",
    "tests/test_shared_snapshot.lua",
    "tests/test_ui.lua",
}

for _, path in ipairs(tests) do
    dofile(path)
end

print("Timer tests passed")
