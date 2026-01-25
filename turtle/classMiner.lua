local PathFinder = require("classPathFinder")
local CheckPointer = require("classCheckPointer")
--require("classMap")
require("classLogger")
require("classList")
require("classChunkyMap")
local bluenet = require("bluenet")
local config = config

-- local blockTranslation = require("blockTranslation")
-- local nameToId = blockTranslation.nameToId
-- local idToName = blockTranslation.idToName

local default = {
	waitTimeFallingBlock = 0.25,
	maxVeinRadius = 10, --8 MAX:16
	maxVeinSize = 256,
	inventorySize = 16,
	criticalFuelLevel = 512,
	goodFuelLevel = 4099,
	--maxHomeDistance = 128, -- unused
	file = "runtime/miner.txt",
	fuelAmount = 16,
	turtleName = "computercraft:turtle_advanced",
	pathfinding = {
		maxTries = 15,
		maxParts = 2,
		maxDistance = 10,
	}
}

local fuelItems = {
["minecraft:coal"]=80,
["minecraft:charcoal"]=80,
["minecraft:coal_block"]=800,
["minecraft:lava_bucket"]=1000,
}
-- do not translate

-- blocks that can explicitly be mined, without making the world look destroyed
-- otherwise turtle might decide to navigate through decorative blocks of the base
-- though this could lead to pathfinding issues if the target pos is a leaf block
local mineBlocks = {
["minecraft:cobblestone"]=true,
["minecraft:stone"]=true,
["minecraft:grass_block"]=true,
["minecraft:dirt"]=true,
["minecraft:gravel"]=true,
["minecraft:sand"]=true,
["minecraft:flint"]=true,
["minecraft:sandstone"]=true,
["minecraft:diorite"]=true,
["minecraft:granite"]=true,
["minecraft:andesite"]=true,
["minecraft:tuff"]=true,
["minecraft:deepslate"]=true,
["minecraft:cobbled_deepslate"]=true,
-- own array with fluids / allowedBlocks
["minecraft:water"]=true,
["minecraft:lava"]=true,
["minecraft:glass"]=true,
}
--mineBlocks = blockTranslation.translateTable(mineBlocks)


local inventoryBlocks = {
["minecraft:chest"]=true,
["minecraft:trapped_chest"]=true,
["minecraft:ender_chest"]=true, -- ?? 
["minecraft:shulker_box"]=true,
["minecraft:white_shulker_box"]=true,
["minecraft:orange_shulker_box"]=true,
["minecraft:magenta_shulker_box"]=true,
["minecraft:light_blue_shulker_box"]=true,
["minecraft:yellow_shulker_box"]=true,
["minecraft:lime_shulker_box"]=true,
["minecraft:pink_shulker_box"]=true,
["minecraft:gray_shulker_box"]=true,
["minecraft:light_gray_shulker_box"]=true,
["minecraft:cyan_shulker_box"]=true,
["minecraft:purple_shulker_box"]=true,
["minecraft:blue_shulker_box"]=true,
["minecraft:brown_shulker_box"]=true,
["minecraft:green_shulker_box"]=true,
["minecraft:red_shulker_box"]=true,
["minecraft:black_shulker_box"]=true,
["minecraft:hopper"]=true,
["minecraft:barrel"]=true,
}
--inventoryBlocks = blockTranslation.translateTable(inventoryBlocks)

