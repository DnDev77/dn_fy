local PlayerPedId            = PlayerPedId
local GetEntityCoords        = GetEntityCoords
local DoesEntityExist        = DoesEntityExist
local Wait                   = Wait
local CreateThread           = CreateThread
local IsControlJustPressed   = IsControlJustPressed
local GetGamePool            = GetGamePool
local xSound                 = exports.xsound
local nuiAberto = false

local musicData = { volume = 0.2, loop = false }
local Zones = {}

local SoundsPlaying = {}
local playerHoldingBoombox = false

local boomboxInHand = nil
local lastDroppedBoombox = nil

local myBoomboxes = {}
local cachedBoomboxHash = nil

local vehicleTakeoverActive = false
local takeoverSoundId = nil

local takeoverPreviousVolume = 0.2
local takeoverVehicle = nil

local nearbyBoomboxCache = {
    object     = nil,
    networkId  = nil,
    lastUpdate = 0,
    valid      = false,
}

local CACHE_DURATION = 500

CreateThread(function()
    while not Config or not Config.Boombox or not Config.Boombox.Model do
        Wait(100)
    end
    local hash = GetHashKey(Config.Boombox.Model)
    if hash and hash ~= 0 then
        cachedBoomboxHash = hash
        Debug('client.boomboxHashLoaded', tostring(cachedBoomboxHash))
    else
        Debug('client.boomboxHashFailed', tostring(Config.Boombox.Model))
    end
end)

RegisterNetEvent("central_music:receiveLocale")
AddEventHandler("central_music:receiveLocale", function(localeTable)
    Debug('client.localeReceived')
    SendNUIMessage({ action = "setLocale", locale = localeTable })
end)

function GetBoomboxHash()
    if not cachedBoomboxHash and Config and Config.Boombox and Config.Boombox.Model then
        cachedBoomboxHash = GetHashKey(Config.Boombox.Model)
        if cachedBoomboxHash and cachedBoomboxHash ~= 0 then
            Debug('client.boomboxHashLoaded', tostring(cachedBoomboxHash))
        else
            Debug('client.boomboxHashFailed', tostring(Config.Boombox.Model))
        end
    end
    return cachedBoomboxHash
end

