-- TCP/IP remote console. Allows to interact with NodeMCU over wifi in a similar way as over serial port.
-- Don't forget to send AUTH_MAGIC after connecting. Tested with Raw socket connection via PuTTY.
--
-- Known issues: Prompt character (">") gets sometimes sent twice (at least with Putty client).
--               It is caused by two on_receive events, one for entered string in console, second for \r\n
-- 
-- required modules: net, node, buffered_socket.lua

-- CONFIG
local LISTEN_PORT = 65432
local CONNECTION_TIMEOUT = 1200 -- 20min
local AUTH_MAGIC = "<secret>" -- have to send 

-- LOCALS
local authorized = {}

-- event handlers
function send_output(str)
    for sock, enabled in pairs(authorized) do
        if enabled then
            sock:send(str)
        end
    end
end

function on_receive(sck, data)
    -- auth check
    if authorized[sck] == nil then
        if data:sub(1, AUTH_MAGIC:len()) == AUTH_MAGIC then
            authorized[sck] = 1
            node.output(send_output, false) -- write result to both socket and serial
            sck:send("Welcome!\r\n> ")
        end
        return
    end

    -- process command
    local success, error = pcall(loadstring(data))--pcall(node.input, data)
    if not success then
        sck:send(error)
    end
    
    sck:send("\r\n> ")
end

function on_close(sck)
    authorized[sck] = nil
    print("disconnected")
end

pcall( function() remote_console:close() end ) -- try to close previous server instance
remote_console = net.createServer(net.TCP, CONNECTION_TIMEOUT)

if remote_console then
    remote_console:listen(LISTEN_PORT, function(conn)
        buff_conn = BufferedSocket(conn)
        
        buff_conn:on("receive", on_receive)
        buff_conn:on("disconnection", on_close)
    end)
end
