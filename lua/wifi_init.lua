-- Module for more convenient connecting to WiFi networks with a fallback
--   AP mdoe when the preconfigured network is not available
--
-- based on https://iotbytes.wordpress.com/wifi-configuration-on-nodemcu/
--
--
-- To change default settings, define following global variables before loading this file:
--      WIFI_USE_ENDUSER_SETUP - use enduser_setup  module (default false)
--      WIFI_AP_SSID - fallback AP ssid
--      WIFI_AP_PASSWORD - fallback AP password
--
---------------------------------------

---------------------------------------
--- Set Variables ---
---------------------------------------
local NETWORK_POLLING_INTERVAL = 30000 -- how often to check availability of "old" network in end_user_setup mode
local MAX_ERRORS = 5  -- max wifi connect errors before starting enduser_setup configurator using settings below
local USE_ENDUSER_SETUP = WIFI_USE_ENDUSER_SETUP or false
local ON_CONNECTED_CALLBACKS = {}
local ON_SETUP_STARTED_CALLBACKS = {}
--- Set AP Configuration Variables ---
local AP_CFG={}
--- SSID: 1-32 chars
AP_CFG.ssid = WIFI_AP_SSID or "nodemcu"
--- Password: 8-64 chars. Minimum 8 Chars
AP_CFG.pwd = WIFI_AP_PASSWORD or "wifipassword"
--- Authentication: AUTH_OPEN, AUTH_WPA_PSK, AUTH_WPA2_PSK, AUTH_WPA_WPA2_PSK
AP_CFG.auth = AUTH_OPEN
--- Channel: Range 1-14
AP_CFG.channel = 6
--- Hidden Network? True: 1, False: 0
AP_CFG.hidden = 0
--- Max Connections: Range 1-4
AP_CFG.max = 4
--- WiFi Beacon: Range 100-60000
AP_CFG.beacon = 100

--- Set AP IP Configuration Variables ---
local AP_IP_CFG={}
AP_IP_CFG.ip = "192.168.10.1"
AP_IP_CFG.netmask = "255.255.255.0"
AP_IP_CFG.gateway = "192.168.10.1"

--- Set AP DHCP Configuration Variables ---
--- There is no support for defining last DHCP IP ---
local AP_DHCP_CFG = {}
AP_DHCP_CFG.start = "192.168.10.100"
---------------------------------------

--- internals
local wifi_connected = false
local error_counter = 0
local enduser_setup_started = false
local network_polling_timer = tmr.create()
network_polling_timer:register(NETWORK_POLLING_INTERVAL, tmr.ALARM_AUTO, function (t)
    if enduser_setup_started then
        print("Trying to reconnect to original network...")
        wifi.sta.connect()
        -- STATINOAP mode has to be restored in _disconnected_callback otherwise
        -- it gets reconfigured by enduser_setup to defaults (open network)
    end 
end)

function wifi_connected_register( callback )
    ON_CONNECTED_CALLBACKS[callback] = true
end

function wifi_connected_unregister( callback )
    ON_CONNECTED_CALLBACKS[callback] = false
end

function wifi_setup_started_register( callback )
    ON_SETUP_STARTED_CALLBACKS[callback] = true
end

function wifi_setup_started_unregister( callback )
    ON_SETUP_STARTED_CALLBACKS[callback] = false
end

function wifi_connect( ssid, password )
    local STA_CFG={}
    STA_CFG.ssid = ssid
    STA_CFG.pwd = password
    
    wifi.setmode(wifi.STATION)
    wifi.sta.config( STA_CFG )
    wifi.sta.connect()
    enduser_setup_started = false
    error_counter = 0
end

local function _enduser_setup_done()
    print("Connected to wifi as:" .. wifi.sta.getip())
    wifi_connected = true
    enduser_setup.stop()
    enduser_setup_started = false
end

local function _enduser_setup_error(err, str)
    print("enduser_setup: Err #" .. err .. ": " .. str)
end

function wifi_start_enduser_setup()
    print("(re)starting enduser_setup...")

    if not enduser_setup_started then -- call callback just once
        for callback, enabled in pairs(ON_SETUP_STARTED_CALLBACKS) do
            if enabled then
                callback( T )
            end
        end
    end
    
    --- Configure ESP8266 into AP Mode ---
    wifi.setmode(wifi.SOFTAP)
    --- Configure 802.11n Standard ---
    wifi.setphymode(wifi.PHYMODE_N)
    
    --- Configure WiFi Network Settings ---
    wifi.ap.config(AP_CFG)
    --- Configure AP IP Address ---
    wifi.ap.setip(AP_IP_CFG)
    
    --- Configure DHCP Service ---
    wifi.ap.dhcp.config(AP_DHCP_CFG)
    --- Start DHCP Service ---
    wifi.ap.dhcp.start()

    if USE_ENDUSER_SETUP and not enduser_setup_started then
        enduser_setup.manual(true)
        enduser_setup.start(_enduser_setup_done,
         _enduser_setup_error)
    end
    wifi.setmode(wifi.STATIONAP) -- have to switch to stationap to make reconnection attempts work
    network_polling_timer:start()

    enduser_setup_started = true
end
---------------------------------------
--- Setup callbacks
---------------------------------------

local function _disconnected_callback(T)
    error_counter = error_counter + 1
    
    print("\n\tSTA - DISCONNECTED".."\n\tSSID: "..T.SSID.."\n\tBSSID: "..
        T.BSSID.."\n\treason: "..T.reason.."\n\terror_count: " .. error_counter)

    if error_counter > MAX_ERRORS then
        wifi_start_enduser_setup()
    end

    if wifi_connected then
        node.restart()    -- bail if we had a connection
    end
end

local function _connected_callback(T)
    print("\n\tSTA - GOT IP".."\n\tStation IP: "..T.IP.."\n\tSubnet mask: "..
        T.netmask.."\n\tGateway IP: "..T.gateway)
    wifi_connected = true
    
    for callback, enabled in pairs(ON_CONNECTED_CALLBACKS) do
        if enabled then
            callback( T )
        end
    end
end

wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, _disconnected_callback)

wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, _connected_callback)

-- finally try to connect to wifi!
wifi.setmode(wifi.STATION)
wifi.sta.connect()

