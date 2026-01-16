--Class Variables

require("classList")

local defaultBackgroundColor = colors.black
local defaultTextColor = colors.white
local defaultTextScale = 0.5
local defaultBoderWidth = 2

-- special characters: https://thox.madefor.cc/through/topics/encodings.html#computercraft-encoding

local Monitor = {}

local function findMonitor()
    local monitors = {peripheral.find("monitor")}
    if monitors[1] == nil then
        error("no monitor found",0)
    end
    return monitors[1]
end

local min = math.min
local stringbyte, stringchar = string.byte, string.char
local tableconcat = table.concat
local toBlit = colors.toBlit

--Class Initialization
function Monitor:new(m)
	local term = m or findMonitor()
    local m = {} --Window:new(1,1,term.getSize())
    setmetatable(m, self)
    self.__index = self
	
	m.term = term
	if m.term.setTextScale then 
		m.term.setTextScale(defaultTextScale)
	end
    m.term.setBackgroundColor(defaultBackgroundColor)
	self.backgroundColor = defaultBackgroundColor
	
    m.term.setTextColor(defaultTextColor)
	self.textColor = defaultTextColor
    
	m.visible = true
	m.frame = {}
	m.emptyLine = {}
	
	m.term.clear()
	m.curX, m.curY = m.term.getCursorPos()
	
    m:initialize()
    
    return m
end

--Class Functions
function Monitor:initialize()
    --DoStuff
    self.objects = List:new()
	self.events = List:new()
	self:updateSize()
	self:resizeFrame()
end

function Monitor:resizeFrame()
	local textColor = toBlit(self.textColor)
	local backgroundColor = toBlit(self.backgroundColor)
	
	for r=1, self.height do
		local line = self.frame[r]
		if not line then
			--self.frame[r] = emptyLine
			--self.frame[r].modified = false
			self.frame[r] = {text={}, textColor={}, backgroundColor={}}
			line = self.frame[r]
			for i=1, self.width do
				line.text[i] = " "
				line.textColor[i] = textColor
				line.backgroundColor[i] = backgroundColor
			end
		else
			for i=#line.text+1, self.width do
				line.text[i] = " "
				line.textColor[i] = textColor
				line.backgroundColor[i] = backgroundColor
			end
		end
	end
	-- for r=self.height+1, #self.frame do
		-- self.frame[r] = nil
	-- end
end

function Monitor:clearFrame()
	local textColor = toBlit(self.textColor)
	local backgroundColor = toBlit(self.backgroundColor)
	
	for r=1, self.height do
		local line = self.frame[r]
		if line then 
			for i=1, self.width do
				line.text[i] = " "
				line.textColor[i] = textColor
				line.backgroundColor[i] = backgroundColor
			end
		end
	end
end

function Monitor:handleEvent(event)
	print("Monitor:handleEvent", event[1], event[2], event[3], event[4])
	if event[1] == "monitor_touch" or event[1] == "mouse_up" or event[1] == "mouse_click" then
		local x = event[3]
		local y = event[4]
		local o = self:getObjectByPos(x,y)
		if o and o.handleClick then
			o:handleClick(x,y)
		end
	elseif event[1] == "monitor_resize" then 
		self:onResize()
	end
end

function Monitor:pullEvent(eventName)
	local event
	if eventName then
		event = {os.pullEvent(eventName)}
	else --too much?
		event = {os.pullEvent()}
	end
	self:handleEvent(event)
end
function Monitor:addEvent(event)
	self.events:addFirst(event)
end
function Monitor:checkEvents()
	local event = self.events.last
	if event then
		self.events:remove(event)
		self:handleEvent(event)
	end
end

function Monitor:onResize()
	self:updateSize()
	self:resizeFrame()
	local o = self.objects.first
	while o do
		if o.onResize then o:onResize() end
		o = o._next
	end
	self:redraw()
end

function Monitor:updateSize()
    self.width, self.height = self.term.getSize()
end

function Monitor:getSize()
	self:updateSize()
	return self.width, self.height
end

function Monitor:getWidth()
    self:updateSize()
    return self.width
end

function Monitor:getHeight()
    self:updateSize()
    return self.height
end


function Monitor:setVisible(isVisible)
	self.visible = isVisible
	local node = self.objects.first
    while node do
		if node.setVisible then
			node:setVisible(isVisible)
		else
			node.visible = isVisible
		end
		node = node._next
	end
