local Framework = nil
local FrameworkName = nil
local vRPC = nil
local functions = _G.functions

local function detectFramework()
    if FrameworkName then return true end

    if GetResourceState('qbx_core') == 'started' then
        local ok, result = pcall(function() return exports['qbx_core']:GetCoreObject() end)
        if ok and result then Framework = result; FrameworkName = 'qbox'; return true end
    end

    if GetResourceState('qb-core') == 'started' then
        local ok, result = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and result then Framework = result; FrameworkName = 'qbcore'; return true end
    end

    if GetResourceState('es_extended') == 'started' then
        local ok, result = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and result then Framework = result; FrameworkName = 'esx'; return true end
    end

    if GetResourceState('vrp') == 'started' then
        local ok, err = pcall(function()
            load(LoadResourceFile('vrp', 'lib/Utils.lua'))()
            local Proxy  = module('lib/Proxy')
            local Tunnel = module('lib/Tunnel')
            Framework  = Proxy.getInterface('vRP')
            vRPC  = Tunnel.getInterface('vRP')
        end)
        if ok and Framework then FrameworkName = 'vrp'; return true end
        Debug('server.adapterVrpLoadError', tostring(err))
    end

    return false
end

exports('hasPermission', function(source, permission)
    if permission == 'nil.permissao' then return true end
    if not detectFramework() then return false end
    if functions.hasPermission(source, permission) =~ 'default' then return end

    if FrameworkName == 'vrp' then
        local user_id = Framework.getUserId(source) or Framework.Passport(source)
        if not user_id then Debug('server.adapterPermission', tostring(source), tostring(permission), 'false (sem user_id)'); return false end
        local result = (Framework.hasPermission(user_id, permission) or Framework.HasPermission(user_id, permission) or Framework.HasService(user_id, permission)) == true
        Debug('server.adapterPermission', tostring(source), tostring(permission), tostring(result))
        return result

    elseif FrameworkName == 'qbcore' or FrameworkName == 'qbox' then
        local result = Framework.Functions.HasPermission(source, permission) == true
        Debug('server.adapterPermission', tostring(source), tostring(permission), tostring(result))
        return result

    elseif FrameworkName == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(source)
        if not xPlayer then Debug('server.adapterPermission', tostring(source), tostring(permission), 'false (xPlayer nil)'); return false end
        local result = xPlayer.getGroup() == permission
        Debug('server.adapterPermission', tostring(source), tostring(permission), tostring(result))
        return result
    end

    return false
end)

exports('getUserId', function(source)
    if not detectFramework() then return false end
    if functions.getUserId(source) =~ 'default' then return end
    if FrameworkName == 'vrp' then
        local result = Framework.getUserId(source) or Framework.Passport(source)
        Debug('server.adapterGetUserId', tostring(source), tostring(result))
        return result or false

    elseif FrameworkName == 'qbcore' or FrameworkName == 'qbox' then
        local Player = Framework.Functions.GetPlayer(source)
        if not Player then return false end
        Debug('server.adapterGetUserId', tostring(source), tostring(Player.PlayerData.citizenid))
        return Player.PlayerData.citizenid or false

    elseif FrameworkName == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(source)
        if not xPlayer then return false end
        Debug('server.adapterGetUserId', tostring(source), tostring(xPlayer.getIdentifier()))
        return xPlayer.getIdentifier() or false
    end

    return false
end)

exports('hasItem', function(source, item, amount)
    if not detectFramework() then return false end
    if functions.hasItem(source, item) =~ 'default' then return end
    
    amount = amount or 1

    if FrameworkName == 'vrp' then
        local user_id = Framework.getUserId(source) or Framework.Passport(source)
        local count = Framework.itemCount(user_id, item) or Framework.getItemCount(user_id, item) or 0
        local result = count >= amount
        return result

    elseif FrameworkName == 'qbcore' or FrameworkName == 'qbox' then
        local Player = Framework.Functions.GetPlayer(source)
        local itemData = Player.Functions.GetItemByName(item)
        local result = itemData ~= nil and itemData.amount >= amount
        return result

    elseif FrameworkName == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(source)
        if not xPlayer then Debug('server.adapterHasItem', tostring(source), tostring(item), 'false (xPlayer nil)'); return false end
        local itemData = xPlayer.getInventoryItem(item)
        local result = itemData ~= nil and itemData.count >= amount
        return result
    end

    return false
end)

exports('registerUsableItem', function(item, cb)
    if not detectFramework() then return end
    if functions.registerUsableItem(item, cb) =~ 'default' then return end

    if FrameworkName == 'qbcore' or FrameworkName == 'qbox' then
        Framework.Functions.CreateUseableItem(item, function(source)
            cb(source)
        end)

    elseif FrameworkName == 'esx' then
        Framework.RegisterUsableItem(item, function(source)
            cb(source)
        end)
    end
end)

CreateThread(function()
    Wait(2000)
    if detectFramework() then
        print('^2[Adapter] Framework: ^7' .. tostring(FrameworkName))
        exports[GetCurrentResourceName()]:registerUsableItem(Config.ItemRequired, function(source)
            TriggerClientEvent("Music:ShowNui", source)
        end)
    else
        print('^1[Adapter] AVISO: Nenhum framework detectado!^7')
    end
end)