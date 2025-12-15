provider = "Chicken"  --[Chicken/Cow/Tackle/ATM]
delay = 200
worldType = "island" --[normal/nether/island]

showUI = true
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

if string.lower(worldType) == "normal" then
    sizeX, sizeY = 100, 60
elseif string.lower(worldType) == "nether" then
    sizeX, sizeY = 150, 150
elseif string.lower(worldType) == "island" then
    sizeX, sizeY = 200, 200
else
    sizeX, sizeY = 100, 60
end

if string.lower(provider) == "Chicken" then
    providerID = 872
elseif string.lower(provider) == "Cow" then
    providerID = 866
elseif string.lower(provider) == "Tackle" then
    providerID = 3044
elseif string.lower(provider) == "ATM" then
    providerID = 1008
elseif string.lower(provider) == "Coffee" then
    providerID = 1632
else
    warn("`4Masukkan Nama provider yang valid")
end

harvestTiles = {}
for x = 0, sizeX - 1 do
    for y = sizeY - 2, 0, -1 do
        local tileData = GetTile(x, y)
        if tileData and tileData.fg == providerID then
            table.insert(harvestTiles, { x = x, y = y })
        end
    end
end

for i = 1, 3 do
    for _, tile in pairs(harvestTiles) do
        local tileData = GetTile(tile.x, tile.y)
        if tileData and tileData.fg == providerID and tileData.extra and tileData.extra.progress == 1 then
            SendPacketRaw(false, { state = 32, x = tile.x * 32, y = tile.y * 32 })
            SendPacketRaw(false, { type = 3, value = 18, px = tile.x, py = tile.y, x = tile.x * 32, y = tile.y * 32 })
            SendPacketRaw(false, { state = 4196896, px = tile.x, py = tile.y, x = tile.x * 32, y = tile.y * 32 })
            SendPacketRaw(false, { state = 16779296, px = tile.x, py = tile.y, x = tile.x * 32, y = tile.y * 32 })
            Sleep(delay)
        end
    end
end

AddHook("OnDraw", "ht_provider_imgui", function()
    if not showUI then return end
        if ImGui.Begin("HT Provider @Lent", true) then
            ImGui.TextColored(ImVec4(1, 1, 1, 1), "Script by")
            ImGui.SameLine()
            ImGui.TextColored(ImVec4(1, 0.7, 0, 1), "@Lent")
            ImGui.Separator()
    
            ImGui.Separator()
            ImGui.Text("Settings:")

            local regionWidth = ImGui.GetContentRegionAvail().x
            local halfWidth = regionWidth / 2

            ImGui.PushItemWidth(halfWidth / 2)
            ImGui.Text("Provider")
            ImGui.SameLine()
            _, provider = ImGui.InputText("##Provider", provider, 64)
            ImGui.Spacing()
            ImGui.Text("World Type")
            ImGui.SameLine()
            _, worldType = ImGui.InputText("##WorldType", worldType, 64)
            ImGui.PopItemWidth()

            ImGui.Separator()

            if ImGui.Button("Close Menu") then
                showUI = false
            end
            ImGui.End()
        end
end)

warn("`w[`2MADE by "..credit.."`w] `4DO NOT RESELL!!")
Sleep(2000)
