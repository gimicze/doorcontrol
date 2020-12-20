--================================--
--       DoorControl v1.1.4       --
--           (by GIMI)            --
--      License: GNU GPL 3.0      --
--================================--

Config = {}

Config.enabledByDefault = true

Config.Vehicle = {
    searchRadius = 1.0,
    blacklist = { -- Vehicle model names to be ignored by the script
        "stretcher"
    }
}

Config.Text = {
    scale = 0.5,
    font = 4,
    background = true
}

--================================--
--        SCRIPT VARIABLES        --
--================================--

local nearestVehicle, nearestDoorIndex, nearestDoorCoords, nearestDoorDistance = nil
local playerCoords = nil
local playerPed = nil

--[[
    Door Index Legend:
    ------------------
    0 = Front Left Door  
    1 = Front Right Door  
    2 = Back Left Door  
    3 = Back Right Door  
    4 = Hood  
    5 = Trunk  
    6 = Back  
    7 = Back2 
]]

local doorBones = {
    "door_dside_f",
    "door_pside_f",
    "door_dside_r",
    "door_pside_r",
    "bonnet",
    "boot"
}

--================================--
--       PROCESS BLACKLIST        --
--================================--

local newBlacklist = {}

for k, v in pairs(Config.Vehicle.blacklist) do
    newBlacklist[GetHashKey(v)] = true
end

Config.Vehicle.blacklist, newBlacklist = newBlacklist, nil

local checkBlacklist = next(Config.Vehicle.blacklist) ~= nil

--================================--
--            THREADS             --
--================================--

function init()
    local runThreads = true
    Citizen.CreateThread(
        function()
            while runThreads do
                Citizen.Wait(300)

                playerPed = GetPlayerPed(-1)
                if not IsPedInAnyVehicle(playerPed, true) then
                    playerCoords = GetEntityCoords(playerPed)
                    nearestVehicle = GetNearestVehicle()

                    if nearestVehicle and (checkBlacklist and not Config.Vehicle.blacklist[GetEntityModel(nearestVehicle)]) and GetVehicleDoorLockStatus(nearestVehicle) == 1 then
                        local nearestDoorIndexTemp, nearestDoorDistanceTemp, nearestDoorCoordsTemp = nil
                        for doorIndex, boneName in pairs(doorBones) do
                            Citizen.Wait(10)
                            
                            local boneIndex = GetEntityBoneIndexByName(nearestVehicle, boneName)
                            
                            if boneIndex ~= -1 then
                                local doorCoords = GetWorldPositionOfEntityBone(nearestVehicle, boneIndex)
                                if doorIndex < 5 then
                                    doorCoords = doorCoords + GetEntityForwardVector(nearestVehicle) * -1
                                end
                                local distance = #(playerCoords - doorCoords)

                                if not nearestDoorIndexTemp or (nearestDoorDistanceTemp > distance) then
                                    nearestDoorIndexTemp = doorIndex - 1
                                    nearestDoorCoordsTemp = doorCoords
                                    nearestDoorDistanceTemp = distance
                                end
                            end
                        end
                        nearestDoorIndex, nearestDoorCoords, nearestDoorDistance = nearestDoorIndexTemp, nearestDoorCoordsTemp, nearestDoorDistanceTemp
                    elseif nearestDoorIndex then
                        nearestVehicle, nearestDoorDistance, nearestDoorIndex, nearestDoorCoords = nil
                    end
                else
                    if nearestDoorIndex then
                        nearestVehicle, nearestDoorDistance, nearestDoorIndex, nearestDoorCoords = nil
                    end
                    Citizen.Wait(1000)
                end
            end
        end
    )

    Citizen.CreateThread(
        function()
            while runThreads do
                Citizen.Wait(0)
                if nearestVehicle and nearestDoorIndex then
                    DrawTextThisFrame("[E] Open / Close", nearestDoorCoords)
                    if nearestDoorIndex < 4 and GetVehicleDoorAngleRatio(nearestVehicle, nearestDoorIndex) > 0.1 then
                        DrawTextThisFrame("[G] Roll down / up", nearestDoorCoords + vector3(0, 0, tonumber(GetTextScaleHeight(Config.Text.scale, Config.Text.font)) * 6.0))
                    end
                else
                    Citizen.Wait(1000)
                end
            end
        end
    )

    return function()
        runThreads = false
    end
