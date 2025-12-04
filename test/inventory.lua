
--https://github.com/SquidDev-CC/artist/blob/vnext/src/artist/core/items.lua#L596


package.path = package.path ..";../storage/?.lua"
local ItemStorage = require("classItemStorage")
local call = peripheral.call



function findWiredModem()
    for _,modem in ipairs(peripheral.getNames()) do
        local modemType, subType = peripheral.getType(modem)
        print(modem, "modemType", modemType, subType)
        if modemType == "modem" and subType == "peripheral_hub" then
            return modem
        end
    end
end

local modem = findWiredModem()


function getConnectedInventories(modem)
    local connected = call(modem, "getNamesRemote")
    local inventories = {}
    for _,name in ipairs(connected) do
        local mainType, subType = call(modem, "getTypeRemote", name)
        if subType == "inventory" then 
            inventories[#inventories+1] = name
            print("Found inventory:", name)
        end
    end
    return inventories
end
    
local connected = getConnectedInventories(modem)

function pushItems(fromInv, toInv, fromSlot, count, toSlot)


    local moved = call(fromInv, "pushItems", toInv, fromSlot, count, toSlot)
    print("moved", moved)
end



local storage = ItemStorage:new()
storage:getInventories()
storage:indexInventories()
storage:printIndex()


storage:extract("minecraft:stripped_spruce_wood", 65, "minecraft:chest_6")
storage:input("minecraft:chest_6")
storage:extract("minecraft:stripped_spruce_wood", 65, "minecraft:chest_6")


local time = os.epoch("utc")
pushItems("minecraft:hopper_0", "minecraft:chest_5", 1, 64, 1)
print("Time taken:", os.epoch("utc") - time)
pushItems("minecraft:hopper_0", "minecraft:chest_5", 2, 64, 4)
print("Time taken:", os.epoch("utc") - time)
pushItems("minecraft:hopper_0", "minecraft:chest_5", 3, 64, 6)
print("Time taken:", os.epoch("utc") - time)