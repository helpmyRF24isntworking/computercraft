
-- bluenet, a modified rednet for better performance


local bluenet = {}

local default = {
	typeSend = 1,
	typeAnswer = 2,
	typeDone = 3,
	waitTime = 1,
	
	channels = {
		max = 65400,
		broadcast = 65401, 
		repeater = 65402,
		host = 65403,
		refuel = 65404,
		storage = 65405,
	}
}
bluenet.default = default
--msg = { id, time, sender, recipient, protocol, type, data, answer, wait, distance}

local receivedMessages = {}
local receivedTimer = nil -- does that work?
local osEpoch = os.epoch


local opened = false
local modem = nil
local ownChannel = nil
bluenet.ownChannel = nil
local computerId = os.getComputerID()

function bluenet.idAsChannel(id)
	return (id or os.getComputerID()) % default.channels.max
end
local idAsChannel = bluenet.idAsChannel

function bluenet.findModem()
	for _,modem in ipairs(peripheral.getNames()) do
		local modemType, subType = peripheral.getType(modem)
		if modemType == "modem" and peripheral.call(modem, "isWireless") then
			return modem
		end
	end
	return nil
end
local findModem = bluenet.findModem

function bluenet.open(modem)
	if not opened then 
		
		if not modem then
			print("NO MODEM")
			opened = false
		end
		peripheral.call(modem, "open", ownChannel)
		peripheral.call(modem, "open", default.channels.broadcast)
		print("opened",ownChannel,default.channels.broadcast)
		
	end
	opened = true
	return true
end		
local open = bluenet.open

function bluenet.close(modem)
	if modem then
		if peripheral.getType(modem) == "modem" then
			peripheral.call(modem, "close", ownChannel)
			peripheral.call(modem, "close", default.channels.broadcast)
			opened = false
		end
	else
		for _,modem in ipairs(peripheral.getNames()) do
			if isOpen(modem) then
				close(modem)
			end
		end
	end
end
local close = bluenet.close

local function isOpen(modem)
	if modem then
		if peripheral.getType(modem) == "modem" then
			return peripheral.call(modem, "isOpen", ownChannel)
				and peripheral.call(modem, "isOpen", default.channels.broadcast)
		end
	else
		for _,modem in ipairs(peripheral.getNames()) do
			if isOpen(modem) then
				return true
			end
		end
	end
	return false
end
bluenet.isOpen = isOpen

function bluenet.isChannelOpen(modem, channel)
	if not modem then 
		print("NO MODEM", modem)
		return false
	end
	return peripheral.call(modem, "isOpen", channel)
end
local isChannelOpen = bluenet.isChannelOpen

function bluenet.openChannel(modem, channel)
	if not isChannelOpen(modem, channel) then 
		if not modem then
			print("NO MODEM")
			return false
		end
		peripheral.call(modem, "open", channel)
		print("opened", channel)
	end
	return true
end
local openChannel = bluenet.openChannel

function bluenet.closeChannel(modem, channel)
	if not modem then 
		print("NO MODEM", modem)
		return false
	end
	if isChannelOpen(modem, channel) then 
		print("closed", channel)
		return peripheral.call(modem, "close", channel)
	end
	return true
end
local closeChannel = bluenet.closeChannel




local startTimer = os.startTimer
local cancelTimer = os.cancelTimer
local osClock = os.clock
local timerClocks = {}
local timers = {}
local pullEventRaw = os.pullEventRaw
local type = type

function bluenet.receive(protocol, waitTime)
	local timer = nil
	local eventFilter = nil
	
	-- CAUTION: if bluenet is loaded globally, 
	--	TODO:	the timers must be distinguished by protocol/coroutine
	-- 			leads to host being unable to reboot!!!
	-- is the protocol ever nil? if so, this code wont work!
	
	if waitTime then
		local t = osClock()
		local clocks, tmrs = timerClocks[protocol], timers[protocol]
		if not clocks then 
			clocks = {}
			tmrs = {}
			timerClocks[protocol] = clocks
			timers[protocol] = tmrs
		end
		if clocks[waitTime] ~= t then 
			--cancel the previous timer and create a new one
			cancelTimer((tmrs[waitTime] or 0))
			timer = startTimer(waitTime)
			--print( protocol, "cancelled", tmrs[waitTime], "created", timer, "diff", timer - (timers[waitTime]or 0))
			clocks[waitTime] = t
			tmrs[waitTime] = timer
		else
			timer = tmrs[waitTime]
			--print( protocol, "reusing", timer)
		end
		
		eventFilter = nil
	else
		eventFilter = "modem_message"
	end
	
	--print("receiving", protocol, waitTime, timer, eventFilter)
	while true do
		local event, modem, channel, sender, msg, distance = pullEventRaw(eventFilter)
		--if event == "modem_message" then print(os.clock(),event, modem, channel, sender) end
		
		if event == "modem_message"
			--and ( channel == ownChannel or channel == default.channels.broadcast 
			--	or channel == default.channels.host ) 
			and type(msg) == "table" 
			--and type(msg.id) == "number" and not receivedMessages[msg.id]
			and ( type(msg.recipient) == "number" and msg.recipient
			and ( msg.recipient == computerId 
				or msg.recipient == default.channels.broadcast 
				or msg.recipient == default.channels.host 
				or msg.recipient == default.channels.refuel 
				or msg.recipient == default.channels.storage ) )
				-- WHY EVEN CHECK THE CHANNEL? only those channels are opened anyways so we wont receive any other
			and ( protocol == nil or protocol == msg.protocol )
			-- just to make sure its a bluenet message
			then
				msg.distance = distance
				-- event, modem, channel, replyChannel, message, distance
				--print("received", msg.id, msg.protocol)
				--receivedMessages[msg.id] = os.clock() + 9.5
				--resetTimer()
				--cancelTimer(timer)
				-- if osEpoch() > t then 
					-- print("cancel old timer")
					-- cancelTimer(timer)
				-- end
				return msg
				
		elseif event == "timer" then
			--print(os.clock(),event, modem, channel, sender, timer)
			
			if modem == timer then -- must be equal! >= geht nicht
				--print("returning nil")
				return nil
			end
		elseif event == "terminate" then 
			error("Terminated",0)
		end
		
	end
	
end

function bluenet.resetTimer()
	if not receivedTimer then receivedTimer = os.startTimer(10) end
end

function bluenet.clearReceivedMessages()
	receivedTimer = nil
	local time, hasMore = os.clock(), nil
	for id, deadline in pairs(receivedMessages) do
		if deadline <= now then receivedMessages[id] = nil
		else hasMore = true end
	end
	receivedTimer = hasMore and os.startTimer(10)
end


modem = findModem()
bluenet.modem = modem
ownChannel = idAsChannel()
bluenet.ownChannel = ownChannel


return bluenet