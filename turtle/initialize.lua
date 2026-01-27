
-- initialize the required globals


require("classList")
local Miner = require("classMiner")
require("classBluenetNode")

local utils = require("utils")
local StorageExtension = require("extTurtleStorage")
local TreeExtension = require("extTreeMining")
utils.loadExtension(StorageExtension, Miner)
utils.loadExtension(TreeExtension, Miner)

local TurtleStorage = require("classTurtleStorage")

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
local function initRefuel()
	global.nodeRefuel = NetworkNode:new("refuel", false, true)
end
local function initStorage()
	global.nodeStorage = NetworkNode:new("storage",false, true)
end

createLabel()
parallel.waitForAll(initNode,initStream, initRefuel, initStorage)

if not global.node.host then
	error(global.node.host, 0)
else
	local status,err = pcall(function() 
		global.miner = Miner:new()
		global.map = global.miner.map
		
	end )
	global.handleError(err,status)
	
	global.turtleStorage = TurtleStorage:new(global.miner, global.nodeStorage)
end