
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
local computerId = os.getComputerID()
local osEpoch = os.epoch




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
	
	--local start = os.epoch("local")
	local ct = 0
	if msg and msg.data and msg.data[1] == "MAP_UPDATE" then
		if miner then 
			local mapLog = msg.data[2]
			for i = 1, #mapLog do
				local entry = mapLog[i]
				
			--for _,entry in ipairs(mapLog) do
				-- setData without log
				-- setChunkData should not result in the chunk being requested!
				miner.map:setChunkData(entry[1],entry[2],entry[3],false)
				ct = ct + 1
			end
		end
	end
	--print(os.epoch("local")-start,"onStream", ct)
end

node.onReceive = function(msg)
	-- reboot is handled in NetworkNode
	if msg and msg.data then
		if msg.data[3] then 
			--print("received:", msg.data[1], msg.data[2], unpack(msg.data[3]))
		else 
			--print("received:", msg.data[1], msg.data[2]) 
		end
		
		if msg.data[1] == "STOP" then
			if miner then 
				miner.stop = true
			end
		else
			table.insert(tasks, msg.data)
		end
	end
end

local pullEventRaw = os.pullEventRaw
local type = type

while true do
	
	local event, p1, p2, p3, msg, p5 = pullEventRaw("modem_message")
	if --( p2 == ownChannel or p2 == channelBroadcast ) 
		type(msg) == "table"
		and ( type(msg.recipient) == "number" and msg.recipient
		and ( msg.recipient == computerId or msg.recipient == channelBroadcast
			or msg.recipient == channelHost or msg.recipient == channelRefuel ) )
		then
			msg.distance = p5
			local protocol = msg.protocol
			if protocol == "miner_stream" then
				--and ( not msg.data or msg.data[1] ~= "STREAM_OK" ) then
				nodeStream:handleMessage(msg)
				
			elseif protocol == "miner" or protocol == "chunk" then -- chunk optional
				node:handleMessage(msg)
			elseif protocol == "refuel" then
				nodeRefuel:handleMessage(msg)
			elseif protocol == "storage" then
				nodeStorage:handleMessage(msg) -- maybe remove nodeStorage 
			end
	elseif event == "terminate" then 
		error("Terminated",0)
	end
	
end