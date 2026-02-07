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
local stringbyte, stringchar, stringsub = string.byte, string.char, string.sub
local tableconcat = table.concat
local toBlit = colors.toBlit

local blitTab = {
    [colors.white] = "0",
    [colors.orange] = "1",
    [colors.magenta] = "2",
    [colors.lightBlue] = "3",
    [colors.yellow] = "4",
    [colors.lime] = "5",
    [colors.pink] = "6",
    [colors.gray] = "7",
    [colors.lightGray] = "8",
    [colors.cyan] = "9",
    [colors.purple] = "a",
    [colors.blue] = "b",
    [colors.brown] = "c",
    [colors.green] = "d",
    [colors.red] = "e",
    [colors.black] = "f",
}

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
	local frame = self.frame
	local width, height = self.width, self.height

	local tColor = blitTab[self.textColor]
	local bgColor = blitTab[self.backgroundColor]

	for r = 1, height do
		local line = frame[r]
		if not line then 
			line = { {}, {}, {} }
			frame[r] = line
			local text, textColor, backgroundColor = line[1], line[2], line[3]
			for c = 1, width do
				text[c] = " "
				textColor[c] = tColor
				backgroundColor[c] = bgColor
			end
		else
			local text, textColor, backgroundColor = line[1], line[2], line[3]
			for c = #text+1, width do
				text[c] = " "
				textColor[c] = tColor
				backgroundColor[c] = bgColor
			end
		end
	end
end

function Monitor:clearFrame()
	local frame = self.frame
	local width, height = self.width, self.height

	local tColor = blitTab[self.textColor]
	local bgColor = blitTab[self.backgroundColor]
	
	for r=1, height do
		local line = frame[r]
		local text, textColor, backgroundColor = line[1], line[2], line[3]
		if line then 
			for i=1, width do
				text[i] = " "
				textColor[i] = tColor
				backgroundColor[i] = bgColor
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
	elseif event[1] == "mouse_scroll" then
		local dir = event[2]
		local x = event[3]
		local y = event[4]		
		local o = self:getObjectByPos(x,y)
		if o and o.handleScroll then
			return o:handleScroll(dir,x,y)
		end
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
		local nx, ny, nwidth, nheight, nvisible = node.x, node.y, node.width, node.height, node.visible
        if nwidth and nheight and nvisible then
            if x >= nx and x <= (nx + nwidth - 1)
                and y >= ny and y <= (ny + nheight - 1) then
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
	local frame = self.frame
	local term = self.term
	for i = 1, min(#frame, self.height) do
		local line = frame[i]
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]
		if line.modified then 
			term.setCursorPos(1,i)
			term.blit(tableconcat(lnText),
				tableconcat(lnTextColor),
				tableconcat(lnBackgroundColor))
			line.modified = false
		end
	end
end


