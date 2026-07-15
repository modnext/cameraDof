--
-- CameraDofDialog
--
-- Author: aaw3k
-- Copyright (C) ModNext, All Rights Reserved.
--

local modDirectory = g_currentModDirectory

CameraDofDialog = {}

---
CameraDofDialog.SLIDER_CONFIGS = {
  nearCoCRadius = {
    min = 0.05,
    max = 2,
    step = 0.05,
    precision = 2,
    format = "%.2f",
  },
  nearBlurEnd = {
    min = 0,
    max = 20,
    step = 0.05,
    precision = 2,
    format = "%.2f m",
    minValueKey = "nearCoCRadius",
    minStepOffset = 1,
  },
  farCoCRadius = {
    min = 0,
    max = 2,
    step = 0.05,
    precision = 2,
    format = "%.2f",
  },
  farBlurStart = {
    min = 0,
    max = 3000,
    step = 10,
    precision = 0,
    format = "%.0f m",
  },
  farBlurEnd = {
    min = 0,
    max = 5000,
    step = 10,
    precision = 0,
    format = "%.0f m",
    minValueKey = "farBlurStart",
    minStepOffset = 1,
  },
}

local CameraDofDialog_mt = Class(CameraDofDialog, MessageDialog)

---Register dialog GUI
function CameraDofDialog.register()
  local dialog = CameraDofDialog.new()

  if g_gui ~= nil then
    g_gui:loadGui(modDirectory .. "gui/CameraDofDialog.xml", "CameraDofDialog", dialog)
  end

  CameraDofDialog.INSTANCE = dialog
end

---Show dialog
-- @param string|nil profileKey profile selected when opening
function CameraDofDialog.show(profileKey)
  if CameraDofDialog.INSTANCE ~= nil and g_gui ~= nil then
    if profileKey == nil and g_cameraDofSystem ~= nil then
      profileKey = g_cameraDofSystem:getActiveProfileKey()
    end

    CameraDofDialog.INSTANCE.pendingProfileKey = profileKey
    g_gui:showDialog("CameraDofDialog")
  end
end

---Create dialog instance
function CameraDofDialog.new(target, customMt)
  local self = CameraDofDialog:superClass().new(target, customMt or CameraDofDialog_mt)

  self.selectedProfileIndex = 1
  self.pendingProfileKey = nil
  self.blockCallbacks = false

  return self
end

---Get selected profile key
-- @return string profile key
function CameraDofDialog:getSelectedProfileKey()
  return CameraDofSystem.PROFILE_ORDER[self.selectedProfileIndex] or CameraDofSystem.PROFILE_ORDER[1]
end

---Get translated text or key fallback
-- @param string key l10n key
-- @return string text translated text
function CameraDofDialog:getText(key)
  if g_i18n ~= nil and g_i18n:hasText(key) then
    return g_i18n:getText(key)
  end

  return key
end

---Called when GUI is fully built
function CameraDofDialog:onGuiSetupFinished()
  CameraDofDialog:superClass().onGuiSetupFinished(self)

  if self.contentContainer ~= nil and self.headerText ~= nil and self.topLineLeft ~= nil and self.topLineRight ~= nil then
    local lineSize = (self.contentContainer.absSize[1] - self.headerText:getTextWidth()) / 2 - 20 * g_pixelSizeScaledX

    self.topLineLeft:setSize(lineSize, nil)
    self.topLineRight:setSize(lineSize, nil)
  end

  self:setupProfileSelector()
  self:setupSliders()
  self:updateControls()
end

---Called when dialog opens
function CameraDofDialog:onOpen()
  CameraDofDialog:superClass().onOpen(self)

  local pendingProfileKey = self.pendingProfileKey
  self.pendingProfileKey = nil

  if pendingProfileKey == nil or not self:selectProfileByKey(pendingProfileKey) then
    self:updateControls()
  end

  if self.profileSelector ~= nil then
    FocusManager:setFocus(self.profileSelector)
  elseif self.enabled ~= nil then
    FocusManager:setFocus(self.enabled)
  end
end

