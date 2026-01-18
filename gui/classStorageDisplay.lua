
local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")
local ItemControl = require("classStorageItemControl")
local ChoiceSelector = require("classChoiceSelector")


local sortFunctions = {
    nameAsc = function(a,b) return a.name < b.name end,
    nameDesc = function(a,b) return a.name > b.name end,
    countAsc = function(a,b) return a.count < b.count end,
    countDesc = function(a,b) return a.count > b.count end,
}

local default = {
	colors = {
		--background = colors.black,
	},
    sortFunc = "countDesc",
}
local global = global

local StorageDisplay = Window:new()

function StorageDisplay:new(x,y,width,height,storage)
	local o = o or Window:new(x,y,width,height)
	setmetatable(o,self)
	self.__index = self
	
	--o.backgroundColor = default.colors.background

    o.itemControls = {}
    o.itemCt = 0
    o.storage = storage or nil
    o.sortFuncName = default.sortFunc
    o.sortFunction = sortFunctions[o.sortFuncName] or sortFunctions.countDesc
    
	o:initialize()
	
	return o
end

function StorageDisplay:initialize()
    -- Initialize storage display components here

    self.lblTitle = Label:new("Stored Items",1,1)
    self:addObject(self.lblTitle)
    self:addScrollbar(true)

    self.btnSort = Button:new("Sort Order", 20, 1, 12, 1)
    self.btnSort.click = function() self:selectSortFunction() end
    self:addObject(self.btnSort)

    self.lblSortFunc = Label:new(self.sortFuncName, 33, 1)
    self:addObject(self.lblSortFunc)

    self:refresh()

end

function StorageDisplay:setHostDisplay(hostDisplay)
    self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end


function StorageDisplay:setStorage(storage)
    self.storage = storage
end

function StorageDisplay:onAdd()
    self.storage:requestItemList(true)
end

function StorageDisplay:checkUpdates()
    -- check if storage data has changed, and refresh if needed
    if self.storage and self.visible then
        local redraw = true
        -- TODO: only redraw/refresh if the itemlist has changed or expanded/collapsed or provider info changed in expanded
        self:refresh()
        if redraw then self:redraw() end
    end
end

function StorageDisplay:selectSortFunction()

    local choices = {}
    for name, func in pairs(sortFunctions) do
        table.insert(choices, name)
    end
    self.funcSelector = ChoiceSelector:new(self.btnSort.x, self.btnSort.y+1, 16, 6, choices)
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

function StorageDisplay:refresh()
    -- change positions / contents etc.
    if self.visible then 
        local itemControls = self.itemControls
        local storage = self.storage
        local itemList = storage:getAccumulatedItemList()
        table.sort(itemList, self.sortFunction)

        -- todo: resort existing controls if order changed

        local x, y = 1,3
        local prvHeight = 0

        for i = 1, #itemList do
            local item = itemList[i]
            local data = { itemName = item.name, total = item.count }
            local itemControl = itemControls[item.name]
            if not itemControl then 
                
                itemControl = ItemControl:new(x,y,data,storage)
                self:addObject(itemControl)
                itemControl:fillWidth()
                itemControl:setHostDisplay(self.hostDisplay)
                itemControls[item.name] = itemControl
                self.itemCt = self.itemCt + 1
            else
                if prvHeight > 3 and itemControl:getHeight() > 3 then 
                    y = y - 1
                end
                if itemControl:getY() ~= y then
                    itemControl:setY(y)
                end
                itemControl:setData(data)
            end
            prvHeight = itemControl:getHeight()
            y = y + prvHeight
            itemControl.refreshed = true
        end

        for itemName, itemControl in pairs(itemControls) do
            if not itemControl.refreshed then
                self:removeObject(itemControl)
                itemControls[itemName] = nil
                self.itemCt = self.itemCt - 1
            else
                itemControl.refreshed = nil
            end
        end

    end
end

return StorageDisplay