local disallowedBlocks = {
["minecraft:chest"] = true,
["minecraft:hopper"]=true,
["computercraft:turtle_advanced"] = true,
["computercraft:computer_advanced"] = true,
["computercraft:wireless_modem_advanced"] = true,
["computercraft:monitor_advanced"] = true,
["minecraft:bedrock"]=true,
--["minecraft:glass"]=true,
["minecraft:white_wool"]=true,
}
--disallowedBlocks = blockTranslation.translateTable(disallowedBlocks)
-- local blocks = {
-- iron = { iron_ore = { id = "minecraft:iron_ore", doMine = true, level = 99 },
	-- { deepslate_iron_ore = { id = "minecraft:deepslate_iron_ore", doMine = true, level = 99 } }
-- coal = { coal
-- }

local oreBlocks = {
["minecraft:iron_ore"]=true,
["minecraft:deepslate_iron_ore"]=true,
["minecraft:coal_ore"]=true,
["minecraft:deepslate_coal_ore"]=true,
["minecraft:gold_ore"]=true,
["minecraft:deepslate_gold_ore"]=true,
["minecraft:diamond_ore"]=true,
["minecraft:deepslate_diamond_ore"]=true,
["minecraft:redstone_ore"]=true,
["minecraft:deepslate_redstone_ore"]=true,
["minecraft:lapis_ore"]=true,
["minecraft:deepslate_lapis_ore"]=true,
["minecraft:copper_ore"]=true,
["minecraft:deepslate_copper_ore"]=true,
["minecraft:emerald_ore"]=true,
["minecraft:deepslate_emerald_ore"]=true,

-- Nether ores
["minecraft:nether_gold_ore"]=true,
["minecraft:nether_quartz_ore"]=true,
["minecraft:ancient_debris"]=true,

-- Raw ore blocks (storage blocks of raw materials)
["minecraft:raw_iron_block"]=true,
["minecraft:raw_copper_block"]=true,
["minecraft:raw_gold_block"]=true,

-- Amethyst (geodes)
["minecraft:amethyst_block"]=true, 
-- ["minecraft:budding_amethyst"]=true, does not drop
["minecraft:amethyst_cluster"]=true,
["minecraft:large_amethyst_bud"]=true,
["minecraft:medium_amethyst_bud"]=true,
["minecraft:small_amethyst_bud"]=true,

}
--oreBlocks = blockTranslation.translateTable(oreBlocks)

local vector = vector
local debuginfo = debug.getinfo
local tablepack = table.pack
local tableunpack = table.unpack
local osEpoch = os.epoch

local vectors = {
	[0] = vector.new(0,0,1),  -- 	+z = 0	south
	[1] = vector.new(-1,0,0), -- 	-x = 1	west
	[2] = vector.new(0,0,-1), -- 	-z = 2	north
	[3] = vector.new(1,0,0),  -- 	+x = 3 	east
}

local vectorUp = vector.new(0,1,0)
local vectorDown = vector.new(0,-1,0)

Miner = {}

function Miner:new()
	local o = o or {} --Worker:new()
	setmetatable(o,self)
	self.__index = self
	print("----INITIALIZING----")
	assert(turtle,"this device is not a turtle")
	
	o.fuelLimit = turtle.getFuelLimit()
	if o.fuelLimit == "unlimited" then o.fuelLimit = 0 end
	
	o.home = nil
	o.startupPos = nil
	o.homeOrientation = 0
	o.orientation = 0
	o.node = global.node
	o.nodeRefuel = global.nodeRefuel
	o.nodeStorage = global.nodeStorage
	o.pos = vector.new(0,70,0)
	o.gettingFuel = false
	o.initializing = true
	o.lookingAt = vector.new(0,0,0)
	o.map = ChunkyMap:new(true)
	o.taskList = List:new()
	o.vectors = vectors
	o.checkPointer = CheckPointer:new()
	o.statusCount = 0
	
	o:initialize() -- initialize after starting parallel tasks in startup.lua
	--print("--------------------")
	return o
end


function Miner:initialize()
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	-- preset chunk request but try not to during initialization
	self.map.requestChunk = function(chunkId) return self:requestChunk(chunkId) end
	self.map:setCheckFunction(self.checkOreBlock)
	
	self:initPosition()
	self:refuel(true)
	print("fuel level:", turtle.getFuelLevel())

	self:initOrientation()

	self.taskList:remove(currentTask)
end	

function Miner:finishInitialization()
	-- split initialization into two parts
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	if not self:requestStation() then
		-- TODO: load station from settings
		self:setHome(self.pos.x, self.pos.y, self.pos.z)
	end
	self:setStartupPos(self.pos)

	self:refuel()

	
	local existsCheckpoint = self.checkPointer:existsCheckpoint()
	if not existsCheckpoint then
		self:returnHome()
	end

	self.initializing = nil
	self.taskList:remove(currentTask)

	if existsCheckpoint then
		if self.checkPointer:load(self) then
			if not self.checkPointer:executeTasks(self) then
				self:error("CHECKPOINT NOT EXECUTED")
			end
		end
	end
	
end

function Miner:initPosition()
	local x,y,z = gps.locate()
	if x and y and z then
		self.pos = vector.new(x,y,z)
	else
		--gps not working
		self:error("GPS UNAVAILABLE",true)
		-- self.pos = vector.new(0,70,0)
	end
	print("position:",self.pos.x,self.pos.y,self.pos.z)
end

function Miner:initOrientation()
	local newPos
	local turns = 0
	for i=1,4 do
		if not turtle.forward() then
			self:turnLeft()
			turns = turns + 1
		else
			newPos = vector.new(gps.locate())
			break
		end
	end
	if not newPos then
		-- retry with breaking
		print("breaking blocks")
		for i=1,4 do
			local hasBlock, data = turtle.inspect()
			if not Miner.checkDisallowed(data.name) then -- or checkSafe(data.name)
				turtle.dig()
				sleep(default.waitTimeFallingBlock)
			end
			if not turtle.forward() then
				self:turnLeft()
				turns = turns + 1
			else
				newPos = vector.new(gps.locate())
				break
			end
		end
	end
	if not newPos then
		self:sendAlert()
		self:error("ORIENTATION NOT DETERMINABLE",true)
		self.orientation = 0
	else
		-- print(newPos, self.pos, turns, self.orientation)
		local diff = newPos - self.pos
		self.pos = newPos
		if diff.x < 0 then self.orientation = 1
		elseif diff.x > 0 then self.orientation = 3
		elseif diff.z < 0 then self.orientation = 2
		else self.orientation = 0
		end
		self:updateLookingAt()

		-- go back without requesting a chunk --self:back()
		if turtle.back() then 
			self.pos = self.pos - self.vectors[self.orientation]
		end
		
		self:turnTo((self.orientation+turns)%4)
		self.homeOrientation = self.orientation
	end
	print("orientation:", self.orientation)
end

function Miner:save(fileName)
	-- this already includes the map!
	if not fileName then fileName = default.file end
	local f = fs.open(fileName,"w")
	f.write(textutils.serialize(self))
	f.close()
end
function Miner:load(fileName)
	if not fileName then fileName = default.file end
	local f = fs.open(fileName,"r")
	if f then
		self = textutils.unserialize( f.readAll() )
		f.close()
	else
		print("FILE DOES NOT EXIST")
	end
end

function Miner:setStartupPos(pos)
	self.startupPos = vector.new(pos.x,pos.y,pos.z)
end
function Miner:setHome(x,y,z)
	self.home = vector.new(x,y,z)
	print("home:", self.home.x, self.home.y, self.home.z)
end

function Miner:requestMap()
	-- ask host for the map
	local retval = false
	if self.node and self.node.host then
		local answer, forMsg = self.node:send(global.node.host,
		{"REQUEST_MAP"},true,true,10)
		if answer then
			if answer.data[1] == "MAP" then
				retval = true
				self.map:setMap(answer.data[2])
				-- not just the map but all map information, including the log etc.
			end
		end
	end
	return retval  
end

function Miner:requestChunk(chunkId)
	-- ask host for a chunk
	-- perhaps use own protocol for this?
	local start = osEpoch("local")
	if self.node and self.node.host then
		local answer, forMsg = self.node:send(self.node.host,
			{"REQUEST_CHUNK", chunkId},true,true,1,"chunk")
		if answer then
			if answer.data[1] == "CHUNK" then
				print(osEpoch("local")-start,"RECEIVED CHUNK", chunkId)
				return answer.data[2]
			else
				print("received other", answer.data[1])
			end
		end
		--print("no answer")
	end
	print(osEpoch("local")-start, "CHUNK REQUEST FAILED", chunkId)
	return nil
end

function Miner:requestStation()
	-- ask host for station
	local retval = false
	if global.node and global.node.host then
		local answer, forMsg = self.node:send(global.node.host,{"REQUEST_STATION"},true,true,10)
		if answer then
			if answer.data[1] == "STATION" then
				retval = true
				local station = answer.data[2]
				self:setStation(station)
			elseif answer.data[1] == "STATIONS_FULL" then
				self:setStation(nil)
			end
			--print("station", textutils.serialize(answer.data[2]))
		else
			print("no station answer")
		end
	else
		print("no station host or node", global.node, global.node.host)
	end
	
	return retval
end
function Miner:setStation(station)
	if station then
		self:setHome(station.pos.x,station.pos.y,station.pos.z)
		if station.orientation then
			self.homeOrientation = station.orientation
		end
		
		--if self.taskList.count == 0 -- no task
		--	or self.taskList.count == 1 then -- or initializing
		--	self:returnHome()
		--end
	else
		-- TODO: try remember station, lmao
		-- settings set get etc.?
		print("NO STATION AVAILABLE")
	end
end

function Miner:sendAlert()
	-- nofity host to be recovered at pos
	-- alternatively broadcast distress signal to all turtles and wait for recovery
	local result = false

	self.stuck = true
	print("help me stepbro, im stuck D:")

	local state = {}
	state.id = os.getComputerID()
	state.label = os.getComputerLabel() or id
	state.time = osEpoch("utc")
		
	state.pos = self.pos
	state.orientation = self.orientation
	
	state.fuelLevel = self:getFuelLevel()
	state.emptySlots = self:getEmptySlots()
	
	if self.taskList.first then
		state.task = self.taskList.first[1]
		state.lastTask = self.taskList.last[1]
	end

	-- why not just use default state communication?
	-- -> its an important event that needs according handling

	local start = osEpoch("local")
	if self.node and self.node.host then
		local answer, forMsg = self.node:send(self.node.host,
			{"ALERT", state },true,true,5)
		if answer then
			if answer.data[1] == "ALERT_RECEIVED" then
				print(osEpoch("local")-start,"ALERT RECEIVED")
				result = true
			else
				print("received other", answer.data[1])
			end
		end
		--print("no answer")
	end
	
	if not result then 
		print(osEpoch("local")-start, "ALERT FAILED")
		-- TODO: broadcast to turtles directly if host is not available
		-- alternatively continuously resend alert until confirmed

	end
	return result
end

function Miner:getCostHome()
	local result = 0
	if self.home then
		local diff = self.pos - self.home
		result = math.abs(diff.x) + math.abs(diff.y) + math.abs(diff.z)	
	end
	return result
end

function Miner:returnHome()
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = false
	self.returningHome = true
	if self.home then
		print("RETURNING HOME", self.home.x, self.home.y, self.home.z)
		result = self:navigateToPos(self.home.x, self.home.y, self.home.z)
		self:turnTo(self.homeOrientation)
	end
	self.returningHome = false
	self.taskList:remove(currentTask)
	return result
end

function Miner:error(reason,real)
	-- TODO: create image of current Miner to load later on
	-- self:save()

	if self.taskList.count > 0 then func = "ERR:"..self.taskList.first[1]
	else func = "ERR:unknown" end
	self.taskList:clear()
	-- OPTI: optional: delete Checkpoint / save after clearing taskList
	if real ~= true then
		self.checkPointer:save(self)
	end
	error({real=real,text=reason,func=func}) -- watch out that this is not caught by some other function
end
function Miner:addCheckTask(task, isCheckpointable, ...)
	-- called by most functions to interrupt execution
	-- if task[1] is nil, could be due to return self:function()

	if self.stop then
		self.stop = false
		self:error("stopped",false)
	end

	if isCheckpointable and self.taskList.first
		and ( task[1] == "?" or self.taskList.first[1] == task[1] ) then
		-- task already currently in list (probably loaded by checkpointer)
		return self.taskList.first
	else
		return self.taskList:addFirst(task)
	end
end

function Miner:checkStatus()
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	-- called by self:forward()
	self:refuel()
	self:cleanInventory()
	self.statusCount = self.statusCount + 1
	if self.statusCount > 40 then
		self:checkMinedTurtle()
		self.statusCount = 0
	end
	
	self.taskList:remove(currentTask)
end




function Miner:getFuelLevel()
	return turtle.getFuelLevel()
end

function Miner:hasFullInventory(minOpen)
	minOpen = minOpen or 0
	if self:getEmptySlots() <= minOpen then
		return true
	end
	return false
end

function Miner:getEmptySlots()
	local empty = 0
	for slot = 1,default.inventorySize do
		if turtle.getItemCount(slot) == 0 then
			empty = empty + 1
		end
	end
	return empty
end


function Miner:findInventoryItem(name)
	-- check for item in inventory
	local found = nil
	for slot = 1,default.inventorySize do
		local data = turtle.getItemDetail(slot)
		if data and data.name == name then
			found = slot
			break
		end
	end
	return found
end

function Miner:checkMinedTurtle()
	-- in very rare cases, a turtle might have ran in front of another turtle during stripmining without safety checks
	-- check inventory for turtles and place them back down 
	local slot = self:findInventoryItem(default.turtleName)
	if slot then
		print("OH NO, I MINED A TURTLE :(")
		self:select(slot)
		-- try and place it
		local direction
		if turtle.placeUp() then direction = "top"
		elseif turtle.placeDown() then direction = "bottom"
		elseif turtle.place() then direction = "front"
		else
			print("could not place turtle")
			return false
		end
		
		if direction then 
			sleep(1) 
			-- give it half the fuel
			for slot = 1, default.inventorySize do
				local data = turtle.getItemDetail(slot)
				if data and fuelItems[data.name] then
					-- could be unreliable if turtle has more than one stack but doesnt really matter
					self:select(slot)
					local amount = data.count/2 
					if direction == "top" then turtle.dropUp(amount)
					elseif direction == "bottom" then turtle.dropDown(amount)
					elseif direction == "front" then turtle.drop(amount) end
					print("giving turtle", amount, "fuel")
					break 
				end
			end
			sleep(1) 
			print("placed", direction, "now turning on")
			local tut = peripheral.wrap(direction)
			if tut then 
				print("turning on turtle", tut.getID())
				tut.turnOn()
				sleep(5) -- give it some time to fuck off before continuing with whatever
				return true
			else 
				self:error("FAILED TO RESTART TURTLE",true)
				return false
			end
		end
	end
	return true
end


function Miner:cleanInventory()
	-- check for full inventory and take action
	-- if turtles are still being mined and not placed back down, increase to at least 1 open slot at all times
	if not self.cleaningInventory and self:getEmptySlots() == 0 then 
		self:condenseInventory()
		if self:getEmptySlots() < 2 then
			self:dumpBadItems()
			if self:getEmptySlots() < 2 then
				self:offloadItemsAtHome()
			end
		end
	end
end

function Miner:offloadItemsAtHome()
	-- return home, empty inventory, return to task
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	self.cleaningInventory = true
	
	local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
	local startOrientation = self.orientation

	if self:returnHome() then
		self:transferItems()
		if self:getEmptySlots() < 2 then
			-- catch this in stripmine e.g.
			self.cleaningInventory = false
			self:error("INVENTORY_FULL",true)
		else
			-- do nothing and return to task
			self:navigateToPos(startPos.x, startPos.y, startPos.z)
			self:turnTo(startOrientation)
		end
	end

	self.cleaningInventory = false
	self.taskList:remove(currentTask)
end

function Miner:transferItems()
	--check for chest and transfer items
	--do not transfer all fuel items (keep 1 stack)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local hasFuel = false
	local hasInventory = false
	local startOrientation = self.orientation
	
	for k=1,4 do
	--check for chest
		self:inspect(true)
		local block = self:getMapValue(self.lookingAt.x, self.lookingAt.y, self.lookingAt.z)
		if block and inventoryBlocks[block] then
			hasInventory = true
			break
		end
		self:turnRight()
	end
	if not hasInventory then 
		print("no inventory found")
		--assert(hasInventory, "no inventory found")
	else
		local startSlot = turtle.getSelectedSlot()
		for i = 0,default.inventorySize-1 do
			local slot = (i+startSlot-1)%default.inventorySize +1
			local data = turtle.getItemDetail(slot)
			if data and data.name then
				if not hasFuel and fuelItems[data.name] then
					hasFuel = true --keep the fuel
				else
					--transfer items
					self:select(slot)
					local ok = turtle.drop(data.count)
					if ok ~= true then
						print(ok,"inventory in front is full")
						break
					end
				end
			end
		end
	end
	self:turnTo(startOrientation)
	self.taskList:remove(currentTask)
end

function Miner:dumpBadItems(dropAll)
	--check for bad items and drop them
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local startSlot = turtle.getSelectedSlot()
	for i = 0,default.inventorySize-1 do
		local slot = (i+startSlot-1)%default.inventorySize +1
		local data = turtle.getItemDetail(slot)
		if data and (mineBlocks[data.name] or ( dropAll and not fuelItems[data.name])) then
			--drop items
			self:select(slot)
			local ok = turtle.drop(data.count)
			if ok ~= true then
				print(ok,"inventory in front is full")
			end
		end
	end	
	self.taskList:remove(currentTask)
end

function Miner:condenseInventory()
	--stack items
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local startSlot = turtle.getSelectedSlot()
	for i = 0,default.inventorySize-1 do
		local slot = (i+startSlot-1)%default.inventorySize +1
		local data = turtle.getItemDetail(slot)
		if data and data.name then
			for targetSlot=1,default.inventorySize do
				--search matching items starting at the first slot
				if targetSlot ~= slot then
					local targetData = turtle.getItemDetail(targetSlot)
					if targetData and targetData.name == data.name then
						local fromSlot = slot
						local toSlot = targetSlot
						if targetSlot > slot then
							fromSlot = targetSlot
							toSlot = slot
						end
						--deal with multiple stacks
						if turtle.getItemSpace(toSlot) > 0 then
							self:select(fromSlot)
							turtle.transferTo(toSlot)
							if turtle.getItemCount(fromSlot) == 0 then
								break
							end
						end
					end
				end
			end
		end
	end
	self.taskList:remove(currentTask)
end

function Miner:select(slot)
	if slot > default.inventorySize then
		slot = (slot-1)%default.inventorySize+1
	end

	if turtle.getSelectedSlot() ~= slot then
		return turtle.select(slot)
	end
	return true
end

function Miner:refuel(simple)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})

	local refueled = false
	local goodLevel = false
	
	if not self.gettingFuel and self.fuelLimit > 0 and turtle.getFuelLevel() <= default.criticalFuelLevel then
		print("refueling...")
		for slot = 1, default.inventorySize do
			data = turtle.getItemDetail(slot)
			if data and fuelItems[data.name] then
				self:select(slot)
				repeat
					local ok, err = turtle.refuel(1)
					goodLevel = ( turtle.getFuelLevel() >= default.goodFuelLevel )
				until goodLevel or not ok
				if goodLevel then break end
			end
		end
		if turtle.getFuelLevel() > default.criticalFuelLevel then
			-- and turtle.getFuelLevel() > 2 * self:getCostHome() then
			refueled = true
		elseif turtle.getFuelLevel() == 0 then
			-- ran out of fuel
			self:sendAlert()
			self:error("NEED FUEL, STUCK",true)
		else
			if not simple then -- for initializing
			--if self:getCostHome() * 2 > turtle.getFuelLevel() then
				local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
				local startOrientation = self.orientation
				if not self:getFuel() then
					if not self:returnHome() and turtle.getFuelLevel() == 0 then
						-- could not refuel, ran out on the way back home
						self:sendAlert()
						self:error("NEED FUEL, STUCK",true)
					else
						self:error("NEED FUEL",true) -- -> terminates stripMine etc.
					end
				else
					refueled = true
					if not self.returningHome then
						self:navigateToPos(startPos.x, startPos.y, startPos.z)
						self:turnTo(startOrientation)
					end
					-- actual refueling happens with the next refuel call
				end
			--end
			end
		end
		print("fuel level:", turtle.getFuelLevel())
	else
		refueled = true
	end
	self.taskList:remove(currentTask)
	return refueled
end







function Miner:clearStaleLocks()
	-- clear old locks on stations to avoid waiting for noone
    local currentTime = osEpoch("utc")
    for id, station in pairs(config.stations.refuel) do
        if station.occupied and (currentTime - (station.lastClaimed or 0)) > 10000 then -- 10 seconds
            -- print("Clearing stale lock on station:", id)
            station.occupied = false
        end
    end
end

function Miner:requestRefuelStation()

	self.refuelClaim = {
		approvedByOwner = false,
		ok = false,
		occupiedStation = nil,
		waiting = false,
		lastClaimed = 0,
		priority = 0,
	}
	local refuelClaim = self.refuelClaim

	-- clear occupied stations
	for id,station in pairs(config.stations.refuel) do
		station.occupied = false
	end

	-- get all the occupied stations
	bluenet.openChannel(bluenet.modem, bluenet.default.channels.refuel)
	self.nodeRefuel:send(bluenet.default.channels.refuel, {"REQUEST_STATION"}, false, false) 
	sleep(1) -- handle responses in onReceive and onRequestAnswer in miner/receive.lua
	-- config should now be updated with occupied stations

	refuelClaim.waiting = true
	-- try to claim a station or wait for one
	local startTime = osEpoch("utc")
	repeat
		local ok = self:tryClaimStation()
		if not ok then 
			sleep(0.5 + math.random()) -- random offset so not every turtle requests at the same time
			self:clearStaleLocks()
		end
	until refuelClaim.ok or ( osEpoch("utc") - startTime )  > 500000 -- 200 seconds for big boy refuels

	refuelClaim.waiting = false

	if refuelClaim.ok and refuelClaim.occupiedStation then
		-- claim successfull
	else 
		-- print(refuelClaim.ok, "claim station", refuelClaim.occupiedStation, "failed")
		refuelClaim.occupiedStation = nil
	end

	return refuelClaim.occupiedStation
end


