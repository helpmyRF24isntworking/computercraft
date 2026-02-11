-- class to draw individual pixels using the funny characters

local blockColor = require("blockColor")
local deltaE = blockColor.deltaEFromRGB
local blitTab = blockColor.blitTab

local default = {
}

local PixelDrawer = {}
PixelDrawer.__index = PixelDrawer

function PixelDrawer:new(width, height)
	local o = {}
	setmetatable(o, self)

	o.width = width
	o.height = height
	o.frame = {}
	o.blitFrame = {}

	o:initialize()
	
	return o
end

function PixelDrawer:initialize()
	self:clearFrame()
end

function PixelDrawer:setHeight(height)
	if height % 3 ~= 0 then
		print("HEIGHT MUST BE MULTIPLE OF 3", height)
		height = height + (3-height % 3)
	end
	if height ~= self.height then
		self.height = height
		self:clearFrame()
	end
end

function PixelDrawer:setWidth(width)
	if width % 2 ~= 0 then
		print("WIDTH MUST BE MULTIPLE OF 2", width)
		width = width + (2-width % 2)
	end
	if width ~= self.width then
		self.width = width
		self:clearFrame()
	end
end

function PixelDrawer:setSize(width, height)
	if height % 3 ~= 0 or width % 2 ~= 0 then
		print("WIDTH MUST BE MULTIPLE OF 2 AND HEIGHT MUST BE MULTIPLE OF 3", width, height)
		height = height + (3-height % 3)
		width = width + (2-width % 2)
	end
	if width ~= self.width or height ~= self.height then
		self.width = width
		self.height = height
		self:clearFrame()
	end
end

function PixelDrawer:clearFrame()
	local frame, width, height = {}, self.width, self.height

	for row = 1, height do
		local line = {}
		frame[row] = line
		for col = 1, width do
			line[col] = "0"
		end
	end
	self.frame = frame

	local bx = 0
	local blit = {}
	for row = 1, height, 3 do
		local by = 0
		bx = bx + 1
		local bline = { {}, {}, {} }
		blit[bx] = bline
		local btext, bcolor, bgcolor = bline[1], bline[2], bline[3]
		for col = 1, width, 2 do 
			by = by + 1
			btext[by] = " "
			bcolor[by] = "0"
			bgcolor[by] = "0"
		end
	end
	self.blitFrame = blit
end

function PixelDrawer:setPixel(x,y,color)
	-- not needed, for performance reasons, most functions will write directly to the frame
	if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
		self.frame[y][x] = color
	end
end

function PixelDrawer:drawLine(x1, y1, x2, y2, color)
    -- Bresenham's Line Algorithm
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

	local width, height = self.width, self.height

	local frame = self.frame
    while true do
        -- Set the pixel at (x1, y1) to the specified color
		if x1 >= 1 and x1 <= width and y1 >= 1 and y1 <= height then
			frame[y1][x1] = color
		end

        -- Break if the line has reached the end point
        if x1 == x2 and y1 == y2 then break end

        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x1 = x1 + sx
        end
        if e2 < dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
end

function PixelDrawer:drawCircle(x,y,radius,color)
    -- Bresenham / midpoint circle algorithm
    if not radius or radius <= 0 then return end

	local frame = self.frame
    local w,h = self.width, self.height

    local cx, cy = math.floor(x), math.floor(y)
    local r = math.floor(radius + 0.5)
    
    local function plot(px, py)
        if px < 1 or px > w or py < 1 or py > h then return end
        local line = frame[py]
        if not line then return end
		line[px] = color

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

