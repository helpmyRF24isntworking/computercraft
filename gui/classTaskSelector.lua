local Button = require("classButton")
local Window = require("classWindow")

local default = {
	colors = {
		background = colors.black,
		border = colors.gray
	},
	width = 20,
	height = 12,
	yLevel =  {
		top = 73,
		bottom = -60,
	}
}

local TaskSelector = Window:new()

function TaskSelector:new(x,y,width,height)
	local o = o or Window:new(x,y,width or default.width ,height or default.height ) or {}
	setmetatable(o, self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)

	o.node = node or nil
	o.mapDisplay = mapDisplay or nil 
	o.taskName = nil
	o.selectedArea = nil
	o.selectedPos = nil
	
	o:initialize()
	return o
end

function TaskSelector:initialize()
	
	self.btnMineArea = Button:new("mineArea",3,3,14,1)
	self.btnNavigateToPos = Button:new("navigateToPos",3,5,14,1)
	self.btnDigToPos = Button:new("digToPos", 3,7,14,1)
	self.btnReboot = Button:new("reboot", 3,9,14,1)
	
	self.btnMineArea.click = function() self:mineArea() end
	self.btnNavigateToPos.click = function() self:navigateToPos() end
	self.btnDigToPos.click = function() self:digToPos() end
	self.btnReboot.click = function() self:reboot() end
	
	self:addObject(self.btnMineArea)
	self:addObject(self.btnNavigateToPos)
	self:addObject(self.btnDigToPos)
	self:addObject(self.btnReboot)
end

function TaskSelector:setTask(task)
	self.task = task
end

function TaskSelector:setNode(node)
	self.node = node
end
function TaskSelector:setData(data)
	self.data = data
end
function TaskSelector:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end
function TaskSelector:openMap()
	if self.hostDisplay and self.mapDisplay then
		self.hostDisplay:displayMap()
	end
end
function TaskSelector:closeMap()
	if self.hostDisplay and self.mapDisplay then
		self.hostDisplay:closeMap()
	end
end

function TaskSelector:selectPosition()
	self.position = nil
	self.mapDisplay.onPositionSelected = function(objRef,x,y,z) self:onPositionSelected(x,y,z) end
	self.mapDisplay:selectPosition()
	self:openMap()
end

function TaskSelector:selectArea()
	self.positions = {}
	self.mapDisplay.onPositionSelected = function(objRef,x,y,z) self:onAreaSelected(x,y,z) end
	self.mapDisplay:selectPosition()
	self:openMap()
end

function TaskSelector:mineArea()
	if self.node then
		self.taskName = "mineArea"
		self:selectArea()
	end
end


function TaskSelector:onAreaSelected(x, y, z)
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
		local args = {self.positions[1] ,self.positions[2]}
		local task = global.taskManager:addTaskToTurtle(self.data.id, self.taskName, args)

		self:close()
		self:closeMap()
	end
end

function TaskSelector:onPositionSelected(x,y,z)
	if x and z then
		if y == nil then y = default.yLevel.top end
		local task = global.taskManager:addTaskToTurtle(self.data.id, self.taskName, {x, y, z})
	else
		-- cancel position selection
	end

	self:close()
	self:closeMap()
end
	
function TaskSelector:navigateToPos()
	if self.node then
		self.taskName = "navigateToPos"
		self:selectPosition()
	end
end

function TaskSelector:digToPos()
	if self.node then
		self.taskName = "digToPos"
		self:selectPosition()
	end
end

function TaskSelector:reboot()
	if self.node then
		self.node:send(self.data.id, {"REBOOT"},false, false)
		-- self.taskManager:rebootTurtle(self.data.id)
		self:close()
	end
end

return TaskSelector