-- MQTT client
-- 
-- required modules: mqtt, wifi_init

local client = nil
local keepalive_topic = "/status/default"
local verbose = true  -- use true for printouts to console 

local _connected = false
local _on_ready = nil
local _host = nil
local _port = nil
local _timer = tmr.create()   -- keepalive / reconnect timer
local _reconnect_delay = 5000
local _keepalive_delay = 60000
local _has_subscriptions = false -- if there is something in _subscriptions table. client:subscribe throws an error if it's empty
local _subscriptions = {}
local _callbacks = {}

local _connect_timeout = 20000 -- 20s in ms, timeout for mqtt_client:connect. Sometimes hangs..
local _connect_attempts = 0
local _connect_max_attempts = 5

local function verbose_print(...)
    if verbose then
        print(...)
    end
end

local function _do_connect(host, port, secure, autoreconnect, on_success, on_error)
    tmr.alarm(_timer, _connect_timeout, tmr.ALARM_SINGLE, function(timer)
        verbose_print("MQTT: Watchdog timeout!")
        node.restart()
    end)
    client:connect( host, port , secure, autoreconnect, on_success, on_error )
end

local function _connect_failed( client, error )
    verbose_print("MQTT: Failed to connect to MQTT server. Error code: ", error)

    _connect_attempts = _connect_attempts + 1
    if _connect_attempts >= _connect_max_attempts then
        node.restart()
    end
    
    tmr.alarm(_timer, _reconnect_delay, tmr.ALARM_SINGLE, function()
        verbose_print("MQTT: Reconnecting...")
        _do_connect( host, port , 0, 0, _connect_succeeded, _connect_failed)
    end )
end

local function _connect_succeeded( client )
    local ip = wifi.sta.getip()
    tmr.alarm(_timer, _keepalive_delay, tmr.ALARM_AUTO, function()
        if not mqtt_publish(keepalive_topic, ip, 0, 0) then
            node.restart()
        end
    end )
    _connected = true
    verbose_print("MQTT: Connected!")

    if _has_subscriptions then
        if verbose then
            for topic, qos in pairs(_subscriptions) do
                print("MQTT: Subscribing topic: ", topic)
            end
        end
        
        client:subscribe( _subscriptions )
    end
    
    if _on_ready then
        _on_ready( client )
    end
end

function mqtt_setup(host, port, clientid, username, password, on_ready)
    if client then
        verbose_print("mqtt error: Already created")
        return
    end
    _on_ready = on_ready
    _host = host
    _port = port

    if clientid then
        keepalive_topic = "/status/" .. clientid
    end
    verbose_print("MQTT: Keepalive topic: ", keepalive_topic)

    client = mqtt.Client(clientid, 45, username, password)
    client:lwt(keepalive_topic, "offline", 0, 1) -- qos=0, retain=true
    client:on("message", function( client, topic, data ) 
        verbose_print("MQTT: Dispatching topic: ", topic, " message: ", data )
        if _callbacks[topic] then
            _callbacks[topic](client, topic, data)
        end
    end )
    client:on("offline", function( client, topic, data ) 
        verbose_print("MQTT: Offline!" )
        node.restart()
    end )
    
    if wifi.sta.getip() then
        verbose_print("MQTT: wifi already connected, starting mqtt")
        _do_connect( host, port , 0, 0, _connect_succeeded, _connect_failed )
    else
        wifi_connected_register(function(T)
            verbose_print("MQTT: wifi connected, starting mqtt")
            _do_connect( host, port , 0, 0, _connect_succeeded, _connect_failed )
        end)
    end
end

function mqtt_subscribe( topic, qos, callback )
    if _connected then
        client:subscribe( topic, qos )
    else
        _subscriptions[topic] = qos
        _callbacks[topic] = callback
        _has_subscriptions = true
    end
end

function mqtt_onready_register( callback )
    _on_ready = callback
end

function mqtt_publish(topic, payload, qos, retain)
    if not _connected then
        return false
    end
    return client:publish(topic, payload, qos, retain)
end

function mqtt_close()
    tmr.stop(_timer)
    client:close()
    client = nil
end


