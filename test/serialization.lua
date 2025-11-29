

local chunk = {
--[1] = 0,
[2] = 0,
[3] = 0,
[4] = 0,
[5] = "computercraft:turtle_advanced",
[6] = 0,
[7] = "computercraft:turtle_advanced",
[8] = "computercraft:turtle_advanced",
[9] = "computercraft:turtle_advanced",
[10] = 0,
[11] = "computercraft:turtle_advanced",
[12] = "computercraft:turtle_advanced",
[13] = 0,
[14] = 0,
[15] = "computercraft:turtle_advanced",
[16] = "computercraft:turtle_advanced",
[17] = 0,
[18] = "computercraft:turtle_advanced",
[19] = 0,
--[20] = 0,
[21] = 0,
[22] = 0,
[23] = "computercraft:turtle_advanced",

["_lastChange"] = 1847592000,
["_accessCount"] = 1332,
}
package.path = package.path ..";../?/?.lua" .. ";../general/?.lua"
local utilsSerialize = require("utilsSerialize")
local binarize = utilsSerialize.binarize
local simpleSerialize = utilsSerialize.serialize
local binarizeRuns = utilsSerialize.binarizeRuns
local unbinarize = utilsSerialize.unbinarize
local unserialize = utilsSerialize.unserialize

local f = fs.open("test/testchunk.txt","r")
local stillSerializedChunk = f.readAll()
chunk = unserialize(stillSerializedChunk)
f.close()


-- BINARIZE
local function testBinarize(times)
    local ts = os.epoch("utc")
    local binaryData
    for i = 1, times do
        binaryData = binarize(chunk)
    end
    print(os.epoch("utc") - ts, "BINARY DATA LENGTH (CHAT):", binaryData and #binaryData or 0)
    local ts = os.epoch("utc")
    local open = fs.open
    for i = 1, times do
        f = open("test/binary_fast_test.bin","wb")
        f.write(binaryData)
        f.close()
    end
    print("FILE WRITE TIME:" , os.epoch("utc") - ts)
    local ts = os.epoch("utc")
    local restoredChunk
    for i = 1, times do
        restoredChunk = unbinarize(binaryData)
    end
    print("UNBINARIZE TIME:" , os.epoch("utc") - ts)
    
end



local function testBinarizeRuns(times)
    local ts = os.epoch("utc")
    local binaryData
    for i = 1, times do
        binaryData = binarizeRuns(chunk)
    end
    print(os.epoch("utc") - ts, "BINARY DATA LENGTH:", binaryData and #binaryData or 0)
    local ts = os.epoch("utc")
    for i = 1, times do
        f = fs.open("test/binary_test.bin","w")
        f.write(binaryData)
        f.close()
    end


end

-- SERIALIZE
local function testSerialize(times)
    local ts = os.epoch("utc")
    local serializedData
    for i = 1, times do
        serializedData = simpleSerialize(chunk)
    end
    print(os.epoch("utc") - ts, "SERIALIZED DATA LENGTH:", serializedData and #serializedData or 0)
    local ts = os.epoch("utc")
    for i = 1, times do
        f = fs.open("test/serialized_test.txt","w")
        f.write(serializedData)
        f.close()
    end
    print("FILE WRITE TIME:" , os.epoch("utc") - ts)
    local ts = os.epoch("utc")
    local restoredChunk
    for i = 1, times do
        restoredChunk = unserialize(serializedData)
    end
    print("UNSERIALIZE TIME:" , os.epoch("utc") - ts)
end


local serializeDefault = textutils.serialize
local function testSerializeDefault(times)
    local ts = os.epoch("utc")
    local serializedData
    for i = 1, times do
        serializedData = serializeDefault(chunk)
    end
    print(os.epoch("utc") - ts, "SERIALIZED DATA LENGTH (DEFAULT):", serializedData and #serializedData or 0)
    local ts = os.epoch("utc")
    for i = 1, times do
        f = fs.open("test/serialized_default_test.txt","w")
        f.write(serializedData)
        f.close()
    end
    print("FILE WRITE TIME:" , os.epoch("utc") - ts)
end


local times = 1000
testBinarize(times)
testSerialize(times)
--testBinarizeRuns(times)
testSerializeDefault(times)


