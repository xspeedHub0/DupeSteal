--// Servicios principales
local services = {
    Players = game:GetService("Players"),
    StarterGui = game:GetService("StarterGui"),
    CoreGui = game:GetService("CoreGui"),
    VirtualInputManager = game:GetService("VirtualInputManager"),
    CollectionService = game:GetService("CollectionService"),
    RunService = game:GetService("RunService"),
}

local LocalPlayer = services.Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

--// Variables globales
local blockedPlayers = {}
local isRunning = false
local playerAddedConn = nil
local periodicTask = nil

-- Helper: safe check if object is a GuiObject with position/size
local function is_valid_gui_object(obj)
    if typeof(obj) ~= "Instance" then return false end
    return obj:IsA("GuiObject")
end

local function click_at(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    pcall(function()
        services.VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.06)
        services.VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    task.wait(0.3)
    return true
end

-- Bloquear a un jugador específico
function block_player(target_player)
    if not target_player or typeof(target_player) ~= "Instance" or not target_player:IsA("Player") then
        warn("✗ Jugador inválido")
        return false
    end

    if blockedPlayers[target_player.UserId] then
        print("✅ " .. target_player.Name .. " ya estaba bloqueado")
        return true
    end

    print("🔧 Intentando bloquear a: " .. target_player.Name)

    local ok, result = pcall(function()
        services.StarterGui:SetCore("PromptBlockPlayer", target_player)
    end)
    if not ok then
        warn("Error al abrir el diálogo de bloqueo: ", result)
        return false
    end

    task.wait(1.5)

    local function try_find_button(targetTexts)
        for _, gui in ipairs(services.CoreGui:GetDescendants()) do
            if is_valid_gui_object(gui) and gui.Visible then
                local okText, text = pcall(function() return gui.Text end)
                local okPos, pos = pcall(function() return gui.AbsolutePosition end)
                local okSize, size = pcall(function() return gui.AbsoluteSize end)
                if okText and okPos and okSize and text and pos and size and gui:IsA("TextButton") then
                    local btnText = string.lower(tostring(text))
                    for _, want in ipairs(targetTexts) do
                        if btnText == want then
                            local clickX = pos.X + (size.X / 2)
                            local clickY = pos.Y + (size.Y / 2)
                            print(("🎯 Haciendo clic en botón '%s' en: %d,%d"):format(text, math.floor(clickX), math.floor(clickY)))
                            click_at(clickX, clickY)
                            task.wait(0.8)
                            local stillPrompt = services.CoreGui:FindFirstChild("PromptDialog", true)
                            if not stillPrompt then return true end
                        end
                    end
                end
            end
        end
        return false
    end

    local success = try_find_button({"bloquear"}) or try_find_button({"block"})

    -- Último recurso: clic estimado en diálogo
    if not success then
        for _, gui in ipairs(services.CoreGui:GetDescendants()) do
            if is_valid_gui_object(gui) and gui.Visible then
                local okSize, size = pcall(function() return gui.AbsoluteSize end)
                local okPos, pos = pcall(function() return gui.AbsolutePosition end)
                if okSize and okPos and size and pos and size.X > 300 and size.Y > 200 then
                    local estimatedX = pos.X + (size.X / 2)
                    local estimatedY = pos.Y + size.Y - 100
                    print("🔎 Intentando clic estimado: " .. math.floor(estimatedX) .. "," .. math.floor(estimatedY))
                    click_at(estimatedX, estimatedY)
                    task.wait(0.8)
                    local stillPrompt = services.CoreGui:FindFirstChild("PromptDialog", true)
                    if not stillPrompt then
                        success = true
                        break
                    end
                end
            end
        end
    end

    if success then
        blockedPlayers[target_player.UserId] = true
        print("🎉 BLOQUEO EXITOSO para: " .. target_player.Name)
        return true
    else
        warn("❌ Todos los métodos de bloqueo fallaron para: " .. target_player.Name)
        return false
    end
end

-- Función para encontrar amigos en el servidor usando IsFriendsWith
function get_friends_in_server()
    local friendsFound = {}
    local allPlayers = services.Players:GetPlayers()
    for _, p in ipairs(allPlayers) do
        if p ~= LocalPlayer and LocalPlayer:IsFriendsWith(p.UserId) then
            table.insert(friendsFound, p)
            print("👥 Amigo detectado: " .. p.Name)
        end
    end
    return friendsFound
end

-- Bloquear todos los amigos en el servidor
function block_all_friends()
    print("🔍 Buscando amigos en el servidor para bloquear...")
    local friends = get_friends_in_server()
    if #friends == 0 then
        print("📭 No se encontraron amigos.")
        return
    end
    for _, friend in ipairs(friends) do
        if not blockedPlayers[friend.UserId] then
            print("🚫 Bloqueando amigo: " .. friend.Name)
            block_player(friend)
            task.wait(2)
        end
    end
end

-- Iniciar bloqueo automático
function start_auto_block()
    if isRunning then return end
    isRunning = true
    print("🛡️ BLOQUEO AUTOMÁTICO DE AMIGOS INICIADO")

    -- Bloquear ahora los amigos
    task.spawn(block_all_friends)

    -- Detectar amigos que entren nuevos
    if not playerAddedConn then
        playerAddedConn = services.Players.PlayerAdded:Connect(function(p)
            task.wait(1)
            if LocalPlayer:IsFriendsWith(p.UserId) then
                print("🚨 NUEVO AMIGO DETECTADO: " .. p.Name)
                block_player(p)
            end
        end)
    end

    -- Periodic check
    if not periodicTask then
        periodicTask = task.spawn(function()
            while isRunning do
                task.wait(30)
                if not isRunning then break end
                local friends = get_friends_in_server()
                for _, f in ipairs(friends) do
                    if not blockedPlayers[f.UserId] then
                        print("🔍 Amigo no bloqueado detectado: " .. f.Name)
                        block_player(f)
                    end
                end
            end
        end)
    end
end

function stop_auto_block()
    isRunning = false
    print("🛑 BLOQUEO AUTOMÁTICO DETENIDO")
    if playerAddedConn then
        pcall(function() playerAddedConn:Disconnect() end)
        playerAddedConn = nil
    end
    periodicTask = nil
end

-- Estadísticas
function get_block_stats()
    local totalBlocked = 0
    for _ in pairs(blockedPlayers) do totalBlocked = totalBlocked + 1 end
    local friendsOnline = #get_friends_in_server()
    return {totalBlocked = totalBlocked, friendsOnline = friendsOnline, isRunning = isRunning}
end

-- Comandos de control
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F1 then
        local stats = get_block_stats()
        print("📊 ESTADÍSTICAS:")
        print("   Amigos bloqueados: " .. stats.totalBlocked)
        print("   Amigos en línea: " .. stats.friendsOnline)
        print("   Estado: " .. (stats.isRunning and "ACTIVO" or "INACTIVO"))
    elseif input.KeyCode == Enum.KeyCode.F2 then
        stop_auto_block()
    elseif input.KeyCode == Enum.KeyCode.F3 then
        start_auto_block()
    elseif input.KeyCode == Enum.KeyCode.F4 then
        block_all_friends()
    end
end)

-- Inicio automático
task.spawn(function()
    task.wait(5)
    print("⏰ Iniciando bloqueo automático...")
    start_auto_block()
end)

return {
    block_player = block_player,
    block_all_friends = block_all_friends,
    start_auto_block = start_auto_block,
    stop_auto_block = stop_auto_block,
    get_block_stats = get_block_stats
}
