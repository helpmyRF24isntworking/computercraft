require("classList")

local default = {
	typeSend = 1,
	typeAnswer = 2,
	typeDone = 3,
	waitTime = 1,
	
	channels = {
		broadcast = 65401, 
		repeater = 65402,
		max = 65400
	}
}
--msg = { id, time, sender, recipient, protocol, type, data, answer, wait }

local timer -- does that work?
local osEpoch = os.epoch
local NetworkNode = {}

function BlueNetNode:new(protocol,isHost)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	
	print("----INITIALIZING----")
	
	o.isHost = isHost or false
	o.protocol = protocol
	o.id = os.getComputerID()
	o.computers = {}
	o.waitlist = List:new()
	o.host = nil
	o.events = List:new()
	o.opened = false

	o:initialize()
	print("--------------------")
	return o
end

-- see https://github.com/cc-tweaked/CC-Tweaked/blob/a70baf0d742c077852889935990e64d68dafaed9/projects/core/src/main/resources/data/computercraft/lua/rom/apis/rednet.lua#L276


function initialize()
	self.channel = self:idAsChannel()
	self.modem = self:findModem()
	
end

function BlueNet:findModem()
	for _,modem in ipairs(peripheral.getNames()) do
		if peripheral.getType(name) == "modem" then
			return modem
		end
	end
	return nil
end

function Bluenet:idAsChannel(id)
	return (id or self.id) % default.channels.max
end

function BlueNet:open()
	if not self:isOpen(self.modem) then 
		
		if not modem then
			print("NO MODEM")
			self.opened = false
		end
		peripheral.call(self.modem, "open", self.channel)
		peripheral.call(self.modem, "open", default.channels.broadcast)
	end
	self.opened = true
	return true
end

function BlueNet:close(modem)
	if modem then
		if peripheral.getType(modem) == modem then
			peripheral.call(modem, "close", self.channel)
			peripheral.call(modem, "close", default.channels.broadcast)
			self.opened = false
		end
	else
		for _,modem in ipairs(peripheral.getNames()) do
			if self:isOpen(modem)
				self:close(modem)
			end
		end
	end
end

function BlueNet:isOpen(modem)
	if modem then
		if peripheral.getType(modem) == "modem" then
			return peripheral.call(modem, "isOpen", self.channel)
				and peripheral.call(modem, "isOpen", default.channels.broadcast)
		end
	else
		for _,modem in ipairs(peripheral.getNames()) do
			if self:isOpen(modem)
				return true
			end
		end
	end
	return false
end


