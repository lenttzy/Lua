itemid =5640
delay = 65
far   = 10

maxPlayersAllowed = 1
showUI = true
local pnbStarted = false
local needCheck = true
local playerCountManual = nil
credit = "@Lent"

function Overlay(txt)
  SendVariantList({ [0] = "OnTextOverlay", [1] = "`w[`6@Lent`w] `9" .. txt })
end

function Log(txt)
  LogToConsole("`w[`6" .. credit .. "`w]: " .. txt)
end

function warn(txt)
  SendVariantList({
    [0] = "OnAddNotification",
    [1] = "interface/atomic_button.rttex",
    [2] = txt,
    [3] = "audio/hub_open.wav"
  })
end

function place(x, y)
    local pkt = {
        x = x * 32,
        y = y * 32,
        px = x,
        py = y,
        type = 3,
        value = itemid
    }
    SendPacketRaw(false, pkt)
end

function punch(x, y)
    local pkt = {
        x = x * 32,
        y = y * 32,
        px = x,
        py = y,
        type = 3,
        value = 18
    }
    SendPacketRaw(false, pkt)
end

AddHook("OnVariant", "PlayerDetector", function(v)
    if v[0] == "OnConsoleMessage" then
        local msg = v[1] or ""
        if msg:find("entered") then
            if playerCountManual ~= nil then
                playerCountManual = playerCountManual + 1
            end
            needCheck = true
        elseif msg:find("left") then
            if playerCountManual ~= nil then
                playerCountManual = math.max(1, playerCountManual - 1)
            end
            needCheck = true
        end
    end
end)

function getPlayerCount()
    return #GetPlayerList()
end

function getRealPlayerCount()
    if playerCountManual == nil then
        playerCountManual = getPlayerCount()
    end
    return playerCountManual
end

function evaluatePlayers()
    local count = getRealPlayerCount()
    local allowedTotal = maxPlayersAllowed

    if count <= allowedTotal then
        if not pnbStarted then
            LogToConsole("`9Jumlah pemain aman `c("..count.."/"..allowedTotal.."), `2PnB lanjut.")
        end
        pnbStarted = true
    else
        if pnbStarted then
            LogToConsole("`9Terlalu banyak pemain `c("..count.."/"..allowedTotal.."), `4PnB berhenti.")
        end
        pnbStarted = false
    end

    needCheck = false
end

function autoWork()
    while true do

        if needCheck then
            evaluatePlayers()
        end

        if pnbStarted then
            local px = math.floor(GetLocal().pos.x / 32)
            local py = math.floor(GetLocal().pos.y / 32)

            for i = 1, far do
                place(px + i, py)
            end

            Sleep(delay)
            punch(px + 1, py)
            Sleep(150)
            punch(px + (1 + far / 2), py)
            Sleep(delay)
        else
            Sleep(delay)
        end
    end
end

AddHook("OnDraw", "pnb_imgui", function()
    if not showUI then return end
        if ImGui.Begin("PnB Controller @Lent", true) then
            ImGui.TextColored(ImVec4(1, 1, 1, 1), "Script by")
            ImGui.SameLine()
            ImGui.TextColored(ImVec4(1, 0.7, 0, 1), "@Lent")
            ImGui.Separator()
    
            ImGui.Separator()
            ImGui.Text("Settings:")

            local regionWidth = ImGui.GetContentRegionAvail().x
            local halfWidth = regionWidth / 2

            ImGui.PushItemWidth(halfWidth / 1.5)
            ImGui.Text("Item ID")
            ImGui.SameLine()
            _, itemid = ImGui.InputInt("##ItemID", itemid)
            ImGui.Spacing()
            ImGui.Text("Max Players")
            ImGui.SameLine()
            _, maxPlayersAllowed = ImGui.InputInt("##MaxPlayersAllowed", maxPlayersAllowed)
            ImGui.Spacing()
            ImGui.Text("Delay (ms)")
            ImGui.SameLine()
            _, delay = ImGui.InputInt("##Delay", delay)
            ImGui.SameLine()
            ImGui.Text("<50 rawan dc")
            ImGui.Spacing()
            ImGui.Text("Far")
            ImGui.SameLine()
            _, far = ImGui.InputInt("##Far", far)
            ImGui.PopItemWidth()

            ImGui.Separator()

        if pnbStarted then
            if ImGui.Button("⏹ Stop PnB", ImVec2(150, 30)) then
                pnbStarted = false
                Overlay("`4PnB Stopped!")
            end
        else
            if ImGui.Button("▶ Start PnB", ImVec2(150, 30)) then
                pnbStarted = true
                Overlay("`2PnB Started!")
                RunThread(function() autoWork() end)
            end
        end

            if ImGui.Button("Close Menu") then
                showUI = false
            end
            ImGui.End()
        end
end)

warn("`w[`2MADE by "..credit.."`w] `4DO NOT RESELL!!")
Sleep(2000)