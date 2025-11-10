Config = {}

-- Billing / cost
-- Billing amounts (separate for NPC revive vs ambulance transport)
Config.CostNPC = 500 -- charged when NPC medic revives the player
Config.CostAmbulance = 1000 -- charged when ambulance completes drop-off

-- Menu configuration: "qb" for qb-menu, "custom" for NUI
Config.MenuType = "custom" -- options: "qb", "custom"

-- Job and ambulance availability rules
Config.AmbulanceJobName = "ambulance"
Config.RequiredAmbulancesOnline = 1 -- if this many or more are on-duty, only ambulance job can use /medic

-- Medic ped options
Config.MedicPed = "s_m_m_paramedic_01"
Config.MedicPedFallbacks = { "s_m_m_paramedic_01", "u_m_m_joeschmoe" }

-- CPR / timings
Config.CPRDuration = 15000 -- ms
Config.ProgressFallbackInterval = 500

-- Spawn / approach
Config.SpawnOffset = vector3(3.0, 0.0, 0.0)
Config.FindRadius = 5.0
Config.MedicApproachDistance = 2.0
Config.MedicApproachTimeout = 8000

-- Limits / debugging
Config.Prefix = "[AI Medic]"
-- legacy: keep for backward compatibility
Config.Cooldown = 600
Config.MedicCooldown = 600 -- seconds, default 10 minutes
Config.Debug = true
Config.MaxSimultaneousMedics = 3
Config.BypassJobs = { "ambulance", "police" }

-- Jobs exempt from billing (no charge when using NPC or ambulance)
Config.BillingExemptJobs = { Config.AmbulanceJobName, "police" }

-- Logging / webhooks
Config.EnableLogging = true
Config.EnableFileLogging = false
Config.WebhookURL = ""

-- Heartbeat sound configuration (used during revive)
Config.HeartbeatSoundName = 'Beep_Red'
Config.HeartbeatSoundSet = 'DLC_HEIST_HACKING_SNAKE_SOUNDS'
Config.HeartbeatInterval = 1000 -- ms between beats
Config.UseSoundFallbacks = true -- try alternate playback methods

-- Ambulance arrival song (MP3 resource name, lowercase)
Config.AmbulanceArrivalSong = 'medic_song'
Config.AmbulanceArrivalSongSet = '' -- optional soundset, leave empty for frontend fallback

-- Call rules
Config.AllowCallWhenNotMarkedDown = false
Config.MaxCallDistance = 100.0
Config.EnforceMaxCallDistance = false
Config.BlockWhenInVehicle = true
Config.BlockWhenSpectating = true
Config.MaxConcurrentCallsPerTarget = 1
Config.CallerRateWindow = 60
Config.CallerMaxCallsPerWindow = 3
Config.PaymentMethods = { 'bank', 'cash' }

-- Ambulance AI settings
Config.AmbulanceModel = 'ambulance'
Config.DriverModel = 's_m_m_paramedic_01'
Config.AmbulanceDropOff1 = vector3(292.45, -582.97, 43.19)
Config.AmbulanceDropOff2 = vector3(315.77, -591.50, 43.19)
Config.AmbulanceStuckTimeout = 120 -- seconds before considered stuck
Config.AmbulanceOverallTimeout = 300 -- seconds overall timeout before fallback
Config.SpawnDistance = 30.0
Config.PickupRadius = 4.5
Config.SeatIndices = {2,1,0}
Config.AmbulancePostPickupLife = 10000 -- ms after pickup before driving to dropoff1 (shortened to ~10s)
Config.AmbulanceAfterDropoff2Life = 20000 -- ms after final dropoff before cleanup
return Config
