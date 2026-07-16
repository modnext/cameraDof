--
-- CameraDofSystem
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

local modSettingsDirectory = g_modSettingsDirectory

CameraDofSystem = {}

---
CameraDofSystem.PROFILE = {
  VEHICLE_FIRST_PERSON = "vehicleFirstPerson",
  VEHICLE_THIRD_PERSON = "vehicleThirdPerson",
  PLAYER_FIRST_PERSON = "playerFirstPerson",
  PLAYER_THIRD_PERSON = "playerThirdPerson",
}

---
CameraDofSystem.PROFILE_ORDER = {
  CameraDofSystem.PROFILE.VEHICLE_FIRST_PERSON,
  CameraDofSystem.PROFILE.VEHICLE_THIRD_PERSON,
  CameraDofSystem.PROFILE.PLAYER_FIRST_PERSON,
  CameraDofSystem.PROFILE.PLAYER_THIRD_PERSON,
}

---
CameraDofSystem.DEFAULT_PROFILES = {
  [CameraDofSystem.PROFILE.VEHICLE_FIRST_PERSON] = {
    enabled = true,
    nearEnabled = false,
    nearCoCRadius = 0.8,
    nearBlurEnd = 0.5,
    farCoCRadius = 0.2,
    farBlurStart = 1000,
    farBlurEnd = 1400,
    applyToSky = false,
  },
  [CameraDofSystem.PROFILE.VEHICLE_THIRD_PERSON] = {
    enabled = true,
    nearEnabled = false,
    nearCoCRadius = 0.5,
    nearBlurEnd = 1,
    farCoCRadius = 0.3,
    farBlurStart = 400,
    farBlurEnd = 1400,
    applyToSky = false,
  },
  [CameraDofSystem.PROFILE.PLAYER_FIRST_PERSON] = {
    enabled = true,
    nearEnabled = false,
    nearCoCRadius = 0.8,
    nearBlurEnd = 0.5,
    farCoCRadius = 0,
    farBlurStart = 1000,
    farBlurEnd = 1400,
    applyToSky = false,
  },
  [CameraDofSystem.PROFILE.PLAYER_THIRD_PERSON] = {
    enabled = true,
    nearEnabled = false,
    nearCoCRadius = 0.5,
    nearBlurEnd = 4,
    farCoCRadius = 0.3,
    farBlurStart = 30,
    farBlurEnd = 200,
    applyToSky = false,
  },
}

local CameraDofSystem_mt = Class(CameraDofSystem)

---Create a new camera blur system instance
function CameraDofSystem.new()
  local self = setmetatable({}, CameraDofSystem_mt)

  self.profiles = {}
  self.isDirty = false
  self.actionEventIds = {}
  self.lastActiveCameraNode = nil

  self:resetToDefaults(false)
  self:loadFromXMLFile()
  self:installPatches()

  return self
end

---Copy a DOF profile
-- @param table profile source profile
-- @return table copy copied profile
function CameraDofSystem.copyProfile(profile)
  return {
    enabled = profile.enabled == true,
    nearEnabled = profile.nearEnabled == true,
    nearCoCRadius = profile.nearCoCRadius,
    nearBlurEnd = profile.nearBlurEnd,
    farCoCRadius = profile.farCoCRadius,
    farBlurStart = profile.farBlurStart,
    farBlurEnd = profile.farBlurEnd,
    applyToSky = profile.applyToSky == true,
  }
end

---Reset all profiles to built-in defaults
-- @param boolean markDirty mark settings as changed
function CameraDofSystem:resetToDefaults(markDirty)
  for _, profileKey in ipairs(CameraDofSystem.PROFILE_ORDER) do
    self.profiles[profileKey] = CameraDofSystem.copyProfile(CameraDofSystem.DEFAULT_PROFILES[profileKey])
    self:normalizeProfile(self.profiles[profileKey], profileKey)
  end

  if markDirty then
    self:markDirty()
    self:applyAllProfileChanges()
  end
end