function Draw3DTextFixed(x, y, z, key, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    SetTextCentre(false)
    AddTextComponentString("~r~[" .. key .. "] ~w~" .. text)
    DrawText(_x + 0.02, _y)
end

function ShowBoomboxOptions(boomboxObject)
    if not boomboxObject or not DoesEntityExist(boomboxObject) then return end
    if not (playerHoldingBoombox and boomboxInHand == boomboxObject) then return end

    local coords  = GetEntityCoords(boomboxObject)
    local baseZ   = coords.z + 0.5

    Draw3DTextFixed(coords.x, coords.y, baseZ,        "E", Locale("hud.openMusicPanel"))
    Draw3DTextFixed(coords.x, coords.y, baseZ - 0.10, "G", Locale("hud.putOnGround"))
    Draw3DTextFixed(coords.x, coords.y, baseZ - 0.20, "Z", Locale("hud.storeBoombox"))
end

function IsNearBoombox()
    if not Config or not Config.Boombox or not Config.Boombox.Enabled then
        return false, nil, nil
    end

    local now = GetGameTimer()

    if nearbyBoomboxCache.valid and (now - nearbyBoomboxCache.lastUpdate) < CACHE_DURATION then
        if nearbyBoomboxCache.object and DoesEntityExist(nearbyBoomboxCache.object) then
            return true, nearbyBoomboxCache.object, nearbyBoomboxCache.networkId
        end
    end

    nearbyBoomboxCache.valid      = false
    nearbyBoomboxCache.object     = nil
    nearbyBoomboxCache.networkId  = nil

    local playerCoords  = GetEntityCoords(PlayerPedId())
    local boomboxHash   = GetBoomboxHash()
    if not boomboxHash then
        Debug('client.isNearBoomboxHashFail')
        return false, nil, nil
    end

    for i = #myBoomboxes, 1, -1 do
        local obj = myBoomboxes[i]
        if DoesEntityExist(obj) and not HasObjectBeenBroken(obj) then
            if #(GetEntityCoords(obj) - playerCoords) <= 2.0 then
                local netId = NetworkGetEntityIsNetworked(obj) and NetworkGetNetworkIdFromEntity(obj) or nil
                local idStr = netId and tostring(netId) or tostring(obj)

                nearbyBoomboxCache.object     = obj
                nearbyBoomboxCache.networkId  = idStr
                nearbyBoomboxCache.lastUpdate = now
                nearbyBoomboxCache.valid      = true

                Debug('client.isNearBoombox', 'true', tostring(obj), tostring(idStr))
                return true, obj, idStr
            end
        else
            Debug('client.zoneCleanupBoombox', tostring(myBoomboxes[i]))
            table.remove(myBoomboxes, i)
        end
    end

    local objects         = GetGamePool("CObject")
    local closestObject   = nil
    local closestDistance = 2.0

    for i = 1, #objects do
        local obj = objects[i]
        if DoesEntityExist(obj) and not HasObjectBeenBroken(obj) then
            if GetEntityModel(obj) == boomboxHash then
                local dist = #(GetEntityCoords(obj) - playerCoords)
                if dist < closestDistance then
                    closestObject   = obj
                    closestDistance = dist
                end
            end
        end
    end

    if closestObject then
        local netId = NetworkGetEntityIsNetworked(closestObject) and NetworkGetNetworkIdFromEntity(closestObject) or nil
        local idStr = netId and tostring(netId) or tostring(closestObject)

        nearbyBoomboxCache.object     = closestObject
        nearbyBoomboxCache.networkId  = idStr
        nearbyBoomboxCache.lastUpdate = now
        nearbyBoomboxCache.valid      = true

        Debug('client.isNearBoombox', 'true', tostring(closestObject), tostring(idStr))
        return true, closestObject, idStr
    end

    nearbyBoomboxCache.lastUpdate = now
    Debug('client.isNearBoombox', 'false', 'nil', 'nil')
    return false, nil, nil
end

function CanUseMusicSystem()
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        local id = GetVehicleNumberPlateText(veh)
        Debug('client.canUseMusicSystem', 'true', 'vehicle', tostring(id))
        return true, "vehicle", veh, id
    end

    local nearBoombox, boomboxObject, boomboxId = IsNearBoombox()
    if nearBoombox then
        Debug('client.canUseMusicSystem', 'true', 'boombox', tostring(boomboxId))
        return true, "boombox", boomboxObject, boomboxId
    end

    if playerHoldingBoombox and boomboxInHand and DoesEntityExist(boomboxInHand) then
        local id = NetworkGetEntityIsNetworked(boomboxInHand)
            and tostring(NetworkGetNetworkIdFromEntity(boomboxInHand))
            or tostring(boomboxInHand)
        Debug('client.canUseMusicSystem', 'true', 'boombox(hand)', tostring(id))
        return true, "boombox", boomboxInHand, id
    end

    Debug('client.canUseMusicSystem', 'false', 'none', 'nil')
    return false, "none"
end

function FindMyBoombox()
    Debug('client.findBoombox')
    local playerPos = GetEntityCoords(PlayerPedId())

    for i = #myBoomboxes, 1, -1 do
        local handle = myBoomboxes[i]
        if DoesEntityExist(handle) and not HasObjectBeenBroken(handle) then
            if not IsEntityAttachedToAnyPed(handle) then
                Debug('client.findBoomboxFound', tostring(handle))
                return handle
            end
        else
            Debug('client.zoneCleanupBoombox', tostring(handle))
            table.remove(myBoomboxes, i)
        end
    end

    if lastDroppedBoombox and DoesEntityExist(lastDroppedBoombox)
        and not HasObjectBeenBroken(lastDroppedBoombox)
        and not IsEntityAttachedToAnyPed(lastDroppedBoombox)
    then
        local dist = #(playerPos - GetEntityCoords(lastDroppedBoombox))
        if dist < 50.0 then
            table.insert(myBoomboxes, lastDroppedBoombox)
            Debug('client.findBoomboxFound', tostring(lastDroppedBoombox))
            return lastDroppedBoombox
        end
    end

    local boomboxHash   = GetBoomboxHash()
    if not boomboxHash then
        Debug('client.isNearBoomboxHashFail')
        return nil
    end

    local objects       = GetGamePool("CObject")
    local closest       = nil
    local closestDist   = 50.0

    for i = 1, #objects do
        local obj = objects[i]
        if DoesEntityExist(obj) and not HasObjectBeenBroken(obj) and GetEntityModel(obj) == boomboxHash then
            local dist = #(playerPos - GetEntityCoords(obj))
            if dist < closestDist and not IsEntityAttachedToAnyPed(obj) then
                closest     = obj
                closestDist = dist
            end
        end
    end

    if closest then
        table.insert(myBoomboxes, closest)
        Debug('client.findBoomboxFound', tostring(closest))
    else
        Debug('client.findBoomboxNotFound')
    end

    return closest
end

function CreateOrRetrieveBoombox()
    Debug('client.createOrRetrieve')

    if playerHoldingBoombox and boomboxInHand and DoesEntityExist(boomboxInHand) then
        TriggerEvent("Notify", "info", Locale("client.alreadyHoldingBoombox"), 3000)
        return
    end

    local existing = FindMyBoombox()
    if existing then
        local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(existing))
        PickupBoombox(existing)
        TriggerEvent("Notify", "success", Locale("client.boomboxRecovered", dist), 4000)
    else
        if #myBoomboxes == 0 then
            CreateBoombox()
        else
            TriggerEvent("Notify", "error", Locale("client.boomboxTooFar"), 4000)
        end
    end
end

function CreateBoombox()
    Debug('client.createBoombox')
    local playerPed  = PlayerPedId()
    local position   = GetEntityCoords(playerPed) + (GetEntityForwardVector(playerPed) * 0.75)
    local modelHash  = GetBoomboxHash()

    if not modelHash then
        Debug('client.boomboxHashFailed', tostring(Config and Config.Boombox and Config.Boombox.Model or 'nil'))
        return
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        Wait(10)
        timeout = timeout + 1
    end
    if not HasModelLoaded(modelHash) then
        Debug('client.createBoomboxModelFail', tostring(modelHash))
        return
    end

    local object = CreateObject(modelHash, position, true, true, false)

    if DoesEntityExist(object) then
        Debug('client.createBoomboxSuccess', tostring(object))
        SetEntityCoords(object, position)
        SetEntityHeading(object, 0.0)
        SetEntityAsMissionEntity(object, true, true)
        table.insert(myBoomboxes, object)
        PickupBoombox(object)
    else
        Debug('client.createBoomboxEntityFail')
    end

    SetModelAsNoLongerNeeded(modelHash)
end

