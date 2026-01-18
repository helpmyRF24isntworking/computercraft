
local ItemStorage = require("classItemStorage")
require("classBluenetNode")
local bluenet = require("bluenet")

local default = {
    waitTime = 3,
    shortWaitTime = 0.5,
    configFile = "/runtime/storage_config.txt",
    priorityProtocol = "storage_priority",
}
local storageChannel = bluenet.default.channels.storage

local peripheralCall = peripheral.call

local RemoteStorage = ItemStorage:new()
RemoteStorage.__index = RemoteStorage

function RemoteStorage:new(node)
	local o = o or ItemStorage:new()
	setmetatable(o, self)
	
	-- Function Caching
    for k, v in pairs(self) do
       if type(v) == "function" then
           o[k] = v  -- Directly assign method to object
       end
    end

    o.node = node or nil
    o.turtles = {}
    o.standalone = standalone or false -- REMOVE ?

	o.inventories = {}

    o.providers = {}
    o.providerInventory = nil -- perhaps multiple inventories?
    o.providerPos = nil
    o.providerIndex = {}

    o.reservations = {}

    o.requestingInventory = nil
    o.requestingPos = nil

    o.pendingItemListRequests = {}
    o.pendingAvailableRequests = {}

	o:initialize()
	return o
end


-- setup: initialize this and hook node into main receiving thread or open a new one for standalone storage

function RemoteStorage:initialize()
    if not self.node then 
        self.node = NetworkNode:new("storage",false, true)
    end
    bluenet.openChannel(bluenet.modem, bluenet.default.channels.storage)

    if self.node then 
        self.node.onRequestAnswer = function(forMsg) end -- dummy overwrite

        self.node.onReceive = function(msg)
            local data = msg.data[2]
            print(msg.data[1], "sender", msg.sender)
            if msg.data[1] == "AVAILABLE_ITEMS" then
                self:handleAvailableResponse(msg)
            elseif msg.data[1] == "ITEM_LIST" then
                self:handleItemListResponse(msg)
            elseif msg.data[1] == "TURTLE_STATE" then 
                --print(msg.data[1], "from", msg.sender, "distance", msg.distance)
                self.turtles[msg.sender] = msg.data[2]
            elseif msg.data[1] == "REQUEST_AVAILABLE_ITEMS" then
                self:onRequestAvailableItems(msg)
            elseif msg.data[1] == "REQUEST_ITEM_LIST" then
                self:onRequestItemList(msg)
            elseif msg.data[1] == "REQUEST_PROVIDER_STATE" then 
                self:onRequestProviderState(msg)
            elseif msg.data[1] == "PROVIDER_STATE" then 
                self:handleProviderStateResponse(msg)
            elseif msg.data[1] == "RESERVE_ITEMS" then
                self:onReserveItems(msg, data.name, data.count)
            elseif msg.data[1] == "PICKUP_ITEMS" then
                self:onPickupItems(msg, data.reservationId)
            elseif msg.data[1] == "CANCEL_RESERVATION" then
                self:onCancelReservation(msg, data.reservationId)
            elseif msg.data[1] == "ITEMS_DELIVERED" then 
                self:handleItemsDelivered(msg)
            else
                print("other", msg.data[1], "sender", msg.sender)
            end
        end

        self.node.onAnswer = function(msg, forMsg)
            if msg.data[1] == "ITEM_LIST" then 
                self:handleItemListResponse(msg,forMsg)
            elseif msg.data[1] == "AVAILABLE_ITEMS" then 
                self:handleAvailableResponse(msg,forMsg)
            
            elseif msg.data[1] == "RESERVATION_CANCELLED" then 
            
            end
        end
        self.node.onNoAnswer = function(forMsg)
            if forMsg.data[1] == "REQUEST_ITEM_LIST" then 
                self:handleNoItemListResponse(forMsg)
            elseif forMsg.data[1] == "REQUEST_AVAILABLE_ITEMS" then 
                self:handleNoAvailableResponse(forMsg)
            end
        end
    end

    self:loadConfig()

    if not pocket then
        -- super
        self:getInventories()
        self:indexInventories()
    end

    self:pingStorageProviders()
