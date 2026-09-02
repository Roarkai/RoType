local emitted = {}

function Candidate(candidate_type, start_pos, end_pos, text, comment)
  return {
    type = candidate_type,
    _start = start_pos,
    _end = end_pos,
    text = text,
    comment = comment,
    quality = 1,
  }
end

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

local function percent_encode(value)
  return (value:gsub(".", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local temporary_dir = "/tmp/rotype-dynamic-filter-test"
os.execute("rm -rf " .. temporary_dir)
assert(os.execute("mkdir -p " .. temporary_dir))

local context = { input = "ni'zai'gan'ma", refreshed = 0 }
function context:is_composing() return true end
function context:refresh_non_confirmed_composition() self.refreshed = self.refreshed + 1 end

local env = { engine = { context = context } }
local filter = dofile("Rime/lua/rotype_dynamic_bilingual_filter.lua")
filter.init(env)
env.bridge_dir = temporary_dir
env.request_path = temporary_dir .. "/request-test.txt"
env.response_path = temporary_dir .. "/response-test.txt"

local chinese = Candidate("phrase", 0, 13, "你在干嘛", "")
emitted = {}
filter.func(translation({ chinese }), env)
assert(#emitted == 1)
assert(emitted[1].text == "你在干嘛")
local request = assert(io.open(env.request_path, "rb")):read("*a")
assert(request:find(percent_encode(context.input), 1, true))
assert(request:find(percent_encode(chinese.text), 1, true))

local response = assert(io.open(env.response_path, "wb"))
response:write(table.concat({
  "v1",
  percent_encode(context.input),
  percent_encode(chinese.text),
  percent_encode("zh-en"),
  percent_encode(chinese.text),
  percent_encode("What are you doing?"),
  "",
}, "\n"))
response:close()

emitted = {}
filter.func(translation({ chinese }), env)
assert(#emitted == 2)
assert(emitted[1].text == "你在干嘛")
assert(emitted[2].text == "What are you doing?")
assert(emitted[2].comment == "〔中→英〕")

context.input = "nihao"
emitted = {}
filter.func(translation({ Candidate("phrase", 0, 5, "你好", "") }), env)
assert(#emitted == 1) -- stale response must not leak into a new composition.

os.remove(env.response_path)
context.input = "genbenmeiyou"
local pinyin_echo = Candidate("rotype_english_echo", 0, 13, "genbenmeiyou", "〔EN〕")
local chinese_phrase = Candidate("phrase", 0, 13, "根本没有", "")
emitted = {}
filter.func(translation({ pinyin_echo, chinese_phrase }), env)
assert(emitted[1].text == "根本没有")
assert(emitted[2].text == "genbenmeiyou")
local pinyin_request = assert(io.open(env.request_path, "rb")):read("*a")
assert(pinyin_request:find(percent_encode(chinese_phrase.text), 1, true))

local pinyin_response = assert(io.open(env.response_path, "wb"))
pinyin_response:write(table.concat({
  "v1",
  percent_encode(context.input),
  percent_encode(chinese_phrase.text),
  percent_encode("zh-en"),
  percent_encode(chinese_phrase.text),
  percent_encode("Not at all"),
  "",
}, "\n"))
pinyin_response:close()
emitted = {}
filter.func(translation({ pinyin_echo, chinese_phrase }), env)
assert(emitted[1].text == "根本没有")
assert(emitted[2].text == "Not at all")
assert(emitted[2].comment == "〔中→英〕")
assert(emitted[3].text == "genbenmeiyou")

local refresh = dofile("Rime/lua/rotype_dynamic_refresh.lua")
assert(refresh.func({ repr = function() return "F18" end }, env) == 1)
assert(context.refreshed == 1)
assert(refresh.func({ repr = function() return "a" end }, env) == 2)

os.execute("rm -rf " .. temporary_dir)
print("dynamic bilingual filter tests passed")
