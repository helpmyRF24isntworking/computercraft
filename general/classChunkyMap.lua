
local translation = require("blockTranslation")
local nameToId = translation.nameToId
local idToName = translation.idToName

local utilsSerialize = require("utilsSerialize")
local binarize = utilsSerialize.binarize
local unbinarize = utilsSerialize.unbinarize

local default =  {
	bedrockLevel = -60,
	-- folder = "runtime/map/chunks/",
	-- folder = "test/map/multichunks/",
	folder = "runtime/map/multichunks/",
	minHeight = -64,
	maxHeight = 320,
	maxFindDistance = 32,
	
	chunkSize = 16,
	maxChunks = 27, --3x3x3
	lifeTime = 72000*60*1,
	clearPercentage = 0.25,
	inMemory = false,
	saveInterval = 72000*20,
}

local maxIndex = default.chunkSize^3
local chunkSize = default.chunkSize
local chunkOffsetY = math.ceil(64/default.chunkSize)
local chunkOffsetX = math.ceil(448/default.chunkSize)
local chunkOffsetZ = math.ceil(896/default.chunkSize)

-- efficient storage, not memory though: https://github.com/Fatboychummy-CC/Simplify-Mapping/blob/main/mapping/file_io.lua

-- for performance perhaps
local osEpoch = os.epoch -- do not use "local" -> worse performance
local floor = math.floor
local sqrt = math.sqrt
local sqSize = default.chunkSize^2
local tableinsert = table.insert

local ChunkyMap = {}
ChunkyMap.__index = ChunkyMap

function ChunkyMap:new(inMemory)
	local o = o or {}
	setmetatable(o, self)
	
	-- Function Caching
    for k, v in pairs(self) do
        if type(v) == "function" then
            o[k] = v  -- Directly assign method to object
        end
    end
	
	o.chunks = {}
	o.chunkLogs = {}
	o.chunkCount = 0
	o.recentOres = {}
	
	o.lastCleanup = 0
	o.lastSave = 0
	o.saveInterval = default.saveInterval

	o.fileLastSave = {}
	o.fileSaveCount = {} -- to track how often a chunk was used
	o.fileHandles = {}
	o.handleCount = 0
	o.handleReuseCount = 0
	o.reusedFiles = {}
	o.maxHandles = 96 -- computer maximum of 128
	
	o.inMemory = inMemory or default.inMemory
	
	o.maxChunks = default.maxChunks
	o.lifeTime = default.lifeTime
	o.cleanInterval = default.lifeTime
	
	o.minedAreas = {} --TODO
	o.log = {}

	o.checkOreBlock = function() return false end
	
	-- list of turtles: function: getNearestTurtle 
	
	o:initialize()
	return o
end


-- pseudo function for requesting a chunk from somewhere else
-- optional: request multiple chunks in one message
-- function ChunkyMap:requestChunk(chunkId) end
-- function ChunkyMap:onUnloadChunk(chunkId) end


function ChunkyMap:initialize()
	--self:load()
	-- perhaps local
	-- self.chunkOffsetY = math.ceil(64/default.chunkSize)
	-- self.chunkOffsetX = math.ceil(448/default.chunkSize)
	-- self.chunkOffsetZ = math.ceil(896/default.chunkSize)
	
	self:setLifeTime(default.lifeTime)
end

function ChunkyMap:setMaxChunks(maxChunks)
	self.maxChunks = maxChunks
end
function ChunkyMap:setLifeTime(lifeTime)
	self.lifeTime = lifeTime
	self.cleanInterval = floor(self.lifeTime/2)
end
function ChunkyMap:setSaveInterval(saveInterval)
	self.saveInterval = saveInterval
end

function ChunkyMap:setCheckFunction(func)
	self.checkOreBlock = func
end


function ChunkyMap.xyzToChunkId(x,y,z)
	-- returns the chunkId for the position

	local cx,cy,cz = floor(x / chunkSize), 
			floor(y / chunkSize), 
			floor(z / chunkSize)
	
	if cx < 0 then 
		cx = -cx 
		cy = cy + chunkOffsetX
	end
	if cz < 0 then 
		cz = -cz 
		cy = cy + chunkOffsetZ
	end
	cy = cy + chunkOffsetY
	
	local cxcy = cx + cy
	local temp = 0.5 * cxcy * ( cxcy + 1 ) + cy
	local tempcz = temp + cz
	return 0.5 * tempcz * ( tempcz + 1 ) + cz 
end
local xyzToChunkId = ChunkyMap.xyzToChunkId


function ChunkyMap.xyzToRelativeChunkPos(x,y,z)
	-- returns the relative position within a chunk
	return x % chunkSize, y % chunkSize, z % chunkSize
end
local xyzToRelativeChunkPos = ChunkyMap.xyzToRelativeChunkPos

function ChunkyMap.posToRelativeChunkPos(pos)
	return xyzToRelativeChunkPos(pos.x, pos.y, pos.z)
end
local posToRelativeChunkPos = ChunkyMap.posToRelativeChunkPos

function ChunkyMap.xyzToRelativeChunkId(x,y,z)
	-- local rcx, rcy, rcz = x % default.chunkSize, y % default.chunkSize, z % default.chunkSize
	-- local temp = 0.5 * ( rcx + rcy ) * ( rcx + rcy + 1 ) + rcy
	-- return 0.5 * ( temp + rcz ) * ( temp + rcz + 1 ) + rcz 
	
	local rcx, rcy, rcz = x % chunkSize, y % chunkSize, z % chunkSize
	return rcx + rcz * chunkSize + rcy * sqSize + 1 -- so we start at 1
end
local xyzToRelativeChunkId = ChunkyMap.xyzToRelativeChunkId

function ChunkyMap.undoCantorPairing(id)
	-- undo cantor pairing
	local w = floor( ( sqrt( 8 * id + 1 ) - 1 ) / 2 )
	local t = ( w^2 + w ) / 2
	local z = id - t
	local temp = w - z
	
	w =  floor( ( sqrt( 8 * temp + 1 ) - 1 ) / 2 )
	t = ( w^2 + w ) / 2
	local y = temp - t
	local x = w - y
	
	return x,y,z
