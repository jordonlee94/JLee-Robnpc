local QBCore = exports['qb-core']:GetCoreObject()
local Config = Config or _G.Config or {}

local spawnedEntities = { medic = nil, ambulance = nil, ambulanceDriver = nil }
local isBeingCarried = false

local function playHeartbeatForPlayer(duration)
    local ped = PlayerPedId()
    local name = Config.HeartbeatSoundName or 'HUD_HEALTH_WARNING'
    local set = Config.HeartbeatSoundSet or 'HUD_AWARDS'
    local interval = tonumber(Config.HeartbeatInterval) or 1000
    local sid = GetSoundId()
    pcall(function() PlaySoundFromEntity(sid, name, ped, set, true, 0) end)
    local t0 = GetGameTimer()
    while GetGameTimer() - t0 < duration do
        Wait(interval)
        pcall(function() PlaySoundFromEntity(sid, name, ped, set, true, 0) end)
    end
    pcall(StopSound, sid); pcall(ReleaseSoundId, sid)
end

local function requestAudioBank(set)
    if not set or set == '' then return end
    RequestScriptAudioBank(set, false)
    Wait(200)
end

RegisterNetEvent('jlee-aimedic:cleanup', function()
    if spawnedEntities.medic and DoesEntityExist(spawnedEntities.medic) then DeleteEntity(spawnedEntities.medic) end
    if spawnedEntities.ambulanceDriver and DoesEntityExist(spawnedEntities.ambulanceDriver) then DeleteEntity(spawnedEntities.ambulanceDriver) end
    if spawnedEntities.ambulance and DoesEntityExist(spawnedEntities.ambulance) then DeleteEntity(spawnedEntities.ambulance) end
    spawnedEntities = { medic = nil, ambulance = nil, ambulanceDriver = nil }
end)

local function spawnAIMedic(coords)
    local player = PlayerPedId()
    local playerCoords = coords or GetEntityCoords(player)
    local model = Config.MedicPed or 's_m_m_paramedic_01'

    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer()-t0 < 5000 do Wait(10) end

    local spawn = playerCoords + (Config.SpawnOffset or vector3(2.5, 0.0, 0.0))
    local medic = CreatePed(4, model, spawn.x, spawn.y, spawn.z, GetEntityHeading(player), true, false)
    if not DoesEntityExist(medic) then return end

    spawnedEntities.medic = medic
    SetEntityAsMissionEntity(medic, true, true)
    SetBlockingOfNonTemporaryEvents(medic, true)
    SetPedCanRagdoll(medic, false)
    SetPedAsCop(medic, false)

    ClearPedTasks(medic)
    TaskGoToEntity(medic, player, -1, 1.0, 0.5, 1073741824, 0)

    local start = GetGameTimer()
    while DoesEntityExist(medic) and DoesEntityExist(player) and #(GetEntityCoords(medic) - GetEntityCoords(player)) > (Config.MedicApproachDistance or 1.8) and GetGameTimer() - start < (Config.MedicApproachTimeout or 10000) do
        if IsPedUsingScenario(medic, 'WORLD_HUMAN_SMOKING') or IsPedUsingScenario(medic, 'WORLD_HUMAN_STAND_MOBILE') then
            ClearPedTasks(medic)
            TaskGoToEntity(medic, player, -1, 1.0, 0.5, 1073741824, 0)
        end
        Wait(150)
    end

    if not DoesEntityExist(medic) then return end
    local dist = #(GetEntityCoords(medic) - GetEntityCoords(player))
    if dist > 3.5 then
        local target = GetEntityCoords(player) + vector3(1.0, 0.0, 0.0)
        local timeout = GetGameTimer() + 1000
        while not NetworkHasControlOfEntity(medic) and GetGameTimer() < timeout do
            NetworkRequestControlOfEntity(medic)
            Wait(50)
        end
        SetEntityCoords(medic, target.x, target.y, target.z, false, false, false, true)
    end

    TaskTurnPedToFaceEntity(medic, player, 1000)

    local animDict = 'mini@cpr@char_a@cpr_str'
    local animName = 'cpr_pumpchest'
    RequestAnimDict(animDict)
    local t1 = GetGameTimer()
    while not HasAnimDictLoaded(animDict) and GetGameTimer()-t1 < 5000 do Wait(10) end

    ClearPedTasks(medic)
    TaskPlayAnim(medic, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)

    CreateThread(function()
        playHeartbeatForPlayer(Config.CPRDuration or 0)
    end)

    local duration = math.max((Config.CPRDuration or 0), 1000)
    QBCore.Functions.Progressbar('ai_medic_cpr', 'Performing CPR', duration, false, true, {}, {}, {}, {}, function()
        if DoesEntityExist(medic) then ClearPedTasks(medic) end
        pcall(function() TriggerEvent('hospital:client:Revive') end)
        TriggerServerEvent('jlee-aimedic:reviveServer', true)
        TriggerServerEvent('jlee-aimedic:charge', 'npc')

        CreateThread(function()
            playHeartbeatForPlayer(3000)
            Wait(500)
            requestAudioBank(Config.HeartbeatSoundSet or 'HUD_AWARDS')
            Wait(200)
            TriggerServerEvent('jlee-aimedic:playReviveSoundForPlayer')
        end)

        QBCore.Functions.Notify('You have been revived!', 'success')
        Wait(3000)
        if DoesEntityExist(medic) then
            DeleteEntity(medic)
            spawnedEntities.medic = nil
        end
    end)
