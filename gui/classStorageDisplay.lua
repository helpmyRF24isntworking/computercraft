
local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")
local ItemControl = require("classStorageItemControl")



local default = {
	colors = {
		--background = colors.black,
	},
}
local global = global

local StorageDisplay = Window:new()

function StorageDisplay:new(x,y,width,height,storage)
	local o = o or Window:new(x,y,width,height)
	setmetatable(o,self)
	self.__index = self
	
	--o.backgroundColor = default.colors.background

    self.itemControls = {}
    self.itemCt = 0
    o.storage = storage or nil

	o:initialize()
	
	return o
end

function StorageDisplay:initialize()
    -- Initialize storage display components here

    self.lblTitle = Label:new("Stored Items",1,1)
    self:addObject(self.lblTitle)

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

function StorageDisplay:refresh()
    -- change positions / contents etc.
    if self.visible then 
        local itemControls = self.itemControls
        local storage = self.storage
        local itemList = storage:getAccumulatedItemList()
        table.sort(itemList, function(a,b) return a.name < b.name end)

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