---Reset a single profile to defaults
-- @param string profileKey profile id
function CameraDofSystem:resetProfile(profileKey)
  local defaultProfile = CameraDofSystem.DEFAULT_PROFILES[profileKey]

  if defaultProfile == nil then
    return
  end

  self.profiles[profileKey] = CameraDofSystem.copyProfile(defaultProfile)
  self:normalizeProfile(self.profiles[profileKey], profileKey)
  self:markDirty()
  self:applyProfileToAssignedCameras(profileKey)
  self:applyActiveCamera()
end

---Keep dependent profile values in a valid range
-- @param table profile DOF profile
-- @param string|nil profileKey profile id
-- @return boolean changed true if profile was adjusted
function CameraDofSystem:normalizeProfile(profile, profileKey)
  local changed = false

  if profile == nil then
    return changed
  end

  if type(profile.nearCoCRadius) == "number" and profile.nearCoCRadius < 0.05 then
    profile.nearCoCRadius = 0.05
    changed = true
  end

  if type(profile.nearBlurEnd) == "number" and type(profile.nearCoCRadius) == "number" and profile.nearBlurEnd < profile.nearCoCRadius + 0.05 then
    profile.nearBlurEnd = profile.nearCoCRadius + 0.05
    changed = true
  end

  if type(profile.farBlurEnd) == "number" and type(profile.farBlurStart) == "number" and profile.farBlurEnd < profile.farBlurStart + 10 then
    profile.farBlurEnd = profile.farBlurStart + 10
    changed = true
  end

  return changed
end

---Mark settings as changed
function CameraDofSystem:markDirty()
  self.isDirty = true
end

---Get profile data
-- @param string profileKey profile id
-- @return table|nil profile data
function CameraDofSystem:getProfile(profileKey)
  return self.profiles[profileKey]
end

---Set a single profile value
-- @param string profileKey profile id
-- @param string name value name
-- @param any value new value
function CameraDofSystem:setProfileValue(profileKey, name, value)
  local profile = self.profiles[profileKey]

  if profile == nil or profile[name] == nil then
    return
  end

  if type(profile[name]) == "number" then
    value = tonumber(value)

    if value == nil then
      return
    end
  elseif type(profile[name]) == "boolean" then
    value = value == true
  end

  if profile[name] == value then
    return
  end

  profile[name] = value
  self:normalizeProfile(profile, profileKey)
  self:markDirty()
  self:applyProfileToAssignedCameras(profileKey)
  self:applyActiveCamera()
end

---Create a DepthOfFieldManager info table from profile
-- @param table profile DOF profile
-- @return table dofInfo camera manager DOF info
function CameraDofSystem:createDofInfo(profile)
  if g_depthOfFieldManager ~= nil and g_depthOfFieldManager.createInfo ~= nil then
    return g_depthOfFieldManager:createInfo(
      profile.nearCoCRadius,
      profile.nearBlurEnd,
      profile.farCoCRadius,
      profile.farBlurStart,
      profile.farBlurEnd,
      profile.applyToSky
    )
  end

  return {
    nearCoCRadius = profile.nearCoCRadius,
    nearBlurEnd = profile.nearBlurEnd,
    farCoCRadius = profile.farCoCRadius,
    farBlurStart = profile.farBlurStart,
    farBlurEnd = profile.farBlurEnd,
    applyToSky = profile.applyToSky,
  }
end

---Apply a profile to the renderer immediately
-- @param table profile DOF profile
function CameraDofSystem:applyProfile(profile)
  if g_depthOfFieldManager == nil then
    return
  end

  if setDofQuality ~= nil then
    setDofQuality(profile.nearEnabled and 2 or 1)
  end

  g_depthOfFieldManager:applyInfo(self:createDofInfo(profile))
end

---Apply a camera manager info object to the renderer
-- @param table cameraInfo camera manager entry
function CameraDofSystem:applyCameraInfo(cameraInfo)
  if g_depthOfFieldManager == nil or cameraInfo == nil then
    return
  end

  if cameraInfo.dofInfo == nil then
    g_depthOfFieldManager:reset()
  else
    g_depthOfFieldManager:applyInfo(cameraInfo.dofInfo)
  end