---Called when dialog closes
function CameraDofDialog:onClose()
  if g_cameraDofSystem ~= nil then
    g_cameraDofSystem:saveIfDirty()
  end

  CameraDofDialog:superClass().onClose(self)
end

---Setup profile selector options
function CameraDofDialog:setupProfileSelector()
  if self.profileSelector == nil then
    return
  end

  local texts = {}

  for _, profileKey in ipairs(CameraDofSystem.PROFILE_ORDER) do
    table.insert(texts, self:getText("cameraDof_profile_" .. profileKey))
  end

  self.profileSelector:setTexts(texts)
  self.profileSelector:setState(self.selectedProfileIndex, true)
end

---Setup slider value lists
function CameraDofDialog:setupSliders()
  self:updateSliderTexts()
end

---Refresh slider value lists
-- @param table|nil profile selected profile
function CameraDofDialog:updateSliderTexts(profile)
  for elementId, config in pairs(CameraDofDialog.SLIDER_CONFIGS) do
    local slider = self[elementId]

    if slider ~= nil then
      slider:setTexts(self:buildSliderTexts(config, self:getSliderMinValue(config, profile)))
    end
  end
end

---Build display texts for a slider
-- @param table config slider config
-- @param number|nil minValue dynamic min value
-- @return table texts display texts
function CameraDofDialog:buildSliderTexts(config, minValue)
  local texts = {}
  local index = 1
  local value = minValue or config.min

  while value <= config.max + config.step * 0.5 do
    texts[index] = string.format(config.format, self:roundValue(value, config.precision))
    index = index + 1
    value = value + config.step
  end

  return texts
end

---Get current slider minimum
-- @param table config slider config
-- @param table|nil profile selected profile
-- @return number minValue slider minimum value
function CameraDofDialog:getSliderMinValue(config, profile)
  local minValue = config.min

  if profile ~= nil and config.minValueKey ~= nil and type(profile[config.minValueKey]) == "number" then
    local profileMinValue = profile[config.minValueKey]
    local minStepOffset = config.minStepOffset or 0

    profileMinValue = profileMinValue + config.step * minStepOffset

    minValue = math.max(minValue, profileMinValue)
  end

  return self:roundValue(math.min(minValue, config.max), config.precision)
end

---Round a numeric value
-- @param number value value
-- @param integer precision decimal places
-- @return number rounded rounded value
function CameraDofDialog:roundValue(value, precision)
  local factor = 10 ^ (precision or 0)

  return math.floor(value * factor + 0.5) / factor
end

---Get slider index for value
-- @param number value numeric value
-- @param table config slider config
-- @param number|nil minValue dynamic min value
-- @return integer state slider state
function CameraDofDialog:getStateFromValue(value, config, minValue)
  minValue = minValue or config.min
  value = math.max(minValue, math.min(config.max, value or minValue))

  return math.floor((value - minValue) / config.step + 0.5) + 1
end

---Get value from slider index
-- @param integer state slider state
-- @param table config slider config
-- @param number|nil minValue dynamic min value
-- @return number value numeric value
function CameraDofDialog:getValueFromState(state, config, minValue)
  minValue = minValue or config.min

  local value = minValue + ((state or 1) - 1) * config.step
  value = math.max(minValue, math.min(config.max, value))

  return self:roundValue(value, config.precision)
end

---Refresh all controls from selected profile
function CameraDofDialog:updateControls()
  if g_cameraDofSystem == nil then
    return
  end

  local profileKey = self:getSelectedProfileKey()
  local profile = g_cameraDofSystem:getProfile(profileKey)

  if profile == nil then
    return
  end

  self.blockCallbacks = true

  self:updateSliderTexts(profile)

  if self.profileSelector ~= nil then
    self.profileSelector:setState(self.selectedProfileIndex, true)
  end

  self:setBinaryOptionChecked(self.enabled, profile.enabled, true)
  self:setBinaryOptionChecked(self.nearEnabled, profile.nearEnabled, true)
  self:setBinaryOptionChecked(self.applyToSky, profile.applyToSky, true)

  for elementId, config in pairs(CameraDofDialog.SLIDER_CONFIGS) do
    local slider = self[elementId]

    if slider ~= nil then
      slider:setState(self:getStateFromValue(profile[elementId], config, self:getSliderMinValue(config, profile)), true)
    end
  end

  self:updateControlAvailability(profile)

  self.blockCallbacks = false
