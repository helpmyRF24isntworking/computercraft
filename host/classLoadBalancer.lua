
local utils = require("utils")
local euclideanDistance = utils.euclideanDistance
local squaredDistance = utils.squaredDistance
local squaredDistancePos = utils.squaredDistancePos

local LoadBalancer = {}
LoadBalancer.__index = LoadBalancer

local tableinsert = table.insert
local tableremove = table.remove

local default = {

}


-- seems to work, dont ask me how, developer was drunk
local function hungarian(cost)
    local n = #cost
    local u, v = {}, {}
    local p, way = {}, {}
    for i = 0, n do
        p[i] = 0
        u[i] = 0
        v[i] = 0
        way[i] = 0
    end
    for i = 1, n do
        p[0] = i
        local minv = {}
        local used = {}
        for j = 0, n do
            minv[j] = math.huge
            used[j] = false
        end
        local j0 = 0
        repeat
            used[j0] = true
            local i0 = p[j0]
            local delta, j1 = math.huge, 0
            for j = 1, n do
                if not used[j] then
                    local cur = cost[i0][j] - u[i0] - v[j]
                    if cur < minv[j] then
                        minv[j] = cur
                        way[j] = j0
                    end
                    if minv[j] < delta then
                        delta = minv[j]
                        j1 = j
                    end
                end
            end
            for j = 0, n do
                if used[j] then
                    u[p[j]] = u[p[j]] + delta
                    v[j] = v[j] - delta
                else
                    minv[j] = minv[j] - delta
                end
            end
            j0 = j1
        until p[j0] == 0
        repeat
            local j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        until j0 == 0
    end
    local result = {}
    for j = 1, n do
        result[p[j]] = j
    end
    return result
end


local function kMeans(assignments, k, iterations)
    -- initialize k centroids randomly
    local centroids = {}
    local n = #assignments
    for i = 1, k do
        local pos = assignments[math.random(n)].pos
        centroids[i] = {x = pos.x, y = pos.y, z = pos.z}
    end

    local clusterAssignments = {}
    for iter = 1, iterations do
        local changed = false

        -- assign each assignment to the nearest centroid
        for i = 1, #assignments do
            local assignment = assignments[i]
            local apos = assignment.pos
            local ax, ay, az = apos.x, apos.y, apos.z

            local minId = 1
            local minDist = math.huge
            for j = 1, k do

                local c = centroids[j]
                local dx, dy, dz = ax - c.x, ay - c.y, az - c.z
                local dist = dx * dx + dy * dy + dz * dz

                if dist < minDist then
                    minDist = dist
                    minId = j
                end

            end
            if clusterAssignments[i] ~= minId then
                clusterAssignments[i] = minId
                changed = true
            end
        end

        -- update centroids

        local sums, counts = {}, {}
        for j = 1, k do
            sums[j] = {x = 0, y = 0, z = 0}
            counts[j] = 0
        end
        for i = 1, n do
            local cid = clusterAssignments[i]
            local pos = assignments[i].pos
            local sum = sums[cid]
            sum.x = sum.x + pos.x
            sum.y = sum.y + pos.y
            sum.z = sum.z + pos.z
            counts[cid] = counts[cid] + 1
        end
        for j = 1, k do
            local count = counts[j]
            if count > 0 then
                local sum = sums[j]
                local c = centroids[j]
                c.x = sum.x / count
                c.y = sum.y / count
                c.z = sum.z / count
            end
        end
        if not changed then break end
    end

    -- build clusters again
    local clusters = {}
    for j = 1, k do clusters[j] = {} end
    for i = 1, n do 
        local cid = clusterAssignments[i]
        tableinsert(clusters[cid], assignments[i])
    end

    return clusters, centroids
end

