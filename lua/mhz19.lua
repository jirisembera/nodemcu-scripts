-- Library for reading CO2 levels from MH-Z19 sensor
-- Sample usage:
-- > sensor = MHZ19()          -- init sensor on UART
-- > sensor:read_value(print)  -- read temperature and print it to console
-- 
-- required modules: uart
-- TODO: Support for other sensor commands (calibrate span point)
--       data validation (last byte == (invert(byte1+...+7))+1)
-- Based on https://github.com/asantoni/brewbot/blob/master/brewbot.lua
-- Sensor doc: http://eleparts.co.kr/data/design/product_file/SENSOR/gas/MH-Z19_CO2%20Manual%20V2.pdf

MHZ19 = {}
MHZ19.__index = MHZ19

-- allow construction via directly calling the meta-table
setmetatable(MHZ19, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- actual constructor
function MHZ19.new()
    local self = setmetatable({}, MHZ19)
    self._last_value = 0

    uart.setup(0, 9600, 8, uart.PARITY_NONE, uart.STOPBITS_1, 0)
        
    return self
end

function MHZ19:read_value(callback)
    uart.on("data", 9, function(data) 
        if string.byte(data, 1) == 0xFF and
            string.byte(data, 2) == 0x86 then
                local high_level_conc = string.byte(data, 3)
                local low_level_conc = string.byte(data, 4)
                self._last_value = high_level_conc * 256 + low_level_conc
                if callback then
                    callback( self._last_value )
                end
            end
    end, 0)

    uart.write(0, 0xFF, 0x01, 0x86,0x00,0x00,0x00,0x00,0x00, 0x79)

    return self._last_value
end

function MHZ19:last_value()
    return self._last_value
end

function MHZ19:calibrate_zero_point()
    uart.write(0, 0xFF, 0x01, 0x87,0x00,0x00,0x00,0x00,0x00, 0x78)
end
