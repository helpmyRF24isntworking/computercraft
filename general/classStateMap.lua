
require("classChunkyMap")

local default =  {

}

-- a map for temporary mapping with detailed information
-- contains full data about blocks and time of inspection / mining

local osEpoch = os.epoch
local tableinsert = table.insert

StateMap = {}

function StateMap:new()
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	
	-- Function Caching
    for k, v in pairs(self) do
        if type(v) == "function" then
            o[k] = v  -- Directly assign method to object
        end
    end
	
	o.chunks = {}
	o.chunkCount = 0
	o.log = {}
	
	o:initialize()
	return o
end

function StateMap:initialize()
	
end

local xyzToChunkId = ChunkyMap.xyzToChunkId
local xyzToRelativeChunkId = ChunkyMap.xyzToRelativeChunkId

function StateMap:accessChunk(chunkId)
	local chunk = self.chunks[chunkId]
	if not chunk then
		chunk = {}
		self.chunks[chunkId] = chunk
		self.chunkCount = self.chunkCount + 1
	end
	return chunk
end

function StateMap:setChunkData(chunkId,relativeId,data)
	local chunk = self:accessChunk(chunkId)
	if chunk then
		chunk[relativeId] = data
	end
end

function StateMap:setData(x,y,z,data,mined)
	--nil = not yet inspected
	--0 = inspected but empty or mined

	local chunkId = xyzToChunkId(x,y,z)
	local relativeId = xyzToRelativeChunkId(x,y,z)

	local time = osEpoch()
	if data == 0 or not data.name then
		data = { name = 0, time = time}
	else
		data.time = time
	end

	data.mined = mined -- flag if block was mined and is thus air now, or it was inspected and found to be air

	local chunk = self:accessChunk(chunkId)
	if chunk and chunk[relativeId] ~= data then
		tableinsert(self.log,{chunkId,relativeId,data})
		chunk[relativeId] = data
	end
end

function StateMap:getData(x,y,z)
	local chunk = self:accessChunk(xyzToChunkId(x,y,z))
	if chunk then 
		return chunk[xyzToRelativeChunkId(x,y,z)]
	end
	return nil
end

function StateMap:getBlockName(x,y,z)

	local chunk = self:accessChunk(xyzToChunkId(x,y,z))
	if chunk then 
		local data = chunk[xyzToRelativeChunkId(x,y,z)]
		if data then
			return data.name
		end

	end
	return nil
end

function StateMap:reconstructMapAtTime(time)

	-- special function to get a theoretical map at time x

	-- e.g. leaf was inspected at time 7 
	-- currently only 1 log is known to exist at time 7
	-- however by time 10, 3 more logs have been inspected and mined
	-- we want to build a map for time 7 but also including the logs that were discovered later

	-- for this we use the log, to rebuild the map at time x and also include blocks
	-- discovered in the furture
    
    local reconstructed = StateMap:new()
    
    -- Replay log entries chronologically up to time
    for i = 1, #self.log do
        local entry = self.log[i]
        local chunkId, relativeId, data = entry[1], entry[2], entry[3]

		-- include this block if:
        -- 1. It was a solid block (not air/mined) at any point
        -- 2. OR it was explicitly set to 0/nil before time
        
        if data.name and ( data.name ~= 0 or not data.mined ) then
            -- Solid block discovered at any time - we assume it also existed at time 
            reconstructed:setChunkData(chunkId, relativeId, data)
        elseif data.time <= time then
            -- Block was confirmed empty/mined by time
            reconstructed:setChunkData(chunkId, relativeId, data)
        end
    end
    return reconstructed

end

function StateMap:getTimedData(x,y,z, time)
    -- Get block state at a specific time, including blocks discovered later
    -- Returns the most recent data for this position following the reconstruction rules
    
    local chunkId = xyzToChunkId(x,y,z)
    local relativeId = xyzToRelativeChunkId(x,y,z)
    
    local blockData = nil
    
    -- Scan through log entries for this position
    for i = 1, #self.log do
        local entry = self.log[i]
        local logChunkId, logRelativeId, logData = entry[1], entry[2], entry[3]
        
        if logChunkId == chunkId and logRelativeId == relativeId then
            if logData.name and logData.name ~= 0 then
                -- Found a solid block - keep the most recent one
                blockData = logData
            elseif logData.time <= time then
                -- Found an empty/mined block before target time
                blockData = logData
            end
        end
    end

	return blockData
end



function StateMap:reconstructMapAtTimeBackwards(time)
    -- special function to get a theoretical map at time x
    -- Works backwards from current state, removing changes that happened after time

    -- e.g. leaf was inspected at time 7 
    -- currently only 1 log is known to exist at time 7
    -- however by time 10, 3 more logs have been inspected and mined
    -- we want to build a map for time 7 but also including the logs that were discovered later

    local reconstructed = StateMap:new()
    local reconstructedChunks = reconstructed.chunks
    -- Copy current state
    for chunkId, chunk in pairs(self.chunks) do
		local copyChunk = {}
        reconstructedChunks[chunkId] = copyChunk
        for relativeId, data in pairs(chunk) do
            copyChunk[relativeId] = data
        end
    end
    reconstructed.chunkCount = self.chunkCount
    
    -- Work backwards through log, removing entries that happened after time
    -- and were empty/mined (solid blocks stay because they existed at time)
    for i = #self.log, 1, -1 do
        local entry = self.log[i]
        local chunkId, relativeId, data = entry[1], entry[2], entry[3]
        
        -- If this change happened after target time
        if data.time > time then
            -- Only overwrite if it was an empty/mined block (name == 0)
            -- Solid blocks discovered after time still existed at time
            if not data.name or data.name == 0 then
                local chunk = reconstructedChunks[chunkId]
                if chunk then
                    chunk[relativeId] = nil
                end
            end
        else
            -- Once we reach entries at or before time, we're done
            -- (log is chronological)
            break
        end
    end
    
    return reconstructed
end

function StateMap:clearLog()
	self.log = {}
end

function StateMap:clear()
	self.chunks = {}
	self:clearLog()
end

return StateMap