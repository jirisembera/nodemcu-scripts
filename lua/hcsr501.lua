-- Simple GPIO wrapper for HCSR501 sensor (or anything else that signals via low/high levels)
-- 
-- required modules: gpio

HCSR501 = {}
HCSR501.__index = HCSR501

-- allow construction via directly calling the meta-table
setmetatable(HCSR501, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- actual constructor
function HCSR501.new(pin)
    local self = setmetatable({}, HCSR501)
    self.pin = pin
    
    gpio.mode(self.pin, gpio.INT)

    return self
end

-- get current value
function HCSR501:current_value()
    return gpio.read(self.pin)
end

-- setup trigger
function HCSR501:on_change(callback)
    gpio.trig(self.pin, "both", callback)
end

-- clear trigger
function HCSR501:clear_on_change()
    gpio.trig(self.pin, "both", function()end)
end

