-- QUASOSEAL MENU v2.5 (OPTIMIZADO - Auto Pesca mejorada)
local player = game.Players.LocalPlayer
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local VIM = game:GetService("VirtualInputManager")

local flyActive, staminaActive, espActive = false, false, false
local autoFishActive, speedActive = false, false
local esperandoReset = false
local forzarResetSpot = false
local flySpeed = 50
local bodyVel, bodyGyro
local staminaConexiones, espConexiones, highlights = {}, {}, {}
local terminalSg, fishThread = nil, nil
local COLOR_ACTIVA = Color3.fromRGB(124, 58, 237)

local colorTargets = {}
local function registrarColor(obj, prop)
    table.insert(colorTargets, {obj, prop})
    obj[prop] = COLOR_ACTIVA
end
local function aplicarColor(c)
    COLOR_ACTIVA = c
    for _, t in pairs(colorTargets) do
        pcall(function() t[1][t[2]] = c end)
    end
end

-- ============================================================
-- VIM HELPERS
-- ============================================================
local function getCenter()
    local vs = workspace.CurrentCamera.ViewportSize
    return vs.X / 2, vs.Y / 2
end

local function refClick()
    local vs = workspace.CurrentCamera.ViewportSize
    local x, y = vs.X / 2, vs.Y / 2
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true,  game, 0) end)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
end

local function vimPress()
    local x, y = getCenter()
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
end

local function vimRelease()
    local x, y = getCenter()
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
end

-- ============================================================
-- STAMINA
-- ============================================================
local function buscarStamina()
    local function engancharlo(v)
        v.Value = 100
        local c = v.Changed:Connect(function()
            if staminaActive then v.Value = 100 end
        end)
        table.insert(staminaConexiones, c)
    end
    pcall(function()
        local char = workspace:FindFirstChild(player.Name)
        local stamina = char and char:FindFirstChild("Vars") and
            char.Vars:FindFirstChild("Swimming") and
            char.Vars.Swimming:FindFirstChild("SwimStamina")
        if stamina then engancharlo(stamina) return end
    end)
    for _, v in pairs(game:GetDescendants()) do
        if v.Name == "SwimStamina" then engancharlo(v) return end
    end
end

local function desconectarStamina()
    for _, c in pairs(staminaConexiones) do c:Disconnect() end
    staminaConexiones = {}
end

-- ============================================================
-- ESP
-- ============================================================
local function aplicarHL(target)
    if target == player then return end
    local char = target.Character
    if not char or highlights[target.Name] then return end
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(0, 255, 80)
    hl.OutlineColor = Color3.fromRGB(0, 200, 60)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char
    highlights[target.Name] = hl
end

local function quitarHL(target)
    if highlights[target.Name] then highlights[target.Name]:Destroy() highlights[target.Name] = nil end
end

local function activarEsp()
    for _, p in pairs(game.Players:GetPlayers()) do aplicarHL(p) end
    table.insert(espConexiones, game.Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function() task.wait(1) if espActive then aplicarHL(p) end end)
    end))
    table.insert(espConexiones, game.Players.PlayerRemoving:Connect(quitarHL))
    table.insert(espConexiones, RS.Heartbeat:Connect(function()
        for _, p in pairs(game.Players:GetPlayers()) do
            if p ~= player and p.Character and not highlights[p.Name] then aplicarHL(p) end
        end
    end))
end

local function desactivarEsp()
    for _, c in pairs(espConexiones) do c:Disconnect() end
    espConexiones = {}
    for name, hl in pairs(highlights) do if hl then hl:Destroy() end highlights[name] = nil end
end

-- ============================================================
-- FLY
-- ============================================================
local function iniciarFly()
    local char = player.Character if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true
    bodyVel = Instance.new("BodyVelocity", hrp)
    bodyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bodyGyro = Instance.new("BodyGyro", hrp)
    bodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bodyGyro.P = 9e4
end

local function detenerFly()
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
    if bodyVel then bodyVel:Destroy() bodyVel = nil end
    if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
end

player.CharacterAdded:Connect(function()
    if flyActive then task.wait(0.5) iniciarFly() end
    if speedActive then
        task.wait(0.5)
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 32 end
    end
end)

RS.Heartbeat:Connect(function()
    if speedActive and player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed ~= 32 then hum.WalkSpeed = 32 end
    end
end)

-- ============================================================
-- AUTO PESCA - HELPERS
-- ============================================================
local function getNumFish()
    local vars = player:FindFirstChild("PlayerInfo")
        and player.PlayerInfo:FindFirstChild("Vars")
    if not vars then return 0, 20 end
    local numFish = vars:FindFirstChild("NumFish")
    local fishSlots = vars:FindFirstChild("FishSlots")
    return numFish and numFish.Value or 0, fishSlots and fishSlots.Value or 20
end

local function venderPeces()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local posOriginal = hrp.CFrame
    local mejorPP, mejorPart = nil, nil
    local mejorDist = math.huge
    for _, v in pairs(workspace:GetDescendants()) do
        if v.Name == "SellAllFish" and v:IsA("ProximityPrompt") then
            local part = v.Parent
            if part and part:IsA("BasePart") then
                local dist = (part.Position - hrp.Position).Magnitude
                if dist < mejorDist then
                    mejorDist = dist
                    mejorPP = v
                    mejorPart = part
                end
            end
        end
    end
    if not mejorPP then return false end
    hrp.CFrame = CFrame.new(mejorPart.Position + Vector3.new(0, 3, 3))
    task.wait(0.5)   -- necesario: servidor debe registrar posicion antes de fireproximityprompt
    pcall(function() fireproximityprompt(mejorPP) end)
    task.wait(1.5)   -- necesario: servidor procesa la venta y actualiza NumFish
    local hrp2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp2 then hrp2.CFrame = posOriginal end
    task.wait(0.3)
    return true
end

local function getNearestSpot()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local spotsFolder = workspace:FindFirstChild("FishingSpots")
    if not spotsFolder then return nil end
    local mejor, mejorDist = nil, math.huge
    for _, spot in pairs(spotsFolder:GetChildren()) do
        local part = spot:IsA("BasePart") and spot or spot:FindFirstChildWhichIsA("BasePart")
        local pp = spot:FindFirstChild("ProximityPrompt")
        if not part or not pp then continue end
        local isEnabled = spot:FindFirstChild("IsEnabled")
        if isEnabled and not isEnabled.Value then continue end
        local dist = (part.Position - hrp.Position).Magnitude
        if dist < mejorDist then mejorDist = dist mejor = spot end
    end
    return mejor
