local M = {}

local function percent_encode(value)
  return (value:gsub(".", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function percent_decode(value)
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function parse_lines(payload)
  local lines = {}
  for line in (payload .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local payload = file:read("*a")
  file:close()
  return payload
end

local function write_request(env, raw_input, top_candidate)
  local payload = table.concat({
    "v1",
    percent_encode(raw_input),
    percent_encode(top_candidate),
    "",
  }, "\n")
  local temporary_path = env.request_path .. ".tmp"
  local file = io.open(temporary_path, "wb")
  if not file then return end
  file:write(payload)
  file:close()
  os.rename(temporary_path, env.request_path)
end

local function matching_response(env, raw_input, top_candidate)
  local payload = read_file(env.response_path)
  if not payload then return nil end
  local lines = parse_lines(payload)
  if #lines < 6 or lines[1] ~= "v1" then return nil end
  if percent_decode(lines[2]) ~= raw_input then return nil end
  if percent_decode(lines[3]) ~= top_candidate then return nil end
  return {
    direction = percent_decode(lines[4]),
    source = percent_decode(lines[5]),
    translation = percent_decode(lines[6]),
  }
end

function M.init(env)
  local default_dir = (os.getenv("HOME") or "") .. "/Library/Caches/RoType/TranslationBridge"
  env.bridge_dir = os.getenv("ROTYPE_TRANSLATION_BRIDGE_DIR") or default_dir
  local session_id = tostring(env.engine):gsub("[^%w]", "")
  env.request_path = env.bridge_dir .. "/request-" .. session_id .. ".txt"
  env.response_path = env.bridge_dir .. "/response-" .. session_id .. ".txt"
end

function M.func(input, env)
  local raw_input = env.engine.context.input or ""
  local candidates = {}

  for candidate in input:iter() do
    table.insert(candidates, candidate)
  end

  if #candidates == 0 then return end

  local primary_index = 1
  if candidates[1].type == "rotype_english_echo" then
    for index = 2, #candidates do
      if not candidates[index].text:match("^[%z\1-\127]*$") then
        primary_index = index
        break
      end
    end
  end

  local primary = candidates[primary_index]
  yield(primary)

  local response = matching_response(env, raw_input, primary.text)
  if response and response.translation ~= "" then
    local comment = response.direction == "en-zh" and "〔英→中〕" or "〔中→英〕"
    local translated = Candidate(
      "rotype_dynamic_translation",
      primary._start,
      primary._end,
      response.translation,
      comment
    )
    translated.quality = primary.quality
    yield(translated)
  else
    write_request(env, raw_input, primary.text)
  end

  for index, candidate in ipairs(candidates) do
    if index ~= primary_index then
      yield(candidate)
    end
  end
end

return M
