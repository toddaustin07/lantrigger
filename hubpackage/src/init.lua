--[[
  Copyright 2021 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  LAN Device Triggered - provides a way for LAN-based devices/applications to trigger SmartThings via HTTP request

  Dependency:  Forwarding Bridge Server running on the LAN

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"                                         -- for time only
local socket = require "cosock.socket"                                  -- for time only
local log = require "log"

local bridge = require "bridge"

-- Custom Capabiities
local cap_createdev = capabilities["partyvoice23922.createanother"]

-- Module variables
local thisDriver = {}
local initialized = false
local device_init_counter = 0
local lastinfochange = socket.gettime()
local BRIDGESERVER_INITIALIZED = false


function split(str, pat)
  local t = {}
  local fpat = "(.-)" .. pat
  local last_end = 1
  local s, e, cap = str:find(fpat, 1)
  while s do
    if s ~= 1 or cap ~= "" then
      table.insert(t, cap)
    end
    last_end = e+1
    s, e, cap = str:find(fpat, last_end)
  end
  if last_end <= #str then
    cap = str:sub(last_end)
    table.insert(t, cap)
  end
  return t
end

function split_path(str)
   return split(str,'[\\/]+')
end


local function trigger_callback(devaddr, method, endpoint)

  if (method == 'POST') or (method == 'GET') then
      
    local pathparts = split_path(endpoint)
    
    local name = pathparts[1]
    local cmd = pathparts[2]

    local device_list = thisDriver:get_devices()
    
    local foundflag = false

    for _, device in ipairs(device_list) do

      if device.preferences.deviceaddr ==  devaddr then
      
        if device.preferences.devicename == name then
        
          log.info (string.format('%s message for device %s: command=%s', method, name, cmd))
          foundflag = true
        
          if cmd == 'trigger' then
        
            device:emit_event(capabilities.button.button.pushed({state_change = true}))

          else
            log.error ('Unknown endpoint command:', cmd)
          end
        end
      end
    end
    
    if not foundflag then
      log.warn ('No matching configured name found')
    end
    
  else
    log.error ('Unexpected HTTP method received:', method)
  end
end


local function create_device(driver)

  local MFG_NAME = 'SmartThings Community'
  local MODEL = 'LAN-Triggered Device'
  local VEND_LABEL = 'LAN-Triggered Device'
  local ID = 'LANTriggered_' .. socket.gettime()
  local PROFILE = 'lantrigger_other.v1'

  log.info (string.format('Creating new device: label=<%s>, id=<%s>', VEND_LABEL, ID))

  local create_device_msg = {
                              type = "LAN",
                              device_network_id = ID,
                              label = VEND_LABEL,
                              profile = PROFILE,
                              manufacturer = MFG_NAME,
                              model = MODEL,
                              vendor_provided_label = VEND_LABEL,
                            }
                      
  assert (driver:try_create_device(create_device_msg), "failed to create device")

end


local function retry_register()

  local device_list = thisDriver:get_devices()
  local unregistered = 0
  
  for _, device in ipairs(device_list) do
  
    if device:get_field('registered') == false then
    
      if bridge.register(device.st_store.driver.id, device.preferences.bridgeaddr, device.preferences.deviceaddr) then
        device:online()
        device:set_field('registered', true)
        log.info ('Registration with Bridge Server successful for', device.label)
      else
        log.error ('Registration with Bridge Server failed for', device.label)
        unregistered = unregistered + 1
      end
    end
  end
  
  if unregistered > 0 then
    log.info('Scheduling registration retry')
    thisDriver:call_with_delay(20, retry_register, 'registration-retry')
  end
end


local function do_register(device)

  if bridge.register(device.st_store.driver.id, device.preferences.bridgeaddr, device.preferences.deviceaddr) then
    device:online()
    device:set_field('registered', true)
    log.info ('Registration with Bridge Server successful')
  else
    log.error ('Registration with Bridge Server failed')
    device:offline()
    device:set_field('registered', false)
  end
  
end


local function clear_registration(id, bridgeaddr, cleared_devaddr)

  local device_list = thisDriver:get_devices()

  -- see if there are any more devices still using this bridgeaddr & deviceaddr combo

  local foundflag = false
  for _, dev in ipairs(device_list) do
    if dev.preferences.bridgeaddr == bridgeaddr and dev.preferences.deviceaddr == cleared_devaddr then
      foundflag = true
    end
  end
    
  -- if none found, then delete the registration for this deviceaddr
  if not foundflag then
    if bridge.delete(id, bridgeaddr, cleared_devaddr) then
      log.info (string.format('Bridge server %s registration deleted for device at: %s', bridgeaddr, cleared_devaddr))
    end
  end

end


-- CAPABILITY HANDLERS

local function handle_createdev(driver, device, command)

  create_device(driver)

end

local function handle_button(driver, device, command)

  log.info ('Virtual button pressed')
  
  device:emit_event(capabilities.button.button.pushed({state_change = true}))
  
end

------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)
  
    log.debug(device.id .. ": " .. device.device_network_id .. "> INITIALIZING")
    
    if BRIDGESERVER_INITIALIZED == false then
      -- Startup Server
      bridge.start_bridge_server(driver, trigger_callback)
      BRIDGESERVER_INITIALIZED = true
    end
    
    -- Register with server
    device.thread:queue_event(do_register, device)
    --do_register(device)
        
    initialized = true
    device_init_counter = device_init_counter + 1
    
    if #driver:get_devices() == device_init_counter then
      driver:call_with_delay(10, retry_register, 'registration-retry')
    end
    
    log.debug('Exiting device initialization')
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.id .. ": " .. device.device_network_id .. "> ADDED")

  local supported_values =  {
                              capabilities.button.button.pushed.NAME,
                            }
  device:emit_event(capabilities.button.supportedButtonValues(supported_values))
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  log.info ('Device doConfigure lifecycle invoked')

