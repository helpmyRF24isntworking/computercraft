
local node = global.node
local nodeStream = global.nodeStream
local tasks = global.tasks
local miner = global.miner
local nodeRefuel = global.nodeRefuel
local nodeStorage = global.nodeStorage
local config = config

local bluenet = require("bluenet")
local ownChannel = bluenet.ownChannel
local channelBroadcast = bluenet.default.channels.broadcast
local channelHost = bluenet.default.channels.host
local channelRefuel = bluenet.default.channels.refuel
local channelStorage = bluenet.default.channels.storage
local computerId = os.getComputerID()
local osEpoch = os.epoch

local MinerTaskAssignment = require("classMinerTaskAssignment")

-- ################ start refueling logic

-- dont use answers, because more than one response is possible
nodeRefuel.onRequestAnswer = nil
nodeRefuel.onAnswer = nil 

nodeRefuel.onReceive = function(msg)
	local refuelClaim = miner.refuelClaim

	if msg.data[1] == "OCCUPIED_STATION" then
		local occupiedId = msg.data[2]
		local station = config.stations.refuel[occupiedId]
		if station then 
			station.occupied = true
			station.lastClaimed = msg.data.lastClaimed
		else 
			-- station is not in config
		end
		
	elseif msg.data[1] == "CLAIM_ACK" then
		if msg.data.owner then 
			-- approved by current owner of the station, ignore others denying it
			print("OWNER ACK", msg.sender, msg.data[1], msg.data[2])
			refuelClaim.approvedByOwner = true
		end

	elseif msg.data[1] == "CLAIM_DENY" then
		-- print(msg.sender, msg.data[1], msg.data[2])
		local id = msg.data[2]
		if id == refuelClaim.occupiedStation then
			refuelClaim.ok = false
		end
	
	elseif msg.data[1] == "REQUEST_STATION" then 
			if refuelClaim.occupiedStation then
				nodeRefuel:send(msg.sender, {"OCCUPIED_STATION", 
						refuelClaim.occupiedStation, 
						lastClaimed = refuelClaim.lastClaimed})
			--elseif refuelClaim.waiting then 
			--	nodeRefuel:answer(forMsg, {"WAITING", priority = refuelClaim.priority})
			end
			
	elseif msg.data[1] == "CLAIM_STATION" then
		local id = msg.data[2]
		local lastClaimed = osEpoch("utc")
		local station = config.stations.refuel[id]

		if station and id ~= refuelClaim.occupiedStation then
			station.occupied = true
			station.lastClaimed = lastClaimed
			-- nodeRefuel:send(msg.sender, {"CLAIM_ACK", id}) -- normal ACK not needed
		elseif id == refuelClaim.occupiedStation then
			if not refuelClaim.waiting and refuelClaim.isReleasing then
				-- if done refueling, pass station to first waiting turtle
				refuelClaim.isReleasing = false
				station.occupied = true
				station.lastClaimed = lastClaimed
				nodeRefuel:send(msg.sender, {"CLAIM_ACK", id, owner = true})
				--print("send ack owner", id)
			else
				-- station is occupied by self
				nodeRefuel:send(msg.sender, {"CLAIM_DENY", id})
				-- print("send deny", id, msg.sender)
			end
		else
			print("i have no station", refuelClaim.occupiedStation, id)
		end


	elseif msg.data[1] == "RELEASE_STATION" then
		local id = msg.data[2]
		local station = config.stations.refuel[id]
		if station then
			station.occupied = false

			-- OPTI: check if miner is looking for station? seems to work fine without
			--local refuelClaim = miner.refuelClaim
			--if refuelClaim.waiting then
				-- miner:tryClaimStation()
			--end
		end
	end
end

-- ################ end refueling logic

