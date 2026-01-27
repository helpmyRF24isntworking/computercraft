local Heap = {}
Heap.__index = Heap

-- default comparator (min-heap)
local function default_compare(a, b)
    return a < b
end

function Heap.new()
    return setmetatable({
        size = 0,
        Compare = default_compare,
        push = Heap.push,
        pop = Heap.pop,
        empty = Heap.empty,
    }, Heap)
end

local floor = math.floor

function Heap:push(value)
    local compare = self.Compare
    local size = self.size + 1
    self.size = size
    self[size] = value

    -- sift up
    local i = size
    while i > 1 do
        local parent = floor(i / 2)
        local pval = self[parent]
        if not compare(value, pval) then
            break
        end
        self[i] = pval
        i = parent
    end
    self[i] = value
end

function Heap:pop()
    local size = self.size
    if size == 0 then
        return nil
    end

    local root = self[1]
    local last = self[size]
    self[size] = nil
    size = size - 1
    self.size = size

    if size == 0 then
        return root
    end

    local compare = self.Compare
    local i = 1
    local half = floor(size / 2)

    -- sift down
    while i <= half do
        local left = i * 2
        local right = left + 1

        local child = left
        local cval = self[left]

        if right <= size then
            local rval = self[right]
            if compare(rval, cval) then
                child = right
                cval = rval
            end
        end

        if not compare(cval, last) then
            break
        end

        self[i] = cval
        i = child
    end

    self[i] = last
    return root
end

function Heap:peek()
    return self[1]
end

function Heap:empty()
    return self.size == 0
end

return Heap