local function rebalanceClusters(clusters, centroids, targetSize)
    -- based on difference we want to rebalance the clusters so they have the same size
    -- farthest point from overfilled cluster -> closest underfilled cluster

    local k = #clusters
    local changed = true

    local minSize = math.floor(targetSize)
    local maxSize = math.ceil(targetSize)

    while changed do
        changed = false
        -- classify clusters
        local overfull, underfull = {}, {}
        for i = 1, k do
            if #clusters[i] > maxSize then
                tableinsert(overfull, i)
            elseif #clusters[i] < minSize then
                tableinsert(underfull, i)
            end
        end
        if #overfull == 0 or #underfull == 0 then break end

        
        for _, i in ipairs(overfull) do
            local fullCluster = clusters[i]
            while #fullCluster > maxSize and #underfull > 0 do
                -- farthest point from centroid
                local maxDist, maxIdx = -1, 1
                for idx = 1, #fullCluster do
                    local item = fullCluster[idx]
                    local dist = squaredDistancePos(item.pos, centroids[i])
                    if dist > maxDist then
                        maxDist = dist
                        maxIdx = idx
                    end
                end
                local point = tableremove(fullCluster, maxIdx)

                -- closest underfull cluster
                local bestJ, bestDist = underfull[1], math.huge
                for _, j in ipairs(underfull) do
                    local dist = squaredDistancePos(point.pos, centroids[j])
                    if dist < bestDist then
                        bestDist = dist
                        bestJ = j
                    end
                end
                tableinsert(clusters[bestJ], point)
                changed = true

                -- update underfull
                if #clusters[bestJ] >= maxSize then
                    for idx, v in ipairs(underfull) do
                        if v == bestJ then
                            tableremove(underfull, idx)
                            break
                        end
                    end
                end
            end
        end

        -- update centroids for next iteration
        for j = 1, k do
            local cluster = clusters[j]
            local sumX, sumY, sumZ = 0, 0, 0
            local count = #cluster

            for q = 1, count do 
                local item = cluster[q]
                local pos = item.pos
                sumX = sumX + pos.x
                sumY = sumY + pos.y
                sumZ = sumZ + pos.z
            end
            if count > 0 then
                centroids[j] = {x = sumX / count, y = sumY / count, z = sumZ / count}
            else
                centroids[j] = {x = 0, y = 0, z = 0}
            end
        end
    end

    return clusters, centroids
end


function LoadBalancer:new(taskManager)
    local o = {}
    setmetatable(o, self)
    o.taskManager = taskManager
    o.turtles = taskManager.turtles

    return o
end

function LoadBalancer:mergeAssignmets(assignments)
    local all = {}
    for i = 1, #assignments do
        local ass = assignments[i]
        for k = 1, #ass do 
            tableinsert(all, ass[k])
        end
    end
    return all
end