nodeStream.onStreamMessage = function(msg,previous) 
	-- reboot is handled in NetworkNode
	nodeStream._clearLog()
	
	local data = msg and msg.data
	if data and data[1] == "MAP_UPDATE" then
		if miner then 
			local map = miner.map
			local mapLog = data[2]
			for i = 1, #mapLog do
				local entry = mapLog[i]
				-- setChunkData does not result in the chunk being requested!
				map:setChunkData(entry[1],entry[2],entry[3],false)
			end
		end
	end
end

node.onRequestAnswer = function(msg)

	local data = msg.data
	local txt = data[1]
	if txt == "TASK_ASSIGNMENT" then 
		local task = MinerTaskAssignment:fromData(data[2])
		if task then 
			if miner then 
				local ok = miner.queue:addTask(task)
				if ok then 
					task:confirmQueued(msg, node)
				else
					task:reject(msg, node, "duplicate task")
				end
			else
				task:reject(msg, node, "no miner object")
			end
		else
			node:answer(msg, {"TASK_REJECTED", "invalid task data"})
			print(textutils.serialize(data[2]))
		end

	elseif txt == "CANCEL_TASK" then
		local taskId = data[2]
		if miner then 
			local ok = miner:cancelTaskAssignment(taskId, msg)
			if not ok then
				node:answer(msg, {"TASK_CANCEL_FAILED", taskId})
			end
		else
			node:answer(msg, {"TASK_CANCEL_FAILED", taskId})
		end
	elseif txt == "REQUEST_TASK_STATE" then
		local task
		if miner then 
			task = miner:getTaskAssignment()
		end
		if task then 
			node:answer(msg, {"TASK_STATE", task:toSerializableData()})
		else
			node:answer(msg, {"NO_TASK"})
		end
	elseif txt == "LOAD_BALANCING_ASSIGNMENT" then 
		local project, assignment = data[2].project, data[2].assignment
		local taskData = assignment.taskData

		-- REWRITE, UNUSED
		if taskData then 
			local task = MinerTaskAssignment:fromData(taskData)
			local ok
			if task then
				ok = miner.queue:addTask(task) -- how do we add recurring tasks from the host? 
				-- just add them as normal, but the funciton called needs to respawn the task
				if ok then
					task:confirmQueued(msg, node)
				else
					task:reject(msg, node, "duplicate task")
				end
			else
				node:answer(msg, {"TASK_REJECTED", "invalid task data"})
				print(textutils.serialize(data[2]))
			end
		else
			-- we apparently aready have a task and need to update it
			-- TODO: either scan the queue + current task or just do if project == "sapling" then miner:setSaplings()

		end

		if miner then 
			miner:handleLoadBalancingAssignment(assignment)
		end
	end
end

node.onReceive = function(msg)
	-- reboot is handled in NetworkNode
	if msg and msg.data and not msg.answer then
		local data = msg.data
		local txt = msg.data[1]
		if txt == "STOP" then
			if miner then 
				miner.stop = true
			end		
		else
			if miner then 
				miner.queue:addDirectTask(data[1], data[2], data[3])
			end
		end
	end
end

local pullEventRaw = os.pullEventRaw
local type = type

while true do
	
	-- oh no, to listen to alarms we would have to remove the modem_message filter 
	-- i would rather check the list every x seconds instead of receiving all events here (thats a lot!), though sleep does the same..

	local event, p1, p2, p3, msg, p5 = pullEventRaw("modem_message")
	if type(msg) == "table" and msg.recipient then

			msg.distance = p5
			local protocol = msg.protocol
			if protocol == "miner_stream" then
				--and ( not msg.data or msg.data[1] ~= "STREAM_OK" ) then
				nodeStream:handleMessage(msg)
				
			elseif protocol == "miner" or protocol == "chunk" then -- chunk optional
				node:handleMessage(msg)
			elseif protocol == "refuel" then
				nodeRefuel:handleMessage(msg)
			elseif protocol == "storage" or protocol == "storage_priority" then
				nodeStorage:handleMessage(msg)
			end

	elseif event == "terminate" then 
		error("Terminated",0)
	end
	
end