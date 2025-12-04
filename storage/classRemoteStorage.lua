
local ItemStorage = require("classItemStorage")
local NetworkNode = require("classBluenetNode")
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

    o.node = nil

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

function RemoteStorage:initialize()
    self.node = NetworkNode:new("storage")

    if self.node then 
        self.node.onRequestAnswer = function(forMsg)
            local data = forMsg.data[2]
            if forMsg.data[1] == "REQUEST_ITEMS" then
                self:onRequestItems(data.name, data.count)
            elseif forMsg.data[1] == "RESERVE_ITEMS" then
                self:onReserveItems(data.name, data.count)
            elseif forMsg.data[1] == "PICKUP_ITEMS" then
                self:onPickupItems(data.reservationId)
            elseif forMsg.data[1] == "CANCEL_RESERVATION" then
                self:onCancelReservation(data.reservationId)
            end
        end

        self.node.onAnswer = function(msg, forMsg)
            local data = msg.data[2]
            if msg.data[1] == "AVAILABLE_ITEMS" then
                self:handleAvailableResponse(msg, data.name, data.available)
            elseif msg.data[1] == "ITEMS_DELIVERED" then 
                self:handleItemsDelivered(msg)
            else 
                print("other", msg.data[1], "sender", msg.sender, "for", forMsg.data[1])
            end
        end
    end



end

-- #####################   view of requiring items

function RemoteStorage:handleItemsDelivered(msg)
    local data = msg.data[2]
    --reservationId = reservation.id, itemName = itemName, count = count - remaining, provider = reservation.provider 
    print("received reservation", data.reservationId, "of", data.count, data.itemName, "from", data.provider, "in", data.requestingInv)

    self:input(data.requestingInv)
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

function RemoteStorage:requestReserveItems(itemName, count)
    -- broadcast to all storage providers? kind of weird, no?
    -- try ringlike topology, where message is passed along until someone can provide it?

    local remaining = count
    local reservations = {}
    self.node:send( storageChannel {"REQUEST_ITEMS", { name = itemName, count = count }})
    sleep(1) -- wait for answers to arrive
    for provider, available in pairs(self.providerIndex[itemName] or {}) do
        print("provider", provider, "has", available, "of", itemName)
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

    local reserved = count - remaining
    if remaining > 0 then 
        print("could only reserve", reserved, "of", itemName, "needed", count, "cancelling reservations")
        for i = 1, #reservations do
            local res = reservations[i]
            self:cancelReservation(res.provider, res.id)
        end
    end

    local function getNearestAvailableTurtles(turtles)
        local availableTurtles = {}
        for id, turt in pairs(turtles) do
            local state = turt.state
            if state.online and state.task == nil and not state.stuck then 
                local diff = self.providerPos - state.pos
                local dist = diff:length()
                availableTurtles[#availableTurtles+1] = { id = id, dist = dist }
            end
        end
        table.sort(availableTurtles, function(a, b) return a.dist < b.dist end)
        return availableTurtles
    end
    local availableTurtles = getNearestAvailableTurtles(self.turtles)
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
            local turt = turtles[availableTurtles[k].id]
            local protocol = "miner" -- misuse storage node to contact turtles through miner protocol

            local answer = self.node:send(id, {"TRANSPORT_REQUEST", 
                { reservation = res, dropOffPos = self.requestingPos, requestingInv = self.requestingInventory, requester = self.nodeRequest.id }},
                true, true, default.waitTime, "miner")
            if answer and answer.data[1] == "TRANSPORT_ACCEPTED" then 
                print("transport accepted by turtle", id)
                ck = k
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
function RemoteStorage:cancelReservation(provider, reservationId)
    local answer = self.node:send(provider, {"CANCEL_RESERVATION", { reservationId = reservationId }}, true, true, default.waitTime)
    print("cancelling reservation", reservationId, "from", provider)
end

-- #####################   view of providing items

function RemoteStorage:onRequestItems(itemName, count)

    local sources = self.index[itemName]
    local available = 0
    if sources then
        for _, qty in pairs(sources) do
            available = available + qty
        end
    end
    self.node:answer(msg, {"AVAILABLE_ITEMS", { name = itemName, available = available}})
end

function RemoteStorage:onReserveItems(itemName, count)

    local reservation = {}
    local reserved = self:extract(itemName, count, self.providerInventory, nil, reservation)

    local id = os.epoch("utc") .. math.random(1000,9999)
    self.reservations[id] = reservation

    self.node:answer(msg, {"ITEMS_RESERVED", { name = itemName, reserved = reserved, id = id, pos = self.providerPos}})
   
end

function RemoteStorage:onPickupItems(reservationId)
    -- turtle is at pickup location and wants the items
    local reservation = self.reservations[reservationId]
    local itemName = reservation[1].itemName
    local extracted = self:extractReservation(reservation, self.providerInventory)
    self.node:answer(msg, {"ITEMS_EXTRACTED", name = itemName, count = extracted})
    if extracted then self.reservations[reservationId] = nil end
end

function RemoteStorage:onCancelReservation(reservationId)
    self:cancelReservation(self.reservations[reservationId])
    self.reservations[reservationId] = nil
    self.node:answer(msg, {"RESERVATION_CANCELLED", reservationId})
end