end

local function handleClickPrompt(cp, fishingGui)
    while autoFishActive and fishingGui.Enabled do
        local txt = cp.Text
        if txt:find("Press & Hold") or txt:find("Hold") then
            local vs = workspace.CurrentCamera.ViewportSize
            local x, y = vs.X / 2, vs.Y / 2
            pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
            while autoFishActive and fishingGui.Enabled do
                if not (cp.Text:find("Press & Hold") or cp.Text:find("Hold")) then
                    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
                    break
                end
                task.wait(0.03)
            end
        else
            refClick()
            task.wait(0.01)
        end
    end
    local vs = workspace.CurrentCamera.ViewportSize
    pcall(function() VIM:SendMouseButtonEvent(vs.X/2, vs.Y/2, 0, false, game, 0) end)
end

local fishSwBtn, fishSwDot

-- ============================================================
-- AUTO PESCA - LOOP PRINCIPAL (OPTIMIZADO)
-- ============================================================
local function autoFishLoop()
    local pgui = player.PlayerGui
    while autoFishActive do
        local numFish, fishSlots = getNumFish()
        if numFish >= fishSlots then
            vimRelease()
            local intentos = 0
            repeat
                venderPeces()
                task.wait(0.5)
                intentos += 1
                numFish, fishSlots = getNumFish()
            until numFish < fishSlots or intentos >= 3
            continue
        end

        local spot = getNearestSpot()
        if not spot then task.wait(0.1) continue end  -- OPTIMIZADO: 0.5 → 0.1
        local pp = spot:FindFirstChild("ProximityPrompt")
        if not pp then task.wait(0.1) continue end    -- OPTIMIZADO: 0.5 → 0.1

        -- Activar spot sin delays
        pcall(function() fireproximityprompt(pp) end)
        pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.E, false, game) end)
        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)

        -- Arrancar clicks inmediatamente en paralelo sin esperar la GUI
        task.spawn(function()
            local fireTimer = 0
            while autoFishActive do
                local fg = pgui:FindFirstChild("FishingGameUI")
                if fg and fg.Enabled then break end
                if not esperandoReset then
                    refClick()
                    local now = tick()
                    if now - fireTimer >= 0.3 then
                        fireTimer = now
                        pcall(function() fireproximityprompt(pp) end)
                        pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.E, false, game) end)
                        pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                    end
                end
                task.wait(0.03)
            end
        end)

        while autoFishActive do
            if forzarResetSpot then
                vimRelease()
                forzarResetSpot = false
                break
            end
            local n, max = getNumFish()
            if n >= max then
                vimRelease()
                break
            end

            local fishingGui = pgui:FindFirstChild("FishingGameUI")
            if not (fishingGui and fishingGui.Enabled) then
                local t1 = tick()
                while autoFishActive and tick() - t1 < 12 do
                    if forzarResetSpot then break end
                    fishingGui = pgui:FindFirstChild("FishingGameUI")
                    if fishingGui and fishingGui.Enabled then break end
                    task.wait(0.03)
                end
            end

            if not autoFishActive then break end
            if forzarResetSpot then vimRelease() forzarResetSpot = false break end
            if not fishingGui or not fishingGui.Enabled then break end

            local cp = nil
            local tCP = tick()
            while not cp and autoFishActive and tick() - tCP < 3 do
                local catchBar = fishingGui:FindFirstChild("CatchBar")
                if catchBar then cp = catchBar:FindFirstChild("ClickPrompt") end
                if not cp then
                    for _, v in pairs(fishingGui:GetDescendants()) do
                        if v.Name == "ClickPrompt" then cp = v break end
                    end
                end
                if not cp then task.wait(0.03) end
            end

            if not cp then break end

            task.spawn(function() handleClickPrompt(cp, fishingGui) end)
            while autoFishActive and fishingGui.Enabled do task.wait(0.03) end

            -- FishGetUI: evento instantaneo en lugar de polling con waits
            local fishGetUI = pgui:FindFirstChild("FishGetUI")
            if fishGetUI then
                if fishGetUI.Enabled then
                    -- Ya estaba visible, cerrar de inmediato
                    esperandoReset = true
                    while fishGetUI.Enabled and autoFishActive do
                        refClick()
                        task.wait(0.03)
                    end
                    esperandoReset = false
                else
                    -- Conectar evento exacto, sin polling
                    local appeared = false
                    local conn
                    conn = fishGetUI:GetPropertyChangedSignal("Enabled"):Connect(function()
                        if fishGetUI.Enabled then appeared = true end
                    end)
                    local t1 = tick()
                    while not appeared and autoFishActive and tick() - t1 < 0.3 do
                        task.wait(0.016)
                    end
                    conn:Disconnect()
                    if appeared then
                        esperandoReset = true
                        while fishGetUI.Enabled and autoFishActive do
                            refClick()
                            task.wait(0.03)
                        end
                        esperandoReset = false
                    end
                end
            end
            refClick()

            local nCheck, maxCheck = getNumFish()
            if nCheck >= maxCheck then
                vimRelease()
                break
            end

            -- Re-lanzar: mandar E y arrancar clicks en paralelo de inmediato
            pcall(function() fireproximityprompt(pp) end)
            pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.E, false, game) end)
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
            task.spawn(function()
                local fireTimer2 = 0
                while autoFishActive do
                    local fg = pgui:FindFirstChild("FishingGameUI")
                    if fg and fg.Enabled then break end
                    if not esperandoReset then
                        refClick()
                        local now = tick()
                        if now - fireTimer2 >= 0.3 then
                            fireTimer2 = now
                            pcall(function() fireproximityprompt(pp) end)
                            pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.E, false, game) end)
                            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                        end
                    end
                    task.wait(0.03)
                end
            end)
            -- Esperar a que aparezca la GUI (max 3s)
            local tL = tick()
            while autoFishActive and tick() - tL < 3 do
                if forzarResetSpot then vimRelease() forzarResetSpot = false break end
                local nL, maxL = getNumFish()
                if nL >= maxL then vimRelease() break end
                local fg = pgui:FindFirstChild("FishingGameUI")
                if fg and fg.Enabled then break end
                task.wait(0.016)
            end
        end
    end
end

local function activarAutoFish()
    autoFishActive = true
    fishThread = task.spawn(autoFishLoop)
    if fishSwBtn and fishSwDot then
        TS:Create(fishSwBtn, TweenInfo.new(0.2), { BackgroundColor3 = COLOR_ACTIVA }):Play()
        TS:Create(fishSwDot, TweenInfo.new(0.2), { BackgroundColor3 = Color3.new(1,1,1), Position = UDim2.new(0,24,0.5,-8) }):Play()
    end