end

local stopThreads = ((Config.enabledByDefault and GetResourceKvpString("enabled") == nil) or GetResourceKvpString("enabled") == "true") and init() or nil

--================================--
--            KEYBINDS            --
--================================--

RegisterCommand(
    '+door',
    function()
        if stopThreads and nearestDoorIndex then
            RequestControlOfEntity(nearestVehicle)
            if GetVehicleDoorAngleRatio(nearestVehicle, nearestDoorIndex) > 0.1 then
                SetVehicleDoorShut(nearestVehicle, nearestDoorIndex, false)
            else
                if nearestDoorIndex == 0 then
                    TaskOpenVehicleDoor(playerPed, nearestVehicle, 1.0, nearestDoorIndex, 1.0)
                else
                    SetVehicleDoorOpen(nearestVehicle, nearestDoorIndex, false, false)
                end
            end
        end
    end,
    false
)

RegisterCommand(
    '-door',
    function() end,
    false
)

RegisterKeyMapping('+door', 'Open / close the nearest door', 'keyboard', 'e')

RegisterCommand(
    '+window',
    function()
        if stopThreads and nearestDoorIndex and nearestDoorIndex < 4 and GetVehicleDoorAngleRatio(nearestVehicle, nearestDoorIndex) > 0.1 then
            RequestControlOfEntity(nearestVehicle)
            if IsVehicleWindowIntact(nearestVehicle, nearestDoorIndex) then
                RollDownWindow(nearestVehicle, nearestDoorIndex)
            else
                RollUpWindow(nearestVehicle, nearestDoorIndex)
            end
        end
    end,
    false
)

RegisterCommand(
    '-window',
    function() end,
    false
)

RegisterKeyMapping('+window', 'Roll up / down the nearest window', 'keyboard', 'g')

--================================--
--            COMMANDS            --
--================================--

RegisterCommand(
    'doorcontrol',
    function()
        SwitchControls()
    end,
    false
)

RegisterCommand(
    'dc',
    function()
        SwitchControls()
    end,
    false
)

--================================--
--           FUNCTIONS            --
--================================--

function SwitchControls()
    if stopThreads then
        stopThreads()
        stopThreads = nil
        SetResourceKvp("enabled", "false")
    else
        stopThreads = init()
        SetResourceKvp("enabled", "true")
    end
end

function GetNearestVehicle()
    if not (playerCoords and playerPed) then
        return
    end

    local pointB = GetEntityForwardVector(playerPed) * 0.001 + playerCoords

    local shapeTest = StartShapeTestCapsule(playerCoords.x, playerCoords.y, playerCoords.z, pointB.x, pointB.y, pointB.z, Config.Vehicle.searchRadius, 10, playerPed, 7)
    local _, hit, _, _, entity = GetShapeTestResult(shapeTest)

    return (hit == 1 and IsEntityAVehicle(entity)) and entity or false
end

function RequestControlOfEntity(entity, limit)
    limit = limit or 20
    local counter = 0
    if not NetworkHasControlOfEntity(entity) then
        NetworkRequestControlOfEntity(entity)
        Citizen.Wait(50)
        while not NetworkHasControlOfEntity(entity) and counter >= limit do
            counter = counter + 1
            Citizen.Wait(50)
        end
    end
end

function DrawTextThisFrame(text, coords, scale)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(table.unpack(coords))

    scale = scale or Config.Text.scale

    if onScreen then
        SetTextFont(Config.Text.font)
        SetColourOfNextTextComponent(000)
        SetTextCentre(true)
        SetTextScale(0.01, scale)

        SetTextEntry("STRING")
        AddTextComponentString(text)
        EndTextCommandDisplayText(x, y)

        local height = GetTextScaleHeight(scale, Config.Text.font)
        local width = text:len() * 0.0075 * scale

        if Config.Text.background then
            DrawRect(x, y + scale / 30, width + 0.020, height + 0.010, 0 --[[ R ]], 0 --[[ G ]], 0 --[[ B ]], 60 --[[ alpha ]])
        end
    end
end