end

---Assign a profile to a camera manager node
-- @param integer cameraNode camera node id
-- @param string profileKey profile id
function CameraDofSystem:assignCameraProfile(cameraNode, profileKey)
  if g_cameraManager == nil or cameraNode == nil or profileKey == nil then
    return
  end

  local cameraInfo = g_cameraManager.cameraInfo[cameraNode]

  if cameraInfo == nil then
    return
  end

  if cameraInfo.cameraDofOriginalDofStored ~= true then
    cameraInfo.cameraDofOriginalDofInfo = cameraInfo.dofInfo
    cameraInfo.cameraDofOriginalDofStored = true
  end

  cameraInfo.cameraDofAssignedProfileKey = profileKey
  self:updateCameraInfoDof(cameraInfo)
end

---Update camera manager DOF info from its assigned profile
-- @param table cameraInfo camera manager entry
function CameraDofSystem:updateCameraInfoDof(cameraInfo)
  if cameraInfo == nil then
    return
  end

  local profile = self.profiles[cameraInfo.cameraDofAssignedProfileKey]

  if profile ~= nil and profile.enabled then
    cameraInfo.dofInfo = self:createDofInfo(profile)
  else
    cameraInfo.dofInfo = cameraInfo.cameraDofOriginalDofInfo
  end
end

---Assign profiles to all known player camera nodes
-- @param table playerCamera PlayerCamera instance
function CameraDofSystem:assignPlayerCamera(playerCamera)
  if playerCamera == nil then
    return
  end

  self:assignCameraProfile(playerCamera.firstPersonCamera, CameraDofSystem.PROFILE.PLAYER_FIRST_PERSON)
  self:assignCameraProfile(playerCamera.thirdPersonCamera, CameraDofSystem.PROFILE.PLAYER_THIRD_PERSON)
  self:assignCameraProfile(playerCamera.thirdPersonConversationCamera, CameraDofSystem.PROFILE.PLAYER_THIRD_PERSON)
end

---Assign a profile to a vehicle camera
-- @param table vehicleCamera VehicleCamera instance
function CameraDofSystem:assignVehicleCamera(vehicleCamera)
  if vehicleCamera == nil then
    return
  end

  local profileKey = vehicleCamera.isInside and CameraDofSystem.PROFILE.VEHICLE_FIRST_PERSON or CameraDofSystem.PROFILE.VEHICLE_THIRD_PERSON

  self:assignCameraProfile(vehicleCamera.cameraNode, profileKey)
end

---Apply a changed profile to all already assigned cameras
-- @param string profileKey profile id
function CameraDofSystem:applyProfileToAssignedCameras(profileKey)
  if g_cameraManager == nil then
    return
  end

  for _, cameraInfo in pairs(g_cameraManager.cameraInfo) do
    if cameraInfo.cameraDofAssignedProfileKey == profileKey then
      self:updateCameraInfoDof(cameraInfo)
    end
  end
end

---Apply all known profile values to assigned cameras
function CameraDofSystem:applyAllProfileChanges()
  if g_cameraManager == nil then
    return
  end

  for _, cameraInfo in pairs(g_cameraManager.cameraInfo) do
    if cameraInfo.cameraDofAssignedProfileKey ~= nil then
      self:updateCameraInfoDof(cameraInfo)
    end
  end
end