end

local function desactivarAutoFish()
    autoFishActive = false
    local vs = workspace.CurrentCamera.ViewportSize
    pcall(function() VIM:SendMouseButtonEvent(vs.X/2, vs.Y/2, 0, false, game, 0) end)
    if fishThread then task.cancel(fishThread) fishThread = nil end
    if fishSwBtn and fishSwDot then
        TS:Create(fishSwBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(35,35,44) }):Play()
        TS:Create(fishSwDot, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(68,68,84), Position = UDim2.new(0,4,0.5,-8) }):Play()
    end
end

-- ============================================================
-- TERMINAL
-- ============================================================
local function abrirTerminal()
    if terminalSg then return end
    terminalSg = Instance.new("ScreenGui", player.PlayerGui)
    terminalSg.Name = "QuasoTerminal"
    terminalSg.ResetOnSpawn = false

    local tFrame = Instance.new("Frame", terminalSg)
    tFrame.Size = UDim2.new(0, 500, 0, 340)
    tFrame.Position = UDim2.new(0, 410, 0, 20)
    tFrame.BackgroundColor3 = Color3.fromRGB(13, 13, 15)
    tFrame.BorderSizePixel = 0
    local tCorner = Instance.new("UICorner", tFrame)
    tCorner.CornerRadius = UDim.new(0, 12)

    local tBar = Instance.new("Frame", tFrame)
    tBar.Size = UDim2.new(1, 0, 0, 36)
    tBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    tBar.BorderSizePixel = 0
    Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 12)

    local tSep = Instance.new("Frame", tBar)
    tSep.Size = UDim2.new(1, 0, 0, 1)
    tSep.Position = UDim2.new(0, 0, 1, -1)
    tSep.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    tSep.BorderSizePixel = 0

    local tTitulo = Instance.new("TextLabel", tBar)
    tTitulo.Size = UDim2.new(1, 0, 1, 0)
    tTitulo.BackgroundTransparency = 1
    tTitulo.Text = "terminal"
    tTitulo.TextColor3 = Color3.fromRGB(150, 150, 165)
    tTitulo.Font = Enum.Font.GothamMedium
    tTitulo.TextSize = 13

    local function crearDotT(color, posX)
        local dot = Instance.new("TextButton", tBar)
        dot.Size = UDim2.new(0, 13, 0, 13)
        dot.Position = UDim2.new(0, posX, 0.5, -6)
        dot.BackgroundColor3 = color
        dot.BorderSizePixel = 0 dot.Text = ""
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        return dot
    end

    local killBtn = crearDotT(Color3.fromRGB(235, 75, 75), 12)
    local minBtn  = crearDotT(Color3.fromRGB(240, 185, 50), 31)
    local maxBtn  = crearDotT(Color3.fromRGB(98, 197, 84),  50)

    local scroll = Instance.new("ScrollingFrame", tFrame)
    scroll.Size = UDim2.new(1, -16, 1, -100)
    scroll.Position = UDim2.new(0, 8, 0, 44)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 75)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    local lineCount = 0

    local function log(txt, color)
        lineCount += 1
        local l = Instance.new("TextLabel", scroll)
        l.LayoutOrder = lineCount
        l.Size = UDim2.new(1, -8, 0, 0)
        l.AutomaticSize = Enum.AutomaticSize.Y
        l.BackgroundTransparency = 1
        l.Text = "> " .. tostring(txt)
        l.TextColor3 = color or Color3.fromRGB(180, 255, 180)
        l.Font = Enum.Font.Code
        l.TextSize = 14
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextWrapped = true
        task.defer(function()
            task.defer(function()
                local h = layout.AbsoluteContentSize.Y + 4
                scroll.CanvasSize = UDim2.new(0, 0, 0, h)
                scroll.CanvasPosition = Vector2.new(0, h)
            end)
        end)
    end

    local inputBg = Instance.new("Frame", tFrame)
    inputBg.Size = UDim2.new(1, -16, 0, 0)
    inputBg.AutomaticSize = Enum.AutomaticSize.Y
    inputBg.Position = UDim2.new(0, 8, 1, -8)
    inputBg.AnchorPoint = Vector2.new(0, 1)
    inputBg.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    inputBg.BorderSizePixel = 0
    Instance.new("UICorner", inputBg).CornerRadius = UDim.new(0, 8)
    local inputPad = Instance.new("UIPadding", inputBg)
    inputPad.PaddingTop    = UDim.new(0, 8)
    inputPad.PaddingBottom = UDim.new(0, 8)
    inputPad.PaddingLeft   = UDim.new(0, 8)
    inputPad.PaddingRight  = UDim.new(0, 8)

    local iPrompt = Instance.new("TextLabel", inputBg)
    iPrompt.Size = UDim2.new(0, 14, 0, 18)
    iPrompt.Position = UDim2.new(0, 0, 0, 0)
    iPrompt.BackgroundTransparency = 1
    iPrompt.Text = ">"
    iPrompt.TextColor3 = COLOR_ACTIVA
    iPrompt.Font = Enum.Font.GothamBold
    iPrompt.TextSize = 14
    iPrompt.TextYAlignment = Enum.TextYAlignment.Top
    registrarColor(iPrompt, "TextColor3")

    local inputBox = Instance.new("TextBox", inputBg)
    inputBox.Size = UDim2.new(1, -20, 0, 0)
    inputBox.AutomaticSize = Enum.AutomaticSize.Y
    inputBox.Position = UDim2.new(0, 18, 0, 0)
    inputBox.BackgroundTransparency = 1
    inputBox.Text = ""
    inputBox.PlaceholderText = "escribe lua aqui..."
    inputBox.PlaceholderColor3 = Color3.fromRGB(55, 55, 65)
    inputBox.TextColor3 = Color3.fromRGB(220, 220, 230)
    inputBox.Font = Enum.Font.Code
    inputBox.TextSize = 14
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.TextYAlignment = Enum.TextYAlignment.Top
    inputBox.ClearTextOnFocus = false
    inputBox.MultiLine = true
    inputBox.TextWrapped = true

    local function ejecutarCodigo()
        local code = inputBox.Text
        if code == "" then return end
        log(code, Color3.fromRGB(160, 160, 255))
        inputBox.Text = ""
        local ok, err = pcall(function()
            local fn = loadstring(code)
            if fn then
                getfenv(fn).print = function(...)
                    local args = {...}
                    local out = ""
                    for i, v in ipairs(args) do out = out .. tostring(v) .. (i < #args and "  " or "") end
                    log(out)
                end
                fn()
            end
        end)
        if not ok then log(tostring(err), Color3.fromRGB(255, 100, 100)) end
    end

    inputBox:GetPropertyChangedSignal("Text"):Connect(function()
        local txt = inputBox.Text
        if txt:sub(-1) == "\n" then
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then
            else
                inputBox.Text = txt:sub(1, -2)
                ejecutarCodigo()
            end
        end
    end)

    local tInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local sNorm = UDim2.new(0, 500, 0, 340)
    local sMax  = UDim2.new(1, -20, 1, -20)
    local pNorm = UDim2.new(0, 410, 0, 20)
    local pMax  = UDim2.new(0, 10, 0, 10)
    local tMin, tMax = false, false

    killBtn.MouseButton1Click:Connect(function()
        terminalSg:Destroy()
        terminalSg = nil
    end)

    minBtn.MouseButton1Click:Connect(function()
        tMin = not tMin
        scroll.Visible = not tMin
        inputBg.Visible = not tMin
        tSep.Visible = not tMin
        tFrame.BackgroundTransparency = tMin and 1 or 0
        TS:Create(tFrame, tInfo, {
            Size = tMin and UDim2.new(0, 500, 0, 36) or (tMax and sMax or sNorm)
        }):Play()
    end)

    maxBtn.MouseButton1Click:Connect(function()
        if tMin then return end
        tMax = not tMax
        TS:Create(tFrame, tInfo, {
            Size = tMax and sMax or sNorm,
            Position = tMax and pMax or pNorm
        }):Play()
        tCorner.CornerRadius = tMax and UDim.new(0, 0) or UDim.new(0, 12)
    end)

    local d2, ds2, sp2
    tBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 and not tMax then
            d2 = true ds2 = inp.Position sp2 = tFrame.Position
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if d2 and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - ds2
            tFrame.Position = UDim2.new(sp2.X.Scale, math.floor(sp2.X.Offset+delta.X), sp2.Y.Scale, math.floor(sp2.Y.Offset+delta.Y))
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then d2 = false end
    end)

    log("QuasoSeal Terminal v2.5", COLOR_ACTIVA)
    log("Ejecuta cualquier codigo Lua aqui", Color3.fromRGB(90, 90, 105))