local min = math.min
function PixelDrawer:drawBox(x,y,width,height,color, borderWidth)

	if not borderWidth then borderWidth = 1 end
	
	local frame = self.frame
	local selfwidth, selfheight = self.width, self.height

	local startX = min(x, selfwidth)
	local maxX = x+width-1
	local endX = min(maxX, selfwidth)
	local sy = y < 1 and 1 or y
	local borderHeight = height - borderWidth + 1 

	local ly = y-1
	for cy = sy, min(height+ly, selfheight) do
		local line = frame[cy]
		if ( cy-y +1 ) <= borderWidth or cy-ly >= borderHeight then
			for ln=x, endX do
				line[ln] = color
			end
		else
			for lx = startX, borderWidth+startX-1 do
				line[lx] = color
			end
			if width > 1 and maxX <= endX then
				for lx = maxX-borderWidth+1, maxX do
					line[lx] = color
				end
			end
		end
	end
end

local farben = {}
local colorDistances = {} -- colorDistances[c1+c2] = distance
local blitDistances = {} -- blitDistances[blit1..blit2] = distance
local blitMap = {} -- blitMap[blit1..blit2][blit3] = blit1 or blit2
local colorMap = {} -- colorMap[c1+c2][c3] = c1 or c2
local blitMap01 = {} -- blitMap01[blit1..blit2][blit3] = 0 or 1
local colorMap01 = {} -- colorMap01[c1+c2][c3] = 0 or 1

local function precalculateColors()
	farben = {}
	for i = 0, 15 do 
		local col = 2^i
		local r,g,b = term.getPaletteColor(col)
		local blit = colors.toBlit(col)

		print("color", col, r,g,b, blit)
		farben[col] = { r = r, g = g, b = b, blit = blit }
	end

	local start = os.epoch("utc")

	for c0, d0 in pairs(farben) do
		for c1, d1 in pairs(farben) do
			local dist = deltaE(d0.r, d0.g, d0.b, d1.r, d1.g, d1.b)

			local blitKey = d0.blit .. d1.blit
			local colorKey = c0 + c1

			blitDistances[blitKey] = dist
			colorDistances[colorKey] = dist
		end
	end

	--[[
	for c0, d0 in pairs(farben) do
		for c1, d1 in pairs(farben) do
			local blitKey = d0.blit .. d1.blit
			local colorKey = c0 + c1
			
			blitMap01[blitKey] = blitMap[blitKey] or {}
			colorMap01[colorKey] = colorMap[colorKey] or {}

			blitMap[blitKey] = blitMap[blitKey] or {}
			colorMap[colorKey] = colorMap[colorKey] or {}

			for cx, dx in pairs(farben) do
				-- print("c0", c0, "c1", c1, "cx", cx, "c0cx", c0+cx, "c1cx", c1+cx)
				local dist0 = colorDistances[c0 + cx]
				local dist1 = colorDistances[c1 + cx]

				if dist0 < dist1 then
					blitMap01[blitKey][dx.blit] = 0
					colorMap01[colorKey][cx] = 0
					blitMap[blitKey][dx.blit] = d0.blit
					colorMap[colorKey][cx] = c0
				else
					blitMap01[blitKey][dx.blit] = 1
					colorMap01[colorKey][cx] = 1
					blitMap[blitKey][dx.blit] = d1.blit
					colorMap[colorKey][cx] = c1
				end
			end
		end
	end
	--]]

	for c0, d0 in pairs(farben) do
		blitMap01[d0.blit] = blitMap01[d0.blit] or {}
		blitMap[d0.blit] = blitMap[d0.blit] or {}

		for c1, d1 in pairs(farben) do
			-- local blitKey = d0.blit .. d1.blit do not concat strings
			local colorKey = c0 + c1

			blitMap01[d0.blit][d1.blit] = blitMap01[d0.blit][d1.blit] or {}
			colorMap01[colorKey] = colorMap01[colorKey] or {}

			blitMap[d0.blit][d1.blit] = blitMap[d0.blit][d1.blit] or {}
			colorMap[colorKey] = colorMap[colorKey] or {}

			for cx, dx in pairs(farben) do
				-- print("c0", c0, "c1", c1, "cx", cx, "c0cx", c0+cx, "c1cx", c1+cx)
				local dist0 = colorDistances[c0 + cx]
				local dist1 = colorDistances[c1 + cx]

				if dist0 < dist1 then
					blitMap01[d0.blit][d1.blit][dx.blit] = 0
					colorMap01[colorKey][cx] = 0
					blitMap[d0.blit][d1.blit][dx.blit] = d0.blit
					colorMap[colorKey][cx] = c0
				else
					blitMap01[d0.blit][d1.blit][dx.blit] = 1
					colorMap01[colorKey][cx] = 1
					blitMap[d0.blit][d1.blit][dx.blit] = d1.blit
					colorMap[colorKey][cx] = c1
				end
			end
		end
	end
	print("deltaE precalculation took", os.epoch("utc") - start, "ms")
