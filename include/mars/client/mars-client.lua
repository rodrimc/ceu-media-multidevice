MARS = {
  peer = nil,
  interfaces = {},
  instance = {},
  message = {
    args = nil
  }
}

function pack (evt, ...)
  local args = {...}
  local packed = {evt = evt, args = {}}
  for i = 1, #args do
    table.insert (packed.args, args[i])
  end
  return serialize (packed)
end