end

-- ============================================================
-- GUI PRINCIPAL
-- ============================================================
local sg = Instance.new("ScreenGui", player.PlayerGui)
sg.Name = "QuasoSeal"
sg.ResetOnSpawn = false

local ANCHO     = 360
local ALTO_BASE = 540
local ALTO_MAX  = 720
local tweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local minimizado = false

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0, ANCHO, 0, ALTO_BASE)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)

local titlebar = Instance.new("Frame", frame)
titlebar.Size = UDim2.new(1, 0, 0, 46)
titlebar.BackgroundColor3 = Color3.fromRGB(19, 19, 23)
titlebar.BorderSizePixel = 0
Instance.new("UICorner", titlebar).CornerRadius = UDim.new(0, 14)

local tbSep = Instance.new("Frame", titlebar)
tbSep.Size = UDim2.new(1, 0, 0, 1)
tbSep.Position = UDim2.new(0, 0, 1, -1)
tbSep.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
tbSep.BorderSizePixel = 0

local titulo = Instance.new("TextLabel", titlebar)
titulo.Size = UDim2.new(1, 0, 1, 0)
titulo.BackgroundTransparency = 1
titulo.Text = "QuasoSeal Menu"
titulo.TextColor3 = Color3.fromRGB(210, 210, 220)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 15

local dotsFrame = Instance.new("Frame", titlebar)
dotsFrame.Size = UDim2.new(0, 70, 1, 0)
dotsFrame.Position = UDim2.new(0, 12, 0, 0)
dotsFrame.BackgroundTransparency = 1

local function crearDot(color, posX)
    local dot = Instance.new("TextButton", dotsFrame)
    dot.Size = UDim2.new(0, 14, 0, 14)
    dot.Position = UDim2.new(0, posX, 0.5, -7)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0 dot.Text = ""
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    return dot
end

local btnCerrar    = crearDot(Color3.fromRGB(235, 75, 75),  0)
local btnMinimizar = crearDot(Color3.fromRGB(240, 185, 50), 22)

local tabsBar = Instance.new("Frame", frame)
tabsBar.Size = UDim2.new(1, -20, 0, 34)
tabsBar.Position = UDim2.new(0, 10, 0, 54)
tabsBar.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
tabsBar.BorderSizePixel = 0
Instance.new("UICorner", tabsBar).CornerRadius = UDim.new(0, 9)

local function crearTabBtn(texto, posX)
    local btn = Instance.new("TextButton", tabsBar)
    btn.Size = UDim2.new(0.5, -4, 1, -6)
    btn.Position = UDim2.new(posX, 2, 0, 3)
    btn.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    btn.BorderSizePixel = 0
    btn.Text = texto
    btn.TextColor3 = Color3.fromRGB(100, 100, 118)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    return btn
end

local tabJugador = crearTabBtn("Jugador", 0)
local tabDev     = crearTabBtn("Desarrollador", 0.5)

local mainScroll = Instance.new("ScrollingFrame", frame)
mainScroll.Size = UDim2.new(1, 0, 1, -96)
mainScroll.Position = UDim2.new(0, 0, 0, 96)
mainScroll.BackgroundTransparency = 1
mainScroll.BorderSizePixel = 0
mainScroll.ScrollBarThickness = 3
mainScroll.ScrollBarImageColor3 = Color3.fromRGB(55, 55, 70)
mainScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
mainScroll.ScrollingDirection = Enum.ScrollingDirection.Y

local function crearPagina()
    local p = Instance.new("Frame", mainScroll)
    p.Size = UDim2.new(1, 0, 0, 0)
    p.AutomaticSize = Enum.AutomaticSize.Y
    p.BackgroundTransparency = 1
    local lay = Instance.new("UIListLayout", p)
    lay.Padding = UDim.new(0, 7)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", p)
    pad.PaddingLeft   = UDim.new(0, 10)
    pad.PaddingRight  = UDim.new(0, 10)
    pad.PaddingTop    = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    return p, lay
end

local pageJugador, jugadorLayout = crearPagina()
pageJugador.Visible = true
local pageDev, devLayout = crearPagina()
pageDev.Visible = false

