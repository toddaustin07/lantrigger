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
  
  SmartThings Edge driver module for handling interface with Bridge Server
  
  For use in linking devices using fixed IP:Port messages with Edge device drivers 

--]]

local cosock = require "cosock" 
local socket = require "cosock.socket"
local Thread = require "st.thread"
local log = require "log"

local listen_ip = "0.0.0.0"
local listen_port = 0
local CLIENTSOCKTIMEOUT = 2
local serversock
local channelID
local server_ip
local server_port
local callback
local server_thread
local reglist = {}


local function validate_address(lanAddress)

  local valid = true
  
  local ip = lanAddress:match('^(%d.+):')
  local port = tonumber(lanAddress:match(':(%d+)$'))
  
  if ip then
    local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
    if #chunks == 4 then
      for i, v in pairs(chunks) do
        if tonumber(v) > 255 then 
          valid = false
          break
        end
      end
    else
      valid = false
    end
  else
    valid = false
  end
  
  if port then
    if type(port) == 'number' then
      if (port < 1) or (port > 65535) then 
        valid = false
      end
    else
      valid = false
    end
  else
    valid = false
  end
  
  if valid then
    return ip, port
  else
    return nil
  end
        
end


local function init_clientsocket()

  clientsock = assert(socket.tcp(), "create TCP socket")
  clientsock:settimeout(CLIENTSOCKTIMEOUT)

  return clientsock

end


local function init_serversocket()

  local serversock = assert(socket.tcp(), "create TCP socket")
  assert(serversock:bind('*', 0))
  serversock:settimeout(0)
  serversock:listen()

  return serversock

end



local function issue_request(req_method, ip, port, endpoint)

  local sock = init_clientsocket()

  if sock:connect(ip, port) then

    local our_address = sock:getsockname()
    
    local headers = table.concat (
      {
          string.upper(req_method) .. ' ' .. endpoint .. ' HTTP/1.1',
          'HOST: ' .. ip .. ':' .. tostring(port),
          '\r\n'
      },
      '\r\n'
    )

    sock:send(headers)

    local buffer, err = sock:receive()

    if buffer then
      sock:close()
      return tonumber(buffer:match('^HTTP/[%d.%.]+ (%d+)')), buffer
    else
      log.error('Failed to get response from bridge:', err)
    end
  else
    log.warn (string.format('Failed to connect to %s:%s', ip, port))
  end

  sock:close()
  return nil
    
end


local function register(id, bridgeaddr, deviceaddr)

  local ip, port = validate_address(bridgeaddr)

  if ip then
  
    -- See if this deviceaddr has already been registered
  
    local foundflag = false
    
    for _, item in ipairs(reglist) do
      if item.bridge == bridgeaddr and item.dev == deviceaddr then
        foundflag = true
      end
    end
    
    if foundflag == true then
      log.debug (string.format('Device at %s already registered with bridge server at %s', deviceaddr, bridgeaddr))
      return true
    end
    
    -- Otherwise, register with bridge server
    log.debug (string.format('Registering: id=%s, bridgeaddr=%s, deviceaddr=%s', id, bridgeaddr, deviceaddr))
    local endpoint = '/api/register?devaddr=' .. tostring(deviceaddr) .. '&edgeid=' .. id .. '&hubaddr=' .. server_ip .. ':' .. tostring(server_port)
    local retcode, response = issue_request('POST', ip, port, endpoint)
    --log.debug ('HTTP Response Code: ', retcode)
    --log.debug ('\tResponse data: ', response)
    
    if retcode == 200 then
      table.insert(reglist, {bridge=bridgeaddr, dev=deviceaddr})
      return true
    end
  else
    log.warn ('Valid Bridge server address not configured')
  end

  return false

end

-----------------------------------------------------------------------
--						SERVER SOCKET CONNECTION HANDLER
-----------------------------------------------------------------------

local function watch_socket(_, sock)

  local client, accept_err = sock:accept()

  local ip, port, _ = client:getpeername()
  log.debug(string.format("Accepted connection from %s:%s", ip, port))

  if accept_err ~= nil then
    log.info("Connection accept error: " .. accept_err)
    listen_sock:close()
    return
  end

  cosock.spawn(function()

    client:settimeout(1)

    local line, hline, err

    -- Receive initial HTTP request line
    line, err = client:receive()
    
    if err == nil then
      log.debug ('Received:', line)
    else
      log.warn("Error on client receive: " .. err)
      client:close()
      return
    end

    -- Receive header lines
    hline, err = client:receive()
    
    if err == nil then
      while (hline ~= "") and (err == nil) do
        --log.debug ('\tHeader:', hline)
        hline, err  = client:receive()
      end
    end
    if err then
      log.warn("Error on header receive: ", err)
      client:close()
      return
    end

    -- Receive body here if needed (Future)
    
    
    if line:find('POST', 1, plaintext) == 1 then
     
      OK_MSG = 'HTTP/1.1 200 OK\r\n\r\n'
                  
      client:send(OK_MSG)
     
      -- received url format = 'POST /<device address>/<device message method>/<device message path> HTTP/1.1'
      local devaddr, devmethod, devmsgpath = line:match('^POST /([%d%.:]+)/(%a+)(.*) ')
      
      callback(devaddr, devmethod, devmsgpath)

    else
      log.error ('Unexpected message received from Bridge:', line)
      
    end
    
    client:close()
    
  end, "read socket task")
  
end


local function start_bridge_server(driver, triggerfunc)

  -- Startup Server
  serversock = init_serversocket()
  server_ip, server_port = serversock:getsockname()
  log.info(string.format('Server started at %s:%s', server_ip, server_port))
  
  callback = triggerfunc

  if not server_thread then
    server_thread = Thread.Thread(driver, 'server thread')
  end
  
  server_thread:register_socket(serversock, watch_socket, 'server handler')

end


local function shutdown(driver)

  log.debug ('Shutting down Bridge server')
  
  if server_thread then
    server_thread:unregister_socket(serversock, watch_socket)
  end
  
  log.debug ('\tServer socket handler unregistered') 
  if serversock then
    serversock:close()
  end
  log.debug ('\tServer socket closed')

end


local function delete(id, bridgeaddr, deviceaddr)
  
  local ip, port = validate_address(bridgeaddr)
  
  if ip then
  
    local endpoint = '/api/register?devaddr=' .. tostring(deviceaddr) .. '&edgeid=' .. id ..'&hubaddr=' .. server_ip .. ':' .. tostring(server_port)
    local retcode, response = issue_request('DELETE', ip, port, endpoint)
    
    if retcode == 200 then
      for i, item in ipairs(reglist) do
        if item.bridge == bridgeaddr and item.dev == deviceaddr then
          table.remove(reglist, i)
        end
      end
      
      return true
      
    else
      log.error ('Failed to delete registration')
    end
  else
    log.warn('Cannot unregister: invalid bridge server address')
  end

  return false
  
end



return {
  start_bridge_server = start_bridge_server,
  register = register,
  delete = delete,
  shutdown = shutdown,
}