end
local undoCantorPairing = ChunkyMap.undoCantorPairing

function ChunkyMap.relativeIdToXYZ(id)
	-- return undoCantorPairing(id)
	local y = floor((id-1)/sqSize)
	local z = floor((id-1-y*sqSize)/chunkSize)
	local x = id -1 - z*chunkSize - y*sqSize
	return x,y,z
end
local relativeIdToXYZ = ChunkyMap.relativeIdToXYZ

function ChunkyMap.chunkIdToXYZ(chunkId)
	local x,y,z = undoCantorPairing(chunkId)
	-- restore negative coordinates
	if y > chunkOffsetX then
		-- x or z negative
		if y > chunkOffsetZ then 
			-- z negative
			z = -z
			y = y - chunkOffsetZ
		end
		if y > chunkOffsetX then
			-- x negative
			x = -x
			y = y - chunkOffsetX
		end
	end
	y = y - chunkOffsetY
	
	return x*chunkSize,y*chunkSize,z*chunkSize
end
local chunkIdToXYZ = ChunkyMap.chunkIdToXYZ

function ChunkyMap.idsToXYZ(chunkId, relativeId)
	local cx,cy,cz = chunkIdToXYZ(chunkId)
	local rcx, rcy, rcz = relativeIdToXYZ(relativeId)
	return cx + rcx, cy + rcy, cz + rcz
end
local idsToXYZ = ChunkyMap.idsToXYZ

function ChunkyMap.xyzToId(x,y,z)
	-- dont use string IDs for Tables, instead use numbers  
	-- Cantor pairing - natural numbers only to make it reversable
	
	--default.maxHeight - default.minHeight + 64
	
	--max length of id = 16 (then its 1.234234e23)
	-- x,y,z can be up to around 10000,320,10000
	-- if this is ever an issue, set the coordinates of turtles relative to their home
	
	if x < 0 then 
		x = -x 
		y = y + 448 
	end
	if z < 0 then 
		z = -z 
		y = y + 896 
	end
	y = y + 64 -- default.minHeight
	--------------------------------------------------------
	local temp = 0.5 * ( x + y ) * ( x + y + 1 ) + y
	return 0.5 * ( temp + z ) * ( temp + z + 1 ) + z 
	--------------------------------------------------------
end
local xyzToId = ChunkyMap.xyzToId

function ChunkyMap:save()
	for id,chunk in pairs(self.chunks) do
		self:saveChunk(id)
	end
end


function ChunkyMap:closeAllHandles()
	for fileId, handle in pairs(self.fileHandles) do
		handle.close()
		self.fileHandles[fileId] = nil
	end
	self.handleCount = 0
end

function ChunkyMap:getHandlePriority(fileId)
	local saveCount = self.fileSaveCount[fileId] or 0
	local lastSave = self.fileLastSave[fileId] or 0
	local time = osEpoch() - lastSave

	-- combines save frequency and recency, save frequency is preferred
	local decayFactor = math.max(0, 1 - ( time / self.saveInterval * 10 )) -- 30 save intervals to decay to 0
	return saveCount * decayFactor
end

function ChunkyMap:decayHandlePriorities()
	local fileSaveCount = self.fileSaveCount
	for fileId, saveCount in pairs(fileSaveCount) do
		saveCount = saveCount * 0.933 -- x/2 each 10 saves
		fileSaveCount[fileId] = saveCount
	end
end

function ChunkyMap:closeLeastValuableHandle()
	local leastPriority = math.huge
	local minId = nil
	local fileHandles = self.fileHandles
	
	for fileId,_ in pairs(fileHandles) do
		local priority = self:getHandlePriority(fileId)
		if priority < leastPriority then
			leastPriority = priority
			minId = fileId
		end
	end
	
	if minId then
		local handle = fileHandles[minId]
		if handle then
			handle.close()
			fileHandles[minId] = nil
			self.handleCount = self.handleCount - 1
		end
	end
end

function ChunkyMap:getFileHandle(fileId)
	local isNewFile = false
	local fileHandles = self.fileHandles
	local handle, reason = fileHandles[fileId], nil
	if not handle then
		if self.handleCount >= self.maxHandles then
			self:closeLeastValuableHandle()
		end
		local path = default.folder .. fileId .. ".bin"
		handle, reason = fs.open(path,"r+")
		if not handle then 
			handle, reason = fs.open(path,"w+")
			isNewFile = true
		end
		if not handle then
			print("UNABLE TO OPEN FILE HANDLE", fileId, reason)
		end
		fileHandles[fileId] = handle
		self.handleCount = self.handleCount + 1
	else
		self.reusedFiles[fileId] = true
		self.handleReuseCount = self.handleReuseCount + 1
	end
	
	self.fileLastSave[fileId] = osEpoch()
	self.fileSaveCount[fileId] = (self.fileSaveCount[fileId] or 0) + 1
	
	return handle, isNewFile
end


local chunkWidthPerFile = 3 -- 3x3x3 chunks per file
local maxChunksPerFile = chunkWidthPerFile^3
local headDescrLen = 9
local headDescrFormat = "<I1I2I2I4" -- idLength, idsCount, maxCount, fileLength
local subHeadLen = 18
local subHeadFormat = "I6I4I4I4" 	-- id, startPos, length, padding

