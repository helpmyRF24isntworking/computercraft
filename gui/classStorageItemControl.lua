-- expandable container like ItemControl for items in storage
-- collapsed: itemname, count, locally stored if applicable (not pocket), request button
-- expanded: per provider list of counts and locations with map button
-- request button to get items delivered 
--      either to current position if pocket or to move between storages
-- too late to do ts now

local Button = require("classButton")
local Label = require("classLabel")
local BasicWindow = require("classBasicWindow")
local Frame = require("classFrame")
local NumberInput = require("classNumberInput")

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
		height = 7,
	},
	collapsed = {
		width = 50,
		height = 1,
	},
}

local ItemControl = BasicWindow:new()

function ItemControl:new(x,y,data,storage)
	local o = o or BasicWindow:new(x,y,default.collapsed.width,default.collapsed.height) or {}
	setmetatable(o,self)
	self.__index = self
	
	o.backgroundColor = default.colors.background
	o.borderColor = default.colors.background
	
    o.storage = storage or nil
	o.data = data
	o.mapDisplay = nil -- needed to enable the map button
	o.hostDisplay = nil
	o.collapsed = true
	o.win = nil
    o.expandedHeight = default.expanded.height
    o.elements = {}

	o:initialize()

	o:setData(data)
	
	return o
end

function ItemControl:setNode(node)
	self.node = node
end

function ItemControl:setData(data)
	if data then
		self.data = data
	else
		--pseudo data
		self.data = {} -- itemName, total
	end
end
function ItemControl:setHostDisplay(hostDisplay)
	self.hostDisplay = hostDisplay
	if self.hostDisplay then
		self.mapDisplay = self.hostDisplay:getMapDisplay()
	end
end
function ItemControl:collapse()
	if not self.collapsed then
		self.collapsed = true
		self:removeObject(self.win)
		self:addObject(self.winSimple)
		self.win = self.winSimple
		self:setHeight(default.collapsed.height)
	end
	return true
end
function ItemControl:expand()
	if self.collapsed then 
		self.collapsed = false
		self:removeObject(self.win)
		self:addObject(self.winDetail)
		self.win = self.winDetail
		self:setHeight(self.expandedHeight)
	end
	return true
end



function ItemControl:openMap(pos)
	if self.hostDisplay and self.mapDisplay then
		self.mapDisplay:setMapMid(pos) -- vector.new(pos.x, pos.z, pos.y)
		self.hostDisplay:displayMap()
	end
end


function ItemControl:onResize() -- super override

	BasicWindow.onResize(self) -- super
	
	self.win:fillParent()
	self.frmName:setWidth(self.width)
	self.frmName:setHeight(self.height)
	
end

function ItemControl:redraw() -- super override
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

