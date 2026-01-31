
local utils = {}



local abs = math.abs
local min = math.min
local max = math.max
local floor = math.floor
local mathrandom = math.random

local tableinsert = table.insert
local stringgsub = string.gsub
local stringformat = string.format

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


utils.gpsLocate = function()
    local pos = nil
    local x,y,z
    if gps then 
        x, y, z = gps.locate()
        if x and y and z then
            x, y, z = floor(x), floor(y), floor(z)
            pos = vector.new(x, y, z)
        end
    end
    return pos
end

function utils.generateUUID(simple)
    if simple then
        return mathrandom(1, 2147483647)
    else 
        local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return stringgsub(template, '[xy]', function (c)
            local v = (c == 'x') and mathrandom(0, 0xf) or mathrandom(8, 0xb)
            return stringformat('%x', v)
        end)
    end
end


function utils.callObjectFunction(obj, funcName, args)
    if not args then args = {} end
    local func = "return function(obj,funcName,args) local res = table.pack(obj:"..funcName.."(table.unpack(args))) return table.unpack(res) end"
    return load(func)()(obj, funcName, args)
end

local osClock = os.clock
local startTimer = os.startTimer
local pullEventRaw = os.pullEventRaw
local tickTimers = {}
local cancelledTimers = {}
local lastTick = nil

function utils.sleep(waitTime)
    -- safe sleep function

    -- nil == 0 == 0.05 == 1 tick
    if not waitTime then waitTime = 0
    elseif waitTime == 0.05 then waitTime = 0 end

	local tick = osClock()
    if lastTick ~= tick then
        -- new tick, clear old timers
        tickTimers = {}
        lastTick = tick
    end

	local timer = tickTimers[waitTime]
	if not timer then
		timer = startTimer(waitTime)
		tickTimers[waitTime] = timer
	else
		--print("reusing timer", waitTime, timer)
	end

    local safetyMargin = waitTime + 1
	while true do
		local event, param = pullEventRaw("timer")
		--print(string.format("clock : %10s  param %10s  timer %10s waitTime %10s", osClock(), param, timer, waitTime))
		if event == "timer" then
			if param == timer then
				return
            elseif osClock() - tick > safetyMargin then
                print(timer, "TIMER MISSED", osClock() - tick, "expected", waitTime, "cancelled", cancelledTimers[timer])
                return
            end
		elseif event == "terminate" then
            error("Terminated",0)
        end
            
	end
end

local originalCancelTimer = os.cancelTimer
function utils.cancelTimer(timer)
    cancelledTimers[timer] = true
    print("cancelled timer", timer)
    originalCancelTimer(timer)
end

_G.os.cancelTimer = utils.cancelTimer
_G.sleep = utils.sleep

return utils
