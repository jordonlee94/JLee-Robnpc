local QBCore = exports['qb-core']:GetCoreObject()
local Config = Config or _G.Config or (function() return Config end)()

-- Server-side tracking
local lastMedicUse = {} -- [citizenid] = os.time()
local activeCalls = {} -- [citizenid] = { source = src, type = 'npc'|'ambulance', timestamp = os.time(), expires = os.time()+X, billed = false }
local callCounts = {} -- rate-limiting per source: [source] = {count, windowStart}

-- Whitelist helper for models
local function isModelAllowed(name, allowedList)
    if not name then return false end
    for _, v in ipairs(allowedList or {}) do if tostring(v) == tostring(name) then return true end end
    return false
end

-- Logging helper
local function logEvent(msg)
    print(('[jlee-aimedic] %s'):format(msg))
    if Config.EnableLogging and Config.WebhookURL and Config.WebhookURL ~= '' then
        local data = { content = msg }
        PerformHttpRequest(Config.WebhookURL, function() end, 'POST', json.encode(data), { ['Content-Type'] = 'application/json' })
    end
end

-- Count on-duty ambulance players
local function countAmbulanceOnline()
    local players = QBCore.Functions.GetPlayers()
    local count = 0
    for _, pid in ipairs(players) do
        local ply = QBCore.Functions.GetPlayer(pid)
        if ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == (Config.AmbulanceJobName or 'ambulance') then
            if ply.PlayerData.job.onduty then
                count = count + 1
            end
        end
    end
    return count
end

-- Rate-limit check
local function canMakeCall(src, cid)
    local window = Config.CallerRateWindow or 60
    local maxCalls = Config.CallerMaxCallsPerWindow or 3
    local key = cid or tostring(src)
    local data = callCounts[key]
    local now = os.time()
    if not data or (now - (data.windowStart or 0)) > window then
        callCounts[key] = { count = 1, windowStart = now }
        return true
    end
    if data.count >= maxCalls then return false end
    data.count = data.count + 1
    return true
end


-- Server check: can player use /medic? returns via response event
RegisterNetEvent('jlee-aimedic:requestUseCheck', function()
    local src = source
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then
        TriggerClientEvent('jlee-aimedic:responseUseCheck', src, false, 'player_not_found')
        return
    end

    local cid = ply.PlayerData.citizenid or tostring(src)
    local ambulances = countAmbulanceOnline()
    local required = Config.RequiredAmbulancesOnline or 1

    if ambulances >= required then
        if not (ply.PlayerData.job and ply.PlayerData.job.name == (Config.AmbulanceJobName or 'ambulance')) then
            TriggerClientEvent('jlee-aimedic:responseUseCheck', src, false, 'ambulance_online_restriction')
            return
        end
    end

    local now = os.time()
    local last = lastMedicUse[cid]
    local cd = Config.MedicCooldown or Config.Cooldown or 600
    if last and (now - last) < cd then
        local remaining = cd - (now - last)
        TriggerClientEvent('jlee-aimedic:responseUseCheck', src, false, 'cooldown', remaining)
        return
    end

    -- rate-limit
    if not canMakeCall(src, cid) then
        TriggerClientEvent('jlee-aimedic:responseUseCheck', src, false, 'rate_limited')
        return
    end

    TriggerClientEvent('jlee-aimedic:responseUseCheck', src, true)
end)

-- Mark usage (set cooldown) called when player actually requests menu/action
RegisterNetEvent('jlee-aimedic:markUsed', function()
    local src = source
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return end
    local cid = ply.PlayerData.citizenid or tostring(src)
    lastMedicUse[cid] = os.time()
end)

