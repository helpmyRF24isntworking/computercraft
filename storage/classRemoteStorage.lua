
local ItemStorage = require("classItemStorage")
require("classBluenetNode")
local bluenet = require("bluenet")

local default = {
    waitTime = 3,
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

            elseif msg.data[1] == "TURTLE_STATE" then 
                print(msg.data[1], "from", msg.sender, "distance", msg.distance)
                self.turtles[msg.sender] = msg.data[2]
            elseif msg.data[1] == "REQUEST_ITEMS" then
                self:onRequestItems(msg.sender, data.name, data.count)
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

    -- super
    self:getInventories()
    self:indexInventories()

end

-- #####################   view of requiring items

function RemoteStorage:handleItemsDelivered(msg)
    local data = msg.data[2]
    local res = data.reservation
    local itemName, count, resId, providerPos, provider = res.itemName, res.reserved, res.id, res.pos, res.provider

    print("received res", resId, ":", count, itemName, "from", provider, "at", providerPos, "in", data.requestingInv)

    --reservationId = reservation.id, itemName = itemName, count = count - remaining, provider = reservation.provider 

    local turtleName = msg.data[2].requestingInv
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

    self:input(data.requestingInv, data.invList) -- make sure turtle is not sucked dry lmao
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



function RemoteStorage:pingTurtles()
    self.turtles = {}
    self.node:broadcast( {"GET_TURTLE_STATE"}, false )
    sleep(1) -- wait for answers to arrive
    return self.turtles
end

function RemoteStorage:getNearestAvailableTurtles()
    local availableTurtles = {}
    for id, state in pairs(self.turtles) do
        if state.task == nil and not state.stuck then 
            local diff = self.providerPos - vector.new(state.pos.x, state.pos.y, state.pos.z)
            local dist = diff:length()
            -- local dist = msg.distance
            availableTurtles[#availableTurtles+1] = { id = id, dist = dist }
        end
    end
    table.sort(availableTurtles, function(a, b) return a.dist < b.dist end)
    return availableTurtles
end

function RemoteStorage:requestReserveItems(itemName, count)
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
    local availableTurtles = self:getNearestAvailableTurtles()

    -- todo: max items a turtle can carry = 15*stackSize
    -- 1 slot reserved for fuel

    -- each reservation might have a different provider 
    -- -> different pickup locations -> multiple trips / turtles needed
    -- -> Travelling Salesman Problem
    -- for now, one provider per turtle trip

    local ck = 1
    local turtles = self.turtles
    for i = 1, #reservations do 
        local res = reservations[i]
        for k = ck, #availableTurtles do
            local id, dist = availableTurtles[k].id, availableTurtles[k].dist
            print("transport request to turtle", id, "for reservation", res.id, "from provider", res.provider)
            local answer = self.node:send(id, {"DO", "pickupAndDeliverItems", 
                { res, self.requestingPos, self.node.id, self.requestingInventory }},
                true, true, default.waitTime)

            --local answer = self.node:send(id, {"TRANSPORT_REQUEST", 
            --    { reservation = res, dropOffPos = self.requestingPos, requestingInv = self.requestingInventory, requester = self.node.id }},
            --    true, true, default.waitTime)
            if answer and answer.data[1] == "RECEIVED" then --"TRANSPORT_ACCEPTED" then 
                print("transport accepted by turtle", id)
                ck = k + 1
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

function RemoteStorage:onRequestItems(requester, itemName, count)

    local sources = self.index[itemName]
    local available = 0
    if sources then
        for _, qty in pairs(sources) do
            available = available + qty
        end
    end
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