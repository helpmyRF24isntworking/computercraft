
local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")
local TaskControl = require("classTaskControl")
local ChoiceSelector = require("classChoiceSelector")


local sortFunctions = {
    createdDesc = function(a,b) return a.time.created > b.time.created end,
    createdAsc = function(a,b) return a.time.created < b.time.created end,
    statusAsc = function(a,b) return a.status < b.status end,
    statusDesc = function(a,b) return a.status > b.status end,
    lastUpdateDesc = function(a,b) return a.lastUpdate > b.lastUpdate end,
    lastUpdateAsc = function(a,b) return a.lastUpdate < b.lastUpdate end,
}

local default = {
	colors = {
		--background = colors.black,
	},
    sortFunc = "createdDesc",
}

local TaskList = {}
setmetatable(TaskList, { __index = Window })
TaskList.__index = TaskList

function TaskList:new(x,y,width,height,taskManager)
	local o = o or Window:new(x,y,width,height)
	setmetatable(o,self)
	
	--o.backgroundColor = default.colors.background

    o.filter = nil
    o.taskControls = {}
    o.taskCt = 0
    o.taskManager = taskManager or nil
    o.sortFuncName = default.sortFunc
    o.sortFunction = sortFunctions[o.sortFuncName] or sortFunctions.createdDesc
    
	o:initialize()
	
	return o
end

function TaskList:initialize()
    -- Initialize storage display components here

    self.lblTitle = Label:new("TaskList",2,1)
    self:addObject(self.lblTitle)
    self:addScrollbar(true)
    self:removeCloseButton()

    self.btnSort = Button:new("Sort Order", 22, 1, 12, 1)
    self.btnSort.click = function() return self:selectSortFunction() end
    self:addObject(self.btnSort)

    self.lblSortFunc = Label:new(self.sortFuncName, 35, 1)
    self:addObject(self.lblSortFunc)

    self:refresh()
end

function TaskList:setFilter(filter)
    -- task ids, turtle id, group id, task type, task status, etc.
    self.filter = filter
end

function TaskList:setTaskManager(taskManager)
    self.taskManager = taskManager
end

function TaskList:onAdd()
    if self.filter then
        self.taskManager:getTaskList(self.filter)
    end
end


function TaskList:selectSortFunction()

    local choices = {}
    for name, func in pairs(sortFunctions) do
        table.insert(choices, name)
    end
    table.sort(choices)
    self.funcSelector = ChoiceSelector:new(self.x + self.btnSort.x, self.y + self.btnSort.y-8, 16, 6, choices)
    self.funcSelector.onChoiceSelected = function(choice)
        self.sortFunction = sortFunctions[choice]
        self.sortFuncName = choice
        self.lblSortFunc:setText(choice)
        self:refresh()
        self:redraw()
    end
    self.parent:addObject(self.funcSelector)
    self.parent:redraw()
    return true -- noBlink
end

function TaskList:refresh()
    -- change positions / contents etc.
    if self.parent and self.visible then 
        local taskControls = self.taskControls
        local taskList = self.taskManager:getTaskList(self.filter)
        table.sort(taskList, self.sortFunction)

        local x, y = 1,3
        local prvHeight = 0

        for i = 1, #taskList do
            local task = taskList[i]
            local taskControl = taskControls[task.id]
            if not taskControl then 
                
                taskControl = TaskControl:new(x,y,task)
                self:addObject(taskControl)
                taskControl:fillWidth()
                taskControls[task.id] = taskControl
                self.taskCt = self.taskCt + 1
            else
                if prvHeight > 3 and taskControl:getHeight() > 3 then 
                    y = y - 1
                end
                if taskControl:getY() ~= y then
                    taskControl:setY(y)
                end
            end
            prvHeight = taskControl:getHeight()
            y = y + prvHeight
            taskControl.refreshed = true
        end

        for id, taskControl in pairs(taskControls) do
            if not taskControl.refreshed then
                self:removeObject(taskControl)
                taskControls[id] = nil
                self.taskCt = self.taskCt - 1
            else
                taskControl.refreshed = nil
            end
        end
    end
end

return TaskList