function Miner:tryClaimStation()
	local refuelClaim = self.refuelClaim
	local result = false
	for id,station in pairs(config.stations.refuel) do
		if not station.occupied or station.occupied == false then
			refuelClaim.occupiedStation = id -- reserve it to deny other claim requests
			refuelClaim.lastClaimed = osEpoch("utc")
			-- print("claiming station", id)
			refuelClaim.ok = true
			self.nodeRefuel:send(bluenet.default.channels.refuel, {"CLAIM_STATION", id}, false, false)
			sleep(1) -- wait for denying answers

			if refuelClaim.ok or refuelClaim.approvedByOwner then 
				print("claimed station", id, "owner approved:", refuelClaim.approvedByOwner)
				refuelClaim.ok = true
				result = true
				break
			else
				refuelClaim.occupiedStation = nil
				refuelClaim.lastClaimed = 0
				--print("claim station failed", id)
			end
		end
	end
	return result
end

function Miner:releaseStation()
	if self.refuelClaim and self.refuelClaim.occupiedStation then
		--print("releasing station", self.refuelClaim, self.refuelClaim.occupiedStation)
		self.refuelClaim.isReleasing = true
		self.nodeRefuel:send(bluenet.default.channels.refuel, 
				{"RELEASE_STATION", self.refuelClaim.occupiedStation}, false, false)
		-- wait a bit (~1s) to solve claim conflicts using owner acks
		self:back()
		self:back()
		self:back()
		-- self:back()
		-- self:back()
		-- self:back()
		--sleep(1)
		
		self.refuelClaim = {occupiedStation = nil}
		--print(osEpoch("utc")/1000, "released station")
	end
	-- close channel to stop listening
	bluenet.closeChannel(bluenet.modem, bluenet.default.channels.refuel)
	
end

function Miner:getRefuelStation(random)
	local id 
	-- print("not random", not random, self.nodeRefuel)
	if not random and self.nodeRefuel then
		id = self:requestRefuelStation()
	end
	if id then 
		return id
	else
		-- fallback, use random station 
		local ct = 0
		for _,v in pairs(config.stations.refuel) do ct = ct + 1 end
		local index = math.random(1, ct)
		ct = 0
		for id, station in pairs(config.stations.refuel) do
			ct = ct + 1
			if ct == index then 
				print("using random station", id)
				return id
			end
		end
	end
end


function Miner:getFuel()

	-- default method:
	-- 1. move near to refuel stations based on config
	-- 2. ask turtles if stations are occupied 
	-- 3. claim station
	--    if occupied, wait for station
	-- 3. move to station and refuel
	-- 4. report station as free and leave

	-- no station available:
	-- wait in queue for station, but this would also require messaging etc...
	-- not nice
	-- could use home-stations as queue that is always available

	-- no host available:
	-- use config or ask other turtles if they are refueling

	-- TODO: advanced method:
	-- add support turtles that represent a temporary refuel station
	-- they act like a passive provider chest
	-- this way turtles dont have to return all the way home for big tasks
	-- different types of turtles
	-- general turtle with all the default methods like navigation etc.
	-- types: support(refuel, collect items), miner, "forester"

	-- TODO: change from config to internal variable?
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	self.gettingFuel = true
	local result = false
	
	local ok, err = pcall( function() 

		-- move near the refuel stations

		local isInQueue = false
		
		if config.stations.refuelQueue and config.stations.refuelQueue.origin then 
			local tries = 0
			local origin = config.stations.refuelQueue.origin
			local maxDistance = config.stations.refuelQueue.maxDistance or 8
			repeat 
				tries = tries + 1
				local randomPosition = vector.new(
					math.random(origin.x-maxDistance, origin.x+maxDistance),
					origin.y,
					math.random(origin.z-maxDistance, origin.z+maxDistance)
				)
				print("moving to queue", randomPosition)
				isInQueue = self:navigateToPos(randomPosition.x, randomPosition.y, randomPosition.z)
				if not isInQueue and tries > 3 then
					print("cant reach refuel queue")
					isInQueue = true -- set to true anyways, should be nearby the queue
					-- return false-- only leave pcall function !
					break
				end
			until isInQueue
		end

		local useRandomStation = not isInQueue
		-- print("using random station", useRandomStation)
		local id = self:getRefuelStation(useRandomStation)
		local station = config.stations.refuel[id]

		-- actually refuel
		if not self:navigateToPos(station.pos.x, station.pos.y, station.pos.z) then
			--print("unable to reach station")
			return false
		end

		if station.orientation then 
			self:turnTo(station.orientation) 
		end
		
		local hasInventory = false
		
		for k=1,4 do
		--check for chest
			self:inspect(true) -- true for wrong map entries or new stations
			local block = self:getMapValue(self.lookingAt.x, self.lookingAt.y, self.lookingAt.z)
			if block and inventoryBlocks[block] then
				hasInventory = true
				break
			end
			self:turnRight()
		end
		if not hasInventory then 
			print("no inventory found")
			--assert(hasInventory, "no inventory found")
		else
			result = turtle.suck(default.fuelAmount)
		end
	
	end )

	-- !! cancellation while getting fuel can result in no more refueling
	if not ok then
		self.gettingFuel = false
		bluenet.closeChannel(bluenet.modem, bluenet.default.channels.refuel)
		error(err,0) -- pass error
	end
	
	if not result then
		print("unable to refuel", result)
		result = false
	end

	-- done refueling
	self:releaseStation()

	if self:getEmptySlots() < 10 then -- 8
		-- already at home, also offload items
		self:offloadItemsAtHome() 
	end

	self:returnHome()

	self.gettingFuel = false
	
	self.taskList:remove(currentTask)
	return result
end




function Miner:setMapValue(x,y,z,value)
	--self.map:logData(x,y,z,value)
	self.map:setData(x,y,z,value,true)
end

function Miner:getMapValue(x,y,z)
	return self.map:getData(x,y,z)
end	

function Miner:turnTo(orient)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	orient = orient%4
	while self.orientation ~= orient do
	
		local diff = self.orientation - orient
		if ( diff > 0 and math.abs(diff) < 3 ) or ( self.orientation == 0 and orient == 3 ) then
			self:turnLeft()
		else
			self:turnRight()
		end
	end
	self.taskList:remove(currentTask)
end



function Miner:updateLookingAt()
	-- 	+z = 0	south
	-- 	-x = 1	west
	-- 	-z = 2	north
	-- 	+x = 3 	east
	self.lookingAt = self.pos + self.vectors[self.orientation]
end

function Miner:forward()
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.forward()
	if result then
		self:setMapValue(self.pos.x, self.pos.y, self.pos.z, 0)
		self.pos = self.pos + self.vectors[self.orientation]
		-- TODO: setMapValue of current position to avoid wrong entries
		--self:setMapValue(self.pos.x, self.pos.y, self.pos.z,default.turtleName)
	end
	self:checkStatus()
	--self.taskList:remove(currentTask)
	return result
end

function Miner:back()
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.back()
	if result then
		self:setMapValue(self.pos.x, self.pos.y, self.pos.z, 0)
		self.pos = self.pos - self.vectors[self.orientation]
		--self:setMapValue(self.pos.x, self.pos.y, self.pos.z,default.turtleName)
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner:up()
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.up()
	if result then
		self:setMapValue(self.pos.x, self.pos.y, self.pos.z, 0)
		self.pos.y = self.pos.y + 1
		--self:setMapValue(self.pos.x, self.pos.y, self.pos.z,default.turtleName)
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner:down()
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.down()
	if result then
		self:setMapValue(self.pos.x, self.pos.y, self.pos.z, 0)
		self.pos.y = self.pos.y - 1
		--self:setMapValue(self.pos.x, self.pos.y, self.pos.z,default.turtleName)
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner:turnLeft()
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	turtle.turnLeft()
	self.orientation = ( self.orientation - 1 ) % 4
	--self.taskList:remove(currentTask)
end

function Miner:turnRight()
	turtle.turnRight()
	self.orientation = ( self.orientation + 1 ) % 4
end

function Miner:dig(side)
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.dig(side)
	if result then
		self:updateLookingAt()
		-- local block = self:getMapValue(self.lookingAt.x, self.lookingAt.y, self.lookingAt.z)
		-- if block and block ~= 0 then
			self:setMapValue(self.lookingAt.x, self.lookingAt.y, self.lookingAt.z,0)
		-- end
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner:digUp(side)
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.digUp(side)
	if result then
		-- local block = self:getMapValue(self.pos.x, self.pos.y+1, self.pos.z)
		-- if block and block ~= 0 then
			self:setMapValue(self.pos.x, self.pos.y+1, self.pos.z, 0)
		-- end
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner:digDown(side)
	--local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = turtle.digDown(side)
	if result then
		-- local block = self:getMapValue(self.pos.x, self.pos.y-1, self.pos.z) 
		-- if block and block ~= 0 then
			self:setMapValue(self.pos.x, self.pos.y-1, self.pos.z, 0)
		-- end
	end
	--self.taskList:remove(currentTask)
	return result
end

function Miner.checkOreBlock(blockName)
	if blockName and blockName ~= 0 then
		if oreBlocks[blockName] then
			return true
		elseif string.find(blockName, "_ore") then
			oreBlocks[blockName] = true -- save this block as an ore
			-- TODO: save new blocks in translation on host when seeting map data?
			return true
		end
	end
	return false
end
local checkOreBlock = Miner.checkOreBlock

function Miner.checkDisallowed(id)
	-- blacklist function
	return disallowedBlocks[id]
end
local checkDisallowed = Miner.checkDisallowed

function Miner.checkSafe(id)
	-- whitelist function
	-- does not take changed blocks into account if id comes from the map value
	if not id or id == 0 or mineBlocks[id] or checkOreBlock(id) then
		return true
	end
	return false
end
local checkSafe = Miner.checkSafe

function Miner:inspect(safe)
	-- WARNING: NOT safe does NOT update the Map if the block has been explored before
	self:updateLookingAt()
	local block, hasBlock, data
	if not safe then 
		block = self:getMapValue(self.lookingAt.x, self.lookingAt.y, self.lookingAt.z)
	end
	if block == nil then
		-- never inspected before
		hasBlock, data = turtle.inspect()
		--block = hasBlock and ( nameToId[data.name] or data.name ) or 0
		self:setMapValue(self.lookingAt.x,self.lookingAt.y,self.lookingAt.z,
		( data and data.name ) or 0)
		block = data.name
	elseif checkOreBlock(block) then
		self.map:rememberOre(self.lookingAt.x,self.lookingAt.y,self.lookingAt.z, block)
	end
	return block, data
end

function Miner:inspectUp(safe)
	local block, hasBlock, data
	if not safe then
		block = self:getMapValue(self.pos.x, self.pos.y+1, self.pos.z)
	end
	if block == nil then
		hasBlock, data = turtle.inspectUp()
		self:setMapValue(self.pos.x,self.pos.y+1,self.pos.z,
		( data and data.name ) or 0)
		block = data.name
	elseif checkOreBlock(block) then
		self.map:rememberOre(self.pos.x,self.pos.y+1,self.pos.z, block)
	end
	return block, data
end

function Miner:inspectDown(safe)
	local block, hasBlock, data
	if not safe then
		block = self:getMapValue(self.pos.x, self.pos.y-1, self.pos.z)
	end
	if block == nil then
		hasBlock, data = turtle.inspectDown()
		self:setMapValue(self.pos.x,self.pos.y-1,self.pos.z,
		( data and data.name ) or 0)
		block = data.name
	elseif checkOreBlock(block) then
		self.map:rememberOre(self.pos.x,self.pos.y-1,self.pos.z, block)
	end
	return block, data
end
function Miner:inspectLeft()
	local block = self.pos + self.vectors[(orientation-1)%4]
	local name = self:getMapValue(block.x, block.y, block.z)
	local hasBlock, data
	if name == nil then
		self:turnTo((orientation-1)%4)
		hasBlock, data = turtle.inspect()
		self:setMapValue(block.x, block.y, block.z, 
		( data and data.name ) or 0)
		block = data.name
	elseif checkOreBlock(name) then
		self.map:rememberOre(block.x, block.y, block.z, name)
		block = name
	end
	return block, data
end
function Miner:inspectRight()
	local block = self.pos + self.vectors[(orientation+1)%4]
	local name = self:getMapValue(block.x, block.y, block.z)
	local hasBlock, data
	if name == nil then
		self:turnTo((orientation+1)%4)
		hasBlock, data = turtle.inspect()
		self:setMapValue(block.x, block.y, block.z,
		( data and data.name ) or 0)
		block = data.name
	elseif checkOreBlock(name) then
		self.map:rememberOre(block.x, block.y, block.z, name)
		block = name
	end
	return block, data
end

function Miner:inspectAll()
	--inspectLeft + inspectRigth ist gleich schnell wie inspectAll
	--AUßER: eines von beiden wurde bereits inspected und behind ist irrelevant
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	local orientation = self.orientation
	local hasBlock, data
	--self:inspect()
	self:inspectDown()
	self:inspectUp()
	
	-- inspect Front, Left, Behind, Right
	for i=0,3 do
		block = self.pos + self.vectors[(orientation+i)%4]
		local mapValue = self:getMapValue(block.x, block.y, block.z)

		if mapValue == nil then
			self:turnTo((orientation+i)%4)
			hasBlock, data = turtle.inspect()
			self:setMapValue(block.x, block.y, block.z, 
			( data and data.name ) or 0)
		elseif checkOreBlock(mapValue) then
			-- mark as ore block
			self.map:rememberOre(block.x, block.y, block.z, mapValue)
		end
	end
	self.taskList:remove(currentTask)