local function resizarFrame()
    if minimizado then return end
    local lay = pageJugador.Visible and jugadorLayout or devLayout
    local contenido = lay.AbsoluteContentSize.Y + 20
    mainScroll.CanvasSize = UDim2.new(0, 0, 0, contenido)
    local targetH = math.clamp(contenido + 96, ALTO_BASE, ALTO_MAX)
    TS:Create(frame, tweenInfo, { Size = UDim2.new(0, ANCHO, 0, targetH) }):Play()
end

jugadorLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizarFrame)
devLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizarFrame)

local function activarTab(esJ)
    pageJugador.Visible = esJ pageDev.Visible = not esJ
    mainScroll.CanvasPosition = Vector2.zero
    resizarFrame()
    TS:Create(tabJugador, TweenInfo.new(0.18), {
        BackgroundColor3 = esJ and COLOR_ACTIVA or Color3.fromRGB(28,28,35),
        TextColor3 = esJ and Color3.new(1,1,1) or Color3.fromRGB(100,100,118)
    }):Play()
    TS:Create(tabDev, TweenInfo.new(0.18), {
        BackgroundColor3 = not esJ and COLOR_ACTIVA or Color3.fromRGB(28,28,35),
        TextColor3 = not esJ and Color3.new(1,1,1) or Color3.fromRGB(100,100,118)
    }):Play()
end

tabJugador.MouseButton1Click:Connect(function() activarTab(true) end)
tabDev.MouseButton1Click:Connect(function() activarTab(false) end)
activarTab(true)

btnCerrar.MouseButton1Click:Connect(function()
    if terminalSg then terminalSg:Destroy() terminalSg = nil end
    sg:Destroy()
end)

btnMinimizar.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    tabsBar.Visible = not minimizado
    mainScroll.Visible = not minimizado
    tbSep.Visible = not minimizado
    frame.BackgroundTransparency = minimizado and 1 or 0
    TS:Create(frame, tweenInfo, {
        Size = minimizado and UDim2.new(0, ANCHO, 0, 46) or UDim2.new(0, ANCHO, 0, ALTO_BASE)
    }):Play()
end)

-- ============================================================
-- HELPERS UI
-- ============================================================
local function crearToggle(parent, nombre, desc, callback)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 60)
    row.BackgroundColor3 = Color3.fromRGB(19, 19, 24)
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", row)
    stroke.Color = Color3.fromRGB(32, 32, 42)
    stroke.Thickness = 1

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(1, -68, 0, 22)
    label.Position = UDim2.new(0, 14, 0, 10)
    label.BackgroundTransparency = 1
    label.Text = nombre
    label.TextColor3 = Color3.fromRGB(225, 225, 232)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 15
    label.TextXAlignment = Enum.TextXAlignment.Left

    local sub = Instance.new("TextLabel", row)
    sub.Size = UDim2.new(1, -68, 0, 16)
    sub.Position = UDim2.new(0, 14, 0, 34)
    sub.BackgroundTransparency = 1
    sub.Text = desc
    sub.TextColor3 = Color3.fromRGB(72, 72, 88)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextXAlignment = Enum.TextXAlignment.Left

    local swBg = Instance.new("Frame", row)
    swBg.Size = UDim2.new(0, 44, 0, 24)
    swBg.Position = UDim2.new(1, -56, 0.5, -12)
    swBg.BackgroundColor3 = Color3.fromRGB(35, 35, 44)
    swBg.BorderSizePixel = 0
    Instance.new("UICorner", swBg).CornerRadius = UDim.new(1, 0)

    local swDot = Instance.new("Frame", swBg)
    swDot.Size = UDim2.new(0, 16, 0, 16)
    swDot.Position = UDim2.new(0, 4, 0.5, -8)
    swDot.BackgroundColor3 = Color3.fromRGB(68, 68, 84)
    swDot.BorderSizePixel = 0
    Instance.new("UICorner", swDot).CornerRadius = UDim.new(1, 0)

    local active = false
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1 btn.Text = ""
    btn.MouseButton1Click:Connect(function()
        active = not active
        TS:Create(swBg, TweenInfo.new(0.2), {
            BackgroundColor3 = active and COLOR_ACTIVA or Color3.fromRGB(35,35,44)
        }):Play()
        TS:Create(swDot, TweenInfo.new(0.2), {
            BackgroundColor3 = active and Color3.new(1,1,1) or Color3.fromRGB(68,68,84),
            Position = active and UDim2.new(0,24,0.5,-8) or UDim2.new(0,4,0.5,-8)
        }):Play()
        callback(active)
    end)
    return swBg, swDot
end

local function crearBoton(parent, nombre, desc, callback)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 60)
    row.BackgroundColor3 = Color3.fromRGB(19, 19, 24)
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", row)
    stroke.Color = Color3.fromRGB(32, 32, 42)
    stroke.Thickness = 1

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(1, -42, 0, 22)
    label.Position = UDim2.new(0, 14, 0, 10)
    label.BackgroundTransparency = 1
    label.Text = nombre
    label.TextColor3 = Color3.fromRGB(225, 225, 232)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 15
    label.TextXAlignment = Enum.TextXAlignment.Left

    local sub = Instance.new("TextLabel", row)
    sub.Size = UDim2.new(1, -42, 0, 16)
    sub.Position = UDim2.new(0, 14, 0, 34)
    sub.BackgroundTransparency = 1
    sub.Text = desc
    sub.TextColor3 = Color3.fromRGB(72, 72, 88)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextXAlignment = Enum.TextXAlignment.Left

    local arrow = Instance.new("TextLabel", row)
    arrow.Size = UDim2.new(0, 26, 1, 0)
    arrow.Position = UDim2.new(1, -32, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "›"
    arrow.TextColor3 = COLOR_ACTIVA
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 24
    registrarColor(arrow, "TextColor3")

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1 btn.Text = ""
    btn.MouseButton1Click:Connect(function()
        TS:Create(row, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(28,18,48) }):Play()
        task.delay(0.18, function()
            TS:Create(row, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(19,19,24) }):Play()
        end)
        callback()
    end)
end