end

function RemoteStorage:loadConfig(fileName)

    -- ItemStorage.loadConfig(self) -- either overwrite or build on super

    if not fileName then fileName = default.configFile end
    local file = fs.open(fileName, "r")
    if file then 
        local content = file.readAll()
        file.close()
        local config = textutils.unserialize(content)
        if config then 
            if config.providerPos then 
            self.providerPos = vector.new(config.providerPos.x, config.providerPos.y, config.providerPos.z)
            else
                print("no providerPos in config")
            end
            if config.requestingPos then
            self.requestingPos = vector.new(config.requestingPos.x, config.requestingPos.y, config.requestingPos.z)
            else
                print("no requestingPos in config")
            end
            self.providerInventory = config.providerInventory
            self.requestingInventory = config.requestingInventory
        end
    else
        print("could not load storage config from", fileName)
    end
end

function RemoteStorage:saveConfig(fileName)
    if not fileName then fileName = default.configFile end
    local file = fs.open(fileName, "w")
    if file then 
        if not self.providerPos or not self.requestingPos then
            print("cannot save config, positions not set")
            return
        end
        local config = {
            providerPos = vector.new(self.providerPos.x, self.providerPos.y, self.providerPos.z),
            requestingPos = vector.new(self.requestingPos.x, self.requestingPos.y, self.requestingPos.z),
            providerInventory = self.providerInventory,
            requestingInventory = self.requestingInventory,
        }
        local content = textutils.serialize(config)
        file.write(content)
        file.close()
    else
        print("could not save storage config to", fileName)
    end
end

function RemoteStorage:setProviderPos(x,y,z)
    self.providerPos = vector.new(x,y,z)
    self:saveConfig()
end
function RemoteStorage:setRequestingPos(x,y,z)
    self.requestingPos = vector.new(x,y,z)
    self:saveConfig()
end


-- #####################   view of requiring items

function RemoteStorage:handleItemsDelivered(msg)
    local data = msg.data[2]
    local res = data.reservation
    local itemName, count, resId, providerPos, provider = res.itemName, res.reserved, res.id, res.pos, res.provider

    print("received res", resId, ":", count, itemName, "from", provider, "at", providerPos, "in", data.requestingInv)

    if data.requestingInv == "player" then 
        -- NO SLEEPING, this locks the main thread
        -- use inventory_change events?
        -- use manual confirmation or gui prompt to send answer
    else
        local turtleName = data.requestingInv
        local ok = false
        if turtleName then 
            local present = peripheral.isPresent(turtleName)
            if present then 
                local tid = peripheralCall(turtleName, "getID")
                if tid and tid == msg.sender then 
                    ok = true
                    print(turtleName, "verified, id:", tid)
                end
            end
        end
        if not ok then 
            print("pickup items: turtle identity could not be verified", msg.sender, turtleName)
            return
        end
        self:input(data.requestingInv, data.invList)
        self.node:answer(msg, {"DELIVERY_CONFIRMED"})
    end   
end


function RemoteStorage:printProviderIndex()
    local itCt = 0
    -- explicitly remember that a provider has 0 of some item?
    for itemName, providers in pairs(self.providerIndex) do
        local total = 0
        for provider, count in pairs(providers) do
            total = total + count
        end
        write(itemName .. ": " .. total .. " | ")
        for provider, count in pairs(providers) do
            write("  " .. provider .. ": " .. count)
        end
        print()
    end
    return itemList
end