---Detect the profile for a camera node from current player/vehicle state
-- @param integer cameraNode camera node id
-- @return string|nil profileKey profile id
function CameraDofSystem:detectProfileKeyForCamera(cameraNode)
  if cameraNode == nil then
    return nil
  end

  if g_localPlayer ~= nil and g_localPlayer.camera ~= nil then
    local playerCamera = g_localPlayer.camera

    if cameraNode == playerCamera.firstPersonCamera then
      return CameraDofSystem.PROFILE.PLAYER_FIRST_PERSON
    elseif cameraNode == playerCamera.thirdPersonCamera or cameraNode == playerCamera.thirdPersonConversationCamera then
      return CameraDofSystem.PROFILE.PLAYER_THIRD_PERSON
    end
  end

  if g_activeVehicleCamera ~= nil and g_activeVehicleCamera.cameraNode == cameraNode then
    return g_activeVehicleCamera.isInside and CameraDofSystem.PROFILE.VEHICLE_FIRST_PERSON or CameraDofSystem.PROFILE.VEHICLE_THIRD_PERSON
  end

  if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
    local vehicle = g_localPlayer:getCurrentVehicle()

    if vehicle ~= nil and vehicle.getActiveCamera ~= nil then
      local activeCamera = vehicle:getActiveCamera()

      if activeCamera ~= nil and activeCamera.cameraNode == cameraNode then
        return activeCamera.isInside and CameraDofSystem.PROFILE.VEHICLE_FIRST_PERSON or CameraDofSystem.PROFILE.VEHICLE_THIRD_PERSON
      end
    end
  end

  return nil
end

---Get the profile key matching the currently active camera
-- @return string|nil profileKey profile id
function CameraDofSystem:getActiveProfileKey()
  local cameraNode = nil

  if g_cameraManager ~= nil then
    cameraNode = g_cameraManager.activeCameraNode
  end

  cameraNode = cameraNode or self.lastActiveCameraNode

  if cameraNode == nil then
    return nil
  end

  if g_cameraManager ~= nil then
    local cameraInfo = g_cameraManager.cameraInfo[cameraNode]

    if cameraInfo ~= nil and cameraInfo.cameraDofAssignedProfileKey ~= nil then
      return cameraInfo.cameraDofAssignedProfileKey
    end
  end

  return self:detectProfileKeyForCamera(cameraNode)
end

---Called after CameraManager sets an active camera
-- @param integer cameraNode active camera node
function CameraDofSystem:onActiveCameraChanged(cameraNode)
  if g_cameraManager == nil or cameraNode == nil then
    return
  end

  local cameraInfo = g_cameraManager.cameraInfo[cameraNode]

  if cameraInfo == nil then
    return
  end

  local profileKey = cameraInfo.cameraDofAssignedProfileKey or self:detectProfileKeyForCamera(cameraNode)

  if profileKey ~= nil then
    self:assignCameraProfile(cameraNode, profileKey)
  end

  profileKey = cameraInfo.cameraDofAssignedProfileKey
  local profile = self.profiles[profileKey]

  if profile ~= nil and profile.enabled then
    self:applyProfile(profile)
  else
    self:applyCameraInfo(cameraInfo)
  end

  self.lastActiveCameraNode = cameraNode
end

---Apply the currently active camera again
function CameraDofSystem:applyActiveCamera()
  if g_cameraManager ~= nil then
    self:onActiveCameraChanged(g_cameraManager.activeCameraNode)
  end
end

---Scan already loaded player and vehicle cameras
function CameraDofSystem:applyAllKnownCameras()
  if g_localPlayer ~= nil and g_localPlayer.camera ~= nil then
    self:assignPlayerCamera(g_localPlayer.camera)
  end

  if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
      local spec = vehicle.spec_enterable

      if spec ~= nil and spec.cameras ~= nil then
        for _, camera in ipairs(spec.cameras) do
          self:assignVehicleCamera(camera)
        end
      end
    end
  end

  self:applyActiveCamera()
end

