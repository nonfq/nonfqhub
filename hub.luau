--[[
nondevelopers hub
made by: @nonfq | on discord
]]--
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false)
--freecam
local freecamActive = false
local freecamConnection = nil
local camera = workspace.CurrentCamera
local originalCameraType = camera.CameraType
local UIS = game:GetService("UserInputService")
local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
--autorespawn
local lastCFrame = nil
local respawnConnection = nil
local trackConnection = nil
local removeConnection = nil
--ank
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if self == game and method == "Kick" then
        return
    end
    return oldNamecall(self, ...)
end)
--antifling
local antiFlingConnection = nil

--[[

MAIN BUILD

]]--
local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nonfq/Vape-UiLibrary/main/source.luau"))()

-- accent color: white, or black when the theme is Light
local THEME = "Light" -- "Dark", "Light" or "Black"
local function accentFor(theme)
    return theme == "Light" and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
end

-- lib:Window(title, accentColor, closeKeybind, size, transparency, theme)
local win = lib:Window(
    "nonfqhub.luau",
    accentFor(THEME),
    Enum.KeyCode.RightControl,
    Vector2.new(500, 360), -- window size
    0.14,                   -- window transparency (elements follow automatically)
    THEME                  -- starting theme
)
--tabs (second argument is a Lucide icon name)
local updatelog = win:Tab("Update-Log", "history")
local devscript = win:Tab("deving", "code")
local workspacetools = win:Tab("workspace", "box")
local protection = win:Tab("protection", "shield")
local settings = win:Tab("Settings", "settings")
--[[

COMPONENTS

]]--
--updatelog
updatelog:Paragraph(
    "v1.0.0 [BETA]",
    "everything will be 100% vibecoded.\nthis is just a developer scripthub.\nAlso credits to every script developer."
)
updatelog:Label("autorespawn won't work in most games.")

--devscript
-- Button(text, callback, hasSettings, icon)
devscript:Button("Dex Recontinued", function()
    loadstring(game:HttpGet("https://github.com/Tesker-103/DexRecontinued/releases/latest/download/out.lua"))()
end, false, "folder-tree")
devscript:Button("VEX Explorer", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Vezise/2026/main/Vez/VexExplorer/VEXExplorer.lua"))()
end, false, "compass")
devscript:Section("Use decompiler first.")
devscript:Button("decompiler", function()
    loadstring(game:HttpGet("https://robloxscripts.com/raw/new-decompiler-lua-expert"))()
    lib:Notification("decompiler", "decompiler active", 3)
end, false, "file-code")
devscript:Button("game structure dumper", function()
    loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-game-structure-dumper-204708"))()
end, false, "download")
devscript:Button("Cobalt", function()
    loadstring(game:HttpGet("https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau"))()
end, false, "radio")
devscript:Button("Sspy", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/SimpleSpyV3/main.lua"))()
end, false, "eye")

--workspacetools
workspacetools:Button("Print All Remotes", function()
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") or v:IsA("BindableEvent") then
            print(v:GetFullName())
        end
    end
    print("--- done ---")
    lib:Notification("Remotes", "printed to the console", 3)
end, false, "list")
-- Toggle(text, default, callback, icon)
workspacetools:Toggle("Freecam", false, function(enabled)
    if isMobile then
        lib:Notification("Freecam", "not supported on mobile", 3)
        return
    end

    freecamActive = enabled

    if enabled then
        camera.CameraType = Enum.CameraType.Scriptable
        local speed = 50

        freecamConnection = RunService.RenderStepped:Connect(function(dt)
            local cf = camera.CFrame
            local newPos = cf.Position

            if UIS:IsKeyDown(Enum.KeyCode.W) then newPos += cf.LookVector * speed * dt end
            if UIS:IsKeyDown(Enum.KeyCode.S) then newPos -= cf.LookVector * speed * dt end
            if UIS:IsKeyDown(Enum.KeyCode.A) then newPos -= cf.RightVector * speed * dt end
            if UIS:IsKeyDown(Enum.KeyCode.D) then newPos += cf.RightVector * speed * dt end
            if UIS:IsKeyDown(Enum.KeyCode.E) then newPos += Vector3.new(0, 1, 0) * speed * dt end
            if UIS:IsKeyDown(Enum.KeyCode.Q) then newPos -= Vector3.new(0, 1, 0) * speed * dt end

            camera.CFrame = CFrame.new(newPos, newPos + cf.LookVector)
        end)
    else
        if freecamConnection then
            freecamConnection:Disconnect()
            freecamConnection = nil
        end
        camera.CameraType = originalCameraType
    end
end, "video")
workspacetools:Button("Custom Output", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/nondevelopers/nondev-scripts/main/custom_output.luau"))()
end, false, "terminal")

