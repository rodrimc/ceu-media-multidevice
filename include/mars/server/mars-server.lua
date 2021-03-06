MARS = {
  onConnect = nil,
  onDisconnect = nil,
  onOutputEvent = nil,
  peers = {},
  interfaces = nil,
  incoming_payload = nil,
}

function map (instFrom, evtFrom, instTo, evtTo, transform)
  if instFrom.__mapping [evtFrom] == nil then
    instFrom.__mapping [evtFrom] = {}
  end

  table.insert (instFrom.__mapping[evtFrom],
    {
      to = instTo.id,
      evt = evtTo,
      transform = transform
    })
end

function mapping (M)
  MARS.interfaces = type(M) == 'table' and M or nil
end