end



local function check(b, bn, s, sn, v, n)
	if n > bn then
		s, sn = b, bn
		b, bn = v, n
	elseif v ~= b and n > sn then
		s,sn = v, n
	end
	return b, bn, s, sn
end


local function checktotal(b, bn, s, sn, v, n, t)
	if n > bn then
		s, sn = b, bn
		b, bn = v, n
		t = t - n
	elseif v ~= b and n > sn then
		s,sn = v, n
		t = t - n		
	end
	return b, bn, s, sn, t
end


local function dominantColors3(a, b, c, d, e, f)
    -- Direct counting for each color
    local n1, n2, n3, n4, n5, n6 = 1, 0, 0, 0, 0, 0
	

    if b == a then n1 = n1 + 1 else n2 = n2 + 1 end
    if c == a then n1 = n1 + 1 elseif c == b then n2 = n2 + 1 else n3 = n3 + 1 end
    if d == a then n1 = n1 + 1 elseif d == b then n2 = n2 + 1 elseif d == c then n3 = n3 + 1 else n4 = n4 + 1 end
    if e == a then n1 = n1 + 1 elseif e == b then n2 = n2 + 1 elseif e == c then n3 = n3 + 1 elseif e == d then n4 = n4 + 1 else n5 = n5 + 1 end
    if f == a then n1 = n1 + 1 elseif f == b then n2 = n2 + 1 elseif f == c then n3 = n3 + 1 elseif f == d then n4 = n4 + 1 elseif f == e then n5 = n5 + 1 else n6 = n6 + 1 end

    -- Determine the two most frequent colors
    local best, bestn = a, n1
    local second, secondn = a, 0


	-- inline comparisons
    if n2 > bestn then
        second, secondn = best, bestn
        best, bestn = b, n2
    elseif n2 > secondn and b ~= best then
        second, secondn = b, n2
    end

    if n3 > bestn then
        second, secondn = best, bestn
        best, bestn = c, n3
    elseif n3 > secondn and c ~= best then
        second, secondn = c, n3
    end

    if n4 > bestn then
        second, secondn = best, bestn
        best, bestn = d, n4
    elseif n4 > secondn and d ~= best then
        second, secondn = d, n4
    end

    if n5 > bestn then
        second, secondn = best, bestn
        best, bestn = e, n5
    elseif n5 > secondn and e ~= best then
        second, secondn = e, n5
    end

    if n6 > bestn then
        second = best
        best = f
    elseif n6 > secondn and f ~= best then
        second = f
    end

    return best, second
end


