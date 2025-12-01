
--require("classNetworkNode")
require("classBluenetNode")
local Monitor = require("classMonitor")
local HostDisplay = require("classHostDisplay")
--require("classMap")
require("classChunkyMap")
require("classTaskGroup")



local function initNode()
	global.node = NetworkNode:new("miner",true)
end
local function initStream()
	global.nodeStream = NetworkNode:new("miner_stream",true)
end
local function initUpdate()
	global.nodeUpdate = NetworkNode:new("update",true)
end

local function initPosition()
	local x,y,z = gps.locate()
	if x and y and z then
		x, y, z = math.floor(x), math.floor(y), math.floor(z)
		global.pos = vector.new(x,y,z)
	else
		print("gps not working")
		global.pos = vector.new(0,70,0) -- this is bad for turtles especially
	end
	print("position:",global.pos.x,global.pos.y,global.pos.z)
end

local function loadGroups(fileName)
	if not fileName then fileName = "runtime/taskGroups.txt" end
	local f = fs.open(fileName,"r")
	local groups = nil
	if f then
		groups = textutils.unserialize( f.readAll() )
		f.close()
	else
		-- no problem if this file does not exist yet
		-- print("FILE DOES NOT EXIST", fileName)
	end
	if groups then 
		for _,group in pairs(groups) do
			local taskGroup = TaskGroup:new(global.turtles,nil,group)
			global.taskGroups[taskGroup.id] = taskGroup
		end
	else
		global.taskGroups = {}
	end
end

-- quick boot
parallel.waitForAll(initNode,initStream,initUpdate)



initPosition()
global.map = ChunkyMap:new(false)
global.map:setMaxChunks(2048) --256 for operational use
global.map:setLifeTime(-1)
global.map:load()
global.loadTurtles()
global.loadStations()
loadGroups()
global.loadAlerts()

if not pocket then -- pocket uses shellDisplay
	global.monitor = Monitor:new()
	global.display = HostDisplay:new(1,1,global.monitor:getWidth(),global.monitor:getHeight())
end
