
running = true
monitor = {}
display = {}
node = nil
nodeStream = nil
nodeUpdate = nil
printStatus = false
printEvents = false
printSend = false
printMainTime = false

map = {}
updates = {}

-- turtles: state, mapLog, mapBuffer
turtles = {}
alerts = {}

pos = {}
taskGroups = {}


function saveStations(fileName)
	print("saving stations")
	if not fileName then fileName = "runtime/stations.txt" end
	local f = fs.open(fileName,"w")
	f.write(textutils.serialize(config.stations))
	f.close()
end
function loadStations(fileName)
	if not fileName then fileName = "runtime/stations.txt" end
	local f = fs.open(fileName,"r")
	if f then
		config.stations = textutils.unserialize( f.readAll() )
		f.close()
	else
		-- no problem if this file does not exist yet, uses config file isntead
		print("FILE DOES NOT EXIST", fileName)
	end
end

function saveTurtles(fileName)
	-- problem: two turtles have the same entry in their outgoing mapLog
	-- e.g. 3 sends mapupdate
	-- 		update is stored in maplog of 1 and 2
	--		update has the same reference in both tables
	--		-> repeated entries error
	-- solution: 
	--		1	save turtles seperately/sequentially or without maplog
	--		2	create shollow/deep copy of maplog
	print("saving turtles")
	if not fileName then fileName = "runtime/turtles.txt" end
	local f = fs.open(fileName,"w")
	f.write("{\n")
	for id,turtle in pairs(global.turtles) do
		f.write("[ "..id.." ] = { state = "..textutils.serialise(turtle.state).."\n},\n")
		print("written", id)
	end
	f.write("}")
	--f.write(textutils.serialize(global.turtles))
	f.close()
end

function loadTurtles(fileName)
	if not fileName then fileName = "runtime/turtles.txt" end
	local f = fs.open(fileName,"r")
	if f then
		global.turtles = textutils.unserialize( f.readAll() )
		f.close()
		for id,turtle in pairs(global.turtles) do
			if not turtle.state then
				turtle.state = { online = false, time = 0}
			else
				turtle.state.online = false
			end
			turtle.mapLog = {}
			turtle.mapBuffer = {}
			turtle.loadedChunks = {}
		end
	else
		print("FILE DOES NOT EXIST", fileName)
	end
	if not global.turtles then
		global.turtles = {}
	end
end

function saveAlerts(fileName)
	print("saving alerts")
	if not fileName then fileName = "runtime/alerts.txt" end
	local f = fs.open(fileName,"w")
	f.write(textutils.serialize(global.alerts))
	f.close()
end

function loadAlerts()
	if not fileName then fileName = "runtime/alerts.txt" end
	local f = fs.open(fileName,"r")
	if f then
		global.alerts = textutils.unserialize( f.readAll() )
		f.close()
	end
	if not global.alerts then
		global.alerts = { open = {}, handled = {} }
	end
	if not global.alerts.open then
		global.alerts.open = {}
	end
	if not global.alerts.handled then
		global.alerts.handled = {}
	end
end

function saveGroups(fileName)
	print("saving groups")
	if not fileName then fileName = "runtime/taskGroups.txt" end
	for _,taskGroup in pairs(global.taskGroups) do
		taskGroup.turtles = nil
	end
	local f = fs.open(fileName,"w")
	f.write(textutils.serialize(global.taskGroups))
	f.close()
	for _,taskGroup in pairs(global.taskGroups) do
		taskGroup:setTurtles(global.turtles)
	end
end


function saveConfig(fileName)
	-- only use to overwrite the original config file!
	-- actual stations and their allocations are stored in the runtime folder

	print("saving config")
	if not fileName then fileName = "general/config.lua" end

	saveStations() -- save allocations, then remove them for the general config file

	for _,station in pairs(config.stations.turtles) do
		station.occupied = false
		station.id = nil
	end
	for _,station in pairs(config.stations.refuel) do
		station.occupied = false
		station.id = nil
	end

	local f = fs.open(fileName,"w")
	for k,v in pairs(config) do
		f.write(k.." = " .. textutils.serialize(v) .. "\n")
	end
	--f.write(textutils.serialize(config))
	f.close()

	loadStations() -- restore allocations
end

	-- #######################################################
	-- goofy aah functions so normal users can use the program

local stringToOrientation = {
	["south"] 	= 0,  -- 	+z = 0	south		
	["west"] 	= 1, 	-- 	-x = 1	west
	["north"] 	= 2,	-- 	-z = 2	north
	["east"] 	= 3		-- 	+x = 3 	east
}
local orientationToString = {
	[0] = "south",
	[1] = "west",
	[2] = "north",
	[3] = "east"
}

