if not game:IsLoaded() then game.Loaded:Wait() end

local BASE = "https://raw.githubusercontent.com/nonfq/nonfqhub/main/"
local FALLBACK = "hub.luau"

local SUPPORTED = {
    [79393329652220] = "games/Defusal.luau",
    [1240123653] = "games/ZombieAttack.luau", -- Easy Mode
    [504035427] = "games/ZombieAttack.luau", -- Hard mode
}

local env = (getgenv and getgenv()) or _G
if env.NonDevLoaded then return end
env.NonDevLoaded = false

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer

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
if not target then
    local ok, err = run(FALLBACK)
    if not ok then
        env.NonDevLoaded = false -- allow a retry
        warn("[nonfqhub] hub failed:", err)
    end
    return
end

local function grey(v) return Color3.fromRGB(v, v, v) end
local C = {
    bg = grey(30),
    btn = grey(34),
    btnHover = grey(37),
    btnPress = grey(44),
    title = grey(68),
    text = grey(255),
    sub = grey(150),
    bar = grey(58),
    accent = Color3.fromRGB(44, 120, 224),
    danger = Color3.fromRGB(190, 60, 60),
    bad = Color3.fromRGB(224, 92, 92),
    good = Color3.fromRGB(88, 190, 120),
}

local function tween(inst, t, props, style)
    local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function create(class, props)
    local inst = Instance.new(class)
    local parent = props.Parent
    props.Parent = nil
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function corner(parent, r)
    return create("UICorner", {CornerRadius = UDim.new(0, r), Parent = parent})
end