-- Request spawn: client asks server to spawn medic/ambulance. Server validates and then triggers client-side spawn.
RegisterNetEvent('jlee-aimedic:requestSpawn', function(choice, coords)
    local src = source
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return end
    local cid = ply.PlayerData.citizenid or tostring(src)
    choice = tostring(choice or '')
    if not (choice == 'npc' or choice == 'ambulance') then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid spawn request', 'error')
        return
    end

    -- enforce max simultaneous medics
    local activeCount = 0
    for _, v in pairs(activeCalls) do activeCount = activeCount + 1 end
    if activeCount >= (Config.MaxSimultaneousMedics or 3) then
        TriggerClientEvent('QBCore:Notify', src, 'System busy, please try again later', 'error')
        return
    end

    -- validate coords if provided (prevent arbitrary far spawns)
    if coords and type(coords) == 'table' and Config.EnforceMaxCallDistance then
        -- Server cannot call client natives; try to use player data position if available
        local valid = true
        local px, py, pz = nil, nil, nil
        if ply and ply.PlayerData and ply.PlayerData.position then
            local pos = ply.PlayerData.position
            px, py, pz = pos.x or pos[1], pos.y or pos[2], pos.z or pos[3]
        end
        if not px then
            -- Unable to verify distance server-side; reject to be safe
            TriggerClientEvent('QBCore:Notify', src, 'Unable to verify spawn location server-side', 'error')
            return
        end
        local dx,dy,dz = coords.x - px, coords.y - py, coords.z - pz
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist > (Config.MaxCallDistance or 100.0) then
            TriggerClientEvent('QBCore:Notify', src, 'Spawn location too far away', 'error')
            return
        end
    end

    -- whitelist models (safety)
    if not isModelAllowed(Config.MedicPed, Config.MedicPedFallbacks) and not isModelAllowed(Config.AmbulanceModel, {Config.AmbulanceModel}) then
        -- no-op: keep compatibility, but ensure strings exist
    end

    -- create active call record and give it a short expiry, key by citizenid
    activeCalls[cid] = { source = src, type = choice, timestamp = os.time(), expires = os.time() + (Config.AmbulanceOverallTimeout or 300), billed = false }

    -- trigger client-side spawn (server-initiated) - use client events that the client listens for
    if choice == 'npc' then
        TriggerClientEvent('jlee-aimedic:clientCallAIMedic', src, { coords = coords })
        logEvent(('Player %s (%s) requested NPC medic'):format(ply.PlayerData.citizenid or '-', GetPlayerName(src)))
    else
        TriggerClientEvent('jlee-aimedic:clientCallAmbulance', src, { coords = coords })
        logEvent(('Player %s (%s) requested AI ambulance'):format(ply.PlayerData.citizenid or '-', GetPlayerName(src)))
    end
end)

-- Billing: charge player for npc revive or ambulance dropoff.
-- Only allow billing if player has an active call that matches the type (prevents arbitrary client billing)
RegisterNetEvent('jlee-aimedic:charge', function(requestedType)
    local src = source
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return end
    local cid = ply.PlayerData.citizenid or tostring(src)
    local active = activeCalls[cid]
    if not active or not active.type then
        TriggerClientEvent('QBCore:Notify', src, 'No active medical call found for billing', 'error')
        return
    end

    -- Only allow billing once per active call
    if active.billed then
        TriggerClientEvent('QBCore:Notify', src, 'You have already been billed for this call', 'error')
        return
    end

    if requestedType ~= active.type then
        TriggerClientEvent('QBCore:Notify', src, 'Billing type mismatch', 'error')
        return
    end

    -- Jobs exempt from billing
    local exemptJobs = Config.BillingExemptJobs or { (Config.AmbulanceJobName or 'ambulance'), 'police' }
    local playerJob = ply.PlayerData.job and ply.PlayerData.job.name or ''
    for _, j in ipairs(exemptJobs) do
        if tostring(playerJob) == tostring(j) then
            active.billed = true
            TriggerClientEvent('QBCore:Notify', src, 'No charge: job exemption applied', 'primary')
            logEvent(('Skipped billing for player %s (%s) due to job exemption (%s)'):format(cid, GetPlayerName(src), tostring(playerJob)))
            return
        end
    end

    local amount = 0
    if requestedType == 'npc' then amount = Config.CostNPC or 500
    elseif requestedType == 'ambulance' then amount = Config.CostAmbulance or 1000 end

    local billed = false
    if ply.Functions.RemoveMoney('bank', amount) then
        TriggerClientEvent('QBCore:Notify', src, ('You were billed $%s for medical services (bank).'):format(amount), 'primary')
        billed = true
    elseif ply.Functions.RemoveMoney('cash', amount) then
        TriggerClientEvent('QBCore:Notify', src, ('You were billed $%s for medical services (cash).'):format(amount), 'primary')
        billed = true
    end

    if not billed then
        TriggerClientEvent('QBCore:Notify', src, 'Unable to bill you for medical services (insufficient funds)', 'error')
    end

    active.billed = true
    logEvent(('Billed player %s (%s) $%s for %s'):format(cid, GetPlayerName(src), tostring(amount), tostring(requestedType)))
end)

-- Cleanup active call when player disconnects
AddEventHandler('playerDropped', function(reason)
    local src = source
    -- remove any activeCalls associated with this source
    for cid, info in pairs(activeCalls) do
        if info and info.source == src then activeCalls[cid] = nil end
    end
end)

-- Server -> client: play revive sound
RegisterNetEvent('jlee-aimedic:playReviveSoundForPlayer', function()
    local src = source
    -- trigger the client event the client actually listens for
    TriggerClientEvent('jlee-aimedic:client:playReviveSound', src)
end)

-- Simple server revive logger
RegisterNetEvent('jlee-aimedic:reviveServer', function(success)
    local src = source
    local name = GetPlayerName(src)
    if success then
        logEvent(('%s was revived successfully.'):format(name))
    else
        logEvent(('%s revival attempt failed.'):format(name))
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        print('[jlee-aimedic] server.lua loaded (secured)')
    end
end)
