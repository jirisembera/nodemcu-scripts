-- TCP/IP remote console. Allows to interact with NodeMCU over wifi in a similar way as over serial port.
-- Don't forget to send AUTH_MAGIC after connecting. Tested with Raw socket connection via PuTTY.
-- 
-- required modules: net, node

-- CONFIG
local LISTEN_PORT = 65432
local CONNECTION_TIMEOUT = 1200 -- 20min
local AUTH_MAGIC = "<secret>" -- have to send 
local EVAL_INPUT = true --use node.input() instead of loadstring()
                        --  node.input() is closer to serial console but does not allow to report errors

-- LOCALS
local authorized = {}

function _node_input(val)
    EVAL_INPUT = val
end

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
            sck:send("Welcome! Use _node_input(false) to switch to loadstring() evaluation. _node_input(true) switches back to node.input() evaluation (default)")
        end
        return
    end

    -- process data
    if EVAL_INPUT then
        node.input(data)
    else
        local success, error = pcall(loadstring(data))--pcall(node.input, data)
        if not success then
            sck:send(error)
        end
    end
end

function on_close(sck)
    authorized[sck] = nil
    print("disconnected")
end

pcall( function() remote_console:close() end ) -- try to close previous server instance
remote_console = net.createServer(net.TCP, CONNECTION_TIMEOUT)

if remote_console then
    remote_console:listen(LISTEN_PORT, function(conn)
        conn:on("receive", on_receive)
        conn:on("disconnection", on_close)
    end)
end
