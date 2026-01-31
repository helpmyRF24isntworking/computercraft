
local global = global
local tasks = global.tasks
local taskList = global.list
local miner = global.miner
local nodeStream = global.nodeStream
local nodeStorage = global.nodeStorage

local id = os.getComputerID()
local label = os.getComputerLabel() or id

local waitTime = 3 -- to not overload the host
local mapLog = {}
local osEpoch = os.epoch

nodeStream.onStreamBroken = function(previous)
	--print("STREAM BROKEN")
end

-- called by onStreamMessage
nodeStream._clearLog = function()
	mapLog = {}
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

local state = { id = id, label = label }
local packet = {"STATE", state}
local invalidPos = vector.new(-1,-1,-1)

nodeStream.onRequestStreamData = function(previous)

	-- use preallocated state and packet
	local state = state
	local miner = miner

	state.time = osEpoch() --ingame
	
	if miner and miner.pos then -- somethings broken
		
		state.pos = miner.pos
		state.orientation = miner.orientation
		state.stuck = miner.stuck -- can be nil
		
		state.fuelLevel = miner:getFuelLevel()
		state.emptySlots = miner:getEmptySlots()
		-- state.progress = miner:getOverallProgress() include in assignment?
		-- might be interesting if no assignment exists, though this should not happen often
		state.progress = miner:getOverallProgress()
		state.assignment = miner:getAssignmentState()
		
		local mapLog = mapLog

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
		
		-- send loadedChunks
		state.loadedChunks = map:getLoadedChunks()

		state.mapLog = mapLog
		
		local taskList = miner.taskList
		if taskList.first then
			state.task = taskList.first[1]
			state.lastTask = taskList.last[1]
		else
			state.task = nil
			state.lastTask = nil
		end
	else
		state.pos = invalidPos
		state.orientation = -1
		state.fuelLevel = -1
		state.emptySlots = -1
		state.progress = nil
		state.stuck = true
		if global.err then
			state.lastTask = global.err.func
			state.task = global.err.text
		else
			state.lastTask = "ERROR: NO MINER"
			state.task = ""
		end
		state.mapLog = {}
		state.unloadedLog = {}
	end	
	local err = global.err
	if err then
		state.lastTask = err.func
		state.task = err.text
	end

	return packet
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
	nodeStorage:checkWaitList() -- !! should not be done in send but in main, main is blocking however
	sleep(0.2)
end

print("how did we end up here...")