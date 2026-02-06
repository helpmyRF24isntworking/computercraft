
local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Window = require("classWindow")
local Frame = require("classFrame")
local TaskSelector = require("classTaskSelector")
local TaskList = require("classTaskList")
local MapDisplay = require("classMapDisplay")

local default = {
	colors = {
		background = colors.black,
		border = colors.gray,
		good = colors.green,
		okay = colors.orange,
		bad = colors.red,
		neutral = colors.white,
	},
	width = 50,
	height = 20,
}

local TurtleDetails  = {}
setmetatable(TurtleDetails, { __index = Window })
TurtleDetails.__index = TurtleDetails

function TurtleDetails:new(x,y,turt)
	local o = o or Window:new(x,y,default.width,default.height) or {}
	setmetatable(o,self)
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)
	
	o.turt = turt
	-- o.taskManager = taskManager or nil
	o.mapDisplay = nil -- needed to enable the map button
	o.hostDisplay = nil
	o.win = nil

	
	o:initialize()
	
	return o
end

function TurtleDetails:refreshData()
	-- has to poll turtle data
	local data = self.turt.state
	
	self.data = data
	if data.stuck then
		self.onlineText = "stuck"
		self.onlineColor = default.colors.bad
	elseif data.online then
		self.onlineText = "online"
		self.onlineColor = default.colors.good
	else
		self.onlineText = "offline" 
		self.onlineColor = default.colors.bad
	end
	
	if data.fuelLevel <= 0 then
		self.fuelColor = default.colors.bad
	elseif data.fuelLevel <= 128 then
		self.fuelColor = default.colors.okay
	else self.fuelColor = default.colors.neutral end
end

function TurtleDetails:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		-- only for showing fullscreen map?
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end


function TurtleDetails:addTask()
	self.taskSelector = TaskSelector:new(self.x+19,self.y+2)
	self.taskSelector:setData(self.data)
	self.taskSelector:setHostDisplay(self.hostDisplay)
	self:addObject(self.taskSelector)
	self:redraw()
	return true
end

function TurtleDetails:cancelTask()
	global.taskManager:cancelCurrentTurtleTask(self.data.id)
end

function TurtleDetails:openMap()
	if self.hostDisplay and self.mapDisplay then
		self.mapDisplay:setFocus(self.data.id)
		self.hostDisplay:displayMap()
	end
end

function TurtleDetails:callHome()
	local task = global.taskManager:callTurtleHome(self.data.id)
end

local taskListY = 15
local mapX = 37
function TurtleDetails:onResize() -- super override
	Window.onResize(self) -- super
	
	
	self.winMap:setSize(self.width - mapX, math.min(10, self.height - 4))
	self.taskList:setSize(self.width-2, self.height - taskListY)
	self.winInfo:setSize(self.width - 2, self.taskList.y - 2)

end

function TurtleDetails:initializeMiniMap()
	-- could also use main mapDisplay but this is cleaner
	self.winMap = MapDisplay:new(mapX, 2, self.width - mapX, math.min(10, self.height - 4))
	self.winMap:setMap(global.map)
	self.winMap:setFocus(self.data.id)
	self.winMap:hideControls()
	self.winMap.handleClick = function(x,y) self:openMap() end
	self:addObject(self.winMap)
end


local function getTaskString(data)
	return ( data.lastTask or "no task" ) .. ( data.task and ( " : " .. data.task) or "" )
end

