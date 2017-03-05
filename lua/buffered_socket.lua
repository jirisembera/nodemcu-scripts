-- buffered_socket.lua - net.socket wrapper that allows comfortably call send() without having to deal with
--   "sent" callbacks (cannot send another message unless the previous has been sent...)


BufferedSocket = {}
BufferedSocket.__index = BufferedSocket

-- allow construction via directly calling the meta-table
setmetatable(BufferedSocket, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

local socket_cache = {} -- BufferedSocket cache

-- disconnect callback
local function _on_disconnect( sck, error_code )
    socket_cache[sck] = nil
    if self._disconnection_callback then
        self._disconnection_callback(self, error_code)
    end
end

-- actual constructor
function BufferedSocket.new(socket)
    if socket_cache[socket] ~= nil then
        return socket_cache[socket]
    end

    local self = setmetatable({}, BufferedSocket)
    
    self._socket = socket
    self._queue = {} -- messages to send
    self._send_pending = false -- a message is currently being sent
    self._all_sent_callback = nil -- callback fired when self._queue is empty
    self._disconnection_callback = nil -- on disconnect callback

    socket:on("disconnection", _on_disconnect)

    socket_cache[socket] = self -- store in cache
    return self
end

function BufferedSocket:send(data)
    if self._send_pending then
        table.insert(self._queue, 1, data) -- enqueue
    else
        self._send_pending = true
        self._socket:send(data, function(sck)
            if #self._queue > 0 then  -- send next message
                local data = table.remove(self._queue) 
                sck:send(data)
            else -- all sent
                self._send_pending = false
                if self._all_sent_callback then
                    self._all_sent_callback(self) -- notify everything has been sent
                end
            end
        end)
    end
end

function BufferedSocket:on(event, callback)
    if event == "sent" then -- capture sent event - fire when everything has been sent
        self._all_sent_callback = callback
    elseif event == "disconnection" then
        self._disconnection_callback = callback
    else -- pass other events to underlying socket
        self._socket:on(event, function(sck, arg2)
            callback(BufferedSocket(sck), arg2)
        end)
    end
end

-- Returns socket passed in constructor
function BufferedSocket:get_socket()
    return self._socket
end

-- Returns socket passed in constructor
function BufferedSocket:close()
    return self._socket:close()
end


