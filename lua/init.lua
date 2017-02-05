local SSID = "SSID"
local PASSWORD = "password"
local APP = "thermo.lua"

print("Connecting to WiFi access point...")
wifi.setmode(wifi.STATION)
wifi.sta.config(SSID, PASSWORD)

tmr.alarm(1, 1000, 1, function()
    if wifi.sta.getip() == nil then
        print("Waiting for IP address...")
    else
        tmr.stop(1)
        print("WiFi connection established, IP address: " .. wifi.sta.getip())
        if file.open(APP) ~= nil then
            file.close(APP)
            dofile(APP)
        end
    end
end)
