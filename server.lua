local QBCore = exports['qb-core']:GetCoreObject()

local pedCooldowns = {} -- [pedNetId] = expiryTimestamp (epoch seconds)
local playerRobCounts = {} -- [playerId] = consecutiveRobCount
local playerCooldowns = {} -- [playerId] = expiryTimestamp (epoch seconds)
local pendingAttempts = {} -- [src] = {pedNetId = <num>, ts = <os.time()>}
local lastAttemptTime = {} -- [src] = epoch seconds for simple rate limit

local function debug(...) if Config.Debug then print('[rob-npc][server]', ...) end end

local function inCooldown(pedNet)
    if not pedNet then return false end
    local expires = pedCooldowns[pedNet]
    if not expires then return false end
    return expires > os.time()
end

local function countOnlineCops()
    if not QBCore or not QBCore.Functions or not QBCore.Functions.GetPlayers then return 0 end
    local players = QBCore.Functions.GetPlayers()
    local cnt = 0
    for _, pid in ipairs(players) do
        local ply = QBCore.Functions.GetPlayer(pid)
        if ply and ply.PlayerData and ply.PlayerData.job then
            local job = ply.PlayerData.job
            if job.name == (Config.PoliceJobName or 'police') then
                if Config.RequirePoliceOnDuty then
                    if job.onduty == true then
                        cnt = cnt + 1
                    end
                else
                    cnt = cnt + 1
                end
            end
        end
    end
    return cnt
end

