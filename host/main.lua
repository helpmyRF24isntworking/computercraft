
local global = global

local node = global.node
local nodeStream = global.nodeStream
local nodeUpdate = global.nodeUpdate
local nodeStorage = global.storage.node

local map = global.map
local turtles = global.turtles
local updates = global.updates
local alerts = global.alerts

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
	if previous.data[1] == "MAP_UPDATE" then	
		if global.printSend then
			print(osEpoch(),"MAP STREAM",msg.sender)
		end
		turtles[msg.sender].mapBuffer = {}
	end
	if msg.data[1] == "STATE" then
		updates[#updates+1] = msg.data[2]
		--table.insert(updates, msg.data[2])
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
		global.map:save()
		global.saveConfig() -- optional but whatever
		global.saveStations()
		global.saveGroups()
		global.saveAlerts()

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
			local answer, forMsg = node:send(id, {"DO", "recoverTurtle", {alert.id, alert.state.pos}}, true, true, 1)
			if answer then 
				if answer.data[1] == "RECEIVED" then 
					print("Turtle", answer.sender, "accepted recovery task for", alert.state.id)
					result = true
					break
				else
					print("received other", answer.data[1])
				end
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
	
	if forMsg.data[1] == "REQUEST_CHUNK" then
		-- local start = osEpoch("local")
		if map then
			--print("request_chunk",textutils.serialize(forMsg.data))
			local chunkId = forMsg.data[2]
			node:answer(forMsg,{"CHUNK", map:accessChunk(chunkId,false,true)})
			-- mark the requested chunk as loaded, regardless if received?
			if not turtles[forMsg.sender] then 
				turtles[forMsg.sender] = {
				state = { online = true, timeDiff = 0, time = osEpoch() },
				--state = { online = false, time = 0 },
				mapLog = {},
				mapBuffer = {},
				loadedChunks = {}
				}
			end
			turtles[forMsg.sender].loadedChunks[chunkId] = true
			--print(id, forMsg.sender,"loaded chunk",chunkId)
			-- !!! os.pullEvent steals from receive if called by handleMessage directly !!!
			-- os.pullEvent(os.queueEvent("yield"))
		else
			node:answer(forMsg,{"NO_CHUNK"})
		end
		-- print(osEpoch("local")-start, "id", forMsg.sender, "chunk request", forMsg.data[2])
		
	elseif forMsg.data[1] == "REQUEST_STATION" then
		--print(forMsg.sender, "station request")
		local station = getStation(forMsg.sender)
		if station then
			node:answer(forMsg,{"STATION",station})
		else
			node:answer(forMsg,{"STATIONS_FULL"})
		end
	-- elseif forMsg.data[1] == "REQUEST_MAP" then
		-- print("map request")
		-- if map then
			-- node:answer(forMsg,{"MAP", map:getMap()})
			-- os.pullEvent(os.queueEvent("yield"))
		-- else
			-- node:answer(forMsg,{"NO_MAP"})
		-- end
	elseif forMsg.data[1] == "ALERT" then
		local alert = addAlert(forMsg)
		node:answer(forMsg, {"ALERT_RECEIVED"})
		--handleAlert(alert)
	end
end



local function checkUpdates()
	-- function not allowed to yield!!!
	local printStatus = global.printStatus
	
	for i = 1, #updates do
		local update = updates[i]
		local updateId = update.id
	
		local turtle = turtles[updateId]
		if not turtle then 
			turtles[updateId] = {
				state = update,
				mapLog = {},
				mapBuffer = {},
				loadedChunks = {}
			}
			turtle = turtles[updateId]
		else
			update.online = true
			update.timeDiff = 0
			turtle.state = update
		end
		
		-- keep track of unloaded chunks
		-- could result in an infinite request loop, 
		-- if the turtle just unloaded but another sent an update for this chunk
		-- -> delay?

		local loadedChunks = turtle.loadedChunks
		local unloadedLog = update.unloadedLog

		if unloadedLog then
			for i=1,#unloadedLog do
				loadedChunks[unloadedLog[i]] = nil
			end
		end
		
		local mapLog = update.mapLog
		for i=1,#mapLog do 
			local entry = mapLog[i]
			local chunkId = entry[1]

			map:setChunkData(chunkId,entry[2],entry[3],true)
			if printStatus then
				print("chunkid,pos,data", chunkId,entry[2],entry[3])
			end			
			
			-- turtle sent update for this chunk so it is probably loaded
			loadedChunks[chunkId]=true
			
			-- save data for distribution to other turtles
			-- alternative: not each entry but chunkwise logs
			-- loops should be reversed: turtles then entries
			for id,otherTurtle in pairs(turtles) do
				-- save data for distribution to other turtles
				if updateId ~= id then
					if otherTurtle.loadedChunks[chunkId] then
						tableinsert(otherTurtle.mapLog, entry)
						-- otherTurtle.chunks[entry[1]][entry[2]] = entry[3]
					end
				end
			end
			
		end
		
		
		if printStatus then
			local pos = update.pos
			local orientation = update.orientation
			local task = update.task
			local lastTask = update.lastTask
			print("state:", update.id, pos.x, pos.y, pos.z, orientation, lastTask, task)
		end
		
	end
	updates = {}
	
	
	local logs
	
	
	
	-- for i=1,#updates do
		-- local update = updates[i]
		
		-- for id,turtle in pairs(turtles) do

			-- for chunkId,chunkLog in pairs(update.chunkLogs) do
				-- if turtle.loadedChunks[chunkId] then
					-- turtle.chunkLogs[#turtle.chunkLogs+1] = chunkLog
				-- end
			-- end
		-- end
	-- end
	
	--process logs seperately to reduce nested loops ?
	-- complexity = turtleCount*(turtleCount-1)*avgEntriesPerLog
	-- for id,turtle in pairs(turtles) do
	-- 	local loadedChunks = turtle.loadedChunks
	-- 	local chunkLogs = turtle.chunkLogs
	-- 	for i=1,#logs do 
	-- 		local log = logs[i]
	-- 		if not log.sender == id then
	-- 			for k=1,#log do
	-- 				local entry = log[k]
	-- 				local chunkId = entry[1]
	-- 				if loadedChunks[chunkId] then
	-- 					if not chunkLogs[chunkId] then
	-- 						chunkLogs[chunkId] = { entry[2] = entry[3] }
	-- 					else
	-- 						chunkLogs[chunkId]][entry[2]] = entry[3]
	-- 					end
	-- 				end
					
	-- 			end
	-- 		end
	-- 	end
	-- end
		
		
		-- for senderId,log in ipairs(logs) do
			-- if not (senderId == id) then
				-- for _,entry in ipairs(log) do
					-- if turtle.loadedChunks[entry[1]] then
						-- table.insert(turtle.maplog,entry)
					-- end
				-- end
			-- end
		-- end
	-- end
	
end

local function refreshState()
	-- refresh the online state of the turtles
	for id,turtle in pairs(turtles) do
		local state = turtle.state
		state.timeDiff = osEpoch() - state.time
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