function RemoteStorage:getAccumulatedItemList()
    -- list all items from all providers
    local itCt = 0
    local itemList = {}
    local tempList = {}

    -- have to combine own item index with provider index 
    local ownItems = self:getItemList()
    for i = 1, #ownItems do
        local item = ownItems[i]
        tempList[item.name] = item.count
    end

    for itemName, providers in pairs(self.providerIndex) do
        local total = tempList[itemName] or 0
        for provider, count in pairs(providers) do
            total = total + count
        end
        tempList[itemName] = nil

        if total > 0 then 
            itCt = itCt + 1
            itemList[itCt] = { name = itemName, count = total }
        end
    end

    -- add items that are only in own storage
    for itemName, count in pairs(tempList) do
        itCt = itCt + 1
        itemList[itCt] = { name = itemName, count = count }
    end

    return itemList
end

function RemoteStorage:printAccumulatedItemList()
    local items = self:getAccumulatedItemList()
    table.sort(items, function(a,b) return a.count > b.count end )
    for i = 1, #items do
        local item = items[i]
        print( item.name .. ": " .. item.count )
    end
end

function RemoteStorage:requestItemList(awaitResponses)
    -- try requesting from known providers first
    local providerCt = 0
    local start = os.epoch("utc")
    local requestToken = math.random(1,2147483647)
    self.itemListRequestToken = requestToken
    local pendingItemListRequests = self.pendingItemListRequests
    for provider, state in pairs(self.providers) do
        -- instead of asking each provider synchronously, send all requests and wait for answers
        local msg = self.node:send( provider, {"REQUEST_ITEM_LIST"}, 
            true, false, default.shortWaitTime, default.priorityProtocol)
        pendingItemListRequests[provider] = msg.id
        providerCt = providerCt + 1
    end
    if providerCt == 0 then 
        -- broadcast request
        self.itemListRequestToken = nil
        self:pingStorageProviders()
        self.node:send( storageChannel, {"REQUEST_ITEM_LIST"})
    elseif awaitResponses then
        while true do
            local event, token = os.pullEventRaw("item_list_ready")
            if token == requestToken then break end
        end
    end
    print("item list request:", os.epoch("utc") - start, "ms, from", providerCt, "providers")
end

function RemoteStorage:removeProvider(provider)
    -- provider not responding, has to be pinged again
    self.providers[provider] = nil
    -- remove entries from index
    for itemName, providers in pairs(self.providerIndex) do
        providers[provider] = nil
    end
end

function RemoteStorage:onAllItemListsReceived()
    local token = self.itemListRequestToken
    if token then 
        self.itemListRequestToken = nil
        os.queueEvent("item_list_ready", token) -- queued in receive/main thread
    end
end

function RemoteStorage:handleNoItemListResponse(forMsg)
    local provider = forMsg.recipient
    print("no item list response from", provider)
    self:removeProvider(provider)
    local pending = self.pendingItemListRequests
    pending[provider] = nil
    for k,v in pairs(pending) do return end -- still pending requests
    self:onAllItemListsReceived()
end

function RemoteStorage:handleItemListResponse(msg, forMsg)
    local provIdx = self.providerIndex
    local provider = msg.sender
    local itemList = msg.data[2]
    for i = 1, #itemList do
        local item = itemList[i]
        local idx = provIdx[item.name]
        if not idx then 
            idx = {[provider] = item.count}
            provIdx[item.name] = idx
        else
            idx[provider] = item.count
        end
    end
    if forMsg then 
        local pending = self.pendingItemListRequests
        pending[provider] = nil
        for k,v in pairs(pending) do return end -- still pending requests
        self:onAllItemListsReceived()
    end
end


function RemoteStorage:pingStorageProviders()
    -- also broadcast your own state
    local state = self:getState()
    self.node:send( storageChannel, {"REQUEST_PROVIDER_STATE", state}, 
                    false, false, nil, default.priorityProtocol )
end

function RemoteStorage:handleProviderStateResponse(msg)
    local state = msg.data[2]
    self.providers[msg.sender] = state
end

function RemoteStorage:pingTurtles()
    self.turtles = {}
    self.node:broadcast( {"GET_TURTLE_STATE"}, false )
    sleep(default.shortWaitTime) -- wait for answers to arrive
    return self.turtles
end