local reverseMapping = {
	--[[
	[000000] = "\128",
	[000001] = "\129",
	[000010] = "\130",
	[000011] = "\131",
	[000100] = "\132",
	[000101] = "\133",
	[000110] = "\134",
	[000111] = "\135",
	[001000] = "\136",
	[001001] = "\137",
	[001010] = "\138",
	[001011] = "\139",
	[001100] = "\140",
	[001101] = "\141",
	[001110] = "\142",
	[001111] = "\143",
	[010000] = "\144",
	[010001] = "\145",
	[010010] = "\146",
	[010011] = "\147",
	[010100] = "\148",
	[010101] = "\149",
	[010110] = "\150",
	[010111] = "\151",
	[011000] = "\152",
	[011001] = "\153",
	[011010] = "\154",
	[011011] = "\155",
	[011100] = "\156",
	[011101] = "\157",
	[011110] = "\158",
	[011111] = "\159",
	--]]

	-- one less bit
	[00000] = "\128",
	[00001] = "\129",
	[00010] = "\130",
	[00011] = "\131",
	[00100] = "\132",
	[00101] = "\133",
	[00110] = "\134",
	[00111] = "\135",
	[01000] = "\136",
	[01001] = "\137",
	[01010] = "\138",
	[01011] = "\139",
	[01100] = "\140",
	[01101] = "\141",
	[01110] = "\142",
	[01111] = "\143",
	[10000] = "\144",
	[10001] = "\145",
	[10010] = "\146",
	[10011] = "\147",
	[10100] = "\148",
	[10101] = "\149",
	[10110] = "\150",
	[10111] = "\151",
	[11000] = "\152",
	[11001] = "\153",
	[11010] = "\154",
	[11011] = "\155",
	[11100] = "\156",
	[11101] = "\157",
	[11110] = "\158",
	[11111] = "\159",

	-- instead of doing 63 - char we could also add the inverse mapping, but this way we can also support the case where the dominant color is 1 instead of 0
	-- or we just use p5-p1 as charid and use p6 for inverting?
	--[[
	[111111] = "\128",
	[111110] = "\129",
	[111101] = "\130",
	[111100] = "\131",
	[111011] = "\132",
	[111010] = "\133",
	[111001] = "\134",
	[111000] = "\135",
	[110111] = "\136",
	[110110] = "\137",
	[110101] = "\138",
	[110100] = "\139",
	[110011] = "\140",
	[110010] = "\141",
	[110001] = "\142",
	[110000] = "\143",
	[101111] = "\144",
	[101110] = "\145",
	[101101] = "\146",
	[101100] = "\147",
	[101011] = "\148",
	[101010] = "\149",
	[101001] = "\150",
	[101000] = "\151",
	[100111] = "\152",
	[100110] = "\153",
	[100101] = "\154",
	[100100] = "\155",
	[100011] = "\156",
	[100010] = "\157",
	[100001] = "\158",
	[100000] = "\159",
	--]]
}

-- convert my funny binary to actual numbers
local mapping = {}
for bin,char in pairs(reverseMapping) do
	mapping[tonumber(bin,2)] = char
end

-- instead of a 16^6 lookup we can also do a 6^6 lookup
-- but not really needed for now, map:getData is main issue

