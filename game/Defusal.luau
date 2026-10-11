local ALLOWED_ID = 79393329652220

local cref = cloneref or function(x) return x end
local Players = cref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer

if game.PlaceId ~= ALLOWED_ID and game.GameId ~= ALLOWED_ID then
    LocalPlayer:Kick("This script only works in the game it was made for.")
    return
end

local genv = (getgenv and getgenv()) or _G

if genv.__DefusalMenu then
    pcall(genv.__DefusalMenu)
    genv.__DefusalMenu = nil
end

local RunService = cref(game:GetService("RunService"))
local CoreGui = cref(game:GetService("CoreGui"))
local Workspace = cref(game:GetService("Workspace"))

local okLib, lib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/nonfq/Vape-UiLibrary/main/source.luau"))()
end)
if not okLib or not lib then
    warn("[Defusal Menu] Could not load the UI library: " .. tostring(lib))
    return
end

local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
if not hasDrawing then
    warn("[Defusal Menu] Drawing library not found: ESP boxes and health bars are unavailable. Chams still work.")
end

local Settings = {
    Enabled = false,
    Sticky = true,
    TeamCheck = true,
    WallCheck = true,
    LockHead = true,
    ShowFOV = true,
    FOVSize = "Medium",
    Boxes = false,
    Health = false,
    Chams = false,
    NoRec = false,
    NoSpread = false,
    InfAmo = false,
    RapidFire = false,
}

local FOV_SIZES = {Small = 80, Medium = 150, Large = 250}
local RELEASE_MULT = 1.6
local WALL_GRACE = 0.3
local DEFAULT_COLOR = Color3.fromRGB(255, 70, 70)
local LOCK_NAME = "DefusalMenuLock"

local alive = true
local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local gui = Instance.new("ScreenGui")
gui.Name = "DefusalMenuESP"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
local okParent = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not okParent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local fovCircle
if hasDrawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Visible = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
end

local TEAM_ATTRS = {"Team", "TeamName", "TeamId", "TeamID", "team", "Side", "Faction"}

local function attrOf(obj)
    if not obj then return nil end
    for _, name in ipairs(TEAM_ATTRS) do
        local v = obj:GetAttribute(name)
        if v ~= nil then return v end
    end
    return nil
end

local function valueOf(obj)
    if not obj then return nil end
    for _, name in ipairs(TEAM_ATTRS) do
        local c = obj:FindFirstChild(name)
        if c and c:IsA("ValueBase") then return c.Value end
    end
    return nil
end

local function statsOf(plr)
    local ls = plr:FindFirstChild("leaderstats")
    return valueOf(ls)
end

local function highlightOf(plr)
    local char = plr.Character
    local hl = char and char:FindFirstChildOfClass("Highlight")
    return hl and hl.FillColor or nil
end

local teamSources = {
    function(p) return p.Team end,
    function(p) if not p.Neutral then return p.TeamColor end end,
    function(p) return attrOf(p) end,
    function(p) return attrOf(p.Character) end,
    function(p) return valueOf(p) end,
    function(p) return valueOf(p.Character) end,
    statsOf,
    highlightOf,
}

local function isTeammate(plr)
    for _, source in ipairs(teamSources) do
        local okA, a = pcall(source, LocalPlayer)
        local okB, b = pcall(source, plr)
        if okA and okB and a ~= nil and b ~= nil then
            return a == b
        end
    end
    return false
end

local function getColor(plr)
    if plr.Team and plr.TeamColor then
        return plr.TeamColor.Color
    end
    return DEFAULT_COLOR
end

