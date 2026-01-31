
local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Frame = require("classFrame")
local TaskSelector = require("classTaskSelector")

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
	height = 7,
}

local TaskGroupControl = BasicWindow:new()

function TaskGroupControl:new(x,y,taskGroup,node,taskGroups)
	local o = o or BasicWindow:new(x,y,default.width,default.height) or {}
	setmetatable(o,self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)
	
	o.node = node or nil 
	o.taskGroup = taskGroup or nil
	o.mapDisplay = nil -- needed to enable the map button
	o.hostDisplay = nil
	o.taskGroups = taskGroups
	o:initialize()
	
	o:setTaskGroup(taskGroup)
	
	return o
end

function TaskGroupControl:setNode(node)
	self.node = node
end

function TaskGroupControl:setTaskGroup(taskGroup)
	if taskGroup then
		self.taskGroup = taskGroup
		local activeCount = self.taskGroup:getActiveTurtles()
		self.active = (activeCount ~= 0)
	
	else
		--pseudo data
		self.taskGroup = {}
		self.taskGroup.id = "no data"
		self.taskGroup.taskName = "no task"
		self.taskGroup.groupSize = 0
		self.taskgroup.startTime = os.epoch("ingame")
		self.active = false
	end
	if self.active then
		self.statusText = "active"
		self.statusColor = default.colors.good
	else
		self.statusText = "done"
		self.statusColor = default.colors.okay
	end
end
function TaskGroupControl:setTaskGroups(taskGroups)
	self.taskGroups = taskGroups
end

function TaskGroupControl:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end

-- function TurtleControl:addTask()
	-- self.taskSelector = TaskSelector:new(self.x+19,self.y-1)
	-- self.taskSelector:setNode(self.node)
	-- self.taskSelector:setData(self.data)
	-- self.taskSelector:setHostDisplay(self.hostDisplay)
	-- self.parent:addObject(self.taskSelector)
	-- self.parent:redraw()
	-- return true
-- end

function TaskGroupControl:cancelTask()
	-- cancel all running tasks of the turtles
	local assignments = self.taskGroup:getAssignments()
	if assignments then 
		for _,assignment in ipairs(assignments) do
			if self.node then
				self.node:send(assignment.turtleId, {"STOP"})
			end
		end
	end
end

function TaskGroupControl:openMap()
	-- open map and set focus to middle of area
	
	-- todo: draw area
	if self.hostDisplay and self.mapDisplay then
		local area = self.taskGroup.area
		
		minX = math.min(area.start.x, area.finish.x)
		minY = math.min(area.start.y, area.finish.y)
		minZ = math.min(area.start.z, area.finish.z)
		maxX = math.max(area.start.x, area.finish.x)
		maxY = math.max(area.start.y, area.finish.y)
		maxZ = math.max(area.start.z, area.finish.z)
		
		start = vector.new(minX, minY, minZ)
		finish = vector.new(maxX, maxY, maxZ)
		
		diff = finish - start
		focus = vector.new(minX + math.floor(diff.x/2), maxY, minZ + math.floor(diff.z/2))
		
		self.mapDisplay:setMid(focus.x, focus.y, focus.z)
		self.hostDisplay:displayMap()
	end
end

function TaskGroupControl:callHome()
	local assignments = self.taskGroup:getAssignments()
	if assignments then 
		for _,assignment in ipairs(assignments) do
			if self.node then
				self.node:send(assignment.turtleId, {"DO", "returnHome"})
			end
		end
	end
end

function TaskGroupControl:onResize() -- super override
	BasicWindow.onResize(self) -- super
	
	self.frmId:setWidth(self.width)
end

function TaskGroupControl:redraw() -- super override
	self:refresh()
	
	BasicWindow.redraw(self) -- super
	
	for i=3,5 do
		self:setCursorPos(19,i)
		self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
	end
	for i=3,5 do
		self:setCursorPos(28,i)
		self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
	end
end

