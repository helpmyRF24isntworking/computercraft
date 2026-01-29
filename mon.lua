function printGlobals()
	count = 0
	for _,entry in pairs(global.map.chunks) do
		count = count + 1
	end
	print("map chunks       ", count)
	print("map.log          ", #global.map.log)
	print("global.updates   ", #global.updates)
end

function printTurtles()
	for id,turtle in pairs(global.turtles) do
		print("turtle.state.mapLog", id, #turtle.state.mapLog)
		print("turtle.maplog      ", id, #turtle.mapLog)
		print("turtle.mapBuffer   ", id, #turtle.mapBuffer)
	end
end

function printEvents()
	local streamCt = 0
	for _,v in pairs(global.nodeStream.streams) do streamCt = streamCt + 1 end
	print("streams          ", streamCt)
	print("stream.events    ", global.nodeStream.events.count)
	print("stream.messages  ", global.nodeStream.messages.count)
	print("stream.waitlist  ", global.nodeStream.waitlist.count)
	print("stream.streamlist", global.nodeStream.streamlist.count)
	
	print("global.updates   ", #global.updates)
	print("update.events    ", global.nodeUpdate.events.count)
	print("update.messages  ", global.nodeUpdate.messages.count)
	print("update.waitlist  ", global.nodeUpdate.waitlist.count)
	
	print("node.events      ", global.node.events.count)
	print("node.messages    ", global.node.messages.count)
	print("node.waitlist    ", global.node.waitlist.count)
	print("monitor.events   ", global.monitor.events.count)
end

function createDeepTable()
	local updates = {}
	local mapLogs = {}
	local ct = 0
	for i=1,2000 do
		mapLogs[i] = {}
		for k = 1,80 do
			table.insert(mapLogs[i], { x=200, y=200, z=200, data = "asdfkjasdflklaksjdflksadjflaskdfj"..k})
			ct = ct +1
		end
	end
	print("created mapLogs", ct)
	
	return mapLogs
end

function createFlatTable(mapLogs)
	local mapLogReturn = {}
	for _,mapLog in ipairs(mapLogs) do
		for _,entry in ipairs(mapLog) do
			table.insert(mapLogReturn,entry)
		end
	end
	return mapLogReturn
end

function emptyDeepTable(mapLogs)
	local start = os.epoch("local")
	for _,mapLog in ipairs(mapLogs) do
		for _,entry in ipairs(mapLog) do
			global.map:setData(entry.x,entry.y,entry.z,entry.data)
		end
	end
	print("deep", os.epoch("local")-start)
end

function emptyFlatTable(mapLog)
	local start = os.epoch("local")
	for _,entry in ipairs(mapLog) do
		global.map:setData(entry.x,entry.y,entry.z,entry.data)
	end
	print("flat", os.epoch("local")-start)
end

mapLogs = {}
mapLog = {}

function testTableInsert()
	mapLogs = createDeepTable()
	mapLog = createFlatTable(createDeepTable())
	
	emptyDeepTable(mapLogs)
	emptyFlatTable(mapLog)
	
end



printTurtles()
printGlobals()
printEvents()

--testTableInsert()
