List = {
first,
last,
count,
}

List.__index = List

function List:new(o)
    local o = o or {}
    setmetatable(o, self)
	
	---- Function Caching
    --for k, v in pairs(self) do
    --    if type(v) == "function" then
    --        o[k] = v  -- Directly assign method to object
    --    end
    --end
	
    o.first = nil
    o.last = nil
    o.count = 0
    return o
end

function List:clear()
    self.first, self.last = nil, nil
    self.count = 0
end

function List:addFirst(n)
	local first = self.first
    if first then
        first._prev = n
        n._prev, n._next = nil, first  -- slower but neccessary
        self.first = n
    else
		self.first, self.last = n, n
		n._prev, n._next = nil, nil
    end
    self.count = self.count + 1
	return n
end

function List:addLast(n)
	local last = self.last
	if last then 
		last._next = n
		n._prev, n._next = last, nil
		self.last = n
	else
		self.first, self.last = n, n
		n._prev, n._next = nil, nil
	end
	self.count = self.count + 1

	return n
end

function List:removeLast(n)
	-- for faster removal within loops, where the position is known
	-- if n ~= self.last then 
		-- error("not last")
	-- end
	local prv = n._prev
	if prv then 
		prv._next = nil
		self.last, self.count = prv, self.count - 1
		return prv
	else
		self.first, self.last, self.count = nil, nil, self.count - 1
		return nil
	end
end

function List:remove(n)
	local nxt, prv = n._next, n._prev
	if nxt then 
        if prv then -- middle node
            nxt._prev = prv
            prv._next = nxt
        else
			if n ~= self.first then self:logError("not first", n) end
            nxt._prev = nil
            self.first = nxt
        end
    elseif prv then
		if n ~= self.last then self:logError("not last", n) end  
		prv._next = nil
		self.last = prv
	else
		-- only node
		if n ~= self.first and n ~= self.last then	
			self:logError("not first or last", n)
		end
		self.first, self.last = nil, nil
    end
	-- set to nil in add
	-- n._next = nil
    -- n._prev = nil
    self.count = self.count - 1
	
end

function List:logError(reason, n)
	f = fs.open("trace.txt", "r")
	local text = ""
	if f then 
		text = f.readAll() 
		f.close()
	end
	f = fs.open("trace.txt", "w")
	f.write(text.." END")
	f.write(reason .. " | " .. textutils.serialize(debug.traceback()))
	f.close()
	print("prv, n, nxt", n._prev, n, n._next, "first, last", self.first, self.last)
	error(reason) --textutils.serialize(debug.traceback()))
end

-- DO NOT USE 
-- function List:getFirst()
    -- return self.first
-- end
-- function List:getLast()
    -- return self.last
-- end

-- function List:getNext(n)
    -- if n then
        -- return n._next
    -- else
        -- return self.first
    -- end
-- end
-- function List:getPrev(n)
    -- if n then
        -- return n._prev
    -- else
        -- return self.last
    -- end
-- end   

function List:toString()
	local text = ""
	node = self.first
	while node do
		text = text .. ":" .. textutils.serialize(node[1])
		node = node._next
	end
	return text
end


function List:moveToFront(n)
	-- for least recently used functionality. not used
	if n == self.first then
		return
	end
	if n._prev then
		n._prev._next = n._next
	end
	if n._next then
		n._next._prev = n._prev
	end
	if n == self.last then
		self.last = n._prev
	end
	self.count = self.count - 1
	return self:addFirst(n)
end