local function isVisible(part, char, camera)
    local ignore = {LocalPlayer.Character, camera}
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local origin = camera.CFrame.Position
    local direction = part.Position - origin
    for _ = 1, 6 do
        params.FilterDescendantsInstances = ignore
        local hit = Workspace:Raycast(origin, direction, params)
        if not hit then return true end
        local inst = hit.Instance
        if inst:IsDescendantOf(char) then return true end
        if inst.Transparency >= 0.95 or not inst.CanCollide then
            ignore[#ignore + 1] = inst
        else
            return false
        end
    end
    return false
end

local function getAimPart(char)
    if Settings.LockHead then
        return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
end

local currentTarget = nil
local lastSeen = 0

local function evaluate(plr, camera, point, radius, skipWall)
    if plr == LocalPlayer then return nil end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return nil end
    local part = getAimPart(char)
    if not part then return nil end
    if Settings.TeamCheck and isTeammate(plr) then return nil end
    local sp, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil end
    local dist = (Vector2.new(sp.X, sp.Y) - point).Magnitude
    if dist > radius then return nil end
    if Settings.WallCheck and not skipWall and not isVisible(part, char, camera) then return nil end
    return part, dist
end

local function getTarget(camera, point)
    local fov = FOV_SIZES[Settings.FOVSize]
    if Settings.Sticky and currentTarget then
        local part = evaluate(currentTarget, camera, point, fov * RELEASE_MULT, false)
        if part then
            lastSeen = os.clock()
            return part
        end
        if os.clock() - lastSeen < WALL_GRACE then
            local held = evaluate(currentTarget, camera, point, fov * RELEASE_MULT, true)
            if held then return held end
        end
        currentTarget = nil
    end
    local best, bestDist, bestPlr
    for _, plr in ipairs(Players:GetPlayers()) do
        local part, dist = evaluate(plr, camera, point, fov, false)
        if part and (not bestDist or dist < bestDist) then
            best, bestDist, bestPlr = part, dist, plr
        end
    end
    currentTarget = bestPlr
    if best then lastSeen = os.clock() end
    return best
end

local objects = {}

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function createObjects(plr)
    if objects[plr] then return end
    local o = {}
    if hasDrawing then
        o.BoxOutline = newDrawing("Square", {Thickness = 3, Filled = false, Visible = false, ZIndex = 1, Color = Color3.new(0, 0, 0)})
        o.Box = newDrawing("Square", {Thickness = 1, Filled = false, Visible = false, ZIndex = 2, Color = DEFAULT_COLOR})
        o.HealthBG = newDrawing("Line", {Thickness = 4, Visible = false, ZIndex = 1, Color = Color3.new(0, 0, 0)})
        o.HealthBar = newDrawing("Line", {Thickness = 2, Visible = false, ZIndex = 2, Color = Color3.fromRGB(0, 255, 0)})
    end
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled = false
    hl.Parent = gui
    o.Highlight = hl
    objects[plr] = o
end

local function hide(o)
    for key, obj in pairs(o) do
        if key == "Highlight" then
            obj.Enabled = false
            obj.Adornee = nil
        else
            obj.Visible = false
        end
    end
end

local function removeObjects(plr)
    local o = objects[plr]
    if not o then return end
    for key, obj in pairs(o) do
        if key == "Highlight" then
            obj:Destroy()
        else
            pcall(function() obj:Remove() end)
        end
    end
    objects[plr] = nil
end

local function readHealth(plr, char, hum)
    local h = char:GetAttribute("Health") or plr:GetAttribute("Health")
    local m = char:GetAttribute("MaxHealth") or plr:GetAttribute("MaxHealth")
    if type(h) == "number" then
        return h, type(m) == "number" and m or hum.MaxHealth
    end
    local hv = char:FindFirstChild("Health") or plr:FindFirstChild("Health")
    if hv and hv:IsA("ValueBase") and type(hv.Value) == "number" then
        local mv = char:FindFirstChild("MaxHealth") or plr:FindFirstChild("MaxHealth")
        local max = (mv and mv:IsA("ValueBase") and type(mv.Value) == "number") and mv.Value or hum.MaxHealth
        return hv.Value, max
    end
    return hum.Health, hum.MaxHealth
end

local function updateESP(camera)
    for plr, o in pairs(objects) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        local valid = hrp and head and hum and hum.Health > 0
        if valid and Settings.TeamCheck and isTeammate(plr) then
            valid = false
        end

        if not valid then
            hide(o)
        else
            local color = getColor(plr)

            if Settings.Chams then
                o.Highlight.Adornee = char
                o.Highlight.FillColor = color
                o.Highlight.OutlineColor = color
                o.Highlight.Enabled = true
            else
                o.Highlight.Enabled = false
            end

            if hasDrawing then
                local rootPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local top = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                    local bottom = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local height = math.abs(bottom.Y - top.Y)
                    local width = height / 1.6
                    local x = rootPos.X - width / 2
                    local y = top.Y

                    o.Box.Visible = Settings.Boxes
                    o.BoxOutline.Visible = Settings.Boxes
                    if Settings.Boxes then
                        o.Box.Size = Vector2.new(width, height)
                        o.Box.Position = Vector2.new(x, y)
                        o.Box.Color = color
                        o.BoxOutline.Size = o.Box.Size
                        o.BoxOutline.Position = o.Box.Position
                    end

                    o.HealthBG.Visible = Settings.Health
                    o.HealthBar.Visible = Settings.Health
                    if Settings.Health then
                        local hp, maxHp = readHealth(plr, char, hum)
                        local pct = math.clamp(hp / math.max(maxHp, 1), 0, 1)
                        local bx = x - 5
                        o.HealthBG.From = Vector2.new(bx, y + height + 1)
                        o.HealthBG.To = Vector2.new(bx, y - 1)
                        o.HealthBar.From = Vector2.new(bx, y + height)
                        o.HealthBar.To = Vector2.new(bx, y + height - height * pct)
                        o.HealthBar.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), pct)
                    end
                else
                    o.Box.Visible = false
                    o.BoxOutline.Visible = false
                    o.HealthBG.Visible = false
                    o.HealthBar.Visible = false
                end
            end
        end
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then createObjects(plr) end
end
connect(Players.PlayerAdded, function(plr)
    if plr ~= LocalPlayer then createObjects(plr) end
end)
connect(Players.PlayerRemoving, function(plr)
    if currentTarget == plr then currentTarget = nil end
    removeObjects(plr)
end)

