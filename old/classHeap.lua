local Heap = {}
Heap.__index = Heap

local floor = math.floor

local function findLowest(a, b)
    return a < b
end

local function newHeap(template, compare)
    return setmetatable({
        Data = {},
        Compare = compare or findLowest,
        Size = 0
    }, template)
end

function Heap:Empty()
    return self.Size == 0
end

function Heap:Clear()
    self.Data, self.Size = {}, 0
    return self
end

function Heap:Push(item)
    if not item then return self end
    
    local size = self.Size + 1
    self.Size = size
    local data = self.Data
    data[size] = item
    
    -- Inline sortUp
    local compare = self.Compare
    local index = size
    while index > 1 do
        local pIndex = floor(index / 2)
        local parent = data[pIndex]
        if compare(parent, item) then break end
        data[index] = parent
        index = pIndex
    end
    data[index] = item
    
    return self
end

function Heap:Pop()
    local size = self.Size
    if size == 0 then return nil end
    
    local data = self.Data
    local root = data[1]
    
    if size == 1 then
        data[1] = nil
        self.Size = 0
        return root
    end
    
    local item = data[size]
    data[size] = nil
    local newSize = size - 1
    self.Size = newSize
    
    -- Inline sortDown
    local compare = self.Compare
    local index = 1
    local half = floor(newSize / 2)
    
    while index <= half do
        local leftIndex = index * 2
        local rightIndex = leftIndex + 1
        local minIndex = leftIndex
        
        if rightIndex <= newSize and compare(data[rightIndex], data[leftIndex]) then
            minIndex = rightIndex
        end
        
        if compare(item, data[minIndex]) then break end
        
        data[index] = data[minIndex]
        index = minIndex
    end
    data[index] = item
    
    return root
end

return setmetatable(Heap, {__call = function(self, ...) return newHeap(self, ...) end})