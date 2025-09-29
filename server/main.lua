local Config = Config
local Locales = Locales
local CraftingData = CraftingData

local ESX = exports['es_extended']:getSharedObject()

local resourceName = GetCurrentResourceName()
local json = json

local function tableCount(tbl)
    local c = 0
    for _ in pairs(tbl or {}) do
        c = c + 1
    end
    return c
end

local function tableClone(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            copy[k] = tableClone(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local function _U(key)
    local locale = Config.Locale or 'en'
    return (Locales[locale] and Locales[locale][key]) or Locales['en'][key] or key
end

local function debugPrint(...)
    if Config.Debug then
        print('[^5Crafting^0]', ...)
    end
end

local function LoadJsonFile(path)
    local raw = LoadResourceFile(resourceName, path)
    if not raw then return nil end
    local data = json.decode(raw)
    return data
end

local function SaveJsonFile(path, data)
    SaveResourceFile(resourceName, path, json.encode(data, { indent = true }), -1)
end

local function LoadStations()
    if Config.Persistence == 'sql' then
        local result = MySQL.Sync.fetchAll('SELECT * FROM `' .. Config.SQL.StationsTable .. '`')
        local stations = {}
        for _, row in ipairs(result) do
            stations[row.id] = {
                id = row.id,
                label = row.label,
                type = row.type,
                coords = json.decode(row.coords),
                radius = row.radius,
                job = row.job,
                grade = row.grade,
                items = row.items and json.decode(row.items) or {},
                hours = row.hours and json.decode(row.hours) or nil
            }
        end
        return stations
    else
        local data = LoadJsonFile(Config.Data.StationsFile) or {}
        local stations = {}
        for _, station in ipairs(data) do
            stations[station.id] = station
        end
        return stations
    end
end

local function LoadRecipes()
    if Config.Persistence == 'sql' then
        local result = MySQL.Sync.fetchAll('SELECT * FROM `' .. Config.SQL.RecipesTable .. '`')
        local recipes = {}
        for _, row in ipairs(result) do
            local data = json.decode(row.data)
            data.id = row.id
            data.label = row.label
            recipes[row.id] = data
        end
        return recipes
    else
        local data = LoadJsonFile(Config.Data.RecipesFile) or {}
        local recipes = {}
        for _, recipe in ipairs(data) do
            recipes[recipe.id] = recipe
        end
        return recipes
    end
end

local function PersistStations()
    if Config.Persistence == 'sql' then
        for _, station in pairs(CraftingData.Stations) do
            MySQL.Async.execute('REPLACE INTO `' .. Config.SQL.StationsTable .. '` (`id`,`label`,`type`,`coords`,`radius`,`job`,`grade`,`items`,`hours`) VALUES (?,?,?,?,?,?,?,?,?)', {
                station.id,
                station.label,
                station.type,
                json.encode(station.coords),
                station.radius,
                station.job,
                station.grade,
                json.encode(station.items or {}),
                station.hours and json.encode(station.hours) or nil
            })
        end
    else
        local payload = {}
        for _, station in pairs(CraftingData.Stations) do
            payload[#payload + 1] = station
        end
        SaveJsonFile(Config.Data.StationsFile, payload)
    end
end

local function PersistRecipes()
    if Config.Persistence == 'sql' then
        for _, recipe in pairs(CraftingData.Recipes) do
            MySQL.Async.execute('REPLACE INTO `' .. Config.SQL.RecipesTable .. '` (`id`,`label`,`station`,`data`) VALUES (?,?,?,?)', {
                recipe.id,
                recipe.label,
                recipe.station,
                json.encode(recipe)
            })
        end
    else
        local payload = {}
        for _, recipe in pairs(CraftingData.Recipes) do
            payload[#payload + 1] = recipe
        end
        SaveJsonFile(Config.Data.RecipesFile, payload)
    end
end

local function BroadcastData(target)
    local stations = CraftingData.Stations
    local recipes = CraftingData.Recipes
    local settings = {
        minigame = Config.Crafting.MinigameEnabled,
        durability = Config.Crafting.UseDurability,
        fees = Config.Crafting.EnableFees,
        animations = Config.Animations.Enabled
    }
    if target then
        TriggerClientEvent('crafting:client:sync', target, stations, recipes)
        TriggerClientEvent('crafting:client:updateSettings', target, settings)
    else
        TriggerClientEvent('crafting:client:sync', -1, stations, recipes)
        TriggerClientEvent('crafting:client:updateSettings', -1, settings)
    end
end

local function LoadAll()
    CraftingData.SetStations(LoadStations())
    CraftingData.SetRecipes(LoadRecipes())
    debugPrint('Loaded', tableCount(CraftingData.Stations), 'stations and', tableCount(CraftingData.Recipes), 'recipes')
end

local function EnsureQueue(source)
    if not CraftingPlayerQueues[source] then
        CraftingPlayerQueues[source] = {
            active = false,
            queue = {},
            limit = Config.Crafting.DefaultQueueLimit
        }
    end
    return CraftingPlayerQueues[source]
end

local function Notify(source, msg)
    TriggerClientEvent('esx:showNotification', source, msg)
end

local function VectorDistance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function ValidateStationAccess(xPlayer, stationId)
    local station = CraftingData.GetStation(stationId)
    if not station then return false, _U('invalid_station') end

    if station.job and station.job ~= '' and xPlayer.job.name ~= station.job then
        return false, _U('missing_job')
    end
    if station.grade and xPlayer.job.grade < station.grade then
        return false, _U('missing_job')
    end

    if station.items and #station.items > 0 then
        for _, item in ipairs(station.items) do
            local inv = xPlayer.getInventoryItem(item)
            if not inv or inv.count <= 0 then
                return false, _U('missing_items')
            end
        end
    end

    if station.hours then
        local open = station.hours.open or 0
        local close = station.hours.close or 24
        local hour = tonumber(os.date('%H'))
        if close > open then
            if hour < open or hour >= close then
                return false, _U('outside_hours')
            end
        else
            if hour < open and hour >= close then
                return false, _U('outside_hours')
            end
        end
    end

    local ped = GetPlayerPed(xPlayer.source)
    if ped and ped ~= 0 then
        local coords = GetEntityCoords(ped)
        local stationCoords = vector3(station.coords[1], station.coords[2], station.coords[3])
        local dist = VectorDistance(coords, stationCoords)
        if dist > (station.radius or 3.0) + Config.Crafting.CancelDistance then
            return false, _U('invalid_station')
        end
    end

    return true, station
end

local function HasBlueprint(xPlayer, blueprint)
    if not blueprint then return true end
    local item = xPlayer.getInventoryItem(blueprint)
    return item and item.count > 0
end

local function ValidateRecipeAccess(xPlayer, recipeId)
    local recipe = CraftingData.GetRecipe(recipeId)
    if not recipe then return false, _U('invalid_data') end

    if recipe.job and recipe.job ~= '' and xPlayer.job.name ~= recipe.job then
        return false, _U('missing_job')
    end
    if recipe.grade and xPlayer.job.grade < recipe.grade then
        return false, _U('missing_job')
    end

    if recipe.blueprint and not HasBlueprint(xPlayer, recipe.blueprint) then
        return false, _U('blueprint_locked')
    end

    if recipe.level and Config.Skill.Enabled then
        local identifier = xPlayer.identifier
        local level = Config.Skill.Levels[identifier] or Config.Skill.DefaultLevel
        if level < recipe.level then
            return false, _U('missing_level')
        end
    end

    if recipe.accountMoney then
        local account = xPlayer.getAccount(recipe.accountMoney.account or 'bank')
        if not account or account.money < recipe.accountMoney.amount then
            return false, _U('not_enough_money')
        end
    end

    return true, recipe
end

local function CheckTools(xPlayer, recipe)
    if not recipe.tools or #recipe.tools == 0 then
        return true
    end
    for _, tool in ipairs(recipe.tools) do
        local item = xPlayer.getInventoryItem(tool)
        if not item or item.count <= 0 then
            return false
        end
    end
    return true
end

local function DeductInputs(xPlayer, recipe, amount)
    local removed = {}
    for _, input in ipairs(recipe.inputs or {}) do
        local count = input.count * amount
        local item = xPlayer.getInventoryItem(input.item)
        if not item or item.count < count then
            return false, _U('missing_items')
        end
        removed[#removed + 1] = { item = input.item, count = count }
    end

    for _, entry in ipairs(removed) do
        xPlayer.removeInventoryItem(entry.item, entry.count)
    end

    if recipe.accountMoney then
        xPlayer.removeAccountMoney(recipe.accountMoney.account or 'bank', recipe.accountMoney.amount * amount)
    end

    if Config.Crafting.EnableFees and recipe.fee and recipe.fee > 0 then
        local totalFee = recipe.fee * amount
        if recipe.feeAccount and recipe.feeAccount ~= '' then
            TriggerEvent('esx_addonaccount:getSharedAccount', recipe.feeAccount, function(account)
                if account then
                    account.addMoney(totalFee)
                else
                    xPlayer.removeAccountMoney(recipe.feeType or Config.Crafting.FeeFallback or 'cash', totalFee)
                end
            end)
        else
            xPlayer.removeAccountMoney(recipe.feeType or Config.Crafting.FeeFallback or 'cash', totalFee)
        end
    end

    return true
end

local function RefundInputs(xPlayer, recipe, amount)
    for _, input in ipairs(recipe.inputs or {}) do
        local count = input.count * amount
        xPlayer.addInventoryItem(input.item, count)
    end
    if recipe.accountMoney then
        xPlayer.addAccountMoney(recipe.accountMoney.account or 'bank', recipe.accountMoney.amount * amount)
    end
end

local function ApplyOutputs(xPlayer, recipe, amount)
    for _, output in ipairs(recipe.outputs or {}) do
        local metadata = tableClone(output.metadata or {})
        if recipe.quality then
            metadata.quality = math.random(recipe.quality.min or 80, recipe.quality.max or 120)
        end
        metadata.craftedBy = xPlayer.getName() or xPlayer.identifier
        metadata.craftedAt = os.time()
        for i = 1, (output.count * amount) do
            local entry = metadata
            if metadata.serial then
                entry = tableClone(metadata)
                entry.serial = entry.serial .. '-' .. math.random(1000, 9999)
            end
            xPlayer.addInventoryItem(output.item, 1, entry)
        end
    end
end

local function ApplyDurability(xPlayer, recipe)
    if not Config.Crafting.UseDurability then return true end
    if not recipe.durability or not recipe.durability.tool then return true end
    for _, tool in ipairs(recipe.tools or {}) do
        local item = xPlayer.getInventoryItem(tool)
        if item and item.metadata and item.metadata.durability then
            local metadata = tableClone(item.metadata)
            local newDurability = (metadata.durability or 100) - recipe.durability.tool
            xPlayer.removeInventoryItem(tool, 1, metadata)
            if newDurability > 0 then
                metadata.durability = newDurability
                xPlayer.addInventoryItem(tool, 1, metadata)
            end
        end
    end
end

local function StartCrafting(source)
    local queue = EnsureQueue(source)
    if queue.active then return end
    if #queue.queue == 0 then
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        return
    end

    local entry = queue.queue[1]
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local ok, stationOrMessage = ValidateStationAccess(xPlayer, entry.stationId)
    if not ok then
        Notify(source, stationOrMessage)
        queue.queue = {}
        queue.active = false
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        TriggerClientEvent('crafting:client:craftFailed', source, stationOrMessage)
        return
    end
    local station = stationOrMessage

    local okRecipe, recipeOrMessage = ValidateRecipeAccess(xPlayer, entry.recipeId)
    if not okRecipe then
        Notify(source, recipeOrMessage)
        table.remove(queue.queue, 1)
        queue.active = false
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        return
    end
    local recipe = recipeOrMessage

    if not CheckTools(xPlayer, recipe) then
        Notify(source, _U('missing_tools'))
        table.remove(queue.queue, 1)
        queue.active = false
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        return
    end

    local cooldown = recipe.cooldown or Config.Crafting.Cooldown
    local last = CraftingData.GetRecipeCooldown(recipe.id)
    if last and os.time() < last then
        Notify(source, _U('cooldown'))
        table.remove(queue.queue, 1)
        queue.active = false
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        return
    end

    local success, reason = DeductInputs(xPlayer, recipe, entry.amount)
    if not success then
        Notify(source, reason or _U('missing_items'))
        table.remove(queue.queue, 1)
        queue.active = false
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        return
    end

    queue.active = true
    queue.current = entry

    CraftingPlayerLocks[source] = true
    TriggerEvent('crafting:started', source, recipe.id, station.id)
    TriggerClientEvent('crafting:client:startCraft', source, {
        recipe = recipe,
        station = station,
        amount = entry.amount
    })

    SetTimeout(recipe.time or 5000, function()
        if not CraftingPlayerLocks[source] then
            RefundInputs(xPlayer, recipe, entry.amount)
            queue.active = false
            table.remove(queue.queue, 1)
            TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
            TriggerClientEvent('crafting:client:craftFailed', source, _U('crafting_cancelled'))
            return
        end

        CraftingData.SetRecipeCooldown(recipe.id, os.time() + cooldown)
        ApplyOutputs(xPlayer, recipe, entry.amount)
        ApplyDurability(xPlayer, recipe)

        CraftingPlayerLocks[source] = nil

        queue.active = false
        table.remove(queue.queue, 1)
        TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
        TriggerClientEvent('crafting:client:craftSuccess', source, recipe.id)
        TriggerEvent('crafting:finished', source, recipe.id, true)
        StartCrafting(source)
    end)
end

local function CancelCrafting(source)
    CraftingPlayerLocks[source] = nil
    local queue = EnsureQueue(source)
    if queue.active then
        queue.active = false
        TriggerClientEvent('crafting:client:craftCancelled', source)
        TriggerEvent('crafting:cancelled', source)
    end
    queue.queue = {}
    queue.current = nil
    TriggerClientEvent('crafting:client:queueUpdated', source, queue.queue)
end

RegisterNetEvent('crafting:server:addToQueue', function(data)
    local src = source
    local queue = EnsureQueue(src)
    if not CraftingData.CanRateLimit(src, 'craft', Config.RateLimit.CraftRequest) then
        TriggerClientEvent('crafting:client:notify', src, _U('rate_limited'))
        return
    end

    if #queue.queue >= queue.limit then
        TriggerClientEvent('crafting:client:notify', src, _U('queue_full'))
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local recipeId = data.recipeId
    local stationId = data.stationId
    local amount = math.max(1, math.floor(data.amount or 1))

    local ok, recipeOrMessage = ValidateRecipeAccess(xPlayer, recipeId)
    if not ok then
        TriggerClientEvent('crafting:client:notify', src, recipeOrMessage)
        return
    end

    local okStation, stationMessage = ValidateStationAccess(xPlayer, stationId)
    if not okStation then
        TriggerClientEvent('crafting:client:notify', src, stationMessage)
        return
    end

    queue.queue[#queue.queue + 1] = {
        recipeId = recipeId,
        stationId = stationId,
        amount = amount
    }

    TriggerClientEvent('crafting:client:queueUpdated', src, queue.queue)
    StartCrafting(src)
end)

RegisterNetEvent('crafting:server:cancel', function()
    CancelCrafting(source)
end)

RegisterNetEvent('crafting:server:adminOpen', function()
    local src = source
    if not CraftingData.CanRateLimit(src, 'admin', Config.RateLimit.AdminRequest) then
        TriggerClientEvent('crafting:client:notify', src, _U('rate_limited'))
        return
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then
        TriggerClientEvent('crafting:client:notify', src, _U('admin_only'))
        return
    end
    TriggerClientEvent('crafting:client:openAdmin', src, CraftingData.Stations, CraftingData.Recipes)
end)

RegisterNetEvent('crafting:server:saveStation', function(payload)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    if not payload.id or payload.id == '' then
        payload.id = ('station_%s'):format(math.random(1000, 9999))
    end

    CraftingData.Stations[payload.id] = payload
    PersistStations()
    BroadcastData()
    TriggerClientEvent('crafting:client:notify', src, _U('saved'))
end)

RegisterNetEvent('crafting:server:deleteStation', function(id)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    CraftingData.Stations[id] = nil
    PersistStations()
    BroadcastData()
    TriggerClientEvent('crafting:client:notify', src, _U('deleted'))
end)

RegisterNetEvent('crafting:server:saveRecipe', function(payload)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    if not payload.id or payload.id == '' then
        payload.id = ('recipe_%s'):format(math.random(1000, 9999))
    end

    CraftingData.Recipes[payload.id] = payload
    PersistRecipes()
    BroadcastData()
    TriggerClientEvent('crafting:client:notify', src, _U('saved'))
end)

RegisterNetEvent('crafting:server:deleteRecipe', function(id)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    CraftingData.Recipes[id] = nil
    PersistRecipes()
    BroadcastData()
    TriggerClientEvent('crafting:client:notify', src, _U('deleted'))
end)

RegisterNetEvent('crafting:server:importData', function(typeName, jsonData)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    local ok, data = pcall(json.decode, jsonData)
    if not ok or type(data) ~= 'table' then
        TriggerClientEvent('crafting:client:notify', src, _U('invalid_data'))
        return
    end

    if typeName == 'stations' then
        local stations = {}
        for _, station in ipairs(data) do
            stations[station.id] = station
        end
        CraftingData.SetStations(stations)
        PersistStations()
    else
        local recipes = {}
        for _, recipe in ipairs(data) do
            recipes[recipe.id] = recipe
        end
        CraftingData.SetRecipes(recipes)
        PersistRecipes()
    end

    BroadcastData()
    TriggerClientEvent('crafting:client:notify', src, _U('imported'))
end)

RegisterNetEvent('crafting:server:exportData', function(typeName)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    if typeName == 'stations' then
        print('Crafting Stations Export:', json.encode(CraftingData.Stations, { indent = true }))
    else
        print('Crafting Recipes Export:', json.encode(CraftingData.Recipes, { indent = true }))
    end

    TriggerClientEvent('crafting:client:notify', src, _U('exported'))
end)

RegisterNetEvent('crafting:server:updateSetting', function(settings)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local group = xPlayer.getGroup()
    if group ~= 'admin' and group ~= 'superadmin' and group ~= 'god' then return end

    if type(settings.minigame) == 'boolean' then
        Config.Crafting.MinigameEnabled = settings.minigame
    end
    if type(settings.durability) == 'boolean' then
        Config.Crafting.UseDurability = settings.durability
    end
    if type(settings.fees) == 'boolean' then
        Config.Crafting.EnableFees = settings.fees
    end
    if type(settings.animations) == 'boolean' then
        Config.Animations.Enabled = settings.animations
    end

    BroadcastData()
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    BroadcastData(playerId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    CraftingData.ClearRateLimit(src)
    CraftingPlayerQueues[src] = nil
    CraftingPlayerLocks[src] = nil
end)

exports('AddRecipe', function(recipe)
    CraftingData.Recipes[recipe.id] = recipe
    PersistRecipes()
    BroadcastData()
end)

exports('RemoveRecipe', function(recipeId)
    CraftingData.Recipes[recipeId] = nil
    PersistRecipes()
    BroadcastData()
end)

exports('AddStation', function(station)
    CraftingData.Stations[station.id] = station
    PersistStations()
    BroadcastData()
end)

exports('RemoveStation', function(stationId)
    CraftingData.Stations[stationId] = nil
    PersistStations()
    BroadcastData()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= resourceName then return end
    LoadAll()
    BroadcastData()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    for _, queue in pairs(CraftingPlayerQueues) do
        queue.queue = {}
        queue.active = false
    end
end)
