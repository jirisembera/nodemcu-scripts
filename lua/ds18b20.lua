-- Library for reading temperature from DS12B20 sensor
-- Sample usage:
-- > sensor = DS12B20(5)       -- init sensor on pin 5
-- > sensor:read_value(print)  -- read temperature and print it to console
-- 
-- required modules: ow, tmr
-- TODO: Support for other sensor commands (Precision configuration, ROM access, etc.)

DS12B20 = {}
DS12B20.__index = DS12B20

-- allow construction via directly calling the meta-table
setmetatable(DS12B20, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- actual constructor
function DS12B20.new(pin)
    local self = setmetatable({}, DS12B20)
    self.timer = tmr.create()
    self.pin = pin
    self.callback = nil

    ow.setup(pin)
    local addr
    local count = 0
    repeat
        count = count + 1
        addr = ow.reset_search(self.pin)
        addr = ow.search(self.pin)
        tmr.wdclr()  -- reset watchdog... taken from the example in ow module docs
    until (addr ~= nil) or (count > 100)
    
    if addr == nil then
        print("Failed to locate 1wire device.")
        return nil
    end
    
    -- verify data CRC
    local crc = ow.crc8(string.sub(addr,1,7))
    if crc ~= addr:byte(8) then
        print("CRC is not valid!")
        return nil
    end

    -- check if the device is supported
    if (addr:byte(1) ~= 0x10) and (addr:byte(1) ~= 0x28) then
        print("Device family is not recognized.")
        return nil
    end

    self.addr = addr
    return self
end

-- Reads out data from scratchpad. Don't call directly, use read_value method instead.
function DS12B20:_readout(callback)
    if not callback then
        return
    end
    
    if ow.reset(self.pin) == 0 then
        print("DS12B20: Device not present, cannot read data.")
        return
    end
    
    ow.select(self.pin, self.addr)
    ow.write(self.pin,0xBE,1) -- Command to read Scratchpad

    -- receive scratchpad data
    local data = string.char(ow.read(self.pin))
    for i = 1, 8 do
        data = data .. string.char(ow.read(self.pin))
    end

    -- verify CRC
    crc = ow.crc8(string.sub(data,1,8))    
    if crc ~= data:byte(9) then
        print("DS12B20: CRC mismatch on readout.")
        return
    end

    -- convert to degrees
    local t = (data:byte(1) + data:byte(2) * 256) * 625
    local t1 = t / 10000 -- temperature in degrees
    local t2 = t % 10000 -- decimal part (useful for integer builds)

    -- call calback
    callback(t1, t2)
end

-- Reads out the temperatre. The thermometer has up to 750ms latency
-- so the result is returned asynchronously via callback
-- 
-- @param callback Function to call when readout is finished. The callback receives 2 values:
--        measured value in °C and decimal part of the temperature (useful for non-float builds).
function DS12B20:read_value(callback)
    -- issue Convert T command
    if ow.reset(self.pin) == 0 then
        print("DS12B20: Device not present, cannot read data.")
        return false
    end
    
    ow.select(self.pin, self.addr)
    ow.write(self.pin, 0x44, 1) -- issue readout command
    
    if not tmr.alarm(self.timer,
            800, -- 800 ms timeout (the data should be ready within 750ms)
            tmr.ALARM_SINGLE, -- oneshot timer
            function() self:_readout(callback, as_string) end) then -- callback to read-out data and call user's callback
        return false -- failed to setup timer
    end

    return true
end
