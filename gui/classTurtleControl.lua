
local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Frame = require("classFrame")
local TaskSelector = require("classTaskSelector")
local TurtleDetails = require("classTurtleDetails")


local default = {
	colors = {
		background = colors.black,
		border = colors.gray,
		good = colors.green,
		okay = colors.orange,
		bad = colors.red,
		neutral = colors.white,
	},
	expanded = {
		width = 50,
		height = 7,
	},
	collapsed = {
		width = 50,
		height = 1,
	},
}

local TurtleControl = BasicWindow:new()

function TurtleControl:new(x,y,turt,node)
	local o = o or BasicWindow:new(x,y,default.collapsed.width,default.collapsed.height) or {}
	setmetatable(o,self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)
	
	o.node = node or nil 
	o.turt = turt or nil
	o.mapDisplay = nil -- needed to enable the map button
	o.hostDisplay = nil
	o.collapsed = true
	o.win = nil

	o:initialize()

	return o
end

function TurtleControl:setTurt(turt)
	self.turt = turt
end

function TurtleControl:setNode(node)
	self.node = node
end

function TurtleControl:refreshData()
	local data = self.turt and self.turt.state or nil
	if data then
		self.data = data
		
		if self.data.stuck then
			self.onlineText = "stuck"
			self.onlineColor = default.colors.bad
		elseif self.data.online then
			self.onlineText = "online"
			self.onlineColor = default.colors.good
		else
			self.onlineText = "offline" 
			self.onlineColor = default.colors.bad
		end
		
		if self.data.fuelLevel <= 0 then
			self.fuelColor = default.colors.bad
		elseif self.data.fuelLevel <= 128 then
			self.fuelColor = default.colors.okay
		else self.fuelColor = default.colors.neutral end
		
		self.data.pos = vector.new(self.data.pos.x, self.data.pos.y, self.data.pos.z)
		-- self:refresh()
		
	else
		--pseudo data
		self.data = {}
		self.data.id = "no data"
		self.data.label = ""
		self.data.pos = vector.new(0,0,0)
		self.data.taskLast = "no task"
		self.data.task = "no task"
		self.data.fuelLevel = 123
		self.data.online = false
		self.data.time = 283473834
		self.onlineText = "offline"
	end
end
function TurtleControl:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end
function TurtleControl:collapse()
	if not self.collapsed then
		self.collapsed = true
		self:removeObject(self.win)
		self:addObject(self.winSimple)
		self.win = self.winSimple
		self:setHeight(default.collapsed.height)
		--self.monitor:redraw()
	end
	return true
end
function TurtleControl:expand()
	if self.collapsed then 
		self.collapsed = false
		self:removeObject(self.win)
		self:addObject(self.winDetail)
		self.win = self.winDetail
		self:setHeight(default.expanded.height)
		--self.monitor:redraw()
	end
	return true
end

function TurtleControl:openDetails()
	-- open a new window with more details and options for the turtle
	-- for fullscreen add to hostDisplay instead of parent
	self.hostDisplay:openTurtleDetails(self.turt)
	return true
end

function TurtleControl:addTask()
	self.taskSelector = TaskSelector:new(self.x+19,self.y-1)
	self.taskSelector:setNode(self.node)
	self.taskSelector:setData(self.data)
	self.taskSelector:setHostDisplay(self.hostDisplay)
	self.parent:addObject(self.taskSelector)
	self.parent:redraw()
	return true
	
end
function TurtleControl:cancelTask()
	global.taskManager:cancelCurrentTurtleTask(self.data.id)
end

function TurtleControl:openMap()
	if self.hostDisplay and self.mapDisplay then
		self.mapDisplay:setFocus(self.data.id)
		self.hostDisplay:displayMap()
	end
end

function TurtleControl:callHome()
	local task = global.taskManager:callTurtleHome(self.data.id) -- abstraction?
	-- assignment to return home? yes but can be handled by the manager
end

function TurtleControl:onResize() -- super override
	BasicWindow.onResize(self) -- super
	
	self.win:fillParent()
	self.frmId:setWidth(self.width)
	self.frmId:setHeight(self.height)
	
end

function TurtleControl:redraw() -- super override
	self:refresh()
	
	BasicWindow.redraw(self) -- super
	
	if not self.collapsed then
		for i=3,5 do
			self:setCursorPos(18,i)
			self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
		end
		for i=3,5 do
			self:setCursorPos(34,i)
			self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
		end
	end
end

