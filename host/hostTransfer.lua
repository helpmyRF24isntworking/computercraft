
local osEpoch = os.epoch

local function importFile(fileName, fileData)

	if fs.exists(fileName) then 
		fs.delete(fileName)
	end
	file = fs.open(fileName, "w")
	file.write(fileData)
	file.close()
	
end

local function handleAnswer(msg,forMsg)
	if msg and msg.data then
		local i = 0
		if msg.data[1] == "FILE" then
            i = i + 1
			print(i, "RECEIVED",msg.data[2].name)
			importFile(msg.data[2].name, msg.data[2].data)
		elseif msg.data[1] == "FOLDERS" then
			local start = osEpoch("utc")
			for folderName, folder in pairs(msg.data[2]) do
                if fs.isDir(folderName) then
                    fs.delete(folderName)
                end
				for fileName,file in pairs(folder) do
                    importFile(folderName.."/"..fileName, file.data)
                    i = i + 1
                    print(i, "RECEIVED", folderName.."/"..fileName)
                    if osEpoch("utc") - start > 1000 then
                        print("IMPORTED", i, "FILES")
                        start = osEpoch("utc")
                        sleep(0)
                    end
				end
			end
		else
			print(msg.data[1], textutils.serialize(msg.data[2]))
            return false
		end
	end
    return true
end 

local function transferFiles(node)
    local result = true
	local waitTime = 5
    local folders = { "runtime/map/chunks", "runtime/map/multichunks" }
    -- only for testing purposses update pocket from 0
    if pocket then
        folders = { "runtime/map/chunks",
					"runtime/map/multichunks",
                    "general",
                    "gui",
                    "host",
                    "pocket",
                    "turtle",
					"storage",
                    }
    end
    local files = {
        "runtime/turtles.txt", 
        "runtime/stations.txt", 
        "runtime/taskData.txt", 
        "runtime/alerts.txt", 
        "runtime/config.lua"
    }

	for _,file in ipairs(files) do
		-- local modified = nil
		-- if fs.exists(file) then modified = fs.attributes(file).modified end
        print("FILE_REQUEST", file)
		local data = { "FILE_REQUEST", { fileName = file, modified = nil } }
		local answer, forMsg = node:send(node.differentHost, data, true, true, waitTime)
		if not handleAnswer(answer, forMsg) then
            result = false
        end
	end

    -- relevant file transfer done
    -- optionally try and get map chunks as well

    local ts = os.epoch("utc")
	-- unsure if this is perhaps too much data
    print("FOLDERS_REQUEST", textutils.serialize(folders))
	local data = { "FOLDERS_REQUEST", { folderNames = folders, files = files } }
	local answer, forMsg = node:send(node.differentHost, data, true, true, 60)
    print("ANSWER TIME", os.epoch("utc") - ts)
    ts = os.epoch("utc")
	if not handleAnswer(answer, forMsg) then
        result = false
        print("folder failed", answer and answer.data[1] or "no answer")
    end
    print("IMPORT TIME", os.epoch("utc") - ts)

    return result
end

local function checkForHostTransfer()
	local node = global.nodeUpdate 
	local waitTime = 5
	local flagFile = "runtime/hostTransferFlag.txt"

	if fs.exists(flagFile) then
		fs.delete(flagFile)
		print("HOST TRANSFER IN PROGRESS")
		--display:showPopUp (gui.Label:new(2,2,display.width-2,1,"This computer has been set as the new host. Press any key to continue."))
		
		-- notify old host that this is ready to accept turtles clients
        local tempWait = 5
        for _,turt in pairs(global.turtles) do tempWait = tempWait + 2 end
        print("HOST_TRANSFER_COMPLETE")
		local answer = node:send(node.differentHost, {"HOST_TRANSFER_COMPLETE"}, true, true, waitTime)
		if answer and answer.data[1] == "HOST_TRANSFER_COMPLETE_OK" then
			print(answer.data[1])
			local noAck = answer.data[2] and answer.data[2].noAck or nil
			if noAck then
				for id in ipairs(noAck) do
					if global.turtles[id] then
						global.turtles[id].needsHostNotify = true
					end
					print("TURTLE", id, "DID NOT ACKNOWLEDGE HOST")
				end
			end

			-- alternatively keep old host online to redirect turtles to new host 
            print("HOST_TRANSFER_SHUTDOWN")
			local answer = node:send(node.differentHost, {"HOST_TRANSFER_SHUTDOWN"}, true, true, waitTime)
			if answer and answer.data[1] == "HOST_TRANSFER_SHUTDOWN_OK" then
				print(answer.data[1])
				print("HOST TRANSFER DONE")
                return true
				-- done
			else
				print("HOST_TRANSFER_SHUTDOWN_UNSUCCESSFUL", answer and answer.data[1] or "no answer")
                return false
			end
		else 
			print("HOST_TRANSFER_COMPLETION_UNSUCCESSFUL", answer and answer.data[1] or "no answer")
            return false
		end

	elseif node.differentHost then 
		local display = global.display

		-- TODO: implement proper GUI prompt
		--display:showPopUp (gui.Label:new(2,2,display.width-2,1,"Host transfer requested from another host. Accept? (y/n)"))
		print("\n-------------------------------------------")
        print("DIFFERENT HOST DETECTED:", node.differentHost)
        print("-------------------------------------------")
        write("REQUEST TRANSFER? (y/n): ")
		local answer = read()
		if answer:lower() ~= "y" then
			print("HOST_TRANSFER_DENIED")
			return false
		end

        print("HOST_TRANSFER_REQUEST")
		local answer = node:send(node.differentHost, {"HOST_TRANSFER_REQUEST"}, true, true, 5)
		if answer and answer.data[1] == "HOST_TRANSFER_OK" then
			print(answer.data[1])
            print("HOST_TRANSFER_PREPARE")
			local answer = node:send(node.differentHost, {"HOST_TRANSFER_PREPARE"}, true, true, 5)
			if answer and answer.data[1] == "HOST_TRANSFER_PREPARE_OK" then
				print(answer.data[1])
				-- host stops serving turtles etc.

                -- request files from old host
				if transferFiles(node) then
					print("FILE_TRANSFER_COMPLETE")
					-- set flag file to indicate host mode on reboot
					local f = fs.open(flagFile,"w")
					f.write("transfer")
					f.close()
					os.reboot()
				else
					-- TODO: inform old host whenever the process failed
					local answer = node:send(node.differentHost, {"HOST_TRANSFER_FAILED"}, true, true, waitTime)
					print("HOST_TRANSFER_FAILED")
					return false
				end
			else
				print("HOST_TRANSFER_PREPARATION_UNSUCCESSFUL", answer and answer.data[1] or "no answer")
				return false
			end
		else
			print("HOST_TRANSFER_UNSUCCESSFUL", answer and answer.data[1] or "no answer")
			return false
		end
	end
    return true
end

return checkForHostTransfer()