function PickupBoombox(object)
    Debug('client.pickupBoombox', tostring(object))

    if playerHoldingBoombox then
        Debug('client.pickupBoomboxAlreadyHolding')
        return
    end
    if not object or not DoesEntityExist(object) then
        Debug('client.pickupBoomboxInvalid', tostring(object))
        return
    end
    if HasObjectBeenBroken(object) then
        Debug('client.pickupBoomboxInvalid', tostring(object) .. ' (broken)')
        return
    end

    local playerPed = PlayerPedId()

    playerHoldingBoombox        = true
    boomboxInHand               = object
    nearbyBoomboxCache.valid    = false

    FreezeEntityPosition(object, false)
    SetEntityCollision(object, false, false)

    Wait(50)

    local boneIndex = GetPedBoneIndex(playerPed, 57005)
    if boneIndex == -1 then
        boneIndex = GetPedBoneIndex(playerPed, 18905)
    end

    AttachEntityToEntity(
        object, playerPed, boneIndex,
        0.15, 0.08, -0.05,
        0.0, 270.0, 60.0,
        true, true, false, true, 1, true
    )

    Wait(100)

    if GetEntityAttachedTo(object) == playerPed then
        Debug('client.pickupBoomboxAttachSuccess', tostring(boneIndex))
        TriggerEvent("Notify", "sucesso", Locale("notifications.boomboxPickedUp"), 3000)
        return
    end

    Debug('client.pickupBoomboxAttachFail', tostring(boneIndex))

    local leftHandBone = GetPedBoneIndex(playerPed, 24817)
    AttachEntityToEntity(
        object, playerPed, leftHandBone,
        0.15, 0.08, -0.05,
        0.0, 270.0, 60.0,
        true, true, false, true, 1, true
    )

    Wait(100)

    if GetEntityAttachedTo(object) == playerPed then
        Debug('client.pickupBoomboxAttachSuccess', tostring(leftHandBone))
        TriggerEvent("Notify", "sucesso", Locale("notifications.boomboxPickedUp"), 3000)
    else
        Debug('client.pickupBoomboxFinalFail')
        playerHoldingBoombox = false
        boomboxInHand        = nil
        FreezeEntityPosition(object, true)
        SetEntityCollision(object, true, true)
        TriggerEvent("Notify", "negado", Locale("notifications.boomboxPickupFailed"), 3000)
    end
end

function DropBoombox()
    Debug('client.dropBoombox', tostring(boomboxInHand))

    if not playerHoldingBoombox or not boomboxInHand then
        Debug('client.dropBoomboxNotHolding')
        return
    end
    if not DoesEntityExist(boomboxInHand) then
        Debug('client.dropBoomboxEntityGone')
        playerHoldingBoombox = false
        boomboxInHand        = nil
        return
    end

    local playerPed = PlayerPedId()

    playerHoldingBoombox        = false
    nearbyBoomboxCache.valid    = false

    DetachEntity(boomboxInHand, true, true)
    Wait(100)

    local playerCoords  = GetEntityCoords(playerPed)
    local heading       = GetEntityHeading(playerPed)
    local dropPos       = playerCoords + (GetEntityForwardVector(playerPed) * 1.5)

    SetEntityCoords(boomboxInHand, dropPos.x, dropPos.y, dropPos.z)
    SetEntityHeading(boomboxInHand, heading)

    local onGround, groundZ = GetGroundZFor_3dCoord(dropPos.x, dropPos.y, dropPos.z + 1.0, 0)
    if onGround then
        SetEntityCoords(boomboxInHand, dropPos.x, dropPos.y, groundZ + 0.1)
    end

    SetEntityAsMissionEntity(boomboxInHand, true, true)
    FreezeEntityPosition(boomboxInHand, true)
    SetEntityCollision(boomboxInHand, true, true)

    lastDroppedBoombox  = boomboxInHand
    local dropped       = boomboxInHand
    boomboxInHand       = nil

    Debug('client.dropBoomboxSuccess')

    CreateThread(function()
        Wait(2000)
        if DoesEntityExist(dropped) then
            FreezeEntityPosition(dropped, false)
        end
    end)

    TriggerEvent("Notify", "sucesso", Locale("notifications.boomboxDropped"), 3000)
end

function ActivateVehicleTakeover(soundId, vehicle)
    if vehicleTakeoverActive then
        Debug('client.vehicleTakeoverAlreadyActive')
        return
    end
    if not Config.VehicleTakeover or not Config.VehicleTakeover.Enabled then
        Debug('client.vehicleTakeoverDisabled')
        return
    end
    if not xSound:soundExists(soundId) then
        Debug('client.vehicleTakeoverSoundMissing', tostring(soundId))
        return
    end

    Debug('client.vehicleTakeoverActivate', tostring(soundId), tostring(vehicle))

    vehicleTakeoverActive  = true
    takeoverSoundId        = soundId
    takeoverVehicle        = vehicle
    takeoverPreviousVolume = xSound:getVolume(soundId) or musicData.volume

    if Config.VehicleTakeover.HidePropOnEnter then
        local prop = boomboxInHand or lastDroppedBoombox
        if prop and DoesEntityExist(prop) then
            SetEntityAlpha(prop, 0, false)
            SetEntityCollision(prop, false, false)
            FreezeEntityPosition(prop, true)
        end
    end

    local targetVol  = Config.VehicleTakeover.TakeoverVolume
    local fadeDur    = Config.VehicleTakeover.FadeDuration or 800
    local steps      = 20
    local stepDelay  = math.floor(fadeDur / steps)
    local stepDelta  = (targetVol - takeoverPreviousVolume) / steps

    CreateThread(function()
        local currentVol = takeoverPreviousVolume
        for _ = 1, steps do
            if not vehicleTakeoverActive then break end
            currentVol = currentVol + stepDelta
            if xSound:soundExists(soundId) then
                xSound:setVolume(soundId, math.max(0.0, math.min(1.0, currentVol)))
            end
            Wait(stepDelay)
        end
    end)

    CreateThread(function()
        while vehicleTakeoverActive do
            if xSound:soundExists(soundId) and DoesEntityExist(vehicle) then
                xSound:Position(soundId, GetEntityCoords(vehicle))
            end
            Wait(150)
        end
    end)

    TriggerEvent("Notify", "info", Locale("notifications.vehicleTakeoverStart"), 3000)
