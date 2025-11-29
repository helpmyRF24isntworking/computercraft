local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")
local Frame = require("classFrame")
require("classTaskGroup")

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

	yLevel =  {
		top = 60,
		bottom = -58,
	}
}

local TaskGroupSelector = Window:new()

function TaskGroupSelector:new(x,y,turtles,node,taskGroups)
	local o = o or Window:new(x,y,width or default.width ,height or default.height ) or {}
	setmetatable(o, self)
	self.__index = self
	
	o.backgroundColor = default.colors.background
	o.borderColor = default.colors.border
	
	o.turtles = turtles or nil
	o.node = node or nil
	o.mapDisplay = nil 
	o.positions = {}
	o.taskGroup = nil
	o.taskGroups = taskGroups
	
	o.taskName = "mineArea"
	
	o:initialize()
	return o
end

function TaskGroupSelector:onResize() -- super overwrite
	Window.onResize(self) -- super
	self.frm:setWidth(self.width)
	self.frm:setHeight(self.height)
end
function TaskGroupSelector:initialize()
	
	self.taskGroup = TaskGroup:new(self.turtles)
	
	self.frm = Frame:new("new group - "..string.sub(self.taskGroup.id,1,4), 1,1,self.width,self.height,default.borderColor)
	
	self.lblGroupSizeTxt = Label:new("group size", 3,3)
	self.btnDecreaseSize = Button:new("-",19,3,1,1)
	self.lblGroupSize = Label:new(self.taskGroup.groupSize,21,3)
	self.btnIncreaseSize = Button:new("+",23,3,1,1)
	
	self.btnIncreaseSize.click = function() self:changeGroupSize(1) end
	self.btnDecreaseSize.click = function() self:changeGroupSize(-1) end
	
	self.btnSelectArea = Button:new("select area", 5,11,13,1)
	self.btnSelectArea.click = function() self:selectArea() end
	
	self.lblAreaStart = Label:new("start  ",3,13)
	self.lblAreaEnd = Label:new("end    ", 3, 14)

	self.lblXStart = Label:new("X  " .. "-",3,6)
	self.lblYStart = Label:new("Y  " .. "-",3,7)
	self.lblZStart = Label:new("Z  " .. "-",3,8)
	
	self.lblXFinish = Label:new("-",13,6)
	self.lblYFinish = Label:new("-",13,7)
	self.lblZFinish = Label:new("-",13,8)
	
	
	self.btnFromTop = Button:new("top",5,9,6,1 )
	self.btnToBottom = Button:new("bottom", 12,9,6,1)
	self.btnFromTop.click = function() self:setFromTop() end
	self.btnToBottom.click = function() self:setToBottom() end
	
	self.btnSplitArea = Button:new("split area", 3,19,14)
	self.btnSplitArea.click = function() self:splitArea() end
	
	self.btnStartTasks = Button:new("start", 41,9,8,1)
	self.btnStartTasks.click = function() self:startTasks() end
	self.btnStartTasks:setEnabled(false)
	
	self:removeObject(self.btnClose)
	self:addObject(self.frm)
	self:addObject(self.btnClose)
	
	
	self:addObject(self.lblXStart)
	self:addObject(self.lblYStart)
	self:addObject(self.lblZStart)
	self:addObject(self.lblXFinish)
	self:addObject(self.lblYFinish)
	self:addObject(self.lblZFinish)
	
	self:addObject(self.lblGroupSizeTxt)
	self:addObject(self.lblGroupSize)
	self:addObject(self.lblAreaStart)
	self:addObject(self.lblAreaEnd)
	
	self:addObject(self.btnIncreaseSize)
	self:addObject(self.btnDecreaseSize)
	self:addObject(self.btnSelectArea)
	self:addObject(self.btnSplitArea)
	self:addObject(self.btnStartTasks)
	self:addObject(self.btnFromTop)
	self:addObject(self.btnToBottom)
end

function TaskGroupSelector:getTaskGroup()
	return self.taskGroup
end

function TaskGroupSelector:changeGroupSize(increment)
	self.taskGroup:setGroupSize(self.taskGroup.groupSize+increment)
	--self.taskGroup:forceGroupSize(self.taskGroup.groupSize+increment)
	self:refresh()
	self.lblGroupSize:redraw()
end