function ItemControl:initialize()
	
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

    local nameStr = string.gsub(self.data.itemName, "minecraft:", "")
	self.winSimple.lblName = Label:new(nameStr,13,1)
    local totalStr = string.format("%6d", self.data.total)
	self.winSimple.lblTotal = Label:new(totalStr,5,1) -- 39
    self.winSimple.btnRequest = Button:new("request",44,1,9,1)

    self.winSimple.btnRequest.click = function() end
	
	self.btnExpand.click = function() return self:expand() end
	
	self.winSimple:addObject(self.btnExpand)
	self.winSimple:addObject(self.winSimple.lblName)
	self.winSimple:addObject(self.winSimple.lblTotal)
	self.winSimple:addObject(self.winSimple.btnRequest)
	
	
	-- detail
	self.frmName = Frame:new(self.data.itemName ,1,1,self.width,self.height,default.borderColor)
	self.btnCollapse = Button:new("-",1,1,3,1)
	-- row 1 - 16

    


	-- row 20 - 

    local elements = {}
    local total = 0

    local x, y = 3, 4 
    local offsetX1, offsetX2 = 17, 36

    self.lblProviderHd = Label:new("provider",x,3)
    self.lblCountHd = Label:new("count",x+offsetX1,3)
    self.btnDetails = Button:new("print details",x+offsetX2-6,3,15,1)

    if self.storage and self.storage.index then 
        local count = self.storage:countItem(self.data.itemName)
        if count > 0 then 
            self:createElements(elements, "self", count, nil, x, y, offsetX1, offsetX2)
            y = y + 1
            total = total + count
        end
    end

    if self.storage and self.storage.providerIndex then 
        local providerStates = self.storage.providers or {}
        local providers = self.storage.providerIndex[self.data.itemName]
        if providers then 
            for provider, count in pairs(providers) do
                local state = providerStates[provider]
                self:createElements(elements, provider, count, state, x, y, offsetX1, offsetX2)
                y = y + 1
                total = total + count
            end
        end
    end

    if total > 0 then 
        self:createElements(elements, "total", total, nil, x, y, offsetX1, offsetX2)
    end

    self.btnCollapse.click = function() return self:collapse() end
    

    self.winDetail:addObject(self.frmName) -- add frame first to be in background ...
    self.winDetail:addObject(self.lblProviderHd)
    self.winDetail:addObject(self.lblCountHd)
    self.winDetail:addObject(self.btnDetails)

    self.elements = elements
    for provider, provElements in pairs(elements) do
        for descr, elem in pairs(provElements) do
            self.winDetail:addObject(elem)
            elem.added = nil
        end
    end

	self.winDetail:addObject(self.btnCollapse)

    self.expandedHeight = y + 2
	
	self.winSimple.btnRequest.visible = self.data.total > 0
end

function ItemControl:createElements(elements, provider, count, state, x, y, offsetX1, offsetX2)
    -- helper for adding elements in the expanded view
    local newElements = {}
    if provider == "self" then
        newElements["lblSelf"] = Label:new("self", x, y)
        newElements["lblCountSelf"] = Label:new(count, x + offsetX1, y)
        newElements["btnExtract"] = Button:new("extract", x + offsetX2, y, 9, 1)
        newElements["btnExtract"].click = function() 
            if self.storage then 
                -- self.storage:extract() -- but where to
            end
        end
    elseif provider == "total" then 
        newElements["lblTotal"] = Label:new("total"..string.rep("\175",offsetX1-5), x, y)
        newElements["lblCountTotal"] = Label:new(total, x + offsetX1, y)
        newElements["btnRequestTotal"] = Button:new("request any", x + offsetX2-6, y, 15, 1)
        newElements["btnRequestTotal"].click = function() 
            if self.storage then 
                local amount

                local requestDelivery = function(amount)
                    print("requested amount:", amount)
                    self.storage:requestDelivery(self.data.itemName, amount, pocket and true)
                end

                if pocket then 
                    -- use keyboard input for amount
                    local rx, ry = self:getRealPos(x + offsetX2+10, y)
                    local curTerm = self:getTerm()
                    curTerm.setCursorPos(rx, ry)
                    curTerm.write("amount: ")
                    os.queueEvent("input_request", math.random(1,1000)) -- caught in shellDisplay.lua
                    local event, token, input = os.pullEventRaw("input_response")
                    if event == "terminate" then return end
                    amount = tonumber(input) or 0

                    requestDelivery(amount)
                else
                    -- use a touch gui prompt for amount
                    local inputWin = NumberInput:new(10,5,"Item Amount")
                    self.parent:addObject(inputWin)
                    inputWin:center()
                    inputWin.onNumberEntered = requestDelivery

                end

            end
        end
    else
        local strProvider = provider
        if state then 
            if state.label and tostring(state.label) ~= tostring(provider) then 
                strProvider = provider .. "-" .. state.label
            end
        end
        newElements["lbl"..provider] = Label:new(strProvider, x, y)
        newElements["lblCount"..provider] = Label:new(count, x + offsetX1, y)
        newElements["btnMap"..provider] = Button:new("map", x + offsetX2-6, y, 5, 1)
        newElements["btnMap"..provider].click = function() 
            -- self:openMap(nil) -- TODO: get provider position
        end
        newElements["btnRequest"..provider] = Button:new("request", x + offsetX2, y, 9, 1)
        newElements["btnRequest"..provider].click = function() 
            if self.storage then 
                -- self.storage:requestDelivery() -- direct request to specified provider, not general
            end
        end
    end
    for descr, elem in pairs(newElements) do
        elem.added = true
    end
    elements[provider] = newElements