end

function DeactivateVehicleTakeover()
    if not vehicleTakeoverActive then
        Debug('client.vehicleTakeoverNotActive')
        return
    end

    local soundId    = takeoverSoundId
    Debug('client.vehicleTakeoverDeactivate', tostring(soundId))

    local targetVol  = takeoverPreviousVolume
    local fadeDur    = (Config.VehicleTakeover and Config.VehicleTakeover.FadeDuration) or 800
    local steps      = 20
    local stepDelay  = math.floor(fadeDur / steps)

    vehicleTakeoverActive = false
    takeoverVehicle       = nil

    if soundId and xSound:soundExists(soundId) then
        local currentVol = xSound:getVolume(soundId) or musicData.volume
        local stepDelta  = (targetVol - currentVol) / steps

        CreateThread(function()
            for _ = 1, steps do
                currentVol = currentVol + stepDelta
                if xSound:soundExists(soundId) then
                    xSound:setVolume(soundId, math.max(0.0, math.min(1.0, currentVol)))
                end
                Wait(stepDelay)
            end
        end)
    end

    if Config.VehicleTakeover and Config.VehicleTakeover.HidePropOnEnter then
        local prop = boomboxInHand or lastDroppedBoombox
        if prop and DoesEntityExist(prop) then
            SetEntityAlpha(prop, 255, false)
            SetEntityCollision(prop, true, true)
            FreezeEntityPosition(prop, false)
        end
    end

    takeoverSoundId       = nil
    takeoverPreviousVolume = 0.2

    TriggerEvent("Notify", "info", Locale("notifications.vehicleTakeoverEnd"), 3000)
end

CreateThread(function()
    while not Config do
        Debug('client.configWaiting')
        Wait(100)
    end

    local wasInVehicle = false

    while true do
        if Config.VehicleTakeover and Config.VehicleTakeover.Enabled then
            local ped = PlayerPedId()
            local inVehicle = IsPedInAnyVehicle(ped, false)

            if inVehicle and not wasInVehicle then
                local vehicle = GetVehiclePedIsIn(ped, false)

                local activeSoundId = nil
                if boomboxInHand then
                    local id = NetworkGetEntityIsNetworked(boomboxInHand)
                        and tostring(NetworkGetNetworkIdFromEntity(boomboxInHand))
                        or tostring(boomboxInHand)
                    if xSound:soundExists(id) and xSound:isPlaying(id) then
                        activeSoundId = id
                    end
                end
                if not activeSoundId and lastDroppedBoombox and DoesEntityExist(lastDroppedBoombox) then
                    local id = NetworkGetEntityIsNetworked(lastDroppedBoombox)
                        and tostring(NetworkGetNetworkIdFromEntity(lastDroppedBoombox))
                        or tostring(lastDroppedBoombox)
                    if xSound:soundExists(id) and xSound:isPlaying(id) then
                        activeSoundId = id
                    end
                end

                Debug('client.vehicleEntered', tostring(NetworkGetNetworkIdFromEntity(vehicle)), tostring(activeSoundId))

                if activeSoundId then
                    ActivateVehicleTakeover(activeSoundId, vehicle)
                end

            elseif not inVehicle and wasInVehicle then
                Debug('client.vehicleLeft', tostring(vehicleTakeoverActive))
                if vehicleTakeoverActive then
                    DeactivateVehicleTakeover()
                end
            end

            wasInVehicle = inVehicle
        end

        Wait(500)
    end
end)

function ShowNUI(nameId)
    local canUse, contextType, object, id = CanUseMusicSystem()

    Debug('client.showNui', tostring(canUse), tostring(contextType))

    if not canUse then
        Debug('client.showNuiDenied')
        TriggerEvent("Notify", "negado", Locale("notifications.cannotDoNow"), 5000)
        return
    end

    nuiAberto = not nuiAberto

    if nuiAberto then
        musicData = { volume = 0.2, loop = false }
        local linkUrl = nil

        if xSound:soundExists(id) then
            musicData.loop = xSound:isLooped(id)
            if xSound:isPlaying(id) then
                musicData.volume = xSound:getVolume(id)
                linkUrl          = xSound:getLink(id)
            end
        end

        SetNuiFocus(true, true)
        SendNUIMessage({ action = "setVisible",        data   = true })
        SendNUIMessage({ action = "changevidname",     text   = linkUrl })
        SendNUIMessage({ action = "changeMusicVolume", volume = musicData.volume * 100 })
        SendNUIMessage({ action = "changeMusicLoop",   loop   = musicData.loop })

        UpdateMusicTime(id)
    else
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "setVisible", data = false })
    end
end

