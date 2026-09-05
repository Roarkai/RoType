-- Synthetic pull-boundary benchmark, not a measurement of macOS UI latency.
local filter = dofile(arg[1] or "Rime/lua/rotype_candidate_filter.lua")
function yield(value) coroutine.yield(value) end
local size = 10000
local repetitions = 40
for _, layout in ipairs({"chinese-first", "echo-first", "english-only"}) do
  local times, total_read, total_memory = {}, 0, 0
  for attempt = 1, repetitions do
    collectgarbage("collect")
    local before = collectgarbage("count")
    local read = 0
    local input = {iter = function()
      return function()
        if read == size then return nil end
        read = read + 1
        local echo = (layout == "echo-first" and read == 1) or
                     (layout ~= "echo-first" and read == size)
        return {type = echo and "rotype_english_echo" or "phrase",
                text = (echo or layout == "english-only") and "example" or ("候选" .. read)}
      end
    end}
    local task = coroutine.create(function() filter.func(input) end)
    local start = os.clock()
    for _ = 1, 5 do
      local ok, value = coroutine.resume(task)
      assert(ok and value)
    end
    times[#times + 1] = (os.clock() - start) * 1000
    total_read = total_read + read
    collectgarbage("collect")
    assert(coroutine.status(task) == "suspended") -- keep the unfinished stream rooted
    total_memory = total_memory + math.max(0, collectgarbage("count") - before)
  end
  table.sort(times)
  print(string.format("%s n=%d first=5 upstream=%.0f p50_ms=%.3f p95_ms=%.3f retained_kib=%.1f",
    layout, size, total_read / repetitions, times[math.ceil(repetitions * 0.5)],
    times[math.ceil(repetitions * 0.95)], total_memory / repetitions))
end
