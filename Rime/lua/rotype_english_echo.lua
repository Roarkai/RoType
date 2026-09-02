local M = {}

function M.func(input, segment)
  if not input:match("^[A-Za-z][A-Za-z']+$") then return end
  local text = input:gsub("'", " ")
  local candidate = Candidate("rotype_english_echo", segment.start, segment._end, text, "〔EN〕")
  candidate.quality = 0.7
  yield(candidate)
end

return M
