if getgenv().ZA_Shutdown then
    pcall(getgenv().ZA_Shutdown)
end

getgenv().AutoFarmEnabled = false
getgenv().GroundDistance = 8
getgenv().BehindDistance = 9
getgenv().FireDelay = 0.05
getgenv().globalTarget = nil

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nonfq/Vape-UiLibrary/main/source.luau"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local THEME = "Dark"
local CONFIG_FILE = "ZombieAttackFarm_config.json"
local ENEMY_FOLDER = "enemies"
local BOSS_FOLDER = "BossFolder"
local ESP_HIGHLIGHT_MAX = 24
local LOG_MAX = 80

local alive = true
local conns = {}

local function keep(c)
    conns[#conns + 1] = c
    return c
end

local config = {
    AutoEquip = true,
    PreferredTool = "",
    AntiAFK = true,
    BossPriority = false,
    WaveAware = true,
    MultiTarget = true,
    MaxTargets = 3,
    SafeEnabled = false,
    SafeBelow = 30,
    SafeResume = 80,
    ESPDistance = true,
    PowerupName = "",
    BuyCalls = "",
    BuyDelay = 5,
    BuyBetweenWaves = true,
    AutoSave = true,
    MatchRate = true,
    RateScale = 100,
    AutoFireMethod = "Gun Remote",
    AutoFire = false,
    ESP = false,
    AutoBuy = false,
    AutoPowerups = false,
}

local persistedKeys = {
    "AutoEquip", "PreferredTool", "AntiAFK", "BossPriority", "WaveAware", "MultiTarget",
    "MaxTargets", "SafeEnabled", "SafeBelow", "SafeResume", "ESPDistance", "PowerupName",
    "BuyCalls", "BuyDelay", "BuyBetweenWaves", "AutoSave", "MatchRate", "RateScale", "AutoFireMethod",
}
local persistedGlobals = {"GroundDistance", "BehindDistance", "FireDelay"}

local function canUseFiles()
    return typeof(isfile) == "function" and typeof(readfile) == "function" and typeof(writefile) == "function"
end

local function saveConfig()
    if not canUseFiles() then
        return false
    end
    local data = {}
    for _, k in ipairs(persistedGlobals) do
        data[k] = getgenv()[k]
    end
    for _, k in ipairs(persistedKeys) do
        data[k] = config[k]
    end
    local ok = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    return ok
end

local function loadConfig()
    if not canUseFiles() or not isfile(CONFIG_FILE) then
        return false
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(data) ~= "table" then
        return false
    end
    for _, k in ipairs(persistedGlobals) do
        if type(data[k]) == "number" then
            getgenv()[k] = data[k]
        end
    end
    for _, k in ipairs(persistedKeys) do
        if data[k] ~= nil and type(data[k]) == type(config[k]) then
            config[k] = data[k]
        end
    end
    return true
end

loadConfig()

local function accentFor(theme)
    return theme == "Light" and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
end

local win = lib:Window(
    "Zombie Attack - Autofarm",
    accentFor(THEME),
    Enum.KeyCode.RightControl,
    Vector2.new(500, 330),
    0.1,
    THEME
)

local farmTab = win:Tab("Autofarm", "crosshair")
local itemsTab = win:Tab("Items", "package")
local statsTab = win:Tab("Stats", "activity")
local visualTab = win:Tab("Visuals", "eye")
local miscTab = win:Tab("Misc", "settings")
local settingsTab = win:Tab("Settings", "sliders-horizontal")

local function notify(title, text, duration)
    pcall(function()
        lib:Notification(title, text, duration or 4)
    end)
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function copyText(text)
    if typeof(setclipboard) == "function" then
        pcall(setclipboard, text)
        return true
    end
    return false
end

local function fmtNum(n)
    local neg = n < 0
    local s = tostring(math.floor(math.abs(n) + 0.5))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    s = s:gsub("^,", "")
    return (neg and "-" or "") .. s
end

local tracked = {}
local kills = 0
local shots = 0
local lastDamageAt = 0
local stall = {noTarget = 0, retreat = 0, noTool = 0, noGun = 0, silent = 0}
local credited = setmetatable({}, {__mode = "k"})
local lastFired = setmetatable({}, {__mode = "k"})

local function isAlive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChild("Humanoid")
    return hum ~= nil
        and hum.Health > 0
        and model:FindFirstChild("Head") ~= nil
        and model:FindFirstChild("HumanoidRootPart") ~= nil
end

local function credit(model)
    if credited[model] then
        return
    end
    local t = lastFired[model]
    if not t or os.clock() - t > 4 then
        return
    end
    credited[model] = true
    kills = kills + 1
end

local function untrack(model)
    local info = tracked[model]
    if not info then
        return
    end
    credit(model)
    for _, c in ipairs(info.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    tracked[model] = nil
end

local function track(model, isBoss)
    if tracked[model] then
        return
    end
    local info = {boss = isBoss, conns = {}}
    tracked[model] = info
    task.spawn(function()
        local hum = model:WaitForChild("Humanoid", 5)
        if not hum or tracked[model] ~= info then
            return
        end
        info.hp = hum.Health
        info.conns[#info.conns + 1] = hum.HealthChanged:Connect(function(h)
            if info.hp and h < info.hp then
                lastDamageAt = os.clock()
            end
            info.hp = h
            if h <= 0 then
                credit(model)
            end
        end)
        info.conns[#info.conns + 1] = hum.Died:Connect(function()
            credit(model)
        end)
    end)
end

local folderStates = {}

local function bindFolder(name, isBoss)
    local state = {name = name, folder = nil, conns = {}}
    local function attach(folder)
        for _, c in ipairs(state.conns) do
            pcall(function()
                c:Disconnect()
            end)
        end
        state.conns = {}
        state.folder = folder
        if not folder then
            return
        end
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") then
                track(m, isBoss)
            end
        end
        state.conns[#state.conns + 1] = folder.ChildAdded:Connect(function(m)
            if m:IsA("Model") then
                track(m, isBoss)
            end
        end)
        state.conns[#state.conns + 1] = folder.ChildRemoved:Connect(function(m)
            untrack(m)
        end)
    end
    state.attach = attach
    attach(Workspace:FindFirstChild(name))
    folderStates[#folderStates + 1] = state
end

bindFolder(BOSS_FOLDER, true)
bindFolder(ENEMY_FOLDER, false)

local function aliveCount()
    local n = 0
    for m in pairs(tracked) do
        if isAlive(m) then
            n = n + 1
        end
    end
    return n
end

local function nearest(fromPos)
    local best, bestD, bestBoss = nil, math.huge, false
    for m, info in pairs(tracked) do
        if isAlive(m) then
            local d = (fromPos - m.HumanoidRootPart.Position).Magnitude
            local better
            if not best then
                better = true
            elseif config.BossPriority and info.boss ~= bestBoss then
                better = info.boss
            else
                better = d < bestD
            end
            if better then
                best, bestD, bestBoss = m, d, info.boss
            end
        end
    end
    return best
end

local function rankedTargets(fromPos, skip)
    local list = {}
    for m, info in pairs(tracked) do
        if m ~= skip and isAlive(m) then
            list[#list + 1] = {m = m, d = (fromPos - m.HumanoidRootPart.Position).Magnitude, boss = info.boss}
        end
    end
    table.sort(list, function(a, b)
        if config.BossPriority and a.boss ~= b.boss then
            return a.boss
        end
        return a.d < b.d
    end)
    return list
end

local function normalizeName(s)
    return (tostring(s):lower():gsub("[^%w]", ""))
end

local RATE_LIST = {
    {"Pistol", 6}, {"Revolver", 4}, {"Uzi", 10}, {"Trench Shotgun", 2.5}, {"M1 Garand", 3},
    {"Type 100", 6}, {"M16", 8}, {"Sniper", 1.5}, {"Tactical Shotgun", 3}, {"Thompson", 12},
    {"Blaster", 3.5}, {"Machine Gun", 16}, {"Cobra", 1.5}, {"Fiery Cannon", 2.5}, {"Toxic", 10},
    {"Retribution Ray", 6}, {"Platinum Gun", 4}, {"Scope Rifle", 2.5}, {"Space Gun", 8}, {"Railgun", 1},
    {"Ghost", 10}, {"Alien Rifle", 7}, {"Ray Gun", 6}, {"Annihilator", 18.5}, {"Biohazard", 10},
    {"Venom", 1}, {"Golden Pistol", 6}, {"Rainbow Blaster", 15}, {"Hex Spitter", 8}, {"Beam Launcher", 1.5},
    {"Gatling Laser", 20}, {"Tri Laser", 3.5}, {"Techno Rifle", 3}, {"Minigun", 22},
}

local FIRE_RATES = {}
for _, e in ipairs(RATE_LIST) do
    FIRE_RATES[normalizeName(e[1])] = e[2]
end

local function rateFor(name)
    local key = normalizeName(name)
    local exact = FIRE_RATES[key]
    if exact then
        return exact
    end
    local found, bestLen = nil, 0
    for k, v in pairs(FIRE_RATES) do
        if key:find(k, 1, true) and #k > bestLen then
            found, bestLen = v, #k
        end
    end
    return found
end

local function shotDelay(tool)
    if config.MatchRate then
        local r = rateFor(tool.Name)
        if r then
            return (1 / r) / (config.RateScale / 100), true
        end
    end
    return getgenv().FireDelay, false
end

local function diagnostics()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local delay, matched = getgenv().FireDelay, false
    if tool then
        delay, matched = shotDelay(tool)
    end
    return table.concat({
        "Tool: " .. (tool and tool.Name or "none"),
        string.format("Shot delay: %d ms (%s)", math.floor(delay * 1000 + 0.5), matched and "matched to weapon rate" or "slider value"),
        "Multi-target: " .. tostring(config.MultiTarget) .. " x" .. config.MaxTargets,
        "Boss priority: " .. tostring(config.BossPriority) .. " | Wave aware: " .. tostring(config.WaveAware),
        string.format("Stall seconds - no target %.1f | retreat %.1f | no tool %.1f | no gun remote %.1f | shots ignored by server %.1f",
            stall.noTarget, stall.retreat, stall.noTool, stall.noGun, stall.silent),
        "Shots: " .. shots .. " | Kills: " .. kills,
    }, "\n")
end

local function dumpTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then
        return nil
    end
    local out = {"Tool: " .. tool.Name}
    for k, v in pairs(tool:GetAttributes()) do
        out[#out + 1] = "Attribute " .. tostring(k) .. " = " .. tostring(v)
    end
    for _, d in ipairs(tool:GetDescendants()) do
        local line = d.ClassName .. " " .. d:GetFullName()
        if d:IsA("ValueBase") then
            line = line .. " = " .. tostring(d.Value)
        end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

local function ensureTool()
    local char = player.Character
    if not char then
        return nil
    end
    local equipped = char:FindFirstChildOfClass("Tool")
    local want = config.PreferredTool
    if equipped and (want == "" or equipped.Name == want) then
        return equipped
    end
    if config.AutoEquip then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local bp = player:FindFirstChildOfClass("Backpack")
        if hum and bp then
            local cand
            if want ~= "" then
                cand = bp:FindFirstChild(want)
            end
            if not cand and not equipped then
                cand = bp:FindFirstChildOfClass("Tool")
            end
            if cand and cand:IsA("Tool") then
                hum:EquipTool(cand)
                return cand
            end
        end
    end
    return equipped
end

local function fireAt(gun, model, toolName)
    local head = model:FindFirstChild("Head")
    if not head then
        return
    end
    lastFired[model] = os.clock()
    shots = shots + 1
    gun:FireServer({
        ["Normal"] = Vector3.new(0, 0, 0),
        ["Direction"] = head.Position,
        ["Name"] = toolName,
        ["Hit"] = head,
        ["Origin"] = head.Position,
        ["Pos"] = head.Position
    })
end

local renderConn, heartConn
local retreating = false
local safePos = nil
local safeCustom = false
local forced = nil
local lastShot = 0
local runAccum = 0
local runStart = nil

local function elapsed()
    return runAccum + (runStart and (os.clock() - runStart) or 0)
end

local function zeroVel(char, root)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local torso = char:FindFirstChild("Torso")
    if torso then
        torso.AssemblyLinearVelocity = Vector3.zero
    end
end

local function farmStep()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then
        getgenv().globalTarget = nil
        return
    end

    if not safePos then
        safePos = root.Position + Vector3.new(0, 120, 0)
    end

    if config.SafeEnabled and hum.MaxHealth > 0 then
        local pct = hum.Health / hum.MaxHealth * 100
        local resume = math.max(config.SafeResume, config.SafeBelow + 5)
        if pct < config.SafeBelow then
            retreating = true
        elseif retreating and pct >= resume then
            retreating = false
        end
    elseif retreating then
        retreating = false
    end

    if retreating then
        getgenv().globalTarget = nil
        root.CFrame = CFrame.new(safePos)
        zeroVel(char, root)
        return
    end

    if forced then
        if os.clock() < forced.untilT then
            root.CFrame = forced.cf
            zeroVel(char, root)
            return
        end
        forced = nil
    end

    local target = nearest(root.Position)
    getgenv().globalTarget = target

    if not target then
        if config.WaveAware then
            root.CFrame = CFrame.new(safePos)
            zeroVel(char, root)
        end
        return
    end

    local cam = Workspace.CurrentCamera
    if cam then
        cam.CFrame = CFrame.new(cam.CFrame.Position, target.Head.Position)
    end
    root.CFrame = target.HumanoidRootPart.CFrame * CFrame.new(0, getgenv().GroundDistance, getgenv().BehindDistance)
    zeroVel(char, root)
end

local function fireStep(dt)
    if retreating then
        stall.retreat = stall.retreat + dt
        return
    end
    local target = getgenv().globalTarget
    if not isAlive(target) then
        stall.noTarget = stall.noTarget + dt
        return
    end
    local now = os.clock()
    if lastShot > 0 and now - lastShot < 0.5 and now - lastDamageAt > 1.5 then
        stall.silent = stall.silent + dt
    end
    local tool = ensureTool()
    if not tool then
        stall.noTool = stall.noTool + dt
        return
    end
    local gun = ReplicatedStorage:FindFirstChild("Gun")
    if not gun then
        stall.noGun = stall.noGun + dt
        return
    end
    local delay, matched = shotDelay(tool)
    if now - lastShot < delay then
        return
    end
    lastShot = now
    fireAt(gun, target, tool.Name)
    if config.MultiTarget and not matched and config.MaxTargets > 1 then
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local list = rankedTargets(root.Position, target)
            for i = 1, math.min(#list, config.MaxTargets - 1) do
                fireAt(gun, list[i].m, tool.Name)
            end
        end
    end
end

local function stopFarm()
    if runStart then
        runAccum = runAccum + (os.clock() - runStart)
        runStart = nil
    end
    getgenv().AutoFarmEnabled = false
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    if heartConn then
        heartConn:Disconnect()
        heartConn = nil
    end
    getgenv().globalTarget = nil
    retreating = false
    forced = nil
end

local function startFarm()
    stopFarm()
    if not safeCustom then
        safePos = nil
    end
    getgenv().AutoFarmEnabled = true
    runStart = os.clock()
    lastShot = 0
    lastDamageAt = os.clock()
    renderConn = RunService.RenderStepped:Connect(farmStep)
    heartConn = RunService.Heartbeat:Connect(fireStep)
end

local holding = false
local lastAuto = 0

local function manualShot(tool)
    if config.AutoFireMethod == "Tool Activate" then
        tool:Activate()
        return
    end
    local gun = ReplicatedStorage:FindFirstChild("Gun")
    local mouse = player:GetMouse()
    local hit = mouse.Target
    if not gun or not hit then
        return
    end
    local pos = mouse.Hit.Position
    shots = shots + 1
    gun:FireServer({
        ["Normal"] = Vector3.new(0, 0, 0),
        ["Direction"] = pos,
        ["Name"] = tool.Name,
        ["Hit"] = hit,
        ["Origin"] = pos,
        ["Pos"] = pos
    })
end

local function autoFireStep()
    if not config.AutoFire or not holding or getgenv().AutoFarmEnabled then
        return
    end
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then
        return
    end
    local now = os.clock()
    local delay = shotDelay(tool)
    if now - lastAuto < delay then
        return
    end
    lastAuto = now
    manualShot(tool)
end

local function isFireInput(input)
    local t = input.UserInputType
    return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

keep(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and isFireInput(input) then
        holding = true
    end
end))

keep(UserInputService.InputEnded:Connect(function(input)
    if isFireInput(input) then
        holding = false
    end
end))

keep(RunService.Heartbeat:Connect(autoFireStep))

local waveSource = nil
local cashValue = nil
local cashStart = 0
local cleared = 0
local idleNow = true

local function parseWave(text)
    local n = tostring(text):lower():match("^%s*wave%s*[:#]?%s*(%d+)")
    return n and tonumber(n) or nil
end

local function readWave()
    if waveSource and waveSource.Parent then
        local ok, v = pcall(function()
            if waveSource:IsA("TextLabel") or waveSource:IsA("TextButton") then
                return parseWave(waveSource.Text)
            end
            return tonumber(waveSource.Value)
        end)
        if ok and v then
            return v
        end
    end
    waveSource = nil
    return nil
end

local function scanWave()
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        for _, d in ipairs(gui:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and parseWave(d.Text) then
                waveSource = d
                return
            end
        end
    end
    local function isWaveValue(d)
        return (d:IsA("IntValue") or d:IsA("NumberValue")) and d.Name:lower():find("wave", 1, true) ~= nil
    end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if isWaveValue(d) then
            waveSource = d
            return
        end
    end
    for _, d in ipairs(Workspace:GetChildren()) do
        if isWaveValue(d) then
            waveSource = d
            return
        end
    end
end

local function findCash()
    local ls = player:FindFirstChild("leaderstats")
    if not ls then
        return nil
    end
    for _, v in ipairs(ls:GetChildren()) do
        local n = v.Name:lower()
        if (v:IsA("IntValue") or v:IsA("NumberValue"))
            and (n:find("cash", 1, true) or n:find("money", 1, true) or n:find("coin", 1, true)
                or n:find("point", 1, true) or n:find("gold", 1, true)) then
            return v
        end
    end
    return nil
end

local function statsText()
    local e = elapsed()
    local s = math.floor(e)
    local rate = e > 0 and kills / (e / 60) or 0
    local w = readWave()
    local cashText = "Cash: n/a"
    if cashValue and cashValue.Parent then
        local net = cashValue.Value - cashStart
        cashText = string.format("Cash: %s | Net: %s%s", fmtNum(cashValue.Value), net >= 0 and "+" or "", fmtNum(net))
    end
    return {
        wave = w and ("Wave: " .. w) or ("Waves cleared (est.): " .. cleared),
        alive = "Zombies alive: " .. aliveCount(),
        kills = "Kills: " .. kills,
        rate = string.format("Kills/min: %.1f", rate),
        shots = "Shots: " .. shots,
        stallA = string.format("Stalled (s): no target %.1f | no tool %.1f | no gun %.1f", stall.noTarget, stall.noTool, stall.noGun),
        stallB = string.format("Retreat %.1f s | Shots ignored by server %.1f s", stall.retreat, stall.silent),
        cash = cashText,
        time = string.format("Runtime: %02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60),
    }
end

local function powerupContainers()
    local list = {}
    if config.PowerupName ~= "" then
        local f = Workspace:FindFirstChild(config.PowerupName, true)
        if f then
            list[1] = f
        end
        return list
    end
    for _, c in ipairs(Workspace:GetChildren()) do
        local n = c.Name:lower()
        if n:find("powerup", 1, true) or n:find("power_up", 1, true) or n:find("pickup", 1, true) or n:find("drop", 1, true) then
            list[#list + 1] = c
        end
    end
    return list
end

local function touchParts(container)
    local parts = {}
    local function consider(p)
        if p:IsA("BasePart") and (p:FindFirstChild("TouchInterest") or p:FindFirstChildWhichIsA("TouchTransmitter")) then
            parts[#parts + 1] = p
        end
    end
    consider(container)
    for _, d in ipairs(container:GetDescendants()) do
        consider(d)
    end
    return parts
end

local function touch(root, part)
    if typeof(firetouchinterest) == "function" then
        pcall(firetouchinterest, root, part, 0)
        pcall(firetouchinterest, root, part, 1)
        return true
    end
    local cf = part.CFrame + Vector3.new(0, 2, 0)
    if renderConn then
        forced = {cf = cf, untilT = os.clock() + 0.3}
    else
        root.CFrame = cf
    end
    return false
end

local function collectPowerups(limit)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        return 0
    end
    local done = 0
    for _, container in ipairs(powerupContainers()) do
        for _, part in ipairs(touchParts(container)) do
            if done >= limit then
                return done
            end
            done = done + 1
            if not touch(root, part) then
                return done
            end
        end
    end
    return done
end

local logging = false
local logLines = {}
local lastCapture = nil

local function record(remote, method, packed)
    if not logging or typeof(remote) ~= "Instance" then
        return
    end
    local name = remote.Name
    if name == "Gun" then
        return
    end
    local shown, clean = {}, true
    for i = 1, packed.n do
        local v = packed[i]
        local t = typeof(v)
        if t == "string" or t == "number" or t == "boolean" then
            shown[#shown + 1] = tostring(v)
        else
            clean = false
            shown[#shown + 1] = "<" .. t .. ">"
        end
    end
    local line = name .. " (" .. method .. ") " .. table.concat(shown, ",")
    if logLines[#logLines] == line then
        return
    end
    logLines[#logLines + 1] = line
    if #logLines > LOG_MAX then
        table.remove(logLines, 1)
    end
    if clean then
        lastCapture = {name = name, args = table.concat(shown, ",")}
    end
end

getgenv().ZA_Record = function(remote, method, packed)
    pcall(record, remote, method, packed)
end

local function installHook()
    if getgenv().ZA_HookInstalled then
        return true
    end
    if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then
        return false
    end
    local old
    local wrap = typeof(newcclosure) == "function" and newcclosure or function(f)
        return f
    end
    old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local rec = getgenv().ZA_Record
            local ours = typeof(checkcaller) == "function" and checkcaller()
            if rec and not ours then
                rec(self, method, table.pack(...))
            end
        end
        if typeof(setnamecallmethod) == "function" then
            setnamecallmethod(method)
        end
        return old(self, ...)
    end))
    getgenv().ZA_HookInstalled = true
    return true
end

local function coerce(s)
    local n = tonumber(s)
    if n then
        return n
    end
    if s == "true" then
        return true
    end
    if s == "false" then
        return false
    end
    return (s:gsub("^[\"'](.*)[\"']$", "%1"))
end

local function parseCalls(raw)
    local calls = {}
    for entry in raw:gmatch("[^;]+") do
        local pieces = {}
        for piece in entry:gmatch("[^,]+") do
            pieces[#pieces + 1] = trim(piece)
        end
        local name = table.remove(pieces, 1)
        if name and name ~= "" then
            local args = {}
            for _, s in ipairs(pieces) do
                args[#args + 1] = coerce(s)
            end
            calls[#calls + 1] = {name = name, args = args}
        end
    end
    return calls
end

local function runBuyCalls()
    for _, call in ipairs(parseCalls(config.BuyCalls)) do
        local remote = ReplicatedStorage:FindFirstChild(call.name, true)
        if remote then
            pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(table.unpack(call.args))
                elseif remote:IsA("RemoteEvent") then
                    remote:FireServer(table.unpack(call.args))
                end
            end)
        end
    end
end

local function captureLast()
    if not lastCapture then
        notify("Capture", "Nothing logged yet. Turn on Remote Logger and buy something.", 5)
        return
    end
    local entry = lastCapture.name
    if lastCapture.args ~= "" then
        entry = entry .. "," .. lastCapture.args
    end
    if config.BuyCalls ~= "" then
        config.BuyCalls = config.BuyCalls .. ";" .. entry
    else
        config.BuyCalls = entry
    end
    copyText(config.BuyCalls)
    notify("Capture", "Added: " .. entry, 5)
end

local function dumpLayout()
    local out = {"[Workspace]"}
    for _, c in ipairs(Workspace:GetChildren()) do
        out[#out + 1] = c.ClassName .. " " .. c.Name
    end
    out[#out + 1] = "[ReplicatedStorage remotes]"
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            out[#out + 1] = d.ClassName .. " " .. d:GetFullName()
        end
    end
    return table.concat(out, "\n")
end

local espObjects = {}
local espSession = 0

local function destroyESP(o)
    if o.h then
        o.h:Destroy()
    end
    if o.g then
        o.g:Destroy()
    end
end

local function clearESP()
    for _, o in pairs(espObjects) do
        destroyESP(o)
    end
    table.clear(espObjects)
end

local function createESP(m, isBoss)
    local head = m:FindFirstChild("Head")
    if not head then
        return nil
    end
    local g = Instance.new("BillboardGui")
    g.Adornee = head
    g.AlwaysOnTop = true
    g.Size = UDim2.fromOffset(110, 14)
    g.StudsOffset = Vector3.new(0, 2.2, 0)
    g.Parent = head

    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size = UDim2.fromScale(1, 1)
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.Text = m.Name
    t.TextColor3 = isBoss and Color3.fromRGB(255, 190, 80) or Color3.fromRGB(255, 255, 255)
    t.TextStrokeTransparency = 0.5
    t.Parent = g

    return {g = g, label = t, boss = isBoss, h = nil}
end

local function setHighlight(o, m, on)
    if on and not o.h then
        local h = Instance.new("Highlight")
        h.Adornee = m
        h.FillColor = o.boss and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(255, 50, 50)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.5
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = m
        o.h = h
    elseif not on and o.h then
        o.h:Destroy()
        o.h = nil
    end
end

local function updateESP()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local list = {}
    for m, info in pairs(tracked) do
        if isAlive(m) then
            local d = root and (root.Position - m.HumanoidRootPart.Position).Magnitude or 0
            list[#list + 1] = {m = m, boss = info.boss, d = d}
        end
    end
    table.sort(list, function(a, b)
        return a.d < b.d
    end)
    local keepSet = {}
    for i, e in ipairs(list) do
        keepSet[e.m] = true
        local o = espObjects[e.m]
        if not o then
            o = createESP(e.m, e.boss)
            espObjects[e.m] = o
        end
        if o then
            if config.ESPDistance then
                o.label.Text = string.format("%s [%dm]", e.m.Name, math.floor(e.d + 0.5))
            else
                o.label.Text = e.m.Name
            end
            setHighlight(o, e.m, i <= ESP_HIGHLIGHT_MAX)
        end
    end
    for m, o in pairs(espObjects) do
        if not keepSet[m] then
            destroyESP(o)
            espObjects[m] = nil
        end
    end
end

local function rejoin()
    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)
    if not ok then
        pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
    end
end

local function serverHop()
    local ok, servers = pcall(function()
        local body = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        return HttpService:JSONDecode(body).data
    end)
    if ok and type(servers) == "table" then
        for _, s in ipairs(servers) do
            if s.id ~= game.JobId and s.playing < s.maxPlayers - 1 then
                local sent = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, player)
                end)
                if sent then
                    return
                end
            end
        end
    end
    pcall(function()
        TeleportService:Teleport(game.PlaceId, player)
    end)
end

local powerSession = 0
local buySession = 0

local function panic()
    stopFarm()
    config.AutoBuy = false
    buySession = buySession + 1
    config.AutoPowerups = false
    powerSession = powerSession + 1
    notify("Panic", "Farm, auto buy and powerups stopped.", 4)
end

local sWave = statsTab:Section("Wave: -")
local sAlive = statsTab:Section("Zombies alive: 0")
local sKills = statsTab:Section("Kills: 0")
local sRate = statsTab:Section("Kills/min: 0.0")
local sShots = statsTab:Section("Shots: 0")
local sCash = statsTab:Section("Cash: n/a")
local sTime = statsTab:Section("Runtime: 00:00:00")
local sStallA = statsTab:Section("Stalled (s): -")
local sStallB = statsTab:Section("Retreat 0.0 s | Shots ignored by server 0.0 s")

local function setStat(obj, text)
    pcall(function()
        if obj and obj.Set then
            obj:Set(text)
        elseif obj and obj.SetText then
            obj:SetText(text)
        end
    end)
end

local function refreshStats()
    local t = statsText()
    setStat(sWave, t.wave)
    setStat(sAlive, t.alive)
    setStat(sKills, t.kills)
    setStat(sRate, t.rate)
    setStat(sShots, t.shots)
    setStat(sCash, t.cash)
    setStat(sTime, t.time)
    setStat(sStallA, t.stallA)
    setStat(sStallB, t.stallB)
end

statsTab:Button("Show Stats", function()
    local t = statsText()
    notify("Stats", t.wave .. " | " .. t.kills .. " | " .. t.rate .. " | " .. t.cash .. " | " .. t.time, 7)
end)

statsTab:Button("Reset Stats", function()
    kills = 0
    shots = 0
    cleared = 0
    for k in pairs(stall) do
        stall[k] = 0
    end
    runAccum = 0
    if runStart then
        runStart = os.clock()
    end
    if cashValue and cashValue.Parent then
        cashStart = cashValue.Value
    end
    refreshStats()
end)

farmTab:Section("Lock & Kill")

farmTab:Toggle("AutoFarm Lock (Spam Kill)", false, function(state)
    if state then
        startFarm()
    else
        stopFarm()
    end
end)

farmTab:Toggle("Multi-Target Volley (no switch delay)", config.MultiTarget, function(state)
    config.MultiTarget = state
end)

farmTab:Slider("Max Targets Per Volley", 1, 8, math.clamp(config.MaxTargets, 1, 8), function(v)
    config.MaxTargets = v
end)

farmTab:Toggle("Boss Priority", config.BossPriority, function(state)
    config.BossPriority = state
end)

farmTab:Toggle("Auto Equip Tool", config.AutoEquip, function(state)
    config.AutoEquip = state
end)

farmTab:Textbox("Preferred Tool Name (blank = first)", true, function(t)
    config.PreferredTool = trim(t)
end)

farmTab:Section("Waves")

farmTab:Toggle("Wave Aware (hold safe spot when empty)", config.WaveAware, function(state)
    config.WaveAware = state
end)

farmTab:Section("Safe Spot")

farmTab:Toggle("Retreat On Low Health", config.SafeEnabled, function(state)
    config.SafeEnabled = state
    if not state then
        retreating = false
    end
end)

farmTab:Slider("Retreat Below (%)", 5, 90, math.clamp(config.SafeBelow, 5, 90), function(v)
    config.SafeBelow = v
end)

farmTab:Slider("Resume Above (%)", 20, 100, math.clamp(config.SafeResume, 20, 100), function(v)
    config.SafeResume = v
end)

farmTab:Button("Set Safe Spot Here", function()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        safePos = root.Position
        safeCustom = true
        notify("Safe Spot", "Position saved.", 3)
    end
end)

farmTab:Button("Reset Safe Spot", function()
    safePos = nil
    safeCustom = false
    notify("Safe Spot", "Reset. Uses the spot above where you start farming.", 4)
end)

farmTab:Section("Tuning")

farmTab:Slider("Height", 5, 20, math.clamp(getgenv().GroundDistance, 5, 20), function(v)
    getgenv().GroundDistance = v
end)

farmTab:Slider("Distance Behind Target", 0, 20, math.clamp(getgenv().BehindDistance, 0, 20), function(v)
    getgenv().BehindDistance = v
end)

farmTab:Slider("Fire Delay (ms)", 20, 200, math.clamp(math.floor(getgenv().FireDelay * 1000 + 0.5), 20, 200), function(v)
    getgenv().FireDelay = v / 1000
end)

farmTab:Section("Weapons")

farmTab:Toggle("Match Weapon Fire Rate", config.MatchRate, function(state)
    config.MatchRate = state
end)

farmTab:Slider("Fire Rate Scale (%)", 50, 200, math.clamp(config.RateScale, 50, 200), function(v)
    config.RateScale = v
end)

farmTab:Toggle("Auto Fire (hold click = every gun automatic)", false, function(state)
    config.AutoFire = state
    holding = false
end)

farmTab:Dropdown("Auto Fire Method", {"Gun Remote", "Tool Activate"}, function(t)
    config.AutoFireMethod = t
end)

farmTab:Button("Copy Diagnostics", function()
    notify("Diagnostics", copyText(diagnostics()) and "Copied to clipboard." or "No clipboard access.", 4)
end)

farmTab:Button("Copy Equipped Tool Info", function()
    local text = dumpTool()
    if not text then
        notify("Tool Info", "Equip a weapon first.", 3)
        return
    end
    notify("Tool Info", copyText(text) and "Copied to clipboard." or "No clipboard access.", 4)
end)

itemsTab:Section("Powerups")

itemsTab:Toggle("Auto Collect Powerups", false, function(state)
    config.AutoPowerups = state
    powerSession = powerSession + 1
    local current = powerSession
    if not state then
        return
    end
    task.spawn(function()
        while alive and config.AutoPowerups and powerSession == current do
            pcall(collectPowerups, 10)
            task.wait(0.6)
        end
    end)
end)

itemsTab:Textbox("Powerup Folder Name (blank = auto detect)", true, function(t)
    config.PowerupName = trim(t)
end)

itemsTab:Button("Collect Now", function()
    local n = collectPowerups(25)
    notify("Powerups", n > 0 and ("Touched " .. n .. " pickup(s).") or "No pickups found. Use Dump Layout to find the folder name.", 5)
end)

itemsTab:Section("Auto Buy / Upgrade")

itemsTab:Textbox("Buy Calls (Remote,arg,arg;Remote2,arg)", true, function(t)
    config.BuyCalls = trim(t)
end)

itemsTab:Slider("Buy Interval (s)", 1, 30, math.clamp(config.BuyDelay, 1, 30), function(v)
    config.BuyDelay = v
end)

itemsTab:Toggle("Buy Only Between Waves", config.BuyBetweenWaves, function(state)
    config.BuyBetweenWaves = state
end)

itemsTab:Toggle("Auto Buy", false, function(state)
    config.AutoBuy = state
    buySession = buySession + 1
    local current = buySession
    if not state then
        return
    end
    task.spawn(function()
        while alive and config.AutoBuy and buySession == current do
            if config.BuyCalls ~= "" and (not config.BuyBetweenWaves or idleNow) then
                runBuyCalls()
            end
            task.wait(config.BuyDelay)
        end
    end)
end)

itemsTab:Section("Discovery")

itemsTab:Toggle("Remote Logger (buy a gun, then Capture)", false, function(state)
    if state then
        if not installHook() then
            logging = false
            notify("Logger", "This executor lacks hookmetamethod.", 5)
            return
        end
        logging = true
    else
        logging = false
    end
end)

itemsTab:Button("Capture Last Logged Call -> Buy List", captureLast)

itemsTab:Button("Copy Remote Log", function()
    if #logLines == 0 then
        notify("Log", "Log is empty.", 3)
        return
    end
    notify("Log", copyText(table.concat(logLines, "\n")) and "Copied to clipboard." or "No clipboard access.", 3)
end)

itemsTab:Button("Clear Buy List", function()
    config.BuyCalls = ""
    notify("Buy List", "Cleared.", 3)
end)

itemsTab:Button("Dump Workspace + Remotes", function()
    local text = dumpLayout()
    notify("Layout", copyText(text) and "Copied to clipboard." or "No clipboard access.", 4)
end)

visualTab:Section("ESP")

visualTab:Toggle("Zombie ESP", false, function(state)
    config.ESP = state
    espSession = espSession + 1
    local current = espSession
    if not state then
        clearESP()
        return
    end
    task.spawn(function()
        while alive and config.ESP and espSession == current do
            pcall(updateESP)
            task.wait(0.4)
        end
    end)
end)

visualTab:Toggle("Show Distance", config.ESPDistance, function(state)
    config.ESPDistance = state
end)

miscTab:Section("Utility")

miscTab:Toggle("Anti AFK", config.AntiAFK, function(state)
    config.AntiAFK = state
end)

keep(player.Idled:Connect(function()
    if config.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))

miscTab:Bind("Panic Key (stop everything)", Enum.KeyCode.End, panic)

miscTab:Button("Rejoin Server", rejoin)
miscTab:Button("Server Hop", serverHop)

miscTab:Section("Scripts")
miscTab:Button("Infinite Yield", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end)
miscTab:Button("decompiler", function()
    loadstring(game:HttpGet("https://robloxscripts.com/raw/new-decompiler-lua-expert"))()
    lib:Notification("decompiler", "decompiler active", 3)
end)
miscTab:Button("Dex Recontinued", function()
    loadstring(game:HttpGet("https://github.com/Tesker-103/DexRecontinued/releases/latest/download/out.lua"))()
end)

miscTab:Section("Info")
miscTab:Label("created by: @nondevelopers")
miscTab:Label("Discord: nonfq")
miscTab:Label("Version: v3.1")

settingsTab:Section("Appearance")

local accentPicker = settingsTab:Colorpicker("Change UI Color", accentFor(THEME), function(t)
    lib:ChangePresetColor(Color3.fromRGB(t.R * 255, t.G * 255, t.B * 255))
end)

settingsTab:Dropdown("Theme", {"Dark", "Light", "Black"}, function(t)
    lib:SetTheme(t)
    accentPicker:Set(accentFor(t))
end)

settingsTab:Section("Config")

settingsTab:Toggle("Auto Save On Close", config.AutoSave, function(state)
    config.AutoSave = state
end)

settingsTab:Button("Save Config", function()
    if saveConfig() then
        notify("Config", "Saved.", 3)
    else
        notify("Config", "Save failed (no file access).", 4)
    end
end)

settingsTab:Button("Load Config", function()
    if loadConfig() then
        notify("Config", "Loaded. Sliders sync on next execute.", 4)
    else
        notify("Config", "No saved config found.", 4)
    end
end)

local function shutdown(save)
    if save and config.AutoSave then
        saveConfig()
    end
    alive = false
    stopFarm()
    config.ESP = false
    espSession = espSession + 1
    clearESP()
    config.AutoBuy = false
    buySession = buySession + 1
    config.AutoPowerups = false
    powerSession = powerSession + 1
    logging = false
    getgenv().ZA_Record = nil
    for _, state in ipairs(folderStates) do
        for _, c in ipairs(state.conns) do
            pcall(function()
                c:Disconnect()
            end)
        end
    end
    for m in pairs(tracked) do
        untrack(m)
    end
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    pcall(function()
        lib:Destroy()
    end)
    getgenv().ZA_Shutdown = nil
end

getgenv().ZA_Shutdown = function()
    shutdown(false)
end

settingsTab:Section("Danger Zone")

settingsTab:Button("Fully Close", function()
    shutdown(true)
end)

task.spawn(function()
    local emptyFor, had, tick = 0, false, 0
    while alive do
        for _, state in ipairs(folderStates) do
            local f = Workspace:FindFirstChild(state.name)
            if f ~= state.folder then
                state.attach(f)
            end
        end
        for m in pairs(tracked) do
            if not m:IsDescendantOf(Workspace) then
                untrack(m)
            end
        end

        local n = aliveCount()
        idleNow = n == 0
        if n == 0 then
            emptyFor = emptyFor + 1
        else
            if had and emptyFor >= 3 then
                cleared = cleared + 1
            end
            emptyFor = 0
            had = true
        end

        if not cashValue or not cashValue.Parent then
            cashValue = findCash()
            if cashValue then
                cashStart = cashValue.Value
            end
        end

        tick = tick + 1
        if not readWave() and tick % 5 == 1 then
            pcall(scanWave)
        end

        refreshStats()
        task.wait(1)
    end
end)

notify("Zombie Attack", "Loaded.", 3)
