
local g = global

local function createStations(sx,sy,sz, amountPerRow, rows, rowDistance)
    config.stations.turtles = {}

    -- minus x direction

    for row = 1, rows do
        for k = 1, amountPerRow do
            local x = sx - (k - 1)
            local y = sy + (row - 1) * rowDistance
            g.addStation(x, y, sz, "north", "turtle")
        end
    end
end

local function createStationsDiagonal(sx,sy,sz, amountPerRow, rows, rowDistance)
    config.stations.turtles = {}

    -- minus x direction

    for row = 1, rows do
        for k = 1, amountPerRow do
            local x = sx - (k - 1)
	        local y = sy + (row - 1) * rowDistance
            local z = sz - (row - 1) * rowDistance
            g.addStation(x, y, z, "north", "turtle")
        end
    end
end

createStationsDiagonal(60, 66, -12, 25, 10, 2)