end

local function spawnAIAmbulance(coords)
    local playerPed = PlayerPedId()
    local playerCoords = coords or GetEntityCoords(playerPed)
    local vehicleModel = Config.AmbulanceModel or 'ambulance'
    local driverModel = Config.DriverModel or 's_m_m_paramedic_01'
    local dropoff1 = Config.AmbulanceDropOff1 or vector3(300.0, -1400.0, 29.0)
    local dropoff2 = Config.AmbulanceDropOff2 or vector3(295.0, -1430.0, 29.0)

    RequestModel(vehicleModel)
    RequestModel(driverModel)
    while not HasModelLoaded(vehicleModel) or not HasModelLoaded(driverModel) do Wait(10) end

    local spawnPos = playerCoords + vector3(10.0, 0.0, 0.0)
    local vehicle = CreateVehicle(vehicleModel, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, false)
    local driver = CreatePedInsideVehicle(vehicle, 4, driverModel, -1, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)

    spawnedEntities.ambulance = vehicle
    spawnedEntities.ambulanceDriver = driver

    CreateThread(function()
        local name = Config.AmbulanceArrivalSong or Config.AmbulanceSoundName or 'medic_song'
        if name and name ~= '' and DoesEntityExist(vehicle) then
            local fileName = tostring(name)
            if not fileName:match('%.mp3$') then fileName = fileName .. '.mp3' end
            local nuiPath = 'sounds/' .. fileName
            SendNUIMessage({ action = 'playMedicSong', name = nuiPath })

            local bank = Config.AmbulanceArrivalSongSet or Config.HeartbeatSoundSet or ''
            if bank and bank ~= '' then
                requestAudioBank(bank)
                local sid = GetSoundId()
                pcall(function() PlaySoundFromEntity(sid, name, vehicle, bank, true, 0) end)
                while DoesEntityExist(vehicle) do
                    Wait(3000)
                    pcall(function() PlaySoundFromEntity(sid, name, vehicle, bank, true, 0) end)
                end
                pcall(StopSound, sid); pcall(ReleaseSoundId, sid)
            else
                while DoesEntityExist(vehicle) do Wait(2500) end
            end

            SendNUIMessage({ action = 'stopMedicSong' })
        end
    end)

    local driveSpeed = 20.0 -- lowered so AI can stop reliably
    local driveFlag = 786603
    TaskVehicleDriveToCoordLongrange(driver, vehicle, playerCoords.x, playerCoords.y, playerCoords.z, driveSpeed, driveFlag, 1.0)
    QBCore.Functions.Notify('Ambulance is on its way!', 'primary')

    local startTime = GetGameTimer()
    local arrivedToPlayer = false
    local lastPos = GetEntityCoords(vehicle)
    local stuckSince = nil
    while GetGameTimer() - startTime < (Config.AmbulanceOverallTimeout or 120) * 1000 do
        if not DoesEntityExist(vehicle) then break end
        local dist = #(GetEntityCoords(vehicle) - GetEntityCoords(playerPed))
        if dist <= (Config.PickupRadius or 15.0) then
            arrivedToPlayer = true
            break
        end
        local curPos = GetEntityCoords(vehicle)
        if #(curPos - lastPos) < 0.5 then
            if not stuckSince then stuckSince = GetGameTimer() end
        else
            stuckSince = nil
        end
        if stuckSince and (GetGameTimer() - stuckSince) > (Config.AmbulanceStuckTimeout or 120) * 1000 then
            local t = GetEntityCoords(playerPed) + vector3(5.0, 0.0, 0.0)
            if NetworkRequestControlOfEntity(vehicle) then
                SetEntityCoords(vehicle, t.x, t.y, t.z, false, false, false, true)
            else
                NetworkRequestControlOfEntity(vehicle)
            end
            stuckSince = nil
        end
        lastPos = curPos
        Wait(500)
    end

    if not arrivedToPlayer then
        if DoesEntityExist(vehicle) then
            SetEntityCoords(vehicle, dropoff1.x + 2.0, dropoff1.y + 2.0, dropoff1.z)
        end
        SetEntityCoords(playerPed, dropoff1.x, dropoff1.y, dropoff1.z)
        QBCore.Functions.Notify('Ambulance teleport fallback: arriving at hospital entrance', 'error')
    end

        if DoesEntityExist(driver) and DoesEntityExist(vehicle) then
        TaskVehicleTempAction(driver, vehicle, 27, 3000)
        Wait(800) -- give vehicle time to come to rest before leaving
        TaskLeaveVehicle(driver, vehicle, 0)
        local leaveStart = GetGameTimer()
        while IsPedInAnyVehicle(driver, false) and GetGameTimer() - leaveStart < 4000 do Wait(150) end
        if IsPedInAnyVehicle(driver, false) then
            TaskLeaveVehicle(driver, vehicle, 0)
            Wait(200)
            if IsPedInAnyVehicle(driver, false) then
                TaskWarpPedOutOfVehicle(driver, vehicle, 0)
                Wait(200)
            end
        end
        Wait(300)
        ClearPedTasks(driver)
        TaskGoToEntity(driver, playerPed, -1, 1.0, 2.0, 1073741824.0, 0)
        while #(GetEntityCoords(driver) - GetEntityCoords(playerPed)) > 2.5 do Wait(250) end

        RequestAnimDict('amb@medic@standing@kneel@base')
        while not HasAnimDictLoaded('amb@medic@standing@kneel@base') do Wait(10) end
        TaskPlayAnim(driver, 'amb@medic@standing@kneel@base', 'base', 8.0, -8.0, -1, 1, 0, false, false, false)
        Wait(1000)

        TaskLeaveVehicle(driver, vehicle, 0)
        Wait(1000)
        TaskGoToEntity(driver, playerPed, -1, 1.0, 2.0, 1073741824.0, 0)
        while #(GetEntityCoords(driver) - GetEntityCoords(playerPed)) > 1.8 do Wait(200) end

        RequestAnimDict('missfinale_c2mcs_1')
        while not HasAnimDictLoaded('missfinale_c2mcs_1') do Wait(10) end
        ClearPedTasks(driver)
        TaskPlayAnim(driver, 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 8.0, -8.0, -1, 1, 0, false, false, false)
        Wait(300)

        if not isBeingCarried then
            isBeingCarried = true
            local timeoutCtrl = GetGameTimer() + 2000
            while not NetworkHasControlOfEntity(playerPed) and GetGameTimer() < timeoutCtrl do
                NetworkRequestControlOfEntity(playerPed)
                Wait(50)
            end
            DetachEntity(playerPed, true, true)
            ClearPedTasksImmediately(playerPed)
            SetPedCanRagdoll(playerPed, false)

            local warped = false
            if DoesEntityExist(vehicle) then
                local timeoutCtrlV = GetGameTimer() + 2000
                while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeoutCtrlV do
                    NetworkRequestControlOfEntity(vehicle)
                    Wait(50)
                end
                local preferredSeats = Config.SeatIndices or {2,3,1,0}
                for _, seat in ipairs(preferredSeats) do
                    if not IsEntityDead(playerPed) and DoesEntityExist(vehicle) then
                        pcall(function() TaskWarpPedIntoVehicle(playerPed, vehicle, seat) end)
                        Wait(200)
                        if IsPedInVehicle(playerPed, vehicle) then
                            warped = true
                            break
                        end
                    end
                end
            end

            if not warped then
                AttachEntityToEntity(playerPed, driver, GetPedBoneIndex(driver, 28252), 0.0, -0.5, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            end
        end

        QBCore.Functions.Notify('Medic is carrying you to the ward...', 'primary')
        TaskGoToCoordAnyMeans(driver, dropoff2.x, dropoff2.y, dropoff2.z, 1.2, 0, 0, 786603, 0xbf800000)

        local startCarry = GetGameTimer()
        local carried = false
        while GetGameTimer() - startCarry < 30000 do
            if #(GetEntityCoords(driver) - dropoff2) <= 3.0 then
                carried = true
                break
            end
            if IsPedRagdoll(driver) then ClearPedTasks(driver) TaskGoToCoordAnyMeans(driver, dropoff2.x, dropoff2.y, dropoff2.z, 1.2, 0, 0, 786603, 0xbf800000) end
            Wait(250)
        end

        if isBeingCarried then
            local timeoutCtrl2 = GetGameTimer() + 2000
            while not NetworkHasControlOfEntity(playerPed) and GetGameTimer() < timeoutCtrl2 do
                NetworkRequestControlOfEntity(playerPed)
                Wait(50)
            end
            DetachEntity(playerPed, true, true)
            SetPedCanRagdoll(playerPed, true)
            isBeingCarried = false
        end

        ClearPedTasks(driver)

        if carried or #(GetEntityCoords(driver) - dropoff2) <= 3.0 then
            local timeoutCtrl3 = GetGameTimer() + 1000
            while not NetworkHasControlOfEntity(playerPed) and GetGameTimer() < timeoutCtrl3 do
                NetworkRequestControlOfEntity(playerPed)
                Wait(50)
            end
            SetEntityCoords(playerPed, dropoff2.x, dropoff2.y, dropoff2.z)
            QBCore.Functions.Notify('Medic carried you into the ward safely.', 'success')
        else
            SetEntityCoords(playerPed, dropoff2.x, dropoff2.y, dropoff2.z)
            QBCore.Functions.Notify('Teleporting you inside due to path issue.', 'error')
        end

        Wait(2000)
        TaskWanderStandard(driver, 10.0, 10)
        Wait(5000)
        if DoesEntityExist(driver) then DeleteEntity(driver) spawnedEntities.ambulanceDriver = nil end
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) spawnedEntities.ambulance = nil end
    end