local function pixelsToChar(p1,p2,p3,p4,p5,p6)
	-- we assume that we are in blit-mode

	-- do some bitshifting and use result as hash for the mapping
	-- e.g. 000000 = char \128 with 1 as foreground, 0 as background
	-- 		111111 = char \128 with 0 as foreground, 1 as background

	local c0, c1 = dominantColors3(p1,p2,p3,p4,p5,p6)
	local bmap = blitMap01[c0][c1]

	--[[
	print("pixel", p1, p2, p3, p4, p5, p6)
	print("c0", c0, "c1", c1)
	local function colToClos(col)
		if col == c0 then return 0
		elseif col == c1 then return 1
		else 
			print("mapping", col, " to ", bmap[col], "c0", c0, "c1", c1, "dist0", blitDistances[col..c0], "dist1", blitDistances[col..c1])
			return bmap[col] or 0
			--return colorDist(col, c0) <= colorDist(col, c1) and 0 or 1
		end
	end
	p1 = colToClos(p1)
	p2 = colToClos(p2)
	p3 = colToClos(p3)
	p4 = colToClos(p4)
	p5 = colToClos(p5)
	p6 = colToClos(p6)

		if p1 == c0 then p1 = 0 else p1 = 1 end
	if p2 == c0 then p2 = 0 else p2 = 1 end
	if p3 == c0 then p3 = 0 else p3 = 1 end
	if p4 == c0 then p4 = 0 else p4 = 1 end
	if p5 == c0 then p5 = 0 else p5 = 1 end
	if p6 == c0 then p6 = 0 else p6 = 1 end
	
		if p1 == c0 then p1 = 0 elseif p1 == c1 then p1 = 1 else p1 = 0 end
	if p2 == c0 then p2 = 0 elseif p2 == c1 then p2 = 1 else p2 = 0 end
	if p3 == c0 then p3 = 0 elseif p3 == c1 then p3 = 1 else p3 = 0 end
	if p4 == c0 then p4 = 0 elseif p4 == c1 then p4 = 1 else p4 = 0 end
	if p5 == c0 then p5 = 0 elseif p5 == c1 then p5 = 1 else p5 = 0 end
	if p6 == c0 then p6 = 0 elseif p6 == c1 then p6 = 1 else p6 = 0 end

--]]


	if p1 == c0 then p1 = 0 elseif p1 == c1 then p1 = 1 else p1 = bmap[p1] end
	if p2 == c0 then p2 = 0 elseif p2 == c1 then p2 = 1 else p2 = bmap[p2] end
	if p3 == c0 then p3 = 0 elseif p3 == c1 then p3 = 1 else p3 = bmap[p3] end
	if p4 == c0 then p4 = 0 elseif p4 == c1 then p4 = 1 else p4 = bmap[p4] end
	if p5 == c0 then p5 = 0 elseif p5 == c1 then p5 = 1 else p5 = bmap[p5] end
	if p6 == c0 then p6 = 0 elseif p6 == c1 then p6 = 1 else p6 = bmap[p6] end

--[[

	if p1 == c0 then p1 = 0 elseif p1 == c1 then p1 = 1 else p1 = bmap[p1] end
	if p2 == c0 then p2 = 0 elseif p2 == c1 then p2 = 1 else p2 = bmap[p2] end
	if p3 == c0 then p3 = 0 elseif p3 == c1 then p3 = 1 else p3 = bmap[p3] end
	if p4 == c0 then p4 = 0 elseif p4 == c1 then p4 = 1 else p4 = bmap[p4] end
	if p5 == c0 then p5 = 0 elseif p5 == c1 then p5 = 1 else p5 = bmap[p5] end
	if p6 == c0 then p6 = 0 elseif p6 == c1 then p6 = 1 else p6 = bmap[p6] end
	
	p1 = colorToClosest(p1, c0, c1)
	p2 = colorToClosest(p2, c0, c1)
	p3 = colorToClosest(p3, c0, c1)
	p4 = colorToClosest(p4, c0, c1)
	p5 = colorToClosest(p5, c0, c1)
	p6 = colorToClosest(p6, c0, c1)
	--]]

	local charId = p6 * 32 + p5 * 16 + p4 * 8 + p3 * 4 + p2 * 2 + p1
	--p = p and print("charid", charId, "bin", p6, p5, p4, p3, p2, p1)
	-- or if p6 == 1 then
	if charId > 31 then 
		-- color 0 is foreground, color 1 is background
		return mapping[63 - charId], c0, c1
	else
		-- color 0 is background, color 1 is foreground
		return mapping[charId], c1, c0
	end

	-- usage
	-- btext[bc], bcolor[bc], bgcolor[bc] = pixelsToChar(p1, p2, p3, p4, p5, p6)
end
PixelDrawer.pixelsToChar = pixelsToChar

local setcursor = term.setCursorPos
local termblit = term.blit
local tableconcat = table.concat