function TaskGroupSelector:refreshPos()
	if self.positions and self.positions[1] then
		self.lblAreaStart:setText("start  "..self.positions[1].x.." "..self.positions[1].y.." "..self.positions[1].z )
		self.lblXStart:setText("X  " .. self.positions[1].x)
		self.lblYStart:setText("Y  " .. self.positions[1].y)
		self.lblZStart:setText("Z  " .. self.positions[1].z)
	end
	if self.positions and self.positions[2] then
		self.lblAreaEnd:setText("end    "..self.positions[2].x.." "..self.positions[2].y.." "..self.positions[2].z )
		self.lblXFinish:setText(self.positions[2].x)
		self.lblYFinish:setText(self.positions[2].y)
		self.lblZFinish:setText(self.positions[2].z)
	end
end
function TaskGroupSelector:refresh()
	self.lblGroupSize:setText(self.taskGroup.groupSize)
	self:refreshPos()
	if self.positions and #self.positions == 2 then
		self.btnStartTasks:setEnabled(true)
	else
		self.btnStartTasks:setEnabled(false)
	end
end

function TaskGroupSelector:splitArea()
	if #self.positions == 2 then
		self.taskGroup:setArea(self.positions[1], self.positions[2])
		self.taskGroup:splitArea()		
	end
end

function TaskGroupSelector:setFromTop()
	if self.positions and self.positions[1] then
		self.positions[1].y = default.yLevel.top
		self:refresh()
	end
	
end
function TaskGroupSelector:setToBottom()
	if self.positions and self.positions[2] then
		self.positions[2].y = default.yLevel.bottom
		self:refresh()
	end
end

function TaskGroupSelector:startTasks()
	if self.node then 
		self:splitArea()
		self.taskGroup.taskName = self.taskName
		for _,assignment in ipairs(self.taskGroup:getAssignments()) do
			self.node:send(assignment.turtleId, {
					"DO", self.taskName, 
				{assignment.area.start ,assignment.area.finish}}) 
		end
		self:close()
	end
	self:addToGlobal()
end

function TaskGroupSelector:addToGlobal()
	self.taskGroups[self.taskGroup.id] = self.taskGroup
	global.saveGroups()
end

--- RANDOM

function TaskGroupSelector:setNode(node)
	self.node = node
end
function TaskGroupSelector:setTurtles(turtles)
	self.turtles = turtles
	self.taskGroup:setTurtles(turtles)
end

function TaskGroupSelector:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end
function TaskGroupSelector:openMap()
	if self.hostDisplay and self.mapDisplay then
		self.hostDisplay:displayMap()
	end
end

function TaskGroupSelector:selectPosition()
	self.position = nil
	self.mapDisplay.onPositionSelected = function(objRef,x,y,z) self:onPositionSelected(x,y,z) end
	self.mapDisplay:selectPosition()
	self:openMap()
end

function TaskGroupSelector:selectArea()
	self.positions = {}
	self.mapDisplay.onPositionSelected = function(objRef,x,y,z) self:onAreaSelected(x,y,z) end
	self.mapDisplay:selectPosition()
	self:openMap()
end

function TaskGroupSelector:mineArea()
	if self.node then
		self.taskName = "mineArea"
		self:selectArea()
	end
end


function TaskGroupSelector:onAreaSelected(x, y, z)
	print("selected position", #self.positions, x,y,z)
	if x and z then
		if #self.positions < 2 then
			if y == nil then
				if #self.positions == 0 then
					-- default top level
					y = default.yLevel.top					
				else
					-- default end level
					y = default.yLevel.bottom
				end
			end
			table.insert(self.positions,vector.new(x,y,z))

			if #self.positions == 1 then
				-- start selection for second position
				self.mapDisplay.onPositionSelected = function(objRef,x,y,z) self:onAreaSelected(x,y,z) end
				self.mapDisplay:selectPosition()
			end
		end
	else
		-- cancel position selection
	end
	
	if #self.positions == 2 then
		-- area selected
		self.mapDisplay:close()
		self:refresh()
		self:redraw()
	end
end

function TaskGroupSelector:onPositionSelected(x,y,z)
	if x and z then
		if y == nil then y = default.yLevel.top end
		self.node:send(self.data.id, {"DO",self.taskName,{x,y,z}})
	else
		-- cancel position selection
	end
	
	self:close()
	self.mapDisplay:close()
end
	
function TaskGroupSelector:navigateToPos()
	if self.node then
		self.taskName = "navigateToPos"
		self:selectPosition()
	end
end

return TaskGroupSelector
