
local global = global
local tasks = global.tasks
local taskList = global.list
local miner = global.miner
local nodeStream = global.nodeStream

local id = os.getComputerID()
local label = os.getComputerLabel() or id

local waitTime = 3 -- to not overload the host
local mapLog = {}
local unloadedLog = {}
local osEpoch = os.epoch

nodeStream.onStreamBroken = function(previous)
	--print("STREAM BROKEN")
end

-- called by onStreamMessage
nodeStream._clearLog = function()
	mapLog = {}
	unloadedLog = {}
end


local function packData()
	-- label = string -- no need to send this every time
	-- time = long
	-- pos = 3 longs
	-- orientation = 2 bit (0-3)
	-- home = 3 longs -- not needed
	-- fuelLevel = long 
	-- emptySlots = 5 bit (0-16)
	-- task = string
	-- lastTask = string 
	-- mapLog:
		-- entries long
		-- entryLength long?
		-- entry:
			-- chunkId long
			-- posId  13 bit / (12) (1-4096)
			-- value string or long
	-- unloadedLog: (not sent very often)
		-- array of chunkIds: long 
	
	
	
	local data = {
	
		label or nil,
		osEpoch("ingame"),
		
		miner.pos.x,
		miner.pos.y,
		miner.pos.z,
		miner.orientation,
		
		miner:getFuelLevel(),
		miner:getEmptySlots(),
		miner.taskList.first[1],
		miner.taskList.last[1],
		
		mapLog,
		unloadedLog,
	}
	
	local packet = string.pack((">zLlllHBlBzz"),
		"label",
		os.epoch("ingame"),
		-123,
		1234567,
		5000,
		3,
		100000,
		16,
		"task",
		"lastTask"
		
		)
		
end

nodeStream.onRequestStreamData = function(previous)
	local state = {}
	state.id = id
	state.label = label
	state.time = osEpoch("ingame") --ingame milliseconds
	
	if miner and miner.pos then -- somethings broken
		
		state.pos = miner.pos
		state.orientation = miner.orientation
		state.stuck = miner.stuck -- can be nil
		
		state.fuelLevel = miner:getFuelLevel()
		state.emptySlots = miner:getEmptySlots()
	
		--state.inventory = miner:
		local map = miner.map
		local minerLog = map.log
		if #minerLog > 0 then 
			local mapLog = mapLog
			local logCount = #mapLog
			for i = 1, #minerLog do
				mapLog[logCount+i] = minerLog[i]
			end
			map.log = {}
		end
		
		-- send unloadedChunks
		if #map.unloadedChunks > 0 then 
			local unloadedChunks = map.unloadedChunks
			for i = 1, #unloadedChunks do
				unloadedLog[#unloadedLog+1] = unloadedChunks[i]
			end
			map.unloadedChunks = {}
		end
		
		state.unloadedLog = unloadedLog
		state.mapLog = mapLog
		
		if miner.taskList.first then
			state.task = miner.taskList.first[1]
			state.lastTask = miner.taskList.last[1]
		end
	else
		state.pos = vector.new(-1,-1,-1)
		state.orientation = -1
		state.fuelLevel = -1
		state.emptySlots = -1
		state.stuck = true
		if global.err then
			state.lastTask = global.err.func
			state.task = global.err.text
		else
			state.lastTask = "ERROR"
			state.task = ""
		end
		state.mapLog = {}
	end	
	if global.err then
		state.lastTask = global.err.func
		state.task = global.err.text
	end

	return {"STATE", state }
end

while true do
	--sendState()
	if not nodeStream.host then
		--print("no streaming host")
		nodeStream:lookupHost(1, waitTime)
	else
		nodeStream:openStream(nodeStream.host,waitTime)
	end
	nodeStream:stream()
	nodeStream:checkWaitList()
	sleep(0.2) --0.2
end

print("how did we end up here...")