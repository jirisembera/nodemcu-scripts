-- Library for reading CO2 levels from MH-Z19 sensor
-- Sample usage:
-- > sensor = dofile("mhz19.lua") 
-- > sensor:read_value(print)      -- read temperature and print it to console
-- 
-- required modules: uart
-- TODO: data validation (last byte == (invert(byte1+...+7))+1)

-- Based on https://github.com/asantoni/brewbot/blob/master/brewbot.lua
-- Sensor doc: http://www.winsen-sensor.com/d/files/PDF/Infrared%20Gas%20Sensor/NDIR%20CO2%20SENSOR/MH-Z19%20CO2%20Ver1.0.pdf
--        and: http://www.winsen-sensor.com/d/files/infrared-gas-sensor/mh-z19b-co2-ver1_0.pdf

-- defaults
local CMD_READ = string.char(0xFF, 0x01, 0x86,0x00,0x00,0x00,0x00,0x00, 0x79)
local CMD_CALIBRATE_ZERO = string.char(0xFF, 0x01, 0x87,0x00,0x00,0x00,0x00,0x00, 0x78)
local CMD_CALIBRATE_SPAN = string.char(0xFF, 0x01, 0x88,0x07,0xD0,0x00,0x00,0x00, 0xA0)
local CMD_ABC_ON = string.char(0xFF, 0x01, 0x79,0xA0,0x00,0x00,0x00,0x00, 0x46)
local CMD_ABC_OFF = string.char(0xFF, 0x01, 0x79,0x00,0x00,0x00,0x00,0x00, 0x86)

local MHZ19 = {
    -- internal state
    _last_value = 0,
    _last_temp = -40,
    _tmr = tmr.create(),

    -- for UART settings backup
    _baud = 115200,
    _databits = 8,
    _parity = 0,
    _stopbits = 1
}

function MHZ19:_send_command(data, trigger_len, callback, timeout)
    -- backup uart config
    self._baud, self._databits, self._parity, self._stopbits = uart.getconfig(0)

    function restore_uart()
        print("restore uart")
        uart.on("data")
        uart.alt(0) -- restore UART setup after at most 1s
        uart.setup(0, self._baud, self._databits, self._parity, self._stopbits, 1)
        self._tmr:stop()
    end

    -- setup restore
    if timeout and (timeout > 0) then
        tmr.alarm(self._tmr, timeout, tmr.ALARM_SINGLE, restore_uart)
    else
        timeout = nil
    end

    -- setup data callback
    if trigger_len and (trigger_len > 0) and callback then
        uart.on("data", trigger_len, function(data)
            restore_uart()
            callback(data)
        end, 0)
    end

    uart.alt(1) -- switch UART to alternative pins
    uart.setup(0, 9600, 8, uart.PARITY_NONE, uart.STOPBITS_1, 0)
    
    uart.write(0, data)

    if timeout == nil then -- revert immediately
        restore_uart()
    end
end

function MHZ19:read_value(callback)
    function data_callback(data)
        if (data:byte(1) ~= 255) and (data:byte(2) == 255) then
            data = data:sub(2) -- workaround for debugging (sometimes there is LF byte left over from interactive console
        end
    
        if string.byte(data, 1) == 0xFF and
            string.byte(data, 2) == 0x86 then
                local high_level_conc = string.byte(data, 3)
                local low_level_conc = string.byte(data, 4)
                self._last_value = high_level_conc * 256 + low_level_conc
                self._last_temp = string.byte(data, 5) - 40
                
                if callback then
                    callback( self._last_value, self._last_temp )
                end
            end
    end

    self:_send_command(
        CMD_READ,
        9,
        data_callback,
        1000)

    return self._last_value, self._last_temp
end

function MHZ19:last_value()
    return self._last_value
end

function MHZ19:last_temp()
    return self._last_temp
end

function MHZ19:calibrate_zero_point()
    self:_send_command(CMD_CALIBRATE_ZERO)
end

--
function MHZ19:calibrate_span_point()
    self:_send_command(CMD_CALIBRATE_SPAN)
end

-- enable or disable automatic baseline correction
function MHZ19:set_abc(on)
    if on then
        self:_send_command(CMD_ABC_ON)
    else
        self:_send_command(CMD_ABC_OFF)
    end
end

return MHZ19
