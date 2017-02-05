local MEASUREMENT_PERIOD_SEC = 60

dofile("ds18b20.lua")
local THERMO_PIN = 4
local TEMP_ADJUSTMENT_HUNDREDTHS = 0

local MQTT_CLIENT_ID = "ESP8266"
local MQTT_USER = "username"
local MQTT_PASS = "password"
local MQTT_KEEPALIVE_SEC = 120
local MQTT_BROKER = "0.0.0.0"
local MQTT_PORT = 1883
local MQTT_TOPIC = "my/mqtt/topic"


local thermo = DS12B20(THERMO_PIN)
local mqtt_online = false
local mqtt_client = nil
local fn_publish_temp = nil
local fn_offline_measurement = nil


function get_adjusted_tenths(degrees, tenthousandths)
    hundredths = degrees * 100 + tenthousandths / 100 + TEMP_ADJUSTMENT_HUNDREDTHS
    tenths = hundredths / 10
    if hundredths % 10 >= 5 then
        tenths = tenths + 1
    end
    return tenths
end

function format_temp(degrees, tenthousandths)
    if degrees == nil or tenthousandths == nil then
        return nil
    end
    tenths = get_adjusted_tenths(degrees, tenthousandths)
    formatted_temp = string.format("%02d.%01d", tenths / 10, tenths % 10)
    return formatted_temp
end

fn_offline_measurement = function(degrees, tenthousandths)
    formatted_temp = format_temp(degrees, tenthousandths)
    if formatted_temp == nil then
        return
    end
    print("Offline measurement: " .. formatted_temp .. "C")
end

function measurement_event()
    if mqtt_online then
        thermo:read_value(fn_publish_temp)
    else
        thermo:read_value(fn_offline_measurement)
    end
end

mqtt_client = mqtt.Client(MQTT_CLIENT_ID, MQTT_KEEPALIVE_SEC, MQTT_USER, MQTT_PASS)
mqtt_client:on("connect", function(client)
    print ("MQTT connected.")
    mqtt_online = true
    measurement_event()
end)
mqtt_client:on("offline", function(client)
    print ("MQTT offline.")
    mqtt_online = false
end)

fn_publish_temp = function(degrees, tenthousandths)
    formatted_temp = format_temp(degrees, tenthousandths)
    if formatted_temp == nil then
        return
    end
    mqtt_client:publish(MQTT_TOPIC, formatted_temp , 0, 0, function(client)
        print("Measurement of " .. formatted_temp .. "C sent to " .. MQTT_TOPIC .. " on " .. MQTT_BROKER .. ":" .. MQTT_PORT)
    end)
end

function mqtt_connect(client)
    print("Attempting MQTT connection...")
    client:connect(MQTT_BROKER, MQTT_PORT, 0, 1,
        function(client) 
            print("MQTT connected successfully")
            mqtt_online = true
            measurement_event()
        end, 
        function(client, reason)
            print("MQTT connection failed. Reason: " .. reason)
            mqtt_online = false
        end)
end

mqtt_connect(mqtt_client)

local measurement_timer = tmr.create()
measurement_timer:register(MEASUREMENT_PERIOD_SEC * 1000, tmr.ALARM_AUTO, function()
    measurement_event()
end)
measurement_timer:start()