end

---Set a binary option without interrupting its current animation
-- @param table|nil element binary option element
-- @param boolean checked checked state
-- @param boolean skipAnimation skip animation if state must be synced
function CameraDofDialog:setBinaryOptionChecked(element, checked, skipAnimation)
  if element ~= nil and element.setIsChecked ~= nil then
    if element.getIsChecked == nil or element:getIsChecked() ~= checked then
      element:setIsChecked(checked, skipAnimation)
    end
  end
end

---Set a GUI element disabled state when available
-- @param table|nil element GUI element
-- @param boolean disabled disabled state
function CameraDofDialog:setElementDisabled(element, disabled)
  if element ~= nil and element.setDisabled ~= nil then
    element:setDisabled(disabled)
  end
end

---Refresh enabled/disabled state for profile controls
-- @param table profile selected profile
function CameraDofDialog:updateControlAvailability(profile)
  local profileDisabled = not profile.enabled
  local nearDisabled = profileDisabled or not profile.nearEnabled

  self:setElementDisabled(self.nearEnabled, profileDisabled)
  self:setElementDisabled(self.farCoCRadius, profileDisabled)
  self:setElementDisabled(self.farBlurStart, profileDisabled)
  self:setElementDisabled(self.farBlurEnd, profileDisabled)
  self:setElementDisabled(self.applyToSky, profileDisabled)
  self:setElementDisabled(self.nearCoCRadius, nearDisabled)
  self:setElementDisabled(self.nearBlurEnd, nearDisabled)
end

---Select a profile by profile key
-- @param string profileKey profile id
-- @return boolean selected true if profile was found
function CameraDofDialog:selectProfileByKey(profileKey)
  for index, key in ipairs(CameraDofSystem.PROFILE_ORDER) do
    if key == profileKey then
      self:selectProfile(index)
      return true
    end
  end

  return false
end

---Select a profile
-- @param integer index profile index
function CameraDofDialog:selectProfile(index)
  if CameraDofSystem.PROFILE_ORDER[index] == nil then
    return
  end

  self.selectedProfileIndex = index
  self:updateControls()
end

---Handle profile selector change
-- @param integer state selected profile state
function CameraDofDialog:onClickProfileSelector(state)
  if self.blockCallbacks then
    return
  end

  self:selectProfile(state)
end

---Handle slider change
-- @param integer state slider state
-- @param table element slider element
function CameraDofDialog:onSliderChanged(state, element)
  if self.blockCallbacks or g_cameraDofSystem == nil or element == nil then
    return
  end

  local config = CameraDofDialog.SLIDER_CONFIGS[element.id]
  local profile = g_cameraDofSystem:getProfile(self:getSelectedProfileKey())

  if config == nil or profile == nil then
    return
  end

  local value = self:getValueFromState(state, config, self:getSliderMinValue(config, profile))

  g_cameraDofSystem:setProfileValue(self:getSelectedProfileKey(), element.id, value)
  self:updateControls()
end

---Handle toggle change
-- @param integer state toggle state
-- @param table element toggle element
function CameraDofDialog:onToggleChanged(_, element)
  if self.blockCallbacks or g_cameraDofSystem == nil or element == nil then
    return
  end

  g_cameraDofSystem:setProfileValue(self:getSelectedProfileKey(), element.id, element:getIsChecked())
  self:updateControls()
end

---Reset selected profile
function CameraDofDialog:onClickReset()
  if g_cameraDofSystem ~= nil then
    g_cameraDofSystem:resetProfile(self:getSelectedProfileKey())
    self:updateControls()
  end
end

---Close dialog
function CameraDofDialog:onClickBack()
  if g_cameraDofSystem ~= nil then
    g_cameraDofSystem:saveIfDirty()
  end

  self:close()

  return false
end

---
CameraDofDialog.register()