function RemoteStorage:getNearestAvailableTurtles(pos)
    if not pos then pos = self.providerPos end
    local availableTurtles = {}
    for id, state in pairs(self.turtles) do
        if state.task == nil and not state.stuck and not state.alreadySent then 
            local diff = pos - vector.new(state.pos.x, state.pos.y, state.pos.z)
            local dist = diff:length()
            -- local dist = msg.distance
            availableTurtles[#availableTurtles+1] = { id = id, dist = dist }
        end
    end
    table.sort(availableTurtles, function(a, b) return a.dist < b.dist end)
    return availableTurtles
end

function RemoteStorage:requestDelivery(itemName, count, toPlayer, fromProvider)
    local requestingPos = self.requestingPos
    local requestingInv = self.requestingInventory

    if not count or count <= 0 then return end

    if toPlayer then
        requestingInv = "player"
        if not pocket then
            print("toPlayer; NOT A POCKET COMPUTER")
            return
        end
        requestingPos = nil
        local x,y,z
        if gps and pocket then 
            x, y, z = gps.locate()
            if x and y and z then
                x, y, z = math.floor(x), math.floor(y), math.floor(z)
                requestingPos = vector.new(x, y, z)
            end
        end
        if not requestingPos then
            print("toPlayer; NO GPS POSITION AVAILABLE")
            return
        end
        print("DELIVERY TO PLAYER", requestingPos)
    end

    if not requestingPos then
        print("requestDelivery: pos not set", requestingPos, "inv", requestingInv)
        return
    end

    local providerFilter = fromProvider and { [fromProvider] = true } or nil
    return self:requestReserveItems(itemName, count, requestingPos, requestingInv, providerFilter)
    
end




function RemoteStorage:requestAvailableItems(itemName, count)
    local providerCt = 0
    local start = os.epoch("utc")
    local pending = self.pendingAvailableRequests
    
    local requestToken = math.random(1,2147483647)
    self.availableRequestToken = requestToken
    
    for provider, state in pairs(self.providers) do
        local msg = self.node:send( provider, {"REQUEST_AVAILABLE_ITEMS", { name = itemName, count = count }}, 
                    true, false, default.shortWaitTime, default.priorityProtocol)
        pending[provider] = msg.id
        providerCt = providerCt + 1
    end
    
    if providerCt == 0 then 
        self.availableRequestToken = nil
        self:pingStorageProviders()
        self.node:send( storageChannel, {"REQUEST_AVAILABLE_ITEMS", { name = itemName, count = count }})
    else
        print("waiting for allAvailableReceived...")
        while true do
            local event, token = os.pullEventRaw("available_ready")
            if token == requestToken then break end
        end
    end
    
    print("available items request:", os.epoch("utc") - start, "ms, from", providerCt, "providers")
end

function RemoteStorage:onAllAvailableReceived()
    local token = self.availableRequestToken
    if token then
        self.availableRequestToken = nil
        os.queueEvent("available_ready", token) -- queued in receive/main thread
    end
end

function RemoteStorage:handleNoAvailableResponse(forMsg)
    local provider = forMsg.recipient
    print("no available items response from", provider)
    self:removeProvider(provider)
    local pending = self.pendingAvailableRequests
    pending[provider] = nil
    for k,v in pairs(pending) do return end -- still pending requests
    self:onAllAvailableReceived()
end


function RemoteStorage:handleAvailableResponse(msg, forMsg)
    local provider = msg.sender
    local data = msg.data[2]
    local itemName, available = data.name, data.available
    -- remember which providers have which items
    local idx = self.providerIndex[itemName]
    if not idx then
        idx = {[provider] = available}
        self.providerIndex[itemName] = idx
    else
        idx[provider] = available
    end

    if forMsg then 
        local pending = self.pendingAvailableRequests
        pending[provider] = nil
        for k,v in pairs(pending) do return end -- still pending requests
        self:onAllAvailableReceived()
    end
end




function RemoteStorage:requestReserveItems(itemName, count, requestingPos, requestingInv, providerFilter)
    -- broadcast to all storage providers? kind of weird, no?
    -- try ringlike topology, where message is passed along until someone can provide it?

    -- why even reserve items if we know beforehand we dont have enough providers

    local remaining = count
    local reservations = {}
    self:requestAvailableItems(itemName, count)

    for provider, available in pairs(self.providerIndex[itemName] or {}) do
        if providerFilter and not providerFilter[provider] then
            print("skipping provider", provider, "not in filter")
        else
            print("provider", provider, "has", available, "of", itemName)
            if available > 0 then 
                local answer = self.node:send(provider, {"RESERVE_ITEMS", { name = itemName, count = count }}, true, true, default.waitTime)
                if answer and answer.data[1] == "ITEMS_RESERVED" then
                    local data = answer.data[2]
                    data.provider = provider
                    if data.pos then 
                        data.pos = vector.new(data.pos.x, data.pos.y, data.pos.z)
                    end
                    reservations[#reservations+1] = data
                    remaining = remaining - data.reserved
                    print("reserved", data.reserved, "of", itemName, "from", provider)
                    if remaining <= 0 then
                        -- all items reserved
                        break
                    end
                end
            end
        end
    end

    local reserved = count - remaining
    if remaining > 0 then 
        print("could only reserve", reserved, "of", itemName, "needed", count, "cancelling reservations")
        for i = 1, #reservations do
            local res = reservations[i]
            if self:sendCancelReservation(res.provider, res.id) then 
                reservations[i] = nil
            else
                print("failed to cancel reservation", res.id, "from", res.provider)
            end
        end
        reservations = {}
    end


    if #reservations == 0 then
        print("no reservations could be made for", itemName)
        return nil
    end
    self:pingTurtles()

    -- todo: max items a turtle can carry = 15*stackSize
    -- 1 slot reserved for fuel

    -- each reservation might have a different provider 
    -- -> different pickup locations -> multiple trips / turtles needed
    -- -> Travelling Salesman Problem
    -- for now, one provider per turtle trip

    local turtles = self.turtles
    for i = 1, #reservations do 
        local res = reservations[i]
        -- not neares turtle to current/requesting position but pickup/provider position
        local availableTurtles = self:getNearestAvailableTurtles(res.pos)
        for k = 1, #availableTurtles do
            local id, dist = availableTurtles[k].id, availableTurtles[k].dist
            print("transport request to turtle", id, "for reservation", res.id, "from provider", res.provider)
            local answer = self.node:send(id, {"DO", "pickupAndDeliverItems", 
                { res, requestingPos, self.node.id, requestingInv }},
                true, true, default.waitTime)

            --local answer = self.node:send(id, {"TRANSPORT_REQUEST", 
            --    { reservation = res, dropOffPos = self.requestingPos, requestingInv = self.requestingInventory, requester = self.node.id }},
            --    true, true, default.waitTime)
            if answer and answer.data[1] == "RECEIVED" then --"TRANSPORT_ACCEPTED" then 
                turtles[id].alreadySent = true
                print("transport accepted by turtle", id)
                break
            end
        end
    end


    -- hmmm

    -- send turtle to pickup location
    -- once arrived turtle has to send pickup items message to provider
    -- provider then extracts items to chest at pickup location
        -- perhaps even directly into turtle 
    -- turtle picks up items
    -- returns to dropoff location
    -- dumps items into requesting storage system
    -- move items to requesting inventory or import items into local storage


    -- how to determine turtles available for transport?
    -- a) ask host to do it ( usually host is the same machine as requester-role ) -> in theory
    -- b) have a pool of dedicated transport turtles -> waste of turtles
    -- c) ask turtles directly (broadcast) -- no need to involve host
    --  -> c is most robust and flexible
    --     protocol: miner or storage ... miner is already running on turtles 
    -- perhaps also a more versatile protocol where anybody can ping turtles for availability

    --     ping turtles for availability and distance
    --     receive current state from turtles 
    --     ask turtles to do transport job 

    -- todo: cancel reservations if pickup failed or not in time

    return nil

