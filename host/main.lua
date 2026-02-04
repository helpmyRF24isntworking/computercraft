
local global = global

local node = global.node
local nodeStream = global.nodeStream
local nodeUpdate = global.nodeUpdate
local nodeStorage = global.storage.node

local map = global.map
local turtles = global.turtles
local updates = global.updates
local alerts = global.alerts
local taskManager = global.taskManager

local fileExpiration = 1000 * 5 -- 30s
local files = {}
local folders = {}
local foldersLastRead = {}
-- nodeStatus.onRequestAnswer = function(forMsg)
	-- -- check if state is outdated before answering
	-- no, best to go by newest only, not oldest first
	-- if node:checkValid(forMsg) then
	-- node:answer(forMsg,{"RECEIVED"})
-- end
local osEpoch = os.epoch
local tableinsert = table.insert

nodeStream.onStreamMessage = function(msg,previous)
	local msgData, sender = msg.data, msg.sender
	if previous.data[1] == "MAP_UPDATE" then	
		if global.printSend then
			print(osEpoch(),"MAP STREAM", sender)
		end
		turtles[sender].mapBuffer = {}
	end
	if msgData[1] == "STATE" then
		updates[#updates+1] = msgData[2]
	end
end

nodeStream.onStreamBroken = function(previous)
	-- idk
end

nodeUpdate.onRequestAnswer = function(forMsg)

	if forMsg.data[1] == "FILE_REQUEST" then
		local requestedFile = forMsg.data[2]
		local requestedModified = requestedFile.modified
		local fileName = requestedFile.fileName
		local timeRead = osEpoch("utc")
		print("----sending", fileName .."----")	
		if not files[fileName] then
		
			local file = fs.open(fileName, "r")
			if file then 
				local modified = fs.attributes(fileName).modified
				local fileData = file.readAll()
				file.close()
				files[fileName] = { name = fileName, data = fileData, lastRead = timeRead, modified = modified }
			end

		elseif timeRead - files[fileName].lastRead > fileExpiration then 
			if fs.exists(fileName) then 
				local modified = fs.attributes(fileName).modified
				if modified > files[fileName].lastRead then 
					-- file has been changed since last read
					local file = fs.open(fileName, "r")
					if file then 
						local fileData = file.readAll()
						file.close()
						files[fileName] = { name = fileName, data = fileData, lastRead = timeRead, modified = modified }
					end					
				else
					files[fileName].lastRead = timeRead
				end
			else
				files[fileName] = nil
			end
		end
		
		local file = files[fileName] 
		if file then 
			if not requestedModified or file.modified > requestedModified then
				nodeUpdate:answer(forMsg, { "FILE" , file })
				sleep(0)
			else
				nodeUpdate:answer(forMsg, { "FILE_UNCHANGED", { name = fileName } })
			end
		else
			nodeUpdate:answer(forMsg, { "FILE_MISSING", { name = fileName } })
		end
		
	elseif forMsg.data[1] == "FOLDERS_REQUEST" then
	
		local requestedFolders = forMsg.data[2]
		local folderNames = requestedFolders.folderNames
		local existingFiles = requestedFolders.files
		local foldersToSend = {}
		local missingFolders = {}
		
		local timeRead = osEpoch("utc")
		
		for _,folderName in ipairs(folderNames) do
		
			local filesToSend = {}	
			
			local folder = folders[folderName]
			if not folder then
				if fs.isDir(folderName) then 
					folders[folderName] = {}
					foldersLastRead[folderName] = timeRead
					-- read files
					for _, fileName in ipairs(fs.list('/' .. folderName)) do
						local modified = fs.attributes(folderName.."/"..fileName).modified
						local file = fs.open(folderName.."/"..fileName, "r")
						if file then 
							local fileData = file.readAll()
							file.close()
							folders[folderName][fileName] = { data = fileData, lastRead = timeRead, modified = modified }
						end
						
						local existingFile = existingFiles and existingFiles[fileName]
						if not existingFile or modified > existingFile.modified then 
							-- print("add read", fileName, modified, existingFile and existingFile.modified)
							filesToSend[fileName] = folders[folderName][fileName]
						end

						if osEpoch("utc") - timeRead > 1000 then timeRead = osEpoch("utc"); sleep(0) end
					end
				else
					filesToSend = nil
				end
			else 
				if timeRead - foldersLastRead[folderName] > fileExpiration then 
					-- folder must be updated
					foldersLastRead[folderName] = timeRead
					
					for _, fileName in ipairs(fs.list('/' .. folderName)) do
						local cachedFile = folder[fileName]
						local modified = fs.attributes(folderName.."/"..fileName).modified					
						
						if not cachedFile or modified > cachedFile.lastRead then 
							local file = fs.open(folderName.."/"..fileName, "r")
							if file then 
								local fileData = file.readAll()
								file.close()
								folder[fileName] = { data = fileData, lastRead = timeRead, modified = modified }
							end	
						elseif cachedFile then 
							cachedFile.lastRead = timeRead
						end
						
						local existingFile = existingFiles and existingFiles[fileName]
						if not existingFile or modified > existingFile.modified then 
							print("add chg", fileName, modified, existingFile and existingFile.modified)
							filesToSend[fileName] = folder[fileName]
						end

						if osEpoch("utc") - timeRead > 1000 then timeRead = osEpoch("utc"); sleep(0) end
					end
					-- !! does not detect if files which exist in cache have been deleted
				else
					if existingFiles then 
						for fileName, file in pairs(folder) do
							local existingFile = existingFiles[fileName]
							if not existingFile or file.modified > existingFile.modified then 
								print("add cache", fileName, file.modified, existingFile and existingFile.modified)
								filesToSend[fileName] = file
							end
						end
					else
						print("full folder, no existing files")
						filesToSend = folder
					end
					
				end
			end
			if filesToSend then 
				foldersToSend[folderName] = filesToSend
			else
				table.insert(missingFolders, folderName)
			end
			
		end
		
		
		if foldersToSend then 
			nodeUpdate:answer(forMsg, {"FOLDERS", foldersToSend})
			--sleep(0)
		else
			nodeUpdate:answer(forMsg, { "FOLDERS_MISSING", missingFolders })
		end
		
		local timeFolders = osEpoch("utc")-timeRead
		print(timeFolders, forMsg.sender, "FOLDERS")	
		if timeFolders > 50 then 
			sleep(0)
		end
		
	elseif forMsg.data[1] == "HOST_TRANSFER_REQUEST" then
		-- do we want to accept host transfer? yeah why not
		nodeUpdate:answer(forMsg, {"HOST_TRANSFER_OK"})

	elseif forMsg.data[1] == "HOST_TRANSFER_PREPARE" then 
		-- prepare for host transfer

		global.sending = false 			-- stop sending to turtles
		global.processOnlyNodeUpdate = true -- stop processing other messages

		-- save all current data to disk
		global.beforeTerminate()

		nodeUpdate:answer(forMsg, {"HOST_TRANSFER_PREPARE_OK"})

	elseif forMsg.data[1] == "HOST_TRANSFER_COMPLETE" then
		-- notify other nodes that a new host exists
		local newHost = forMsg.sender
		local noAck = {}
		for id, turtle in pairs(turtles) do
			if id ~= newHost and ( turtle.state and turtle.state.online ) then
				local noAnswer = false
				local answer = node:send(id, {"NEW_HOST", newHost}, true, true, 1)
				if not answer then noAnswer = true end
				local answer = nodeStream:send(id, {"NEW_HOST", newHost}, true, true, 1)
				if not answer then noAnswer = true end
				if noAnswer then
					noAck[#noAck+1] = id
				end
			end
		end
		nodeUpdate:answer(forMsg, {"HOST_TRANSFER_COMPLETE_OK", { noAck = noAck }})
		-- also clear the file cache, could be lots of files
		files = {}
		folders = {}
		foldersLastRead = {}

	elseif forMsg.data[1] == "HOST_TRANSFER_SHUTDOWN" then
		nodeUpdate:answer(forMsg, {"HOST_TRANSFER_SHUTDOWN_OK"})
		global.display:terminate()
		os.shutdown()

	elseif forMsg.data[1] == "HOST_TRANSFER_FAILED" then
		-- resume normal operations
		print("HOST_TRANSFER_FAILED")
		global.sending = true
		global.processOnlyNodeUpdate = false
		
		-- maybe reboot to clear all the received messages in meantime?
		-- also reclaim all the turtles, so they know this is still host
		nodeUpdate:answer(forMsg, {"HOST_TRANSFER_FAILED_OK"})
	end
end


local function checkOnline(id)
	local turt = turtles[id]
	local online = false
	if turt then
		local timeDiff = osEpoch() - turt.state.time
		if timeDiff > 144000 then
			online = false
		else
			online = true
		end
	end
	return online
end

local function getStation(id)
	local result
	-- check already allocated stations
	for _,station in pairs(config.stations.turtles) do
		if station.id == id then
			result = station
			station.occupied = true
			break
		end
	end
	-- check free stations
	if not result then
		for _,station in pairs(config.stations.turtles) do
			if station.occupied == false then
				result = station
				station.occupied = true
				station.id = id
				break
			end
		end
	end 
	-- reset offline station allocations
	if not result then
		for _,station in pairs(config.stations.turtles) do
			if station.id and not checkOnline(station.id) then
				station.occupied = false
				station.id = nil
			end
			
			if station.occupied == false then
				result = station
				station.occupied = true
				station.id = id
				break
			end
		end
	end
	return result
end

local function addAlert(msg)
	-- check for duplicate alerts for same turtle, only keep newest
	for i,alert in ipairs(alerts.open) do
		if alert.id == msg.sender then
			-- add existing alert to handled
			table.remove(alerts.open,i)
			table.insert(alerts.handled, alert)
			break
		end
	end
	-- add new alert to open
	local state = msg.data[2]
	local alert = { lastHandledTime = osEpoch("utc"), time = osEpoch("utc"), id = msg.sender, state = state }
	alerts.open[#alerts.open+1] = alert
	global.saveAlerts()
	return alert
end


local function handleAlert(alert)
	-- do something with alert
	-- ask turtles to recover the turtle

	local result = false
	for id,turtle in pairs(turtles) do
		local state = turtle.state

		if id ~= alert.id and state.online and not state.task and not state.stuck then
			-- turtle is available to help
			local task = taskManager:addTaskToTurtle(id, "recoverTurtle", {alert.id, alert.state.pos})
			if task then 
				print("Turtle", id, "accepted recovery task for", alert.state.id)
				result = true
			end
		end
	end

	if result then 
		-- remove alert
		for i,a in ipairs(alerts.open) do
			if a == alert then
				table.remove(alerts.open,i)
				table.insert(alerts.handled, alert)
				global.saveAlerts()
				break
			end
		end
	else
		alert.lastHandledTime = osEpoch("utc")
	end

end

local function checkAlerts()
	for i,alert in ipairs(alerts.open) do
		local timeDiff = osEpoch("utc") - alert.lastHandledTime
		if timeDiff > 60000 then
			-- re-handle alert
			handleAlert(alert)
		end
	end
end

node.onRequestAnswer = function(forMsg)
	
	local data, sender = forMsg.data, forMsg.sender
	local txt = data[1]
	if txt == "REQUEST_CHUNK" then
		-- local start = osEpoch("local")
		if map then
			--print("request_chunk",textutils.serialize(forMsg.data))
			local chunkId = data[2]
			node:answer(forMsg,{"CHUNK", map:accessChunk(chunkId,false,true)})
			-- mark the requested chunk as loaded, regardless if received?
			
			local turt = turtles[sender]
			if not turt then 
				turt = {
				state = { online = true, timeDiff = 0, time = osEpoch() },
				mapLog = {},
				mapBuffer = {},
				loadedChunks = {}
				}
				turtles[sender] = turt
			end
			
			-- is this really needed? 
			-- turt.loadedChunks[#turt.loadedChunks+1] = chunkId

			--print(id, forMsg.sender,"loaded chunk",chunkId)
			-- !!! os.pullEvent steals from receive if called by handleMessage directly !!!
			-- os.pullEvent(os.queueEvent("yield"))
		else
			node:answer(forMsg,{"NO_CHUNK"})
		end
		-- print(osEpoch("local")-start, "id", forMsg.sender, "chunk request", forMsg.data[2])
		
	elseif txt == "REQUEST_STATION" then
		--print(forMsg.sender, "station request")
		local station = getStation(sender)
		if station then
			node:answer(forMsg,{"STATION",station})
		else
			node:answer(forMsg,{"STATIONS_FULL"})
		end

	elseif txt == "ALERT" then
		local alert = addAlert(forMsg)
		node:answer(forMsg, {"ALERT_RECEIVED"})
		--handleAlert(alert)
	elseif taskManager:isTaskMessage(forMsg) then 
		taskManager:handleMessage(forMsg)

	end
end



local function checkUpdates()
	-- function not allowed to yield!!!
	-- (other enries to updates could be made?)

	local turtles = turtles
	local updateCount = #updates

	if global.printStatus then
		print("processing updates", updateCount)
	end

	if updateCount > 0 then		
		local tasks = taskManager:getTasks()

		-- 1: process updates into own map, update turtle states
		for i = 1, updateCount do
			local update = updates[i]
			local updateId = update.id
		
			local turt = turtles[updateId]
			if not turt then 
				turt = { 
					state = update,
					mapLog = {},
					mapBuffer = {},
					loadedChunks = {}
				}
				turtles[updateId] = turt
			else
				update.online = true
				update.timeDiff = 0
				turt.state = update
				turt.loadedChunks = update.loadedChunks
			end

			-- update task states
			local assignment = update.assignment
			if assignment then
				local task = tasks[assignment.id]
				if task then
					task:updateFromState(assignment, update.time)
				else
					--print("received update for unknown task", assignment.id)
				end
			end

			
			local mapLog = update.mapLog

			for i=1, #mapLog do 
				local entry = mapLog[i]
				local chunkId = entry[1]
				-- at startup, this needs to read a lot of chunks from disk
				map:setChunkData(chunkId,entry[2],entry[3],true)
			end
				
		end

		-- 2: before distribution, create an index of loaded chunks per turtle 
		local chunkToTurtles = {}  -- { [chunkId] = { turtle1, turtle2, ... } }
		for id, turt in pairs(turtles) do
			local loadedChunks = turt.loadedChunks
			if loadedChunks then
				for i = 1, #loadedChunks do 
					local chunkId = loadedChunks[i]
					local interestedTurtles = chunkToTurtles[chunkId]
					if not interestedTurtles then
						interestedTurtles = { turt }
						chunkToTurtles[chunkId] = interestedTurtles
					else
						interestedTurtles[#interestedTurtles+1] = turt
					end
				end
			end
		end

		-- 3: distribute updates to subscribed turtles
		for i = 1, updateCount do 
			local update = updates[i]
			local turt = turtles[update.id]
			local mapLog = update.mapLog

			for j = 1, #mapLog do
				local entry = mapLog[j]
				local chunkId = entry[1]
				
				local interestedTurtles = chunkToTurtles[chunkId]
				if interestedTurtles then
					for k = 1, #interestedTurtles do
						local otherTurtle = interestedTurtles[k]
						if otherTurtle ~= turt then
							local otherMapLog = otherTurtle.mapLog
							otherMapLog[#otherMapLog+1] = entry
						end
					end
				end
			end
		end

		updates = {}
		global.updates = updates
	end

	-- operations count:
	-- = nUpdates * nAvgLogEntries
	-- + nTurtles * nAvgLoadedChunks
	-- + nUpdates * nAvgLogEntries * nAvgInterestedTurtlesPerChunk

	-- == 14.500 for 250 turtles, 250 updates, 8 avgLog, 5 avgInterested, 10 avgLoaded
	 
	-- modem messages = nUpdates + nTurtles = 500


	-- ######################################################

	-- compared to: nUpdates * (nTurtles-1) * avgLogEntries

	-- == 498.000 checks when turtles broadcast to each other

	-- modem_messages = nUpdates = 250

	-- at the cost of 0 version control, unloading support etc.
	
	-- assuming on my machine, 
	-- 1 million table inserts 						= 144 ms 
	-- 1 million random sparse existance checks 	= 114 ms
	-- 100.000 streams 	= 2.380 ms
	-- 100.000 sends	= 2.050 ms

	-- 1 msg = 0.0238ms 
	-- 1 tableins = 0.000144 ms

	-- extra table op cost 	= + 69,6 ms 
	-- saved modem msg cost = - 5,95 ms 
	-- 	                    = 63,65 ms slower than individiual sends

	-- A: ~14 ms @ 500 messages, 14.500 table ops
	-- B: ~77 ms @ 250 messages, 498.000 table ops

	-- B rises exponetially with more turtles, A linearly

end

local function refreshState()
	-- refresh the online state of the turtles
	local time = osEpoch()
	for id,turtle in pairs(turtles) do
		local state = turtle.state
		state.timeDiff = time - state.time
		if state.timeDiff > 144000 then
			state.online = false
		else
			state.online = true
		end
	end
end


while global.running do
	
	local start = osEpoch("local")
	
	if global.processOnlyNodeUpdate then
		nodeUpdate:checkMessages()
	else
		nodeStorage:checkMessages()
		--local s = os.epoch("local")
		node:checkMessages()
		--print(os.epoch("local")-s,"events")
		--s = os.epoch("local")
		nodeStream:checkMessages()
		--print(os.epoch("local")-s,"nodeStream:checkEvents")
		--s = os.epoch("local")
		nodeUpdate:checkMessages()
		--print(os.epoch("local")-s,"nodeUpdate:checkEvents")
		--s = os.epoch("local")
		checkUpdates()
		--print(os.epoch("local")-s,"checkUpdates")
		--s = os.epoch("local")
		refreshState()
		--print(os.epoch("local")-s, "refreshState")
		checkAlerts()

	end
	if global.printMainTime then 
		print(osEpoch("local")-start, "done")
	end
	sleep(0)
end

print("eeeh how")