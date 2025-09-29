Config = {}

Config.Locale = 'en'

Config.Debug = false

Config.Persistence = 'json' -- 'json' or 'sql'

Config.Data = {
    StationsFile = 'data/stations.json',
    RecipesFile = 'data/recipes.json'
}

Config.SQL = {
    StationsTable = 'crafting_stations',
    RecipesTable = 'crafting_recipes'
}

Config.Crafting = {
    ProgressUpdateInterval = 500,
    CancelDistance = 5.0,
    Cooldown = 5, -- default fallback seconds
    MinigameEnabled = true,
    UseDurability = true,
    EnableFees = true,
    FeeAccount = 'society_mechanic',
    FeeFallback = 'cash', -- cash or bank
    DefaultQueueLimit = 5
}

Config.Hints = {
    DrawDistance = 20.0,
    TextDistance = 2.5,
    DrawScale = 0.35,
    DrawFont = 4,
    DrawColor = {255, 255, 255, 200}
}

Config.Animations = {
    Enabled = true,
    DefaultDict = 'mini@repair',
    DefaultAnim = 'fixing_a_ped',
    DefaultProp = {
        Model = 'prop_tool_hammer',
        Bone = 28422,
        Position = {x = 0.0, y = 0.0, z = 0.0},
        Rotation = {x = 0.0, y = 0.0, z = 0.0}
    }
}

Config.BlueprintItem = 'crafting_blueprint'

Config.Skill = {
    Enabled = false,
    DefaultLevel = 0,
    Levels = {
        -- ['identifier'] = level
    }
}

Config.Commands = {
    Admin = 'craftadmin'
}

Config.RateLimit = {
    CraftRequest = 1500,
    AdminRequest = 1000
}

return Config
