local Config = Config
local Locales = Locales

local ESX = exports['es_extended']:getSharedObject()

local Stations = {}
local Recipes = {}
local VisibleRecipes = {}
local Queue = {}
local CurrentStation
local CurrentCraft
local IsMenuOpen = false
local AdminMenuOpen = false
local PlayerData = {}

CreateThread(function()
    PlayerData = ESX.GetPlayerData()
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('esx:inventory:setItem', function(item, count, slot)
    PlayerData.inventory = PlayerData.inventory or {}
    local found = false
    for _, inv in pairs(PlayerData.inventory) do
        if inv.name == item then
            inv.count = count
            found = true
            break
        end
    end
    if not found then
        table.insert(PlayerData.inventory, { name = item, count = count })
    end
end)

local function _U(key)
    local locale = Config.Locale or 'en'
    return (Locales[locale] and Locales[locale][key]) or Locales['en'][key] or key
end

local function DrawText3D(x, y, z, text)
    SetDrawOrigin(x, y, z + 0.05, 0)
    SetTextScale(Config.Hints.DrawScale, Config.Hints.DrawScale)
    SetTextFont(Config.Hints.DrawFont)
    SetTextProportional(1)
    SetTextColour(Config.Hints.DrawColor[1], Config.Hints.DrawColor[2], Config.Hints.DrawColor[3], Config.Hints.DrawColor[4])
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function RequestAnimDict(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(5)
    end
end

local function LoadModel(model)
    if not IsModelValid(model) then return end
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(5)
    end
end

local function SendUI(message)
    SendNUIMessage(message)
end

local function CloseMenu()
    SetNuiFocus(false, false)
    IsMenuOpen = false
    AdminMenuOpen = false
    SendUI({ action = 'close' })
end

local function HasBlueprint(recipe)
    if not recipe.blueprint then return true end
    if not PlayerData or not PlayerData.inventory then return false end
    for _, item in pairs(PlayerData.inventory) do
        if item.name == recipe.blueprint and item.count > 0 then
            return true
        end
    end
    return false
end

local function RefreshVisibleRecipes(station)
    VisibleRecipes = {}
    for _, recipe in pairs(Recipes) do
        if not station or recipe.station == station.type then
            if HasBlueprint(recipe) then
                VisibleRecipes[#VisibleRecipes + 1] = recipe
            end
        end
    end
end

local function OpenCraftMenu(station)
    if IsMenuOpen then return end
    IsMenuOpen = true
    CurrentStation = station
    RefreshVisibleRecipes(station)
    SetNuiFocus(true, true)
    SendUI({
        action = 'open',
        station = station,
        recipes = VisibleRecipes,
        queue = Queue,
        admin = false
    })
end

local function OpenAdminMenu()
    if AdminMenuOpen then return end
    AdminMenuOpen = true
    SetNuiFocus(true, true)
    SendUI({
        action = 'openAdmin',
        stations = Stations,
        recipes = Recipes
    })
end

local function CancelCurrentCraft()
    if CurrentCraft then
        TriggerServerEvent('crafting:server:cancel')
        CurrentCraft = nil
    end
end

RegisterNetEvent('crafting:client:updateSettings', function(settings)
    if type(settings.minigame) == 'boolean' then
        Config.Crafting.MinigameEnabled = settings.minigame
    end
    if type(settings.durability) == 'boolean' then
        Config.Crafting.UseDurability = settings.durability
    end
    if type(settings.animations) == 'boolean' then
        Config.Animations.Enabled = settings.animations
    end
    if type(settings.fees) == 'boolean' then
        Config.Crafting.EnableFees = settings.fees
    end
    SendUI({ action = 'settings', payload = settings })
end)

RegisterNetEvent('crafting:client:sync', function(stations, recipes)
    Stations = stations or {}
    Recipes = recipes or {}
    RefreshVisibleRecipes(CurrentStation)
    if AdminMenuOpen then
        SendUI({ action = 'syncAdmin', stations = Stations, recipes = Recipes })
    end
    if IsMenuOpen and CurrentStation then
        SendUI({
            action = 'open',
            station = CurrentStation,
            recipes = VisibleRecipes,
            queue = Queue,
            admin = false
        })
    end
end)

RegisterNetEvent('crafting:client:queueUpdated', function(queue)
    Queue = queue or {}
    if IsMenuOpen then
        SendUI({ action = 'queue', queue = Queue })
    end
end)

RegisterNetEvent('crafting:client:notify', function(message)
    ESX.ShowNotification(message)
end)

RegisterNetEvent('crafting:client:startCraft', function(data)
    local ped = PlayerPedId()
    if not IsPedOnFoot(ped) then
        TriggerServerEvent('crafting:server:cancel')
        return
    end

    CurrentCraft = {
        recipe = data.recipe,
        station = data.station,
        amount = data.amount,
        start = GetGameTimer(),
        duration = data.recipe.time or 5000
    }

    local dict = Config.Animations.DefaultDict
    local anim = Config.Animations.DefaultAnim
    if data.recipe.animation then
        dict = data.recipe.animation.dict or dict
        anim = data.recipe.animation.anim or anim
    end

    local prop
    local propCfg = Config.Animations.DefaultProp
    if data.recipe.prop then
        propCfg = data.recipe.prop
    end

        if Config.Animations.Enabled then
            RequestAnimDict(dict)
            TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)

            if propCfg and propCfg.Model then
                local model = propCfg.Model
                if type(model) == 'string' then
                    model = GetHashKey(model)
                end
                LoadModel(model)
                prop = CreateObject(model, 0.0, 0.0, 0.0, true, true, true)
                local pos = propCfg.Position or Config.Animations.DefaultProp.Position
                local rot = propCfg.Rotation or Config.Animations.DefaultProp.Rotation
                AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, propCfg.Bone or Config.Animations.DefaultProp.Bone), pos.x or 0.0, pos.y or 0.0, pos.z or 0.0, rot.x or 0.0, rot.y or 0.0, rot.z or 0.0, true, true, false, true, 1, true)
                SetModelAsNoLongerNeeded(model)
            end
        end

    SendUI({ action = 'progress', state = 'start', label = data.recipe.label, duration = data.recipe.time, amount = data.amount })

    if data.recipe.minigame and Config.Crafting.MinigameEnabled then
        SendUI({ action = 'minigame', state = 'start' })
    end

    CreateThread(function()
        while CurrentCraft do
            local elapsed = GetGameTimer() - CurrentCraft.start
            local progress = math.min(1.0, elapsed / CurrentCraft.duration)
            SendUI({ action = 'progress', state = 'update', value = progress })
            Wait(Config.Crafting.ProgressUpdateInterval)
            if not IsPedOnFoot(ped) then
                CancelCurrentCraft()
                break
            end
            if CurrentCraft and CurrentCraft.station then
                local coords = GetEntityCoords(ped)
                local stationCoords = vector3(CurrentCraft.station.coords[1], CurrentCraft.station.coords[2], CurrentCraft.station.coords[3])
                if #(coords - stationCoords) > (CurrentCraft.station.radius or 3.0) + Config.Crafting.CancelDistance then
                    CancelCurrentCraft()
                    break
                end
            end
        end
        if prop and DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
        if Config.Animations.Enabled then
            ClearPedTasks(ped)
        end
    end)
end)