end

RegisterNetEvent('jlee-aimedic:client:playReviveSound', function()
    local sid = GetSoundId()
    RequestScriptAudioBank(Config.HeartbeatSoundSet or 'HUD_AWARDS', false)
    Wait(200)
    pcall(function() PlaySoundFrontend(sid, Config.ReviveSoundName or 'REVIVE_AMBIENT', Config.HeartbeatSoundSet or 'HUD_AWARDS', true) end)
    Wait(1500)
    pcall(StopSound, sid); pcall(ReleaseSoundId, sid)
end)

RegisterNetEvent('jlee-aimedic:spawnMedic', function(coords) spawnAIMedic(coords) end)
RegisterNetEvent('jlee-aimedic:spawnAmbulance', function(coords) spawnAIAmbulance(coords) end)

-- Compatibility: server may trigger these client-call events; forward them to the same handlers
RegisterNetEvent('jlee-aimedic:clientCallAIMedic', function(data) spawnAIMedic(data and data.coords or nil) end)
RegisterNetEvent('jlee-aimedic:clientCallAmbulance', function(data) spawnAIAmbulance(data and data.coords or nil) end)

RegisterCommand('medic', function()
    local listenerName = 'jlee-aimedic:responseUseCheck'
    local registered = false
    local function responseHandler(allowed, reason, extra)
        if registered then return end
        registered = true
        if not allowed then
            if reason == 'ambulance_online_restriction' then
                QBCore.Functions.Notify('An on-duty ambulance is available — only ambulance job may call /medic', 'error')
            elseif reason == 'cooldown' then
                local mins = math.ceil((extra or 0) / 60)
                QBCore.Functions.Notify('You must wait '..mins..' minute(s) before using /medic again', 'error')
            elseif reason == 'rate_limited' then
                QBCore.Functions.Notify('You are calling too frequently, try again later', 'error')
            else
                QBCore.Functions.Notify('Cannot use /medic right now', 'error')
            end
            return
        end

        TriggerServerEvent('jlee-aimedic:markUsed')

        if Config.MenuType == "qb" then
            local menu = {
                { header = "Medic Assistance", isMenuHeader = true },
                { header = "Call AI Medic", txt = "Request an NPC medic", params = { event = "jlee-aimedic:menuRequestSpawn", args = { choice = 'npc' } } },
                { header = "Call NPC Ambulance", txt = "Request an NPC ambulance", params = { event = "jlee-aimedic:menuRequestSpawn", args = { choice = 'ambulance' } } },
                { header = "Cancel", txt = "Close menu", params = { event = "qb-menu:client:closeMenu" } }
            }
            exports['qb-menu']:openMenu(menu)
        elseif Config.MenuType == "custom" then
            SetNuiFocus(true, true)
            SendNUIMessage({ action = "openMedicUI" })
        else
            QBCore.Functions.Notify('Invalid medic menu configuration', 'error')
        end
    end

    RegisterNetEvent(listenerName, responseHandler)
    TriggerServerEvent('jlee-aimedic:requestUseCheck')
end)

RegisterNetEvent('jlee-aimedic:menuRequestSpawn', function(data)
    if not data or not data.choice then return end
    TriggerServerEvent('jlee-aimedic:requestSpawn', data.choice, GetEntityCoords(PlayerPedId()))
end)

RegisterNUICallback('chooseOption', function(data, cb)
    if data.option == 'npc' then
        TriggerServerEvent('jlee-aimedic:requestSpawn', 'npc', GetEntityCoords(PlayerPedId()))
    elseif data.option == 'ambulance' then
        TriggerServerEvent('jlee-aimedic:requestSpawn', 'ambulance', GetEntityCoords(PlayerPedId()))
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMedicUI' })
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMedicUI' })
    cb('ok')
end)
