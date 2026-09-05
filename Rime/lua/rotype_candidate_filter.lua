local M = {}

local function can_lead(candidate)
  return candidate.type ~= "rotype_english_echo"
      and not candidate.text:match("^[%z\1-\127]*$")
end

-- Preserve the established ordering, but only pull as much as the consumer
-- needs. In particular, the first Chinese page need not locate a distant echo.
function M.func(input)
  local iterator, state, control = input:iter()
  local ended = false
  local function take()
    while not ended do
      local candidate = iterator(state, control)
      control = candidate
      if not candidate then ended = true; return nil end
      if candidate.type ~= "rotype_translation" and candidate.type ~= "rotype_dynamic_translation" then
        return candidate
      end
    end
  end

  local first = take()
  if not first then return end
  local primary, echo
  local buffered = {}
  if can_lead(first) then
    primary = first
  else
    -- Until both a promotable candidate and an echo exist, the original order
    -- might still be required. This ambiguous prefix cannot safely be streamed.
    local prefix = {first}
    local echo_index = first.type == "rotype_english_echo" and 1 or nil
    local primary_index
    while not (echo_index and primary_index) do
      local candidate = take()
      if not candidate then
        for _, value in ipairs(prefix) do yield(value) end
        return
      end
      table.insert(prefix, candidate)
      if not echo_index and candidate.type == "rotype_english_echo" then echo_index = #prefix end
      if not primary_index and can_lead(candidate) then primary_index = #prefix end
    end
    primary, echo = prefix[primary_index], prefix[echo_index]
    for index, candidate in ipairs(prefix) do
      if index ~= primary_index and index ~= echo_index then table.insert(buffered, candidate) end
    end
  end

  local cursor, buffered_count = 1, #buffered
  local function next_regular()
    if cursor <= buffered_count then
      local candidate = buffered[cursor]
      buffered[cursor] = nil
      cursor = cursor + 1
      return candidate
    end
    return take()
  end

  yield(primary)
  local leading = 1
  while leading < 7 do
    local candidate = next_regular()
    if not candidate then break end
    if not echo and candidate.type == "rotype_english_echo" then
      echo = candidate
    else
      yield(candidate)
      leading = leading + 1
    end
  end

  -- Only a consumer asking for position eight pays for locating a late echo.
  -- With no echo this scan may reach the end; preserve order rather than guess.
  local before_echo = {}
  while not echo do
    local candidate = next_regular()
    if not candidate then break end
    if candidate.type == "rotype_english_echo" then echo = candidate
    else table.insert(before_echo, candidate) end
  end
  if echo then yield(echo) end
  for index = 1, #before_echo do
    local candidate = before_echo[index]
    before_echo[index] = nil
    yield(candidate)
  end
  while true do
    local candidate = next_regular()
    if not candidate then return end
    yield(candidate)
  end
end

return M
