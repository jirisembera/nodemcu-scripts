-- based on https://iotbytes.wordpress.com/wifi-configuration-on-nodemcu/
--
-- WARNING: Windows 10 fail to obtain IP address from ESP's DHCP server. See https://github.com/nodemcu/nodemcu-firmware/issues/1577 
-- use wifi_connected_register( callback ) to register on_connected callback, wifi_connected_unregister to unregister

---------------------------------------
--
---------------------------------------

---------------------------------------
--- Set Variables ---
---------------------------------------
local MAX_ERRORS = 5  -- max wifi connect errors before starting enduser_setup configurator using settings below
local USE_ENDUSER_SETUP = false
local ON_CONNECTED_CALLBACKS = {}
local ON_SETUP_STARTED_CALLBACKS = {}
--- Set AP Configuration Variables ---
local AP_CFG={}
--- SSID: 1-32 chars
AP_CFG.ssid="nodemcu"
--- Password: 8-64 chars. Minimum 8 Chars
AP_CFG.pwd="wifipassword"
--- Authentication: AUTH_OPEN, AUTH_WPA_PSK, AUTH_WPA2_PSK, AUTH_WPA_WPA2_PSK
AP_CFG.auth=AUTH_OPEN
--- Channel: Range 1-14
AP_CFG.channel = 6
--- Hidden Network? True: 1, False: 0
AP_CFG.hidden = 0
--- Max Connections: Range 1-4
AP_CFG.max=4
--- WiFi Beacon: Range 100-60000
AP_CFG.beacon=100

--- Set AP IP Configuration Variables ---
local AP_IP_CFG={}
AP_IP_CFG.ip="192.168.10.1"
AP_IP_CFG.netmask="255.255.255.0"
AP_IP_CFG.gateway="192.168.10.1"

--- Set AP DHCP Configuration Variables ---
--- There is no support for defining last DHCP IP ---
local AP_DHCP_CFG ={}
AP_DHCP_CFG.start = "192.168.10.100"
---------------------------------------

--- internals
local wifi_connected = false
local error_counter = 0
local enduser_setup_started = false

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
    wifi.setmode(wifi.STATION)     
    wifi.sta.config( ssid, password)
    wifi.sta.connect()
    enduser_setup_started = false
    error_counter = 0
end

if enduser_setup then 
    enduser_setup.manual(true)
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
    print("starting enduser_setup...")
    enduser_setup_started = true

    for callback, enabled in pairs(ON_SETUP_STARTED_CALLBACKS) do
        if enabled then
            callback( T )
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

    if USE_ENDUSER_SETUP then
        enduser_setup.manual(true)
        enduser_setup.start(_enduser_setup_done,
         _enduser_setup_error)
     end
end
---------------------------------------
--- Setup callbacks
---------------------------------------

local function _disconnected_callback(T)
 error_counter = error_counter + 1
    
    print("\n\tSTA - DISCONNECTED".."\n\tSSID: "..T.SSID.."\n\tBSSID: "..
        T.BSSID.."\n\treason: "..T.reason.."\n\terror_count: " .. error_counter)

    if ( error_counter > MAX_ERRORS ) and not enduser_setup_started then
        start_enduser_setup()
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

