
require("classBluenetNode")
local bluenet = require("bluenet")
local RemoteStorage = require("classRemoteStorage")

-- basic storage functions over bluenet 
-- mainly for turtles that dont actually manage a storage system themselves
-- but can request items from a central storage provider

local default = {
    waitTime = 3,
    shortWaitTime = 0.5,
    priorityProtocol = "storage_priority",
    extractionWaitTime = 10,
}
local storageChannel = bluenet.default.channels.storage
local peripheralCall = peripheral.call


local TurtleStorage = {}
setmetatable(TurtleStorage, { __index = RemoteStorage })
TurtleStorage.__index = TurtleStorage

--local TurtleStorage = RemoteStorage:new(nil, true)
--TurtleStorage.__index = TurtleStorage

function TurtleStorage:new(miner, node)
	local o = RemoteStorage:new(nil, true)
	setmetatable(o, self)

    o.node = node 
    o.miner = miner


	o:initialize()
	return o
end


-- setup: initialize this and hook node into main receiving thread or open a new one for standalone storage

function TurtleStorage:initialize()
    if not turtle then 
        print("TurtleStorage can only be used on turtles")
        return nil
    end

    if not self.node then 
        print("no node for TurtleStorage provided")
        self.node = NetworkNode:new("storage",false, true)
    end
    if not self.miner then 
        print("no miner for TurtleStorage provided")
        return nil
    else 
        if self.miner:hasStorageExtension() then
            self.miner.storage = self
        else
            print("miner has no storage extension")
        end
    end

    -- bluenet.openChannel(bluenet.modem, bluenet.default.channels.storage) 
    -- not sure if this is needed
    -- only open this channel on demand?

    if self.node then 
        self.node.onRequestAnswer = function(forMsg) end -- dummy overwrite

        self.node.onReceive = function(msg)
            local data = msg.data[2]
            print(msg.data[1], "sender", msg.sender)

            if msg.data[1] == "REQUEST_TURTLE_STATE" then 
                self:onRequestTurtleState(msg)
            elseif msg.data[1] == "DO" then 
                self:onTask(msg)

            elseif msg.data[1] == "AVAILABLE_ITEMS" then
                self:handleAvailableResponse(msg)
            elseif msg.data[1] == "ITEM_LIST" then
                self:handleItemListResponse(msg)
            elseif msg.data[1] == "TURTLE_STATE" then 
                -- not sure why this would be needed for TurtleStorage
                self.turtles[msg.sender] = msg.data[2]
            elseif msg.data[1] == "REQUEST_AVAILABLE_ITEMS" then
                -- self:onRequestAvailableItems(msg)
                print("REQUEST_AVAILABLE_ITEMS not handled")
            elseif msg.data[1] == "REQUEST_ITEM_LIST" then
                -- self:onRequestItemList(msg)
                print("REQUEST_ITEM_LIST not handled")
            elseif msg.data[1] == "REQUEST_PROVIDER_STATE" then 
                -- self:onRequestProviderState(msg)
                print("REQUEST_PROVIDER_STATE not handled")
                -- todo instead turtle state

            elseif msg.data[1] == "PROVIDER_STATE" then 
                self:handleProviderStateResponse(msg)
            elseif msg.data[1] == "REQUEST_TRANSPORT_DESTINATION" then 
                self:onRequestTransportDestination(msg)
            elseif msg.data[1] == "RESERVE_ITEMS" then
                -- self:onReserveItems(msg, data.name, data.count)
                print("RESERVE_ITEMS not handled")
            elseif msg.data[1] == "PICKUP_ITEMS" then
                self:onPickupItems(msg, data.reservationId)
            elseif msg.data[1] == "CANCEL_RESERVATION" then
                -- self:onCancelReservation(msg, data.reservationId)
                print("CANCEL_RESERVATION not handled")
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
            print("no answer for", forMsg.data[1])
        end
    end

    self:setProviderSorting("distance_asc")

    
    -- self:pingStorageProviders() -- do not ping on init!
    -- TODO add provider ping for turtles, since they do not listen to the storage channel by default
    -- or open storage channel permanently, to listen to providers but not contribute?

    -- anyways, ping on startup is a lot of messages, turtleCount*providerCount (best case)

end


function TurtleStorage:getProviderPos() -- override
    if self.miner then
        return self.miner.pos
    end
end
function TurtleStorage:getRequestingPos() -- override
    if self.miner then
        return self.miner.pos
    end
end

function TurtleStorage:handleItemsDelivered(msg)
    -- perhaps for turtle to turtle delivery?
    print("handleItemsDelivered not implemented")
end

function TurtleStorage:onPickupItems(msg, reservationId)
    -- maybe for turtle to turtle delivery and then transfer, probably better with handeItemsDelivered
    print("onPickupItems not implemented")
end

function TurtleStorage:getItemList()
    print("getItemList not implemented for TurtleStorage")
    -- perhaps return own inventory content
    return {}
end


