local M = {}

function M.func(key, env)
  if key:repr() == "F18" then
    if env.engine.context:is_composing() then
      env.engine.context:refresh_non_confirmed_composition()
    end
    return 1 -- kAccepted: consume the private refresh event.
  end
  return 2 -- kNoop
end

return M