function LoadBalancer:calculateNeededWorkers(project)

    -- project level
    local allItems = project:getAllItems()
    local totalWork = #allItems * project.metrics.avgTimePerItem

    --[[ assignment level
    local totalWork = 0
    for tid, ass in pairs(project.assignments) do
        local items = ass.items 
        local avgTimePerItem = ass.metrics.avgTimePerItem
        if ass.items and ass.metrics.avgTimePerItem then 
            totalWork = totalWork + #items * avgTimePerItem
        end
    end
    --]]

    if totalWork == 0 then return 0 end

    local needed = math.ceil(totalWork/project.itemInterval + 0.25) -- at 4.99 we dont want to assign just 5 turts

    print("total", totalWork, "items", #allItems, "pavg", project.metrics.avgTimePerItem, "needed", needed)
    if needed < 1 then needed = 1 end

    return needed
end


function LoadBalancer:partitionWithKMeans(items, workerCount, maxIterations)
    -- if #items == 0 or workerCount <= 1 then return { items } end

    local targetSize = #items / workerCount
    local clusters, centroids = kMeans(items, workerCount, maxIterations)
    clusters, centroids = rebalanceClusters(clusters, centroids, targetSize)
    return clusters, centroids

end

function LoadBalancer:printCluster(clusters,centroids)
    print("cluster", #clusters)
    for i = 1, #clusters do 
        print(i, "items", #clusters[i], "centroid", textutils.serialize(centroids[i], {compact = true}))
    end
end
function LoadBalancer:balanceProject(project)

    local allItems = project:getAllItems()
    local assignedTurts = project:getAssignedTurtles()
    local ct, availableTurts = global.taskManager:getAvailableTurtles()
    local totalTurts = #assignedTurts + #availableTurts
    local newWorkerCount = self:calculateNeededWorkers(project)
    if newWorkerCount > totalTurts then newWorkerCount = totalTurts end

    local prvWorkerCount = #assignedTurts
    local reassignments, centroids = self:partitionWithKMeans(allItems, newWorkerCount, 100)
    self:printCluster(reassignments, centroids)

    local selectedTurts = self:selectTurtles(assignedTurts, availableTurts, centroids)
    local turtReassignments = self:reassignTurtles(selectedTurts, reassignments, centroids)

    print("rebalanced", "totalItems", #allItems, "neededWorkers", newWorkerCount, "assignedWorkers", #assignedTurts, "availableWorkers", #availableTurts)
    print("reassignments", textutils.serialize(turtReassignments, {compact = true, allow_repetitions = true}))
    print("centroids", textutils.serialize(centroids, {compact = true, allow_repetitions = true}))
    return turtReassignments
end

function LoadBalancer:balanceAssignments(assignments, assignedTurts, availableTurts)
    -- TODO we need the workers utilization, to either increase, rebalance or even reduce the workers
    local prvWorkerCount = #assignments
    local newWorkerCount = prvWorkerCount + 1
    local total = #assignedTurts + #availableTurts
    if total < newWorkerCount then newWorkerCount = total end

    local all = self:mergeAssignmets(assignments)
    local reassignments, centroids = kMeans(all, newWorkerCount, 100)

    local selectedTurts = self:selectTurtles(assignedTurts, availableTurts, centroids)
    local turtReassignments = self:reassignTurtles(selectedTurts, reassignments, centroids)
    return turtReassignments
end

function LoadBalancer:selectTurtles(assigned, available, centroids)
    -- select which turtles should be assigned for the project
    local selected = {}
    local k = #centroids
    local selectedCount = 0
    for _, turt in pairs(assigned) do
        if selectedCount < k then
            tableinsert(selected, turt)
            selectedCount = selectedCount + 1
        end
    end

    -- for new turtles we select the ones closest to any of the centroids
    -- in theory we should use hungarian here as well but it scales with n^3

    if selectedCount < k then
        local newTurts = {}
        for _, turt in pairs(available) do
            local tpos = turt.state.pos
            local tx, ty, tz = tpos.x, tpos.y, tpos.z
            local minDist = math.huge
            for j = 1, k do
                local cpos = centroids[j]
                local dx, dy, dz = tx - cpos.x, ty - cpos.y, tz - cpos.z
                local dist = dx * dx + dy * dy + dz * dz
                if dist < minDist then
                    minDist = dist
                end
            end
            tableinsert(newTurts, {turt = turt, dist = minDist})
        end
        table.sort(newTurts, function(a,b) return a.dist < b.dist end)
        for i = 1, #newTurts do
            if selectedCount < k then
                tableinsert(selected, newTurts[i].turt)
                selectedCount = selectedCount + 1
            end
        end
    end

    if selectedCount < k then 
        print("NOT ENOUGH TURTLES FOR LOAD BALANCING, NEED", k, "SELECTED", selectedCount)
    end

    return selected
end

function LoadBalancer:reassignTurtles(turtles, reassignments, centroids)
    -- assign the nearest turtle to the nearest centroid, using hungarian
    local costs = {}
    local turts = {}
    for id, turt in pairs(turtles) do tableinsert(turts, turt) end

    local k = #centroids
    for i = 1, #turts do 
        local tpos = turts[i].state.pos
        local tx, ty, tz = tpos.x, tpos.y, tpos.z
        local tcosts = {}
        costs[i] = tcosts
        for j = 1, k do 
            local cpos = centroids[j]
            local dx, dy, dz = tx - cpos.x, ty - cpos.y, tz - cpos.z
            local dist = dx * dx + dy * dy + dz * dz
            tcosts[j] = dist
        end
    end
    local assignment = hungarian(costs)
    local turtReassinments = {}
    for i = 1, #assignment do
        local turt = turts[i]
        local cid = assignment[i]
        turtReassinments[turt.state.id] = reassignments[cid]
    end
    return turtReassinments

end


return LoadBalancer