function ChunkyMap:readChunk(chunkId)
	local fileId = self:chunkIdToFileId(chunkId)
	local handle = fs.open(default.folder .. fileId .. ".bin", "r")
	-- we could hold the handle as long as we have space in cache 

	if handle then
		-- read header 
		local headerDescr = handle.read(headDescrLen)
		local subHeadLen, subHeadCount, maxCount, fileLength = string.unpack(headDescrFormat, headerDescr, 1)
		if maxCount ~= maxChunksPerFile then
			error("WARNING: unexpected max chunk count " .. maxCount .. " expected " .. maxChunksPerFile)
		end

		local headerData = handle.read(subHeadLen * subHeadCount)
		local format = "<" .. string.rep(subHeadFormat, subHeadCount)
		local headerTab = {string.unpack(format, headerData, 1)}

		if fs.getSize(default.folder .. fileId .. ".bin") ~= fileLength then
			print("FILE SIZE MISMATCH", fileId, "fsSize", fs.getSize(default.folder .. fileId .. ".bin"), "fileLength", fileLength)
			sleep(30000)
		end

		--print("HEADDESCR", "hdlen", subHeadLen, "hdcount", subHeadCount, "maxCount", maxCount, "filelen", fileLength)
		for i = 1, subHeadCount do
			local hdId = (i-1)*4 + 1
			local id = headerTab[hdId]
			-- print("SUBHEAD", "id", id, "startPos", headerTab[hdId + 1], "length", headerTab[hdId + 2], "pad", headerTab[hdId + 3])
			if id == chunkId then
				
				-- found existing chunk entry
				local startPos = headerTab[hdId + 1]
				local len = headerTab[hdId + 2]
				local padding = headerTab[hdId + 3]
				handle.seek("set", startPos)
				local chunkData = handle.read(len)
				handle.close()
				print("READ CHUNK", chunkId, "start", startPos, "len", len, "pad", padding, "FROM FILE", fileId, "readLen", chunkData and #chunkData)
				local chunk = unbinarize(chunkData)
				-- print("READ CHUNK", chunkId, "start", startPos, "len", len, "pad", padding, "FROM FILE", fileId)
				return chunk
			end
		end
	else
		print("FILE", fileId, "FOR CHUNK", chunkId, "NOT FOUND")
		return nil
	end
end

local log

function ChunkyMap:saveChunk(chunkId)

	local ok,err = pcall(function()

	local fileId = self:chunkIdToFileId(chunkId)
	local handle, isNewFile = self:getFileHandle(fileId)
	local chunkData = binarize(self.chunks[chunkId], maxIndex)
	local len = #chunkData

	local minPadding = 256
	local paddingFactor = 0.15
	local pad_byte = string.char(0xFF)

	if not log then
		log = fs.open("save_log.txt", "a")
		log.writeLine("---- NEW LOG ----")
	end

	if isNewFile then
		local subHeadCount = 1
		local fileLength = headDescrLen + subHeadLen * maxChunksPerFile + len
		local headerDescr = string.pack(headDescrFormat, subHeadLen, subHeadCount, maxChunksPerFile, fileLength)
		handle.seek("set", 0)
		handle.write(headerDescr)
		local padding = 0
		local startPos = headDescrLen + subHeadLen * maxChunksPerFile
		local headerData = string.pack("<" .. subHeadFormat, chunkId, startPos, len, padding)
		headerData = headerData .. string.rep(pad_byte, subHeadLen * (maxChunksPerFile - 1)) -- fill rest of header
		handle.write(headerData)
		handle.seek("set", startPos)
		handle.write(chunkData)
		-- print("SAVED NEW CHUNK", chunkId, "len", len, "padding", padding, "TO NEW FILE", fileId, "len", fileLength)
		handle.flush()
		return
	else

		-- read header
		-- format: idLength, idsCount, fileLength { id, startPos, length, padding } ...  , )
		handle.seek("set", 0)
		local headerDescr = handle.read(headDescrLen)
		local subHeadLen, subHeadCount, maxCount, fileLength = string.unpack(headDescrFormat, headerDescr, 1)
		print("HEADERS:", "subHeadLen", subHeadLen, "subHeadCount", subHeadCount, "maxCount", maxCount, "fileLength", fileLength)
		if maxCount ~= maxChunksPerFile then
			error("WARNING: unexpected max chunk count " .. maxCount .. " expected " .. maxChunksPerFile)
		end
	
		if fileLength ~= fs.getSize(default.folder .. fileId .. ".bin") then
			handle.seek("set", 0)
			local all = handle.readAll()
			print("slight mismatch", fileId, "all", #all, "fileLength", fileLength, "fsSize", fs.getSize(default.folder .. fileId .. ".bin"))

			-- fileLength = #all -- maybe this works? not really true though

			--sleep(30000)
			-- error("WARNING: file length mismatch in chunk file " .. fileId .. ", expected " .. fileLength .. " got " .. fs.getSize(default.folder .. fileId .. ".bin"))
		end

		handle.seek("set", headDescrLen) -- optional
		local headerData = handle.read(subHeadLen * subHeadCount)
		local format = "<" .. string.rep(subHeadFormat, subHeadCount)
		-- print("format", format, "#headerData", #headerData)
		local headerTab = {string.unpack(format, headerData, 1)}
		headerTab[#headerTab] = nil -- remove index entry
		
		local fileSize = fs.getSize(default.folder .. fileId .. ".bin")
		print("file", fileId, "size", fileSize, "fileLength", fileLength)

		for i = 1, subHeadCount do
			local hdId = (i-1)*4 + 1
			local id = headerTab[hdId]

			print(i, "/", subHeadCount, "SUBHEAD", "id", id, "start", headerTab[hdId + 1], "length", headerTab[hdId + 2], "pad", headerTab[hdId + 3])

			if id == chunkId then
				-- found existing chunk entry
				local startPos = headerTab[hdId + 1]
				local oldLen = headerTab[hdId + 2]
				local padding = headerTab[hdId + 3]
				
				print("SUBHEAD", "id", id, "startPos", headerTab[hdId + 1], "length", headerTab[hdId + 2], "pad", headerTab[hdId + 3], "dataLen", len)
				local ofl = fileLength

				if len <= ( oldLen + padding ) or i == subHeadCount then

					-- can overwrite in place
					-- rewrite header
					-- need to also update length if its the last one
					
					local newPadding = oldLen + padding - len

					if i == subHeadCount then
						if newPadding < 0 then newPadding = 0 end 
						fileLength = fileLength - oldLen - padding + len + newPadding
						headerDescr = string.pack(headDescrFormat, subHeadLen, subHeadCount, maxCount, fileLength)
						handle.seek("set", 0)
						handle.write(headerDescr)
					end

					headerTab[hdId + 2] = len
					headerTab[hdId + 3] = newPadding

					print("newPadding", newPadding, " -> len", len, "<=", oldLen + padding, "fileLength", fileLength, "ofl", ofl, "#hdTab", #headerTab) --, "hd", textutils.serialize(headerTab))
					handle.seek("set", headDescrLen)
					local newHeaderData = string.pack(format, table.unpack(headerTab))
					handle.write(newHeaderData)
					-- overwrite chunk data
					handle.seek("set", startPos)
					handle.write(chunkData)
					-- print("OVERWROTE CHUNK", chunkId, "len", len, "pad", headerTab[hdId + 3], "oldLen", oldLen, "oldPad", padding, "IN FILE", fileId, "len", fileLength)
					handle.flush()

					local nfl = fs.getSize(default.folder .. fileId .. ".bin")
					if fileLength ~= nfl or fileLength < 0 then
						print(i, "/", subHeadCount, "SIZE MISMATCH", "fileLen", fileLength, "old", ofl, "new", nfl, "fileId", fileId)
						sleep(30000)
					end

					return
				else
					-- SOMEWHERE WE MESS UP CALCULATING THE FILELENGTH BADLY
					-- need to shift chunks that come after this one
					-- read rest of file
					print("i", i, "subHeadCount", subHeadCount, "fileLen", fileLength, "fileSize", fileSize)
					local nextPos = startPos + oldLen + padding
					local toRead = fileSize - nextPos
					--local toRead = fileLength - nextPos

					if toRead < 0 then 
						handle.seek("set", 0)
						local all = handle.readAll()
						print("slight mismatch", fileId, "all", #all, "fileLength", fileLength, "fsSize", fs.getSize(default.folder .. fileId .. ".bin"))

						print("readlen", toRead, "filelen", fileLength, "nextpos", nextPos, "start", startPos, "oldLen", oldLen, "padding", padding, "chunkId", chunkId, "fileId", fileId)
						print("EEEEEEEEERRRRRRRROR")
						sleep(30000)
					end

					-- read remaining data if exists (chunks can be "" at eof)
					local restData
					if toRead > 0 then
						handle.seek("set", nextPos)
						restData = handle.read(toRead)
					end

					-- write data and add some new padding to reduce future shifts
					-- maxBytes = maxIndex * ~4, though usually much less
					local newPadding = math.max(minPadding, math.floor(len * paddingFactor))
					handle.seek("set", startPos)
					handle.write(chunkData)

					-- no need to actually write padding bytes -- though it is nice for comparing fs.size with fileLength
					handle.write(string.rep(pad_byte, newPadding))

					if restData then 
						handle.seek("set", startPos + len + newPadding)
						handle.write(restData)
					end

					local offset = ( len + newPadding) - ( oldLen + padding )

					-- update header
					headerTab[hdId + 2] = len
					headerTab[hdId + 3] = newPadding
					-- shift following chunks
					for k = i+1, subHeadCount do
						local hdId2 = (k-1)*4 + 1

						print(k, "/", subHeadCount, "SHIFTING SUBHEAD", "id", headerTab[hdId2], "oldStart", headerTab[hdId2 + 1], "newStart", headerTab[hdId2 + 1] + offset, "length", headerTab[hdId2 + 2], "pad", headerTab[hdId2 + 3])
						headerTab[hdId2 + 1] = headerTab[hdId2 + 1] + offset
					end
					local newFileLength = fileLength + offset
					headerDescr = string.pack(headDescrFormat, subHeadLen, subHeadCount, maxCount, newFileLength)
					handle.seek("set", 0)
					handle.write(headerDescr)
					local newHeaderData = string.pack(format, table.unpack(headerTab))
					handle.write(newHeaderData)
					print("SHIFTED AFTER CHUNK", chunkId, "pos", startPos, "len", len, "pad", newPadding, "oldLen", oldLen, "oldPad", padding, "restLen", restData and #restData, "toRead", toRead, "off", offset, "IN FILE", fileId, "len", newFileLength)
					handle.flush()

					local nfl = fs.getSize(default.folder .. fileId .. ".bin")
					if newFileLength ~= nfl or newFileLength < 0 then
						print(i, "/", subHeadCount, "SIZE MISMATCH 2", "fileLen", newFileLength, "old", ofl, "new", nfl, "fileId", fileId)
						sleep(30000)
					end
					return
				end
			end
		end
		
		local ofl = fileLength
		if true then
			-- add padding to previous last chunk
			local lastHdId = (subHeadCount -1) * 4 + 1
			local lastPadding = headerTab[lastHdId + 3]
			-- if lastPadding < 0 then lastPadding = 0 end not needed
			local lastLen = headerTab[lastHdId + 2]
			local neededPad = math.max(minPadding - lastPadding, math.floor(lastLen * paddingFactor) - lastPadding)
			if neededPad > 0 then 
				-- physically write new padding
				handle.seek("set", fileLength)
				handle.write(string.rep(pad_byte, neededPad))
				fileLength = fileLength + neededPad
				headerTab[lastHdId + 3] = lastPadding + neededPad
			end
		end

		-- new chunk entry at eof
		subHeadCount = subHeadCount + 1
		local newFileLength = fileLength + len
		headerDescr = string.pack(headDescrFormat, subHeadLen, subHeadCount, maxCount, newFileLength)
		handle.seek("set", 0)
		handle.write(headerDescr)

		local newStartPos = fileLength
		local hdId = (subHeadCount - 1) * 4 + 1
		headerTab[hdId] = chunkId
		headerTab[hdId + 1] = newStartPos
		headerTab[hdId + 2] = len
		headerTab[hdId + 3] = 0 -- no padding at eof
		
		print(table.unpack(headerTab))
		print("subheadCount", subHeadCount, "len", len, "chunkId", chunkId, "fileId", fileId)
		print("startPos", newStartPos, "newFileLength", newFileLength)
		for k, v in pairs(headerTab) do
			if k % 4 == 1 then
				print(k, "/", subHeadCount, "SUBHEAD", "id", headerTab[k], "start", headerTab[k + 1], "length", headerTab[k + 2], "pad", headerTab[k + 3])
			end
			if v < 0 then 
				
				print("NEGATIVE VALUE", k, v)
				sleep(30000)
			end
		end
		format = format .. subHeadFormat
		local newHeaderData = string.pack(format, table.unpack(headerTab))
		handle.write(newHeaderData)		

		handle.seek("set", newStartPos)
		handle.write(chunkData)
		-- print("ADDED NEW CHUNK", chunkId, "len", len, "padding", 0, "TO FILE", fileId, "len", newFileLength)
		handle.flush()

		local nfl = fs.getSize(default.folder .. fileId .. ".bin")
		if newFileLength ~= nfl or newFileLength < 0 then
			print(i, "/", subHeadCount, "SIZE MISMATCH 2", "fileLen", newFileLength, "old", ofl, "new", nfl, "fileId", fileId)
			sleep(30000)
		end
	end

	end)
	if not ok then
		print(textutils.serialize(err))
		print("ERROR SAVING CHUNK", chunkId, ":", err)
		sleep(30000)
	end
	
end

-- TODO: if bored: create chunks of chunks to reduce file handle usage
-- e.g. 3x3x3 chunks saved in one file, using file.seek to access individual chunks
-- but this requires rewriting the whole rest of file when one chunk changes 
-- (at least if it takes more space than before, could add padding between chunks
--  -> rewrite is only needed if pad is exceeded to shift chunks coming afterwards )
-- DONE :D -> this not yet though
-- also: keep a logfile opened for very sudden crashes, which we can read from on startup
-- to replay and have the best possible consistency

function ChunkyMap:chunkIdToFileId(chunkId)
	-- for chunk of chunks file storage
	local x,y,z = chunkIdToXYZ(chunkId)
	local aggregatedSize = chunkSize * chunkWidthPerFile
	local cx, cy, cz = floor(x / aggregatedSize), 
			floor(y / aggregatedSize), 
			floor(z / aggregatedSize)

	if cx < 0 then 
		cx = -cx 
		cy = cy + chunkOffsetX
	end
	if cz < 0 then 
		cz = -cz 
		cy = cy + chunkOffsetZ
	end
	cy = cy + chunkOffsetY
	
	local cxcy = cx + cy
	local temp = 0.5 * cxcy * ( cxcy + 1 ) + cy
	local tempcz = temp + cz
	return 0.5 * tempcz * ( tempcz + 1 ) + cz
end

function ChunkyMap:saveChanged()
	-- save all chunks that might have been changed

	if not self.inMemory then
		self.handleReuseCount = 0
		local start = osEpoch("local")
		local ct = 0

		-- prioritize chunks that have open write handles
		local saveLater = {}
		for id,chunk in pairs(self.chunks) do
			if chunk._lastChange > self.lastSave then
				if self.fileHandles[id] then
					self:saveChunk(id)
					ct = ct + 1
				else 
					tableinsert(saveLater, id)
				end
			end
		end

		os.queueEvent("yield")
		os.pullEvent("yield")

		for i = 1, #saveLater do
			local id = saveLater[i]
			self:saveChunk(id)
			ct = ct + 1
			if i % 20 == 0 then 
				-- sleep instead of yield to actually give others time to catch up?
				os.queueEvent("yield")
				os.pullEvent("yield")
			end
		end

		self:decayHandlePriorities()
		self.lastSave = osEpoch()

		local filesReused = 0
		for fileId, _ in pairs(self.reusedFiles) do filesReused = filesReused + 1; self.reusedFiles[fileId] = nil end

		print("saved", ct, "/", self.chunkCount, "chunks, for", self.handleReuseCount, "chunks reused", filesReused, "/", self.maxHandles, "handles", osEpoch("local") - start, "ms")
	end
end

function ChunkyMap:load()
	-- chunks are loaded on demand
end

function ChunkyMap:loadChunk(chunkId)
	-- could use fs.list to check existence efficiently

	local result = false
	self:cleanCache()
	--print(textutils.serialize(debug.traceback()))
	local chunk
	if not self.inMemory then 

		chunk = self:readChunk(chunkId)
		self.chunks[chunkId] = chunk

	else
		if self.requestChunk then 
			chunk = self.requestChunk(chunkId)
			self.chunks[chunkId] = chunk
		end
	end
	if chunk then
		self.chunkCount = self.chunkCount + 1
		chunk._accessCount = 0
		chunk._lastAccess = osEpoch()
		chunk._lastChange = 0
		chunk.locked = false
		result = true
	end
	return result
end

-- TODO: Optimization: keep latest chunk in latestChunk, to reduce accessChunk calls
--		 only keep it while chunkId stays unchanged
-- 		 Increment accessCount and lastAccess in getData/setData

function ChunkyMap:accessChunk(chunkId,writing,realAccess)

	local chunk = self.chunks[chunkId]
	if not chunk then
		if realAccess then -- only real accesses are allowed to load chunks
			if not self:loadChunk(chunkId) then
				--if writing then 
					self.chunks[chunkId] = {}
					self.chunkCount = self.chunkCount + 1
					chunk = self.chunks[chunkId]
					chunk._accessCount = 0
					chunk._lastAccess = osEpoch()
					chunk._lastChange = 0
					chunk.locked = false
				--end
			else
				chunk = self.chunks[chunkId]
			end
		end
	end

	if chunk then 
		local time = osEpoch()
		if realAccess then
			--accessCount should not rise if set externally
			chunk._accessCount = (chunk._accessCount or 0) + 1
			chunk._lastAccess = time
		end
		if writing then
			chunk._lastChange = time
		end
	end
	-- self.currentChunk = chunk 
	-- self.currentChunkId = chunkId
	return chunk
end

function ChunkyMap:logChunkData(chunkId,rcx,rcy,rcz,data)
	if not self.chunkLogs[chunkId] then self.chunkLogs[chunkId] = {} end
	tableinsert(self.chunkLogs[chunkId],{x=rcx,y=rcy,z=rcz,data=data})
end

function ChunkyMap:logData(x,y,z,data)
	-- depricated
	--tableinsert(self.log,{x=x,y=y,z=z,data=data})
	-- TODO: check if chunkwise logging is needed?
	-- perhaps for the host to distribute updates
	--> easier to set data if chunkId and relative position is already known
	
	-- local chunkId = self:xyzToChunkId(x,y,z)
	-- local rcx, rcy, rcz = self:xyzChunkRelative(x,y,z)
	-- self:logChunkData(chunkId, rcx,rcy,rcz,data)
end

function ChunkyMap:setChunkData(chunkId,relativeId,data,real)
	-- no translation needed -> ids are known so translation should have happenend by now
	local chunk = self:accessChunk(chunkId,true,real)
	if chunk then
		
		-- no logging for setChunkData -- use setData for logging
		-- if real then tableinsert(self.log,{chunkId,relativeId,data}) end
		
		chunk[relativeId] = data
	end

	if self.lifeTime > 0 then 
		if osEpoch() - self.lastCleanup > self.cleanInterval then 
			-- to clean time based chunks while stationary
			self:cleanCache()
			self:saveChanged()
		end
	elseif not self.inMemory and osEpoch() - self.lastSave > self.saveInterval then
		self:saveChanged()
		-- could just as easily be called from the main loop -- can setup a timer for that
		-- just 1 setChunkData triggerts 2 osEpoch calls
	end
end

function ChunkyMap:setData(x,y,z,data,real)
	--nil = not yet inspected
	--0 = inspected but empty or mined

	local chunkId = xyzToChunkId(x,y,z)
	local relativeId = xyzToRelativeChunkId(x,y,z)
	local value = (nameToId[data] or data)
	
	-- remember and forget recent ores, consistency not important
	if data == 0 then
		self:forgetBlock(chunkId, relativeId)
	elseif self.checkOreBlock(data) then 
		self:rememberBlock(chunkId, relativeId, data)
	end

	-- if self.currentChunkId == chunkId then 
		-- -- skip accessChunk
		-- chunk = self.currentChunk
		-- if real then 
			-- chunk._accessCount = chunk._accessCount + 1
			-- chunk._lastAccess = osEpoch()
		-- end
	-- else
		-- chunk = self:accessChunk(chunkId,true,real)
	-- end
	
	local chunk = self:accessChunk(chunkId,true,real)
	if chunk and chunk[relativeId] ~= value then
		if real then
			tableinsert(self.log,{chunkId,relativeId,value})
		end
		chunk[relativeId] = value
	end
end

local bedrockLevel = default.bedrockLevel
function ChunkyMap:getData(x,y,z)
	if y <= bedrockLevel then
		return -1
	else
		local chunk = self:accessChunk(xyzToChunkId(x,y,z),false,true)
		if chunk then 
			--return chunk[xyzToRelativeChunkId(x,y,z)]
			local block = chunk[xyzToRelativeChunkId(x,y,z)]
			return idToName[block] or block
		end
	end
	return nil
end
ChunkyMap.getBlockName = ChunkyMap.getData


function ChunkyMap:resetChunk(chunkId)
	-- to avoid impossible path finiding tasks
	self.chunks[chunkId] = {}
end

function ChunkyMap:lockChunk(chunkId)
	-- prevent chunk from being cleared from cache
	self.chunks[chunkId].locked = true
end
function ChunkyMap:unlockChunk(chunkId)
	self.chunks[chunkId].locked = false
end	

function ChunkyMap:getLoadedChunks()
	local loadedChunks = {}
	local loadedCt = 0
	for chunkId,chunk in pairs(self.chunks) do 
		loadedCt = loadedCt + 1
		loadedChunks[loadedCt] = chunkId
	end
	return loadedChunks
end

function ChunkyMap:unloadChunk(chunkId)
	-- internal use! chunk must exist
	if not self.inMemory then
		self:saveChunk(chunkId)
	end
	self.chunks[chunkId] = nil	
	self.chunkCount = self.chunkCount - 1
	if self.onUnloadChunk then
		self.onUnloadChunk(chunkId)
	end
end

function ChunkyMap:cleanCache()
	-- remove chunks from memory and save them accordingly
	local cleared = true
	local ct = 0
	
	cleared = false
	local time = osEpoch()
	self.lastCleanup = time
	
	-- always check time based
	if self.lifeTime > 0 then
		
		for id,chunk in pairs(self.chunks) do
			if not chunk.locked then 
				if time - chunk._lastAccess > self.lifeTime then
					self:unloadChunk(id)
					cleared = true
					ct = ct + 1
				end
			end
		end
	end
		
	if self.chunkCount > self.maxChunks then
		
		if not cleared then 

			-- accesscount based
			local countTable = {}
			local deleteCount = math.ceil(self.maxChunks * default.clearPercentage)
			if deleteCount < 1 then deleteCount = 1 end
			for id,chunk in pairs(self.chunks) do
				if not chunk.locked then 
					tableinsert(countTable, { id=id, count=chunk._accessCount})
				end
				chunk._accessCount = 0
			end
			-- sort ascending by least accesses
			table.sort(countTable, function(a,b) return a.count < b.count end)
			for i=1,deleteCount do
				self:unloadChunk(countTable[i].id)
				cleared = true
				ct = ct + 1
			end
			
		end
		
	end
	if cleared then
		print("CHACHE CLEARED", ct, "LOADED", self.chunkCount)
	end
	
	return cleared
end


-- use local tables for internal use directly
function ChunkyMap:nameToId(blockName)
	-- only for external use
	return nameToId[blockName]
end
function ChunkyMap:idToName(id)
	-- only for external use, use 
	return idToName[id]
end


function ChunkyMap:getMap()
	-- used for transferring map via rednet --unused
	return { 
		chunks = self.chunks, 
		chunkCount = self.chunkCount, 
		minedAreas = self.minedAreas 
	}
end

function ChunkyMap:setMap(map)
	self.chunks = map.chunks
	self.chunkCount = map.chunkCount
	self.minedAreas = map.minedAreas
end


function ChunkyMap:readLog()
	return self.chunkLogs
end
function ChunkyMap:clearLog()
	self.chunkLogs = {}
	self.log = {}
end


function ChunkyMap:clear()
	self.chunks = {}
end


function ChunkyMap.getDistance(start,finish)
	return math.sqrt( ( finish.x - start.x )^2 + ( finish.y - start.y )^2 + ( finish.z - start.z )^2 )
end
local getDistance = ChunkyMap.getDistance


function ChunkyMap.manhattanDistance(sx,sy,sz,ex,ey,ez)
	return math.abs(ex-sx)+math.abs(ey-sy)+math.abs(ez-sz)
end
local manhattanDistance = ChunkyMap.manhattanDistance

function ChunkyMap:rememberBlock(chunkId, relativeId, blockName)
	-- internal use for remembering ores
	local recentOres = self.recentOres
	if not recentOres[chunkId] then 
		recentOres[chunkId] = {} 
	end
	recentOres[chunkId][relativeId] = blockName
end

function ChunkyMap:rememberOre(x,y,z ,blockName)
	-- external use for remembering ores
	local chunkId = xyzToChunkId(x,y,z)
	local recentOres = self.recentOres
	if not recentOres[chunkId] then
		recentOres[chunkId] = {}
	end
	recentOres[chunkId][xyzToRelativeChunkId(x,y,z)] = blockName
end

function ChunkyMap:forgetBlock(chunkId, relativeId)
	local recentOres = self.recentOres
	if recentOres[chunkId] then
		recentOres[chunkId][relativeId] = nil
	end
end

function ChunkyMap:forgetOre(x,y,z)
	local chunkId = xyzToChunkId(x,y,z)
	local recentOres = self.recentOres
	if recentOres[chunkId] then
		recentOres[chunkId][xyzToRelativeChunkId(x,y,z)] = nil
	end
end

function ChunkyMap:findNextBlock(curPos, checkFunction, maxDistance)

	if not maxDistance or maxDistance > default.maxFindDistance then 
		maxDistance = default.maxFindDistance end
	
	local start = os.epoch("local")
	local ct = 0
	local chunkCt = 0
	
	local minDist = -1
	local minPos = nil
	
	local curX = curPos.x
	local curY = curPos.y
	local curZ = curPos.z

	local sqrt = math.sqrt
	local type = type

	local minX,minY,minZ = nil,nil,nil
	
	-- check recentOres before actually scanning the map
	local minId = nil
	local recentOres = self.recentOres
	for chunkId, chunk in pairs(recentOres) do
		for relativeId, blockName in pairs(chunk) do
			if checkFunction(blockName) then
				local rcx, rcy, rcz = relativeIdToXYZ(relativeId)
				local x,y,z = chunkIdToXYZ(chunkId)
				x = x + rcx
				y = y + rcy
				z = z + rcz
				local dist = sqrt( ( x - curX )^2 + ( y - curY )^2 + ( z - curZ )^2 )
				
				ct = ct + 1
				-- print(blockName, "found", x,y,z)
								
				if ( minDist < 0 or dist < minDist) and dist <= maxDistance and dist > 0 then 
					minDist = dist
					minId = { chunkId = chunkId, relativeId = relativeId }
					minX,minY,minZ = x,y,z
				end
			end
		end
	end

	if minX and minY and minZ then
		print("FOUND RECENT", os.epoch("local") - start, "ms,", ct, "checks")
		-- table.remove(recentOres, minId)
		return vector.new(minX,minY,minZ)
	end


	--TODO: search nearest/current chunk first, then continue with next?
	-- -> could return a block that isnt actually the nearest though
	
	
	-- miner.map:findNextBlock(miner.pos,miner.checkOreBlock,30)
	
	-- test (30)
		-- noDistance, 						nothing: 		33
		-- noVector, noGetData, noCheck, 	getDistance: 	460-480
		-- vector, noGetData, 	noCheck, 	noDistance: 	min(750) 840 (max 900)
		-- vector, getData, 	noCheck, 	noDistance:		3550 max(4200)
		-- vector, noGetData, 	check, 		noDistance: 	1170 (negative check)
		-- vector, noGetData, 	noCheck, 	getDistance: 	1300
		
		
	-- -> 
		-- getData: 2710
		-- vector: 370
		-- check: 330
		-- getDistance: 460
	
	-- total expected: 3870, real: 3750 - 4200
	
	
	-- optimization: no more vector and getDistance
		-- cx,cy,cz -> 		300-350
		-- curX,curY,curZ: 	250-300
		-- local sqrt:		170-220
		
		-- getData: default 			2600-2900
		-- noTranslation: 				2000-2200 
		-- noLastAccess:				1930-2080 -> nicht wert aber als -- baseline
		-- .xyzToChunkId				1950
		-- .xyzToChunkId local floor	1850-2000
		-- local xyzToChunkId			1770-1900
		-- local xyzToRelativeChunkPos	1610-1700
		-- best case: kein access 		1450
		-- lokale impl. getData			1150-1200
		-- local xyz in function		1150-1200 -- not faster
		-- x+z*16+y*16^2 as id 			900
		-- local x+z*16+y*16^2			780
		-- local 16^2					800
		
		
	-- still 32.768 positions to be checked
	
	--local pos = vector.new(0,0,0)
	
	local sqSize = default.chunkSize^2
	local totalRange = (maxDistance*2)+1
	local halfRange = maxDistance+1
	
	local cx = curPos.x+halfRange
	local cy = curPos.y+halfRange
	local cz = curPos.z+halfRange
	

	
	-- chunk based breadth first search 
	
	local queue = {}
	local visited = {}
	local directions = {
        {default.chunkSize, 0, 0}, {-default.chunkSize, 0, 0}, 
		{0, default.chunkSize, 0}, {0, -default.chunkSize, 0}, 
		{0, 0, default.chunkSize}, {0, 0, -default.chunkSize}
    }
	
	local rcx,rcy,rcz = xyzToRelativeChunkPos(curX,curY,curZ)
	
	local halfChunk = (default.chunkSize-1)/2
	local startChunkX,startChunkY,startChunkZ = curX-rcx, curY-rcy, curZ-rcz
	local midX,midY,midZ = startChunkX+halfChunk, startChunkY+halfChunk, startChunkZ+halfChunk
	
	local minX,minY,minZ = nil,nil,nil
	
	local chunkId = xyzToChunkId(curX,curY,curZ)
	
	tableinsert(queue, {id = chunkId, mid = { midX, midY, midZ }, distance = 0 })
	visited[chunkId] = true
	
	while #queue > 0 do
		table.sort(queue, function(a, b) return a.distance < b.distance end)
		local nearest = table.remove(queue,1)
		midX, midY, midZ = nearest.mid[1],nearest.mid[2],nearest.mid[3]

		-- do stuff
		local chunk = self:accessChunk(nearest.id,false,true)
		if chunk then 
			chunkCt = chunkCt + 1
			
			local cx,cy,cz = chunkIdToXYZ(nearest.id)
			for id,block in pairs(chunk) do
				-- fully check the chunk
				ct = ct +1
				
				if checkFunction(idToName[block] or block) then -- 40 ms
					
					if type(id) == "number" then 
						-- because of paris loop, _accessCount is also looped
					
						local bx,by,bz = relativeIdToXYZ(id)
						
						local dist = sqrt( ( cx+bx - curX )^2 + 
							( cy+by - curY )^2 + ( cz+bz - curZ )^2 )
						
						-- print(idToName[block] or block, "found", cx+bx,cy+by,cz+bz)

						self:rememberBlock(nearest.id, id, idToName[block] or block)
						
						--local dist = 3 -- self:getDistance(curPos, pos)
						if ( minDist < 0 or dist < minDist) and dist <= maxDistance and dist > 0 then 
							minDist = dist
							minX,minY,minZ = cx+bx,cy+by,cz+bz
							-- if minDist<=1 then
								-- -- cant be any more nearby
								-- break
							-- end
						end
					end
				end
			end

		else
			print("no chunk")
		end
		
		
		for _,dir in ipairs(directions) do
			
			local newX = midX + dir[1]
			local newY = midY + dir[2]
			local newZ = midZ + dir[3]
			
			chunkId = xyzToChunkId(newX,newY,newZ)
			
			local distance = manhattanDistance(curX,curY,curZ, newX,newY,newZ)
			local borderDistance = math.max(math.abs(newX-curX),math.abs(newY-curY),math.abs(newZ-curZ))-halfChunk-1
			--print("borderDistance", borderDistance)
			if borderDistance < maxDistance and not visited[chunkId] then
				tableinsert(queue, { id=chunkId, mid = { newX, newY, newZ }, distance = distance })
				visited[chunkId] = true
			else
				-- out of range
			end
			
		end
		
	end
	
	if minX and minY and minZ then 
		 minPos = vector.new(minX,minY,minZ)
	end
	
	print(os.epoch("local")-start, "findNextBlock", minPos, "chunks", chunkCt, "count", ct)
	
	return minPos

	
	-- for x=1,totalRange do
		-- local chunk = self:accessChunk(xyzToChunkId(x,1,1),false,true)
		-- for z=1,totalRange do
			
			-- for y=1, totalRange do
				-- -- local pos = vector.new(curPos.x-x+halfRange,
										-- -- curPos.y-y+halfRange,
										-- -- curPos.z-z+halfRange)
										
				-- local tx = cx-x
				-- local ty = cy-y
				-- local tz = cz-z
				
				-- local blockName --= self:getData(tx, ty, tz) --500 ms
				
				
				-- if chunk then 
					-- blockName = chunk[xyzToRelativeChunkId(x,y,z)] --
					-- -- return (idToName[chunk[self:xyzToRelativeChunkId(x,y,z)]]
						-- -- or 	chunk[self:xyzToRelativeChunkId(x,y,z)] )
				-- end
				-- --local blockName = self:getData(x,y,z)
				-- --local blockName = "minecraft:iron_osre"
				-- ct = ct +1
				-- --if checkFunction(nil,blockName) then -- 40 ms
					-- -- alternatively: halfRange-x
					-- -- local dist = sqrt( ( tx - curX )^2 + 
						-- -- ( ty - curY )^2 + ( tz - curZ )^2 )
						
					-- local dist = 3 -- self:getDistance(curPos, pos)
					-- if ( minDist < 0 or dist < minDist) and dist <= maxDistance and dist > 0 then 
						-- minDist = dist
						-- minPos = pos
						-- -- if minDist<=1 then
							-- -- -- cant be any more nearby
							-- -- break
						-- -- end
					-- end
				-- --end
			-- end
		-- end
	-- end

	
	-- print(os.epoch("local")-start, "findNextBlock", minPos, "count", ct)
	--return minPos
end



-- for pathfinding, absolute ids

function ChunkyMap.posToId(pos)
	return xyzToId(pos.x, pos.y, pos.z)
end
local posToId = ChunkyMap.posToId

function ChunkyMap.idToXYZ(id)
	local w = floor( ( sqrt( 8 * id + 1 ) - 1 ) / 2 )
	local t = ( w^2 + w ) / 2
	local z = id - t
	local temp = w - z
	
	w =  floor( ( sqrt( 8 * temp + 1 ) - 1 ) / 2 )
	t = ( w^2 + w ) / 2
	local y = temp - t
	local x = w - y
	
	-- restore negative coordinates
	if y > 448 then
		-- x or z negative
		if y > 896 then 
			-- z negative
			z = -z
			y = y - 896
		end
		if y > 448 then
			-- x negative
			x = -x
			y = y - 448
		end
	end
	y = y - 64
	
	return x,y,z
end
local idToXYZ = ChunkyMap.idToXYZ

function ChunkyMap.idToPos(id)
	local x,y,z = idToXYZ(id)
	return vector.new(x,y,z)
end
local idToPos = ChunkyMap.idToPos

return ChunkyMap