end

function RemoteStorage:reserveItems(provider, itemName, count)
    return self.node:send(provider, {"RESERVE_ITEMS", { name = itemName, count = count }}, true, true, default.waitTime)
end
function RemoteStorage:pickupItems(provider, reservationId)
    local answer = self.node:send(provider, {"PICKUP_ITEMS", { reservationId = reservationId }}, true, true, default.waitTime)
end

-- NOOO this overwrites the ItemStorage:cancelReservation function
function RemoteStorage:sendCancelReservation(provider, reservationId)
    local answer = self.node:send(provider, {"CANCEL_RESERVATION", { reservationId = reservationId }}, true, true, default.waitTime)
    print("cancelling reservation", reservationId, "from", provider)
    if answer and answer.data[1] == "RESERVATION_CANCELLED" then
        return true
    else
        return false
    end
    
end


-- #####################   view of providing items

function RemoteStorage:getState()
    return {
        label = os.getComputerLabel() or self.node.id,
        pos = global.pos,
        providerPos = self.providerPos,
        providerInventory = self.providerInventory,
    }
end

function RemoteStorage:onRequestProviderState(msg)
    self:handleProviderStateResponse(msg) -- update own state of requester
    local state = self:getState()
    self.node:send(msg.sender, {"PROVIDER_STATE", state})