end


-- Called when device was deleted via mobile app
local function device_removed(driver, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")
  
  clear_registration(device.st_store.driver.id, device.preferences.bridgeaddr, device.preferences.deviceaddr)
  
  local device_list = driver:get_devices()
  if #device_list == 0 then
    log.warn ('All devices removed')
    initialized = false
  end
  
end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end


local function shutdown_handler(driver, event)

  if event == 'shutdown' then
    bridge.shutdown(driver)
    log.warn('Bridge server shutdown')
  end
end


local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')
  
  -- Did preferences change?
  if args.old_st_store.preferences then
  
    if args.old_st_store.preferences.bridgeaddr ~= device.preferences.bridgeaddr then
      log.info ('Bridge address changed to: ', device.preferences.bridgeaddr)
      do_register(device)
      
    elseif args.old_st_store.preferences.deviceaddr ~= device.preferences.deviceaddr then 
      log.info ('Device address changed to: ', device.preferences.deviceaddr)
      clear_registration(device.st_store.driver.id, device.preferences.bridgeaddr, args.old_st_store.preferences.deviceaddr)
      do_register(device)
      
    elseif args.old_st_store.preferences.devicename ~= device.preferences.devicename then 
      log.info ('Device name changed to: ', device.preferences.devicename)
    
    elseif args.old_st_store.preferences.devicon ~= device.preferences.devicon then 
      log.info ('Icon preference changed to: ', device.preferences.devicon)
      device:try_update_metadata({profile = 'lantrigger_' .. device.preferences.devicon .. '.v1'})
      
    end
  end
end


-- Create Initial Device
local function discovery_handler(driver, _, should_continue)
  
  log.debug("Device discovery invoked")
  
  if not initialized then
    create_device(driver)
  end
  
  log.debug("Exiting discovery")
  
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("thisDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  driver_lifecycle = shutdown_handler,
  capability_handlers = {
    [cap_createdev.ID] = {
      [cap_createdev.commands.push.NAME] = handle_createdev,
    },
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = handle_button,
    },
  }
})

log.info ('LAN-Triggered Device Driver v2.2 Started')


thisDriver:run()
