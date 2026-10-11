if not game:IsLoaded() then game.Loaded:Wait() end

local BASE = "https://raw.githubusercontent.com/nonfq/nonfqhub/main/"
local FALLBACK = "hub.luau"

local SUPPORTED = {
   [79393329652220] = "games/Defusal.luau",
   [1240123653] = "games/ZombieAttack.luau", -- Easy Mode
   [504035427] = "games/ZombieAttack.luau", -- Hard mode
}

local env = getgenv()
if env.NonDevLoaded then return end
env.NonDevLoaded = true

local function run(path)
    local ok, src = pcall(game.HttpGet, game, BASE .. path)
    if not ok or type(src) ~= "string" or src:sub(1, 3) == "404" then
        return false, "fetch failed: " .. path
    end
    local fn, compileErr = loadstring(src)
    if not fn then return false, compileErr end
    return pcall(fn)
end

local target = SUPPORTED[game.PlaceId] or SUPPORTED[game.GameId]
local ok, err = false, nil

if target then
    ok, err = run(target)
    if not ok then
        warn("[nondev] game script failed, using hub:", err)
    end
end

if not ok then
    ok, err = run(FALLBACK)
    if not ok then
        env.NonDevLoaded = false -- allow a retry
        warn("[nondev] hub failed:", err)
    end
end