connect(RunService.RenderStepped, function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    updateESP(camera)
    if fovCircle then
        fovCircle.Visible = Settings.Enabled and Settings.ShowFOV
        fovCircle.Position = camera.ViewportSize / 2
        fovCircle.Radius = FOV_SIZES[Settings.FOVSize]
    end
end)

RunService:BindToRenderStep(LOCK_NAME, Enum.RenderPriority.Last.Value, function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if not Settings.Enabled then
        currentTarget = nil
        return
    end
    local part = getTarget(camera, camera.ViewportSize / 2)
    if not part then return end
    camera.CFrame = CFrame.new(camera.CFrame.Position, part.Position)
end)

local NAME_KINDS = {}

local function addNames(kind, list)
    for _, n in ipairs(list) do
        NAME_KINDS[n] = kind
    end
end

addNames("ammo", {"ammo", "currentammo", "curammo", "clipammo", "magammo", "ammoinclip", "loadedammo", "ammocount", "bullets", "currentbullets"})
addNames("reserve", {"storedammo", "reserveammo", "totalammo", "ammostored", "ammoreserve", "reserve", "stored", "spareammo", "extraammo"})
addNames("capacity", {"maxammo", "clipsize", "magsize", "magazinesize", "maxclip", "maxmag", "magcapacity", "clipcapacity"})
addNames("rate", {"firerate", "fire_rate", "rpm", "firedelay", "shootdelay", "shootcooldown", "firecooldown", "rateoffire", "rof", "cooldown", "shotdelay", "bulletdelay", "timebetweenshots", "fireinterval"})

local KIND_WORDS = {
    {kind = "recoil", words = {"recoil", "kick", "sway"}},
    {kind = "spread", words = {"spread", "bloom", "inaccuracy", "deviation"}},
}

local HINT_NAMES = {Variables = true, Shucky = true, Ambassador = true}
local FAST_KEYS = {"Ammo", "StoredAmmo", "CurrentAmmo", "ReserveAmmo", "Recoil", "Spread", "FireRate", "Bloom", "Sway"}

local classCache = {}
local entries = {}
local entryOf = setmetatable({}, {__mode = "k"})
local frozenTables = {}
local gunTables = {}
local known = {}
local toolTargets = {}
local toolConns = {}
local scanning = false
local scanRequested = true
local scanAgain = false
local notifyNext = false
local lastScan = 0

