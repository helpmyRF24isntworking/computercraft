
local storage = global.storage

if os.getComputerID() == 68 then
	storage.providerPos = vector.new(2214, 69, -2673)
else
	storage.providerPos = vector.new(2220, 69, -2660)
end
storage.requestingPos = storage.providerPos

storage:getInventories()
storage:indexInventories()

--storage:pingTurtles()
--local availableTurtles = storage:getNearestAvailableTurtles()

--for i, turtle in ipairs(availableTurtles) do
--    print("Available turtle:", turtle.id, "Distance:", turtle.dist)
--end

-- global.storage:requestReserveItems("minecraft:cobblestone", 200)