function UpdateMusicTime(id)
    if not nuiAberto or not id then return end

    CreateThread(function()
        while nuiAberto do
            Wait(1000)
            if xSound:soundExists(id) and xSound:isPlaying(id) then
                local total  = xSound:getMaxDuration(id)
                local played = xSound:getTimeStamp(id)
                Debug('client.updateMusicTime', tostring(id), tostring(total), tostring(played))
                SendNUIMessage({
                    action = "TimeVid",
                    total  = total,
                    played = played,
                })
            else
                SendNUIMessage({ action = "TimeVid", total = 0, played = 0 })
            end
        end
    end)
end

RegisterNUICallback("action", function(data, cb)
    local canUse, contextType, object, id = CanUseMusicSystem()

    if not canUse then
        Debug('client.nuiActionDenied')
        TriggerEvent("Notify", "negado", Locale("notifications.cannotDoNow"), 5000)
        cb("ok")
        return
    end

    local action = data.action
    Debug('client.nuiAction', tostring(action), tostring(contextType), tostring(id))

    if action == "requestMusicUrl" then
        TriggerServerEvent("central_music/requestMusicUrl", data.musicId, data.name, data.imageUrl, data.author)

    elseif action == "seturl" then
        SetMusicUrl(data.link, id, contextType, object)

    elseif action == "play" then
        if contextType == "boombox" then
            TriggerServerEvent("central_music/PlayBoomboxMusic", id)
        else
            TriggerServerEvent("central_music/ChangeState", true, id)
        end

    elseif action == "pause" then
        if contextType == "boombox" then
            TriggerServerEvent("central_music/PauseBoomboxMusic", id)
        else
            TriggerServerEvent("central_music/ChangeState", false, id)
        end

    elseif action == "volume" then
        if contextType == "boombox" then
            TriggerServerEvent("central_music/SetBoomboxVolume", id, data.value)
        else
            ApplyVolume(data.value, id)
        end

    elseif action == "loop" then
        musicData.loop = not musicData.loop
        if contextType == "boombox" then
            TriggerServerEvent("central_music/SetBoomboxLoop", id, musicData.loop)
        else
            TriggerServerEvent("central_music/ChangeLoop", id, musicData.loop)
        end
        SendNUIMessage({ action = "changeMusicLoop", loop = musicData.loop })

    elseif action == "setNewTime" then
        if contextType == "boombox" then
            TriggerServerEvent("central_music/SetBoomboxTime", id, data.newTime)
        else
            TriggerServerEvent("central_music/ChangePosition", data.newTime, id)
        end

    elseif action == "exit" then
        ShowNUI()

    elseif action == "showLike" then
        TriggerServerEvent("central_music/showLike", data.url_id)

    elseif action == "liked" then
        TriggerServerEvent("central_music/liked", data.url_id, data.name, data.newIdBd, data.image_url)

    elseif action == "remLike" then
        TriggerServerEvent("central_music/remLike", data.url_id)

    elseif action == "reqBannerInfo" then
        TriggerServerEvent("central_music/reqBannerInfo")

    elseif action == "reqLikeList" then
        TriggerServerEvent("central_music/reqLikeList")

    elseif action == "showFooterLike" then
        TriggerServerEvent("central_music/footerLike", data.url_id)

    elseif action == "addToHistory" then
        TriggerServerEvent("central_music/addToHistory", data.url_id, data.name, data.newIdBd, data.image_url, data.author)

    elseif action == "reqHistory" then
        TriggerServerEvent("central_music/reqHistory")

    elseif action == "createPlaylist" then
        TriggerServerEvent("central_music/createNewPlaylist", data.name, data.url_img)

    elseif action == "reqPlaylists" then
        TriggerServerEvent("central_music/reqPlaylists")

    elseif action == "addToPlaylist" then
        TriggerServerEvent("central_music/addToPlaylist", data.playlistId, data.url_id, data.name, data.id, data.image_url)

    elseif action == "removeToPlaylist" then
        TriggerServerEvent("central_music/removeMusicFromPlaylist", data.id, data.playlistId)

    elseif action == "updatePlaylist" then
        TriggerServerEvent("central_music/updatePlaylistMusicList", data.playlist_id, data.updatedMusicList)

    elseif action == "editPlaylist" then
        TriggerServerEvent("central_music/editPlaylist", data.id, data.name, data.url_img)

    elseif action == "searchMusic" then
        TriggerServerEvent("central_music/searchMusic", data.musicQuery)

    elseif action == "deletePlaylist" then
        TriggerServerEvent("central_music/deletePlaylist", data.id)

    else
        Debug('client.nuiActionUnknown', tostring(action))
    end

    cb("ok")
end)

RegisterNUICallback("hideFrame", function(_, cb)
    nuiAberto = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisible", data = false })
    cb({})
end)

function ApplyVolume(value, id)
    local volume = value / 100
    if volume < 0.0 then volume = 0.0 end
    if volume > 1.01 then
        Debug('client.applyVolumeIgnored', tostring(volume))
        return
    end
    if volume < 0.005 then volume = 0.0 end

    Debug('client.applyVolume', tostring(value), tostring(volume), tostring(id))
    musicData.volume = volume
    TriggerServerEvent("central_music/ChangeVolume", volume, id)
end