---Install class hooks once
---
---The guard flag has to live on the same objects that are patched. The mod's Lua
---environment is re-created on every mission load, so `CameraDofSystem` (and any
---flag on it) is a fresh table each time, while the engine classes below persist
---for the whole process along with the wrappers already installed on them.
function CameraDofSystem:installPatches()
  if CameraManager ~= nil and not CameraManager.cameraDofPatched then
    CameraManager.cameraDofPatched = true

    CameraManager.setActiveCamera = Utils.appendedFunction(CameraManager.setActiveCamera, function(_, cameraNode)
      if g_cameraDofSystem ~= nil then
        g_cameraDofSystem:onActiveCameraChanged(cameraNode)
      end
    end)
  end

  if PlayerCamera ~= nil and not PlayerCamera.cameraDofPatched then
    PlayerCamera.cameraDofPatched = true

    PlayerCamera.initialiseCameraNodes = Utils.appendedFunction(PlayerCamera.initialiseCameraNodes, function(playerCamera)
      if g_cameraDofSystem ~= nil then
        g_cameraDofSystem:assignPlayerCamera(playerCamera)
      end
    end)
  end

  if VehicleCamera ~= nil and not VehicleCamera.cameraDofPatched then
    VehicleCamera.cameraDofPatched = true

    VehicleCamera.loadFromXML = Utils.overwrittenFunction(VehicleCamera.loadFromXML, function(vehicleCamera, superFunc, xmlFile, key, savegame, cameraIndex)
      local result = superFunc(vehicleCamera, xmlFile, key, savegame, cameraIndex)

      if result and g_cameraDofSystem ~= nil then
        g_cameraDofSystem:assignVehicleCamera(vehicleCamera)
      end

      return result
    end)

    VehicleCamera.onActivate = Utils.appendedFunction(VehicleCamera.onActivate, function(vehicleCamera)
      if g_cameraDofSystem ~= nil then
        g_cameraDofSystem:assignVehicleCamera(vehicleCamera)
        g_cameraDofSystem:applyActiveCamera()
      end
    end)
  end

  if PlayerInputComponent ~= nil and not PlayerInputComponent.cameraDofPatched then
    PlayerInputComponent.cameraDofPatched = true

    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function(playerInputComponent, contextName)
      if g_cameraDofSystem ~= nil then
        g_cameraDofSystem:registerGlobalPlayerActionEvents(playerInputComponent, contextName)
      end
    end)
  end
end

---Register global player action events for all player input contexts
function CameraDofSystem:registerGlobalPlayerActionEvents(playerInputComponent, contextName)
  if playerInputComponent == nil or playerInputComponent.player == nil or not playerInputComponent.player.isOwner then
    return
  end

  if g_inputBinding == nil or InputAction.CAMERA_DOF_SETTINGS == nil then
    return
  end

  local currentContextName = g_inputBinding:getContextName()
  local newContextName = contextName or currentContextName

  if currentContextName ~= newContextName then
    g_inputBinding:beginActionEventsModification(newContextName)
  end

  self:registerGlobalActionEvents(playerInputComponent.player, g_inputBinding)

  if currentContextName ~= newContextName then
    g_inputBinding:beginActionEventsModification(currentContextName)
  end
end

---Register action event for opening the dialog
function CameraDofSystem:registerGlobalActionEvents(player, inputBinding)
  if inputBinding == nil or InputAction.CAMERA_DOF_SETTINGS == nil then
    return
  end

  local _, actionEventId = inputBinding:registerActionEvent(InputAction.CAMERA_DOF_SETTINGS, self, self.onOpenSettingsAction, false, true, false, true)

  if actionEventId ~= nil then
    table.insert(self.actionEventIds, actionEventId)
    inputBinding:setActionEventTextVisibility(actionEventId, false)
    inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
  end
end

---Remove registered action events
function CameraDofSystem:unregisterActionEvents()
  if g_inputBinding ~= nil then
    g_inputBinding:removeActionEventsByTarget(self)
  end

  self.actionEventIds = {}
end

---Open settings dialog from input action
function CameraDofSystem:onOpenSettingsAction()
  if g_gui ~= nil and g_gui:getIsGuiVisible() then
    return
  end

  if CameraDofDialog ~= nil then
    CameraDofDialog.show(self:getActiveProfileKey())
  end
end

---Called by mod event listener on map load
function CameraDofSystem:loadMap()
  self:applyAllKnownCameras()
end