RegisterNetEvent('crafting:client:craftSuccess', function(recipeId)
    SendUI({ action = 'progress', state = 'finish', success = true, recipe = recipeId })
    CurrentCraft = nil
end)

RegisterNetEvent('crafting:client:craftFailed', function(reason)
    SendUI({ action = 'progress', state = 'finish', success = false, reason = reason })
    CurrentCraft = nil
end)

RegisterNetEvent('crafting:client:craftCancelled', function()
    SendUI({ action = 'progress', state = 'finish', success = false })
    CurrentCraft = nil
end)

RegisterNetEvent('crafting:client:openAdmin', function(stations, recipes)
    Stations = stations or {}
    Recipes = recipes or {}
    OpenAdminMenu()
end)

RegisterNetEvent('crafting:openMenu', function(stationId)
    if stationId then
        local station = Stations[stationId]
        if station then
            CurrentStation = station
            OpenCraftMenu(station)
        end
    elseif CurrentStation then
        OpenCraftMenu(CurrentStation)
    end
end)

RegisterNetEvent('crafting:client:hint', function(toggle, station)
    if toggle then
        CurrentStation = station
    else
        CurrentStation = nil
    end
end)

RegisterNUICallback('crafting:add', function(data, cb)
    if not CurrentStation and not data.stationId then
        cb({ success = false, message = _U('invalid_station') })
        return
    end
    local payload = {
        recipeId = data.recipeId,
        stationId = data.stationId or CurrentStation.id,
        amount = data.amount or 1
    }
    TriggerServerEvent('crafting:server:addToQueue', payload)
    cb({ success = true })
end)