function PixelDrawer:toBlitFrame()
	local frame, width, height = self.frame, self.width, self.height
	local blit = self.blitFrame

	local br = 0
	for row = 1, height, 3 do -- 3 pixels height per char
		local line1 = frame[row]
		local line2 = frame[row+1]
		local line3 = frame[row+2]

		-- actual blit entry
		local bc = 0
		br = br + 1
		local bline = blit[br]
		local btext, bcolor, bgcolor = bline[1], bline[2], bline[3]

		for col = 1, width, 2 do -- 2 pixels width per char
			bc = bc + 1

			local col2 = col + 1
			local p1, p2, p3, p4, p5, p6 = line1[col], line1[col2], line2[col], line2[col2], line3[col], line3[col2]
			local txt, fgcol, bgcol = " ", 0, p1

			local singlecol = p1 == p2 and p1 == p3 and p1 == p4 and p1 == p5 and p1 == p6
			if not singlecol then
				-- all inline
				local n1, n2, n3, n4, n5, n6 = 1, 0, 0, 0, 0, 0

				if p2 == p1 then n1 = n1 + 1 else n2 = n2 + 1 end
				if p3 == p1 then n1 = n1 + 1 elseif p3 == p2 then n2 = n2 + 1 else n3 = n3 + 1 end
				if p4 == p1 then n1 = n1 + 1 elseif p4 == p2 then n2 = n2 + 1 elseif p4 == p3 then n3 = n3 + 1 else n4 = n4 + 1 end
				if p5 == p1 then n1 = n1 + 1 elseif p5 == p2 then n2 = n2 + 1 elseif p5 == p3 then n3 = n3 + 1 elseif p5 == p4 then n4 = n4 + 1 else n5 = n5 + 1 end
				if p6 == p1 then n1 = n1 + 1 elseif p6 == p2 then n2 = n2 + 1 elseif p6 == p3 then n3 = n3 + 1 elseif p6 == p4 then n4 = n4 + 1 elseif p6 == p5 then n5 = n5 + 1 else n6 = n6 + 1 end

				-- determine the two most frequent colors
				local c0, bestn = p1, n1
				local c1, secondn = p1, 0

				-- inline sorting
				if n2 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p2, n2
				elseif n2 > secondn and p2 ~= c0 then
					c1, secondn = p2, n2
				end

				if n3 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p3, n3
				elseif n3 > secondn and p3 ~= c0 then
					c1, secondn = p3, n3
				end

				if n4 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p4, n4
				elseif n4 > secondn and p4 ~= c0 then
					c1, secondn = p4, n4
				end

				if n5 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p5, n5
				elseif n5 > secondn and p5 ~= c0 then
					c1, secondn = p5, n5
				end

				if n6 > bestn then
					c1 = c0
					c0 = p6
				elseif n6 > secondn and p6 ~= c0 then
					c1 = p6
				end

				local bmap = blitMap01[c0][c1]
				p1 = bmap[p1]
				p2 = bmap[p2]
				p3 = bmap[p3]
				p4 = bmap[p4]
				p5 = bmap[p5]
				p6 = bmap[p6]

				--p1 = bmap[p1]; p2 = bmap[p2]; p3 = bmap[p3]; p4 = bmap[p4];	p5 = bmap[p5]; p6 = bmap[p6]

				-- leading bit p6 inverts the character
				local charId = p5 * 16 + p4 * 8 + p3 * 4 + p2 * 2 + p1
				if p6 == 1 then 
					-- color 0 is foreground, color 1 is background
					txt, fgcol, bgcol = mapping[31 - charId], c0, c1
				else
					-- color 0 is background, color 1 is foreground
					txt, fgcol, bgcol = mapping[charId], c1, c0
				end
			end

			btext[bc], bcolor[bc], bgcolor[bc] = txt, fgcol, bgcol

		end
	end
	return blit
end


