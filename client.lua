local QBCore = exports['qb-core']:GetCoreObject()

local function hasAllowedWeapon()
    -- Enforce pistol-only requirement regardless of config
    local weapon = GetSelectedPedWeapon(PlayerPedId())
    return weapon == GetHashKey('weapon_pistol')
end

local function loadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        local t0 = GetGameTimer()
        while not HasAnimDictLoaded(dict) do
            Wait(10)
            if GetGameTimer() - t0 > 2000 then break end
        end
    end
end

-- Add target option for Peds via qb-target (dynamic registration for all nearby peds)
Citizen.CreateThread(function()
    if not exports['qb-target'] then return end

    local registered = {}

    while true do
        local playerPed = PlayerPedId()
        local pPos = GetEntityCoords(playerPed)
        local handle, ped = FindFirstPed()
        local success
        repeat
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                local pedNet = nil
                    if NetworkGetEntityIsNetworked(ped) then pedNet = PedToNet(ped) end
                if pedNet and not registered[pedNet] then
                    local pedModel = GetEntityModel(ped)
                    local blacklisted = false
                    for _, m in ipairs(Config.PedBlacklist) do
                        if GetHashKey(m) == pedModel then blacklisted = true break end
                    end
                    if not blacklisted then
                        local dist = #(pPos - GetEntityCoords(ped))
                        if dist <= Config.TargetDistance + 1.0 then
                            -- register this ped with qb-target
                            exports['qb-target']:AddTargetEntity(ped, {
                                options = {{
                                    icon = "fas fa-hand-paper",
                                    label = Config.TargetLabel,
                                    event = 'jlee-robnpc:client:InitiateRob',
                                    type = 'client'
                                }},
                                distance = Config.TargetDistance
                            })
                            registered[pedNet] = true
                        end
                    end
                end
            end
            success, ped = FindNextPed(handle)
        until not success
        EndFindPed(handle)

        -- cleanup registered map for peds no longer around
        for netId,_ in pairs(registered) do
            local ent = nil
            if netId and netId ~= 0 then ent = NetToPed(netId) end
            if not DoesEntityExist(ent) or #(GetEntityCoords(ent) - pPos) > Config.TargetDistance + 5.0 then
                registered[netId] = nil
            end
        end

        Wait(2000)
    end
end)

-- Initiate rob flow
RegisterNetEvent('jlee-robnpc:client:InitiateRob', function(entity)
    -- qb-target may pass either a plain entity id (number) or an option table like {entity = <id>}.
    -- Normalize the incoming value to a numeric ped entity to avoid native type errors.
    local ped = entity
    if type(ped) == 'table' and ped.entity then ped = ped.entity end
    if type(ped) ~= 'number' then return end

    local playerPed = PlayerPedId()

    if not DoesEntityExist(ped) then return end
    if IsPedAPlayer(ped) then QBCore.Functions.Notify('That is a player.', 'error') return end
    if not hasAllowedWeapon() then QBCore.Functions.Notify('You need a weapon to rob.', 'error') return end

    -- ensure ped is networked and record start attempt with server
    local netId = nil
    if NetworkGetEntityIsNetworked(ped) then
        netId = PedToNet(ped) -- use PedToNet only if entity is networked
    else
        -- entity isn't networked, abort gracefully to avoid native warning spam
        QBCore.Functions.Notify('NPC is not networked. Move closer and try again.', 'error')
        return
    end

    -- Ask server whether robbing is allowed (police requirement)
    QBCore.Functions.TriggerCallback('jlee-robnpc:server:canRob', function(can, msg)
        if not can then
            QBCore.Functions.Notify(msg or 'Not enough police online to commit this crime.', 'error')
            return
        end

        -- Tell server we are starting an attempt (server will record/validate briefly)
        TriggerServerEvent('jlee-robnpc:server:startAttempt', netId)

        -- Freeze & hands up
        if Config.FreezePed then
            FreezeEntityPosition(ped, true)
        end
    end)

    loadAnimDict(Config.HandsUpAnim.dict)
    TaskPlayAnim(ped, Config.HandsUpAnim.dict, Config.HandsUpAnim.anim, 8.0, -8.0, Config.RobDuration/1000, 1, 0, false, false, false)

    -- play player animation briefly (pointing/rob gesture)
    loadAnimDict('random@arrests')
    TaskPlayAnim(playerPed, 'random@arrests', 'confined_to_stand_loop', 8.0, -8.0, Config.RobDuration/1000, 49, 0, false, false, false)

    local function finishRob()
        TriggerServerEvent('jlee-robnpc:server:attempt', netId)
    end

    -- Use progressbar if available. Support QBCore.Functions.Progressbar or exports['progressbar'] fallback
    if Config.UseProgressBar then
        local used = false
        if QBCore and QBCore.Functions and QBCore.Functions.Progressbar then
            used = true
            QBCore.Functions.Progressbar('rob_ped', Config.ProgressLabel or Config.TargetLabel or 'Robbing', Config.RobDuration, false, true, {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            }, {}, {}, {}, function()
                finishRob()
            end, function()
                -- cancelled
                if DoesEntityExist(ped) then
                    FreezeEntityPosition(ped, false)
                    ClearPedTasks(ped)
                end
                ClearPedTasks(PlayerPedId())
            end)
        elseif exports['progressbar'] then
            used = true
            exports['progressbar']:Start(Config.RobDuration, Config.ProgressLabel or Config.TargetLabel or 'Robbing')
            Citizen.SetTimeout(Config.RobDuration, function()
                finishRob()
            end)
        end
        if not used then
            -- no progressbar available, fallback
            Wait(Config.RobDuration)
            finishRob()
        end
    else
        -- fallback: simple wait then finish
        Wait(Config.RobDuration)
        finishRob()
    end
    Wait(Config.RobDuration)

    -- unfreeze ped but do NOT clear ped tasks here; clearing can interrupt the upcoming attack
    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
    end
    ClearPedTasks(playerPed)
end)

