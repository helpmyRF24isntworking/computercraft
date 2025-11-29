
--local type = type

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

		if data and #data > 13 then -- min header size
			-- read header
			local partsLength, partCount,indexBytes, strCount, index = string.unpack("<I4I4I1I4", data, 1)
			-- read parts
			
			if partCount > 0 then

				local format = "<" .. string.rep("I" .. indexBytes .. "I2", partCount)
				local unpackedParts = {string.unpack(format, data, index)}
				
				index = index + partsLength

				-- read strings
				local strMap = {}
				for i = 1, strCount do
					local strVal
					strVal, index = string.unpack("z", data, index)
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