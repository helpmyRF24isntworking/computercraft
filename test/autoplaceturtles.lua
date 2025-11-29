
local g = global


-- Function to place a turtle, refuel it, and make it download and run a file
local function deployTurtle(pastebinCode)
    -- Check if there's a turtle in the inventory
    local slot = nil
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == "computercraft:turtle_advanced" then
            slot = i
            break
        end
    end

    if not slot then
        print("No turtle found in inventory!")
        return
    end

    -- Select the slot with the turtle and place it
    turtle.select(slot)
    if not turtle.place() then
        print("Failed to place the turtle!")
        return
    end

    print("Turtle placed successfully!")

    -- Refuel the placed turtle
    local fuelSlot = nil
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == "minecraft:coal_block" then
            fuelSlot = i
            break
        end
    end

    if not fuelSlot then
        print("No fuel found in inventory!")
        return
    end

    -- Drop fuel into the placed turtle
    turtle.select(fuelSlot)
    if not turtle.drop() then
        print("Failed to drop fuel into the turtle!")
        return
    end

    print("Fuel provided to the turtle!")

    -- Send a command to the placed turtle to download and run the file
    local modem = peripheral.find("modem")
    if not modem then
        print("No modem found! Ensure a wireless modem is attached.")
        return
    end

    local channel = 12000 -- Communication channel
    modem.open(channel)

    -- Send the command to the placed turtle
    local command = string.format(
        "pastebin get %s startup && startup",
        pastebinCode
    )
    modem.transmit(channel, channel, command)

    print("Command sent to the turtle to download and run the file!")
end

-- Example usage
local pastebinCode = "your_pastebin_code_here" -- Replace with your Pastebin code
deployTurtle(pastebinCode)