-- Client: handle server telling ped to attack player
RegisterNetEvent('jlee-robnpc:client:PedAttack', function(netId, instigatorSrc)
    if Config.Debug then print("[rob-npc][client] PedAttack received, netId=", tostring(netId), "instigator=", tostring(instigatorSrc)) end

    local ped = nil
    if type(netId) == 'number' and netId ~= 0 then
        ped = NetToPed(netId)
    end

    local playerPed = PlayerPedId()

    if not ped or not DoesEntityExist(ped) then
        if Config.Debug then print("[rob-npc][client] NetToPed returned invalid entity for netId", tostring(netId)) end
        return
    end

    -- if ped is dead or ragdolled, ignore
    if IsPedDeadOrDying(ped, true) then
        if Config.Debug then print("[rob-npc][client] Ped is dead or dying, aborting attack") end
        return
    end

    -- equip pistol only and set ped hostile (force no weapon changes)
    local choice = 'weapon_pistol'
    local wepHash = GetHashKey(choice)

    -- simple give with verification
    GiveWeaponToPed(ped, wepHash, 50, false, true)
    Citizen.Wait(100)
    if HasPedGotWeapon(ped, wepHash, false) then
        SetCurrentPedWeapon(ped, wepHash, true)
        SetPedCurrentWeaponVisible(ped, true, true, true, true)
        if Config.Debug then print("[rob-npc][client] Gave forced weapon_pistol to ped") end
    else
        if Config.Debug then print("[rob-npc][client] Failed to give forced weapon_pistol to ped") end
    end

    SetCurrentPedWeapon(ped, wepHash, true)
    SetPedCanSwitchWeapon(ped, true)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedAsEnemy(ped, true)
    SetPedRelationshipGroupHash(ped, GetHashKey("ENEMY"))
    SetRelationshipBetweenGroups(5, GetHashKey("ENEMY"), GetHashKey("PLAYER"))
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, 0)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedAccuracy(ped, 60)
    ClearPedTasksImmediately(ped)
    Citizen.Wait(50)
    TaskCombatPed(ped, playerPed, 0, 16)
    SetPedCombatAttributes(ped, 46, true) -- can use weapons
    SetPedCombatAbility(ped, 100)

    if Config.Debug then print("[rob-npc][client] Started combat task for ped", tostring(ped)) end

    Citizen.SetTimeout(Config.AttackTime or 10000, function()
        if DoesEntityExist(ped) then
            ClearPedTasks(ped)
            SetPedAsNoLongerNeeded(ped)
            if Config.Debug then print("[rob-npc][client] Cleared combat tasks for ped", tostring(ped)) end
        end
    end)
end)

-- Dispatch alert handler for police clients
RegisterNetEvent('jlee-robnpc:client:dispatchAlert', function(data)
    if not data then return end
    local pedNetId = data.pedNetId
    local offender = data.offender
    -- try resolve ped position if available
    local coords = nil
    if pedNetId and pedNetId ~= 0 then
        local ped = NetToPed(pedNetId)
        if DoesEntityExist(ped) then coords = GetEntityCoords(ped) end
    end
    -- notify police
    QBCore.Functions.Notify('Robbery in progress nearby!', 'error')
    -- create a temporary blip at location if resolved
    if coords then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        local sprite = (Config.DispatchBlip and Config.DispatchBlip.sprite) or 161
        local color = (Config.DispatchBlip and Config.DispatchBlip.color) or 1
        local scale = (Config.DispatchBlip and Config.DispatchBlip.scale) or 1.0
        SetBlipSprite(blip, sprite)
        SetBlipColour(blip, color)
        SetBlipScale(blip, scale)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Robbery Alert')
        EndTextCommandSetBlipName(blip)
        Citizen.SetTimeout((Config.DispatchBlipTime or 60000), function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end)
    end
end)

-- Debug helper: draw ped netid
Citizen.CreateThread(function()
    while true do
        if Config.Debug then
            local playerPed = PlayerPedId()
            local pos = GetEntityCoords(playerPed)
            local handle, ped = FindFirstPed()
            local success
            repeat
                local pedPos = GetEntityCoords(ped)
                if #(pos - pedPos) < 10.0 then
                    local netId = PedToNet(ped)
                    DrawText3D(pedPos.x, pedPos.y, pedPos.z + 1.0, tostring(netId))
                end
                success, ped = FindNextPed(handle)
            until not success
            EndFindPed(handle)
        end
        Wait(1000)
    end
end)

-- small utility for drawing 3D text (debug)
function DrawText3D(x,y,z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x,y,z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

-- End of client.lua
