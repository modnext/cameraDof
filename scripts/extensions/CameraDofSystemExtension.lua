--
-- CameraDofSystemExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

CameraDofSystemExtension = {}

---Return the active system while the mod is loaded
function CameraDofSystemExtension.getActiveSystem()
  local system = CameraManager ~= nil and CameraManager.cameraDofSystem or nil

  if system ~= nil and g_modIsLoaded ~= nil and g_modIsLoaded[modName] then
    return system
  end

  return nil
end

---Handle active camera changes
function CameraDofSystemExtension.onSetActiveCamera(_, cameraNode)
  local system = CameraDofSystemExtension.getActiveSystem()

  if system ~= nil then
    system:onActiveCameraChanged(cameraNode)
  end
end

---Assign profiles to initialized player cameras
function CameraDofSystemExtension.onInitialiseCameraNodes(playerCamera)
  local system = CameraDofSystemExtension.getActiveSystem()

  if system ~= nil then
    system:assignPlayerCamera(playerCamera)
  end
end

---Assign a profile after loading a vehicle camera
function CameraDofSystemExtension.onVehicleCameraLoadFromXML(vehicleCamera, superFunc, xmlFile, key, savegame, cameraIndex)
  local result = superFunc(vehicleCamera, xmlFile, key, savegame, cameraIndex)
  local system = CameraDofSystemExtension.getActiveSystem()

  if result and system ~= nil then
    system:assignVehicleCamera(vehicleCamera)
  end

  return result
end

---Apply the profile of an activated vehicle camera
function CameraDofSystemExtension.onVehicleCameraActivate(vehicleCamera)
  local system = CameraDofSystemExtension.getActiveSystem()

  if system ~= nil then
    system:assignVehicleCamera(vehicleCamera)
    system:applyActiveCamera()
  end
end

---Register the settings action for a player input context
function CameraDofSystemExtension.onRegisterGlobalPlayerActionEvents(playerInputComponent, contextName)
  local system = CameraDofSystemExtension.getActiveSystem()

  if system ~= nil then
    system:registerGlobalPlayerActionEvents(playerInputComponent, contextName)
  end
end

---Install game function hooks once
function CameraDofSystemExtension.install(system)
  if CameraManager ~= nil and CameraManager.cameraDofSystem ~= system then
    local previousSystem = CameraManager.cameraDofSystem

    if previousSystem ~= nil then
      previousSystem:unregisterActionEvents()
      removeModEventListener(previousSystem)
    end

    CameraManager.cameraDofSystem = system
  end

  if CameraManager ~= nil and not CameraManager.cameraDofPatched then
    CameraManager.cameraDofPatched = true
    CameraManager.setActiveCamera = Utils.appendedFunction(CameraManager.setActiveCamera, CameraDofSystemExtension.onSetActiveCamera)
  end

  if PlayerCamera ~= nil and not PlayerCamera.cameraDofPatched then
    PlayerCamera.cameraDofPatched = true
    PlayerCamera.initialiseCameraNodes = Utils.appendedFunction(PlayerCamera.initialiseCameraNodes, CameraDofSystemExtension.onInitialiseCameraNodes)
  end

  if VehicleCamera ~= nil and not VehicleCamera.cameraDofPatched then
    VehicleCamera.cameraDofPatched = true
    VehicleCamera.loadFromXML = Utils.overwrittenFunction(VehicleCamera.loadFromXML, CameraDofSystemExtension.onVehicleCameraLoadFromXML)
    VehicleCamera.onActivate = Utils.appendedFunction(VehicleCamera.onActivate, CameraDofSystemExtension.onVehicleCameraActivate)
  end

  if PlayerInputComponent ~= nil and not PlayerInputComponent.cameraDofPatched then
    PlayerInputComponent.cameraDofPatched = true
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, CameraDofSystemExtension.onRegisterGlobalPlayerActionEvents)
  end
end

---
CameraDofSystemExtension.install(g_cameraDofSystem)
