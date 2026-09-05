package.path = "Rime/lua/?.lua;" .. package.path
local emitted = {}
function yield(candidate) table.insert(emitted, candidate) end
local function candidate(kind, text)
  return {type = kind, text = text, _start = 0, _end = 5, quality = 1, comment = ""}
end
local function stream(values)
  return {iter = function()
    local i = 0
    return function() i = i + 1; return values[i] end
  end}
end

for _, name in ipairs({"rotype_dynamic_bilingual_filter", "rotype_candidate_filter"}) do
  local filter = require(name)
  local writes, reads = 0, 0
  local context = {input = "nihao"}
  function context:get_property(key) return key == "rotype_session_id" and "retired-fixture" or "" end
  function context:set_property() writes = writes + 1 end
  local env = {engine = {context = context}}
  if filter.init then filter.init(env) end
  local echo = candidate("rotype_english_echo", "nihao")
  local values = {echo}
  local chinese = {}
  for _, text in ipairs({"你好", "你号", "你", "尼", "拟", "泥", "逆", "妮", "腻"}) do
    local value = candidate("phrase", text)
    table.insert(values, value)
    table.insert(chinese, value)
  end
  table.insert(values, candidate("rotype_translation", "hello"))
  table.insert(values, candidate("rotype_translation", "second static translation"))
  table.insert(values, candidate("rotype_dynamic_translation", "stale dynamic translation"))
  local original_open = io.open
  io.open = function() reads = reads + 1; return nil end
  emitted = {}
  filter.func(stream(values), env)
  io.open = original_open
  assert(reads == 0, "retired response files must never be read")
  assert(writes == 0, "ranking must not publish obsolete translation properties")
  assert(#emitted == 10, "only original candidates and the English echo remain")
  for i = 1, 7 do assert(emitted[i] == chinese[i]) end
  assert(emitted[8] == echo)
  assert(emitted[9] == chinese[8] and emitted[10] == chinese[9])

  local english = candidate("table", "hello")
  emitted = {}
  filter.func(stream({english, candidate("rotype_translation", "你好")}), env)
  assert(#emitted == 1 and emitted[1] == english)
  local accented_echo = candidate("rotype_english_echo", "résumé")
  emitted = {}
  filter.func(stream({accented_echo}), env)
  assert(#emitted == 1 and emitted[1] == accented_echo, "an echo must never demote and duplicate itself")
  emitted = {}
  filter.func(stream({}), env)
  assert(#emitted == 0)
end

-- Old custom schema imports still load, but cannot translate, refresh or commit.
emitted = {}
require("rotype_bilingual_translator").func("nihao", {start = 0, _end = 5})
assert(#emitted == 0)
for _, name in ipairs({"rotype_dynamic_refresh", "rotype_full_translation_commit"}) do
  for _, key in ipairs({"F18", "space", "9"}) do
    assert(require(name).func({repr = function() return key end}, {}) == 2)
  end
end
print("candidate ranking and inert legacy entry points passed")
