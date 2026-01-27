
local utils = {}


local abs = math.abs
local min = math.min
local max = math.max


function utils.loadExtension(extensionModule, targetClass)
    for name, func in pairs(extensionModule) do
        if type(func) == "function" then
            targetClass[name] = func
        end
    end
end

function utils.manhattanDistance(x1, y1, z1, x2, y2, z2)
    return abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2)
end

return utils
