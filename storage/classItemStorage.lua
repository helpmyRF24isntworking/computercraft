
local default = {
    stackSize = 64,
}

local peripheralCall = peripheral.call

ItemStorage = {}
ItemStorage.__index = ItemStorage

function ItemStorage:new()
	local o = o or {}
	setmetatable(o, self)
	
	-- Function Caching
    for k, v in pairs(self) do
       if type(v) == "function" then
           o[k] = v  -- Directly assign method to object
       end
    end

	o.inventories = {}
    o.index = {}
    o.itemDetails = {}
    o.peripheralHubs = {}

	o:initialize()
	return o
end

function ItemStorage:initialize()
    self.peripheralHubs = self.findWiredModems()
end

function ItemStorage.findWiredModem()
    for _,modem in ipairs(peripheral.getNames()) do
        local modemType, subType = peripheral.getType(modem)
        if modemType == "modem" and subType == "peripheral_hub" then
            return modem
        end
    end
    return nil
end

function ItemStorage.findWiredModems()
    local sides = {}
    for _,side in ipairs(redstone.getSides()) do
        local mainType, subType = peripheral.getType(side)
        if mainType == "modem" and ( subType == "peripheral_hub" or peripheral.call(side, "isWireless") == false ) then
            sides[#sides+1] = side
        end
    end
    return sides
end

function ItemStorage:getInventories()
    local inventories = self.inventories
    for _, peripheralHub in ipairs(self.peripheralHubs) do
        local connected = peripheralCall(peripheralHub, "getNamesRemote")
        
        for _,name in ipairs(connected) do
            local mainType, subType = peripheralCall(peripheralHub, "getTypeRemote", name) -- 0 ticks
            if subType == "inventory" then 
                local size = peripheralCall(name, "size") -- 1 tick
                local slots = {}
                for k = 1, size do slots[k] = { count = 0 } end
                inventories[name] = slots
                print("Found inventory:", name)
            end
        end
    end
end

function ItemStorage.getHash(item)
    -- optional to use nbt
    return item.nbt and ( item.name .. "@" .. item.nbt ) or item.name
end

function ItemStorage:indexInventories()
    local index = {}
    local inventories = self.inventories
    for invName, slots in pairs(inventories) do

        local size = #slots
        local list = peripheralCall(invName, "list") -- 1 tick
        for slot, item in pairs(list) do
            local name = item.name
            local idxEntry = index[name]
            if not idxEntry then 
                idxEntry = { [invName] = item.count }
                index[name] = idxEntry
            else
                idxEntry[invName] = ( idxEntry[invName] or 0 ) + item.count
            end
            slots[slot] = item
            
        end

        print("indexed", invName, "size", size)
    end
    self.index = index
end

function ItemStorage:printIndex()
    for itemName, invs in pairs(self.index) do
        print(itemName .. ": ")
        for invName, count in pairs(invs) do
            print( string.format("%s(%d) ", invName, count) )
        end

    end
end



function ItemStorage:countItem(itemName, sources)
    -- perhaps change the way index works to store total counts
    local total = 0
    local sources = sources or self.index[itemName]
    if sources then
        for invName, count in pairs(sources) do
            total = total + count
        end
    end
    return total
end

function ItemStorage:getItemList()
    local itCt = 0
    local itemList = {}
    for itemName, sources in pairs(self.index) do
        local count = self:countItem(itemName, sources)
        itCt = itCt + 1
        itemList[itCt] = { name = itemName, count = count }
    end
    return itemList
end

function ItemStorage:printItems()
    local items = self:getItemList()
    table.sort(items, function(a,b) return a.count > b.count end )
    for i = 1, #items do
        local item = items[i]
        print( item.name .. ": " .. item.count )
    end
end

function ItemStorage:cancelReservation(reservation)
    local inventories = self.inventories
    local index = self.index
    for i = 1, #reservation do
        local res = reservation[i]
        local invName, slot, count = res.invName, res.slot, res.count
        local invSlot = inventories[invName][slot]
        invSlot.reserved = invSlot.reserved - count
        invSlot.count = invSlot.count + count
        index[invSlot.name][invName] = ( index[invSlot.name][invName] or 0 ) + count
    end
end

function ItemStorage:extractReservation(reservation, toInv, toSlot)
    local extracted = 0
    local inventories = self.inventories
    for i = 1, #reservation do
        local res = reservation[i]
        local itemName, invName, slot, count = res.itemName, res.invName, res.slot, res.count
        local moved = peripheralCall(invName, "pushItems", toInv, slot, count, toSlot)
        if moved and moved > 0 then
            extracted = extracted + moved
            print(string.format("Extracted %d items from %s (slot %d) reserv", moved, invName, slot))
        else
            print("No items were extracted from:", invName, "slot:", slot)
        end
        local invSlot = inventories[invName][slot]
        invSlot.reserved = invSlot.reserved - count
    end
    return extracted
end

function ItemStorage:extract(itemName, count, toInv, toSlot, reservation)
    local index = self.index
    local inventories = self.inventories

    local remaining = count
    local sources = index[itemName]
    if not sources then
        print("Item not found in index:", itemName)
        return 0
    end

    for invName, available in pairs(sources) do
        if invName == toInv then break end

        local inventory = inventories[invName]
        local toMove = math.min(available, remaining)


        for i = #inventory, 1, -1 do
            local slot = inventory[i]
            local free = slot.count --- ( slot.reserved or 0 )
            if slot.name == itemName and free > 0 then 
                local moveCount = math.min(free, toMove)
                local moved
                if reservation then 
                    slot.reserved = ( slot.reserved or 0 ) + moveCount
                    reservation[#reservation+1] = { itemName = itemName, invName = invName, slot = i, count = moveCount }
                    moved = moveCount
                else
                    moved = peripheralCall(invName, "pushItems", toInv, i, moveCount, toSlot)
                end
                if moved and moved > 0 then
                    print(string.format("Moved %d of %s from %s (slot %d) to %s", moved, itemName, invName, i, toInv))
                    
                    available = available - moved
                    if available == 0 then
                        sources[invName] = nil
                    else
                        sources[invName] = available
                    end

                    toMove = toMove - moved
                    remaining = remaining - moved
                    slot.count = slot.count - moved

                    if remaining <= 0 or toMove <= 0 then break end
                else
                    print("no items in slot", invName, i, "or inventory is full", toInv)
                end
            end           
        end
    end

    local extracted = count - remaining
    if extracted > 0 then
        print(string.format("Extracted total of %d of %s to %s", extracted, itemName, toInv))
    else
        print("No items were extracted for:", itemName)
    end
    return extracted
end

function ItemStorage:input(fromInv, invList)
    -- invList optional
    local list
    if invList then
        list = invList
    else
        list = peripheralCall(fromInv, "list")
    end
    local inventories = self.inventories
    local index = self.index
    local itemDetails = self.itemDetails
    for srcSlot, item in pairs(list) do
        local name = item.name
        local remaining = item.count
        if not item.protected then
            local idxEntry = index[name]
            if idxEntry then
                for invName, invCount in pairs(idxEntry) do
                    if invName ~= fromInv then 
                        local inv = inventories[invName]
                        for toSlot = 1, #inv do
                            local slot = inv[toSlot]
                            local slotCount = slot.count
                            if slot.name == name then 
                                if slotCount < default.stackSize then 
                                    -- perhaps single stack or 16 stack item
                                    -- itemdetail relevant, store in idxentry though
                                    local itemDetail = itemDetails[name]
                                    if not itemDetail then 
                                        
                                        itemDetail = peripheralCall(invName, "getItemDetail", toSlot) -- 1 tick
                                        itemDetails[name] = itemDetail
                                    end
                                    local space = itemDetail.maxCount - slotCount
                                    if space > 0 then 
                                        local toMove = math.min(space, remaining)
                                        --local moved = peripheralCall(fromInv, "pushItems", invName, srcSlot, toMove, toSlot )
                                        local moved = peripheralCall(invName, "pullItems", fromInv, srcSlot, toMove, toSlot )
                                        if moved and moved > 0 then 
                                            slotCount = slotCount + moved
                                            remaining = remaining - moved
                                            invCount = invCount + moved
                                        else
                                            print("failed to move", name, "from", fromInv, "to", invName, "slot", toSlot)
                                        end
                                    end
                                    slot.count = slotCount
                                end
                            elseif slotCount == 0 then 
                                -- empty slot in same inventory can be used
                                --local moved = peripheralCall(fromInv, "pushItems", invName, srcSlot, remaining, toSlot)
                                local moved = peripheralCall(invName, "pullItems", fromInv, srcSlot, remaining, toSlot )
                                if moved and moved > 0 then 
                                    slot.name = name
                                    slot.count = moved
                                    remaining = 0
                                    invCount = invCount + moved
                                else
                                    print("failed to move", name, "from", fromInv, "to", invName, "slot", toSlot)
                                end
                            end
                            if remaining == 0 then break end
                        end
                    end
                    if invCount == 0 then -- shouldnt happen since we add items
                        idxEntry[invName] = nil
                    else
                        idxEntry[invName] = invCount
                    end
                    if remaining == 0 then break end
                end
                --idxEntry[fromInv] = ( idxEntry[fromInv] or 0 ) + ( item.count - remaining )
            end

            if remaining > 0 then
                idxEntry = idxEntry or {}

                -- unable to store all items together, find any empty inventory slot to store in
                for invName, slots in pairs(inventories) do
                    if invName ~= fromInv and not idxEntry[invName] then 
                        for toSlot = 1, #slots do
                            local slot = slots[toSlot]
                            if slot.count == 0 then
                                --local moved = peripheralCall(fromInv, "pushItems", invName, srcSlot, remaining, toSlot )
                                local moved = peripheralCall(invName, "pullItems", fromInv, srcSlot, remaining, toSlot )
                                if moved and moved > 0 then 
                                    slot.name = name
                                    slot.count = moved
                                    remaining = 0
                                    idxEntry[invName] = moved
                                    break
                                else
                                    print("failed to move", name, "from", fromInv, "to", invName, "slot", toSlot)
                                end
                            end
                        end
                        if remaining == 0 then break end
                    end
                end
                if remaining == 0 then
                    index[name] = idxEntry
                end
            end

            if remaining > 0 then 
                print("unable to store all of item:", name, "remaining:", remaining)
            end
        end
    end

end

    
function ItemStorage:push(fromInv, fromSlot, count, toInv, toSlot)
    local moved = peripheralCall(fromInv, "pushItems", toInv, fromSlot, count, toSlot)
    if moved then
        print(string.format("Inserted %d items from %s (slot %d) to %s (slot %d)", moved, fromInv, fromSlot, toInv, toSlot))
    else
        print("No items were inserted from:", fromInv)
    end
    return moved
end

return ItemStorage