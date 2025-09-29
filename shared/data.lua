CraftingData = {
    Stations = {},
    Recipes = {}
}

CraftingCooldowns = {}
CraftingPlayerQueues = {}
CraftingPlayerLocks = {}
CraftingRateLimits = {}

function CraftingData.GetStation(id)
    return CraftingData.Stations[id]
end

function CraftingData.GetRecipe(id)
    return CraftingData.Recipes[id]
end

function CraftingData.SetStations(stations)
    CraftingData.Stations = stations or {}
end

function CraftingData.SetRecipes(recipes)
    CraftingData.Recipes = recipes or {}
end

function CraftingData.GetRecipeCooldown(recipeId)
    return CraftingCooldowns[recipeId]
end

function CraftingData.SetRecipeCooldown(recipeId, timestamp)
    CraftingCooldowns[recipeId] = timestamp
end

function CraftingData.CanRateLimit(source, key, interval)
    local now = GetGameTimer()
    CraftingRateLimits[source] = CraftingRateLimits[source] or {}
    local last = CraftingRateLimits[source][key]
    if last and now - last < interval then
        return false
    end
    CraftingRateLimits[source][key] = now
    return true
end

function CraftingData.ClearRateLimit(source)
    CraftingRateLimits[source] = nil
end

return CraftingData
