Config = {}

Config.Locale = "pt-br"
Config.CommandVehicle = "som"
Config.MinimumHealth = 101
Config.StopOnDeath = true
Config.DistanceToVolume = 100.0
Config.PlayToEveryone = true
Config.Debug = true
Config.RequireItem = false
Config.ItemRequired = "boombox"
Config.UseItem = false -- funciona somente em esx ou qbcore

Config.Boombox = {
    Enabled = true,
    Model = "prop_boombox_01",
    Range = 20,
}

Config.VehicleTakeover = {
    Enabled = true,
    TakeoverVolume = 0.8,
    FadeDuration = 800,
    HidePropOnEnter = true,
}

Config.Permissions = {
    RequirePermission = true,
    AllowedGroups = { "Admin", "som" },
}

Config.Zones = {
    {
        -- name            = "ZONE_NAME",
        -- coords          = vector3(0, 0, 0),
        -- range           = 30.0,
        -- volume          = 0.1,
        -- deflink         = "https://www.youtube.com/watch?v=xxx",
        -- isplaying       = true,
        -- loop            = true,
        -- deftime         = 0,
        -- changemusicblip = vector3(0, 0, 0),
    }
}

Config.IsWindowsOpen = function(vehicle)
    return true
end