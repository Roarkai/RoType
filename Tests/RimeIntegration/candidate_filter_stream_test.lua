local current = dofile("Rime/lua/rotype_candidate_filter.lua")
local baseline = dofile("Tests/RimeIntegration/fixtures/eager_candidate_filter.lua")
function yield(value) coroutine.yield(value) end

local function collect(filter, values, limit)
  local consumed, result = 0, {}
  local input = {iter = function()
    local index = 0
    return function(state, previous)
      assert(state == values, "iterator state must be forwarded, as required by librime-lua")
      assert(previous == (index > 0 and values[index] or nil), "generic-for control value must be forwarded")
      index = index + 1
      if values[index] then consumed = consumed + 1 end
      return values[index]
    end, values
  end}
  local task = coroutine.create(function() filter.func(input) end)
  while coroutine.status(task) ~= "dead" and (not limit or #result < limit) do
    local ok, value = coroutine.resume(task)
    assert(ok, value)
    if value then table.insert(result, value) end
  end
  return result, consumed
end

local many = {}
for i = 1, 10000 do many[i] = {type = "phrase", text = "候选" .. i} end
many[10000] = {type = "rotype_english_echo", text = "example"}
local first, consumed = collect(current, many, 5)
assert(#first == 5 and first[1] == many[1] and first[5] == many[5])
assert(consumed == 5, "first-page display must not traverse the tail to find an echo")

local complete = collect(current, many)
assert(#complete == 10000 and complete[8] == many[10000] and complete[9] == many[8])
local echo = {type = "rotype_english_echo", text = "raw"}
local shared_cases = {
  {echo, many[1], echo},
  {many[1], many[2], many[3]}, -- no echo, order must stay unchanged
  {{type = "phrase", text = "word"}, echo, many[1]},
}
for _, values in ipairs(shared_cases) do
  local actual, expected = collect(current, values), collect(baseline, values)
  assert(#actual == #expected)
  for i = 1, #actual do assert(actual[i] == expected[i]) end
end

-- Freeze the pre-optimization ordering as an independent differential oracle.
-- This fixture is test-only and is never included in the product payload.
math.randomseed(87123)
for attempt = 1, 600 do
  local values = {}
  for i = 1, math.random(0, 90) do
    local kind = ({"phrase", "table", "rotype_english_echo", "rotype_translation", "rotype_dynamic_translation"})[math.random(5)]
    local text = ({"word", "中文", "résumé"})[math.random(3)] .. i
    values[i] = {type = kind, text = text}
  end
  local actual = collect(current, values)
  local expected = collect(baseline, values)
  assert(#actual == #expected, "candidate count changed in case " .. attempt)
  for i = 1, #actual do assert(actual[i] == expected[i], "candidate ordering changed in case " .. attempt) end
end
print("lazy first-page consumption and 600 differential ordering cases passed")
