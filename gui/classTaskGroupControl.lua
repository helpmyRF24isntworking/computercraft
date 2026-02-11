
local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Frame = require("classFrame")
local TaskSelector = require("classTaskSelector")
local ChoiceSelector = require("classChoiceSelector")
local GroupDetails = require("classTaskGroupDetails")

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

function TaskGroupControl:new(x,y,taskGroup)
	local o = o or BasicWindow:new(x,y,default.width,default.height) or {}
	setmetatable(o,self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)

	o.taskGroup = taskGroup or nil
	o.mapDisplay = nil -- needed to enable the map button
	o.hostDisplay = nil
	o:initialize()
	
	o:setTaskGroup(taskGroup)
	
	return o
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
		self.taskGroup.started = os.epoch("ingame")
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
	self.taskGroup:cancel()
end

function TaskGroupControl:openMap()
	-- open map and set focus to middle of area
	if self.hostDisplay and self.mapDisplay then
		local start, finish, focus = self.taskGroup:getAreaDetails()
		if not start then return end
		table.insert(self.mapDisplay.areas, {start = start, finish = finish, color = self.taskGroup:getStatusColor()})
		self.mapDisplay:setMid(focus.x, focus.y, focus.z)
		self.hostDisplay:displayMap()
	end
end

function TaskGroupControl:openDetails()
	-- open a new window with more details and options for the turtle
	-- for fullscreen add to hostDisplay instead of parent
	self.hostDisplay:openGroupDetails(self.taskGroup)
	return true
end

function TaskGroupControl:openOptions()
	local choices = { "call home", "reboot" }
	if self.taskGroup:isResumable() then 
		table.insert(choices,1,"resume task")
	end
	local active = self.taskGroup:isActive()
	if active then 
		table.insert(choices, "cancel task")
	else
		table.insert(choices, "delete group")
	end
	
	local choiceSelector = ChoiceSelector:new(self.x + self.btnOptions.x - 1, self.y + self.btnOptions.y-5, 16, 6, choices)
	choiceSelector.onChoiceSelected = function(choice)
		if choice == "call home" then
			self:callHome()
		elseif choice == "reboot" then
			self.taskGroup:reboot()
		elseif choice == "resume task" then
			self.taskGroup:resume()
		elseif choice == "cancel task" then
			self.taskGroup:cancel()
		elseif choice == "delete group" then
			self:deleteGroup()
		end
	end
	
	self.parent:addObject(choiceSelector)
	self.parent:redraw()
	return true
end
function TaskGroupControl:callHome()
	self.taskGroup:addTaskToTurtles("returnHome",{})
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
	
	local group = self.taskGroup
	local area = group:getArea() or { start = {x=0,y=0,z=0}, finish = {x=0,y=0,z=0} }
	-- row 1 - 16
	self.lblXStart = Label:new("X  " .. area.start.x,3,3)
	self.lblYStart = Label:new("Y  " .. area.start.y,3,4)
	self.lblZStart = Label:new("Z  " .. area.start.z,3,5)
	
	self.lblXFinish = Label:new(area.finish.x,13,3)
	self.lblYFinish = Label:new(area.finish.y,13,4)
	self.lblZFinish = Label:new(area.finish.z,13,5)
	
	
	-- row 17 - 27
	self.btnMap = Button:new("map",21,3,6,1)
	self.btnOptions = Button:new("opts", 21,4,6,1)
	
	--self.btnCancelTask = Button:new("cancel",21,5,6,1)
	--self.btnDeleteGroup = Button:new("delete", 21,5,6,1)
	self.btnDetails = Button:new("detail", 21,5,6,1)
	
	self.lblTask = Label:new(group.taskName,30,3)
	self.lblProgress = Label:new("",30,5)
	self.lblActiveTurtles = Label:new("0/".. group.groupSize,41,4)
	self.lblStatus = Label:new(self.statusText,30,4,self.statusColor)
	self.lblTime = Label:new("00:00.00", 41,5)
	
	self.btnMap.click = function() self:openMap() end
	--self.btnCancelTask.click = function() self:cancelTask() end
	--self.btnDeleteGroup.click = function() return self:deleteGroup() end
	
	self.btnOptions.click = function() return self:openOptions() end
	self.btnDetails.click = function() return self:openDetails() end

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
	--self:addObject(self.btnCancelTask)
	self:addObject(self.btnOptions)
	--self:addObject(self.btnDeleteGroup)
	self:addObject(self.btnDetails)
	--self.btnDeleteGroup.visible = false
end

function TaskGroupControl:refreshPos()

	local area = self.taskGroup:getArea() or { start = {x=0,y=0,z=0}, finish = {x=0,y=0,z=0} }
	local start, finish = area.start, area.finish

	self.lblXStart:setText("X  " .. start.x)
	self.lblYStart:setText("Y  " .. start.y)
	self.lblZStart:setText("Z  " .. start.z)
	self.lblXFinish:setText(finish.x)
	self.lblYFinish:setText(finish.y)
	self.lblZFinish:setText(finish.z)
end

function TaskGroupControl:refresh()
	self:refreshPos()
	
	local group = self.taskGroup
	self.lblTask:setText(group.taskName or "no task")
	
	local status = group:getStatus()
	local activeCount = group:getActiveTurtles()
	local active = group:isActive()

	self.lblStatus:setText(status)
	self.lblStatus:setTextColor(group:getStatusColor())
	self.lblActiveTurtles:setText(activeCount.."/"..group.groupSize)
	self.lblProgress:setText(group:getProgressText())
	
	self.lblTime:setText(group:getUptimeText())
	
	--self.btnCancelTask:setEnabled(active)
	
	--self.btnCancelTask.visible = active
	--self.btnDeleteGroup.visible = not active
end

function TaskGroupControl:deleteGroup()
	if self.taskGroup then 
		self.taskGroup:delete()
	end
	if self.hostDisplay then
		self.hostDisplay:deleteGroup(self.taskGroup.id)
	end
	return true
end

return TaskGroupControl