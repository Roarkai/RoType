-- Frozen step-9 ordering oracle, used only by tests/benchmarks, never shipped.
local M = {}

-- Candidate ordering only. Translation belongs to the native action row.
function M.func(input)
  local candidates = {}
  local echo_index, primary_index
  for candidate in input:iter() do
    -- Ignore retired translators even when imported by a custom schema.
    if candidate.type ~= "rotype_translation" and candidate.type ~= "rotype_dynamic_translation" then
      table.insert(candidates, candidate)
      if candidate.type == "rotype_english_echo" and not echo_index then
        echo_index = #candidates
      end
      if not primary_index and candidate.type ~= "rotype_english_echo"
          and not candidate.text:match("^[%z\1-\127]*$") then
        primary_index = #candidates
      end
    end
  end
  if not echo_index or not primary_index then
    for _, candidate in ipairs(candidates) do yield(candidate) end
    return
  end

  -- Preserve the existing Chinese-first order and raw English echo position.
  -- Deliberately keep eager traversal until the next measured optimization.
  local regular = {candidates[primary_index]}
  for index, candidate in ipairs(candidates) do
    if index ~= primary_index and index ~= echo_index then table.insert(regular, candidate) end
  end
  local leading = math.min(7, #regular)
  for index = 1, leading do yield(regular[index]) end
  yield(candidates[echo_index])
  for index = leading + 1, #regular do yield(regular[index]) end
end

return M
