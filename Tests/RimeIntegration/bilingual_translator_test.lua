local emitted = {}

function Candidate(candidate_type, start_pos, end_pos, text, comment)
  return {
    type = candidate_type,
    start = start_pos,
    _end = end_pos,
    text = text,
    comment = comment,
  }
end

function yield(candidate)
  table.insert(emitted, candidate)
end

local translator = dofile("Rime/lua/rotype_bilingual_translator.lua")
local segment = { start = 0, _end = 5 }

local function translate(input)
  emitted = {}
  translator.func(input, segment)
  return emitted
end

local from_pinyin = translate("ni'hao")
assert(#from_pinyin == 1)
assert(from_pinyin[1].text == "hello")
assert(from_pinyin[1].comment == "〔中→英〕")
assert(from_pinyin[1].type == "rotype_translation")

local flypy_cases = {
  ["ni'hc"] = "hello",
  xpxp = "thanks",
  zcuhhc = "good morning",
  wjaj = "good night",
  zdjm = "goodbye",
  uijp = "world",
  uurufa = "input method",
  vswf = "Chinese",
  ykwf = "English",
  ceui = "test",
}

for input, expected in pairs(flypy_cases) do
  local from_flypy = translate(input)
  assert(#from_flypy >= 1)
  assert(from_flypy[1].text == expected)
  assert(from_flypy[1].comment == "〔中→英〕")
end

local from_english = translate("HELLO")
assert(#from_english == 1)
assert(from_english[1].text == "你好")
assert(from_english[1].comment == "〔英→中〕")

local unknown = translate("unknownword")
assert(#unknown == 0)

print("bilingual translator tests passed")
