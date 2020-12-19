-- A very simple web server
-- 
-- Usage:
--   * define your own request handler: function webserver:handle_request(socket, location, get_params, data, file_name)
--       * data: string with POST data (if any and if the length is within memory limit)
--       * file_name: name of temporary file holding the POST data (if any)
--       * return either Response.text(your_response_string) or Response.file(file_name) to serve a file from filesystem
--       * NOTE: Uploaded files are autmatically removed after the response is sent. To keep it, rename it.
--   * call webserver:start() to start listening on port 80
--
-- Features:
--   * GET parameters parsing (incl. %-encoding)
--   * store POST data (in memory or in file depending on length)
--   * serving text responses or files
--

-- TODO: handler should return status code

--
-- Config
--

local UPLOAD_PREFIX = "ws_tmp_"
local MAX_REQUEST_LENGTH = 3072 -- Max request length (request line + headers)
local MAX_IN_MEMORY_POST_LEN = 3072 -- max content length to be stored in RAM. temp file is used otherwise

--
-- Globals
--

webserver = {}

--
-- Utils
--

local function url_decode(url)
    local result = ""
    local rest = (url:gsub("([^%%]*)%%(%x%x)", function(plain, code)
        result = result .. plain .. string.char(tonumber(code, 16))
        return ""
    end))
    result = result .. rest
    return result
end

local function write_status_and_close(socket, status_code, status_text, body)
    print("Sending status", status_code, body)
    socket:send("HTTP/1.0 " .. status_code .. " " .. status_text 
            .. "\r\n\r\n" .. body)

    socket:on("sent", function(socket)
            socket:close()
        end)
    socket:on("receive", nil)
end

local function parse_get_params( location )
    local get_params = {}
    local get_params_start, _ = location:find("?")
    if get_params_start ~= nil then
        location:gsub("([^?&=]+)=([^&=]*)", function(key, value)
            key = url_decode(key)
            value = url_decode(value)
            get_params[key] = value
        end)
        
        location = location:sub(1, get_params_start - 1)
    end
    return location, get_params
end

local function parse_request( raw_headers )
    local lines = {}
    raw_headers:gsub("(.-)\r\n", function(line) table.insert(lines, line) end)
    if #lines == 0 then
        return nil
    end
    
    local reqline_parts = {}
    lines[1]:gsub("(%S+)", function(part) table.insert(reqline_parts, part) end)
    if #reqline_parts ~= 3 then
        return nil
    end
    
    if (reqline_parts[1] ~= "GET" and reqline_parts[1] ~= "POST") or reqline_parts[3] ~= "HTTP/1.1" then
        return nil
    end
    
    local location, get_params = parse_get_params(reqline_parts[2])

    -- get content length, thats the only thing that is important in req. headers
    for i=2,#lines do
        local content_length_name = lines[i]:match("^Content%-Length")
        if content_length_name ~= nil then
            content_length = lines[i]:match("%d+$")

            if content_length == nil then
                return nil
            end
            
            return location, get_params, tonumber(content_length)
        end
    end
    
    return location, get_params, 0
end

local function sent_handler(callback, file_to_delete)
    return function( socket )
        local success, data = pcall(callback)
        
        if not success or data == nil then
            socket:close()
            if file_to_delete ~= nil and file.exists(file_to_delete) then
                file.remove(file_to_delete) -- delete temporary upload
            end
            return
        end
        socket:send(data)
    end
end

--
-- Request handler
--

local Request = {}
Request.__index = Request

-- allow construction via directly calling the meta-table
setmetatable(Request, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- actual constructor
function Request.new(socket)
    local self = setmetatable({}, Request)
    
    self.socket = socket
    self.content_length = 0
    self.location = nil
    self.get_params = nil

    local header_buffer = ""
    local data_buffer = ""
    local output_file_name = UPLOAD_PREFIX .. random_string(8)
    local output_file = nil

    local function call_on_request( socket, data, file_name )
        if type(webserver.handle_request) == "function" then
            local success, response = pcall(webserver.handle_request, self, socket, self.location, self.get_params, data, file_name)
            if success then
                socket:on("sent", sent_handler(response, file_name))
                socket:send("HTTP/1.1 200 OK\r\n\r\n")
                return
            end
            print("handle_request failed", response)
            write_status_and_close(socket, 500, "Internal Server Error", "Request failed: " .. response)
        else
            write_status_and_close(socket, 500, "Internal Server Error", "Request handler not defined")
        end 
    end

    local function store_to_buffer(socket, data)
        print("store_to_buffer", data:len())
        data_buffer = data_buffer .. data

        if data_buffer:len() >= self.content_length then
            call_on_request( socket, data_buffer, nil )
        end
    end

    local function store_to_file(socket, data)
        print("store_to_file", data:len())
        if output_file == nil then
            output_file = file.open(output_file_name, "w")
            if output_file == nil then
                write_status_and_close(socket, 500, "Internal Server Error", "Failed to handle upload.")
                return
            end
        end

        if not output_file:write(data) then
            output_file.close()
            output_file = nil
            
            write_status_and_close(socket, 500, "Internal Server Error", "Failed to handle upload.")
            return
        end
        
        if output_file.seek("end") >= self.content_length then
            output_file.close()
            call_on_request( socket, nil, output_file_name )
        end
    end
    
    local function on_headers_data( socket, data )
        if data:len() + header_buffer:len() > MAX_REQUEST_LENGTH then
            write_status_and_close(socket, 500, "Internal Server Error", "Request too long")
            return
        end

        headers_end, data_start = data:find("\r\n\r\n")
        if data_start == nil then
            header_buffer = header_buffer .. data
            return
        end

        header_buffer = header_buffer .. data:sub(1, headers_end - 1)

        self.location, self.get_params, self.content_length = parse_request( header_buffer )
        header_buffer = nil

        if self.location == nil then
            write_status_and_close(socket, 400, "Bad Requestr", "The request could not be parsed")
            return
        end

        local request_data_handler = nil
        if self.content_length < MAX_IN_MEMORY_POST_LEN then
            request_data_handler = store_to_buffer
        else
            request_data_handler = store_to_file
        end

        socket:on("receive", request_data_handler )

        request_data_handler(socket, data:sub(data_start + 1))
    end

    socket:on("receive", on_headers_data )
        
    return self
end

--
-- Response generators:
--

Response = {}
Response.text = function (text)
    local sent = false
    return function()
        if sent then
            return nil
        else
            sent = true
            return text
        end
    end
end

Response.file = function (name)
    local text_file = file.open(name)
    return function()
        local text = text_file:read()
        if text == nil then
            text_file:close()      
        end
        return text
    end
end

--
-- Webserver main function
--

-- Start listening on port 80
function webserver:start()
    local function on_connect(sck)
        Request(sck)
    end

    -- cleanup old uploads
    for name,size in pairs(file.list()) do
        if string.sub(name,1,string.len(UPLOAD_PREFIX))==UPLOAD_PREFIX then
            print("Removing old temp file", name)
            file.remove(name)
        end
    end
    
    local srv = net.createServer(net.TCP, 1)
    srv:listen(80, on_connect)
end
