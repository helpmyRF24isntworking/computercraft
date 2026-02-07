
local bluenet = require("bluenet")
local ownChannel = bluenet.ownChannel
local channelBroadcast = bluenet.default.channels.broadcast
local channelHost = bluenet.default.channels.host
local channelStorage = bluenet.default.channels.storage
local computerId = os.getComputerID()

local global = global
local monitor = global.monitor

local node = global.node
local nodeStream = global.nodeStream
local nodeUpdate = global.nodeUpdate
local nodeStorage = global.storage.node

global.timerCount = 0
global.eventCount = 0
global.messageCount = 0

local updateRate = 0.1

local pullEventRaw = os.pullEventRaw -- = coroutine.yield
local type = type
--local tmr = os.startTimer(updateRate)

while global.running and global.receiving do
	--local event = {os.pullEventRaw()}
	
	-- !! none of the functions called here can use os.pullEvent !!
	
	local event, p1, p2, p3, msg, p5 = pullEventRaw()
	global.eventCount = global.eventCount + 1
	if event == "modem_message" and type(msg) == "table" and msg.recipient then
			
			-- event, modem, channel, replyChannel, message, distance
			global.messageCount = global.messageCount + 1
			msg.distance = p5
			local protocol = msg.protocol
			if protocol == "miner_stream" then
				nodeStream:addMessage(msg)
				-- handle events immediately to avoid getting behind
				--nodeStream:handleEvent(event) 
				
			elseif protocol == "update" then
				nodeUpdate:addMessage(msg)
			elseif protocol == "miner" then
				node:addMessage(msg)
			elseif protocol == "chunk" then
				-- handle chunk requests immediately
				-- would be nice but seems to lead to problems
				node:handleMessage(msg)
				--node:addMessage(msg)
			elseif protocol == "storage" then 
				nodeStorage:addMessage(msg)
			elseif protocol == "storage_priority" then
				nodeStorage:handleMessage(msg)
			end
			
	elseif event == "timer" then
		global.timerCount = global.timerCount + 1

	elseif event == "monitor_touch" or event == "mouse_up"
		or event == "mouse_click" or event == "monitor_resize" then -- scroll only in shellDisplay
		monitor:addEvent({event,p1,p2,p3,msg,p5})
		
	elseif event == "terminate" then 
		error("Terminated",0)
	end
	if event and global.printEvents then
		if not (event == "timer") then
			print(event,p1,p2,p3,msg,p5)
		end
	end
end