workspacetools:Section("Use custom output")
workspacetools:Button("Grab Coordinates", function()
    local cam = workspace.CurrentCamera
    if cam then
        local pos = cam.CFrame.Position
        print(string.format("Vector3.new(%.4f, %.4f, %.4f)", pos.X, pos.Y, pos.Z))
    end
end, false, "map-pin")
workspacetools:Textbox("Teleport to Coords [Testing coords]", true, function(input)
    local x, y, z = input:match("([%-%.%d]+)[,%s]+([%-%.%d]+)[,%s]+([%-%.%d]+)")
    if x and y and z then
        local char = game.Players.LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = CFrame.new(Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
        else
            lib:Notification("Teleport", "no character found", 3)
        end
    else
        lib:Notification("Teleport", "invalid input, use: x, y, z or Vector3.new(x, y, z)", 4)
    end
end)
workspacetools:Section("-")

--protection
protection:Toggle("Anti-Fling", false, function(enabled)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if enabled then
        hrp.CanCollide = false
        antiFlingConnection = RunService.Heartbeat:Connect(function()
            char = LocalPlayer.Character
            if not char then return end
            hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            if hrp.AssemblyLinearVelocity.Magnitude > 100 then
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        end)
    else
        hrp.CanCollide = true
        if antiFlingConnection then
            antiFlingConnection:Disconnect()
            antiFlingConnection = nil
        end
    end
end, "shield")
protection:Toggle("Auto Respawn", false, function(enabled)
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    if enabled then
        respawnConnection = LocalPlayer.CharacterAdded:Connect(function(char)
            local hrp = char:WaitForChild("HumanoidRootPart")

            if lastCFrame then
                task.wait(0.5)
                hrp.CFrame = lastCFrame
            end

            trackConnection = game:GetService("RunService").Heartbeat:Connect(function()
                if hrp and hrp.Parent then
                    lastCFrame = hrp.CFrame
                end
            end)
        end)

        removeConnection = LocalPlayer.CharacterRemoving:Connect(function(char)
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                lastCFrame = hrp.CFrame
            end
            if trackConnection then
                trackConnection:Disconnect()
                trackConnection = nil
            end
        end)
    else
        lastCFrame = nil
        if respawnConnection then respawnConnection:Disconnect() respawnConnection = nil end
        if trackConnection then trackConnection:Disconnect() trackConnection = nil end
        if removeConnection then removeConnection:Disconnect() removeConnection = nil end
    end
end, "refresh-cw")

--settings
settings:Section("Appearance")
-- changes the accent color live
local accentPicker = settings:Colorpicker("Change UI Color", accentFor(THEME), function(t)
    lib:ChangePresetColor(Color3.fromRGB(t.R * 255, t.G * 255, t.B * 255))
end)
-- lib:SetTheme("Dark" | "Light" | "Black"), accent follows the theme
settings:Dropdown("Theme", {"Dark", "Light", "Black"}, function(t)
    lib:SetTheme(t)
    accentPicker:Set(accentFor(t))
end)
settings:Section("Danger Zone")
settings:Button("Fully Close", function()
    lib:Destroy()
end, false, "log-out")