function BlueNet:answer(sender,data,uuid)
	local msg = {
		id = uuid
		time = osEpoch()
		sender = self.channel
		recipient = sender
		protocol = self.protocol
		type = default.typeAnswer
		data = data
		answer = false
		wait = false
	}

	if not self.timer then self.timer = os.startTimer(10) end
	
	if recipient ~= default.channels.broadcast then
		recipient = self:idAsChannel(recipient)
	end
	
	if self.opened then
		peripheral.call(self.modem, "transmit", recipient, self.channel, msg
		-- needed?
		peripheral.call(self.modem, "transmit", default.channel.repeater, self.channel, msg)
	end

	return msg
end

function BlueNet:send(recipient,data,answer,wait,waitTime)
	if recipient ~= self.channel then
	
		local msg = {
			id = self:generateUUID(),
			time = osEpoch(),
			sender = self.channel,
			recipient = recipient,
			protocol = self.protocol,
			type = default.typeSend,
			data = data,
			answer = answer,
			wait = wait,
			waitTime = waitTime,
		}
		
		self:beforeSend(msg)
		
		if not self.timer then self.timer = os.startTimer(10) end
		
		if recipient ~= default.channels.broadcast then
			recipient = self:idAsChannel(recipient)
		end
		
		if self.opened then
			peripheral.call(self.modem, "transmit", recipient, self.channel, msg
			-- needed?
			peripheral.call(self.modem, "transmit", default.channel.repeater, self.channel, msg)
			sent = true
		end

		if wait then
			-- wait for this exact answer
			return self:listenForAnswer(msg, waitTime or default.waitTime)
		else
			-- return the sent message
			return msg
		end
	end
	return nil
end

function NetworkNode:broadcast(data,answer)
	return self:send(default.channels.broadcast,data,answer,false)
end

function receive(protocol, waitTime)
	local timer = nil
	
	if waitTime then
		timer = os.startTimer(waitTime)
		eventFilter = nil
	else
		eventFilter = "modem_message"
	end
	
	while true do
		
		local event, modem, channel, sender, msg, distance = os.pullEvent(eventFilter)
		if event == "modem_message" 
			and ( channel == self.channel or channel == default.channels.broadcast ) 
			and type(msg) == "table" 
			and ( type(msg.recipient) == "number" and msg.recipient
			and ( msg.recipient == self.id or msg.recipient = default.channels.broadcast ) )
			-- and type(msg.type) == "number" and msg.type == msg.type 
			-- just to make sure its a bluenet message
			then
			-- event, side, channel, replyChannel, message, distance
			if protocol == nil or protocol == msg.protocol then
				return sender, msg, distance
			end
		elseif event == "timer" then
			if side == timer then
				return nil
			end
		end
	end
	
end

-- protocol specific

function BlueNet:host(protocol, hostName)
	if hostName == "localhost" then
		error("reserved hostname",2)
	end
	if hostNames[protocol] ~= hostName then
		if
end

--pseudo funcitons to be implemented by enduser
-- function NetworkNode:onReceive(msg) end
-- function NetworkNode:onAnswer(msg,forMsg) end
-- function NetworkNode:onNoAnswer(forMsg) end
-- function NetworkNode:onRequestAnswer(forMsg) end

function NetworkNode:initialize()
	self:openRednet()
	self:lookupHost()
	--self:notifyHost()
	print("myId:", self.id, "host:", self.host, "protocol:", self.protocol)
end
function NetworkNode:openRednet()
	if rednet.isOpen() then
		rednet.close() -- closing not necessary
	end
	peripheral.find("modem",rednet.open)
	assert(rednet.isOpen(),"no modem found")
	self:hostProtocol()	
end
function NetworkNode:notifyHost()
	--notify host that a new worker is available
	--could be replaced by regular lookups through host
	if self.host then
		if self.host >= 0 then
			local answerMsg = self:send(self.host, {"REGISTER"}, true, true)
			assert(answerMsg, "no host found")
		end
	end
end

function NetworkNode:hostProtocol()
	if self.isHost then
		rednet.host(self.protocol, "host")
	else
		rednet.host(self.protocol, tostring(self.id))
	end
	-- node:broadcast or check the dns messages with os.pullEvent
end

function NetworkNode:setProtocol(protocol)
	if self.protocol then
		rednet.unhost(self.protocol)
	end
	self:hostProtocol()
end

function NetworkNode:beforeReceive(sender,msg,senderProtocol)
	--if msg.data[1] == "RUN" then -- from now on, RUN is handled by the receiver
	--	shell.run(msg.data[2])
	--else
	if msg.data[1] == "REBOOT" then
		os.reboot()
	elseif msg.data[1] == "FILE_REQUEST" then
		local fileName = msg.data[2].fileName
		if fs.exists(fileName) then
			print("sending", fileName)
			local file = fs.open(fileName, "r")
			local fileData = file.readAll()
			local data = { "FILE", { fileName = fileName, fileData = fileData } }
			self:send(sender,data,self.protocol)
		else
			self:send(sender, { "FILE_MISSING", { fileName = fileName } })
		end
	elseif msg.data[1] == "FOLDER_REQUEST" then
		local folderName = msg.data[2].folderName
		if fs.exists(folderName) and fs.isDir(folderName) then
			print("sending", folderName)
			local folderData = {}
			for _, fileName in pairs(fs.list('/' .. folderName)) do
				local file = fs.open(folderName.."/"..fileName, "r")
				local fileData = file.readAll()
				file.close()
				table.insert(folderData, { fileName = fileName, fileData = fileData })
			end
			self:send(sender, {"FOLDER", folderData})
		else
			self:send(sender, { "FOLDER_MISSING", { folderName = folderName }})
		end
	end
end

function NetworkNode:generateUUID()
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	return string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end)
end


function NetworkNode:beforeSend(msg)
	-- add original message to waitlist
	if msg.answer then
		self.waitlist:add(msg)
	end
end

function NetworkNode:checkValid(msg,waitTime)
	if (os.epoch("ingame") - msg.time)/(72000) > ( waitTime or msg.waitTime or default.waitTime) then
		return false
	end
	return true
end

function NetworkNode:checkWaitList()
	-- regularly check this list to trigger onNoAnswer events
	local msg = self.waitlist:getLast()
	while msg do
		local prev = self.waitlist:getPrev(msg)
		if not self:checkValid(msg) then
			self.waitlist:remove(msg)
			if self.onNoAnswer then
				self.onNoAnswer(msg)
			end
		end
		msg = prev
	end
end


function NetworkNode:findMessage(uuid)
	-- find original message to answer to
	local msg
	local node = self.waitlist:getFirst()
	while node do
		if node.id == uuid then
			msg = node
			break
		end
		node = self.waitlist:getNext(node)
	end
	return msg
end

function NetworkNode:listenForAnswer(forMsg,waitTime)
	-- ONLY FOR SEQUENTIAL MESSAGING?
	local startTime = os.epoch("ingame")
	local hasAnswer = false
	repeat 
		sender, msg, senderProtocol = rednet.receive(self.protocol,waitTime)
		if msg then 
			if msg.id == forMsg.id then
				self.waitlist:remove(forMsg)
				break
			else
				-- different message
				-- do not handle other messages, it came to the error below
				-- self:handleMessage(sender,msg,senderProtocol)
			end
		else
			self.waitlist:remove(forMsg) -- this could trigger errors if it has already been removed from the list OR because its not the same table as when it was inserted
			if self.onNoAnswer then
				self.onNoAnswer(forMsg)
			end
			break
		end
		waitTime = waitTime - ((os.epoch("ingame")-startTime)/72000)
	until waitTime <= 0
	return msg, forMsg
end

function NetworkNode:listen(waitTime)
	-- listen for anything, not just answers
	local sender, msg, senderProtocol = rednet.receive(self.protocol,waitTime)
	if msg then
		self:handleMessage(sender,msg,senderProtocol)
	else
		self:checkWaitList()
	end
	return msg
end

function NetworkNode:addEvent(event)
	self.events:add(event)
end
function NetworkNode:checkEvents()
	-- check all events, oldest first
	local event = self.events:getPrev()
	while event do
		local prev = self.events:getPrev(event)
		self.events:remove(event)
		self:handleEvent(event)
		event = prev
	end
	self:checkWaitList()
end
function NetworkNode:handleEvent(event)
	if event and event[1] == "rednet_message" then
		--local name, sender, msg, senderProtocol = event
		self:handleMessage(event[2],event[3],event[4])
	end
end


function NetworkNode:handleMessage(sender,msg,senderProtocol)
	if senderProtocol == self.protocol and msg then
		if msg.answer then
			if self.onRequestAnswer then
				--special handler exists
				self.onRequestAnswer(msg)
			else
				self:answer(sender,{"RECEIVED"},msg.id)
			end
		end
		
		if msg.type == default.typeSend then
			self:beforeReceive(sender,msg,senderProtocol)
			if self.onReceive then
				self.onReceive(msg)
			end
		elseif msg.type == default.typeAnswer then
			-- check if the message that requested this answer is outdated
			local original = self:findMessage(msg.id)
			if original then
				if self:checkValid(original) then
					if self.onAnswer then 
						self.onAnswer(msg,original)
					end
				end
				self.waitlist:remove(original)
			else
				-- discard the answer message
			end
		end
	end
end
		


function NetworkNode:getHost()
	return self.host
end

function NetworkNode:lookupHost()
	if self.isHost then 
		self.host = self.id
	else 
		self.host = rednet.lookup(self.protocol,"host") 
	end
	return self.host
end

function NetworkNode:lookup()
	if self.isHost then
		self.host = self.id
	else
		self.host = rednet.lookup(self.protocol,"host")
	end
	self.computers = {rednet.lookup(self.protocol)}
end

function NetworkNode:close()
	rednet.unhost(self.protocol)
	if rednet.isOpen() then
		rednet.close()
	end
end