end

function Miner:digMove(safe)		
	-- tries to dig the block in front and move forwards
	-- while not mining any turtles
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local ct = 0
	local result = true	
	
	-- all changes here should be made in Down and Up as well
	
	-- optimization: if it is known that a block is in front -> dig first, then move
	-- trust, that the mapvalue is correct/up to date?
	-- could lead to mining another turtle
	-- why have the map in the first place if it cannot be trusted?
	-- solution: only check block if not safe -> no trust issues
	local blockName, data
	-- if not safe then
		-- blockName = self:inspect() -- or getMapValue for faster mining
		-- if blockName and blockName ~= 0 then
			-- if not checkDisallowed(blockName) then
				-- self:dig()
			-- end
		-- end
		-- -- else 
			-- -- nonone has been here before -> must be safe -- only for getMapValue
			-- -- but block could also be free so dig is redundant
			-- -- self:dig()
		-- -- end
	-- end
	-- end of optimization --> perhaps delete
	
	--try to move
	while not self:forward() do
		blockName, data = self:inspect(true) -- cannot move so there has to be a block
		--check block
		if blockName then
			--dig if safe
			local doMine = true
			if safe then
				doMine = checkSafe(blockName)
			else
				-- -> check if its explictly disallowed
				doMine = not checkDisallowed(blockName)
			end
			if doMine then
				self:dig()
				sleep(0.25)
				--print("digMove", checkSafe(blockName), blockName)
			else
				print("NOT SAFE",blockName)
				result = false -- return false
				break
			end
		end
		ct = ct + 1
		if ct > 100 then
			if turtle.getFuelLevel() == 0 then
				self:refuel()
				ct = 90
				--possible endless loop if fuel is empty -> no refuel raises error
			else
				print("UNABLE TO MOVE")
			end
			result = false -- return false
			break
		end
	end

	self.taskList:remove(currentTask)

	return ( result and ( blockName or true ) ) or false, data
end

function Miner:digMoveDown(safe)
	-- check digMove for documentation
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local ct = 0
	local result = true
	
	-- might be an unnecessary optimization for up/down
	-- delete if there are problems with turtles mining each other
	local blockName, data
	-- if not safe then
		-- blockName = self:inspectDown()
		-- if blockName and blockName ~= 0 then
			-- if not checkDisallowed(blockName) then
				-- self:digDown()
			-- end
		-- end
	-- end
	
	while not self:down() do
		blockName, data = self:inspectDown(true)
		if blockName then
			local doMine = true
			if safe then
				doMine = checkSafe(blockName)
			else
				doMine = not checkDisallowed(blockName)
			end
			if doMine then
				self:digDown()
				sleep(0.25)
				--print("digMoveDown", checkSafe(blockName), blockName)
			else
				print("NOT SAFE DOWN", blockName)
				result = false
				break
			end
		end
		ct = ct+1
		if ct>100 then
			if turtle.getFuelLevel() == 0 then
				self:refuel()
				ct = 90
			else
				print("UNABLE TO MOVE DOWN")
			end
			result = false
			break
		end
	end
	
	self.taskList:remove(currentTask)
	return ( result and ( blockName or true ) ) or false, data
end

function Miner:digMoveUp(safe)
	-- check digMove for documentation
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local ct = 0
	local result = true
	
	local blockName, data
	-- if not safe then
		-- blockName = self:inspectUp()
		-- if blockName and blockName ~= 0 then
			-- if not checkDisallowed(blockName) then
				-- self:digUp()
			-- end
		-- end
	-- end
	
	while not self:up() do
		blockName, data = self:inspectUp(true)
		if blockName then
			local doMine = true
			if safe then
				doMine = checkSafe(blockName)
			else
				doMine = not checkDisallowed(blockName)
			end
			if doMine then
				self:digUp()
				sleep(0.25)
				--print("digMoveUp", checkSafe(blockName), blockName)
			else
				print("NOT SAFE UP", blockName)
				result = false
				break
			end
		end
		ct = ct+1
		if ct>100 then
			if turtle.getFuelLevel() == 0 then
				self:refuel()
				ct = 90
			else
				print("UNABLE TO MOVE UP")
			end
			result = false
			break
		end
	end
	self.taskList:remove(currentTask)
	return ( result and ( blockName or true ) ) or false, data
end


function Miner:digToPos(x,y,z,safe)	
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	print("digToPos:", x, y, z, "safe:", safe)
	-- TODO: if digToPos fails, retry with navigateToPos
	-- 		if that fails as well (not immediately), return to digToPos
	-- NO, navigateToPos calls digToPos which could lead to recursive calls
	
	-- inspect is unnecessary due to digMove inspecting on demand
	local result = true
	
	if self.pos.x < x then
		self:turnTo(3) -- +x
		self:inspect()
	elseif self.pos.x > x then
		self:turnTo(1) -- -x
		self:inspect()
	end
	while self.pos.x ~= x do
		if not self:digMove(safe) then result = false; break end
		self:inspect()
		self:inspectDown()
		self:inspectUp()
	end
	if result then
		if self.pos.z < z then
			self:turnTo(0) -- +z
			self:inspect()
		elseif self.pos.z > z then
			self:turnTo(2) -- -z
			self:inspect()
		end
		
		while self.pos.z ~= z do
			if not self:digMove(safe) then result = false; break end
			self:inspect()
			self:inspectDown()
			self:inspectUp()
		end
		
		if result then
			while self.pos.y ~= y do
				if self.pos.y < y then
					if not self:digMoveUp(safe) then result = false; break end
					self:inspect()
					self:inspectUp()
				else
					if not self:digMoveDown(safe) then result = false; break end
					self:inspect()
					self:inspectDown()
				end
			end
		end
	end
	self.taskList:remove(currentTask)
	return result
end

function Miner:mineVein() 
	--ore in front? dig, move, inspect
	--ore left? turnleft, dig, move, inspect
	--ore right? turnright, dig, move, inspect
	--ore behind? turnright, turnright, dig, move, inspect
	--ore up? digup, moveup, inspect
	--ore down? digdown, movedown, inspect
	--ore somewhere on map? check last seen ores via list
		--dig towards nearest or last seen ore (last seen = nearest?)
		-- inspect
	--no ores: exit
	--else repeat
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	-- TODO: give turtle a bucket and gobble up lava to refuel

	local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
	local startOrientation = self.orientation
	local block
	local ct = 0
	local isInVein = false
	
	repeat
	
	self:inspectAll()
	--in front
	block = self.pos + self.vectors[self.orientation]
	if checkOreBlock(self:getMapValue(block.x, block.y, block.z)) then
		self:digMove()
		isInVein = true
	else -- left
		block = self.pos + self.vectors[(self.orientation-1)%4]
		if checkOreBlock(self:getMapValue(block.x, block.y, block.z)) then
			self:turnLeft()
			self:digMove()
			isInVein = true
		else -- right
			block = self.pos + self.vectors[(self.orientation+1)%4]
			if checkOreBlock(self:getMapValue(block.x, block.y, block.z)) then
				self:turnRight()
				self:digMove()
				isInVein = true
			else -- behind
				block = self.pos + self.vectors[(self.orientation+2)%4]
				if checkOreBlock(self:getMapValue(block.x, block.y, block.z)) then
					self:turnRight()
					self:turnRight()
					self:digMove()
					isInVein = true
				else -- up
					if checkOreBlock(self:getMapValue(self.pos.x, self.pos.y+1, self.pos.z)) then
						self:digMoveUp()
						isInVein = true
					else -- down
						if checkOreBlock(self:getMapValue(self.pos.x, self.pos.y-1, self.pos.z)) then
							self:digMoveDown()
							isInVein = true
						else -- nearest ore, if ore has been found before
							if isInVein then
								local nextOre = self.map:findNextBlock(self.pos, 
									checkOreBlock
									,default.maxVeinRadius)
								if nextOre then
									self:digToPos(nextOre.x, nextOre.y, nextOre.z)
								else
									-- done
									break
								end
							else
								-- do not look if none has been found before
								break
							end
						end
					end
				end
			end
		end
	end
	ct = ct + 1
	
	until ct > default.maxVeinSize
	
	--return to start
	self:navigateToPos(startPos.x, startPos.y, startPos.z)
	self:turnTo(startOrientation)
	self.taskList:remove(currentTask)
end

function Miner:stripMine(rowLength, rows, levels, rowFactor, levelFactor, offset, noInspect)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name}, true)
	print("stripmining", "rows", rows, "levels", levels)

	local directionFactor = 1 -- -1 for right hand mining

	local taskState = currentTask.taskState
	if taskState then
		rowLength, rows, levels, rowFactor, levelFactor, offset, noInspect = tableunpack(taskState.args,1,taskState.args.n)
	else
		taskState = {
			stage = 1,
			ignorePosition = false,
			vars = {
				currentRow = 1,
				currentLevel = 1,
				rowOrientation = self.orientation,
				tunnelDirection = -1 * directionFactor,
				startPos = vector.new(self.pos.x, self.pos.y, self.pos.z),
				startOrientation = self.orientation,
			},
			args = tablepack(rowLength, rows, levels, rowFactor, levelFactor, offset, noInspect),
		}
	end
	local vars = taskState.vars
	currentTask.taskState = taskState
	self.checkPointer:save(self)
	-- prepare values

	if not levels then levels = 1 end
	local positiveLevel = true
	if levels < 0 then 
		positiveLevel = false 
		levels = levels * -1
	end


-- OPTIMAL STRATEGIES
-- M -> Mine
-- * -> gets looked at

-- MULTILEVEL lookAtAll
--------------------
--	 * 	 *	 *		
-- * M * M * M *	
--	 * * * * * *
--	 * M * M * M *
--	   *   *   *	
--------------------
	-- local rowFactor = 2
	-- local rowLength = (rows-1) * rowFactor
	-- for currentLevel=1,levels do
		-- for currentRow=1,rows do
			-- self:tunnelMine(rowLength,1,1)
			-- --self:turnRight()
			-- if currentRow < rows then
				-- self:turnTo(startOrientation-1)
				-- self:tunnelMine(rowFactor,1,1)
				-- if currentRow%2 == 1 then
					-- self:turnTo(startOrientation-2)
				-- else
					-- self:turnTo(startOrientation)
				-- end
			-- end
		-- end
		-- -- go up one level
	-- end



	
-- MULTILEVEL speed (leaves areas uninspected)
--------------------
--	 * 	   *	 *		
-- * M * * M * * M *	
--	 * *   * *   * *
--	 * M * * M * * M *
--	   *     *     *	
--------------------



	if taskState.stage == 1 then
		-- try, catch
		local ok,err = pcall(function()

			if not rowFactor then rowFactor = 3 end
			if not levelFactor then levelFactor = 2 end
			if not offset then offset = 1 end
			
			for currentLevel = vars.currentLevel, levels do
				vars.currentLevel = currentLevel
				self.checkPointer:save(self)
				if currentLevel%2 == 0 and rows%2 == 0 then 
					vars.tunnelDirection = 1 * directionFactor
				else vars.tunnelDirection = -1 * directionFactor end
				
				for currentRow = vars.currentRow, rows do
					vars.currentRow = currentRow
					self.checkPointer:save(self) -- perhaps at start of for-loop
					self:tunnelStraight(rowLength, noInspect)
					if currentRow < rows then
						self:turnTo(vars.rowOrientation + vars.tunnelDirection)
						self:tunnelStraight(rowFactor, noInspect)
						if currentRow%2 == 1 then
							self:turnTo(vars.rowOrientation-2)
						else
							self:turnTo(vars.rowOrientation)
						end
					end
				end
				vars.currentRow = 1 -- reset row to start at 1 again, not saved state
				if currentLevel < levels then
					-- move up
					if positiveLevel then
						self:tunnelUp(levelFactor, noInspect)
					else
						self:tunnelDown(levelFactor, noInspect)
					end
					if self.orientation == vars.startOrientation or currentLevel%2 == 0 then
							self:turnRight() 
							self:tunnelStraight(offset, noInspect)
							self:turnRight()
							self:tunnelStraight(offset, noInspect)
					else
						if rows%2 == 0 then
							self:tunnelStraight(offset, noInspect)
							self:turnLeft()
							self:tunnelStraight(offset, noInspect)
							self:turnLeft()
						else
							self:turnLeft()
							self:tunnelStraight(offset, noInspect)
							self:turnLeft()
							self:tunnelStraight(offset, noInspect)
						end
					end
					
				end
				vars.rowOrientation = self.orientation
			end
			
		end)
	
		if not ok then 
			if err == "TUNNEL FAIL" then
				print(ok, err)
			else
				-- pass error
				error(err)
			end
		end
		taskState.stage = 2
		taskState.ignorePosition = true
		self.checkPointer:save(self)
	end

--SINGLE LEVEL PART OF MULTILEVEL
--------------------
--	 * 	   *     *
-- * M * * M * * M *
--	 *     *     *
--------------------

	if taskState.stage == 2 then
		-- only needed for testing i guess
		self:navigateToPos(vars.startPos.x, vars.startPos.y, vars.startPos.z)
		self:turnTo(vars.startOrientation)
	end

	self.taskList:remove(currentTask)
	self.checkPointer:save(self)