function TurtleStorage:requestTransportDestination(requester, requestingInv, oldPos)
    local answer = self.node:send(requester, {"REQUEST_TRANSPORT_DESTINATION", 
        { requestingInv = requestingInv, oldPos = oldPos }}, true, true, default.waitTime, default.priorityProtocol)
    if answer and answer.data[1] == "TRANSPORT_DESTINATION" then
        local newPos =  answer.data[2]
        if newPos then 
            newPos = vector.new(newPos.x, newPos.y, newPos.z)
        else newPos = oldPos end
        return newPos
    else 
        print("no dropoff request answer, using old")
        return oldPos
    end
end


function TurtleStorage:getDynamicTransportDestination(requester, requestingInv, oldPos)
    -- ask requester for position to drop off items
    local requestNewPosition = false
    if requestingInv == "player" then
        -- we need to ask player for positon
        requestNewPosition = true
    else
        -- determine if requester / requestingInv is static or dynamic
        -- no need to constantly harass requester for position if it is static
        if self.providers[requester] then 
            -- static requester (for now at least), in future those could be moving turtles as well
            requestNewPosition = false
        elseif self.turtles[requester] then 
            -- a moving requester
            requestNewPosition = true
        end
    end

    if requestNewPosition then 
        return self:requestTransportDestination(requester, requestingInv, oldPos)
    else
        return oldPos
    end    
end

function TurtleStorage:requestDeliveryConfirmation(requester, reservation, requestingInv, diffList)

    -- request extraction and wait for confirmation
    -- perhaps rename to requestExtraction, if that fails, try dropping into physical inventory
    -- answer could also not be "DELIVERY_CONFIRMED" but "DROP INTO INVENTORY" or similar

    local result = false
    local networkName = nil
    local waitTime = default.waitTime
    if requestingInv == "player" then 
        waitTime = 60*2
        networkName = nil -- "player"
    else 
        networkName = self.miner.getWiredNetworkName() -- not sure if it should stay there or not
        print("networkName", networkName)
    end

    local answer, manualConfirmation
    local requestConfirmation = function() 
        answer = self.node:send(requester, {"ITEMS_DELIVERED", 
        { reservation = reservation, requestingInv = networkName or requestingInv, invList = diffList }},
        true, true, waitTime)
    end

    parallel.waitForAny( 
        requestConfirmation, 
        function()
            shell.switchTab(multishell.getCurrent())
            print("---------------------------\n     ITEMS DELIVERED\nPRESS ENTER TO CONFIRM\n---------------------------")
            local confirmed = read()
            manualConfirmation = true
        end
    )
    if answer and answer.data[1] == "DELIVERY_CONFIRMED" then
        print("delivery confirmed by requester", requester)
        result = true
    elseif manualConfirmation then 
        print("manual delivery confirmation")
        result = true
    else
        if answer then print(answer.data[1]) end
        print("no delivery confirmation from requester", requester)
        -- perhaps ping requester again if this happens often
    end
    return result
end


function TurtleStorage:pickupReservation(provider, reservationId)

    local ok, extractedToTurtle = false, nil
    local networkName = self.miner.getWiredNetworkName()
    print("networkName:", networkName)

    local waitTime = default.extractionWaitTime -- extracting can take some time

    local answer = self.node:send(provider, {"PICKUP_ITEMS", 
        { reservationId = reservationId, turtleName = networkName }}, true, true, waitTime)

    if answer and answer.data[1] == "ITEMS_EXTRACTED" then 
        local data = answer.data[2]
        print("extracted", data.name, data.count, "into turt", data.extractedToTurtle)
        ok = true
        extractedToTurtle = data.extractedToTurtle
        
    else
        print(answer and answer.data[1] or "NO ANSWER FROM PROVIDER")
    end
    return ok, extractedToTurtle
end


function TurtleStorage:onTask(msg)
    -- e.g. pickupanddeliver items: forward task to global task list, to not block receiving thread
    global.addTask(msg.data)
    self.node:answer(msg, {"TASK_ACCEPTED"})
end

function TurtleStorage:getState()
    -- super override
    local state = nil
    local miner = self.miner
    if miner and miner.pos then 
        state = {}
        state.type = "turtle_storage"
        state.id = computerId
        state.label = os.getComputerLabel() or computerId

        state.pos = miner.pos
        state.orientation = miner.orientation
        state.stuck = miner.stuck -- can be nil
        
        state.fuelLevel = miner:getFuelLevel()
        state.emptySlots = miner:getEmptySlots()

        if miner.taskList.first then
            state.task = miner.taskList.first[1]
            state.lastTask = miner.taskList.last[1]
        end
    end
    return state
end

function TurtleStorage:onRequestTurtleState(msg)
    -- dont respond if miner is not initialized
    self:handleProviderStateResponse(msg) -- update own record of provider
    local state = self:getState()
    if state then
        self.node:send(msg.sender, {"TURTLE_STATE", state })
    end
end

function TurtleStorage:pingStorageProviders()
    -- also broadcast your own state ? yes, we are a turtle with storage capabilities like pickup
    local state = self:getState()
    self.node:send( storageChannel, {"REQUEST_PROVIDER_STATE", state}, 
                    false, false, nil, default.priorityProtocol )
end


function TurtleStorage:onRequestProviderState(msg)
    -- Turtle: listen to providers but do not respond with own state
    -- this only receives if the storage channel is opened, which it might not be
    self:handleProviderStateResponse(msg)
end


return TurtleStorage