local function crearPaleta(parent)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 60)
    row.BackgroundColor3 = Color3.fromRGB(19, 19, 24)
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", row)
    stroke.Color = Color3.fromRGB(32, 32, 42)
    stroke.Thickness = 1

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.45, 0, 0, 22)
    label.Position = UDim2.new(0, 14, 0, 10)
    label.BackgroundTransparency = 1
    label.Text = "Color del menú"
    label.TextColor3 = Color3.fromRGB(225, 225, 232)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 15
    label.TextXAlignment = Enum.TextXAlignment.Left

    local sub = Instance.new("TextLabel", row)
    sub.Size = UDim2.new(0.45, 0, 0, 16)
    sub.Position = UDim2.new(0, 14, 0, 34)
    sub.BackgroundTransparency = 1
    sub.Text = "Elige el color del acento"
    sub.TextColor3 = Color3.fromRGB(72, 72, 88)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextXAlignment = Enum.TextXAlignment.Left

    local colores = {
        Color3.fromRGB(124, 58, 237),
        Color3.fromRGB(59, 130, 246),
        Color3.fromRGB(16, 185, 129),
        Color3.fromRGB(239, 68, 68),
        Color3.fromRGB(245, 158, 11),
        Color3.fromRGB(236, 72, 153),
    }

    local paletaFrame = Instance.new("Frame", row)
    paletaFrame.Size = UDim2.new(0, #colores * 26 + 2, 0, 26)
    paletaFrame.Position = UDim2.new(1, -(#colores * 26 + 14), 0.5, -13)
    paletaFrame.BackgroundTransparency = 1

    for i, color in ipairs(colores) do
        local chip = Instance.new("TextButton", paletaFrame)
        chip.Size = UDim2.new(0, 20, 0, 20)
        chip.Position = UDim2.new(0, (i-1)*26, 0.5, -10)
        chip.BackgroundColor3 = color
        chip.BorderSizePixel = 0
        chip.Text = ""
        Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)

        local ring = Instance.new("UIStroke", chip)
        ring.Color = Color3.new(1,1,1)
        ring.Thickness = 0

        chip.MouseButton1Click:Connect(function()
            for _, c in pairs(paletaFrame:GetChildren()) do
                local s = c:FindFirstChildOfClass("UIStroke")
                if s then s.Thickness = 0 end
            end
            ring.Thickness = 2
            aplicarColor(color)
            activarTab(pageJugador.Visible)
        end)
    end
end

local function crearSeccionLucky(parent)
    local header = Instance.new("TextButton", parent)
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(19, 19, 24)
    header.BorderSizePixel = 0 header.Text = ""
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    local hStroke = Instance.new("UIStroke", header)
    hStroke.Color = Color3.fromRGB(32, 32, 42) hStroke.Thickness = 1

    local hLabel = Instance.new("TextLabel", header)
    hLabel.Size = UDim2.new(1, -36, 1, 0)
    hLabel.Position = UDim2.new(0, 14, 0, 0)
    hLabel.BackgroundTransparency = 1
    hLabel.Text = "⭐ LUGARES SUERTUDOS :D"
    hLabel.TextColor3 = COLOR_ACTIVA
    hLabel.Font = Enum.Font.GothamBold
    hLabel.TextSize = 13
    hLabel.TextXAlignment = Enum.TextXAlignment.Left
    registrarColor(hLabel, "TextColor3")

    local hArrow = Instance.new("TextLabel", header)
    hArrow.Size = UDim2.new(0, 26, 1, 0)
    hArrow.Position = UDim2.new(1, -30, 0, 0)
    hArrow.BackgroundTransparency = 1
    hArrow.Text = "▼"
    hArrow.TextColor3 = COLOR_ACTIVA
    hArrow.Font = Enum.Font.GothamBold
    hArrow.TextSize = 13
    registrarColor(hArrow, "TextColor3")

    local listFrame = Instance.new("Frame", parent)
    listFrame.Size = UDim2.new(1, 0, 0, 0)
    listFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
    listFrame.BorderSizePixel = 0
    listFrame.ClipsDescendants = true
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 10)
    local lStroke = Instance.new("UIStroke", listFrame)
    lStroke.Color = Color3.fromRGB(32,32,42) lStroke.Thickness = 1

    local listScroll = Instance.new("ScrollingFrame", listFrame)
    listScroll.Size = UDim2.new(1, -8, 1, -8)
    listScroll.Position = UDim2.new(0, 4, 0, 4)
    listScroll.BackgroundTransparency = 1
    listScroll.BorderSizePixel = 0
    listScroll.ScrollBarThickness = 3
    listScroll.ScrollBarImageColor3 = Color3.fromRGB(55,55,70)
    listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    local listLayout = Instance.new("UIListLayout", listScroll)
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local ITEM_H, MAX_V = 42, 4
    local abierto = false
    local luckyRows = {}
    local luckyConexiones = {}

    local function calcAltura(count)
        return math.min(count, MAX_V) * (ITEM_H + 5) + 8
    end

    local function actualizarLista()
        for _, r in pairs(luckyRows) do if r and r.Parent then r:Destroy() end end
        luckyRows = {}
        local count = 0
        local spotsFolder = workspace:FindFirstChild("FishingSpots")
        if not spotsFolder then return end
        for i, spot in pairs(spotsFolder:GetChildren()) do
            local lucky = spot:FindFirstChild("LuckySpawned")
            if not lucky or not lucky.Value then continue end

            local row = Instance.new("Frame", listScroll)
            row.Size = UDim2.new(1, 0, 0, ITEM_H)
            row.BackgroundColor3 = Color3.fromRGB(23, 23, 29)
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

            local lootType = spot:FindFirstChild("LootType")
            local lootTxt = lootType and lootType.Value ~= "" and lootType.Value or ("Spot " .. i)

            local nom = Instance.new("TextLabel", row)
            nom.Size = UDim2.new(1, -72, 1, 0)
            nom.Position = UDim2.new(0, 12, 0, 0)
            nom.BackgroundTransparency = 1
            nom.Text = "⭐ " .. lootTxt
            nom.TextColor3 = Color3.fromRGB(245, 200, 80)
            nom.Font = Enum.Font.GothamMedium
            nom.TextSize = 13
            nom.TextXAlignment = Enum.TextXAlignment.Left

            local tpBtn = Instance.new("TextButton", row)
            tpBtn.Size = UDim2.new(0, 52, 0, 26)
            tpBtn.Position = UDim2.new(1, -60, 0.5, -13)
            tpBtn.BackgroundColor3 = COLOR_ACTIVA
            tpBtn.BorderSizePixel = 0
            tpBtn.Text = "Ir"
            tpBtn.TextColor3 = Color3.new(1,1,1)
            tpBtn.Font = Enum.Font.GothamBold
            tpBtn.TextSize = 13
            Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 7)
            registrarColor(tpBtn, "BackgroundColor3")

            local spotRef = spot
            tpBtn.MouseButton1Click:Connect(function()
                local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if not hrp or not spotRef or not spotRef.Parent then return end
                local part = spotRef:IsA("BasePart") and spotRef or spotRef:FindFirstChildWhichIsA("BasePart")
                if not part then return end

                local materialesSolidos = {
                    [Enum.Material.Glacier]     = true,
                    [Enum.Material.Snow]        = true,
                    [Enum.Material.Basalt]      = true,
                    [Enum.Material.Rock]        = true,
                    [Enum.Material.CrackedLava] = true,
                    [Enum.Material.Ground]      = true,
                    [Enum.Material.Grass]       = true,
                    [Enum.Material.Sand]        = true,
                    [Enum.Material.Wood]        = true,
                    [Enum.Material.SmoothPlastic] = true,
                }

                local bestPos = nil
                local bestDist = math.huge
                for dist = 15, 80, 5 do
                    for angulo = 0, 315, 45 do
                        local rad = math.rad(angulo)
                        local offset = Vector3.new(math.cos(rad)*dist, 60, math.sin(rad)*dist)
                        local origen = part.Position + offset
                        local ray = workspace:Raycast(origen, Vector3.new(0, -150, 0))
                        if ray and materialesSolidos[ray.Material] and dist < bestDist then
                            bestDist = dist
                            bestPos = ray.Position
                        end
                    end
                    if bestPos then break end
                end

                if bestPos then
                    forzarResetSpot = true
                    hrp.CFrame = CFrame.new(bestPos + Vector3.new(0, 4, 0))
                else
                    forzarResetSpot = true
                    hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 10, 0))
                end

                TS:Create(tpBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(80,200,120) }):Play()
                task.delay(0.4, function()
                    TS:Create(tpBtn, TweenInfo.new(0.2), { BackgroundColor3 = COLOR_ACTIVA }):Play()
                end)
            end)

            count += 1
            table.insert(luckyRows, row)
        end

        if count == 0 then
            local empty = Instance.new("TextLabel", listScroll)
            empty.Size = UDim2.new(1, 0, 0, ITEM_H)
            empty.BackgroundTransparency = 1
            empty.Text = "No hay spots suertudos activos"
            empty.TextColor3 = Color3.fromRGB(90, 90, 105)
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 13
            table.insert(luckyRows, empty)
            count = 1
        end

        listScroll.CanvasSize = UDim2.new(0, 0, 0, count * (ITEM_H + 5))
        if abierto then
            TS:Create(listFrame, tweenInfo, { Size = UDim2.new(1, 0, 0, calcAltura(count)) }):Play()
        end
    end

    local function engancharSpots()
        for _, c in pairs(luckyConexiones) do c:Disconnect() end
        luckyConexiones = {}
        local spotsFolder = workspace:FindFirstChild("FishingSpots")
        if not spotsFolder then return end
        for _, spot in pairs(spotsFolder:GetChildren()) do
            local lucky = spot:FindFirstChild("LuckySpawned")
            if lucky then
                local c = lucky.Changed:Connect(function()
                    if abierto then actualizarLista() end
                end)
                table.insert(luckyConexiones, c)
            end
        end
    end

    header.MouseButton1Click:Connect(function()
        abierto = not abierto
        hArrow.Text = abierto and "▲" or "▼"
        if abierto then
            engancharSpots()
            actualizarLista()
            TS:Create(header, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(24,16,42) }):Play()
        else
            for _, c in pairs(luckyConexiones) do c:Disconnect() end
            luckyConexiones = {}
            TS:Create(listFrame, tweenInfo, { Size = UDim2.new(1, 0, 0, 0) }):Play()
            TS:Create(header, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(19,19,24) }):Play()
        end
    end)