function TurtleDetails:initialize()

	self:refreshData()

	self.taskList = TaskList:new(2, taskListY, self.width-2, self.height - taskListY, global.taskManager)
	self.taskList:setFilter({ turtleIds = { self.data.id } })
	
	self.winInfo = BasicWindow:new(2,2,self.width-2,self.taskList.y - 2)
	local winInfo = self.winInfo
	local data = self.data


	winInfo.lblId = Label:new("Turtle  " .. data.id .. " - " .. data.label,3,1)
	-- row 1 - 16
	local x, y = 3,3
	winInfo.lblX = Label:new("X  " .. data.pos.x,x,y)
	winInfo.lblY = Label:new("Y  " .. data.pos.y,x,y+1)
	winInfo.lblZ = Label:new("Z  " .. data.pos.z,x,y+2)
	
	-- row 17 - 27
	-- winInfo.lblProgress = Label:new("",29,2)
	local x, y = 3,9
	local strTask = getTaskString(data)
	winInfo.lblOnline = Label:new(self.onlineText,x,y+1,self.onlineColor)
	winInfo.lblTime = Label:new("00:00.00", x+10,y+1)
	winInfo.lblTask = Label:new(strTask,x,y)

	local x, y = 3 ,7
	winInfo.btnCallHome = Button:new("home",x, y,6,1)
	winInfo.btnAddTask = Button:new("add task",x + 7,y,10,1, colors.purple)
	winInfo.btnCancelTask = Button:new("cancel",x + 18, y,6,1)
	winInfo.btnDeleteTurtle = Button:new("delete turtle",x,y,13,1)
	-- row 28 - 
	local x, y = 14, 3
	winInfo.lblFuel = Label:new(      "fuel   " .. data.fuelLevel,x+7,y)
	winInfo.lblEmptySlots = Label:new("slots  " .. data.emptySlots,x+7,y+1)
	winInfo.btnDump = Button:new("dump",x,y+1,6,1)
	winInfo.btnRefuel = Button:new("refuel", x,y,6,1)
	
	winInfo.btnDump.click = function() 
		local dropAll = true
		local task = global.taskManager:addTaskToTurtle(data.id, "dumpBadItems", {dropAll})
	end
	winInfo.btnAddTask.click = function() return self:addTask() end
	winInfo.btnCancelTask.click = function() self:cancelTask() end
	winInfo.btnCallHome.click = function() self:callHome() end
	winInfo.btnDeleteTurtle.click = function() return self:deleteTurtle() end
	
	winInfo:addObject(winInfo.lblId)
	winInfo:addObject(winInfo.lblX)
	winInfo:addObject(winInfo.lblY)
	winInfo:addObject(winInfo.lblZ)
	winInfo:addObject(winInfo.lblTask)
	winInfo:addObject(winInfo.lblFuel)
	winInfo:addObject(winInfo.lblTime)
	winInfo:addObject(winInfo.lblOnline)
	winInfo:addObject(winInfo.lblEmptySlots)

	winInfo:addObject(winInfo.btnAddTask)
	winInfo:addObject(winInfo.btnCancelTask)
	winInfo:addObject(winInfo.btnCallHome)
	winInfo:addObject(winInfo.btnDeleteTurtle)
	winInfo:addObject(winInfo.btnDump)
	winInfo:addObject(winInfo.btnRefuel)

	self:addObject(self.taskList)
	self:addObject(winInfo)
	self:initializeMiniMap()
	
	winInfo.btnDeleteTurtle.visible = not data.online
end

function TurtleDetails:refreshPos()
	local pos = self.data.pos
	local winInfo = self.winInfo
	winInfo.lblX:setText("X  " .. pos.x)
	winInfo.lblY:setText("Y  " .. pos.y)
	winInfo.lblZ:setText("Z  " .. pos.z)
end

function TurtleDetails:refresh()
	
	self:refreshData()
	self:refreshPos()
	local winInfo = self.winInfo
	local data = self.data

	local strTask = getTaskString(data)
	winInfo.lblTask:setText(strTask)
	winInfo.lblFuel:setText(      "fuel   " .. data.fuelLevel)
	winInfo.lblEmptySlots:setText("slots  " .. data.emptySlots.."/16")

	local seconds = math.floor(data.timeDiff/72000)%60
	local minutes = math.floor(data.timeDiff/72000/60)
	local ticks = math.floor((data.timeDiff % 72000)/3600/20*100)
	local lastSeen = string.format("%02d:%02d.%02d",minutes,seconds,ticks)
	winInfo.lblTime:setText(lastSeen)
	winInfo.lblOnline:setText(self.onlineText)
	winInfo.lblOnline:setTextColor(self.onlineColor)

	winInfo.btnAddTask:setEnabled(data.online)
	winInfo.btnCancelTask:setEnabled(data.online)
	winInfo.btnCallHome:setEnabled(data.online)

	winInfo.btnAddTask.visible = data.online
	winInfo.btnCancelTask.visible = data.online
	winInfo.btnCallHome.visible = data.online
	winInfo.btnDeleteTurtle.visible = not data.online

	self.taskList:refresh()
	self.winMap:refresh()

end

function TurtleDetails:deleteTurtle()
	-- TODO: shutdown and remove turtle from global.turtles
	if self.hostDisplay then
		self.hostDisplay:deleteTurtle(self.data.id)
	end
	return true
end

return TurtleDetails