end

function Miner:getAreaStart(start, finish)
	-- determine nearest starting position for an area

	local minX = math.min(start.x, finish.x)
	local minY = math.min(start.y, finish.y)
	local minZ = math.min(start.z, finish.z)
	local maxX = math.max(start.x, finish.x)
	local maxY = math.max(start.y, finish.y)
	local maxZ = math.max(start.z, finish.z)
	
	local corners = {
		-- 1-4 bottom
		vector.new(minX, minY, minZ),
		vector.new(minX, minY, maxZ),
		vector.new(maxX, minY, minZ),
		vector.new(maxX, minY, maxZ),
		-- 5-8 top
		vector.new(maxX, maxY, maxZ),
		vector.new(maxX, maxY, minZ),
		vector.new(minX, maxY, maxZ),
		vector.new(minX, maxY, minZ),
		-- 1 is opposite to (id + 4) % 8
	}
	
	local minCost, minId
	for id,corner in ipairs(corners) do
		local cost = math.abs(self.pos.x - corner.x) + math.abs(self.pos.y - corner.y) + math.abs(self.pos.z - corner.z)
		if minCost == nil or cost < minCost then
			minCost = cost
			minId = id
		end
	end
	
	start = corners[minId]
	finish = corners[((minId+3)%8)+1] -- opposite corner

	-- turn to the correct orientation 
	-- 	+z = 0	south
	-- 	-x = 1	west
	-- 	-z = 2	north
	-- 	+x = 3 	east
	local diff = finish - start
	local orientation
	if diff.x <= 0 and diff.z > 0 then
		orientation = 1 
	elseif diff.x <= 0 and diff.z <= 0 then
		orientation = 2 
	elseif diff.x > 0 and diff.z <= 0 then
		orientation = 3 
	else
		orientation = 0 
	end

	return start, finish, orientation

end

function Miner:mineArea(start, finish) 
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name}, true)
	-- TODO: mine area within start and finish pos
	-- 8 corners = 8 possible starting locations, pick nearest
	-- determine how many rows and levels to mine and in which direction
	
	local taskState = currentTask.taskState
	if taskState then
		start, finish = tableunpack(taskState.args,1,taskState.args.n)
	else
		taskState = {
			stage = 1, -- Stage 1: Execute stripMine, Stage 2: Execute post-stripMine steps
			ignorePosition = true,
			vars = {
			},
			args = tablepack(start, finish),
		}
	end
	local vars = taskState.vars
	currentTask.taskState = taskState
	self.checkPointer:save(self)

	if taskState.stage == 1 then

		local orientation
		start, finish, orientation = self:getAreaStart(start, finish)
		
		local diff = finish - start
		local width = math.abs(diff.x)
		local height = math.abs(diff.y)
		local depth = math.abs(diff.z)
		
		
		local rowFactor = 3
		local levelFactor = 2
		local rowLength, rows, levels
		if orientation%2 == 0 then
			rowLength = depth
			rows = (width+rowFactor)/rowFactor
		else
			rowLength = width
			rows = (depth+rowFactor)/rowFactor
		end
		if diff.y < 0 then
			levels = math.floor(((-height-levelFactor)/levelFactor)+0.5)
		else
			levels = math.floor(((height+levelFactor)/levelFactor)+0.5)
		end
		
		rows = math.floor(rows+0.5)
		--self.map:load()
		
		print("start", start,"end",finish, "diff", diff, "levels", levels)
		
		if not self:navigateToPos(start.x, start.y, start.z) then
			print("unable to get to area")
			self:returnHome()
			-- save checkpoint, tasklist remove
			-- error? could resume after error?
		else
		
			self:turnTo(orientation)
			
			taskState.stage = 2
			taskState.ignorePosition = true
			self.checkPointer:save(self)

			self:stripMine(rowLength, rows, levels)
			
		end
	end

	-- Stage 2: Execute post-stripMine steps
	if taskState.stage == 2 then
		self:returnHome()
		self:condenseInventory()
		self:dumpBadItems()
		self:transferItems()
		--self:getFuel()
		--self.map:save()
	end 

	self.taskList:remove(currentTask)
	self.checkPointer:save(self)
end


function Miner:tunnel(length, direction, noInspect)
	-- throws error
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	
	local result = true
	local skipSteps = 0
	
	-- noInspect default false: look for and mine ore veins while tunneling

	-- determine direction to mine
	local directionVector, digFunc

	if not direction or direction == "straight" then 
		directionVector = self.vectors[self.orientation]
		digFunc = Miner.digMove
	elseif direction == "up" then
		directionVector = vectorUp
		digFunc = Miner.digMoveUp
	elseif direction == "down" then
		directionVector = vectorDown
		digFunc = Miner.digMoveDown
	end
	
	local expectedEndPos = self.pos + directionVector * length
	local startOrientation = self.orientation
	
	-- actually mine
	for i=1,length do
		if skipSteps == 0 then 
		
			if not noInspect then self:inspectMine() end
			if not digFunc(self) then 
				-- if two turtles get in each others way, steps could be skipped
				-- try to navigate to next step, else quit
				if i < length - 1 then
					local newPos = self.pos + directionVector * 2
					if not self:navigateToPos(newPos.x, newPos.y, newPos.z) then
						result = false
						break
					else 
						self:turnTo(startOrientation)
						skipSteps = 2
						--skip the next step as well
					end
				else
					result = false
					break
				end
			end
		else
			skipSteps = skipSteps - 1
		end
		
	end
	
	if not noInspect then self:inspectMine() end
	
	if self.pos ~= expectedEndPos then
		-- try navigating to the position we should be at
		if not self:navigateToPos(expectedEndPos.x, expectedEndPos.y, expectedEndPos.z) then
			-- we truly failed
			result = false
		else 
			result = true
		end
		self:turnTo(startOrientation)
	end
	
	self.taskList:remove(currentTask)
	
	if not result then error("TUNNEL FAIL", 0) end
	return result
	
end

function Miner:tunnelStraight(length, noInspect)
	local result = self:tunnel(length,"straight", noInspect)
	return result
end

function Miner:tunnelUp(height, noInspect)
	local result = self:tunnel(height,"up", noInspect)
	return result
end

function Miner:tunnelDown(height, noInspect)
	local result = self:tunnel(height,"down", noInspect)
	return result
end

function Miner:inspectMine()
	-- useless function
	self:mineVein()
	return
end


function Miner:excavateArea(start, finish)
	-- similar to mineArea, but digs out everything
	-- works but does a lot of unnecessary inspecting -> slow
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name}, true)

	local taskState = currentTask.taskState
	if taskState then
		start, finish = tableunpack(taskState.args,1,taskState.args.n)
	else
		taskState = {
			stage = 1,
			ignorePosition = true,
			vars = {
			},
			args = tablepack(start, finish),
		}
	end
	local vars = taskState.vars
	currentTask.taskState = taskState
	self.checkPointer:save(self)


	if taskState.stage == 1 then

		local orientation
		start, finish, orientation = self:getAreaStart(start, finish)

		local diff = finish - start
		local width = math.abs(diff.x) + 1
		local height = math.abs(diff.y) + 1
		local depth = math.abs(diff.z) + 1
		
		local rowLength, rows, levels
		if orientation%2 == 0 then
			rowLength = depth
			rows = width
		else
			rowLength = width
			rows = depth
		end
		if diff.y < 0 then
			levels = -height
		else
			levels = height
		end
		rowLength = rowLength - 1

		print("start", start,"end",finish, "diff", diff, "levels", levels)
		
		if not self:navigateToPos(start.x, start.y, start.z) then
			print("unable to get to area")
			self:returnHome()
			-- save checkpoint, tasklist remove
			-- error? could resume after error?
			self.checkPointer:save(self) -- next time turtle will try again
			self:error("UNABLE TO REACH AREA", true)
		else
		
			self:turnTo(orientation)
			
			taskState.stage = 2
			taskState.ignorePosition = true
			self.checkPointer:save(self)

			local rowFactor, levelFactor, offset = 1, 1, 0
			local noInspect = true -- excavate does not need inspecting
			self:stripMine(rowLength, rows, levels, rowFactor, levelFactor, offset, noInspect)

			
		end
	end

	-- Stage 2: Execute post-excavation steps
	if taskState.stage == 2 then
		self:returnHome()
		self:condenseInventory()
		self:dumpBadItems()
		self:transferItems()
		--self:getFuel()
	end 

	self.taskList:remove(currentTask)
	self.checkPointer:save(self)

end



function Miner:recoverTurtle(id, pos)
	-- UNTESTED
	-- navigate to a turtle at pos, mine, place, reboot
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	print("recoverTurtle", id, "at", pos.x, pos.y, pos.z)

	local result = true

	local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
	local startOrientation = self.orientation

	-- make sure inventory has at least one free slot
	if self:getEmptySlots() == 0 then
		self:condenseInventory()
		if self:getEmptySlots() == 0 then
			self:dumpBadItems()
			if self:getEmptySlots() == 0 then
				-- cannot recover turtle
				-- self:error("NO FREE INVENTORY SLOTS TO RECOVER TURTLE", true)
				print("NO FREE INVENTORY SLOTS TO RECOVER TURTLE")
				result = false
			end
		end
	end

	-- somehow ping turtle? make sure its there using low level communication (automatic responses)
	-- self.node:lookup("turtlename")
	
	if not self:navigateToPos(pos.x, pos.y+1, pos.z) then
		print("UNABLE TO REACH TURTLE")
		--self:error("UNABLE TO REACH TURTLE", true)
		result = false
	else
		-- mine turtle
		local block = self:inspectDown(true)
		if block == "computercraft:turtle_normal" or
		   block == default.turtleName then
			self:digDown()
			sleep(1)
			self:checkMinedTurtle()
		else
			print("Block", block)
			-- self:error("NO TURTLE FOUND TO RECOVER", true)
			print("NO TURTLE FOUND TO RECOVER")
			result = false
		end
	end

	self:navigateToPos(startPos.x, startPos.y, startPos.z)
	self:turnTo(startOrientation)

	self.taskList:remove(currentTask)
	return result
end

--##############################################################