local function mount(gui)
    local candidates = {}
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and h then candidates[#candidates + 1] = h end
    end
    candidates[#candidates + 1] = game:GetService("CoreGui")
    candidates[#candidates + 1] = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    for _, parent in ipairs(candidates) do
        local ok = pcall(function() gui.Parent = parent end)
        if ok and gui.Parent == parent then return parent end
    end
    return nil
end

local WIN_W, WIN_H = 340, 212
local FullSize = UDim2.new(0, WIN_W, 0, WIN_H)

local gui = Instance.new("ScreenGui")
gui.Name = "NonfqLoader"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

local container = mount(gui)
if not container then
    env.NonDevLoaded = true
    local ok, err = run(FALLBACK)
    if not ok then
        env.NonDevLoaded = false
        warn("[nonfqhub] no GUI container & hub failed:", err)
    end
    return
end

for _, old in ipairs(container:GetChildren()) do
    if old ~= gui and old.Name == "NonfqLoader" then old:Destroy() end
end

local connections = {}
local function track(c) connections[#connections + 1] = c return c end

local Main = create("Frame", {
    Name = "Main",
    Parent = gui,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corner(Main, 9)

local cam = workspace.CurrentCamera
if cam then
    local scale = math.clamp((cam.ViewportSize.X - 24) / WIN_W, 0.6, 1)
    if scale < 1 then create("UIScale", {Scale = scale, Parent = Main}) end
end

create("TextLabel", {
    Name = "Title",
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 19, 0, 9),
    Size = UDim2.new(0, 200, 0, 23),
    Font = Enum.Font.GothamSemibold,
    Text = "nonfqhub",
    TextColor3 = C.title,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local DragFrame = create("Frame", {
    Name = "DragFrame",
    Parent = Main,
    BackgroundTransparency = 1,
    Size = UDim2.new(0, WIN_W, 0, 41),
})

local InfoLabel = create("TextLabel", {
    Name = "Info",
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 19, 0, 46),
    Size = UDim2.new(0, WIN_W - 38, 0, 16),
    Font = Enum.Font.Gotham,
    Text = "Supported game detected",
    TextColor3 = C.sub,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})

local StatusLabel = create("TextLabel", {
    Name = "Status",
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 19, 0, 184),
    Size = UDim2.new(0, WIN_W - 38, 0, 16),
    Font = Enum.Font.Gotham,
    Text = "Pick how you want to load.",
    TextColor3 = C.sub,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})

local closed, busy = false, false
local choices = {}

local function setStatus(text, color)
    if closed then return end
    StatusLabel.Text = text
    tween(StatusLabel, 0.2, {TextColor3 = color or C.sub})
end

local function setBusy(state)
    busy = state
    for _, btn in ipairs(choices) do
        tween(btn, 0.2, {BackgroundTransparency = state and 0.45 or 0})
    end
end

local function close(success)
    if closed then return end
    closed = true
    if not success then env.NonDevLoaded = false end -- allow re-execute after dismissing
    for _, c in ipairs(connections) do c:Disconnect() end
    tween(Main, 0.4, {BackgroundTransparency = 1})
    local tw = tween(Main, 0.45, {Size = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Quart)
    tw.Completed:Connect(function() gui:Destroy() end)
    task.delay(1, function() if gui.Parent then gui:Destroy() end end)
end

local function launch(path, label)
    if busy or closed then return end
    setBusy(true)
    setStatus("Loading " .. label .. "...", C.sub)
    task.spawn(function()
        local ok, err = run(path)
        if ok then
            setStatus("Loaded " .. label .. ".", C.good)
            task.wait(0.25)
            close(true)
        else
            warn("[nonfqhub] " .. label .. " failed:", err)
            if closed then return end
            setBusy(false)
            local msg = tostring(err):gsub("%s+", " "):sub(1, 70)
            setStatus("Failed: " .. msg, C.bad)
        end
    end)
end

local function makeChoice(y, title, desc, barColor, onClick)
    local btn = create("TextButton", {
        Name = title,
        Parent = Main,
        Position = UDim2.new(0, 19, 0, y),
        Size = UDim2.new(0, WIN_W - 38, 0, 50),
        BackgroundColor3 = C.btn,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        ClipsDescendants = true,
        Text = "",
    })
    corner(btn, 7)

    local bar = create("Frame", {
        Name = "Bar",
        Parent = btn,
        Position = UDim2.new(0, 10, 0.5, -14),
        Size = UDim2.new(0, 3, 0, 28),
        BackgroundColor3 = barColor,
        BorderSizePixel = 0,
    })
    corner(bar, 2)

    create("TextLabel", {
        Name = "BtnTitle",
        Parent = btn,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 26, 0, 7),
        Size = UDim2.new(1, -36, 0, 18),
        Font = Enum.Font.Gotham,
        Text = title,
        TextColor3 = C.text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    create("TextLabel", {
        Name = "BtnDesc",
        Parent = btn,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 26, 0, 26),
        Size = UDim2.new(1, -36, 0, 16),
        Font = Enum.Font.Gotham,
        Text = desc,
        TextColor3 = C.sub,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    btn.MouseEnter:Connect(function()
        if not busy then tween(btn, 0.3, {BackgroundColor3 = C.btnHover}) end
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.2, {BackgroundColor3 = C.btn})
    end)
    btn.InputBegan:Connect(function(input)
        if busy then return end
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            tween(btn, 0.1, {BackgroundColor3 = C.btnPress})
        end
    end)
    btn.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            tween(btn, 0.2, {BackgroundColor3 = C.btn})
        end
    end)
    btn.MouseButton1Click:Connect(onClick)

    choices[#choices + 1] = btn
    return btn
end

makeChoice(70, "Supported", "Game-specific script for this game", C.accent, function()
    launch(target, "Supported")
end)
makeChoice(126, "nonfqhub", "Main hub script (universal)", C.bar, function()
    launch(FALLBACK, "nonfqhub")
end)

local CloseBtn = create("TextButton", {
    Name = "CloseBtn",
    Parent = Main,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 9),
    Size = UDim2.new(0, 23, 0, 23),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 5,
})
corner(CloseBtn, 6)
create("TextLabel", {
    Parent = CloseBtn,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Font = Enum.Font.GothamBold,
    Text = "X",
    TextColor3 = grey(210),
    TextSize = 14,
    ZIndex = 5,
})
CloseBtn.MouseEnter:Connect(function() tween(CloseBtn, 0.2, {BackgroundColor3 = C.danger}) end)
CloseBtn.MouseLeave:Connect(function() tween(CloseBtn, 0.2, {BackgroundColor3 = C.bg}) end)
CloseBtn.MouseButton1Click:Connect(function()
    if not busy then close(false) end
end)

do
    local dragging, dragInput, dragStart, startPos
    DragFrame.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    DragFrame.InputChanged:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local d = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

tween(Main, 0.6, {BackgroundTransparency = 0})
tween(Main, 0.6, {Size = FullSize}, Enum.EasingStyle.Quart)

task.spawn(function()
    local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
    if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" and not closed then
        InfoLabel.Text = info.Name .. " is supported"
    end
end)