local function classify(key)
    local c = classCache[key]
    if c ~= nil then
        if c then return c end
        return nil
    end
    local lk = string.lower(key)
    local kind = NAME_KINDS[lk]
    if not kind then
        for _, group in ipairs(KIND_WORDS) do
            for _, w in ipairs(group.words) do
                if lk:find(w, 1, true) then
                    kind = group.kind
                    break
                end
            end
            if kind then break end
        end
    end
    classCache[key] = kind or false
    return kind
end

local function kindEnabled(kind)
    if kind == "recoil" then return Settings.NoRec end
    if kind == "spread" then return Settings.NoSpread end
    if kind == "ammo" or kind == "reserve" then return Settings.InfAmo end
    if kind == "rate" then return Settings.RapidFire end
    return false
end

local function anyGunMod()
    return Settings.NoRec or Settings.NoSpread or Settings.InfAmo or Settings.RapidFire
end

local function unlock(t)
    if isreadonly and isreadonly(t) and setreadonly then
        pcall(setreadonly, t, false)
    end
end

local function usable(kind, v)
    local t = typeof(v)
    if kind == "recoil" or kind == "spread" then
        return t == "number" or t == "Vector3" or t == "Vector2" or t == "table"
    end
    return t == "number"
end

local function inspectTable(t, relaxed)
    local keys, cap, count = {}, nil, 0
    pcall(function()
        for k, v in next, t do
            if type(k) == "string" then
                local kind = classify(k)
                if kind then
                    if kind == "capacity" then
                        count = count + 1
                        if type(v) == "number" and (not cap or v > cap) then cap = v end
                    elseif usable(kind, v) then
                        count = count + 1
                        keys[#keys + 1] = k
                    end
                end
            end
        end
    end)
    if #keys >= 1 and count >= (relaxed and 1 or 2) then
        return {tbl = t, keys = keys, cap = cap}
    end
    return nil
end

local function rateTarget(lk, cur)
    if lk:find("delay", 1, true) or lk:find("cooldown", 1, true) or lk:find("interval", 1, true) or lk:find("between", 1, true) then
        return 0.02
    end
    if lk:find("rpm", 1, true) then return 3000 end
    if cur <= 1 then return 0.02 end
    return math.min(cur * 3, 3000)
end

local function targetFor(kind, key, current, cap)
    local t = typeof(current)
    if kind == "recoil" or kind == "spread" then
        if t == "number" then return 0 end
        if t == "Vector3" then return Vector3.zero end
        if t == "Vector2" then return Vector2.zero end
        return nil
    end
    if t ~= "number" then return nil end
    if kind == "ammo" then
        local v = math.max(current, cap or 0)
        if v < 1 then v = 30 end
        return v
    end
    if kind == "reserve" then return math.max(current, 999) end
    if kind == "rate" then return rateTarget(string.lower(key), current) end
    return nil
end

local function readValue(e)
    if e.mode == "table" then return rawget(e.container, e.key) end
    if e.mode == "value" then return e.container.Value end
    return e.container:GetAttribute(e.key)
end

local function writeValue(e, value)
    if e.mode == "table" then
        unlock(e.container)
        rawset(e.container, e.key, value)
    elseif e.mode == "value" then
        e.container.Value = value
    else
        e.container:SetAttribute(e.key, value)
    end
end

local function zeroNested(e)
    local nested = e.nested
    unlock(nested)
    for k, v in next, nested do
        if type(v) == "number" and v ~= 0 then
            if e.saved[k] == nil then e.saved[k] = v end
            rawset(nested, k, 0)
        end
    end
end

local function freezeKey(t, key, value)
    if type(setrawmetatable) ~= "function" or type(getrawmetatable) ~= "function" then
        return false
    end
    local info = frozenTables[t]
    if info then
        pcall(unlock, t)
        if not pcall(rawset, t, key, nil) then return false end
        info.vals[key] = value
        return true
    end
    return pcall(function()
        unlock(t)
        local oldmt = getrawmetatable(t)
        local oldIndex = oldmt and rawget(oldmt, "__index")
        local oldNewIndex = oldmt and rawget(oldmt, "__newindex")
        local vals = {[key] = value}
        local newmt = {}
        if oldmt then
            for k, v in next, oldmt do newmt[k] = v end
        end
        newmt.__index = function(self, k)
            local v = vals[k]
            if v ~= nil then return v end
            if type(oldIndex) == "function" then return oldIndex(self, k) end
            if oldIndex ~= nil then return oldIndex[k] end
            return nil
        end
        newmt.__newindex = function(self, k, v)
            if vals[k] ~= nil then return end
            if type(oldNewIndex) == "function" then
                oldNewIndex(self, k, v)
            elseif oldNewIndex ~= nil then
                oldNewIndex[k] = v
            else
                rawset(self, k, v)
            end
        end
        setrawmetatable(t, newmt)
        if not pcall(rawset, t, key, nil) then
            setrawmetatable(t, oldmt)
            error("rawset failed")
        end
        frozenTables[t] = {vals = vals, oldmt = oldmt}
    end)
end

local function unfreeze(e)
    local t = e.container
    local info = frozenTables[t]
    local restore = e.orig
    if e.kind == "ammo" or e.kind == "reserve" then restore = e.target end
    if info then
        info.vals[e.key] = nil
        pcall(unlock, t)
        pcall(rawset, t, e.key, restore)
        if next(info.vals) == nil then
            pcall(setrawmetatable, t, info.oldmt)
            frozenTables[t] = nil
        end
    else
        pcall(rawset, t, e.key, restore)
    end
end

local function releaseEntry(e)
    if e.nested then
        unlock(e.nested)
        for k, v in pairs(e.saved) do rawset(e.nested, k, v) end
    elseif e.frozen then
        unfreeze(e)
    elseif e.kind ~= "ammo" and e.kind ~= "reserve" then
        writeValue(e, e.orig)
    end
end

local function ensureEntry(container, key, current, mode, cap)
    local kind = classify(key)
    if not kind or kind == "capacity" or not kindEnabled(kind) then return end
    local map = entryOf[container]
    if map and map[key] then return end
    local e
    if type(current) == "table" then
        if (kind ~= "recoil" and kind ~= "spread") or mode ~= "table" then return end
        e = {kind = kind, container = container, key = key, mode = mode, nested = current, saved = {}}
    else
        local target = targetFor(kind, key, current, cap)
        if target == nil then return end
        e = {kind = kind, container = container, key = key, mode = mode, orig = current, target = target}
    end
    if not map then
        map = {}
        entryOf[container] = map
    end
    map[key] = e
    entries[#entries + 1] = e
    if e.nested then
        pcall(zeroNested, e)
    elseif mode == "table" and freezeKey(container, key, e.target) then
        e.frozen = true
    else
        pcall(writeValue, e, e.target)
    end
end

local function enforce(e)
    if e.nested then
        local cur = rawget(e.container, e.key)
        if type(cur) == "table" and cur ~= e.nested then
            e.nested = cur
            e.saved = {}
        end
        zeroNested(e)
        return
    end
    if e.frozen then
        if rawget(e.container, e.key) ~= nil then
            pcall(unlock, e.container)
            pcall(rawset, e.container, e.key, nil)
        end
        return
    end
    local cur = readValue(e)
    if cur ~= nil and cur ~= e.target then
        writeValue(e, e.target)
    end
end

local function restoreDisabled()
    local i = 1
    while i <= #entries do
        local e = entries[i]
        if kindEnabled(e.kind) then
            i = i + 1
        else
            pcall(releaseEntry, e)
            local map = entryOf[e.container]
            if map then map[e.key] = nil end
            entries[i] = entries[#entries]
            entries[#entries] = nil
        end
    end
end

local function register(e)
    if not e then return end
    if not known[e.tbl] then
        gunTables[#gunTables + 1] = e
    end
    known[e.tbl] = e
end

local function walkTables(root, relaxed, add, limit)
    local visited, stack, count = {}, {{root, 0}}, 0
    while #stack > 0 do
        local item = table.remove(stack)
        local t, depth = item[1], item[2]
        if not visited[t] then
            visited[t] = true
            count = count + 1
            if count > limit then break end
            add(inspectTable(t, relaxed))
            if depth < 3 then
                pcall(function()
                    for _, v in next, t do
                        if type(v) == "table" and not visited[v] then
                            stack[#stack + 1] = {v, depth + 1}
                        end
                    end
                end)
            end
        end
    end
end

local function hintRoots()
    local roots, seenInst = {}, {}
    local function take(inst)
        if seenInst[inst] or not inst:IsA("ModuleScript") then return end
        seenInst[inst] = true
        local ok, mod = pcall(require, inst)
        if ok and type(mod) == "table" then
            roots[#roots + 1] = {name = inst.Name, mod = mod}
        end
    end
    pcall(function()
        if type(getloadedmodules) == "function" then
            for _, inst in ipairs(getloadedmodules()) do
                if HINT_NAMES[inst.Name] then take(inst) end
            end
        end
    end)
    pcall(function()
        local places = {cref(game:GetService("ReplicatedStorage")), LocalPlayer:FindFirstChild("PlayerScripts")}
        for _, place in ipairs(places) do
            for name in pairs(HINT_NAMES) do
                local inst = place:FindFirstChild(name, true)
                if inst then take(inst) end
            end
        end
    end)
    return roots
end

local function hintScan()
    for _, r in ipairs(hintRoots()) do
        walkTables(r.mod, true, register, 3000)
    end
end

local function fastScan(add)
    if type(filtergc) ~= "function" then return end
    for _, k in ipairs(FAST_KEYS) do
        local ok, res = pcall(filtergc, "table", {Keys = {k}}, false)
        if ok and type(res) == "table" then
            for _, t in ipairs(res) do
                if type(t) == "table" then add(inspectTable(t, false)) end
            end
        end
    end
end

local function requestScan()
    scanRequested = true
end

local function runScan()
    if scanning then
        scanAgain = true
        return
    end
    scanning = true
    local seenNow = {}
    local function add(e)
        if not e or seenNow[e.tbl] then return end
        seenNow[e.tbl] = e
        register(e)
    end
    pcall(function()
        for _, r in ipairs(hintRoots()) do
            walkTables(r.mod, true, add, 3000)
        end
        fastScan(add)
        if type(getgc) == "function" then
            local okGc, objs = pcall(getgc, true)
            if okGc and type(objs) == "table" then
                local n = 0
                for _, obj in ipairs(objs) do
                    n = n + 1
                    if n % 3000 == 0 then task.wait() end
                    if type(obj) == "table" then add(inspectTable(obj, false)) end
                end
            end
        end
    end)
    local list, kn = {}, {}
    for t, e in pairs(seenNow) do
        list[#list + 1] = e
        kn[t] = e
    end
    gunTables, known = list, kn
    scanning = false
    if scanAgain then
        scanAgain = false
        scanRequested = true
    end
    if notifyNext then
        notifyNext = false
        pcall(function()
            lib:Notification("Gun Mods", string.format("Scan done: %d weapon tables found", #gunTables))
        end)
    end
end

local function trackable(name)
    local kind = classify(name)
    return kind ~= nil and kind ~= "capacity"
end

local function clearTool()
    for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
    table.clear(toolConns)
    table.clear(toolTargets)
end

local function applyTarget(container, key, mode, cap)
    local map = entryOf[container]
    local e = map and map[key]
    if e then
        enforce(e)
        return
    end
    local cur
    if mode == "table" then
        cur = rawget(container, key)
    elseif mode == "value" then
        cur = container.Value
    else
        cur = container:GetAttribute(key)
    end
    if cur ~= nil then ensureEntry(container, key, cur, mode, cap) end
end

local function trackInstance(inst)
    if (inst:IsA("IntValue") or inst:IsA("NumberValue")) and trackable(inst.Name) then
        toolTargets[#toolTargets + 1] = {inst = inst, key = inst.Name, mode = "value"}
        toolConns[#toolConns + 1] = inst:GetPropertyChangedSignal("Value"):Connect(function()
            if anyGunMod() then pcall(applyTarget, inst, inst.Name, "value") end
        end)
    end
    for name, val in pairs(inst:GetAttributes()) do
        if type(val) == "number" and trackable(name) then
            toolTargets[#toolTargets + 1] = {inst = inst, key = name, mode = "attr"}
            toolConns[#toolConns + 1] = inst:GetAttributeChangedSignal(name):Connect(function()
                if anyGunMod() then pcall(applyTarget, inst, name, "attr") end
            end)
        end
    end
end

local function refreshTool()
    clearTool()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    trackInstance(tool)
    for _, d in ipairs(tool:GetDescendants()) do trackInstance(d) end
    toolConns[#toolConns + 1] = tool.DescendantAdded:Connect(function(d)
        trackInstance(d)
    end)
end

local function applyAll()
    if not anyGunMod() then return end
    for _, tgt in ipairs(toolTargets) do
        if tgt.inst.Parent then applyTarget(tgt.inst, tgt.key, tgt.mode) end
    end
    for _, item in ipairs(gunTables) do
        for _, k in ipairs(item.keys) do
            applyTarget(item.tbl, k, "table", item.cap)
        end
    end
end

connect(RunService.Heartbeat, function() pcall(applyAll) end)
connect(RunService.RenderStepped, function() pcall(applyAll) end)

local function onCharacter(char)
    connect(char.ChildAdded, function(c)
        if c:IsA("Tool") then
            refreshTool()
            if anyGunMod() then
                pcall(hintScan)
                requestScan()
            end
        end
    end)
    connect(char.ChildRemoved, function(c)
        if c:IsA("Tool") then refreshTool() end
    end)
    refreshTool()
end

if LocalPlayer.Character then onCharacter(LocalPlayer.Character) end
connect(LocalPlayer.CharacterAdded, function(char)
    onCharacter(char)
    if anyGunMod() then requestScan() end
end)

task.spawn(function()
    while alive do
        pcall(restoreDisabled)
        if anyGunMod() and not scanning and (scanRequested or os.clock() - lastScan > 15) then
            scanRequested = false
            lastScan = os.clock()
            pcall(runScan)
        end
        task.wait(0.25)
    end
end)

local function onGunToggle(on)
    if on then
        notifyNext = true
        pcall(hintScan)
        requestScan()
    else
        pcall(restoreDisabled)
    end
end

local function dumpGunData()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("Defusal Menu gun data")
    add("PlaceId " .. tostring(game.PlaceId))
    for _, r in ipairs(hintRoots()) do
        add("module " .. r.name)
        local n = 0
        for k, v in next, r.mod do
            n = n + 1
            if n > 80 then
                add("  ...")
                break
            end
            local tv = typeof(v)
            local shown = ""
            if tv == "number" or tv == "boolean" or tv == "string" then shown = " = " .. tostring(v) end
            add("  " .. tostring(k) .. " : " .. tv .. shown)
        end
    end
    for i, item in ipairs(gunTables) do
        add(string.format("table %d cap=%s", i, tostring(item.cap)))
        local map = entryOf[item.tbl]
        for _, k in ipairs(item.keys) do
            local e = map and map[k]
            local shown
            if e and e.frozen then
                shown = "frozen " .. tostring(e.target) .. " (was " .. tostring(e.orig) .. ")"
            else
                shown = tostring(rawget(item.tbl, k))
            end
            add(string.format("  %s [%s] = %s", k, tostring(classify(k)), shown))
        end
    end
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        add("tool " .. tool:GetFullName())
        local n = 0
        for _, d in ipairs(tool:GetDescendants()) do
            n = n + 1
            if n > 60 then
                add("  ...")
                break
            end
            add("  " .. d.ClassName .. " " .. d.Name)
        end
    end
    return table.concat(lines, "\n")
end

local THEME = "Black"
local function accentFor(theme)
    return theme == "Light" and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
end

local win = lib:Window(
    "Defusal Menu",
    accentFor(THEME),
    Enum.KeyCode.RightControl,
    Vector2.new(480, 270),
    0.1,
    THEME
)

local aimTab = win:Tab("Aimbot", "crosshair")
aimTab:Section("Lock")
aimTab:Toggle("Aimbot", Settings.Enabled, function(t) Settings.Enabled = t end)
aimTab:Toggle("Sticky Lock", Settings.Sticky, function(t) Settings.Sticky = t end)
aimTab:Toggle("Lock Head (off = torso)", Settings.LockHead, function(t) Settings.LockHead = t end)
aimTab:Section("Checks")
aimTab:Toggle("Team Check", Settings.TeamCheck, function(t) Settings.TeamCheck = t end)
aimTab:Toggle("Wall Check", Settings.WallCheck, function(t) Settings.WallCheck = t end)
aimTab:Section("FOV")
aimTab:Toggle("Show FOV Circle", Settings.ShowFOV, function(t) Settings.ShowFOV = t end)
aimTab:Dropdown("FOV Size", {"Small", "Medium", "Large"}, function(t) Settings.FOVSize = t end)

local visTab = win:Tab("Visuals", "eye")
visTab:Section("ESP")
visTab:Toggle("Boxes", Settings.Boxes, function(t) Settings.Boxes = t end)
visTab:Toggle("Health Bars", Settings.Health, function(t) Settings.Health = t end)
visTab:Toggle("Chams", Settings.Chams, function(t) Settings.Chams = t end)
if not hasDrawing then
    visTab:Label("Boxes and health bars need the Drawing library")
end

local gunTab = win:Tab("Gun", "wrench")
gunTab:Section("Weapon")
gunTab:Toggle("No Recoil", Settings.NoRec, function(t)
    Settings.NoRec = t
    onGunToggle(t)
end)
gunTab:Toggle("No Spread", Settings.NoSpread, function(t)
    Settings.NoSpread = t
    onGunToggle(t)
end)
gunTab:Toggle("Infinite Ammo", Settings.InfAmo, function(t)
    Settings.InfAmo = t
    onGunToggle(t)
end)
gunTab:Toggle("Fire Rate", Settings.RapidFire, function(t)
    Settings.RapidFire = t
    onGunToggle(t)
end)
gunTab:Section("Debug")
gunTab:Button("Copy Gun Data", function()
    task.spawn(function()
        if #gunTables == 0 then pcall(runScan) end
        local t0 = os.clock()
        while scanning and os.clock() - t0 < 30 do task.wait(0.1) end
        local text = dumpGunData()
        local copied = false
        if type(setclipboard) == "function" then copied = pcall(setclipboard, text) end
        local saved = false
        if type(writefile) == "function" then saved = pcall(writefile, "DefusalMenu_gundata.txt", text) end
        if not copied and not saved then print(text) end
        local msg = "Printed to the console"
        if copied then
            msg = "Copied to clipboard"
        elseif saved then
            msg = "Saved to DefusalMenu_gundata.txt"
        end
        lib:Notification("Gun Data", msg)
    end)
end)

local setTab = win:Tab("Settings", "settings")
setTab:Section("Appearance")
local accentPicker = setTab:Colorpicker("UI Color", accentFor(THEME), function(c)
    lib:ChangePresetColor(Color3.fromRGB(c.R * 255, c.G * 255, c.B * 255))
end)
setTab:Dropdown("Theme", {"Dark", "Light", "Black"}, function(t)
    lib:SetTheme(t)
    accentPicker:Set(accentFor(t))
end)
setTab:Section("Danger Zone")

local function destroy()
    alive = false
    pcall(function() RunService:UnbindFromRenderStep(LOCK_NAME) end)
    Settings.NoRec, Settings.NoSpread, Settings.InfAmo, Settings.RapidFire = false, false, false, false
    pcall(restoreDisabled)
    clearTool()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    for plr in pairs(objects) do removeObjects(plr) end
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    pcall(function() gui:Destroy() end)
    pcall(function() lib:Destroy() end)
end

setTab:Button("Fully Close", function()
    genv.__DefusalMenu = nil
    destroy()
end)

genv.__DefusalMenu = destroy
lib:Notification("Defusal Menu", "Loaded. Press Right Ctrl to hide the menu.")