end

function Monitor:addObject(o)
    self.objects:addFirst(o)
	if o.setVisible then
		o:setVisible(true)
	else
		o.visible = true
	end
	o.parent = self
	if o.onAdd then o:onAdd(self) end
    return o
end

function Monitor:removeObject(o)
    self.objects:remove(o)
	if o.setVisible then
		o:setVisible(false)
	else
		o.visible = false
	end
	o.parent = nil
	if o.onRemove then o:onRemove(self) end
    return o
end

function Monitor:redraw()
	--if self.visible then -- not needed?
    self:clear()
    --draw oldest first -> inverse list
    
    local node = self.objects.last
    while node do
        node:redraw()
        node = node._prev
    end
end

function Monitor:getTerm()
	return self.term
end

function Monitor:getRealPos(x,y)
	return  x, y
end

function Monitor:getObjectByPos(x,y)
    local node = self.objects.first
    while node do
        if node.width and node.height and node.visible then
            if x >= node.x and x <= (node.x + node.width - 1)
                and y >= node.y and y <= (node.y + node.height - 1) then
                return node
            end
        end
        node = node._next
    end
    return nil
end

function Monitor:getBackgroundColorByPos(x,y)
	-- high performance impact
    local o = self:getObjectByPos(x,y)
	if o and o.visible then
		if o.getBackgroundColorByPos then
			return o:getBackgroundColorByPos(x,y)
		elseif o.getBackgroundColor then
			return o:getBackgroundColor()
		elseif o.backgroundColor then
			return o.backgroundColor
		end
	elseif self.visible then
		return self:getBackgroundColor()
	end
    return nil
end

function Monitor:getBackgroundColor()
	return self.backgroundColor
end
function Monitor:setBackgroundColor(color)
    self.prvBackgroundColor = self.backgroundColor
    if color == nil then
        color = defaultBackgroundColor
    end
	self.backgroundColor = color
    --self.setBackgroundColor(color)
end

function Monitor:getTextColor()
	return self.textColor
end
function Monitor:setTextColor(color)
    self.prvTextColor = self.textColor
    if color == nil then
        color = defaultTextColor
    end
	self.textColor = color
    --self.setTextColor(color)
end

function Monitor:restoreBackgroundColor()
    local color = self.prvBackgroundColor
    if color == nil then
        color = defaultBackgroundColor
    end
	self.backgroundColor = color
    --self.setBackgroundColor(color)
end

function Monitor:restoreTextColor()
    local color = self.prvTextColor
    if color == nil then
        color = defaultTextColor
    end
	self.textColor = color
    --self.setTextColor(color)
end

function Monitor:restoreColor()
    self:restoreBackgroundColor()
    self:restoreTextColor()
end

function Monitor:setCursorPos(x,y)
	self.curX = x
	self.curY = y
end

function Monitor:clear()
	self.term.clear()
	self:clearFrame()
end