---Called by mod event listener on map delete
function CameraDofSystem:deleteMap()
  self:saveIfDirty()
  self:unregisterActionEvents()
  self.lastActiveCameraNode = nil
end

---Poll active camera as a fallback for camera changes not using CameraManager hooks
-- @param float dt delta time
function CameraDofSystem:update(dt)
  if g_cameraManager ~= nil and g_cameraManager.activeCameraNode ~= nil and g_cameraManager.activeCameraNode ~= self.lastActiveCameraNode then
    self:onActiveCameraChanged(g_cameraManager.activeCameraNode)
  end
end

---Load settings from XML
function CameraDofSystem:loadFromXMLFile()
  local xmlFilename = modSettingsDirectory .. "cameraDof.xml"
  local xmlFile = XMLFile.loadIfExists("CameraDofXML", xmlFilename)

  if xmlFile == nil then
    return
  end

  local revision = xmlFile:getInt("cameraDof#revision", 1)

  if revision > 1 then
    Logging.warning("CameraDof: settings xml revision '%d' is newer than supported revision '1'", revision)
  end

  for _, profileKey in ipairs(CameraDofSystem.PROFILE_ORDER) do
    local profile = self.profiles[profileKey]
    local key = "cameraDof." .. profileKey

    if profile ~= nil then
      profile.enabled = xmlFile:getBool(key .. "#enabled", profile.enabled)
      profile.nearEnabled = xmlFile:getBool(key .. "#nearEnabled", profile.nearEnabled)
      profile.nearCoCRadius = xmlFile:getFloat(key .. "#nearCoCRadius", profile.nearCoCRadius)
      profile.nearBlurEnd = xmlFile:getFloat(key .. "#nearBlurEnd", profile.nearBlurEnd)
      profile.farCoCRadius = xmlFile:getFloat(key .. "#farCoCRadius", profile.farCoCRadius)
      profile.farBlurStart = xmlFile:getFloat(key .. "#farBlurStart", profile.farBlurStart)
      profile.farBlurEnd = xmlFile:getFloat(key .. "#farBlurEnd", profile.farBlurEnd)
      profile.applyToSky = xmlFile:getBool(key .. "#applyToSky", profile.applyToSky)

      if self:normalizeProfile(profile, profileKey) then
        self:markDirty()
      end
    end
  end

  xmlFile:delete()
end

---Save settings only when changed
function CameraDofSystem:saveIfDirty()
  if self.isDirty then
    self:saveToXMLFile()
  end
end

---Save settings to XML
function CameraDofSystem:saveToXMLFile()
  local xmlFilename = modSettingsDirectory .. "cameraDof.xml"
  local xmlFile = XMLFile.create("CameraDofXML", xmlFilename, "cameraDof")

  if xmlFile == nil then
    Logging.warning("CameraDof: failed to create xml file at '%s'", xmlFilename)
    return
  end

  xmlFile:setInt("cameraDof#revision", 1)

  for _, profileKey in ipairs(CameraDofSystem.PROFILE_ORDER) do
    local profile = self.profiles[profileKey]
    local key = "cameraDof." .. profileKey

    xmlFile:setBool(key .. "#enabled", profile.enabled)
    xmlFile:setBool(key .. "#nearEnabled", profile.nearEnabled)
    xmlFile:setFloat(key .. "#nearCoCRadius", profile.nearCoCRadius)
    xmlFile:setFloat(key .. "#nearBlurEnd", profile.nearBlurEnd)
    xmlFile:setFloat(key .. "#farCoCRadius", profile.farCoCRadius)
    xmlFile:setFloat(key .. "#farBlurStart", profile.farBlurStart)
    xmlFile:setFloat(key .. "#farBlurEnd", profile.farBlurEnd)
    xmlFile:setBool(key .. "#applyToSky", profile.applyToSky)
  end

  xmlFile:save()
  xmlFile:delete()

  self.isDirty = false
end

---
g_cameraDofSystem = CameraDofSystem.new()
addModEventListener(g_cameraDofSystem)
