Config = {}

-- Allowed weapon is fixed to pistol only (cannot be changed)
Config.AllowedWeapons = { 'weapon_pistol' }

-- Distance for qb-target interaction
Config.TargetDistance = 3.0
Config.TargetLabel = "Rob NPC"

-- Time (ms) it takes to complete the robbery
Config.RobDuration = 7000

-- Should the ped raise hands and freeze while robbing
Config.FreezePed = true
Config.HandsUpAnim = {
    dict = 'random@arrests',
    anim = 'idle_2_hands_up'
}

-- Chance (0-100) that the ped will pull a weapon and attack after being asked (in percent)
-- The ped will always use a pistol when attacking (forced in client). Do not change weapon config.
Config.AttackChance = 100
Config.AttackTime = 10000

-- Reward config: cash range (min,max) and item drops (name, min, max, chance%)
Config.Rewards = {
    cash = { min = 20, max = 150 },
    items = {
        { name = 'bread', chance = 30, min = 1, max = 2 },
        { name = 'water_bottle', chance = 20, min = 1, max = 1 },
        { name = 'id_card', chance = 10, min = 1, max = 1 }
    }
}

-- Ped cooldown (ms) to prevent repeated robs on the same ped
Config.PedCooldown = 300000 -- 5 minutes

-- Player cooldown (ms) to prevent repeated robberies by the same player
-- Server enforces a 2 minute cooldown regardless of client attempts
Config.PlayerCooldown = 120000 -- 2 minutes

-- Ped models that are blacklisted from being robbed (optional)
Config.PedBlacklist = {
    -- 's_m_y_cop_01', 's_f_y_cop_01'
}

-- Use progressbar resource if available (set false will use simple wait)
Config.UseProgressBar = true

-- Enable debug prints
Config.Debug = true

-- Police / PD count requirements
-- Enable checking for minimum police online to allow robbing
Config.UsePoliceRequirement = true
-- Minimum number of cops required online (inclusive)
Config.MinPolice = 1
-- Which job name to treat as police (adjust to your server's job identifier)
Config.PoliceJobName = 'police'
-- Require cops to be on-duty to count? (some servers track job.onduty)
Config.RequirePoliceOnDuty = true

-- Weapon given to ped if they decide to fight is deprecated and ignored; ped will use pistol only.

-- Dispatch/Alert settings
-- Enable sending a dispatch alert to police when a robbery starts
Config.EnableDispatch = true
-- By default the resource uses the built-in internal dispatch system.
-- To enable external dispatch integration set Config.ExternalDispatch = 'ps-dispatch'.
-- By default the resource uses the built-in internal dispatch system (no external dispatch).
-- Set Config.ExternalDispatch = 'ps-dispatch' to use ps-dispatch instead of the internal dispatcher.
Config.ExternalDispatch = 'none'

-- Blip settings for client police alerts (when using built-in dispatch blip)
Config.DispatchBlip = { sprite = 161, color = 1, scale = 1.2 }
-- How long (ms) the blip should remain for police clients
Config.DispatchBlipTime = 180000 -- 3 minutes

-- Job name used to identify police players (already defined above but keep explicit here)
Config.PoliceJobName = Config.PoliceJobName or 'police'