end

function RemoteStorage:onRequestItemList(msg)
    local itemList = self:getItemList()
    if msg.answer then 
        -- direct request
        self.node:answer(msg, {"ITEM_LIST", itemList})
    else
        -- broadcasted request
        self.node:send(msg.sender, {"ITEM_LIST", itemList})
    end
end

function RemoteStorage:onRequestAvailableItems(msg)
    local data = msg.data[2]
    local itemName = data.name
    local available = self:countItem(itemName)
    if msg.answer then 
        self.node:answer(msg, {"AVAILABLE_ITEMS", { name = itemName, available = available}})
    else
        self.node:send(msg.sender, {"AVAILABLE_ITEMS", { name = itemName, available = available}})
    end
end

function RemoteStorage:onReserveItems(msg, itemName, count)

    local reservation = {}
    local reserved = self:extract(itemName, count, self.providerInventory, nil, reservation)

    local id = os.epoch("utc") .. math.random(1000,9999)
    self.reservations[id] = reservation

    --self:printReservation(reservation)

    self.node:answer(msg, {"ITEMS_RESERVED", { name = itemName, reserved = reserved, id = id, pos = self.providerPos}})
   
end

function RemoteStorage:onPickupItems(msg, reservationId)
    -- turtle is at pickup location and wants the items
    print("msg.data", msg.data[2].reservationId, msg.data[2].turtleName)
    local turtleName = msg.data[2].turtleName
    local ok = false
    if turtleName then 
        local present = peripheral.isPresent(turtleName)
        if present then 
            local tid = peripheralCall(turtleName, "getID")
            if tid and tid == msg.sender then 
                ok = true
            end
        end
    end
    if not ok then 
        print("pickup items: turtle identity could not be verified", msg.sender, turtleName)
        return
    end

    local toInv = (ok and turtleName) or self.providerInventory
    local reservation = self.reservations[reservationId]
    local itemName = reservation[1].itemName
    local extracted = self:extractReservation(reservation, toInv)
    print("extracted", extracted, "of", itemName, "for reservation", reservationId, "to", toInv)
    self.node:answer(msg, {"ITEMS_EXTRACTED", { name = itemName, count = extracted, extractedToTurtle = ok}})
    if extracted then self.reservations[reservationId] = nil end
end

function RemoteStorage:onCancelReservation(msg, reservationId)
    self:cancelReservation(self.reservations[reservationId])
    self.reservations[reservationId] = nil
    self.node:answer(msg, {"RESERVATION_CANCELLED", reservationId})
end

return RemoteStorage