function PixelDrawer:toBlitFrameInt()
	local frame, width, height = self.frame, self.width, self.height
	local blit = self.blitFrame
		local colorMap01 = colorMap01
	local mapping = mapping

	local br = 0
	for row = 1, height, 3 do -- 3 pixels height per char
		local line1 = frame[row]
		local line2 = frame[row+1]
		local line3 = frame[row+2]

		-- actual blit entry
		local bc = 0
		br = br + 1
		local bline = blit[br]
		local btext, bcolor, bgcolor = bline[1], bline[2], bline[3]

		for col = 1, width, 2 do -- 2 pixels width per char
			bc = bc + 1

			local col2 = col + 1
			local p1, p2, p3, p4, p5, p6 = line1[col], line1[col2], line2[col], line2[col2], line3[col], line3[col2]
			local txt, fgcol, bgcol = " ", 0, p1

			local singlecol = p1 == p2 and p1 == p3 and p1 == p4 and p1 == p5 and p1 == p6
			if not singlecol then

				-- all inline
				local n1, n2, n3, n4, n5, n6 = 1, 0, 0, 0, 0, 0

				if p2 == p1 then n1 = n1 + 1 else n2 = n2 + 1 end
				if p3 == p1 then n1 = n1 + 1 elseif p3 == p2 then n2 = n2 + 1 else n3 = n3 + 1 end
				if p4 == p1 then n1 = n1 + 1 elseif p4 == p2 then n2 = n2 + 1 elseif p4 == p3 then n3 = n3 + 1 else n4 = n4 + 1 end
				if p5 == p1 then n1 = n1 + 1 elseif p5 == p2 then n2 = n2 + 1 elseif p5 == p3 then n3 = n3 + 1 elseif p5 == p4 then n4 = n4 + 1 else n5 = n5 + 1 end
				if p6 == p1 then n1 = n1 + 1 elseif p6 == p2 then n2 = n2 + 1 elseif p6 == p3 then n3 = n3 + 1 elseif p6 == p4 then n4 = n4 + 1 elseif p6 == p5 then n5 = n5 + 1 else n6 = n6 + 1 end

				-- determine the two most frequent colors
				local c0, bestn = p1, n1
				local c1, secondn = p1, 0

				-- inline sorting
				if n2 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p2, n2
				elseif n2 > secondn and p2 ~= c0 then
					c1, secondn = p2, n2
				end

				if n3 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p3, n3
				elseif n3 > secondn and p3 ~= c0 then
					c1, secondn = p3, n3
				end

				if n4 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p4, n4
				elseif n4 > secondn and p4 ~= c0 then
					c1, secondn = p4, n4
				end

				if n5 > bestn then
					c1, secondn = c0, bestn
					c0, bestn = p5, n5
				elseif n5 > secondn and p5 ~= c0 then
					c1, secondn = p5, n5
				end

				if n6 > bestn then
					c1 = c0
					c0 = p6
				elseif n6 > secondn and p6 ~= c0 then
					c1 = p6
				end

				local bmap = colorMap01[c0 + c1]
				p1 = bmap[p1]
				p2 = bmap[p2]
				p3 = bmap[p3]
				p4 = bmap[p4]
				p5 = bmap[p5]
				p6 = bmap[p6]

				--p1 = bmap[p1]; p2 = bmap[p2]; p3 = bmap[p3]; p4 = bmap[p4];	p5 = bmap[p5]; p6 = bmap[p6]

				-- leading bit p6 inverts the character
				local charId = p5 * 16 + p4 * 8 + p3 * 4 + p2 * 2 + p1
				if p6 == 1 then 
					-- color 0 is foreground, color 1 is background
					txt, fgcol, bgcol = mapping[31 - charId], c0, c1
				else
					-- color 0 is background, color 1 is foreground
					txt, fgcol, bgcol = mapping[charId], c1, c0
				end
			end

			btext[bc], bcolor[bc], bgcolor[bc] = txt, fgcol, bgcol

		end
	end
	return blit
end



function PixelDrawer:redraw()
	local blit = self:toBlitFrame()
	--term.clear()
	for row = 1, #blit do
		local bline = blit[row]
		setcursor(1,row)
		termblit(tableconcat(bline[1]), tableconcat(bline[2]), tableconcat(bline[3]))
	end
end

precalculateColors()

return PixelDrawer