function checkExistsStation(x,y,z)
	for _,station in pairs(config.stations.turtles) do
		if station.pos.x == x and station.pos.y == y and station.pos.z == z then
			print("turtle station already exists at", x,y,z)
			return station
		end
	end
	for _,station in pairs(config.stations.refuel) do
		if station.pos.x == x and station.pos.y == y and station.pos.z == z then
			print("refuel station already exists at", x,y,z)
			return station
		end
	end
	return nil
end
function deleteStation(x,y,z)
	if not x or not y or not z then
		print("no coordinates given")
		return
	end
	if not config or not config.stations then
		print("no stations loaded")
		return
	end
	for k,station in pairs(config.stations.turtles) do
		if station.pos.x == x and station.pos.y == y and station.pos.z == z then
			config.stations.turtles[k] = nil
			print("turtle station deleted")
			return true
		end
	end
	for k,station in pairs(config.stations.refuel) do
		if station.pos.x == x and station.pos.y == y and station.pos.z == z then
			config.stations.refuel[k] = nil
			print("refuel station deleted")
			return true
		end
	end
	return false
end
function deleteAllStations()
	if not config or not config.stations then
		print("no stations loaded")
		return
	end
	config.stations.turtles = {}
	config.stations.refuel = {}
	config.stations.refuelQueue = nil
	print("all stations deleted")
end

function listStations()
	if not config or not config.stations then
		print("no stations loaded")
		return
	end
	print("turtle stations:")
	for k,station in pairs(config.stations.turtles) do
		print(k, ":", station.pos.x, station.pos.y, station.pos.z, "facing", orientationToString[station.orientation])
	end
	print("refuel stations:")
	for k,station in pairs(config.stations.refuel) do
		print(k, ":", station.pos.x, station.pos.y, station.pos.z, "facing", orientationToString[station.orientation])
	end
	print("refuel queue:")
	local queue = config.stations.refuelQueue
	if queue then
		local origin = queue.origin
		print("origin:", origin.x, origin.y, origin.z, "maxDistance:", queue.maxDistance)
	else
		print("please set the refuel queue with setRefuelQueue(x,y,z,maxDistance)")
	end
end

function addStation(x,y,z,orientation,typ)
	-- use to add new for turtles or refueling
	if not x or not y or not z or not orientation or not typ then
		print("invalid arguments, usage: addStation( x, y, z, orientation, type)")
		return
	end
	if type(orientation) == "string" then 
		orientation = stringToOrientation[orientation]
		if not orientation then
			print("unknown orientation, please use")
			print(textutils.serialize(stringToOrientation))
			return
		end
	else
		if orientation < 0 or orientation > 3 then
			print("orientation out of bounds, please use")
			print(textutils.serialize(stringToOrientation))
			return
		end
	end

	if not config then
		print("config file not loaded")
		return
	end
	if not config.stations then
		config.stations = { turtles = {}, refuel = {} }
		print("no existing stations, creating new table...")
	end

	if checkExistsStation(x,y,z) then
		return
	end

	if typ == "turtle" then
		config.stations.turtles[#config.stations.turtles+1] = 
			{
				pos = vector.new(x,y,z),
				orientation = orientation,
				occupied = false,
				id = nil
			}
		print(typ, "station added at", x,y,z)
		return config.stations.turtles[#config.stations.turtles]
	elseif typ == "refuel" then
		config.stations.refuel[#config.stations.refuel+1] = 
			{
				pos = vector.new(x,y,z),
				orientation = orientation,
				occupied = false
			}
		print(typ, "station added at", x,y,z)
		return config.stations.refuel[#config.stations.refuel]
	else
		print("unknown station type, use \"turtle\" or \"refuel\"")
	end
	-- saveConfig()
end

function setRefuelQueue(x,y,z,maxDistance)
	config.stations.refuelQueue = {
		origin = vector.new(x,y,z),
		maxDistance = maxDistance or 8
	}
end

-- function autoGenerateStations(amount, facing)
-- 	-- use to add new for turtles or refueling
-- 	if not config then
-- 		print("config file not loaded")
-- 		return
-- 	end
-- 	if not config.stations then
-- 		config.stations = { turtles = {}, refuel = {} }
-- 		print("no existing stations, creating new table...")
-- 	end
-- 	if not amount or not facing then 
-- 		print("invalid arguments, usage: autoGenerateStations( amount, facing )")
-- 		return
-- 	end
-- 	-- create new stations based on the host position
-- 	local ox, oy, oz = 
-- 	for _,station in pairs(config.stations.turtles) do
-- 		if station.occupied == false then
-- 			addStation(station.pos.x,station.pos.y,station.pos.z,station.orientation,"turtle")
-- 		end
-- 	end
-- 	for _,station in pairs(config.stations.refuel) do
-- 		if station.occupied == false then
-- 			addStation(station.pos.x,station.pos.y,station.pos.z,station.orientation,"refuel")
-- 		end
-- 	end
-- end