function Monitor:update()
	-- update the changed frame regions
	local ct = 0
	for i = 1, min(#self.frame,self.height) do
		local line = self.frame[i]
		if line.modified then 
			self.term.setCursorPos(1,i)
			self.term.blit(tableconcat(line.text),
				tableconcat(line.textColor),
				tableconcat(line.backgroundColor))
			line.modified = false
			ct = ct + 1
		end
	end
	-- if ct > 0 then 
		-- print(os.epoch("local")/1000, "updated", ct)
	-- end
end

function Monitor:blit(text,textColor, backgroundColor)
	local line = self.frame[self.curY]
	if line then 
	
		local text = {stringbyte(text,1,#text)}
		local textColor = {stringbyte(textColor,1,#textColor)}
		local backgroundColor = {stringbyte(backgroundColor,1,#backgroundColor)}
		
		local cx = self.curX-1
		for i=self.curX, min(#text+cx, self.width) do
			local charPos = i-cx
			line.text[i] = stringchar(text[charPos])
			line.textColor[i] = stringchar(textColor[charPos])
			line.backgroundColor[i] = stringchar(backgroundColor[charPos])
		end
		line.modified = true
	end
end

function Monitor:blitTable(text, textColor, backgroundColor)
	-- text, textColor, backgroundColor should be table of chars
	local line = self.frame[self.curY]
	if line then 
		local cx = self.curX-1
		for i=self.curX, min(#text+cx, self.width) do
			local charPos = i-cx
			line.text[i] = text[charPos]
			line.textColor[i] = textColor[charPos]
			line.backgroundColor[i] = backgroundColor[charPos]
		end
		line.modified = true
	end
end

function Monitor:write(text)

	local line = self.frame[self.curY]
	if line then 
	
		local chars = {stringbyte(text, 1, #text)}
		local textColor = toBlit(self.textColor)
		local backgroundColor = toBlit(self.backgroundColor)
		local cx = self.curX-1
		for i=self.curX, min(#chars+cx, self.width) do
			line.text[i] = stringchar(chars[i-cx])
			line.textColor[i] = textColor
			line.backgroundColor[i] = backgroundColor
		end
		line.modified = true
		
	end
end

function Monitor:drawText(x,y,text,textColor,backgroundColor)
	-- no real performance impact 1 ms
	local line = self.frame[y]
	if line then 

		local chars = {stringbyte(text, 1, #text)}
		if not textColor then
			textColor = defaultTextColor
		end
		local textColor = toBlit(textColor)
		
		if backgroundColor then 
			backgroundColor = toBlit(backgroundColor)
		end
		local cx = x-1
		for i=x, min(#chars+cx, self.width) do
			line.text[i] = stringchar(chars[i-cx])
			line.textColor[i] = textColor
			if backgroundColor then
				line.backgroundColor[i] = backgroundColor
			end
		end
		line.modified = true
	end


    -- self:setCursorPos(x,y)
	-- if not color then
		-- color = defaultTextColor
	-- end
	-- local backgroundColor = self:getBackgroundColorByPos(x,y)
	-- if not backgroundColor then
		-- backgroundColor = defaultBackgroundColor
	-- end
	-- self:setBackgroundColor(backgroundColor)
    -- self:setTextColor(color)
	-- self:setCursorPos(x,y)
	-- self:write(text)
    -- --TODO: check backgroundColor for each char (with blit)
    -- self:restoreColor()
end

function Monitor:drawLine(x,y,endX,endY,color)
    self:setBackgroundColor(color)
    local old = term.redirect(self.term)
    paintutils.drawLine(x,y,endX,endY,color)
    term.redirect(old)
    self:restoreBackgroundColor()
end

function Monitor:drawBox(x,y,width,height,color, boderWidth, backgroundColor)

	if not borderWidth then borderWidth = defaultBoderWidth end
	if not backgroundColor then backgroundColor = defaultBackgroundColor end
	local backgroundColor = toBlit(backgroundColor)

	--TODO: borderWidth, different values

	-- 4-5/13 ms for drawBox and drawFilled
	
	-- color = toBlit(color)
    -- for c=1,height do
		-- self:setCursorPos(x,y+c-1)
        -- if c == 1 or c == height then
			-- local text, textColor, backgroundColor = {},{},{}
            -- for ln=1,width do
				-- text[ln] = " "
				-- textColor[ln] = 0
				-- backgroundColor[ln] = color
            -- end
			-- self:blitTable(text,textColor,backgroundColor)
        -- else
            -- self:blitTable({" "},{"0"},{color})
            -- if width > 1 then
                -- self:setCursorPos(x+width-1, y+c-1)
                -- self:blitTable({" "},{"0"},{color})
            -- end
        -- end
    -- end
	
	--if 1 == 1 then return nil end
	
	
	local startX = min(x,self.width)
	local maxX = x+width-1
	local endX = min(maxX, self.width)
	local sy = y < 1 and 1 or y

	local frame = self.frame
	
	if false then
		local color = toBlit(color)
		local ly = y-1
		for cy=sy,min(height+ly,self.height) do
			local line = frame[cy]
			if cy-y == 0 or cy-ly == height then
				for ln=x, endX do
					line.text[ln] = " "
					line.textColor[ln] = 0
					line.backgroundColor[ln] = color
				end
			else
				line.text[startX] = " "
				line.textColor[startX] = "0"
				line.backgroundColor[startX] = color
				if width > 1 and maxX <= endX then
					line.text[maxX] = " "
					line.textColor[maxX] = "0"
					line.backgroundColor[maxX] = color
				end
			end
			line.modified = true
		end
	else
		local color = toBlit(color)
		local ly = y-1
		for cy=sy,min(height+ly,self.height) do
			local line = frame[cy]
			if cy-y == 0 or cy-ly == height then
				for ln=x, endX do
					if cy-y == 0 then
						if ln==x then 
							line.text[ln] = " "
							line.textColor[ln] = color
							line.backgroundColor[ln] = color
							--line.text[ln] = "\129"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						elseif ln == endX then
							line.text[ln] = " "
							line.textColor[ln] = color
							line.backgroundColor[ln] = color
							--line.text[ln] = "\130"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						else
							line.text[ln] = "\143" --"\131"
							line.textColor[ln] = color
							line.backgroundColor[ln] = backgroundColor
						end
					else
						if ln==x then 
							line.text[ln] = " "
							line.textColor[ln] = color
							line.backgroundColor[ln] = color
							--line.text[ln] = "\144"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						elseif ln == endX then
							line.text[ln] = " "
							line.textColor[ln] = color
							line.backgroundColor[ln] = color
							--line.text[ln] = "\159"
							--line.textColor[ln] = color
							--line.backgroundColor[ln] = toBlit(self:getBackgroundColor())
						else
							line.text[ln] = "\131"
							line.textColor[ln] = backgroundColor
							line.backgroundColor[ln] = color
						end
					end
				end
			else
				line.text[startX] = " "
				line.textColor[startX] = color
				line.backgroundColor[startX] = color
				if width > 1 and maxX <= endX then
					line.text[maxX] = " "
					line.textColor[maxX] = color
					line.backgroundColor[maxX] = color
				end
			end
			line.modified = true
		end
	end
	
	-- self:setBackgroundCol()
    -- local old = term.redirect(self)
    -- paintutils.drawBox(x,y,x+width-1,y+height-1,color)
    -- term.redirect(old)
	-- self:restoreBackgroundColor()

end

function Monitor:drawFilledBox(x,y,width,height,color)
	-- three options to draw a box
	
	-- color = toBlit(color)
    -- for c=1,height do
		-- self:setCursorPos(x,y+c-1)
		-- local text, textColor, backgroundColor = {},{},{}
		-- for ln=1,width do
			-- text[ln] = " "
			-- textColor[ln] = 0
			-- backgroundColor[ln] = color
		-- end
		-- self:blitTable(text, textColor, backgroundColor)
	-- end
	
	--if 1 == 1 then return nil end

	-- print("drawFilledBox", x,y,width,height,color)
	
	local startX = min(x,self.width)
	local maxX = x+width-1
	local endX = min(maxX, self.width)
	local sy = y < 1 and 1 or y
	
	
	local color = toBlit(color)
    for cy=sy,min(height+y-1,self.height) do
		local line = self.frame[cy]
		for ln=x,endX do
			line.text[ln] = " "
			line.textColor[ln] = 0
			line.backgroundColor[ln] = color
		end
		line.modified = true
	end
	
	-- self:setBackgroundCol()
    -- local old = term.redirect(self)
    -- paintutils.drawFilledBox(x,y,x+width-1,y+height-1,color)
    -- term.redirect(old)
	-- self:restoreBackgroundColor()
end

function Monitor:drawCircle(x,y,radius,color)
    -- Bresenham / midpoint circle algorithm
    if not radius or radius <= 0 then return end
    local w,h = self.width, self.height
    local cx, cy = math.floor(x), math.floor(y)
    local r = math.floor(radius + 0.5)
    local col = toBlit(color)

    local frame = self.frame
    local function plot(px, py)
        if px < 1 or px > w or py < 1 or py > h then return end
        local line = frame[py]
        if not line then return end
        line.text[px] = " "
        line.textColor[px] = col
        line.backgroundColor[px] = col
        line.modified = true
    end

    local dx = r
    local dy = 0
    local err = 1 - dx

    while dx >= dy do
        plot(cx + dx, cy + dy)
        plot(cx - dx, cy + dy)
        plot(cx + dx, cy - dy)
        plot(cx - dx, cy - dy)
        plot(cx + dy, cy + dx)
        plot(cx - dy, cy + dx)
        plot(cx + dy, cy - dx)
        plot(cx - dy, cy - dx)

        dy = dy + 1
        if err < 0 then
            err = err + 2 * dy + 1
        else
            dx = dx - 1
            err = err + 2 * (dy - dx) + 1
        end
    end
end

return Monitor