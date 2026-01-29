local bluenet = require("bluenet")
local ownChannel = bluenet.ownChannel
local channelBroadcast = bluenet.default.channels.broadcast
local channelStorage = bluenet.default.channels.storage
local computerId = os.getComputerID()

local global = global
if not global.storage then 
    error("NO GLOBAL STORAGE AVAILABLE",0)
end
local nodeStorage = global.storage.node


-- FOR FUTURE: dont just filter modem_message
-- turtles might want to use inventory_changed events
-- if turtle then messageFilter = nil else messageFilter = "modem_message" end

local pullEventRaw = os.pullEventRaw
local type = type
while global.running do

	-- !! none of the functions called here can use os.pullEvent !!
	local event, p1, p2, p3, msg, p5 = pullEventRaw("modem_message")
	if event == "modem_message"	and type(msg) == "table" and msg.recipient then

			-- event, modem, channel, replyChannel, message, distance
			msg.distance = p5
			local protocol = msg.protocol
			if protocol == "storage" then
				print("received", msg.data[1], msg.sender)
				nodeStorage:addMessage(msg)
			elseif protocol == "storage_priority" then
				print("priority", msg.data[1], msg.sender)
				nodeStorage:handleMessage(msg)
			end
			
	elseif event == "terminate" then 
		error("Terminated",0)
	end
end