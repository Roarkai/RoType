local emitted = {}

function yield(candidate)
  table.insert(emitted, candidate)
end

local function translation(candidates)
  return {
    iter = function()
      local index = 0
      return function()
        index = index + 1
        return candidates[index]
      end
    end,
  }
end

local filter = dofile("Rime/lua/rotype_simplified_only_filter.lua")
filter.func(translation({
  { text = "你好" },
  { text = "妳好" },
  { text = "我很开心" },
  { text = "Hello" },
}))

assert(#emitted == 3)
assert(emitted[1].text == "你好")
assert(emitted[2].text == "我很开心")
assert(emitted[3].text == "Hello")
print("simplified-only filter tests passed")
