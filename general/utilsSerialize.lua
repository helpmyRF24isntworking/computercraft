
--local type = type

local function bitlen(x)
	local n = 0
	repeat
		x = math.floor(x / 2)
		n = n + 1
	until x == 0
	return n
end

-- TODO: make this a lookup table
local function bytesForValues(valBit)
	local n = 1
	while (n * 8) % valBit ~= 0 do
		n = n + 1
	end
	local numValues = (n * 8) / valBit
	return n, numValues  -- returns number of bytes and number of values that fit exactly
end

local utilsSerialize = {

	serialize = function(chunk)
		if chunk then
			local txt = "{"
			for id, data in pairs(chunk) do
				local idtype, datatype = type(id), type(data)
				if idtype == "number" then 
					if datatype == "number" then 
						txt = txt .. "[".. id .. "] = " .. data .. ",\n"
					elseif datatype == "string" then
						txt = txt .. "[".. id .. "] = \"" .. data .. "\",\n"
					elseif datatype == "boolean" then
						txt = txt .. "[".. id .. "] = " .. tostring(data) .. ",\n"
					end
				else 
					if datatype == "number" then 
						txt = txt .. "[\"" .. id .. "\"] = " .. data .. ",\n"
					elseif datatype == "string" then
						txt = txt .. "[\"" .. id .. "\"] = \"" .. data .. "\",\n"
					elseif datatype == "boolean" then
						txt = txt .. "[\"" .. id .. "\"] = " .. tostring(data) .. ",\n"
					end
				end
			end
			return txt .. "}"
		--else
		--	print(textutils.serialize(debug.traceback()))
		--	error("no chunk")
		end
	end,

	unserialize = function(data)
		local func = load("return " .. data)
		if func then 
			return func()
		end
	end,

	binarizeStreamDict = function(chunk, startIndex, maxIndex)

		-- same logic as binarizeBitwise but instead of just having a index tab for strings,
		-- all values are translated to indices and stored in a value table
		-- instead of using runs starting with indices, store only length + value and imply indices by order
		-- reintroduce runs but only for nil values

		-- reduce the value lookup by first comparing to the previous value
		-- lookup only happens on value change
		-- this is now the state of the art except its slow for very sparse data
		
		-- could also try runs of air values not just nil
		-- can also store runLengths using LZ style enconding instead of fixed to 1 byte

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			local valMap, valList, valMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack
			local floor = math.floor

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local allowedRunLen = 255 -- max run length so it fits in one byte
			local runId = 0
			local runStart = startIndex
			local runLen = 1
			local runVal = chunk[startIndex]

			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag
			local runLengths = {}
			local partCount = 0
			
			-- we have to initialize lastVid, runLen and maxVal
			local lastVid = nil
			if runVal ~= nil then
				partCount = partCount + 1
				if type(runVal) == "number" then
					maxVal = runVal
					local vid = valMap[runVal]
					if not vid then 
						valMapLen = valMapLen + 1
						valMap[runVal] = valMapLen
						valList[valMapLen] = runVal
						lastVid = valMapLen * 2
					else
						lastVid = vid * 2
					end
				else
					local sid = strMap[runVal]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[runVal] = strMapLen
						strList[strMapLen] = runVal
						lastVid = strMapLen * 2 + 1
					else
						lastVid = sid * 2 + 1
					end
				end	
				rawParts[partCount] = lastVid 
			end


			for idx = startIndex + 1, maxIndex do
				local val = chunk[idx]
				if val == runVal and runLen < allowedRunLen then
					-- continue run
					if val == nil then
						runLen = runLen + 1
					else
						-- skip lookup, just re-add lastVid but dont store a run length
						partCount = partCount + 1
						rawParts[partCount] = lastVid
					end
				else
					
					if runVal == nil then
						partCount = partCount + 1
						-- end of nil run
						runId = runId + 1
						rawParts[partCount] = 0
						runLengths[runId] = runLen
						
						if runLen > maxRunLen then
							maxRunLen = runLen
						end
						runLen = 1
					end

					if val ~= nil then
						partCount = partCount + 1
						if type(val) == "number" then
							if val > maxVal then maxVal = val end
							local vid = valMap[val]
							if not vid then 
								valMapLen = valMapLen + 1
								valMap[val] = valMapLen
								valList[valMapLen] = val
								lastVid = valMapLen * 2
							else
								lastVid = vid * 2
							end
						else
							local sid = strMap[val]
							if not sid then
								strMapLen = strMapLen + 1
								strMap[val] = strMapLen
								strList[strMapLen] = val
								lastVid = strMapLen * 2 + 1 -- type flag
								
							else
								lastVid = sid * 2 + 1
							end
						end	
						rawParts[partCount] = lastVid 
					end
					runVal = val
				end
			end

			if runVal == nil then
				-- final nil run
				runId = runId + 1
				partCount = partCount + 1
				rawParts[partCount] = 0
				runLengths[runId] = runLen

				if runLen > maxRunLen then
					maxRunLen = runLen
				end
			end


			local actValByte = maxVal < 256 and 1 or (maxVal < 65536 and 2 or 4)
			maxVal = math.max(valMapLen * 2, strMapLen * 2 + 1)
			local valBit = bitlen(maxVal)
			local runLenBit = bitlen(maxRunLen) -- 1 byte always
			local bytes, values = bytesForValues(valBit)
			local maxValues = floor(48 / valBit) -- limit to 48 bytes per entry, so i6 is max that fits well into a lua number
			if values > maxValues then
				values = maxValues
				bytes = math.ceil((values * valBit) / 8)
			end
			
			local byteEntries = 0
			local multiBytes = {}

			-- can be combined into the main loop after each 128 values or so?
			-- can be done during main loop, though we dont know valBit then
			-- read data in chunks, followed by a new definition for valBit?

			--[[
			for i = startIndex, partCount, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j]
					if val then
						-- append value to buffer
						bitVal = bitVal * mul1 + val -- left shift by valBit
					else
						-- end of data, still shift to fill remaining bytes
						bitVal = bitVal * mul1
					end
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end
			--]]

			-- precomute multipliers
			local multipliers = {}
			local baseMultiplier = 2 ^ valBit
			multipliers[1] = 1
			for i = 2, values + 1 do
				multipliers[i] = multipliers[i - 1] * baseMultiplier
			end

			-- stop 1 package early to avoid checking for nil values
			if values == 1 then 
				for i = 1, partCount, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i]
				end
			elseif values == 2 then 
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[2] + rawParts[i + 1]
				end
			elseif values == 3 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[3] + rawParts[i + 1] * multipliers[2] + rawParts[i + 2]
				end
			elseif values == 4 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[4] + rawParts[i + 1] * multipliers[3] + rawParts[i + 2] * multipliers[2] + rawParts[i + 3]
				end
			elseif values == 5 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[5] + rawParts[i + 1] * multipliers[4] + rawParts[i + 2] * multipliers[3] + rawParts[i + 3] * multipliers[2] + rawParts[i + 4]
				end
			elseif values == 6 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[6] + rawParts[i + 1] * multipliers[5] + rawParts[i + 2] * multipliers[4] + rawParts[i + 3] * multipliers[3] + rawParts[i + 4] * multipliers[2] + rawParts[i + 5]
				end
			elseif values == 7 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[7] + rawParts[i + 1] * multipliers[6] + rawParts[i + 2] * multipliers[5] + rawParts[i + 3] * multipliers[4] + rawParts[i + 4] * multipliers[3] + rawParts[i + 5] * multipliers[2] + rawParts[i + 6]
				end
			elseif values == 8 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[8] + 
						rawParts[i + 1] * multipliers[7] +
						rawParts[i + 2] * multipliers[6] +
						rawParts[i + 3] * multipliers[5] +
						rawParts[i + 4] * multipliers[4] +
						rawParts[i + 5] * multipliers[3] +
						rawParts[i + 6] * multipliers[2] +
						rawParts[i + 7]

				end
			elseif values == 9 then
				for i = 1, partCount - values, values do
					byteEntries = byteEntries + 1
					multiBytes[byteEntries] = rawParts[i] * multipliers[9] + rawParts[i + 1] * multipliers[8] + rawParts[i + 2] * multipliers[7] + rawParts[i + 3] * multipliers[6] + rawParts[i + 4] * multipliers[5] + rawParts[i + 5] * multipliers[4] + rawParts[i + 6] * multipliers[3] + rawParts[i + 7] * multipliers[2] + rawParts[i + 8]
				end
			end
			local nextIndex = byteEntries * values + 1
			for i = nextIndex, partCount, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j] or 0 -- to avoid nil checks, do this at end
					bitVal = bitVal * baseMultiplier + val
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end



			-- runs: index, length, value+flag
			local format = "<" .. string.rep("I" .. bytes, byteEntries)
			local partsBlob = pack(format, table.unpack(multiBytes, 1, byteEntries))

			-- nil run lengths
			local runFormat = "<" .. string.rep("I1", runId)
			local runBlob = pack(runFormat, table.unpack(runLengths, 1, runId))

			-- actual value mapping
			-- bad argument #2 integer overflow = valList[1], chunk 17875585441344, highest actVal = 1149
			local valFormat = "<" .. string.rep("I" .. actValByte, valMapLen)
			local valBlob = pack(valFormat, table.unpack(valList))

			-- string mapping
			local strFormat = string.rep("z", strMapLen)
			local strBlob = pack(strFormat, table.unpack(strList))

			-- TODO: add startIndex to header for rebuilding
			local header = pack("<I1I1I2I2I2I2I2I2", bytes, values, valBit, byteEntries, runId, strMapLen, actValByte, valMapLen)

			result = header .. partsBlob .. runBlob .. valBlob .. strBlob

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	unbinarizeStreamDict = function(data)
		local chunk = {}
		local unpack = string.unpack
		local floor = math.floor
		local band = bit32.band
		local rep = string.rep


		if data and #data > 11 then -- min header size
			-- read header
			local bytes, valPerPack, valBit, entries, runCount, strCount, actValByte, valMapLen, index = unpack("<I1I1I2I2I2I2I2I2", data, 1)

			if runCount > 0 then

				-- read mappings
				local offset = (entries * bytes)
				local runLengths = {unpack(rep("I1", runCount), data, index + offset )}
				offset = offset + (runCount * 1)
				local valList = {unpack(rep("I" .. actValByte, valMapLen), data, index + offset)}
				local strList = {unpack(rep("z", strCount), data, index + offset + (valMapLen * actValByte))}


				local baseMultiplier = 2 ^ valBit
				local multipliers = { [1] = 1}
				for i = 2, valPerPack + 1 do
					multipliers[i] = multipliers[i - 1] * baseMultiplier
				end

				local format = "I" .. bytes

				-- chunkwise unpacking to save memory
				local CHUNK = 128
				local pos = index
				local entry = 1
				local runId = 0
				local idx = 0 -- actual index in chunk = startIndex - 1

				while entry <= entries do
					local n = math.min(CHUNK, entries - entry + 1)
					local fmt = "<" .. rep(format, n)

					local runs = { unpack(fmt, data, pos) }
					pos = pos + n * bytes

					for i = 1, n do
						-- Decode the data
						local bitVal = runs[i]
						for j = valPerPack - 1, 0, -1 do
							-- Extract each value using the precomputed multipliers
							local mult = multipliers[j + 1]
							local val = floor(bitVal / mult)
							val = val % baseMultiplier -- ( floor is not faster than mod here )
							bitVal = bitVal - val * mult

							local actualVal
							if band(val, 1) == 0 then
								if val == 0 then
									-- nil run
									runId = runId + 1
									if runId > runCount then 
										-- reached end of data 
										break
									end
									local runLen = runLengths[runId]
									for r = 1, runLen do
										-- well, do nothing but advance the current idx
										idx = idx + 1
										-- chunk[idx] = nil
									end
								else
									-- numerical value 
									actualVal = valList[val * 0.5]
									idx = idx + 1
									chunk[idx] = actualVal
								end
							else
								actualVal = strList[(val - 1) * 0.5 ]
								idx = idx + 1
								chunk[idx] = actualVal
							end
						end
							
					end
					entry = entry + n
				end
			end
			
		end
		return chunk
	end,



	binarizeStreamAllRun = function(chunk, startIndex, maxIndex)

		-- same logic as binarizeBitwise but instead of just having a index tab for strings,
		-- all values are translated to indices and stored in a value table
		-- instead of using runs starting with indices, store only length + value and imply indices by order
		-- reintroduce runs but only for nil values
		-- now everybody gets runs again

		-- assuming an avg run length of 2-3 for non-nil values
		-- this should theoretically balance out the overhead of storing run lengths

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			local valMap, valList, valMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack
			local floor = math.floor

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local allowedRunLen = 255 -- max run length so it fits in one byte
			local runId = 0
			local runLen = 0
			local runVal = chunk[startIndex]
			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag
			local runLengths = {}

			for idx = startIndex, maxIndex do
				local val = chunk[idx]
				if val == runVal and runLen < allowedRunLen then
					-- continue run
					runLen = runLen + 1
				else
					-- end of run
					runId = runId + 1
					if runLen > maxRunLen then
						maxRunLen = runLen
					end
					runLengths[runId] = runLen

					if runVal == nil then
						rawParts[runId] = 0
					elseif type(runVal) == "number" then
						if runVal > maxVal then maxVal = runVal end
						local vid = valMap[runVal]
						if not vid then 
							valMapLen = valMapLen + 1
							valMap[runVal] = valMapLen
							valList[valMapLen] = runVal
							rawParts[runId] = valMapLen * 2
						else
							rawParts[runId] = vid * 2
						end
					else
						local sid = strMap[runVal]
						if not sid then
							strMapLen = strMapLen + 1
							strMap[runVal] = strMapLen
							strList[strMapLen] = runVal
							rawParts[runId] = strMapLen * 2 + 1 -- type flag
						else
							rawParts[runId] = sid * 2 + 1
						end
					end		
					runLen = 1
					runVal = val
				end
			end

			-- finalize last run
			runId = runId + 1
			if runLen > maxRunLen then
				maxRunLen = runLen
			end
			runLengths[runId] = runLen

			if runVal == nil then
				rawParts[runId] = 0
			elseif type(runVal) == "number" then
				if runVal > maxVal then maxVal = runVal end
				local vid = valMap[runVal]
				if not vid then 
					valMapLen = valMapLen + 1
					valMap[runVal] = valMapLen
					valList[valMapLen] = runVal
					rawParts[runId] = valMapLen * 2
				else
					rawParts[runId] = vid * 2
				end
			else
				local sid = strMap[runVal]
				if not sid then
					strMapLen = strMapLen + 1
					strMap[runVal] = strMapLen
					strList[strMapLen] = runVal
					rawParts[runId] = strMapLen * 2 + 1 -- type flag
				else
					rawParts[runId] = sid * 2 + 1
				end
			end		


			local actValByte = maxVal < 256 and 1 or (maxVal < 65536 and 2 or 4)
			maxVal = math.max(valMapLen * 2, strMapLen * 2 + 1)
			local valBit = bitlen(maxVal)
			local runLenBit = bitlen(maxRunLen) -- 1 byte always
			local bytes, values = bytesForValues(valBit)
			local maxValues = floor(53 / valBit) -- lua max bits without mantissa is 53?
			if values > maxValues then
				values = maxValues
				bytes = math.ceil((values * valBit) / 8)
			end
			
			local byteEntries = 0
			local multiBytes = {}

			-- can be combined into the main loop after each 128 values or so?
			-- can be done during main loop, though we dont know valBit then
			-- read data in chunks, followed by a new definition for valBit?
			local mul1 = (2 ^ valBit)

			--[[
			for i = startIndex, partCount, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j]
					if val then
						-- append value to buffer
						bitVal = bitVal * mul1 + val -- left shift by valBit
					else
						-- end of data, still shift to fill remaining bytes
						bitVal = bitVal * mul1
					end
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end
			--]]

			for i = startIndex, runId, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j] or 0 -- Default to 0, avoid branching
					bitVal = bitVal * mul1 + val
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
				
			end
			
			
			-- runs: index, length, value+flag
			local format = "<" .. string.rep("I" .. bytes, byteEntries)
			local partsBlob = pack(format, table.unpack(multiBytes, 1, byteEntries))

			-- nil run lengths
			-- print("rid", runId, "maxRunLen", maxRunLen, "#runLengths", #runLengths)
			local runFormat = "<" .. string.rep("I1", runId)
			local runBlob = pack(runFormat, table.unpack(runLengths, 1, runId))

			-- actual value mapping
			local valFormat = "<" .. string.rep("I" .. actValByte, valMapLen)
			local valBlob = pack(valFormat, table.unpack(valList))

			-- string mapping
			local strFormat = string.rep("z", strMapLen)
			local strBlob = pack(strFormat, table.unpack(strList))

			local header = pack("<I1I1I2I2I2I2I2", bytes, values, valBit, runId, strMapLen, actValByte, valMapLen)

			-- print("header", #header, "bytes", #partsBlob, "runs", #runBlob, "vals", #valBlob, "strs", #strBlob)

			result = header .. partsBlob .. runBlob .. valBlob .. strBlob

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	binarizeStreamRun = function(chunk, startIndex, maxIndex)

		-- same logic as binarizeBitwise but instead of just having a index tab for strings,
		-- all values are translated to indices and stored in a value table
		-- instead of using runs starting with indices, store only length + value and imply indices by order
		-- reintroduce runs but only for nil values

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			local valMap, valList, valMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack
			local floor = math.floor

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local allowedRunLen = 255 -- max run length so it fits in one byte
			local runId = 0
			local runStart = startIndex
			local runLen = 0
			local runVal = chunk[startIndex]
			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag
			local runLengths = {}
			local partCount = 0

			for idx = startIndex, maxIndex do
				local val = chunk[idx]
				if val == nil and runVal == nil and runLen < allowedRunLen then
					-- nil run
					runLen = runLen + 1
				else
					
					if runVal == nil then
						partCount = partCount + 1
						-- end of nil run
						runId = runId + 1
						rawParts[partCount] = 0
						runLengths[runId] = runLen
						
						if runLen > maxRunLen then
							maxRunLen = runLen
						end
						runLen = 1
					end

					if val ~= nil then
						partCount = partCount + 1
						if type(val) == "number" then
							if val > maxVal then maxVal = val end
							local vid = valMap[val]
							if not vid then 
								valMapLen = valMapLen + 1
								valMap[val] = valMapLen
								valList[valMapLen] = val
								rawParts[partCount] = valMapLen * 2
							else
								rawParts[partCount] = vid * 2
							end
						else
							local sid = strMap[val]
							if not sid then
								strMapLen = strMapLen + 1
								strMap[val] = strMapLen
								strList[strMapLen] = val
								rawParts[partCount] = strMapLen * 2 + 1 -- type flag
							else
								rawParts[partCount] = sid * 2 + 1
							end
						end				
					end
					runVal = val
				end
			end

			if runVal == nil then
				-- final nil run
				runId = runId + 1
				partCount = partCount + 1
				rawParts[partCount] = 0
				runLengths[runId] = runLen

				if runLen > maxRunLen then
					maxRunLen = runLen
				end
			end


			local actValByte = maxVal < 256 and 1 or (maxVal < 65536 and 2 or 4)
			maxVal = math.max(valMapLen * 2, strMapLen * 2 + 1)
			local valBit = bitlen(maxVal)
			local runLenBit = bitlen(maxRunLen) -- 1 byte always
			local bytes, values = bytesForValues(valBit)
			local maxValues = floor(53 / valBit) -- lua max bits without mantissa is 53?
			if values > maxValues then
				values = maxValues
				bytes = math.ceil((values * valBit) / 8)
			end
			
			local byteEntries = 0
			local multiBytes = {}

			-- can be combined into the main loop after each 128 values or so?
			-- can be done during main loop, though we dont know valBit then
			-- read data in chunks, followed by a new definition for valBit?
			local mul1 = (2 ^ valBit)

			--[[
			for i = startIndex, partCount, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j]
					if val then
						-- append value to buffer
						bitVal = bitVal * mul1 + val -- left shift by valBit
					else
						-- end of data, still shift to fill remaining bytes
						bitVal = bitVal * mul1
					end
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end
			--]]

			for i = startIndex, partCount, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j] or 0 -- Default to 0, avoid branching
					bitVal = bitVal * mul1 + val
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end
			
			
			-- runs: index, length, value+flag
			local format = "<" .. string.rep("I" .. bytes, byteEntries)
			local partsBlob = pack(format, table.unpack(multiBytes, 1, byteEntries))

			-- nil run lengths
			local runFormat = "<" .. string.rep("I1", runId)
			local runBlob = pack(runFormat, table.unpack(runLengths, 1, runId))

			-- actual value mapping
			local valFormat = "<" .. string.rep("I" .. actValByte, valMapLen)
			local valBlob = pack(valFormat, table.unpack(valList))

			-- string mapping
			local strFormat = string.rep("z", strMapLen)
			local strBlob = pack(strFormat, table.unpack(strList))

			local header = pack("<I1I1I2I2I2I2I2", bytes, values, valBit, runId, strMapLen, actValByte, valMapLen)

			-- print("header", #header, "bytes", #partsBlob, "runs", #runBlob, "vals", #valBlob, "strs", #strBlob)

			result = header .. partsBlob .. runBlob .. valBlob .. strBlob

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	binarizeStream = function(chunk, startIndex, maxIndex)

		-- same logic as binarizeBitwise but instead of just having a index tab for strings,
		-- all values are translated to indices and stored in a value table
		-- instead of using runs starting with indices, store only length + value and imply indices by order

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			local valMap, valList, valMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack
			local floor = math.floor

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local runId = 1
			local runStart = startIndex
			local runCount = 0
			local runVal = chunk[startIndex]
			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag


			for idx = startIndex, maxIndex do
				local runVal = chunk[idx]
				if runVal == nil then
					rawParts[idx] = 0
				elseif type(runVal) == "number" then
					if runVal > maxVal then maxVal = runVal end
					local vid = valMap[runVal]
					if not vid then 
						valMapLen = valMapLen + 1
						valMap[runVal] = valMapLen
						valList[valMapLen] = runVal
						rawParts[idx] = valMapLen * 2
					else
						rawParts[idx] = vid * 2
					end
				else
					local sid = strMap[runVal]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[runVal] = strMapLen
						strList[strMapLen] = runVal
						rawParts[idx] = strMapLen * 2 + 1 -- type flag
					else
						rawParts[idx] = sid * 2 + 1
					end
				end
			end

			local actValByte = maxVal < 256 and 1 or (maxVal < 65536 and 2 or 4)
			maxVal = math.max(valMapLen * 2, strMapLen * 2 + 1)
			local valBit = bitlen(maxVal)
			local bytes, values = bytesForValues(valBit)
			local maxValues = floor(53 / valBit) -- lua max bits without mantissa is 53?
			if values > maxValues then
				values = maxValues
				bytes = math.ceil((values * valBit) / 8)
			end
			
			local byteEntries = 0
			local multiBytes = {}

			
			-- can be combined into the main loop after each 128 values or so?
			for i = startIndex, maxIndex, values do
				local bitVal = 0
				for j = 0, values - 1 do
					local val = rawParts[i + j]
					if val then
						-- append value to buffer
						bitVal = bitVal * (2 ^ valBit) + val -- left shift by valBit
					else
						-- end of data, still shift to fill remaining bytes
						bitVal = bitVal * (2 ^ valBit)
					end
				end
				byteEntries = byteEntries + 1
				multiBytes[byteEntries] = bitVal
			end

			
			-- runs: index, length, value+flag
			local format = "<" .. string.rep("I" .. bytes, byteEntries)
			local partsBlob = pack(format, table.unpack(multiBytes, 1, byteEntries))

			-- actual value mapping
			local valFormat = "<" .. string.rep("I" .. actValByte, valMapLen)
			local valBlob = pack(valFormat, table.unpack(valList))

			-- string mapping
			local strFormat = string.rep("z", strMapLen)
			local strBlob = pack(strFormat, table.unpack(strList))

			local header = pack("<I1I1I2I2I2", bytes, values, valBit, strMapLen, actValByte, valMapLen)

			result = header .. partsBlob .. valBlob .. strBlob

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,


	binarizeTranslate = function(chunk, startIndex, maxIndex)

		-- same logic as binarizeBitwise but instead of just having a index tab for strings,
		-- all values are translated to indices and stored in a value table

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			local valMap, valList, valMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local runId = 1
			local runStart = startIndex
			local runCount = 0
			local runVal = chunk[startIndex]
			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag

			-- faster on large chunks than pairs but slower on sparse chunks

			-- saving nil runs is unnecessary as they can be implied
			for idx = startIndex, maxIndex do
				local val = chunk[idx]
				if val == runVal then --idx == runStart + runCount
					-- continue run
					runCount = runCount + 1
				else
					-- save non-nil run info
					if runVal ~= nil then
						local rid = ( runId - 1 ) * 3 + 1
						rawParts[rid] = runStart
						rawParts[rid + 1] = runCount

						if runCount > maxRunLen then
							maxRunLen = runCount
						end
						
						if type(runVal) == "number" then
							if runVal > maxVal then maxVal = runVal end
							local vid = valMap[runVal]
							if not vid then 
								valMapLen = valMapLen + 1
								valMap[runVal] = valMapLen
								valList[valMapLen] = runVal
								rawParts[rid + 2] = valMapLen * 2
							else
								rawParts[rid + 2] = vid * 2
							end
						else
							local sid = strMap[runVal]
							if not sid then
								strMapLen = strMapLen + 1
								strMap[runVal] = strMapLen
								strList[strMapLen] = runVal
								rawParts[rid + 2] = strMapLen * 2 + 1 -- type flag
							else
								rawParts[rid + 2] = sid * 2 + 1
							end
						end
						-- new run
						runId = runId + 1
					end
					runStart = idx
					runCount = 1
					runVal = val
				end
			end

			if runVal ~= nil then
				-- final run
				local rid = ( runId - 1 ) * 3 + 1
				rawParts[rid] = runStart
				rawParts[rid + 1] = runCount
				
				if type(runVal) == "number" then
					if runVal > maxVal then maxVal = runVal end
					local vid = valMap[runVal]
					if not vid then 
						valMapLen = valMapLen + 1
						valMap[runVal] = valMapLen
						valList[valMapLen] = runVal
						rawParts[rid + 2] = valMapLen * 2
					else
						rawParts[rid + 2] = vid * 2
					end
				else
					local sid = strMap[runVal]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[runVal] = strMapLen
						strList[strMapLen] = runVal
						rawParts[rid + 2] = strMapLen * 2 + 1
					else
						rawParts[rid + 2] = sid * 2 + 1
					end
				end
				runId = runId + 1
			end

			if runId > 1 then 

				maxIndex = rawParts[( runId - 2 ) * 3 + 1]
				local indexBit = bitlen(maxIndex)
				local runLenBit = bitlen(maxRunLen)
				local actValByte = maxVal < 256 and 1 or (maxVal < 65536 and 2 or 4)
				maxVal = math.max(valMapLen * 2, strMapLen * 2 + 1)
				local valBit = bitlen(maxVal)
				
				local byteCount = math.ceil((indexBit + runLenBit + valBit + 1) / 8)
				


				local mul1 = 2 ^ (runLenBit + valBit + 1)
				local mul2 = 2 ^ (valBit + 1)
				local idx = 0
				for rid = 1, ( runId - 1 ) * 3, 3 do
					idx = idx + 1
					rawParts[idx] =
						rawParts[rid]     * mul1 +
						rawParts[rid + 1] * mul2 +
						rawParts[rid + 2]
				end
				
				-- runs: index, length, value+flag
				local format = "<" .. string.rep("I" .. byteCount, idx)
				local partsBlob = pack(format, table.unpack(rawParts, 1, idx))

				-- actual value mapping
				local valFormat = "<" .. string.rep("I" .. actValByte, valMapLen)
				local valBlob = pack(valFormat, table.unpack(valList))

				-- string mapping
				local strFormat = string.rep("z", strMapLen)
				local strBlob = pack(strFormat, table.unpack(strList))

				local header = pack("<I1I1I1I4I2I2I2", indexBit, runLenBit, valBit, runId - 1, strMapLen, actValByte, valMapLen)

				result = header .. partsBlob .. valBlob .. strBlob
			end

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	unbinarizeTranslate = function(data)
		local chunk = {}
		local unpack = string.unpack
		local floor = math.floor
		local band = bit32.band
		local rep = string.rep


		if data and #data > 11 then -- min header size
			-- read header
			local indexBit, runLenBit, valBit, runCount, strCount, actValByte, valMapLen, index = unpack("<I1I1I1I4I2I2I2", data, 1)

			if runCount > 0 then

				local byteCount = math.ceil((indexBit + runLenBit + valBit + 1) / 8)

				-- read mappings
				local valMap = {unpack(rep("I" .. actValByte, valMapLen), data, index + (runCount * byteCount))}
				local strMap = {unpack(rep("z", strCount), data, index + (runCount * byteCount) + (valMapLen * actValByte))}
				
				local mul1 = 2 ^ (runLenBit + valBit + 1)
				local mul2 = 2 ^ (valBit + 1)
				local format = "I" .. byteCount

				-- chunkwise unpacking to save memory
				local CHUNK = 128
				local pos = index
				local run = 1

				while run <= runCount do
					local n = math.min(CHUNK, runCount - run + 1)
					local fmt = "<" .. rep(format, n)

					local runs = { unpack(fmt, data, pos) }
					pos = pos + n * byteCount

					for i = 1, n do
						local packedVal = runs[i]

						local startIdx = floor(packedVal / mul1)
						packedVal = packedVal - startIdx * mul1

						local len = floor(packedVal / mul2)
						local valFlag = packedVal - len * mul2

						local actualVal
						if band(valFlag, 1) == 0 then
							actualVal = valMap[valFlag * 0.5]
						else
							actualVal = strMap[(valFlag - 1) * 0.5 ]
						end
						
						for j = 0, len - 1 do
							chunk[startIdx + j] = actualVal
						end
					end

					run = run + n
				end
			end
		end
		return chunk
	end,



	binarizeBitwise = function(chunk, startIndex, maxIndex)

		-- exact logic as below but using bitwise operations to pack data more tightly

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack

			-- determine runs of sequential indices
			local maxRunLen, maxVal = 0, 0
			local runId = 1
			local runStart = startIndex
			local runCount = 0
			local runVal = chunk[startIndex]
			local rawParts = {} -- 1 = index, 2 = length, 3 = value + flag

			-- faster on large chunks than pairs but slower on sparse chunks

			-- saving nil runs is unnecessary as they can be implied
			for idx = startIndex, maxIndex do
				local val = chunk[idx]
				if val == runVal then --idx == runStart + runCount
					-- continue run
					runCount = runCount + 1
				else
					-- save non-nil run info
					if runVal ~= nil then
						local rid = ( runId - 1 ) * 3 + 1
						rawParts[rid] = runStart
						rawParts[rid + 1] = runCount

						if runCount > maxRunLen then
							maxRunLen = runCount
						end
						
						if type(runVal) == "number" then
							if runVal > maxVal then maxVal = runVal end
							rawParts[rid + 2] = runVal * 2
						else
							local sid = strMap[runVal]
							if not sid then
								strMapLen = strMapLen + 1
								strMap[runVal] = strMapLen
								strList[strMapLen] = runVal
								rawParts[rid + 2] = strMapLen * 2 + 1 -- type flag
							else
								rawParts[rid + 2] = sid * 2 + 1
							end
						end
						-- new run
						runId = runId + 1
					end
					runStart = idx
					runCount = 1
					runVal = val
				end
			end

			if runVal ~= nil then
				-- final run
				local rid = ( runId - 1 ) * 3 + 1
				rawParts[rid] = runStart
				rawParts[rid + 1] = runCount
				
				if type(runVal) == "number" then
					if runVal > maxVal then maxVal = runVal end
					rawParts[rid + 2] = runVal * 2
				else
					local sid = strMap[runVal]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[runVal] = strMapLen
						strList[strMapLen] = runVal
						rawParts[rid + 2] = strMapLen * 2 + 1
					else
						rawParts[rid + 2] = sid * 2 + 1
					end
				end
				runId = runId + 1
			end

			if runId > 1 then 

				maxIndex = rawParts[( runId - 2 ) * 3 + 1]
				local indexBit = bitlen(maxIndex)
				local runLenBit = bitlen(maxRunLen)
				maxVal = math.max(maxVal * 2, strMapLen * 2 + 1)
				local valBit = bitlen(maxVal)
				
				local byteCount = math.ceil((indexBit + runLenBit + valBit + 1) / 8)
				
				
				local mul1 = 2 ^ (runLenBit + valBit + 1)
				local mul2 = 2 ^ (valBit + 1)
				local idx = 0
				for rid = 1, ( runId - 1 ) * 3, 3 do
					idx = idx + 1
					rawParts[idx] =
						rawParts[rid]     * mul1 +
						rawParts[rid + 1] * mul2 +
						rawParts[rid + 2]
				end
				
				local format = "<" .. string.rep("I" .. byteCount, idx)
				local partsBlob = pack(format, table.unpack(rawParts, 1, idx))

				local strFormat = string.rep("z", strMapLen)
				local strBlob = pack(strFormat, table.unpack(strList))

				local header = pack("<I1I1I1I4I2", indexBit, runLenBit, valBit, runId - 1, strMapLen)

				result = header .. partsBlob .. strBlob
			end

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	unbinarizeBitwise = function(data)
		local chunk = {}
		local unpack = string.unpack
		local floor = math.floor
		local band = bit32.band
		local rep = string.rep


		if data and #data > 9 then -- min header size
			-- read header
			local indexBit, runLenBit, valBit, runCount, strCount, index = unpack("<I1I1I1I4I2", data, 1)

			if runCount > 0 then

				local byteCount = math.ceil((indexBit + runLenBit + valBit + 1) / 8)

				-- read strings
				local strMap = {unpack(rep("z", strCount), data, index + (runCount * byteCount))}

				local mul1 = 2 ^ (runLenBit + valBit + 1)
				local mul2 = 2 ^ (valBit + 1)
				local format = "I" .. byteCount

				-- chunkwise unpacking to save memory
				local CHUNK = 128
				local pos = index
				local run = 1

				while run <= runCount do
					local n = math.min(CHUNK, runCount - run + 1)
					local fmt = "<" .. rep(format, n)

					local runs = { unpack(fmt, data, pos) }
					pos = pos + n * byteCount

					for i = 1, n do
						local packedVal = runs[i]

						local startIdx = floor(packedVal / mul1)
						packedVal = packedVal - startIdx * mul1

						local len = floor(packedVal / mul2)
						local valFlag = packedVal - len * mul2

						local actualVal
						if band(valFlag, 1) == 0 then
							actualVal = valFlag * 0.5
						else
							actualVal = strMap[(valFlag - 1) * 0.5 ]
						end
						
						for j = 0, len - 1 do
							chunk[startIdx + j] = actualVal
						end
					end

					run = run + n
				end
			end
		end
		return chunk
	end,

	-- TODO: binarize runs but completely without indices
	-- with current implementation the indices start at 1 and are sequential for a fully mapped chunk
	-- e.g. for 16x16x16 1 to 4096
	-- so we can just store the runs of values without indices
	-- keep the string mapping idea and translate them to values
	-- then just go from 1-4096 and store runs of same values (incl nil)
	
	-- perhaps like it is done here but compress each run further based on value
	-- format per run
	-- startIdx, length, [valueType, value] * length
	-- -> DONE

	binarizeNoIndex = function(chunk, startIndex, maxIndex)

		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			
			local type = type
			local pack = string.pack

			-- determine runs of sequential indices
			local maxRunLen = 0
			local runId = 1
			local runStart = startIndex
			local runCount = 0
			local runVal = chunk[startIndex]

			local rawParts = {} -- 1 = index, 2 = length, 3 = value

			-- faster on large chunks than pairs but slower on sparse chunks

			-- saving nil runs is unnecessary as they can be implied
			local val
			for idx = startIndex, maxIndex do
				val = chunk[idx]
				if val == runVal then --idx == runStart + runCount
					-- continue run
					runCount = runCount + 1
				else
					-- save non-nil run info
					if runVal ~= nil then
						local rid = ( runId - 1 ) * 3 + 1
						rawParts[rid] = runStart
						rawParts[rid + 1] = runCount

						if runCount > maxRunLen then
							maxRunLen = runCount
						end
						
						if type(runVal) == "number" then
							rawParts[rid + 2] = runVal -- max 15 bit value
						else
							local sid = strMap[runVal]
							if not sid then
								strMapLen = strMapLen + 1
								strMap[runVal] = strMapLen
								strList[strMapLen] = runVal
								rawParts[rid + 2] = strMapLen + 0x8000
							else
								rawParts[rid + 2] = sid + 0x8000
							end
						end
						-- new run
						runId = runId + 1
					end
					runStart = idx
					runCount = 1
					runVal = val
				end
			end

			if runVal ~= nil then
				-- final run
				local rid = ( runId - 1 ) * 3 + 1
				rawParts[rid] = runStart
				rawParts[rid + 1] = runCount
				
				if type(runVal) == "number" then
					rawParts[rid + 2] = runVal -- max 15 bit value
				else
					local sid = strMap[runVal]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[runVal] = strMapLen
						strList[strMapLen] = runVal
						rawParts[rid + 2] = strMapLen + 0x8000
					else
						rawParts[rid + 2] = sid + 0x8000
					end
				end
				runId = runId + 1
			end

			if runId > 1 then 

				--[[
				for i = 1, runId -1  do
					local rid = ( i - 1 ) * 3 + 1
					local sidx, len, val = rawParts[rid], rawParts[rid + 1], rawParts[rid + 2]
					if len > 3 then
					print("RUN", i, "START", sidx, "LEN", len, "VAL", val)
					end
				end
				--]]

				-- allocate less bytes depending on max index (-1 bit for type flag)
				local indexBytes = maxIndex < 128 and 1 or ( maxIndex < 32768 and 2 or 4 )
				local runLenBytes = maxRunLen < 256 and 1 or ( maxRunLen < 65536 and 2 or 4 )
				local strCountBytes = 2 -- due to type flag

				-- index, length, value, index, value, length ...
				local format = "<" .. string.rep("I" .. indexBytes .. "I" .. runLenBytes .. "I" .. strCountBytes, runId - 1)
				local partsBlob = pack(format, table.unpack(rawParts))

				local strFormat = string.rep("z", strMapLen)
				local strBlob = pack(strFormat, table.unpack(strList))

				-- max run count = maxIndex 
				-- header: indexBytes, runCount, strCount
				local header = pack("<I1I1I1I4I2", indexBytes, runLenBytes, strCountBytes, runId - 1, strMapLen)

				result = header .. partsBlob .. strBlob
			end

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end
		return result
	end,

	unbinarizeNoIndex = function(data)
		
		local chunk = {}
		local unpack = string.unpack

		if data and #data > 7 then -- min header size
			-- read header
			local indexBytes, runLenBytes, strCountBytes, runCount, strCount, index = unpack("<I1I1I1I4I2", data, 1)
			-- read runs
			
			-- print("len", #data, "indexBytes", indexBytes, "runCount", runCount, "strCount", strCount,  "idx", index)

			if runCount > 0 then

				local format = "<" .. string.rep("I" .. indexBytes .. "I" .. runLenBytes .. "I" .. strCountBytes, runCount)
				local unpackedRuns = {unpack(format, data, index)}
				
				index = index + (runCount * (indexBytes + runLenBytes + strCountBytes))
				-- index = unpackedRuns[#unpackedRuns]

				-- read strings
				local strFromat = string.rep("z", strCount)
				local strMap = {unpack(strFromat, data, index)}

				for i = 1, #unpackedRuns - 1, 3 do
					local startIdx = unpackedRuns[i]
					local len = unpackedRuns[i+1]
					local val = unpackedRuns[i+2]
					
					local actualVal
					if val >= 0x8000 then
						-- string
						actualVal = strMap[val - 0x8000]
					else
						-- number
						actualVal = val
					end

					for j = 0, len -1 do
						chunk[startIdx + j] = actualVal
					end
				end

			end
		end

		return chunk
	end,

	binarizeRuns = function(chunk)

		if chunk then

			-- ensure numeric indices are sorted
			local indices = {}
			local idct = 0
			for id,_ in pairs(chunk) do
				if type(id) == "number" and id >= 0 then -- ids start at 1
					idct = idct + 1
					indices[idct] = id
				end
			end
			if idct == 0 then return nil end
			table.sort(indices)

			-- allocate less bytes depending on max index
			local indexBytes = indices[idct] < 256 and 1 or ( indices[idct] < 65.536 and 2 or 4 )

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0
			
			-- determine runs of sequential indices
			local runId = 1
			local runStart = indices[1]
			local runCount = 0
			local runTypes, runVals = {}, {}
			-- runlengths can be used to keep everything 1d
			local runStarts, runLengths = {}, {}

			for i = 1, #indices do
				local idx = indices[i]
				if idx == runStart + runCount then
					-- continue run
					runCount = runCount + 1
				else
					-- save run info
					runStarts[runId] = runStart
					runLengths[runId] = runCount
					-- new run
					runId = runId + 1
					runStart = idx
					runCount = 1
				end

				-- add value to run
				local data = chunk[idx]
				if type(data) == "number" then
					runTypes[i] = 0
					runVals[i] = data
				else 
					local sid = strMap[data]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[data] = strMapLen
						strList[strMapLen] = data
						sid = strMapLen
					end
					runTypes[i] = 1
					runVals[i] = sid
					
				end

			end
			-- save final run info
			if runCount > 0 then
				runStarts[runId] = runStart
				runLengths[runId] = runCount
			end

			-- TODO: runs with the same data info can also be merged
			-- e.g. run indices 5-30 are all value 0  -> len run = 25 with single value 0


			-- build binary data
			local pack = string.pack
			local band = bit32.band
			local parts = {}

			local strListLen = #strList
			-- 1 bit is for the type flag, so we use 128 / 32.768
			local strIndexBytes = strListLen < 128 and 1 or (strListLen < 32768 and 2 or 4)
			local strFormat = "<I"..strIndexBytes
			
			local header = pack("<BB", indexBytes, strIndexBytes)

			local partCt = 1
			parts[partCt] = header

			-- string translation
			partCt = partCt + 1
			parts[partCt] = pack(strFormat, strListLen)
			for i = 1, strListLen do
				partCt = partCt + 1
				parts[partCt] = pack("z", strList[i] or "")
			end

			-- runs header
			local indexFormat = "I"..indexBytes
			local runHeaderFormat = "<" .. indexFormat .. indexFormat

			-- actual runs
			partCt = partCt + 1
			local internalIdx = 0
			parts[partCt] = pack( "<" .. indexFormat, #runLengths)
			for runId = 1, #runLengths do
				local runLen = runLengths[runId]
				local runStart = runStarts[runId]
				partCt = partCt + 1
				parts[partCt] = pack(runHeaderFormat, runStart, runLen)
				for i = 1, runLen do
					internalIdx = internalIdx + 1
					local val = runVals[internalIdx]
					partCt = partCt + 1
					if runTypes[internalIdx] == 0 then
						parts[partCt] = pack("<I2", 0, band(val, 0x7FFF)) -- 1 bit type flag, 15 bit block id value
					else
						parts[partCt] = pack(strFormat, 1, val + 0x8000) -- 1 bit type flag, XX bit reference string id
					end
				end 
			end

			-- timings:
			--loop indices and sort: 600 ms
				-- loop pairs: 190 ms
				-- sort: 410 ms
			-- first loop type: 200 ms
			--second loop type: 200 ms
			--parts = 450 ms

			return table.concat(parts)
		else
			return nil
		end
	end,

	binarize = function(chunk, maxIndex)
		-- faster but larger binary format
		local result = ""

		if chunk then

			-- remove non numerical indices but add them back later
			local _accessCount = chunk._accessCount
			local _lastAccess = chunk._lastAccess
			local _lastChange = chunk._lastChange
			local locked = chunk.locked
			chunk._accessCount = nil
			chunk._lastAccess = nil
			chunk._lastChange = nil
			chunk.locked = nil
			

			-- define chunk-specific translation table for strings
			local strMap, strList, strMapLen = {}, {}, 0

			local type = type
			local pack = string.pack
			local partCount = 0
			local rawParts = {}

			for id,val in pairs(chunk) do
				partCount = partCount + 1
				rawParts[partCount] = id
				partCount = partCount + 1
				
				if type(val) == "number" then
					-- optionally band to 15 bit
					rawParts[partCount] = val
				else 
					local sid = strMap[val]
					if not sid then
						strMapLen = strMapLen + 1
						strMap[val] = strMapLen
						strList[strMapLen] = val
						rawParts[partCount] = strMapLen + 0x8000
					else
						rawParts[partCount] = sid + 0x8000
					end
				end
			end

			if partCount > 0 then

				local indexBytes
				-- allocate less bytes depending on max index
				if not maxIndex then 
					indexBytes = 2
				else 
					indexBytes = maxIndex < 256 and 1 or ( maxIndex < 65536 and 2 or 4 )
				end

				local format = "<" .. string.rep("I" .. indexBytes .. "I2", partCount/2)
				local partsBlob = pack(format, table.unpack(rawParts))


				local partBytes = indexBytes + 2 -- "<I2I2"
				local partsLength = partCount / 2 * partBytes
				
				local strParts = {}
				for i = 1, strMapLen do
					strParts[i] = pack("z", strList[i] or "")
				end
				local strBlob = table.concat(strParts)

				local header = pack("<I4I4I1I4", partsLength, partCount / 2, indexBytes, strMapLen)

				-- timings:
				-- first loop: 470 ms
				-- pack : 120 ms				

				result = header .. partsBlob .. strBlob

			end

			-- add back non numerical indices
			chunk._accessCount = _accessCount
			chunk._lastAccess = _lastAccess
			chunk._lastChange = _lastChange
			chunk.locked = locked

		end

		return result

	end,

	unbinarize = function(data)

		local chunk = {}
		local unpack = string.unpack

		if data and #data > 13 then -- min header size
			-- read header
			local partsLength, partCount, indexBytes, strCount, index = unpack("<I4I4I1I4", data, 1)
			-- read parts
			
			-- print("len", #data, "partsLength", partsLength, "partCount", partCount, "indexBytes", indexBytes, "strCount", strCount,  "idx", index)

			if partCount > 0 then

				local format = "<" .. string.rep("I" .. indexBytes .. "I2", partCount)
				local unpackedParts = {unpack(format, data, index)}
				
				index = index + partsLength

				-- read strings
				local strMap = {}
				for i = 1, strCount do
					local strVal
					strVal, index = unpack("z", data, index)
					strMap[i] = strVal
				end

				-- for some reason unpacked - 1
				for i = 1, #unpackedParts - 1, 2 do
					local id = unpackedParts[i]
					local val = unpackedParts[i+1]
					
					if val >= 0x8000 then
						-- string
						chunk[id] = strMap[val - 0x8000]
					else
						-- number
						chunk[id] = val
					end
				end

			end
		end

		return chunk
	end,

}

return utilsSerialize