function Miner:navigateToPos(x,y,z)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = true
	local goal = vector.new(x,y,z)

	local safe = true -- always be safe except very close to goal
	local safeDistance = 3

	if self.pos ~= goal then

		-- calculate how many tries are allowed
		local diff = self.pos - goal
		local cost = math.abs(diff.x) + math.abs(diff.y) + math.abs(diff.z)	
		local maxTries = cost / 2
		if maxTries < 15 then maxTries = default.pathfinding.maxTries end
		local maxParts = ( cost / default.pathfinding.maxDistance ) * 2
		if maxParts < 2 then maxParts = default.pathfinding.maxParts end
		local ct = 0
		local minDist = -1
		local mapReset = false
		
		local pathFinder = PathFinder()
		pathFinder.checkValid = checkSafe
		
		repeat
			ct = ct + 1
			local countParts = 0
			repeat 
				countParts = countParts+1
				local path = pathFinder:aStarPart(self.pos, self.orientation, goal , self.map, nil)
				-- check near goal, and path leads to goal
				-- if path and path[#path].pos == goal and #path < safeDistance + 3 then -- keep eye on this ordeal
				local movesToGoal = math.abs(self.pos.x - goal.x) + math.abs(self.pos.y - goal.y) + math.abs(self.pos.z - goal.z)
				if movesToGoal <= safeDistance then
					if not checkDisallowed(self:getMapValue(goal.x, goal.y, goal.z)) then
						if safe then print("OVERRIDE SAFETY", movesToGoal) end
						safe = false
					end
				end

				if path then 
					if not self:followPath(path,safe) then 
						-- print("NOT SAFE TO FOLLOW PATH")
						result = false
					else 
						if self.pos == goal then
							result = true 
						else
							-- check if the goal can be reached
							local cp = self.pos
							local dist = math.abs(cp.x - goal.x) + math.abs(cp.y - goal.y) + math.abs(cp.z - goal.z)
							--print("min", minDist, "dist", dist, "try", ct, "part", countParts)
							result = false
							if minDist < 0 or dist < minDist then 
								minDist = dist
							elseif dist >= minDist and ct > 1 then  
								path = pathFinder:checkPossible(self.pos, self.orientation, goal, self.map, nil, not mapReset)
								if not path then 
									
									if not mapReset then 
										mapReset = true
										countParts = 0
										ct = math.max(ct, maxTries/2)
									else
										-- path truly impossible
										print("IMPOSSIBLE GOAL", goal)
										
										ct = maxTries
										countParts = maxParts
										-- get home as near as possible
										-- navigateHome but without restarting pathfinding on error?
										-- if self.returningHome == false then 
										--	self:navigateToPos(self.home.x, self.home.y, self.home.z) 
										-- end
										result = false -- return false otherwise will continue with mining at home
										self:digToPos(self.home.x, self.home.y, self.home.z, true)
										
									end
									
								else
									print("GOAL POSSIBLE", goal, #path)
									result = self:followPath(path, safe)
								end
							end
						end
					end
				else
					-- dig to target
					safe = movesToGoal > safeDistance
					if not self:digToPos(goal.x, goal.y, goal.z, safe) then
						--path was not safe
						print("NOT SAFE TO DIG TO POS")
						result = false
						countParts = maxParts
						sleep(0.5) -- give other turtles a chance to move out the way
					else result = true end
				end
			until result == true or countParts >= maxParts
		until result == true or ct >= maxTries
	end
	
	if self.pos ~= goal then result = false end
	if result == false then 
		print("NOT SAFE TO FOLLOW PATH AFTER MULTIPLE TRIES")
	end
	
	self.taskList:remove(currentTask)
	return result
end

function Miner:followPath(path,safe)
	-- safe function
	--print("FOLLOWING PATH TO", path[#path].pos)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	local result = true
	if safe == nil then safe = true end -- always safe?

	for i,step in ipairs(path) do
		if step.pos ~= self.pos  then
			local diff = step.pos - self.pos
			local newOr
			local upDown = 0
			if diff.x < 0 then newOr = 1
			elseif diff.x > 0 then newOr = 3
			elseif diff.z < 0 then newOr = 2
			elseif diff.z > 0 then newOr = 0
			elseif diff.y < 0 then upDown = -1
			else upDown = 1 end

			-- inspecting slows down movement, minimize it
			if i > 1 then
				if upDown ~= 1 then self:inspectUp() end
				if upDown ~= -1 then self:inspectDown() end
				if not newOr or newOr ~= self.orientation then self:inspect() end
			end

			if upDown > 0 then
				if not self:digMoveUp(safe) then 
					result = false --return false
					break
				end
			elseif upDown < 0 then
				if not self:digMoveDown(safe) then 
					result = false --return false
					break
				end
			else
				local block = self:getMapValue(step.pos.x, step.pos.y, step.pos.z)
				if (newOr-2)%4 == self.orientation and block == 0 then
					if not self:back() then
						self:turnTo(newOr)
						print("cannot move backwards")
						result = false
						break
					end
				else
					if newOr ~= self.orientation then
						self:turnTo(newOr)
						self:inspect() --inspect left / right
					end
					if not self:digMove(safe) then
						result = false
						break
					end
				end
			end
		end 
	end

	if result and #path > 0 then
		self:inspect()
		self:inspectUp()
		self:inspectDown()
	end

	--if not result and path[#path].pos == step.pos then
	--	self:error("GOAL IS BLOCKED")
	-- leads to infinite loop
	--end
	self.taskList:remove(currentTask)
	return result
	
end



--############################################################## STORAGE related functions

function Miner.getWiredNetworkName()
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
local getWiredNetworkName = Miner.getWiredNetworkName

function Miner:getTurtleInventoryList()
	-- turtle.getItemDetail(i) is instant
	-- scan inventory for storage related tasks
	local invList = {}
	local hasFuel = false 
	for i = 1,default.inventorySize do
		local data = turtle.getItemDetail(i)
		if data and data.name then
			if not hasFuel and fuelItems[data.name] then
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

function Miner:pickupAndDeliverItems(reservation, dropOffPos, requester, requestingInv)
	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})
	-- TODO: make this a checkpointed task

	local pos = reservation.pos
	if self:navigateToPos(pos.x, pos.y, pos.z) then 

		
		local networkName = Miner.getWiredNetworkName()
		print("networkName:", networkName)

		local invListBefore = self:getTurtleInventoryList()

		local waitTime = 10 -- extracting can take some time
	
		local answer = self.nodeStorage:send(reservation.provider, 
			{"PICKUP_ITEMS", { reservationId = reservation.id, turtleName = networkName }}, true, true, waitTime)
		if answer and answer.data[1] == "ITEMS_EXTRACTED" then 
			local data = answer.data[2]
			print("extracted", data.name, data.count, data.extractedToTurtle)
			local gotItems = false
			if data.extractedToTurtle then
				gotItems = true
			else
			--[[ -- TODO: rewrite or delete this shit, just an idea for the turtle to suck up items i guess
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

			local invList = {}
			-- build new inventory list with difference in items
			for i = 1, default.inventorySize do 
				local before = invListBefore[i]
				local after = invListAfter[i]
				if before.name == after.name then
					if before.count == after.count then 
						before.protected = true
						invList[i] = before
					elseif before.count > after.count then
						-- items removed -- should never happen -- condenseInventory might play a role though
						print("ITEMS REMOVED ON PICKUP?", before.name, before.count - after.count)
						invList[i] = { name = before.name, count = 0, protected = true }
					else
						-- items added
						invList[i] = { name = after.name, count = after.count - before.count, protected = false }
					end
				else
					if not before.name and after.name then
						-- new items
						invList[i] = { name = after.name, count = after.count, protected = false }
					elseif before.name and not after.name then
						-- items removed -- should never happen -- condenseInventory might play a role though
						print("STACK REMOVED ON PICKUP?", before.name, before.count)
						invList[i] = { name = before.name, count = 0, protected = true }
					else
						-- changed items -- should never happen
						print("STACK CHANGED ON PICKUP?", before.name, "to", after.name)
						invList[i] = { name = after.name, count = after.count, protected = true }
					end
				end
			end
			

			if gotItems then
				-- deliver items to requesting storage
				if self:navigateToPos(dropOffPos.x, dropOffPos.y, dropOffPos.z) then 
					-- drop items into inv 

					local waitTime = default.waitTime
					if requestingInv == "player" then 
						waitTime = 60*2
						networkName = nil -- "player"
					else 
						networkName = Miner.getWiredNetworkName()
						print("networkName", networkName)
					end


					-- if this fails use, Miner:transferItems() and dump items into a chest
					print("delivered", data.name, data.count, "to", requester, "inv", networkName or requestingInv)
					local answer, manualConfirmation
					local requestConfirmation = function() 
						answer = self.nodeStorage:send(requester, {"ITEMS_DELIVERED", 
						{ reservation = reservation, requestingInv = networkName or requestingInv, invList = invList }},
						true, true, waitTime)
					end

					parallel.waitForAny( 
						requestConfirmation, 
						function()
							shell.switchTab(multishell.getCurrent())
							print("---------------------------\n     ITEMS DELIVERED\nPRESS ENTER TO CONFIRM\n---------------------------")
							--os.pullEvent("key")
							local confirmed = read()
							manualConfirmation = true
						end
					)
					if answer and answer.data[1] == "DELIVERY_CONFIRMED" then
						print("delivery confirmed by requester", requester)
					elseif manualConfirmation then 
						print("manual delivery confirmation")
					else
						if answer then print(answer.data[1]) end
						print("no delivery confirmation from requester", requester)
						-- perhaps ping requester again if this happens often
					end
					self:returnHome()
				else

				end
			end
		else
			print(answer and answer.data[1] or "NO ANSWER FROM PROVIDER")
		end
	end
	self.taskList:remove(currentTask)
	
end







--############################################################## TREE related functions

local BreadthFirstSearch = require("classBreadthFirstSearch")
local StateMap = require("classStateMap")
local manhattanDistance = ChunkyMap.manhattanDistance

local leafBlocks = {
	["minecraft:oak_leaves"] = true,
	["minecraft:spruce_leaves"] = true,
	["minecraft:birch_leaves"] = true,
	["minecraft:jungle_leaves"] = true,
	["minecraft:acacia_leaves"] = true,
	["minecraft:dark_oak_leaves"] = true,
}
local logBlocks = {
	["minecraft:oak_log"] = true,
	["minecraft:spruce_log"] = true,
	["minecraft:birch_log"] = true,
	["minecraft:jungle_log"] = true,
	["minecraft:acacia_log"] = true,
	["minecraft:dark_oak_log"] = true,
}


local function checkValidLeafBFS(block)
	-- only traverse through unknown blocks or leaf blocks
	if block == nil or leafBlocks[block] then return true
	else return false end
end
local function checkGoalLeafBFS(block)
	-- only goal if leaf block
	if block and logBlocks[block] then return true
	else return false end
end

local function checkAirBlock(data)
	if data == 0 or data.name == 0 then 
		return true
	end
	return false
end

local function checkLogBlock(data)
	-- rewrite ts
	if data and not checkAirBlock(data) and logBlocks[data.name] then 
		return true
	end
	return false
end
local function checkLeafBlock(data)
	if data and not checkAirBlock(data) and data.tags and data.tags["minecraft:leaves"] then
		if not leafBlocks[data.name] then
			print("UNKNOWN LEAF BLOCK:", data.name)
			leafBlocks[data.name] = true
		end
		return true
	end
	return false
end
local function checkBeeHive(data)
	if data and not checkAirBlock(data) and data.name == "minecraft:bee_nest"  then
		return true
	end
	return false
end


-- known issues
-- 1. diagonal blocks without any leaves will not be found
-- 2. leaves that are connected to multiple blocks might return plausible if they are not reinspected
-- 		-> they are ignored to check for logs
--     solution? a simple backtracking down the main trunk and inspecting leaves again could help 
--		   (or step after mining all connected logs)
--     also once at the top of the tree: use leaves gradient to find next log, continue from there with rest of logic
-- 3. inefficient mining order -> logs and leaves could be mined in a better order to minimize movement
--    best would be to pick the nearest log/leaf at each step, but that is quite expensive to calculate
--    simpler is to use a heap for the leaves based on state.distance and always priotitize logs
--    immediately mine logs even if another "job" like mineToLeaf is ongoing
--    always mining logs first, then reevaluating the leaves.distance values could also help with 2.

-- 4. old distance values of leaves 
--  after mining all logs, update the distance values of leaves through bfs again? 
-- bfs for dist 2 = nil but neighbour has been inspected recently dist 5 -> dist 4 now
-- randomly reinspect leaves? best to do it on connected groups of leaves
-- how do we get groups of leaves? 


-- only real optimization left: use bfs to floodfill leaves distance values after having mined logs / inspected leaves
-- e.g. leaf inspected: dist 7 -> neighbour has old value dist 2
--           conflicting info, 7 is more recent, which means the neighbour must be at least dist 6
--           so update dist to 6, and continue bfs from there
--           do this for all leaves that have been inspected after last/latest log was mined
--           only then reinspect leaves that still have a somewhat low distance value (also do this by groups)


function Miner:mineTree()

	-- only needed for oak trees ig 

	-- TODO: prioritize logs over leaves with distance 1
	-- but instead of doing it at the very end, do it at each DFS node after mining logs?
	-- remove bee nests minecraft:bee_nest
	-- for branches, check the next air block as well

	-- global.miner:navigateToPos(2229, 68, -2665); global.miner:turnTo(1); global.miner:mineTree()

	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})

	local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
	local startOrientation = self.orientation

	local treeMap = StateMap:new()
	self.treeMap = treeMap

	local maxDistance = 7
	local distanceLeaves = {}
	for i = 1, maxDistance do distanceLeaves[i] = {} end
	local leafDistanceMap = {}

	local reinspectionDistance = 3

	local prvReinspectionDistance = reinspectionDistance
	local logs = {}
	local priorityLogPos = nil
	

	local function posToKey(pos)
        return pos.x .. "," .. pos.y .. "," .. pos.z
    end

	local function setReinspectionDistance(dist)
		prvReinspectionDistance = reinspectionDistance
		reinspectionDistance = dist
	end
	local function restoreReinspectionDistance()
		reinspectionDistance = prvReinspectionDistance
	end

	local function shouldInspect(data)
		-- not yet inspected or leaf block with distance <= 2

		local result = false
		if not data then 
			result = true
		elseif checkLeafBlock(data) and data.state.distance <= reinspectionDistance then
			-- check if a log was mined since last inspection, only then reinspect the leaf
			local timeLogMined = treeMap:getLastMined("minecraft:oak_log")
			local wasLogMined = timeLogMined and timeLogMined > data.time or false
			result = wasLogMined
		end
		if not result then 
			--print("noInspect", data.name, data.state and data.state.distance, checkLeafBlock(data))
		elseif result and checkLeafBlock(data)then
			-- print("reinspectLeaf", data.name, data.state.distance)
		end
		return result
	end

	local function rememberBlock(pos, data)
		treeMap:setData(pos.x, pos.y, pos.z, data)

		if checkLogBlock(data) then
			table.insert(logs, pos)
		elseif checkLeafBlock(data) then
			local key = posToKey(pos)
			local oldDist = leafDistanceMap[key]
			local newDist = data.state.distance

			if oldDist and newDist ~= oldDist then
				-- already known leaf, update only if distance changed
				distanceLeaves[oldDist][key] = nil
			end
			distanceLeaves[newDist][key] = pos
			leafDistanceMap[key] = newDist

		elseif checkBeeHive(data) then
			table.insert(logs, pos) -- mine bee hives as well
		end
	end

	local function inspectDown()
		local pos = self.pos + vectorDown
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			local blockName, data = self:inspectDown(true)
			rememberBlock(pos, data)
		end
	end
	local function inspectUp()
		local pos = self.pos + vectorUp
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			local blockName, data = self:inspectUp(true)
			rememberBlock(pos, data)
		end
	end
	local function inspect(dir)
		if not dir then dir = self.orientation end
		local pos = self.pos + self.vectors[dir]
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			self:turnTo(dir)
			local hasBlock, data = self:inspect(true)
			rememberBlock(pos, data)
		end
	end
	local function inspectAll()
		-- return how many logs have been found
		local logCt = #logs

		inspectDown()
		inspectUp()
		local orientation = self.orientation
		for i=0,3 do
			local dir = (orientation+i)%4
			inspect(dir)
		end

		return #logs - logCt
	end


	local function getRoot()
		-- find the root block of the tree
		-- its the lowest block in the whole tree
		local minX, minY, minZ = nil, math.huge, nil
		local log = treeMap.log
		for i = 1, #log do 
			local entry = log[i]
			local chunkId, relativeId, data = entry[1], entry[2], entry[3]

			if checkLogBlock(data) then 
				local x, y, z = ChunkyMap.idsToXYZ(chunkId, relativeId)
				if y < minY then 
					minX, minY, minZ = x, y, z
				end
			end
		end

		if minX then 
			return vector.new(minX, minY, minZ)
		else
			print("no root found")
			return nil
		end
	end

	local function getTrunk()
		-- largest collection of logs with state.axis == y
		-- or any blocks directly above / connected to the root

	end


	local bfs = BreadthFirstSearch()
	local options = { maxDistance = 3, returnPath = true}


	local function digToPosUsingLeaves(tx, ty, tz)

		-- idea+optimization: instead of normal digtopos:
			-- try to dig to pos using potentially surrounding leaves (if no logs are there)
			-- could reveal more hidden logs but also increase chance to get saplings back
			-- also solves the issue of the map not being 100% accurate
		-- not quite sure though if this actually helps the edge cases...

		-- prefer y axis to maybe find new logs


		-- caution: using this func to dig toward a leaf with low distance (e.g. 3)
		--          might lead to the leaf being cut from the log. but it is replaced with another entry
		-- not an issue but perhaps reevaluating the target leaf could help avoid unnecessary movement

		local safe = false
		local result = true

		--print("digTo", tx, ty, tz)
		local cx, cy, cz = self.pos.x, self.pos.y, self.pos.z

		if cx == tx and cy == ty and cz == tz then
			return true
		end

		local allVectors = {
			vectors[0],
			vectors[1],
			vectors[2],
			vectors[3],
			vectorUp,
			vectorDown,
		}

		local neighbourVectors = {}
		local xdir, yvec, zdir

		if cx < tx then xdir = 3
		elseif cx > tx then xdir = 1 end

		if cz < tz then zdir = 0
		elseif cz > tz then zdir = 2 end

		if cy < ty then yvec = vectorUp
		elseif cy > ty then yvec = vectorDown end

		if yvec then table.insert(neighbourVectors, yvec) end
		if xdir then table.insert(neighbourVectors, vectors[xdir]) end
		if zdir then table.insert(neighbourVectors, vectors[zdir]) end
		
		local logsFound = inspectAll()
		
		repeat
			local cpos, nextPos = self.pos, nil


			-- check if our target is directly adjacent
			if ChunkyMap.manhattanDistance(cpos.x, cpos.y, cpos.z, tx, ty, tz) == 1 then
				-- ignore all other neighbours, go directly to target
				nextPos = vector.new(tx, ty, tz)
			else

				-- check neighbours 
				local relevantNeighbours, relevantSet = {}, {}
				local irrelevantNeighbours = {}

				-- neighbours on the path towards target
				for _, vec in ipairs(neighbourVectors) do
					relevantSet[vec] = true
					table.insert(relevantNeighbours, cpos + vec)
				end

				-- neighbours that do not lead towards target
				for _, vec in ipairs(allVectors) do
					if not relevantSet[vec] then
						table.insert(irrelevantNeighbours, cpos + vec)
					end
				end

				-- check irrelevant neighbours for logs first
				for _, neighbour in ipairs(irrelevantNeighbours) do
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
					local ndata = treeMap:getData(nx, ny, nz)
					if checkLogBlock(ndata) then
						-- found log block nearby, go there first
						-- cancel current digToPos, add it back to the queue for later
						-- prioritize newly found log
						priorityLogPos = vector.new(nx, ny, nz)
						print("interrupting, found log", nx, ny, nz)
						return "interrupted", neighbour
					end
				end

				-- check relevant neighbours and choose preferable path
				for i, neighbour in ipairs(relevantNeighbours) do
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
					neighbour.dir = neighbourVectors[i]
					local ndata = treeMap:getData(nx, ny, nz)
					neighbour.data = ndata
					if checkLeafBlock(ndata) then
						neighbour.distance = ndata.state.distance
					elseif checkLogBlock(ndata) then
						-- logs should not be present here except its the target itself?
						neighbour.distance = 0
					else
						neighbour.distance = 666
					end
				end
				table.sort(relevantNeighbours, function(a,b) return a.distance < b.distance end)
				-- simply go by the "leaf" with the lowest distance if such a leaf exists
				nextPos = relevantNeighbours[1]
			end

			-- actually move
			local diff = nextPos - self.pos
			if diff.y > 0 then
				if not self:digMoveUp(safe) then result = false; break end
			elseif diff.y < 0 then
				if not self:digMoveDown(safe) then result = false; break end
			else
				local newOr
				if diff.x ~= 0 then newOr = xdir
				elseif diff.z ~= 0 then newOr = zdir end
				self:turnTo(newOr)
				if not self:digMove(safe) then result = false; break end
			end
			treeMap:setMined(self.pos.x, self.pos.y, self.pos.z)
			logsFound = inspectAll()

			-- remove vectors for axes we've already reached
			local filtered = {}
			for _, vec in ipairs(neighbourVectors) do
				local keep = not ((self.pos.x == tx and vec.x ~= 0) or
								(self.pos.y == ty and vec.y ~= 0) or
								(self.pos.z == tz and vec.z ~= 0))
				if keep then
					table.insert(filtered, vec)
				end
			end
			neighbourVectors = filtered

		until ( self.pos.x == tx and self.pos.y == ty and self.pos.z == tz ) or result == false

		return result
	end

	local function checkPlausibleDistance(leafPos, data)
		-- check distance of branch leaves to other logs
		-- if its possible to reach it within distance, if not it suggests there is another log 
		-- hidden in the branch

		-- e.g. 
		-- LOG, 	LEAF(dist1)	???
		-- LOG, 	AIR, 		LEAF(dist2) 
		
		--> to get to the next known log, LEAF must be distance 3, but it has 2
		--> mine this leaf and check if (moving away from trunk) there is a log
		--> could also just be a LOG further up, which hasnt been explored yet but is still connected
		-- use pathfinder to determine distance to nearest log block? if it is bigger than distance, the leaf should be mined

		--[[
			if leav.state.distance > 1 and leaf.state.distance <= 3 then 
				local start = leafPos
				local goal = ?   -- check all log blocks? -> could also just use BFS instead of pathfinding
				local pathFinder = PathFinder()
				pathFinder.checkValid = -- not turtle, not air, preferrably leaves or unknown
				local path = pathFinder:aStarPart(self.pos, self.orientation, goal , self.map, nil)
				local moves = #path 
				if moves > leaf.state.distance then 
					-- mine leaf
				end
			end
		--]]

		-- using bfs instead of astar, because we dont know what the next log is, and thus have no target to pathfind towards
		-- instead we find the nearest log block with bfs

		-- using self.map is not recommended, since it might contain old data when the tree didnt exist yet
		-- or another tree in the same spot has been felled before
		-- create an additional local map for each tree
		-- though if multiple turtles are felling the same tree, this could lead to issues

		-- the map also needs to remember when a block has been mined / inspected
		-- this way we can do the plausibility check for the time the leaf was inspected
		-- and we can also check for logs that have only been expected in the furture (after leaf was instpected, not before)

		local excludeAir = true -- due to leaf decay
		local reconstructedMap = treeMap:reconstructMapAtTime(data.time, excludeAir)
		local getMapBlock = function(x, y, z)
			return reconstructedMap:getBlockName(x, y, z)
		end

		if data.state.distance > 3 then 
			options.maxDistance = 3 
		else
			options.maxDistance = data.state.distance
		end

		local path = bfs:breadthFirstSearch(leafPos, checkGoalLeafBFS, checkValidLeafBFS, getMapBlock, options)
		local moves = ( path and #path - 1 ) or math.huge

		if not path or moves > data.state.distance then
			print("BFS mvs", moves, "leaf", leafPos, "dst",  data.state.distance)
			return false -- not plausible
		else
			return true -- plausible
		end
	end


	local function getActions(fromPos, fromOr, toPos)
		-- estimate number of actions (turns) to get from fromPos to toPos
		-- used for prioritizing logs

		local diff = toPos - fromPos
		local targetOr
		if diff.x < 0 then targetOr = 1
		elseif diff.x > 0 then targetOr = 3
		elseif diff.z < 0 then targetOr = 2
		elseif diff.z > 0 then targetOr = 0 end

		local actions = 0

		-- up/down, over front, over rest
		if targetOr == fromOr then 
			actions = 0.5
		elseif not targetOr then 
			actions = 0
		else
			local turnDiff = (targetOr - fromOr) % 4
			actions = math.min(turnDiff, 4 - turnDiff)
		end

		return actions
	end


	local function mineTowardsLog(leafPos, leafData)
		-- use leaf gradient descent to find the next log
		-- recursive intersecations are theoretically possible
		-- LOG - LEAF - LEAF - LEAF - LOG
		--              LEAF
		-- leaf has distance 3 but two possible paths to logs

		-- pick a random possible path,
		-- the other leaf is added to distanceLeaves for later processing anyways

		local dist = ( leafData and leafData.state.distance ) or maxDistance
		local minDist = dist
		local minPos, minData = nil, nil
		local x, y, z = leafPos.x, leafPos.y, leafPos.z

		print("mtl, leaf", x, y, z, "dst", leafData and leafData.state.distance or "nil")

		inspectAll()
		local neighbours = bfs.getCardinalNeighbours(x, y, z)
		for i, npos in ipairs(neighbours) do
			local nx, ny, nz = npos.x, npos.y, npos.z
			local ndata = treeMap:getData(nx, ny, nz)

			if checkLeafBlock(ndata) and ndata.state.distance < minDist then
				-- all leaves with a smaller distance are candidates for next step
				-- however we only care about the smallest (usually only for the first step though)
				minDist = ndata.state.distance
				minPos = npos
				minData = ndata
				
			elseif checkLogBlock(ndata) then
				-- found log!
				print("mtl, log", nx, ny, nz, "from leaf", x,y,z)
				local result = digToPosUsingLeaves(nx, ny, nz)
				if result == "interrupted" then
					print("SHOULDNT HAPPEN, 2")
					return false
				elseif result then
					return true
				else
					print("mtl, cannot reach log", nx, ny, nz)
				end
			end
		end

		if minPos then
			local nx, ny, nz = minPos.x, minPos.y, minPos.z
			local ndata = minData
			local result = digToPosUsingLeaves(nx, ny, nz)
			if result == "interrupted" then
				print("SHOULDNT HAPPEN, 1")
				return false
			elseif result then
				return mineTowardsLog(minPos, ndata) -- recursive call towards log
			else
				print("mtl, cannot reach leaf", nx, ny, nz)
			end

			-- let the basic logic of mineLeaves handle multiple leaves and recall this func	
		end
	end

	local its = 0
	local maxIts = 256
	local firstGradientPass = false

	local function mineLogsDFS()

		while #logs > 0 and its < maxIts do

			its = its + 1
			-- pick next log to mine
			local pos, logDist
			if priorityLogPos then
				-- use prioritized log (usually leading outwards)
				pos = priorityLogPos
				priorityLogPos = nil
				logDist = manhattanDistance(self.pos.x, self.pos.y, self.pos.z, pos.x, pos.y, pos.z)
			else
				-- use the closest log 

				local cpos, cor = self.pos, self.orientation
				local cx, cy, cz = cpos.x, cpos.y, cpos.z
				local log = logs[1]
				local closestId = 1
				local closestDist = manhattanDistance(cx, cy, cz, log.x, log.y, log.z)
				local minActions = getActions(cpos, cor, log)

				for i = 2, #logs do
					log = logs[i]
					local dist = manhattanDistance(cx, cy, cz, log.x, log.y, log.z)
					if dist < closestDist then
						closestDist = dist
						closestId = i
					elseif dist == closestDist then
						-- same distance, prefer smaller action count
						local actions = getActions(cpos, cor, log)
						if actions < minActions then
							minActions = actions
							closestId = i
						end

					end
				end
				pos = table.remove(logs, closestId)
				logDist = closestDist
			end

			-- mine logs DFS
			local x, y, z = pos.x, pos.y, pos.z
			local data = treeMap:getData(x, y, z)

			if data and data.name ~= 0 then

				if logDist > 1 and not firstGradientPass then 
					-- continuous log streak broken -> use leaf gradient for next log
					table.insert(logs, pos) -- requeue current log
					firstGradientPass = true
					if mineTowardsLog(self.pos, nil) then 
						-- could fail if no leaves are around
					end
					-- we only want to do this once though? -- perhaps also remove again
					-- TODO? maybe prefer going upwards first and only triggering this when moving back down?
					-- (actions determine what direction is preferred, currently the one in front, then up)
					-- when pos.y > self.pos.y
				end

				if logDist <= 1 or firstGradientPass then
					-- after first gradient pass, mine all remaining logs directly

					print("log at", pos)
					local result = digToPosUsingLeaves(x, y, z)

					if result == "interrupted" then
						-- requeue current log and pick new log
						if self.pos.x ~= x or self.pos.y ~= y or self.pos.z ~= z then
							table.insert(logs, pos)
						end
					elseif result then 
						inspectAll()
					else
						print("Cannot reach log at", pos)
					end
				end
			end
		end

	end

	local uncheckedLeaves = {}

	local function mineLeaves()
		print("MINING LEAVES WITH LOW DISTANCE")

		-- indexed priority list for leaves based on distance
		-- or just go by the nearest leaf, to save on movement?

		while true do 

			-- get next leaf with lowest state.distance and distance to turtle
			local cpos = self.pos
			local cx, cy, cz = cpos.x, cpos.y, cpos.z

			local key, pos, distance
			for dist = 1, #distanceLeaves do
				local leaves = distanceLeaves[dist]

				if next(leaves) then
					distance = dist
				
					local minDist = math.huge
					for k, p in pairs(leaves) do 
						local ldist = manhattanDistance(cx, cy, cz, p.x, p.y, p.z)
						if ldist < minDist then
							minDist = ldist
							key, pos = k, p
						end
					end
					break
				end
			end

			if not pos then break end

			local x, y, z = pos.x, pos.y, pos.z

			distanceLeaves[distance][key] = nil
			leafDistanceMap[key] = nil

			local data = treeMap:getData(x, y, z)
			if data and data.name ~= 0 and checkLeafBlock(data) then 
				local currentDist = data.state.distance

				if currentDist ~= distance then
					-- leaf distance changed
					distanceLeaves[currentDist][key] = pos
					leafDistanceMap[key] = currentDist

				elseif currentDist <= 1 then 
					print("leaf at", pos, "dst", currentDist)
					local result = digToPosUsingLeaves(x, y, z)
					if result == "interrupted" then
						-- requeue current leaf, call mineLogsDFS
						distanceLeaves[currentDist][key] = pos
						leafDistanceMap[key] = currentDist
					elseif result then 
						inspectAll()
					else
						print("Cannot reach leaf at", pos)
					end

				elseif currentDist <= reinspectionDistance and not checkPlausibleDistance(pos, data) then
					local result = digToPosUsingLeaves(x, y, z)
					if result == "interrupted" then
						-- requeue current leaf
						distanceLeaves[currentDist][key] = pos
						leafDistanceMap[key] = currentDist
					elseif result then 
						
						if not mineTowardsLog(pos, nil) then -- data
							-- shouldnt happen, but lets chalk it up to faster inspection than distance values can be updated
							-- also leaf decay could perhaps cause this
							-- check commit 4365578 for more debugging stuff
							print("no log from leaf", pos, "dst", currentDist)
						end
					else
						print("Cannot reach leaf at", pos)
					end

				elseif currentDist < maxDistance then
					-- requeue leaves that theoretically could still have logs, but unlikely
					uncheckedLeaves[key] = pos
				end
			end

			-- mine logs found after mining leaves
			mineLogsDFS()

		end
	end

	local Queue = require("classQueue")

	local function getLeafGroup(start, visited)
		-- bfs like search so we get all connected leaf blocks within distance 6
		-- also calculate centroid and representative

		local components = {}
		local group = { components = components }
		local sumX, sumY, sumZ = 0, 0, 0

		local queue = Queue:new()
		local start = { x = start.x, y = start.y, z = start.z, distance = 0 }
		queue:pushRight(start)

		while true do
			local current = queue:popLeft()
			if not current then break end

			local cx, cy, cz, cdist = current.x, current.y, current.z, current.distance
			table.insert(components, vector.new(cx, cy, cz))
			sumX = sumX + cx
			sumY = sumY + cy
			sumZ = sumZ + cz

			if cdist < 6 then
				local neighbours = bfs.getCardinalNeighbours(cx, cy, cz)
				for i = 1, #neighbours do
					local neighbour = neighbours[i]
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z

					local vx = visited[nx]
					if not vx then vx = {}; visited[nx] = vx end
					local vy = vx[ny]
					if not vy then vy = {}; vx[ny] = vy end
					if not vy[nz] then 
						vy[nz] = true

						local ndata = treeMap:getData(nx, ny, nz)
						if checkLeafBlock(ndata) then
							neighbour.distance = cdist + 1
							queue:pushRight(neighbour)
						end
					end
				end
			end
		end
		local ct = #components
		local centroidX = sumX / ct
		local centroidY = sumY / ct
		local centroidZ = sumZ / ct
		group.centroid = { x = centroidX, y = centroidY, z = centroidZ }
		local representative = start

		-- get representative of group (nearest to centroid)
		local minDist = math.huge
		for i = 1, #components do
			local comp = components[i]
			local dist = manhattanDistance(centroidX, centroidY, centroidZ, comp.x, comp.y, comp.z)
			if dist < minDist then
				minDist = dist
				representative = comp
			end
		end
		group.representative = vector.new(representative.x, representative.y, representative.z)

		return group
	end

	local function reinspectLeafGroups(remainingLeaves)
		-- find connected leaf groups and reinspect a single one
		-- since they are within 6 blocks of each other, 
		-- one inspection guarantees that no logs are contained if distance is 7
		-- though navigating to the groups can cut off groups
		-- exclude groups of 1 -> usually lead nowhere useful or are nearby other groups

		local groups = {}
		local visited = {}
		local groupCreationTime = osEpoch()

		for key, pos in pairs(remainingLeaves) do
		
			local sx, sy, sz = pos.x, pos.y, pos.z
			local ndata = treeMap:getData(sx, sy, sz)
			-- check if leaf still exists
			if checkLeafBlock(ndata) then
				local vx = visited[sx]
				if not vx then vx = {}; visited[sx] = vx end
				local vy = vx[sy]
				if not vy then vy = {}; vx[sy] = vy end
				if not vy[sz] then
					vy[sz] = true

					local group = getLeafGroup(pos, visited)
					if #group.components > 1 then
						table.insert(groups, group)
					end
				end
			end
		end

		print("found", #groups, "leaf groups")

		local unvisitedGroups = {}
		for i = 1, #groups do unvisitedGroups[i] = true end

		while next(unvisitedGroups) do 
			-- -- find nearest group based on representative
			local cpos = self.pos
			local cx, cy, cz = cpos.x, cpos.y, cpos.z

			local closestGroupId
			local minDist = math.huge

			for i, _ in pairs(unvisitedGroups) do
				local rep = groups[i].representative
				local dist = manhattanDistance(cx, cy, cz, rep.x, rep.y, rep.z)
				if dist < minDist then
					minDist = dist
					closestGroupId = i
				end
			end

			local group = groups[closestGroupId]
			unvisitedGroups[closestGroupId] = nil

			-- process the group
			-- pick nearest leaf of group to reinspect
			-- also check if a leaf has been updated while processing other groups
			-- if ANY not updated leaf has distance >= 7, skip the group
			-- if ALL updated leaves have distance >= 7, skip the group
			
			local hasUpdatedLeaf, allUpdatesDistant = false, true
			local components = group.components
			local closestLeafId
			minDist = math.huge
			for i = 1, #components do
				local comp = components[i]
				local dist = manhattanDistance(cx, cy, cz, comp.x, comp.y, comp.z)
				if dist < minDist then
					minDist = dist
					closestLeafId = i
				end

				local compData = treeMap:getData(comp.x, comp.y, comp.z)

				-- print("grpLeaf", comp.x, comp.y, comp.z, "time", compData.time, "dst", compData.state.distance)

				if checkLeafBlock(compData) then 
					if compData.time > groupCreationTime then
						-- leaf has been updated since group creation
						-- all updated leaves must be >= 7 to skip the group
						hasUpdatedLeaf = true
						if compData.state.distance < maxDistance then 
							allUpdatesDistant = false
						end
					elseif compData.state.distance >= maxDistance then
						-- found a non-updated leaf with distance 7, skip group
						-- at time of creation, groups were connected, so if one leaf is distant, the whole group is
						allUpdatesDistant = true
						hasUpdatedLeaf = true
						break
						-- TODO: check for conflicting information of leaves?
						-- only rely on most recent inspection time
					end
				end
			end

			if hasUpdatedLeaf and allUpdatesDistant then 
				-- all updated leaves will decay, skip group
				print("skipping group, inspected, size", #components)
			else

				local closestLeaf = components[closestLeafId]
				print("reinsp", closestLeaf.x, closestLeaf.y, closestLeaf.z, "size", #components, "upd", hasUpdatedLeaf)

				-- navigate to leaf, no need for inspection on the way

				-- navigateToPos is allowed to destroy blocks on the way and does not update treeMap
				-- if self:navigateToPos(closestLeaf.x, closestLeaf.y, closestLeaf.z) then 

				-- no need for inspection on the way though...
				-- TODO: expand PathFinder for explicitly following only air blocks or nil 
				--   (but check them for air while following the path)

				-- small issue: reinspection only happens for leaves with distance <= 3
				--  mineTowardsLog also handles leaves with distance 4 and 5
				

				local result = digToPosUsingLeaves(closestLeaf.x, closestLeaf.y, closestLeaf.z)
				if result == "interrupted" then 
					-- found new log on the way, add group back to unvisitedGroups
					unvisitedGroups[closestGroupId] = true
					-- we are out of the main mining loop, so call mineLogsDFS again
					mineLogsDFS()

				elseif result then 
					-- if a surrounding leaf is < 7, then mine towards log
					setReinspectionDistance(6)
					if mineTowardsLog(closestLeaf, nil) then
						print("found a log")
					end
					restoreReinspectionDistance()
					-- TODO: what if multiple logs are contained? they wont be caught
					-- update the group again using bfs floodfill?

				else
					print("unable to reach group", closestLeaf.x, closestLeaf.y, closestLeaf.z)
				end
			end
		end
	end


	-- initial pass
	inspectAll()
	-- mine all connected logs
	mineLogsDFS()
	-- do a second pass over leaves with distance 1
	mineLeaves()
	-- group remaining leaves and reinspect one of each group
	reinspectLeafGroups(uncheckedLeaves)

	-- perhaps also do a final gradient pass to find any remaining logs
	-- mineTowardsLog(self.pos, nil)
	-- rather not, could lead to mining neighbouring trees

	-- todo: set a max distance for the tree size from trunk?
	-- or detect that we entered another tree by detecting its trunk?


	local root = getRoot()
	print("tree ded","root", root)

	--return to start
	self:navigateToPos(startPos.x, startPos.y, startPos.z)
	self:turnTo(startOrientation)
	self.taskList:remove(currentTask)
end

function Miner:place(text)
	local ok, reason = turtle.place(text)
	return ok, reason
end

function Miner:growTree()

	local sapling = self:findInventoryItem("minecraft:oak_sapling")
	local bonemeal = self:findInventoryItem("minecraft:bone_meal")

	if sapling and bonemeal then 
		self:select(sapling)
		local ok, reason = self:place()
		if ok then
			print("Planted sapling")
			-- use bonemeal until tree grows
			self:select(bonemeal)
			local grown = false
			local maxAttempts = 64
			local attempts = 0
			repeat
				attempts = attempts + 1
				local ok, reason = self:place()
				if not ok then
					if reason == "Cannot place item here" then
						-- probably already grown
						local blockName, data = self:inspect(true)
						if blockName and logBlocks[blockName] then
							grown = true
						end
					end
					if not grown then
						print("Using bonemeal failed:", reason)
					end
				end
			until grown or attempts >= maxAttempts
		end
	end
end

function Miner:fellTree()

	-- inspect for wood
	-- mine wood until none found (can use mineVein?)
	-- track leave metadata while felling? -> no, changes while felling
	-- instead: after wood is removed, inspect surrounding blocks for leaves
	-- check leaves state for distance = 1 to 6   -- distance 7 is not generated by tree gen
	-- if found, mine in direction of lowest distance to find wood blocks
	-- check nearest leave blocks again for distance
	-- repeat until no leaves with distance found
	-- but do not mine all leaves

	-- could also use a breadth first search for leaves
	-- or update the distance of leaves after mining wood blocks using own algorithm
	-- then return to leaves that could still be connected to wood
	-- segment the tree?

	--[[
		{
		state = {
			waterlogged = false,
			persistent = false,
			distance = 6,
		},
		name = "minecraft:oak_leaves",
		tags = {
			[ "minecraft:replaceable_by_trees" ] = true,
			[ "computercraft:turtle_hoe_harvestable" ] = true,
			[ "minecraft:parrots_spawnable_on" ] = true,
			[ "computercraft:turtle_always_breakable" ] = true,
			[ "minecraft:lava_pool_stone_cannot_replace" ] = true,
			[ "minecraft:mineable/hoe" ] = true,
			[ "minecraft:completes_find_tree_tutorial" ] = true,
			[ "minecraft:leaves" ] = true,
			[ "minecraft:sword_efficient" ] = true,
		},
		}
	--]]

	-- then somehow make sure to collect saplings to make it self sufficient

end