

package.path = package.path ..";../?/?.lua" .. ";../general/?.lua"
local utilsSerialize = require("utilsSerialize")
local binarize = utilsSerialize.binarize
local serialize = utilsSerialize.serialize
local unbinarize = utilsSerialize.unbinarize
local unserialize = utilsSerialize.unserialize


local path = "test/map/chunks"
local type = type

local function compareChunks(chunkA, chunkB)
    for k, v in pairs(chunkA) do
        if type(k) == "number" then
            if chunkB[k] ~= v then
                print("MISSING KEY:", k, "VALUE A:", v, "VALUE B:", chunkB[k])
                return false
            end
        end
    end
    for k, v in pairs(chunkB) do
        if type(k) == "number" then
            if chunkA[k] ~= v then
                print("MISSING KEY:", k, "VALUE A:", chunkA[k], "VALUE B:", v)
                return false
            end
        end
    end
    return true
end

function compare_results()
    -- for each file in path compare results of serialize/unserialize and binarize/unbinarize
    local files = fs.list(path)
    for _, file in ipairs(files) do
        print("Comparing file:", file)
        local f = fs.open(path .. "/" .. file, "r")
        local serializedChunk = f.readAll()
        f.close()
        
        local unserializedChunk = unserialize(serializedChunk)
        local binaryChunk = binarize(unserializedChunk)
        local unbinarizedChunk = unbinarize(binaryChunk)
        
        if not compareChunks(unserializedChunk, unbinarizedChunk or {}) then
            print("Mismatch in file: " .. file)
            return false
        end
        os.pullEvent(os.queueEvent("yield"))
    end
    return true
end

print(compare_results())