local M = {}

-- S0 intentionally keeps a tiny curated set. A later dictionary builder will
-- replace these tables after translation quality and licensing are accepted.
local zh_to_en = {
  nihao = { "hello" },
  xiexie = { "thanks", "thank you" },
  zaoshanghao = { "good morning" },
  wanan = { "good night" },
  zaijian = { "goodbye" },
  shijie = { "world" },
  shurufa = { "input method" },
  zhongwen = { "Chinese" },
  yingwen = { "English" },
  ceshi = { "test" },
}

-- Equivalent Xiaohe double-pinyin codes for the curated Chinese entries.
local flypy_zh_to_en = {
  nihc = { "hello" },
  xpxp = { "thanks", "thank you" },
  zcuhhc = { "good morning" },
  wjaj = { "good night" },
  zdjm = { "goodbye" },
  uijp = { "world" },
  uurufa = { "input method" },
  vswf = { "Chinese" },
  ykwf = { "English" },
  ceui = { "test" },
}

local en_to_zh = {
  hello = { "你好" },
  thanks = { "谢谢" },
  thankyou = { "谢谢" },
  goodmorning = { "早上好" },
  goodnight = { "晚安" },
  goodbye = { "再见" },
  world = { "世界" },
  inputmethod = { "输入法" },
  chinese = { "中文" },
  english = { "英文" },
  test = { "测试" },
}

local function normalize(input)
  return input:lower():gsub("[%s']", "")
end

local function emit(values, segment, comment)
  if not values then
    return
  end

  for _, text in ipairs(values) do
    local candidate = Candidate(
      "rotype_translation",
      segment.start,
      segment._end,
      text,
      comment
    )
    candidate.quality = 1.1
    yield(candidate)
  end
end

function M.func(input, segment)
  local key = normalize(input)
  emit(zh_to_en[key] or flypy_zh_to_en[key], segment, "〔中→英〕")
  emit(en_to_zh[key], segment, "〔英→中〕")
end

return M
