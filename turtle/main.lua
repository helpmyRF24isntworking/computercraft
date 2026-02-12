
local miner = global.miner
local queue = miner.queue


print("waiting for tasks...")
while true do

	if miner then 
		queue:checkConditionalTasks()
		queue:executeNext()
	end

	sleep(0.2)
end

print("zayum, its quiet in here ...")