end

local function crearSeccionTeleport(parent)
    local header = Instance.new("TextButton", parent)
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(19, 19, 24)
    header.BorderSizePixel = 0 header.Text = ""
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    local hStroke = Instance.new("UIStroke", header)
    hStroke.Color = Color3.fromRGB(32, 32, 42) hStroke.Thickness = 1

    local hLabel = Instance.new("TextLabel", header)
    hLabel.Size = UDim2.new(1, -36, 1, 0)
    hLabel.Position = UDim2.new(0, 14, 0, 0)
    hLabel.BackgroundTransparency = 1
    hLabel.Text = "TELEPORT A JUGADOR ;3"
    hLabel.TextColor3 = COLOR_ACTIVA
    hLabel.Font = Enum.Font.GothamBold
    hLabel.TextSize = 13
    hLabel.TextXAlignment = Enum.TextXAlignment.Left
    registrarColor(hLabel, "TextColor3")

    local hArrow = Instance.new("TextLabel", header)
    hArrow.Size = UDim2.new(0, 26, 1, 0)
    hArrow.Position = UDim2.new(1, -30, 0, 0)
    hArrow.BackgroundTransparency = 1
    hArrow.Text = "▼"
    hArrow.TextColor3 = COLOR_ACTIVA
    hArrow.Font = Enum.Font.GothamBold
    hArrow.TextSize = 13
    registrarColor(hArrow, "TextColor3")

    local listFrame = Instance.new("Frame", parent)
    listFrame.Size = UDim2.new(1, 0, 0, 0)
    listFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
    listFrame.BorderSizePixel = 0
    listFrame.ClipsDescendants = true
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 10)
    local lStroke = Instance.new("UIStroke", listFrame)
    lStroke.Color = Color3.fromRGB(32,32,42) lStroke.Thickness = 1

    local listScroll = Instance.new("ScrollingFrame", listFrame)
    listScroll.Size = UDim2.new(1, -8, 1, -8)
    listScroll.Position = UDim2.new(0, 4, 0, 4)
    listScroll.BackgroundTransparency = 1
    listScroll.BorderSizePixel = 0
    listScroll.ScrollBarThickness = 3
    listScroll.ScrollBarImageColor3 = Color3.fromRGB(55,55,70)
    listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    local listLayout = Instance.new("UIListLayout", listScroll)
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local ITEM_H, MAX_V = 42, 4
    local abierto = false
    local pRows = {}

    local function calcAltura(count)
        return math.min(count, MAX_V) * (ITEM_H + 5) + 8
    end

    local function actualizarLista()
        for _, r in pairs(pRows) do if r and r.Parent then r:Destroy() end end
        pRows = {}
        local count = 0
        for _, p in pairs(game.Players:GetPlayers()) do
            if p ~= player then
                local row = Instance.new("Frame", listScroll)
                row.Size = UDim2.new(1, 0, 0, ITEM_H)
                row.BackgroundColor3 = Color3.fromRGB(23, 23, 29)
                row.BorderSizePixel = 0
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

                local nom = Instance.new("TextLabel", row)
                nom.Size = UDim2.new(1, -72, 1, 0)
                nom.Position = UDim2.new(0, 12, 0, 0)
                nom.BackgroundTransparency = 1
                nom.Text = p.Name
                nom.TextColor3 = Color3.fromRGB(210, 210, 222)
                nom.Font = Enum.Font.GothamMedium
                nom.TextSize = 13
                nom.TextXAlignment = Enum.TextXAlignment.Left

                local tpBtn = Instance.new("TextButton", row)
                tpBtn.Size = UDim2.new(0, 52, 0, 26)
                tpBtn.Position = UDim2.new(1, -60, 0.5, -13)
                tpBtn.BackgroundColor3 = COLOR_ACTIVA
                tpBtn.BorderSizePixel = 0
                tpBtn.Text = "Ir"
                tpBtn.TextColor3 = Color3.new(1,1,1)
                tpBtn.Font = Enum.Font.GothamBold
                tpBtn.TextSize = 13
                Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 7)
                registrarColor(tpBtn, "BackgroundColor3")

                tpBtn.MouseButton1Click:Connect(function()
                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    local tHrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                    if hrp and tHrp then
                        hrp.CFrame = tHrp.CFrame + Vector3.new(3, 0, 0)
                        TS:Create(tpBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(80,200,120) }):Play()
                        task.delay(0.4, function()
                            TS:Create(tpBtn, TweenInfo.new(0.2), { BackgroundColor3 = COLOR_ACTIVA }):Play()
                        end)
                    end
                end)
                count += 1
                table.insert(pRows, row)
            end
        end
        listScroll.CanvasSize = UDim2.new(0, 0, 0, count * (ITEM_H + 5))
        if abierto then
            TS:Create(listFrame, tweenInfo, { Size = UDim2.new(1, 0, 0, calcAltura(count)) }):Play()
        end
    end

    header.MouseButton1Click:Connect(function()
        abierto = not abierto
        hArrow.Text = abierto and "▲" or "▼"
        if abierto then
            actualizarLista()
            TS:Create(header, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(24,16,42) }):Play()
        else
            TS:Create(listFrame, tweenInfo, { Size = UDim2.new(1, 0, 0, 0) }):Play()
            TS:Create(header, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(19,19,24) }):Play()
        end
    end)

    game.Players.PlayerAdded:Connect(function() if abierto then actualizarLista() end end)
    game.Players.PlayerRemoving:Connect(function() task.wait(0.1) if abierto then actualizarLista() end end)
