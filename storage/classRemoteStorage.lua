
local ItemStorage = require("classItemStorage")
require("classBluenetNode")
local bluenet = require("bluenet")

local default = {
    waitTime = 3,
    configFile = "/runtime/storage_config.txt",
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

    o.providerInventory = nil -- perhaps multiple inventories?
    o.providerPos = nil
    o.providerIndex = {}

    o.reservations = {}

    o.requestingInventory = nil
    o.requestingPos = nil

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
        self.node.onRequestAnswer = function(forMsg)
            local data = forMsg.data[2]
            if forMsg.data[1] == "RESERVE_ITEMS" then
                self:onReserveItems(forMsg, data.name, data.count)
            elseif forMsg.data[1] == "PICKUP_ITEMS" then
                self:onPickupItems(forMsg, data.reservationId)
            elseif forMsg.data[1] == "CANCEL_RESERVATION" then
                self:onCancelReservation(forMsg, data.reservationId)
            elseif forMsg.data[1] == "ITEMS_DELIVERED" then 
                self:handleItemsDelivered(forMsg)
            else
                print("unknown request", forMsg.data[1], "from", forMsg.sender)
            end
        end

        self.node.onReceive = function(msg)
            local data = msg.data[2]
            if msg.data[1] == "AVAILABLE_ITEMS" then
                self:handleAvailableResponse(msg, data.name, data.available)
            elseif msg.data[1] == "ITEM_LIST" then
                self:handleItemListResponse(msg)
            elseif msg.data[1] == "TURTLE_STATE" then 
                print(msg.data[1], "from", msg.sender, "distance", msg.distance)
                self.turtles[msg.sender] = msg.data[2]
            elseif msg.data[1] == "REQUEST_ITEMS" then
                self:onRequestItems(msg.sender, data.name, data.count)
            elseif msg.data[1] == "REQUEST_ITEM_LIST" then
                self:onRequestItemList(msg.sender)
            else
                print("other", msg.data[1], "sender", msg.sender)
            end
        end

        self.node.onAnswer = function(msg, forMsg)
            if msg.data[1] == "ITEMS_RESERVED" then 
            
            elseif msg.data[1] == "RESERVATION_CANCELLED" then 
            
            end
        end
    end

    self:loadConfig()

    if not pocket then
        -- super
        self:getInventories()
        self:indexInventories()
    end

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

    --reservationId = reservation.id, itemName = itemName, count = count - remaining, provider = reservation.provider 

    if data.requestingInv == "player" then 
        sleep(60*2-1) -- dont confirm automatically, player has to pick them up
        -- use inventory_change events?
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
        self:input(data.requestingInv, data.invList) -- make sure turtle is not sucked dry lmao
    end

    self.node:answer(msg, {"DELIVERY_CONFIRMED"})
end

function RemoteStorage:handleAvailableResponse(msg, itemName, available)
    local provider = msg.sender
    -- remember which providers have which items
    local idx = self.providerIndex[itemName]
    if not idx then
        idx = {[provider] = available}
        self.providerIndex[itemName] = idx
    else
        idx[provider] = available
    end
end

function RemoteStorage:printProviderIndex()
    local itCt = 0
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

        itCt = itCt + 1
        itemList[itCt] = { name = itemName, count = total }
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

function RemoteStorage:requestItemList()
    self.node:send( storageChannel, {"REQUEST_ITEM_LIST"})
    sleep(0.5)
end

function RemoteStorage:handleItemListResponse(msg)
    print("received item list from", msg.sender)
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
end


function RemoteStorage:pingTurtles()
    self.turtles = {}
    self.node:broadcast( {"GET_TURTLE_STATE"}, false )
    sleep(1) -- wait for answers to arrive
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

function RemoteStorage:requestDelivery(itemName, count, toPlayer)
    local requestingPos = self.requestingPos
    local requestingInv = self.requestingInventory

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

    self:requestReserveItems(itemName, count, requestingPos, requestingInv)
end


function RemoteStorage:requestReserveItems(itemName, count, requestingPos, requestingInv)
    -- broadcast to all storage providers? kind of weird, no?
    -- try ringlike topology, where message is passed along until someone can provide it?

    -- why even reserve items if we know beforehand we dont have enough providers

    local remaining = count
    local reservations = {}
    local msg = self.node:send( storageChannel, {"REQUEST_ITEMS", { name = itemName, count = count }})
    print(msg.data[1], msg.sender, msg.recipient)
    sleep(1) -- wait for answers to arrive
    for provider, available in pairs(self.providerIndex[itemName] or {}) do
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


function RemoteStorage:onRequestItemList(requester)
    local itemList = self:getItemList()
    self.node:send(requester, {"ITEM_LIST", itemList})
end

function RemoteStorage:onRequestItems(requester, itemName)
    local available = self:countItem(itemName)
    self.node:send(requester, {"AVAILABLE_ITEMS", { name = itemName, available = available}})
end

function RemoteStorage:onReserveItems(msg, itemName, count)

    local reservation = {}
    local reserved = self:extract(itemName, count, self.providerInventory, nil, reservation)

    local id = os.epoch("utc") .. math.random(1000,9999)
    self.reservations[id] = reservation

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
    self.node:answer(msg, {"ITEMS_EXTRACTED", { name = itemName, count = extracted, extractedToTurtle = ok}})
    if extracted then self.reservations[reservationId] = nil end
end

function RemoteStorage:onCancelReservation(msg, reservationId)
    self:cancelReservation(self.reservations[reservationId])
    self.reservations[reservationId] = nil
    self.node:answer(msg, {"RESERVATION_CANCELLED", reservationId})
end

return RemoteStorage