function SetMusicUrl(url, id, contextType, object)
    if not url then
        Debug('client.setMusicUrlNoUrl')
        return
    end

    Debug('client.setMusicUrl', tostring(url), tostring(id), tostring(contextType))

    if xSound:soundExists(id) and xSound:isLooped(id) then
        musicData.loop = false
        if contextType == "boombox" then
            TriggerServerEvent("central_music/SetBoomboxLoop", id, false)
        else
            TriggerServerEvent("central_music/ChangeLoop", id, false)
        end
    end

    if xSound:soundExists(id) then
        if contextType == "boombox" then
            TriggerServerEvent("central_music/SetBoomboxTime", id, 0)
        else
            TriggerServerEvent("central_music/ChangePosition", 0, id)
        end
        Wait(500)
    end

    if contextType == "vehicle" then
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            Debug('client.setMusicUrlNoVehicle')
            return
        end

        local veh     = GetVehiclePedIsIn(ped, false)
        if veh == 0 then
            Debug('client.setMusicUrlNoVehicle')
            return
        end

        TriggerServerEvent("central_music/AddVehicle", {
            plate  = id,
            coords = GetEntityCoords(veh),
            link   = url,
            popo   = NetworkGetNetworkIdFromEntity(veh),
            volume = musicData.volume,
            loop   = musicData.loop,
        })

    elseif contextType == "boombox" then
        local boomboxCoords = GetEntityCoords(PlayerPedId())

        if object and DoesEntityExist(object) then
            boomboxCoords = GetEntityCoords(object)
        elseif playerHoldingBoombox and boomboxInHand then
            boomboxCoords = GetEntityCoords(boomboxInHand)
        end

        TriggerServerEvent("central_music/SetBoomboxUrl",
            id, url, boomboxCoords, musicData.volume, musicData.loop, Config.Boombox.Range)
    end

    SendNUIMessage({ action = "changevidname", text = url })
end

RegisterNetEvent("central_music/musicUrlReceived")
AddEventHandler("central_music/musicUrlReceived", function(data)
    local canUse, contextType, object, id = CanUseMusicSystem()
    Debug('client.musicUrlReceivedClient', tostring(data and data.url or 'nil'), tostring(data and data.name or 'nil'))
    if not canUse then
        Debug('client.musicUrlReceivedDenied')
        return
    end

    SendNUIMessage({
        action   = "musicUrlReceived",
        url      = data.url,
        name     = data.name,
        imageUrl = data.imageUrl,
        author   = data.author,
    })
    SetMusicUrl(data.url, id, contextType, object)
    TriggerServerEvent("central_music/addToHistory", data.url, data.name, data.musicId, data.imageUrl, data.author)
    TriggerServerEvent("central_music/footerLike", data.url)
end)

RegisterNetEvent("Music:ShowNui")
AddEventHandler("Music:ShowNui", function()
    ShowNUI()
end)

