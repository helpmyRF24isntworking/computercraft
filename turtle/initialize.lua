
-- initialize the required globals

require("classList")
require("classMiner")
require("classBluenetNode")
--require("classNetworkNode")

tasks = {}
global.list = List:new()
-- global.defaultHost = 0

local function createLabel()
	if os.getComputerLabel() == "" or not os.getComputerLabel() then
		os.setComputerLabel(tostring(os.getComputerID()))
	end
end

local function initNode()
	global.node = NetworkNode:new("miner")
end
local function initStream()
	global.nodeStream = NetworkNode:new("miner_stream")
end

createLabel()
parallel.waitForAll(initNode,initStream)

local status,err = pcall(function() 
	global.miner = Miner:new()
	global.map = global.miner.map
end )
global.handleError(err,status)