end

-- ============================================================
-- PESTAÑA JUGADOR
-- ============================================================
crearToggle(pageJugador, "Fly", "Volar con la camara",
    function(on) flyActive = on if on then iniciarFly() else detenerFly() end end)

crearToggle(pageJugador, "Speed", "Velocidad x2",
    function(on)
        speedActive = on
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = on and 32 or 16 end
    end)

crearToggle(pageJugador, "Stamina infinita", "Mantiene swim stamina al maximo",
    function(on) staminaActive = on if on then buscarStamina() else desconectarStamina() end end)

crearToggle(pageJugador, "ESP Focas", "Resalta jugadores en verde",
    function(on) espActive = on if on then activarEsp() else desactivarEsp() end end)

fishSwBtn, fishSwDot = crearToggle(pageJugador, "Auto Pesca", "Pesca y vende automaticamente  [Q]",
    function(on) if on then activarAutoFish() else desactivarAutoFish() end end)

crearSeccionLucky(pageJugador)
crearSeccionTeleport(pageJugador)

-- ============================================================
-- PESTAÑA DEV
-- ============================================================
crearBoton(pageDev, "Terminal", "Abrir consola Lua", abrirTerminal)
crearBoton(pageDev, "Dex Explorer", "Explorador de instancias", function()
    pcall(function() loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-Dex-Explorer-DPP-73687"))() end)
end)
crearPaleta(pageDev)

-- ============================================================
-- ATAJO Q
-- ============================================================
UIS.InputBegan:Connect(function(inp, gameProcessed)
    if gameProcessed then return end
    if inp.KeyCode == Enum.KeyCode.Q then
        if autoFishActive then desactivarAutoFish() else activarAutoFish() end
    end
end)

-- ============================================================
-- FLY LOOP
-- ============================================================
RS.RenderStepped:Connect(function()
    if flyActive and player.Character then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if hrp and bodyVel and bodyGyro then
            local cam = workspace.CurrentCamera
            bodyGyro.CFrame = cam.CFrame
            bodyVel.Velocity = cam.CFrame.LookVector * flySpeed
        end
    end
end)

-- ============================================================
-- ARRASTRAR
-- ============================================================
local dragging, dragStart, startPos
titlebar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true dragStart = inp.Position startPos = frame.Position
    end
end)
UIS.InputChanged:Connect(function(inp)
    if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = inp.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, math.floor(startPos.X.Offset + delta.X),
            startPos.Y.Scale, math.floor(startPos.Y.Offset + delta.Y)
        )
    end
end)
UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- ============================================================
-- ANTI-ADMIN
-- ============================================================
local MOD_IDS = {
    [395002797]  = true, [5785934400] = true, [6161009207] = true,
    [533788547]  = true, [103052989]  = true, [448367131]  = true,
    [7304569464] = true, [22927328]   = true, [5348354]    = true,
    [181128289]  = true,
}
local MOD_GROUP = 34533445
local MOD_RANK  = 250

local function esAdmin(p)
    if MOD_IDS[p.UserId] then return true end
    local ok, result = pcall(function()
        return p:IsInGroup(MOD_GROUP) and p:GetRankInGroup(MOD_GROUP) >= MOD_RANK
    end)
    return ok and result
end

local function panicMode()
    if autoFishActive then desactivarAutoFish() end
    if flyActive then flyActive = false detenerFly() end
    if staminaActive then staminaActive = false desconectarStamina() end
    if espActive then espActive = false desactivarEsp() end
    if terminalSg then terminalSg:Destroy() terminalSg = nil end
    pcall(function() sg:Destroy() end)
end

local function chequearAdmin(p)
    if p == player then return end
    if esAdmin(p) then panicMode() end
end

for _, p in pairs(game.Players:GetPlayers()) do
    task.spawn(chequearAdmin, p)
end

game.Players.PlayerAdded:Connect(function(p)
    task.wait(1)
    chequearAdmin(p)
end)