RegisterNetEvent("central_music/SendData")
AddEventHandler("central_music/SendData", function(data)
    Debug('client.sendData', tostring(#data))
    Zones = data

    for i = 1, #Zones do
        local v = Zones[i]
        Debug('client.sendDataZone', tostring(v.name), tostring(v.isplaying), tostring(v.deflink))
        if v.isplaying then
            if xSound:soundExists(v.name) then xSound:Destroy(v.name) end

            local volume = v.volume
            if not Config.PlayToEveryone and v.popo then
                volume = 0.0
                local plate = GetVehicleNumberPlateText(GetVehiclePedIsIn(PlayerPedId(), false))
                if plate == v.name then volume = v.volume end
            end

            xSound:PlayUrlPos(v.name, v.deflink, volume, v.coords, v.loop, {
                onPlayStart = function()
                    xSound:setTimeStamp(v.name, v.deftime)
                    xSound:Distance(v.name, v.range)
                end,
            })

            if v.popo then
                table.insert(SoundsPlaying, i)
                StartMusicLoop(i)
            end
        end
    end
end)

RegisterNetEvent("central_music/AddVehicle")
AddEventHandler("central_music/AddVehicle", function(data)
    Debug('client.addVehicle', tostring(data.name), tostring(data.deflink))
    table.insert(Zones, data)
    local v = data

    if xSound:soundExists(v.name) then xSound:Destroy(v.name) end

    local volume = v.volume
    if not Config.PlayToEveryone and v.popo then
        volume = 0.0
        local plate = GetVehicleNumberPlateText(GetVehiclePedIsIn(PlayerPedId(), false))
        if plate == v.name then volume = v.volume end
    end

    xSound:PlayUrlPos(v.name, v.deflink, volume, v.coords, v.loop, {
        onPlayStart = function()
            xSound:setTimeStamp(v.name, v.deftime)
            xSound:Distance(v.name, v.range)
        end,
    })

    table.insert(SoundsPlaying, #Zones)
    StartMusicLoop(#Zones)
end)

RegisterNetEvent("central_music/PlayBoombox")
AddEventHandler("central_music/PlayBoombox", function(uniqueId, url, volume, range, loop, coords)
    Debug('client.playBoombox', tostring(uniqueId), tostring(url))
    if xSound:soundExists(uniqueId) then xSound:Destroy(uniqueId) end
    xSound:PlayUrlPos(uniqueId, url, volume, coords, loop, {
        onPlayStart = function()
            xSound:Distance(uniqueId, range)
        end,
    })
end)

RegisterNetEvent("central_music/UpdateBoomboxPosition")
AddEventHandler("central_music/UpdateBoomboxPosition", function(uniqueId, coords)
    Debug('client.updateBoomboxPos', tostring(uniqueId))
    if xSound:soundExists(uniqueId) then
        xSound:Position(uniqueId, coords)
    end
end)

RegisterNetEvent("central_music/StopBoombox")
AddEventHandler("central_music/StopBoombox", function(uniqueId)
    local existed = xSound:soundExists(uniqueId)
    Debug('client.stopBoombox', tostring(uniqueId), tostring(existed))
    if existed then xSound:Destroy(uniqueId) end
end)

RegisterNetEvent("central_music/PauseBoombox")
AddEventHandler("central_music/PauseBoombox", function(uniqueId)
    local exists = xSound:soundExists(uniqueId)
    Debug('client.pauseBoombox', tostring(uniqueId), tostring(exists))
    if exists then xSound:Pause(uniqueId) end
end)

RegisterNetEvent("central_music/ResumeBoombox")
AddEventHandler("central_music/ResumeBoombox", function(uniqueId)
    local exists = xSound:soundExists(uniqueId)
    Debug('client.resumeBoombox', tostring(uniqueId), tostring(exists))
    if exists then xSound:Resume(uniqueId) end
end)

RegisterNetEvent("central_music/UpdateBoomboxVolume")
AddEventHandler("central_music/UpdateBoomboxVolume", function(uniqueId, volume)
    Debug('client.updateBoomboxVol', tostring(uniqueId), tostring(volume))
    if xSound:soundExists(uniqueId) then xSound:setVolume(uniqueId, volume) end
end)

RegisterNetEvent("central_music/UpdateBoomboxLoop")
AddEventHandler("central_music/UpdateBoomboxLoop", function(uniqueId, loop)
    Debug('client.updateBoomboxLoop', tostring(uniqueId), tostring(loop))
    if xSound:soundExists(uniqueId) then xSound:setSoundLoop(uniqueId, loop) end
end)

RegisterNetEvent("central_music/UpdateBoomboxTime")
AddEventHandler("central_music/UpdateBoomboxTime", function(uniqueId, time)
    Debug('client.updateBoomboxTime', tostring(uniqueId), tostring(time))
    if xSound:soundExists(uniqueId) then xSound:setTimeStamp(uniqueId, time) end
end)

RegisterNetEvent("central_music/ChangeState")
AddEventHandler("central_music/ChangeState", function(playing, name)
    Debug('client.changeState', tostring(name), tostring(playing))
    if playing and xSound:soundExists(name) then
        xSound:Resume(name)
    elseif xSound:soundExists(name) then
        xSound:Pause(name)
    end
    for _, v in ipairs(Zones) do
        if v.name == name then v.isplaying = playing; break end
    end
end)

RegisterNetEvent("central_music/ChangeVolume")
AddEventHandler("central_music/ChangeVolume", function(vol, range, name)
    Debug('client.changeVolume', tostring(name), tostring(vol), tostring(range))
    for _, v in ipairs(Zones) do
        if v.name == name then v.volume = vol; v.range = range; break end
    end
    if xSound:soundExists(name) then
        xSound:Distance(name, range)
        xSound:setVolumeMax(name, vol)
    end
end)

RegisterNetEvent("central_music/ChangeLoop")
AddEventHandler("central_music/ChangeLoop", function(loop, name)
    Debug('client.changeLoop', tostring(name), tostring(loop))
    if xSound:soundExists(name) then xSound:setSoundLoop(name, loop) end
    for _, v in ipairs(Zones) do
        if v.name == name then v.loop = loop; break end
    end
end)

RegisterNetEvent("central_music/NewTimeMusic")
AddEventHandler("central_music/NewTimeMusic", function(time, name)
    Debug('client.newTimeMusic', tostring(name), tostring(time))
    if xSound:soundExists(name) then xSound:setTimeStamp(name, time) end
    for _, v in ipairs(Zones) do
        if v.name == name then
            v.deftime = math.max(0, time)
            break
        end
    end
end)

RegisterNetEvent("central_music/searchMusicResult")
AddEventHandler("central_music/searchMusicResult", function(data)
    Debug('client.searchResult', tostring(data and #data or 0))
    SendNUIMessage({ action = "resSearchMusic", searchList = data })
end)

RegisterNetEvent("central_music/receiveAllPlaylists")
AddEventHandler("central_music/receiveAllPlaylists", function(data)
    SendNUIMessage({ action = "resPlaylists", playlist = data })
end)

RegisterNetEvent("central_music/showBannerInfo")
AddEventHandler("central_music/showBannerInfo", function(data)
    SendNUIMessage({ action = "resBanner", bannerInfo = data })
end)

RegisterNetEvent("central_music/showHistory")
AddEventHandler("central_music/showHistory", function(data)
    SendNUIMessage({ action = "resHistory", listLike = data })
end)

RegisterNetEvent("central_music/showLikeList")
AddEventHandler("central_music/showLikeList", function(data)
    SendNUIMessage({ action = "resLikeList", listLike = data })
end)

RegisterNetEvent("central_music/showFooterLike")
AddEventHandler("central_music/showFooterLike", function(data)
    SendNUIMessage({ action = "footerLike", value = data })
end)

RegisterNetEvent("central_music/showRemLike")
AddEventHandler("central_music/showRemLike", function(url_id)
    SendNUIMessage({ action = "remLikeMusic", url_id = url_id })
end)

RegisterNetEvent("central_music/showLike")
AddEventHandler("central_music/showLike", function(url_id)
    SendNUIMessage({ action = "showLikeMusic", url_id = url_id })
end)

function StartMusicLoop(zoneIndex)
    Debug('client.startMusicLoop', tostring(zoneIndex), tostring(Zones[zoneIndex] and Zones[zoneIndex].name or 'nil'))
    CreateThread(function()
        while Zones[zoneIndex] and Zones[zoneIndex].isplaying do
            local v = Zones[zoneIndex]
            if v.popo and NetworkDoesEntityExistWithNetworkId(v.popo) then
                local vehicle = NetworkGetEntityFromNetworkId(v.popo)
                if DoesEntityExist(vehicle) then
                    v.coords = GetEntityCoords(vehicle)
                    if xSound:soundExists(v.name) then
                        xSound:Position(v.name, v.coords)
                    end
                end
            end
            Wait(150)
        end
    end)
end

CreateThread(function()
    while not Config do Wait(100) end

    while true do
        local sleep = 1000

        if Config.Boombox and Config.Boombox.Enabled then

            if playerHoldingBoombox and boomboxInHand and DoesEntityExist(boomboxInHand) then
                sleep = 5

                if IsControlJustPressed(0, 38) then
                    ShowNUI()
                    Wait(200)
                elseif IsControlJustPressed(0, 47) then
                    DropBoombox()
                    Wait(200)
                elseif IsControlJustPressed(0, 20) then
                    local boomboxId = NetworkGetEntityIsNetworked(boomboxInHand)
                        and tostring(NetworkGetNetworkIdFromEntity(boomboxInHand))
                        or tostring(boomboxInHand)

                    if xSound:soundExists(boomboxId) then xSound:Destroy(boomboxId) end

                    DeleteEntity(boomboxInHand)
                    playerHoldingBoombox        = false
                    boomboxInHand               = nil
                    nearbyBoomboxCache.valid    = false
                    TriggerEvent("Notify", "info", Locale("notifications.boomboxStored"), 3000)
                    Wait(200)
                end

            else
                local nearBoombox, boomboxObject, _ = IsNearBoombox()

                if nearBoombox and boomboxObject and DoesEntityExist(boomboxObject) then
                    sleep = 50

                    if IsControlJustPressed(0, 47) then
                        PickupBoombox(boomboxObject)
                        Wait(200)
                    elseif IsControlJustPressed(0, 38) then
                        ShowNUI()
                        Wait(200)
                    elseif IsControlJustPressed(0, 20) then
                        local boomboxId = NetworkGetEntityIsNetworked(boomboxObject)
                            and tostring(NetworkGetNetworkIdFromEntity(boomboxObject))
                            or tostring(boomboxObject)

                        if xSound:soundExists(boomboxId) then xSound:Destroy(boomboxId) end

                        DeleteEntity(boomboxObject)
                        nearbyBoomboxCache.valid = false
                        TriggerEvent("Notify", "info", Locale("notifications.boomboxDestroyed"), 3000)
                        Wait(200)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if playerHoldingBoombox and boomboxInHand and DoesEntityExist(boomboxInHand)
            and not vehicleTakeoverActive
        then
            local boomboxId = NetworkGetEntityIsNetworked(boomboxInHand)
                and tostring(NetworkGetNetworkIdFromEntity(boomboxInHand))
                or tostring(boomboxInHand)

            if xSound:soundExists(boomboxId) then
                xSound:Position(boomboxId, GetEntityCoords(boomboxInHand))
            end
            Wait(300)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while not Config do Wait(100) end

    local validZones = {}
    if Config.Zones then
        for _, v in ipairs(Config.Zones) do
            if v.changemusicblip and type(v.changemusicblip) == "vector3" then
                table.insert(validZones, v)
            end
        end
    end

    if #validZones == 0 then return end

    while true do
        local sleep  = 2000
        local coords = GetEntityCoords(PlayerPedId())

        for _, v in ipairs(validZones) do
            local dist = #(coords - v.changemusicblip)

            if dist <= 10 then
                sleep = 500
                if dist <= 3 then
                    sleep = 50
                    if IsControlJustReleased(0, 38) then
                        ShowNUI(v.name)
                        Wait(500)
                    end
                end
                break
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(15000)

        for i = #Zones, 1, -1 do
            local zone = Zones[i]
            if zone.popo and not NetworkDoesEntityExistWithNetworkId(zone.popo) then
                local veh = NetworkGetEntityFromNetworkId(zone.popo)
                if not DoesEntityExist(veh) then
                    Debug('client.zoneCleanupVehicle', tostring(zone.name))
                    if xSound:soundExists(zone.name) then xSound:Destroy(zone.name) end
                    TriggerServerEvent("central_music/CheckVehicleExists", zone.popo, zone.name)
                end
            end
        end

        for i = #myBoomboxes, 1, -1 do
            if not DoesEntityExist(myBoomboxes[i]) or HasObjectBeenBroken(myBoomboxes[i]) then
                Debug('client.zoneCleanupBoombox', tostring(myBoomboxes[i]))
                table.remove(myBoomboxes, i)
            end
        end
    end
end)

AddEventHandler("onClientResourceStart", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Debug('client.resourceStart', tostring(resourceName))
    TriggerServerEvent("central_music:requestL")
    TriggerServerEvent("central_music/GetDate")
end)

RegisterNetEvent("central_music/VerifyBoombox")
AddEventHandler("central_music/VerifyBoombox", function(uniqueId)
    local exists = xSound:soundExists(uniqueId)
    Debug('client.verifyBoombox', tostring(uniqueId), tostring(exists))
    if exists then xSound:Destroy(uniqueId) end
    TriggerServerEvent("central_music/CheckBoomboxExists", uniqueId)
end)

RegisterNetEvent("central_music/StopMusic")
AddEventHandler("central_music/StopMusic", function(zoneName)
    local existed = xSound:soundExists(zoneName)
    Debug('client.stopMusic', tostring(zoneName), tostring(existed))
    if existed then xSound:Destroy(zoneName) end
end)

exports("CanUseMusicSystem",  CanUseMusicSystem)
exports("IsNearBoombox",      IsNearBoombox)
exports("GetBoomboxInHand",   function() return boomboxInHand end)