function Monitor:blit(text, textColor, backgroundColor)
	local line = self.frame[self.curY]
	if line then 		
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]
		local cx = self.curX-1

		for i=self.curX, min(#text+cx, self.width) do
			local charPos = i-cx
			lnText[i] = stringsub(text, charPos, charPos)
			lnTextColor[i] = stringsub(textColor, charPos, charPos)
			lnBackgroundColor[i] = stringsub(backgroundColor, charPos, charPos)
		end
		line.modified = true
	end
end

function Monitor:blitTable(text, textColor, backgroundColor)
	-- text, textColor, backgroundColor should be table of chars
	local line = self.frame[self.curY]
	if line then 
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]
		local cx = self.curX-1

		for i=self.curX, min(#text+cx, self.width) do
			local charPos = i-cx
			lnText[i] = text[charPos]
			lnTextColor[i] = textColor[charPos]
			lnBackgroundColor[i] = backgroundColor[charPos]
		end
		line.modified = true
	end
end

function Monitor:write(text)

	local line = self.frame[self.curY]
	if line then 
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]

		local tColor = blitTab[self.textColor]
		local bgColor = blitTab[self.backgroundColor]

		local cx = self.curX-1

		for i=self.curX, min(#text+cx, self.width) do
			local charPos = i-cx
			lnText[i] = stringsub(text, charPos, charPos)
			lnTextColor[i] = tColor
			lnBackgroundColor[i] = bgColor
		end
		line.modified = true
		
	end
end

function Monitor:drawText(x,y,text,textColor,backgroundColor)
	-- no real performance impact 1 ms
	local line = self.frame[y]
	if line then 
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]

		if not textColor then
			textColor = defaultTextColor
		end
		local textColor = blitTab[textColor]
		
		if backgroundColor then 
			backgroundColor = blitTab[backgroundColor]
		end

		local cx = x-1
		for i=x, min(#text+cx, self.width) do
			local charPos = i-cx
			lnText[i] = stringsub(text, charPos, charPos)
			lnTextColor[i] = textColor
			if backgroundColor then
				lnBackgroundColor[i] = backgroundColor
			end
		end
		line.modified = true
	end

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

	--TODO: borderWidth, different values
	
	local frame = self.frame
	local selfwidth, selfheight = self.width, self.height

	local tColor = blitTab[color]
	local bgColor = blitTab[backgroundColor]

	local startX = min(x, selfwidth)
	local maxX = x+width-1
	local endX = min(maxX, selfwidth)
	local sy = y < 1 and 1 or y

	
	if false then
		-- uses full characters to draw the border
		local color = toBlit(color)
		local ly = y-1
		for cy = sy, min(height+ly, selfheight) do
			local line = frame[cy]
			local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]

			if cy-y == 0 or cy-ly == height then
				for ln=x, endX do
					lnText[ln] = " "
					lnTextColor[ln] = "0"
					lnBackgroundColor[ln] = tColor
				end
			else
				lnText[startX] = " "
				lnTextColor[startX] = "0"
				lnBackgroundColor[startX] = tColor
				if width > 1 and maxX <= endX then
					lnText[maxX] = " "
					lnTextColor[maxX] = "0"
					lnBackgroundColor[maxX] = tColor
				end
			end
			line.modified = true
		end
	else
		-- uses special characters to draw the border
		local ly = y-1

		for cy = sy, min(height+ly, selfheight) do

			local line = frame[cy]
			local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]

			if cy-y == 0 or cy-ly == height then
				for ln=x, endX do
					if cy-y == 0 then
						-- top line
						if ln == x then 
							lnText[ln] = " "
							lnTextColor[ln] = tColor
							lnBackgroundColor[ln] = tColor
							--line.text[ln] = "\129"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						elseif ln == endX then
							lnText[ln] = " "
							lnTextColor[ln] = tColor
							lnBackgroundColor[ln] = tColor
							--line.text[ln] = "\130"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						else
							lnText[ln] = "\143" --"\131"
							lnTextColor[ln] = tColor
							lnBackgroundColor[ln] = bgColor
						end
					else
						-- bottom line
						if ln==x then 
							lnText[ln] = " "
							lnTextColor[ln] = tColor
							lnBackgroundColor[ln] = tColor
							--line.text[ln] = "\144"
							--line.textColor[ln] = toBlit(self:getBackgroundColor())
							--line.backgroundColor[ln] = color
						elseif ln == endX then
							lnText[ln] = " "
							lnTextColor[ln] = tColor
							lnBackgroundColor[ln] = tColor
							--line.text[ln] = "\159"
							--line.textColor[ln] = color
							--line.backgroundColor[ln] = toBlit(self:getBackgroundColor())
						else
							lnText[ln] = "\131"
							lnTextColor[ln] = bgColor
							lnBackgroundColor[ln] = tColor
						end
					end
				end
			else
				lnText[startX] = " "
				lnTextColor[startX] = tColor
				lnBackgroundColor[startX] = tColor

				if width > 1 and maxX <= endX then
					lnText[maxX] = " "
					lnTextColor[maxX] = tColor
					lnBackgroundColor[maxX] = tColor
				end
			end
			line.modified = true
		end
	end

end

function Monitor:drawFilledBox(x,y,width,height,color)
	
	local frame = self.frame
	local selfwidth, selfheight = self.width, self.height

	local bgColor = blitTab[color]

	local maxX = x+width-1
	local endX = min(maxX, selfwidth)
	local sy = y < 1 and 1 or y
	
    for cy = sy, min(height+y-1, selfheight) do
		local line = frame[cy]
		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]
		for ln=x,endX do
			lnText[ln] = " "
			lnTextColor[ln] = "0"
			lnBackgroundColor[ln] = bgColor
		end
		line.modified = true
	end

end

function Monitor:drawCircle(x,y,radius,color)
    -- Bresenham / midpoint circle algorithm
    if not radius or radius <= 0 then return end

	local frame = self.frame
    local w,h = self.width, self.height

    local cx, cy = math.floor(x), math.floor(y)
    local r = math.floor(radius + 0.5)
    local col = blitTab[color]
    
    local function plot(px, py)
        if px < 1 or px > w or py < 1 or py > h then return end
        local line = frame[py]
        if not line then return end

		local lnText, lnTextColor, lnBackgroundColor = line[1], line[2], line[3]
        lnText[px] = " "
        lnTextColor[px] = col
        lnBackgroundColor[px] = col

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