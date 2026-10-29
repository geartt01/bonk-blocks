--[[
	Signal: tiny pure-Luau signal (no BindableEvents).
	Handlers run via task.spawn, so a yielding handler never blocks Fire.
]]

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

function Signal.new()
	return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_callback = callback,
	}, Connection)
	table.insert(self._connections, connection)
	return connection :: any
end

function Signal:Once(callback: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
end

return Signal
