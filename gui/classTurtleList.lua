
local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")
local TurtleControl = require("classTurtleControl")
local ChoiceSelector = require("classChoiceSelector")
local OptionSelector = require("classOptionSelector")

local sortFunctions = {
    idAsc = function(a,b) return a.state.id < b.state.id end,
    idDesc = function(a,b) return a.state.id > b.state.id end,
    labelAsc = function(a,b) return a.state.label < b.state.label end,
    labelDesc = function(a,b) return a.state.label > b.state.label end,
}

local default = {
	colors = {
		--background = colors.black,
	},
    sortFunc = "idAsc",
    filter = {
        all = false,
		online = true,
        offline = true,
		active = true,
        inactive = true,
		stuck = true,
        notStuck = true,
	}
}

local TurtleList = {}
setmetatable(TurtleList, { __index = Window })
TurtleList.__index = TurtleList

function TurtleList:new(x,y,width,height,turtles)
	local o = o or Window:new(x,y,width,height)
	setmetatable(o,self)
	
	--o.backgroundColor = default.colors.background

    o.filter = default.filter
    o.turtleControls = {}
    o.turtleCt = 0
    o.turtles = turtles or nil
    o.sortFuncName = default.sortFunc
    o.sortFunction = sortFunctions[o.sortFuncName] or sortFunctions.idAsc
    
	o:initialize()
	
	return o
end

function TurtleList:initialize()
    -- Initialize storage display components here

    self:setTurtles(self.turtles)

    self.lblTitle = Label:new("Turtles",2,1)
    self:addObject(self.lblTitle)
    self:addScrollbar(true)
    -- self:removeCloseButton()

    self.btnFilter = Button:new("Filter", 12, 1, 8, 1)
    self.btnFilter.click = function() return self:selectFilter() end
    self:addObject(self.btnFilter)

    self.btnSort = Button:new("Sort Order", 22, 1, 12, 1)
    self.btnSort.click = function() return self:selectSortFunction() end
    self:addObject(self.btnSort)

    self.lblSortFunc = Label:new(self.sortFuncName, 35, 1)
    self:addObject(self.lblSortFunc)

    self:refresh()
end


function TurtleList:setFilter(filter)
    -- which turtles are displayed (by state)
    self.filter = filter
end

function TurtleList:setTaskManager(taskManager)
    self.taskManager = taskManager
end

function TurtleList:setTurtles(turtles)
    -- list of turtles to display, make it ipairs for sorting if not already
    local turtList = {}
    for _, turt in pairs(turtles) do
        table.insert(turtList, turt)
    end
    self.turtles = turtList
end

function TurtleList:selectSortFunction()

    local choices = {}
    for name, func in pairs(sortFunctions) do
        table.insert(choices, name)
    end
    table.sort(choices)
    self.funcSelector = ChoiceSelector:new(self.x + self.btnSort.x, self.y + self.btnSort.y, 16, 6, choices)
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

function TurtleList:selectFilter()
    -- a bit annoying to set the order
    local optList = {
        {text = "all", value = self.filter.all},
        {text = "online", value = self.filter.online},
        {text = "offline", value = self.filter.offline},
        {text = "active", value = self.filter.active},
        {text = "inactive", value = self.filter.inactive},
        {text = "stuck", value = self.filter.stuck},
        {text = "notStuck", value = self.filter.notStuck},
    }
    local options = optList
    self.optionSelector = OptionSelector:new(self.x + self.btnFilter.x, self.y + self.btnFilter.y, 16, 8, options)
    self.optionSelector.returnAsKeyValue = true
    self.optionSelector.onClose = function(options)
        self.filter = options
        self:refresh()
        self:redraw()
    end
    self.parent:addObject(self.optionSelector)
    self.parent:redraw()
    return true -- noBlink
end

function TurtleList:filterTurtles()
    local turtList = {}
    local filter = self.filter
    for _, turt in pairs(self.turtles) do
        if filter then
            local state = turt.state
            local active = (state.task ~= nil)
            local online, stuck = state.online, state.stuck

            if filter.all or ( ( online and filter.online or not online and filter.offline )
                and ( active and filter.active or not active and filter.inactive )
                and ( stuck and filter.stuck or not stuck and filter.notStuck ) ) then

                    table.insert(turtList, turt)
            end
        else
            table.insert(turtList, turt)
        end
    end
    return turtList
end

function TurtleList:refresh()
    -- change positions / contents etc.

	 if self.parent and self.visible then
        -- apply filter and sorting
        local turtleControls = self.turtleControls
        local turtList = self:filterTurtles()
        table.sort(turtList, self.sortFunction)

		local x, y = 1, 3
		local prvHeight = 1
        
        local prv = nil
        for i = 1, #turtList do
            local turt = turtList[i]
            local id = turt.state.id
            
            print("refreshing turtle", id, prv)
            prv = id
            local turtleControl = turtleControls[id]
            if not turtleControl then 		
                turtleControl = TurtleControl:new(x,y,turt,global.node) -- self.node, but we dont have one
                turtleControls[id] = turtleControl
                self:addObject(turtleControl)
                turtleControl:fillWidth()
                turtleControl:setHostDisplay(global.display) -- global.hostDisplay?
                self.turtleCt = self.turtleCt + 1
            else
                if prvHeight > 3 and turtleControl:getHeight() > 3 then
                    y = y - 1
                end
                if turtleControl:getY() ~= y then
                    turtleControl:setY(y)
                end
            end
            y = y + turtleControl:getHeight()
            prvHeight = turtleControl:getHeight()
            turtleControl.refreshed = true
		end

        for id, turtleControl in pairs(turtleControls) do
            if not turtleControl.refreshed then
                self:removeObject(turtleControl)
                turtleControls[id] = nil
                self.turtleCt = self.turtleCt - 1
            else
                turtleControl.refreshed = nil
            end
        end
	end

end

return TurtleList