function TaskGroupControl:initialize()
	
	self.frmId = Frame:new(string.sub(self.taskGroup.id,1,4),1,1,self.width,self.height,self.borderColor)
	
	-- row 1 - 16
	self.lblXStart = Label:new("X  " .. self.taskGroup.area.start.x,3,3)
	self.lblYStart = Label:new("Y  " .. self.taskGroup.area.start.y,3,4)
	self.lblZStart = Label:new("Z  " .. self.taskGroup.area.start.z,3,5)
	
	self.lblXFinish = Label:new(self.taskGroup.area.finish.x,13,3)
	self.lblYFinish = Label:new(self.taskGroup.area.finish.y,13,4)
	self.lblZFinish = Label:new(self.taskGroup.area.finish.z,13,5)
	
	
	-- row 17 - 27
	self.btnMap = Button:new("map",21,3,6,1)
	self.btnCallHome = Button:new("home",21,4,6,1)
	
	self.btnCancelTask = Button:new("cancel",21,5,6,1)
	self.btnDeleteGroup = Button:new("delete", 21,5,6,1)
	
	self.lblTask = Label:new(self.taskGroup.taskName,30,3)
	self.lblProgress = Label:new("",30,5)
	self.lblActiveTurtles = Label:new("0/"..self.taskGroup.groupSize,41,4)
	self.lblStatus = Label:new(self.statusText,30,4,self.statusColor)
	self.lblTime = Label:new("00:00.00", 41,5)
	
	self.btnMap.click = function() self:openMap() end
	self.btnCancelTask.click = function() self:cancelTask() end
	self.btnCallHome.click = function() self:callHome() end
	self.btnDeleteGroup.click = function() return self:deleteGroup() end
	
	self:addObject(self.frmId)
	
	self:addObject(self.lblXStart)
	self:addObject(self.lblYStart)
	self:addObject(self.lblZStart)
	self:addObject(self.lblXFinish)
	self:addObject(self.lblYFinish)
	self:addObject(self.lblZFinish)
	self:addObject(self.lblTask)
	self:addObject(self.lblTime)
	self:addObject(self.lblStatus)
	self:addObject(self.lblActiveTurtles)
	self:addObject(self.lblProgress)
	
	self:addObject(self.btnMap)
	self:addObject(self.btnCancelTask)
	self:addObject(self.btnCallHome)
	self:addObject(self.btnDeleteGroup)
	
	self.btnDeleteGroup.visible = false
end

function TaskGroupControl:refreshPos()
	self.lblXStart:setText("X  " .. self.taskGroup.area.start.x)
	self.lblYStart:setText("Y  " .. self.taskGroup.area.start.y)
	self.lblZStart:setText("Z  " .. self.taskGroup.area.start.z)
	self.lblXFinish:setText(self.taskGroup.area.finish.x)
	self.lblYFinish:setText(self.taskGroup.area.finish.y)
	self.lblZFinish:setText(self.taskGroup.area.finish.z)
end

function TaskGroupControl:refresh()
	self:refreshPos()
	
	self.lblTask:setText(self.taskGroup.taskName or "no task")
	
	local activeCount = self.taskGroup:getActiveTurtles()
	self.active = (activeCount ~= 0)
	if self.active then
		self.statusText = "active"
		self.statusColor = default.colors.good
	else
		self.statusText = "done"
		self.statusColor = default.colors.okay
	end
	
	self.lblStatus:setText(self.statusText)
	self.lblStatus:setTextColor(self.statusColor)
	self.lblActiveTurtles:setText(activeCount.."/"..self.taskGroup.groupSize)

	local progress = self.taskGroup:getProgress()
	local progressText = (progress and string.format("%3d%%", math.floor(progress * 100))) or ""
	self.lblProgress:setText(progressText)
	
	local timeDiff = os.epoch("ingame") - self.taskGroup.startTime
	-- 1 tick = 3600 ms
	-- 1 day = 24000 ticks
	-- 1 real second = 72000 ms
	local seconds = math.floor(timeDiff/72000)%60
	local minutes = math.floor(timeDiff/72000/60)
	local ticks = math.floor((timeDiff % 72000)/3600/20*100)
	local uptime = string.format("%02d:%02d.%02d",minutes,seconds,ticks)
	self.lblTime:setText(uptime)
	
	self.btnCancelTask:setEnabled(self.active)
	
	self.btnCancelTask.visible = self.active
	self.btnDeleteGroup.visible = not self.active
end

function TaskGroupControl:deleteGroup()
	if self.hostDisplay then
		self.hostDisplay:deleteGroup(self.taskGroup.id)
	end
	return true
end

return TaskGroupControl