RegisterNUICallback('crafting:cancel', function(_, cb)
    CancelCurrentCraft()
    cb({ success = true })
end)

RegisterNUICallback('crafting:close', function(_, cb)
    CloseMenu()
    cb({})
end)

RegisterNUICallback('crafting:admin:saveStation', function(data, cb)
    TriggerServerEvent('crafting:server:saveStation', data)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:deleteStation', function(data, cb)
    TriggerServerEvent('crafting:server:deleteStation', data.id)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:saveRecipe', function(data, cb)
    TriggerServerEvent('crafting:server:saveRecipe', data)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:deleteRecipe', function(data, cb)
    TriggerServerEvent('crafting:server:deleteRecipe', data.id)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:import', function(data, cb)
    TriggerServerEvent('crafting:server:importData', data.type, data.payload)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:export', function(data, cb)
    TriggerServerEvent('crafting:server:exportData', data.type)
    cb({ success = true })
end)

RegisterNUICallback('crafting:admin:updateSetting', function(data, cb)
    TriggerServerEvent('crafting:server:updateSetting', data)
    cb({ success = true })
end)

RegisterNUICallback('crafting:minigame:result', function(data, cb)
    if data.success then
        SendUI({ action = 'minigame', state = 'success' })
    else
        SendUI({ action = 'minigame', state = 'fail' })
        CancelCurrentCraft()
    end
    cb({})
end)

RegisterNUICallback('crafting:sfx', function(data, cb)
    if data.sound == 'open' then
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    elseif data.sound == 'close' then
        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    elseif data.sound == 'success' then
        PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
    end
    cb({})
end)

RegisterCommand('+crafting_interact', function()
    local ped = PlayerPedId()
    if not IsPedOnFoot(ped) then return end
    if not CurrentStation then return end
    OpenCraftMenu(CurrentStation)
end, false)

RegisterCommand('-crafting_interact', function() end, false)
RegisterKeyMapping('+crafting_interact', 'Open crafting menu', 'keyboard', 'E')

RegisterCommand('+crafting_interact_pad', function()
    local ped = PlayerPedId()
    if not IsPedOnFoot(ped) then return end
    if not CurrentStation then return end
    OpenCraftMenu(CurrentStation)
end, false)
RegisterCommand('-crafting_interact_pad', function() end, false)
RegisterKeyMapping('+crafting_interact_pad', 'Open crafting menu (gamepad)', 'pad_digitalbutton', 'A')

RegisterCommand(Config.Commands.Admin, function()
    TriggerServerEvent('crafting:server:adminOpen')
end, false)

local function IsWithinStation(station)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local distance = #(coords - vector3(station.coords[1], station.coords[2], station.coords[3]))
    return distance <= (station.radius or 3.0)
end

CreateThread(function()
    local text = _U('hint')
    local lastStation
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        if IsPedOnFoot(ped) then
            local coords = GetEntityCoords(ped)
            local nearest
            local nearestDist = Config.Hints.DrawDistance
            for id, station in pairs(Stations) do
                local stationCoords = vector3(station.coords[1], station.coords[2], station.coords[3])
                local dist = #(coords - stationCoords)
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = station
                end
            end

            if nearest and nearestDist <= Config.Hints.DrawDistance then
                sleep = 0
                if nearestDist <= Config.Hints.TextDistance then
                    DrawText3D(nearest.coords[1], nearest.coords[2], nearest.coords[3], text)
                    if lastStation ~= nearest.id then
                        TriggerEvent('crafting:hint', true, nearest)
                        lastStation = nearest.id
                    end
                    CurrentStation = nearest
                else
                    CurrentStation = nil
                    if lastStation then
                        TriggerEvent('crafting:hint', false)
                        lastStation = nil
                    end
                end
            else
                CurrentStation = nil
                if lastStation then
                    TriggerEvent('crafting:hint', false)
                    lastStation = nil
                end
            end
        else
            CurrentStation = nil
            if lastStation then
                TriggerEvent('crafting:hint', false)
                lastStation = nil
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CloseMenu()
    if CurrentCraft then
        CancelCurrentCraft()
    end
end)
