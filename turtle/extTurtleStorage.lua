

--############################################################## STORAGE related miner functions
local Miner = require("classMiner")
local utils = require("utils")

local Extension = {}

function Extension:hasStorageExtension()
    return true
end

function Extension.getWiredNetworkName()
	for i = 1, 5 do
		turtle.detect() -- instead of sleep
		for _, side in ipairs(redstone.getSides()) do
			local mainType, subType = peripheral.getType(side)
			if mainType == "modem" and peripheral.call(side, "isWireless") == false then 
				local name = peripheral.call(side, "getNameLocal")
				if name then return name end
			end
		end
	end
	return nil
end

function Extension:getTurtleInventoryList()
	-- turtle.getItemDetail(i) is instant
	-- scan inventory for storage related tasks
	local invList = {}
	local hasFuel = false 
	for i = 1, Miner.default.inventorySize do
		local data = turtle.getItemDetail(i)
		if data and data.name then
			if not hasFuel and Miner.fuelItems[data.name] then
				hasFuel = true --keep the fuel
				invList[i] = { name = data.name, count = data.count, protected = true }
			else
				invList[i] = { name = data.name, count = data.count, protected = false }
			end
		else
			invList[i] = { count = 0 }
		end
	end
	return invList
end

function Extension:getInvListDifference(invListBefore, invListAfter)
    local diffList = {}
    -- build new inventory list with difference in items
    for i = 1, Miner.default.inventorySize do 
        local before = invListBefore[i]
        local after = invListAfter[i]
        if before.name == after.name then
            if before.count == after.count then 
                before.protected = true
                diffList[i] = before
            elseif before.count > after.count then
                -- items removed -- should never happen -- condenseInventory might play a role though
                print("ITEMS REMOVED ON PICKUP?", before.name, before.count - after.count)
                diffList[i] = { name = before.name, count = 0, protected = true }
            else
                -- items added
                diffList[i] = { name = after.name, count = after.count - before.count, protected = false }
            end
        else
            if not before.name and after.name then
                -- new items
                diffList[i] = { name = after.name, count = after.count, protected = false }
            elseif before.name and not after.name then
                -- items removed -- should never happen -- condenseInventory might play a role though
                print("STACK REMOVED ON PICKUP?", before.name, before.count)
                diffList[i] = { name = before.name, count = 0, protected = true }
            else
                -- changed items -- should never happen
                print("STACK CHANGED ON PICKUP?", before.name, "to", after.name)
                diffList[i] = { name = after.name, count = after.count, protected = true }
            end
        end
    end
    return diffList
end


function Extension:pickupReservation(reservation)
    local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})

    local gotItems = false
    local diffList = {}

	local pos = reservation.pos
	if not self:navigateToPos(pos.x, pos.y, pos.z) then
        print("could not navigate to provider pos", pos.x, pos.y, pos.z)
    else

		local invListBefore = self:getTurtleInventoryList()

        local ok, extractedToTurtle = self.storage:pickupReservation(reservation.provider, reservation.id)
		if ok then 
			if extractedToTurtle then
				gotItems = true
			else
			--[[ -- TODO: rewrite this to pickup items from a chest
				local pickupInv
				for _,inv in ipairs(peripheral.getNames()) do
					local mainType, subType = peripheral.getType(inv)
					if subType == "inventory" then
						pickupInv = peripheral.wrap(inv)
						break
					end
				end
				if not pickupInv then 
					print("no inventory found for pickup ... ") 
					return
				else
					-- pickup items
					
					local itemName, count = data.name, data.count
					local remaining = count

					for slot = 1, pickupInv.size() do
						local slotData = pickupInv.getItemDetail(slot)
						if slotData and slotData.name == itemName then
							local toMove = math.min(slotData.count, remaining)
							-- bullshit ai generated code ...
							local moved = pickupInv.pushItems(self.Inventory, slot, toMove)
							if moved and moved > 0 then
								print(string.format("Turtle picked up %d of %s from pickup inventory", moved, itemName))
								remaining = remaining - moved
								if remaining <= 0 then
									break
								end
							end
						end
					end
					if remaining > 0 then 
						print("Turtle could not pick up all items, remaining:", remaining)
					end
				end ]]
			end

			local invListAfter = self:getTurtleInventoryList()
            diffList = self:getInvListDifference(invListBefore, invListAfter)
			
        else
			print(answer and answer.data[1] or "NO ANSWER FROM PROVIDER")
		end
    end

    self.taskList:remove(currentTask)
    return gotItems, diffList
end

function Extension:pickupAndDeliverItems(reservation, dropOffPos, requester, requestingInv)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	-- TODO: make this a checkpointed task

    local gotItems, diffList = self:pickupReservation(reservation)

    if gotItems then
        -- deliver items to requester (turtle, player, chest ...)
        local options = {
            safe = true,
            -- safeDistance = 3, -- within 3 blocks of goal, safety is ignored if block is not disallowed
            updateGoalFunc = function(oldGoal)
                return self.storage:getDynamicTransportDestination(requester, requestingInv, oldGoal)
            end,
        }

        if not self:navigate(dropOffPos.x, dropOffPos.y, dropOffPos.z, self.map, options) then 
            print("could not navigate to dropOffPos", dropOffPos.x, dropOffPos.y, dropOffPos.z)
        else
            -- confirm extraction (manual or by modem)
            local confirmed = self.storage:requestDeliveryConfirmation(requester, reservation, requestingInv, diffList)
            -- alternatively: drop items in inventory
        end
    end

    self:returnHome()

	self.taskList:remove(currentTask)
end

-- TODO: allow for multiple items to be picked up in one go

function Extension:pickupItems(itemName, count)
    -- request items which the turtle itself can come pick up
    local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})

    local received = 0
    local startPos = self.pos
    local startOrientation = self.orientation

    self.storage:setProviderSorting("distance_asc")
    local reservations = self.storage:requestReserveItems(itemName, count)

    if reservations then 
        -- use travelling salesman or just nearest pickup location
        table.sort(reservations, function(a,b) 
            local distA = utils.manhattanDistance(self.pos.x, self.pos.y, self.pos.z, a.pos.x, a.pos.y, a.pos.z)
            local distB = utils.manhattanDistance(self.pos.x, self.pos.y, self.pos.z, b.pos.x, b.pos.y, b.pos.z)
            return distA < distB
        end)

        for _, reservation in ipairs(reservations) do
            local gotItems, diffList = self:pickupReservation(reservation)
            if gotItems then
                print("picked up reserved items", itemName, reservation.reserved)
                received = received + reservation.reserved
            else
                print("could not pick up reserved items", itemName, reservation.reserved)
            end
        end
    end

    self:navigateToPos(startPos.x, startPos.y, startPos.z)
    self:turnTo(startOrientation)

    local result = (received >= count)

    self.taskList:remove(currentTask)
    return result, received
end

return Extension