end

function ItemControl:refresh()

	if self.collapsed then
        local totalStr = string.format("%6d", self.data.total)
		self.winSimple.lblTotal:setText(totalStr)
        self.winSimple.btnRequest.visible = self.data.total > 0
	else

        local total = 0
        local x, y = 3, 4
        local offsetX1, offsetX2 = 17, 36
        local elements = self.elements
        local providerStates = self.storage.providers or {}

        if self.storage and self.storage.index then 
            local providerElements = elements["self"] or {}
            local count = self.storage:countItem(self.data.itemName)
            if count > 0 then 
                if not providerElements["lblSelf"] then
                    self:createElements(elements, "self", count, nil, x, y, offsetX1, offsetX2)
                else
                    providerElements["lblCountSelf"]:setText(count)
                end
                y = y + 1
                total = total + count
            else
                if providerElements["lblSelf"] then
                    providerElements["lblSelf"].removed = true
                    providerElements["lblCountSelf"].removed = true
                    providerElements["btnExtract"].removed = true
                end
            end
        end

        if self.storage and self.storage.providerIndex then 
            local providers = self.storage.providerIndex[self.data.itemName]
            if providers then 
                for provider, count in pairs(providers) do
                    local providerElements = elements[provider] or {}
                    if count > 0 then 
                        if not providerElements["lbl"..provider] then
                            local state = providerStates[provider]
                            self:createElements(elements, provider, count, state, x, y, offsetX1, offsetX2)
                        else
                            providerElements["lblCount"..provider]:setText(count)

                            providerElements["lbl"..provider]:setPos(x, y)
                            providerElements["lblCount"..provider]:setPos(x + offsetX1, y)
                            providerElements["btnMap"..provider]:setPos(x + offsetX2-6, y)
                            providerElements["btnRequest"..provider]:setPos(x + offsetX2, y)
                        end
                        y = y + 1
                        total = total + count
                    else
                        -- requestAvailableItems sets index to 0, not nil 
                        if providerElements["lbl"..provider] then
                            providerElements["lbl"..provider].removed = true
                            providerElements["lblCount"..provider].removed = true
                            providerElements["btnMap"..provider].removed = true
                            providerElements["btnRequest"..provider].removed = true
                        end
                    end
                    -- TODO: provider elements not removed if not in providerIndex any longer
                end
            end
        end

        local providerElements = elements["total"] or {}
        if total > 0 then 
            if not providerElements["lblTotal"] then
                self:createElements(elements, "total", total, nil, x, y, offsetX1, offsetX2)
            else
                providerElements["lblCountTotal"]:setText(total)

                providerElements["lblTotal"]:setPos(x, y)
                providerElements["lblCountTotal"]:setPos(x + offsetX1, y)
                providerElements["btnRequestTotal"]:setPos(x + offsetX2-6, y)
            end            
        else
            if providerElements["lblTotal"] then
                providerElements["lblTotal"].removed = true
                providerElements["lblCountTotal"].removed = true
                providerElements["btnRequestTotal"].removed = true
            end
        end

        -- alternatively instead of removing offline providers, gray them out

        for provider, providerElements in pairs(elements) do
            local state = providerStates[provider]
            local remove = ( not state and provider ~= "self" and provider ~= "total")
            for descr, elem in pairs(providerElements) do
                if elem.removed or remove then
                    print("removing", descr, elem)
                    self.winDetail:removeObject(elem)
                    providerElements[descr] = nil
                elseif elem.added then
                    print("adding", descr, elem)
                    self.winDetail:addObject(elem)
                    elem.added = nil
                end
            end
        end

        
        self.expandedHeight = y + 2
        if self:getHeight() ~= self.expandedHeight then
            self:setHeight(self.expandedHeight)
        end
        
	end
end

return ItemControl