-- Client signals an intent to start robbing a ped. Server records this briefly and rate-limits.
RegisterNetEvent('jlee-robnpc:server:startAttempt', function(pedNetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    pedNetId = tonumber(pedNetId)
    if not pedNetId then return end

    -- simple per-player rate limit: one attempt every 2 seconds
    local now = os.time()
    if lastAttemptTime[src] and (now - lastAttemptTime[src]) < 2 then
        debug('startAttempt: rate limited for', src)
        return
    end
    lastAttemptTime[src] = now

    -- store pending attempt with timestamp; will be validated by the actual AttemptRob call
    pendingAttempts[src] = { pedNetId = pedNetId, ts = now }
    debug('Recorded pending attempt for', src, 'pedNetId=', pedNetId)

    -- Dispatch alert to police when a robbery is started (configurable)
    if Config.EnableDispatch then
        debug('Dispatch enabled - sending alerts to police')

        -- Only attempt external PS-Dispatch integration when explicitly set to 'ps-dispatch'.
        -- Otherwise the built-in internal dispatch is used by default.
        if Config.ExternalDispatch == 'ps-dispatch' then
            local ok = false
            local data = {
                title = 'Robbery in progress',
                coords = nil,
                offender = src,
                pedNetId = pedNetId,
                priority = 2
            }
            -- Try common ps-dispatch event names
            if pcall(function() TriggerEvent('ps-dispatch:send', data) end) then ok = true end
            if not ok and pcall(function() TriggerEvent('ps-dispatch:call', data) end) then ok = true end
            if ok then
                debug('ps-dispatch handled the robbery dispatch')
            else
                debug('ps-dispatch not available; falling back to internal dispatch')
            end
        end

        -- Internal fallback: send client event to police players (keeps previous logic)
        for _, pid in ipairs(QBCore.Functions.GetPlayers() or {}) do
            local ply = QBCore.Functions.GetPlayer(pid)
            if ply and ply.PlayerData and ply.PlayerData.job then
                local job = ply.PlayerData.job
                if job.name == (Config.PoliceJobName or 'police') then
                    if pid == src then
                        debug('Skipping offender when sending dispatch:', pid)
                    else
                        if Config.RequirePoliceOnDuty then
                            if job.onduty == true then
                                debug('Sending dispatch to on-duty police player', pid)
                                TriggerClientEvent('jlee-robnpc:client:dispatchAlert', pid, { offender = src, pedNetId = pedNetId })
                            else
                                debug('Skipping police player (not on duty):', pid)
                            end
                        else
                            debug('Sending dispatch to police player', pid)
                            TriggerClientEvent('jlee-robnpc:client:dispatchAlert', pid, { offender = src, pedNetId = pedNetId })
                        end
                    end
                end
            end
        end
    else
        debug('Dispatch disabled in config')
    end
end)

-- Main attempt handler: only accepts actual source (no srcOverride). Ensures a recent pending attempt exists.
RegisterNetEvent('jlee-robnpc:server:attempt', function(pedNetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    debug('attempt called by', src, 'pedNetId=', tostring(pedNetId))

    if not pedNetId then return end
    pedNetId = tonumber(pedNetId)
    if not pedNetId then return end

    -- Validate that the client previously told the server it started an attempt for this ped
    local pending = pendingAttempts[src]
    if not pending or pending.pedNetId ~= pedNetId then
        debug('No matching pending attempt for', src, 'expected pedNetId=', pending and pending.pedNetId or 'nil')
        return
    end
    -- allow a short window (e.g., 10 seconds) for the client to finish
    if os.time() - pending.ts > math.ceil((Config.RobDuration or 7000) / 1000) + 10 then
        debug('Pending attempt expired for', src)
        pendingAttempts[src] = nil
        return
    end
    -- consume pending attempt
    pendingAttempts[src] = nil

    -- enforce configured player cooldown (Config.PlayerCooldown is ms)
    local pExpires = playerCooldowns[src]
    if pExpires and pExpires > os.time() then
        TriggerClientEvent('QBCore:Notify', src, 'You must wait before trying to rob again.', 'error')
        return
    end

    if inCooldown(pedNetId) then
        TriggerClientEvent('QBCore:Notify', src, 'This person is too shaken up, try someone else', 'error')
        return
    end

    -- Police requirement check
    if Config.UsePoliceRequirement then
        local cops = countOnlineCops()
        local req = tonumber(Config.MinPolice) or 1
        debug('Police check: found', cops, 'required', req)
        if cops < req then
            TriggerClientEvent('QBCore:Notify', src, 'Not enough police are online to commit this crime.', 'error')
            return
        end
    end

    -- Determine attack first. If an attack will occur, do NOT give rewards.
    local chance = Config.AttackChance or 30 -- percent
    local willAttack = false
    if chance == 100 then
        willAttack = true
    else
        local roll = math.random(1,100)
        debug('Attack roll for', src, '=', roll, 'vs chance', chance)
        if roll <= chance then willAttack = true end
    end

    if willAttack then
        -- notify only the instigator client to make ped attack
        TriggerClientEvent('jlee-robnpc:client:PedAttack', src, pedNetId, src)
        debug('Triggered NPC attack for', src, 'pedNetId=', pedNetId)
        TriggerClientEvent('QBCore:Notify', src, 'The person fought back! No reward.', 'error')
        -- set ped cooldown and reset counters, but skip any rewards
        playerRobCounts[src] = 0
        pedCooldowns[pedNetId] = os.time() + math.floor((Config.PedCooldown or 300000) / 1000)
        debug('Set cooldown for', pedNetId, 'until', pedCooldowns[pedNetId])
        return
    end

    -- Give rewards server-side (validate server decides amounts)
    local cashMin = Config.Rewards and Config.Rewards.cash and Config.Rewards.cash.min or 0
    local cashMax = Config.Rewards and Config.Rewards.cash and Config.Rewards.cash.max or 0
    if cashMin and cashMax and cashMax >= cashMin then
        local cash = math.random(cashMin, cashMax)
        if cash and cash > 0 then
            local ok, err = pcall(function()
                Player.Functions.AddMoney('cash', cash, 'robbed-npc')
            end)
            if not ok then
                debug('AddMoney error for', src, err)
            else
                debug('Gave cash', cash, 'to', src)
                TriggerClientEvent('QBCore:Notify', src, 'Found $'..cash, 'success')
            end
        end
    end

    -- Items (validate amounts and clamp to sane bounds)
    if Config.Rewards and Config.Rewards.items then
        for _, item in ipairs(Config.Rewards.items) do
            if math.random(1,100) <= (item.chance or 0) then
                local minAmt = math.max(1, tonumber(item.min) or 1)
                local maxAmt = math.max(minAmt, tonumber(item.max) or minAmt)
                -- clamp maximum amount to 100 to avoid huge grants
                maxAmt = math.min(maxAmt, 100)
                local amt = math.random(minAmt, maxAmt)
                if amt and amt > 0 then
                    local added = false
                    local addErr = nil

                    local ok, ierr = pcall(function()
                        if Player and Player.Functions and Player.Functions.AddItem then
                            Player.Functions.AddItem(item.name, amt)
                            added = true
                        end
                    end)
                    if not ok then addErr = ierr end

                    if not added then
                        ok, ierr = pcall(function()
                            if QBCore and QBCore.Functions and QBCore.Functions.AddItem then
                                QBCore.Functions.AddItem(src, item.name, amt)
                                added = true
                            end
                        end)
                        if not ok and not addErr then addErr = ierr end
                    end

                    if not added then
                        ok, ierr = pcall(function()
                            if exports and exports['qb-inventory'] and exports['qb-inventory'].AddItem then
                                exports['qb-inventory'].AddItem(src, item.name, amt)
                                added = true
                            end
                        end)
                        if not ok and not addErr then addErr = ierr end
                    end

                    if added then
                        TriggerClientEvent('QBCore:Notify', src, 'Found '..amt..'x '..item.name, 'success')
                        debug('Gave item to', src, item.name, amt)
                    else
                        debug('AddItem failed for', src, item.name, 'err=', tostring(addErr))
                    end
                end
            else
                debug('Missed item roll for', src, item.name)
            end
        end
    end

    TriggerClientEvent('jlee-robnpc:client:onRobSuccess', src, pedNetId)

    -- Track consecutive robberies for this player and maybe trigger an NPC attack
    playerRobCounts[src] = (playerRobCounts[src] or 0) + 1
    debug('Player', src, 'consecutive robs =', playerRobCounts[src])
    playerRobCounts[src] = 0

    -- set ped cooldown (Config.PedCooldown is ms -> convert to seconds)
    pedCooldowns[pedNetId] = os.time() + math.floor((Config.PedCooldown or 300000) / 1000)
    debug('Set cooldown for', pedNetId, 'until', pedCooldowns[pedNetId])

    -- set player cooldown (use Config.PlayerCooldown ms value)
    playerCooldowns[src] = os.time() + math.floor((Config.PlayerCooldown or 120000) / 1000)
    debug('Set player cooldown for', src, 'until', playerCooldowns[src])
end)

-- Admin/utility: clear cooldown for a ped (restricted to job 'admin')
RegisterNetEvent('jlee-robnpc:server:clearCooldown', function(pedNetId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local jobName = Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name
    if jobName ~= 'admin' then
        debug('clearCooldown denied for', src, 'job=', tostring(jobName))
        return
    end
    pedCooldowns[pedNetId] = nil
    debug('clearCooldown executed by', src, 'for pedNetId', tostring(pedNetId))
end)

-- Optional: provide a server callback to check cooldown
QBCore.Functions.CreateCallback('jlee-robnpc:server:isPedCooldown', function(source, cb, pedNetId)
    cb(inCooldown(pedNetId))
end)

-- Server callback to check police requirement and return whether player can rob now
QBCore.Functions.CreateCallback('jlee-robnpc:server:canRob', function(source, cb)
    if not Config.UsePoliceRequirement then
        cb(true)
        return
    end
    local cops = countOnlineCops()
    local req = tonumber(Config.MinPolice) or 1
    if cops >= req then
        cb(true)
    else
        cb(false, ('Not enough police online (%d/%d)'):format(cops, req))
    end
end)

-- Backwards-compatible alias: some clients call the event with different casing/name
RegisterNetEvent('jlee-robnpc:server:AttemptRob', function(pedNetId)
    -- forward to the main handler using TriggerEvent preserves source when invoked locally
    -- This alias only triggers the same server handler; do NOT accept external source overrides.
    TriggerEvent('jlee-robnpc:server:attempt', pedNetId)
end)