function TurtleControl:initialize()
	self:refreshData()
	
	self.winDetail = BasicWindow:new()
	self.winSimple = BasicWindow:new()
	
	if self.collapsed then
		self:addObject(self.winSimple)
		self.win = self.winSimple
	else 
		self:addObject(self.winDetail)
		self.win = self.winDetail
	end
	self.win:fillParent()
	
	-- simple
	self.btnExpand = Button:new("+",1,1,3,1)
	self.winSimple.lblId = Label:new(self.data.id .. " - " .. self.data.label,5,1)
	self.winSimple.lblTask = Label:new(self.data.lastTask,20,1)
	self.winSimple.lblOnline = Label:new(self.onlineText,36,1,self.onlineColor)
	
	self.btnExpand.click = function() return self:expand() end
	
	self.winSimple:addObject(self.btnExpand)
	self.winSimple:addObject(self.winSimple.lblId)
	self.winSimple:addObject(self.winSimple.lblTask)
	self.winSimple:addObject(self.winSimple.lblOnline)
	
	--self.winSimple.lblPosition = Label:new(self.data.pos,30,1)
	
	local data = self.data
	-- detail
	self.frmId = Frame:new(data.id .. " - " .. data.label ,1,1,self.width,self.height,self.borderColor)
	self.btnCollapse = Button:new("-",1,1,3,1)
	-- row 1 - 16
	self.lblX = Label:new("X  " .. data.pos.x,3,3)
	self.lblY = Label:new("Y  " .. data.pos.y,3,4)
	self.lblZ = Label:new("Z  " .. data.pos.z,3,5)
	self.btnMap = Button:new("map",12,3,5,1)
	-- self.btnCallHome = Button:new("home",12,5,5,1)
	self.btnDetails = Button:new("more", 12,5,5,1)
	-- row 17 - 27
	self.lblProgress = Label:new("",29,2)
	self.lblTaskLast = Label:new(data.lastTask,20,3)
	self.lblTask = Label:new(data.task,20,4)
	self.btnAddTask = Button:new("add",20,5,6,1, colors.purple)
	self.btnCancelTask = Button:new("cancel",27,5,6,1)
	self.btnDeleteTurtle = Button:new("delete turtle",20,5,13,1)
	-- row 28 - 
	self.lblFuel = Label:new(      "fuel      " .. data.fuelLevel,36,3)
	self.lblEmptySlots = Label:new("slots     " .. data.emptySlots,36,4)
	self.lblOnline = Label:new(self.onlineText,36,5,self.onlineColor)
	self.lblTime = Label:new("00:00.00", 46,5)
	
	self.btnAddTask.click = function() return self:addTask() end
	self.btnMap.click = function() self:openMap() end
	self.btnCancelTask.click = function() self:cancelTask() end
	--self.btnCallHome.click = function() self:callHome() end
	self.btnDeleteTurtle.click = function() return self:deleteTurtle() end
	self.btnCollapse.click = function() return self:collapse() end
	self.btnDetails.click = function() return self:openDetails() end
	
	self.winDetail:addObject(self.frmId)
	self.winDetail:addObject(self.lblX)
	self.winDetail:addObject(self.lblY)
	self.winDetail:addObject(self.lblZ)
	self.winDetail:addObject(self.lblTaskLast)
	self.winDetail:addObject(self.lblTask)
	self.winDetail:addObject(self.lblFuel)
	self.winDetail:addObject(self.lblTime)
	self.winDetail:addObject(self.lblOnline)
	self.winDetail:addObject(self.lblEmptySlots)
	self.winDetail:addObject(self.lblProgress)

	self.winDetail:addObject(self.btnCollapse)
	self.winDetail:addObject(self.btnAddTask)
	self.winDetail:addObject(self.btnMap)
	self.winDetail:addObject(self.btnCancelTask)
	--self.winDetail:addObject(self.btnCallHome)
	self.winDetail:addObject(self.btnDeleteTurtle)
	self.winDetail:addObject(self.btnDetails)
	
	self.btnDeleteTurtle.visible = self.data.online

end

function TurtleControl:refreshPos()
	local pos = self.data.pos
	self.lblX:setText("X  " .. pos.x)
	self.lblY:setText("Y  " .. pos.y)
	self.lblZ:setText("Z  " .. pos.z)
end

function TurtleControl:refresh()
	self:refreshData()
	self:refreshPos()

	local data = self.data
	if self.collapsed then
		--self.winSimple.lblId:setText(self.data.id .. " - " .. self.data.label)
		self.winSimple.lblTask:setText(data.lastTask or "no task")
		self.winSimple.lblOnline:setText(self.onlineText)
		self.winSimple.lblOnline:setTextColor(self.onlineColor)
	else
		self.lblTaskLast:setText(data.lastTask or "no task")
		self.lblTask:setText(data.task)

		self.lblFuel:setTextColor(self.fuelColor)
		self.lblFuel:setText("fuel      " .. data.fuelLevel)
		self.lblEmptySlots:setText("slots     " .. data.emptySlots.."/16")
		local progressText = ( data.progress and string.format("%3d%%", math.floor((data.progress) * 100)) ) or ""
		self.lblProgress:setText(progressText)

		-- 1 tick = 3600 ms
		-- 1 day = 24000 ticks
		-- 1 real second = 72000 ms
		local seconds = math.floor(data.timeDiff/72000)%60
		local minutes = math.floor(data.timeDiff/72000/60)
		local ticks = math.floor((data.timeDiff % 72000)/3600/20*100)
		local lastSeen = string.format("%02d:%02d.%02d",minutes,seconds,ticks)
		self.lblTime:setText(lastSeen)
		self.lblOnline:setText(self.onlineText)
		
		self.lblOnline:setTextColor(self.onlineColor)
		
		
		self.btnAddTask:setEnabled(data.online)
		self.btnCancelTask:setEnabled(data.online)
		--self.btnCallHome:setEnabled(data.online)
		
		self.btnAddTask.visible = data.online
		self.btnCancelTask.visible = data.online
		self.btnDeleteTurtle.visible = not data.online
		self.lblProgress.visible = data.online
	end
end

function TurtleControl:deleteTurtle()
	-- TODO: shutdown and remove turtle from global.turtles
	if self.hostDisplay then
		self.hostDisplay:deleteTurtle(self.data.id)
	end
	return true
end

return TurtleControl