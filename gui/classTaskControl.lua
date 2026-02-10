-- TODO: create a generic collapable list item class
-- same for list displays

local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Frame = require("classFrame")
local NumberInput = require("classNumberInput")
local ChoiceSelector = require("classChoiceSelector")

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
		height = 6,
	},
	collapsed = {
		width = 50,
		height = 1,
	},
}

local TaskControl = {}
setmetatable(TaskControl, { __index = BasicWindow })
TaskControl.__index = TaskControl

function TaskControl:new(x,y,task)
	local o = BasicWindow:new(x,y,default.collapsed.width,default.collapsed.height) or {}
	setmetatable(o,self)
	
	o.backgroundColor = default.colors.background
	o.borderColor = default.colors.background
	
    o.task = task or nil
	o.collapsed = true
	o.win = nil
    o.expandedHeight = default.expanded.height
    o.elements = {}

	o:initialize()

	o:setTask(task)
	
	return o
end



function TaskControl:setTask(task)
	if task then
		self.task = task
	else
		--pseudo data
		self.task = {} -- itemName, total
	end
end

function TaskControl:collapse()
	if not self.collapsed then
		self.collapsed = true
		self:removeObject(self.win)
		self:addObject(self.winSimple)
		self.win = self.winSimple
		self:setHeight(default.collapsed.height)
        self.winDetail:removeObject(self.btnOptions)
        self.winSimple:addObject(self.btnOptions)
        self.btnOptions:setPos(40,1)
	end
	return true
end

function TaskControl:expand()
	if self.collapsed then 
		self.collapsed = false
		self:removeObject(self.win)
		self:addObject(self.winDetail)
		self.win = self.winDetail
		self:setHeight(self.expandedHeight)
        self.winSimple:removeObject(self.btnOptions)
        self.winDetail:addObject(self.btnOptions)
        self.btnOptions:setPos(47,4)
	end
	return true
end


function TaskControl:onResize() -- super override

	BasicWindow.onResize(self) -- super
	
	self.win:fillParent()
	self.frmName:setWidth(self.width)
	self.frmName:setHeight(self.height)
	
end

function TaskControl:redraw() -- super override
	self:refresh()
	
	BasicWindow.redraw(self) -- super
	
	if not self.collapsed then
		for i=3,5 do
			self:setCursorPos(18,i)
			--self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
		end
		for i=3,5 do
			self:setCursorPos(34,i)
			--self:blit("|",colors.toBlit(colors.lightGray),colors.toBlit(self.backgroundColor))
		end
	end
end

function TaskControl:viewGroup()
	local group = self.task:getGroup()
	if group then
		global.display:openGroupDetails(group)
	end
end

function TaskControl:openOptions()
	local choices = { "delete", "cancel" }
	if self.task:isResumable() then 
		table.insert(choices,1,"resume")
    else
        table.insert(choices,1,"restart")
	end
	
    local choiceSelector = ChoiceSelector:new(self.x + self.btnOptions.x -10, 10, 16, 6, choices)
	--local choiceSelector = ChoiceSelector:new(self.x + self.btnOptions.x - 25, self.y + self.btnOptions.y-10, 16, 6, choices)
	choiceSelector.onChoiceSelected = function(choice)
		if choice == "resume" then
			self.task:resume()
		elseif choice == "delete" then
			self.task:delete()
		elseif choice == "cancel" then
			self.task:cancel()
        elseif choice == "restart" then
            self.task:start()
        end
	end
    
    self.parent.parent.parent:addObject(choiceSelector)
    self.parent.parent.parent:redraw()
	return true
end

function TaskControl:initialize()
	
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

    local task = self.task
    local strTask = task.taskName --(task.shortId or "no id") .. " - " .. 
	self.winSimple.lblName = Label:new(strTask,5,1)

	self.winSimple.lblStatus = Label:new(task:getStatus(),22,1, task:getStatusColor())
    self.winSimple.lblProgress = Label:new(task:getProgressText(),34,1)
    self.btnOptions = Button:new("opts", 40, 1, 6, 1)

    self.btnOptions.click = function() 
        return self:openOptions()
    end
	
	self.btnExpand.click = function() return self:expand() end
	
	self.winSimple:addObject(self.btnExpand)
	self.winSimple:addObject(self.winSimple.lblName)
	self.winSimple:addObject(self.winSimple.lblStatus)
	self.winSimple:addObject(self.winSimple.lblProgress)
	self.winSimple:addObject(self.btnOptions)
	
	
	-- detail
	self.frmName = Frame:new(strTask ,1,1,self.width,self.height,default.borderColor)
	self.btnCollapse = Button:new("-",1,1,3,1)
	-- row 1 - 16

    local x, y = 3, 3
    self.lblGroup = Label:new("group:", x, y)
    local gid = task.groupId
    local groupName = gid and string.sub(gid,1,4) or "none"
    self.lblGroupValue = Label:new(groupName, x+7, y)
    self.btnGroup = Button:new("view", x+12, y, 6, 1)
    self.btnGroup:setEnabled(gid ~= nil)

    self.lblChk = Label:new( "checkpoint:", x, y+1)
    self.lblChkValue = Label:new(task:isResumable(), x+12, y+1)

    local x, y = 25, 3
    self.lblStatus = Label:new("status:", x, y)
    self.lblStatusValue = Label:new(task:getStatus(), x+10, y, task:getStatusColor())
    local progress = task:getProgressText()
    local pt = progress and progress ~= "" and "progress:" or ""
    self.lblProgress = Label:new(pt, x, y+1)
    self.lblProgressValue = Label:new(progress, x+10, y+1)

    local x, y = 47, 3
    self.btnDetails = Button:new("print",x,y,6,1)
    self.btnDetails.click = function()
        if self.task then 
            self.task:printDetails()
        end
    end

	self.btnGroup.click = function() return self:viewGroup() end

    self.btnCollapse.click = function() return self:collapse() end


    self.winDetail:addObject(self.frmName) -- add frame first to be in background ...
    self.winDetail:addObject(self.btnDetails)
    self.winDetail:addObject(self.lblGroup)
    self.winDetail:addObject(self.btnGroup)
    self.winDetail:addObject(self.lblGroupValue)
    self.winDetail:addObject(self.lblChk)
    self.winDetail:addObject(self.lblChkValue)
    self.winDetail:addObject(self.lblStatus)
    self.winDetail:addObject(self.lblStatusValue)
    self.winDetail:addObject(self.lblProgress)
    self.winDetail:addObject(self.lblProgressValue)

    self.winDetail:addObject(self.btnCollapse)
	
end

function TaskControl:refresh()

    local task = self.task
	if self.collapsed then
        self.winSimple.lblStatus:setText(task:getStatus())
        self.winSimple.lblStatus:setTextColor(task:getStatusColor())
        self.winSimple.lblProgress:setText(task:getProgressText())
	else
        self.lblStatusValue:setText(task:getStatus())
        self.lblStatusValue:setTextColor(task:getStatusColor())
        local progress = task:getProgressText()
        if progress and progress ~= "" then
            self.lblProgress:setText("progress:")
            self.lblProgressValue:setText(progress)
        else
            self.lblProgress:setText("")
            self.lblProgressValue:setText("")
        end
        self.lblChkValue:setText(task:isResumable())

	end
end

return TaskControl