--EasyCue by Andrew Tomlin & Nick Jackson
--v0.1.0, December 2018, initial draft
--v0.3.1, January 2020, more trigger types, rehearsal points, etc
--v1.0.1, March 2020, tired of calling this a beta

--[[

Quick Start Guide:

TODO fill with guide

]]
--------------------------
--  TABLE OF CONTENTS   --
--------------------------
--[[

To quickly jump to any of these, search for the text case-sensitively

GLOSSARY
SCRIPT STARTUP
LOGGING
PREFERENCES
COMPONENTS
BACK-END FUNCTIONS
ACTION FUNCTIONS
FUNCTION LIST
PLAYBACK
CUE LIBRARY
CUE EDITOR
TABLE MAKER
DIRECT RECALLS
TIME OF DAY TRIGGERS
TIMECODE TRIGGERS
NETWORK TRIGGERS
CONTROL WATCHER
CUE LISTS
CUE LIST NAVIGATION
CUE LIST EDITOR
REHEARSAL POINTS
CONDITIONS
DATABASE
TOOLS
INITIALIZATION
TESTING

]]


--------------------------
--       GLOSSARY       --
--------------------------
--[[
User: The person running the show.
Show Programmer: The person writing the Cues.
Super Coder: The person reading this right now. You're probably about to add/edit a Function or a Preference. Cool!

Function: A function, often parameterized. Stored in the Lua Script. Stored with metadata that is helpful to the Show Programmer.

Cue: A set of Cue Lines. When the Cue is triggered, all Cue Lines in the Cue are activated simultaneously (with wait times, if user decides).
Cue Line: A reference to a Function, plus specific parameters for that Function. Only exists within a Cue.

Cue Trigger: A way to execute a cue. There are mutliple types of Cue Triggers.

Cue List: A list of Cues to be executed in that order, one at a time. A 'Go' will trigger the Cue that is on deck.
Cue Entry: A Cue in a Cue List. This is not the Cue itself; it's a pointer to the Cue.

Preference: A setting that can be changed by the Show Programmer. Stored in the Lua Script.
Preference Value: The actual value of the Preference. Stored in the Controls.

Database: A JSON table of an entire show. This does not include Functions or Preferences. It does include Preferences Values.
Currently Running Database: The active show file.
Example Database: A non-editable show file that has an example setup. You can load this.
Saved Databases: A convenient way to store show files.

Back-end function: Super generic. Used for mundane things like converting strings to booleans.
Action function: A specific task. It's a building block. Example: send a message to lighting.
User function: A function built of one or more action functions. Each Cue Line has exactly one User Function.
Function List: A list of all User Functions.
]]


--------------------------
--    SCRIPT STARTUP    --
--------------------------
debug.sethook()

require('json')
--json = require('rapidjson') --don't need this most of the time
n1l = nil


--------------------------
--        LOGGING       --
--------------------------

logLevels = {}
logLevels[0] = {severityName = "System Message", qsysLogType = "Message", description = "Meta monitoring of log levels."}
logLevels[1] = {severityName = "Error", qsysLogType = "Error", color = "red", description = "Problematic behavior. Something is probably broken now."}
logLevels[2] = {severityName = "Warning", qsysLogType = "Error", color = "orange", description = "Odd behavior. Not damaging to the system."}
logLevels[3] = {severityName = "Message", qsysLogType = "Message", color = "lime", description = "Normal behavior: button presses, something succeeded."}
logLevels[4] = {severityName = "Note", qsysLogType = "Message", color = "lime", description = "Minutia: function calls, meta-info. Not recommended for production use."}

logDatabaseQueue = {}

addToLogDatabase = function (logItemToAdd)
  
  --get existing log
  json = require('rapidjson') --must use rapidjson to decode. the regular json library is too slow.
  local logDB = nil
  if Controls.Log_LogDatabase.String == "" or Controls.Log_LogDatabase.String == "{}" then
    logDB = {}
  else
    logDB = json.decode(Controls.Log_LogDatabase.String)
  end
  require('json') --after decoding, go back to regular json library. other operations don't work well using rapidjson
  
  --add item to log
  table.insert(logDB, logItemToAdd)
  
  --clean database for length
  while #logDB > Controls.Log_MaxLength.Value do
    table.remove(logDB, 1)
  end
  
  --clean database for time
  local maxLengthInSeconds = 86400 * Controls.Log_MaxTime.Value
  local earliestEntry = os.time() - maxLengthInSeconds
  while logDB[1].timestamp < earliestEntry do
    table.remove(logDB, 1)
  end
  
  --write to Controls
  Controls.Log_LogDatabase.String = json.encode(logDB)
  
  local str = ""
  for i = #logDB - 19, #logDB do --load the last 20 lines of the table
    if logDB[i] then
      str = str .. logDB[i].humanTime .. "\t\t" .. logDB[i].severityName .. ": " .. logDB[i].message .. "\n"
    end
  end
  Controls.Log_LogDisplay.String = str
end

logQueueTimer = Timer.New()
logQueueTimerFunc = function ()
  if #logDatabaseQueue == 0 then
    logQueueTimer:Stop()
  else
    local logItemToAdd = table.remove(logDatabaseQueue, 1)
    addToLogDatabase(logItemToAdd)
  end
end
logQueueTimer.EventHandler = logQueueTimerFunc

addToLogDatabaseQueue = function (logItemToAdd)
  table.insert(logDatabaseQueue, logItemToAdd)
  logQueueTimer:Start(.05)
end

--Status LED
logStatusLedLevel = #logLevels
Controls.Log_StatusLED.Boolean = true

clearStatusLED = function ()

  logStatusLedLevel = #logLevels
  
  local color = logLevels[#logLevels].color
  Controls.Log_StatusLED.Color = color
end

Controls.Log_ClearStatusLED.EventHandler = function ()
  log("Log_ClearStatusLED button pressed")
  
  clearStatusLED()
end


log = function (string, severity)
  
  if severity == nil then
    severity = #logLevels
  end
  
  if severity <= Controls.Log_LogLevel.Value then
    
    local severityName = logLevels[severity].severityName
    local qsysLogType = logLevels[severity].qsysLogType
    local color = logLevels[severity].color
    
    --write to Q-SYS log
    if qsysLogType == "Error" then
      Log.Error(string)
    elseif qsysLogType == "Message" then
      Log.Message(string)
    end
    
    --write to debug
    print(severityName .. ": " .. string)
    
    --write to Control: Status LED
    if color and severity < logStatusLedLevel then
      logStatusLedLevel = severity
      Controls.Log_StatusLED.Color = color
    end
    
    --write to Control: log database
    local logItemToAdd = {timestamp = os.time(), humanTime = os.date(), severity = severity, severityName = severityName, message = string}
    addToLogDatabaseQueue(logItemToAdd)
  end
end

log('EasyCue is loading.', 0)

Controls.Log_ClearLog.EventHandler = function ()
  Controls.Log_LogDatabase.String = ""
  Controls.Log_LogDisplay.String = ""
end

Controls.Log_LogLevel.EventHandler = function (cc)
  log('Log level is now ' .. cc.String, 0)
end


--------------------------
--      PREFERENCES     --
--------------------------
prefs = {}
prefs.logPlayCommands = {name = "Log Play Commands", varType = "Boolean", note = "Write every play command to the log."}
prefs.pressAndHoldStopTime = {name = "Press and Hold Stop Time", varType = "Value", note = "How long you have to hold the UCI's stop button in order to activate it." }
prefs.resetCueListWhenNewShowSelected = {name = "Reset Cue List When New Show Selected", varType = "Boolean", note = "When changing shows mid-show do we want to start at the beginning of the cue list?"}
prefs.autoAdvanceOnGo = {name = "Auto Advance On Go", varType = "Boolean", note = "When you tap Go, does the script advance to the next cue?"}
prefs.updateLongestPlayedPerPlayCommand = {name = "Update Longest Played Per Play Command", varType = "Boolean", note = "When playing a new cue would you like to see the longest file being played, or the longest file that was just played"}
prefs.fadeAndStopTime = {name = "Fade and Stop Time", varType = "Value", note = "Defualt time in seconds to fade for a 'fade and stop' function."}
prefs.panicTime = {name = "Panic Time", varType = "Value", note = "Defualt time in seconds to fade during a panic."}
prefs.doubleTapTime = {name = "Double Tap Time", varType = "Value", note = "Defualt time in seconds required between taps."}
prefs.waitForCueLineTest = {name = "Include Wait in Cue Line Test", varType = "Boolean", note = "When you click the cue line 'Test' button, does it wait the listed time before executing the cue line"}
prefs.defaultPlayerGain = {name = "Default Player Gain", varType = "Value", note = "Default level to play back files if omitted from Audio Files Table Maker"}
prefs.playerLoadTime = {name = "Player Load Time", varType = "Value", note = "How many seconds in the future the Loop Player schedules playback. Recommend at least .5s longer than loop player component's buffer time."}
prefs.AnimationFrameRate = {name = "Stopping Animation Frame Rate", varType = "Value", note = "How many times per second would you like the meter to update its position to stop the tracks."}
prefs.logPlayCommands = {name = "Auto-Stop Unrouted Channels", varType = "Boolean", note = "Cleanup and stop channels that are playing content that isn't being routed anywhere"}
prefs.ignoreAdditionalRouting = {name = "Ignore Additional Routing", varType = "Boolean", note = "If you want to stop the files that are routed to that channel, regardless of whether they are also routed elsewhere"}


prefValues = {} --actual values of preferences are stored in database, not here

--Display prefs
populatePrefs = function ()
  log('populatePrefs function called')
  
  local prefsOrderedTable = {}
  local i = 0
  
  --put info in table for sorting
  for k,v in pairs (prefs) do
    i = i + 1
    prefsOrderedTable[i] = v
  end
  table.sort(prefsOrderedTable, sortByname)
  
  --put info in controls
  for i = 1, #prefsOrderedTable do
    Controls.Preferences_Name[i].String = prefsOrderedTable[i].name
    Controls.Preferences_Name[i].IsInvisible = false
    Controls.Preferences_Type[i].String = prefsOrderedTable[i].varType
    Controls.Preferences_Type[i].IsInvisible = false
    Controls.Preferences_Value[i].String = ""
    Controls.Preferences_Value[i].IsInvisible = false
    Controls.Preferences_Note[i].String = prefsOrderedTable[i].note
    Controls.Preferences_Note[i].IsInvisible = false
  end
  
  --Put prefValues in
  for k, v in pairs (prefValues) do
    for i = 1, #Controls.Preferences_Name do
      if k == Controls.Preferences_Name[i].String then
        Controls.Preferences_Value[i].String = tostring(v)
        break
      end
    end
  end
  
  --hide unused controls
  for i = #prefsOrderedTable + 1, #Controls.Preferences_Name do
    Controls.Preferences_Name[i].String = ""
    Controls.Preferences_Name[i].IsInvisible = true
  end
  for i = #prefsOrderedTable + 1, #Controls.Preferences_Type do
    Controls.Preferences_Type[i].String = ""
    Controls.Preferences_Type[i].IsInvisible = true
  end
  for i = #prefsOrderedTable + 1, #Controls.Preferences_Value do
    Controls.Preferences_Value[i].String = ""
    Controls.Preferences_Value[i].IsInvisible = true
  end
  for i = #prefsOrderedTable + 1, #Controls.Preferences_Note do
    Controls.Preferences_Note[i].String = ""
    Controls.Preferences_Note[i].IsInvisible = true
  end
end

--event handler for value controls
for i = 1, #Controls.Preferences_Value do
  Controls.Preferences_Value[i].EventHandler = function (cc)
    log('Preferences_Value text box #' .. i .. " (" .. Controls.Preferences_Name[i].String .. ") changed to " .. cc.String)
    
    local prefName = Controls.Preferences_Name[i].String
    local variableType = ""
    for k, v in pairs(prefs) do
      if prefs[k].name == prefName then
        variableType = string.lower(prefs[k].varType)
      end
    end
    
    local prefValue = cc.String
    if variableType == "value" or variableType == "number" or variableType == "integer" then
      prefValue = tonumber(prefValue)
    elseif variableType == "boolean" or variableType == "bool" then
      prefValue = toboolean(prefValue)
    end 
    
    prefValues[prefName] = prefValue
    writeCurrentDB()
  end
end


--------------------------
--      COMPONENTS      --
--------------------------

components = {}

components["Loop Player"] = {}
components["Loop Player"].note = "This plays your audio files."

components["Playback Router"] = {}
components["Playback Router"].note = "This comes after the player. It expands the number of available output channels."

components["Program Mixer"] = {}
components["Program Mixer"].note = "This is the matrix between program sources and APMs."

components["BGM Mixer"] = {}
components["BGM Mixer"].note = "This is the matrix between BGM sources and APMs."

components["Lighting Controller"] = {}
components["Lighting Controller"].note = "This sends messages to Lighting."

components["Audio Central Controller"] = {}
components["Audio Central Controller"].note = "This sends messages to Audio Central."

components["Video Controller"] = {}
components["Video Controller"].note = "This sends messages to Video."

components["SMPTE LTC Timecode Reader"] = {}
components["SMPTE LTC Timecode Reader"].note = "This reads incoming timecode."

for k, v in pairs (components) do --fills out rest of components table for you
  components[k].component = nil
  components[k].initFunc = function ()
    if componentValues[k] then
      components[k].name = componentValues[k]
      components[k].component = Component.New(componentValues[k])
      components[k].properties = getProperties(componentValues[k])
      
      if k == "Loop Player" then
        countLoopPlayerChannels()
      elseif k == "Playback Router" then
        countPlaybackRouterOutputChannels()
      end
    end
  end
end

-- function to retrieve properties
getProperties = function(control)
  log('getProperties function called with control ' .. control)
  
  local component
  local propsTable = {}
  
  for _, v in pairs (Component.GetComponents()) do -- Get Component table
    if v.Name == control then
      component = v
    end
  end
  
  -- retrieve the properties value
  if component then
    for _, props in pairs(component.Properties) do
      -- extract the properties table
      propsTable[props.PrettyName] = props.Value
    end
  end
  
  return propsTable
  
end


componentValues = {} -- stored in database

populateComponentInfo = function () --puts info in Components window Controls
  log('populateComponentInfo function called')
  
  --get component names
  local componentTable = {}
  for k,v in pairs (components) do
    local name = k
    local note = components[k].note
    local thisComponent = {name = name, note = note}
    table.insert(componentTable, thisComponent)
  end
  table.sort(componentTable, sortByname)
  
  --get components from design
  local componentsInDesign = {}
  for k,v in pairs (Component.GetComponents()) do
    table.insert(componentsInDesign, v.Name)
  end
  table.sort(componentsInDesign)
  
  --put info in Controls
  for i = 1, #componentTable do
    Controls.Components_Component[i].String = componentTable[i].name
    Controls.Components_Component[i].IsInvisible = false
    
    Controls.Components_Note[i].String = componentTable[i].note
    Controls.Components_Note[i].IsInvisible = false
    
    Controls.Components_NameInDesign[i].Choices = componentsInDesign
    Controls.Components_NameInDesign[i].IsInvisible = false
  end
  
  --also put in Control Watcher controls
  local cwComponentTable = componentsInDesign
  table.insert(cwComponentTable, 1, "")
  for i = 1, #Controls.ControlWatcher_Component do
    Controls.ControlWatcher_Component[i].Choices = cwComponentTable
  end
  
  --hide unused Controls
  for i = #componentTable + 1, #Controls.Components_Component do
    Controls.Components_Component[i].String = ""
    Controls.Components_Component[i].IsInvisible = true
  end
  for i = #componentTable + 1, #Controls.Components_Note do
    Controls.Components_Note[i].String = ""
    Controls.Components_Note[i].IsInvisible = true
  end
  for i = #componentTable + 1, #Controls.Components_NameInDesign do
    Controls.Components_NameInDesign[i].Choices = {}
    Controls.Components_NameInDesign[i].IsInvisible = true
  end
  
  --pull names from database
  for k, v in pairs (componentValues) do
    for i = 1, #Controls.Components_NameInDesign do
      if k == Controls.Components_Component[i].String then
        Controls.Components_NameInDesign[i].String = v
        break
      end
    end
  end
end

updateComponentDesignNameValue = function (componentName, componentValue)
  log('updateComponentDesignNameValue function called with componentName ' .. componentName .. ' and componentValue: ' .. componentValue)
  
  --write to database
  componentValues[componentName] = componentValue
  writeCurrentDB()
  
  --rewrite components[name].component with updated Component.New
  components[componentName].initFunc()
end

updateComponentDesignNameValueFromRow = function (rowNum)
  --log('updateComponentDesignNameValueFromRow function called with rowNum ' .. rowNum)
  
  local componentName = Controls.Components_Component[rowNum].String
  local componentValue = Controls.Components_NameInDesign[rowNum].String
  
  updateComponentDesignNameValue(componentName, componentValue)
end

updateAllComponentDesignNameValues = function ()
  log('updateAllComponentDesignNameValues function called')
  
  for i = 1, #Controls.Components_NameInDesign do
    local componentName = Controls.Components_Component[i].String
    local componentValue = Controls.Components_NameInDesign[i].String
    
    if Controls.Components_Component[i].String ~= "" then
      componentValues[componentName] = componentValue
      components[componentName].initFunc()
    end
  end
  
  writeCurrentDB()
end

--when show programmer changes a component name
for i = 1, #Controls.Components_NameInDesign do
  
  local componentName = Controls.Components_Component[i].String
  
  if componentName == "Loop Player" then --update loop player-dependent stuff, if necessary
    Controls.Components_NameInDesign[i].EventHandler = function(cc)
      log('Components_NameInDesign text box # ' .. i .. ' changed to ' .. cc.String)
      
      updateComponentDesignNameValueFromRow(i)
      setUpAutoMuteOfPlaybackChannels()
    end
    
  elseif componentName == "Playback Router" then -- we have playback functions dependent on the router as well
    Controls.Components_NameInDesign[i].EventHandler = function(cc)
      log('Components_NameInDesign text box # ' .. i .. ' changed to ' .. cc.String)
      
      updateComponentDesignNameValueFromRow(i)
      updateRouterInfo()
    end
    
  elseif componentName == "SMPTE LTC Timecode Reader" then -- we have playback functions dependent on the router as well
    Controls.Components_NameInDesign[i].EventHandler = function(cc)
      log('Components_NameInDesign text box # ' .. i .. ' changed to ' .. cc.String)
      
      updateComponentDesignNameValueFromRow(i)
      watchTimecodeReader()
    end
  
  else -- all other components just need the basics
    Controls.Components_NameInDesign[i].EventHandler = function(cc)
      log('Components_NameInDesign text box # ' .. i .. ' changed to ' .. cc.String)
      
      updateComponentDesignNameValueFromRow(i)
    end
  end
end


--------------------------
--  BACK-END FUNCTIONS  --
--------------------------

scrubString = function (dirtyString) -- removes characters that might be dangerous
  local numBadCharacters = 0
  
  --so far, we've only found * and -
  local cleanString, numBadCharacters = string.gsub(dirtyString, "[%*%-]", "")
  
  if numBadCharacters > 0 then
    log("Removed special characters from name because they make problems later", 3)
  end
  
  return cleanString
end

sortByname = function (item1, item2)
  return string.lower(item1.name) < string.lower(item2.name)
end

sortByName = function (item1, item2)
  return string.lower(item1.Name) < string.lower(item2.Name)
end

sortByCueList = function (item1, item2)
  return string.lower(item1.cueList) < string.lower(item2.cueList)
end

sortByCueName = function (item1, item2)
  return string.lower(item1.cueName) < string.lower(item2.cueName)
end

sortByComponent = function (item1, item2)
  return string.lower(item1.component) < string.lower(item2.component)
end

sortByControl = function (item1, item2)
  return string.lower(item1.control) < string.lower(item2.control)
end

sortByFileName = function (item1, item2)
  return string.lower(item1.fileName) < string.lower(item2.fileName)
end

sortByoutputs = function (item1, item2)
  return string.lower(tableToString(item1.outputs)) < string.lower(tableToString(item2.outputs))
end

sortByTime = function (item1, item2)
  return item1.time < item2.time
end

toboolean = function(input)
  if type(input) == "string" then
    return string.lower(input) == "true" or string.lower(input) == "t" or string.lower(input) == "1"or string.lower(input) == "yes"
  elseif type(input) == "number" then
    return input == 1
  end
end

copy = function (original)
  --log('copy function ran') --careful; uncommenting this will spam your logs
  local duplicate = nil
  
  if type(original) == 'table' then
    duplicate = {}
    for k,v in pairs (original) do
      if type(original[k]) == 'table' then
        duplicate[k] = copy(original[k])
      else
        duplicate[k] = original[k]
      end
    end
  else
    duplicate = original
  end
  
  return duplicate
end

getCountOfTable = function (table)
  local count = 0
  
  for k,v in pairs (table) do
    count = count + 1
  end
  
  return count
end

convertToTable = function(items)
  if type(items) ~= "table" then
    return {items}
  else
    return items
  end
end

containsNumber = function(t, value)
  for i = 1, #t do
    if tonumber(t[i]) == tonumber(value) then
      return true
    elseif i == #t then
      return false
    end
  end
end

stringToTable = function(string)

  local tempTable = {}
  for entry in string.gmatch(string, "[^,]+") do
    --print(entry)

    entry = string.gsub(string.reverse(entry), "%s*", "", 1) -- trim the spaces at the end
    entry = string.gsub(string.reverse(entry), "%s*", "", 1) -- trim the spaces at the beginning
    
    table.insert(tempTable, entry)
  end
  
  return tempTable
end

tableToString = function(tempTable, seperator)

  seperator = seperator or ", "
  
  local newString = ""
  for k,v in pairs(tempTable) do
    if k ~= #tempTable then
      newString = newString .. v .. seperator
      
    -- format an additional table within the table
    elseif type(v) == "table" then
      newString = newString .. tableToString(v, "/")
      
    else
      newString = newString .. v
    end
  end
  
  return newString
  
end

filter = function(t, pattern)

  if not pattern then return t end

  local newTable = {}

  for i = 1, #t do
    if string.find(t[i], pattern) then
      table.insert(newTable, t[i])
    end
  end
  
  return newTable

end

getDirectoryFileNames = function(searchPath, fileNames)
  --log('getDirectoryFileNames function called')  --disabled because recursion caused too many logs
  
  fileNames = fileNames or {}
  
  --check that you're actually running on a core
  if System.IsEmulating then
    log('No files retrieved from core because this design is running in emulation.')
  
  else
    local searchPath = searchPath or ""
    
    --get file names from core
    for k,v in pairs(dir.get("media/Audio/"..searchPath)) do
      if v.type == "file" then
        local fileName = "Audio"..searchPath.."/"..v.name
        table.insert(fileNames, fileName)
      else --(v.type is probably "directory")
        getDirectoryFileNames(searchPath.."/"..v.name, fileNames)
      end
    end
    
    table.sort(fileNames) --TODO don't do this every recursion
    
    return fileNames
  end
end

updateStatusDisplay = function(message) --Show messages to the user on UCI
  
  message = message or "" -- clear status
  
  log("updateStatusDisplay function called with message: " .. message)
  
  Controls.UCI_StatusDisplay.String = message

end

----WAIT FUNCTIONS
--To call the wait function, type wait(time, function, arg1, arg2, ...)
  --time = the amount of delay time (in seconds) before calling function
  --function = the function (without parentheses) that you want to call after the wait
  --arg1, arg2, etc. are any arguments you want to pass to the function.

waitTimers = {}

--function to create new timer
createNewTimer = function (timerNum)
  waitTimers[timerNum] = {waitTimer = nil, waitTimerFunc = nil, waitFunction = nil, waitParameters = nil,}

  waitTimers[timerNum].waitTimer = Timer.New() --the new timer itself

  waitTimers[timerNum].waitTimerFunc = function () --the function that executes when the timer is up
    waitTimers[timerNum].waitTimer:Stop() --stops the timer
    waitTimers[timerNum].waitFunction(table.unpack(waitTimers[timerNum].waitParameters)) --calls the function with the parameters (as a table)
    waitTimers[timerNum].waitFunction = nil --deletes the function from the timer table
    waitTimers[timerNum].waitParameters = nil --deletes the parameters from the timer table
  end

  --waitFunction is the function the user wants to call after the wait
  --waitFunctionParameters is the parameters the function uses when it runs
  --these are written when the wait() function is called

  waitTimers[timerNum].waitTimer.EventHandler = waitTimers[timerNum].waitTimerFunc
end

function expand (s)
  s = string.gsub(s, "$(%w+)", function (n) return tostring(_G[n]) end)
  return s
end

wait = function (waitTime, funcName, ...)
  log("wait function called. " .. expand(tostring(funcName)) .. " will wait " .. waitTime .. " seconds before running.") --TODO print better function name
  
  --Allow for math functions in rehearsal timing
  local initialWait = waitTime
  if rehearsalTime >= waitTime then
    waitTime = 0
  else
    waitTime = waitTime - rehearsalTime
  end
  
  --pack parameters into table (for unpacking at time of calling the desired function)
  local parametersToPass = {}
  for i = 1, select("#",...) do
    parametersToPass[#parametersToPass + 1] = select(i,...)
  end
  
  --check for first available timer
  local timerToUse = nil
  for i=1,#waitTimers do
    if waitTimers[i].waitFunction == nil then
      timerToUse = i
      break
    --no available timers, so create a new one
    elseif i == #waitTimers then
      timerToUse = i + 1
      createNewTimer(timerToUse)
    end
  end

  --set function & start timer
  waitTimers[timerToUse].waitFunction = funcName
  waitTimers[timerToUse].waitParameters = parametersToPass
  
  --Allows for the fade and playAudioFiles functions to work with rehearsal seeking
  if funcName == fade then
    if rehearsalTime > initialWait then
      waitTimers[timerToUse].waitParameters[3] = waitTimers[timerToUse].waitParameters[3] + initialWait
    else    
      waitTimers[timerToUse].waitParameters[3] = waitTimers[timerToUse].waitParameters[3] + rehearsalTime
    end
    
  elseif funcName == playAudioFiles then
    if waitTime ~= 0 then
      waitTimers[timerToUse].waitParameters[2] = (waitTimers[timerToUse].waitParameters[2] or 0) - rehearsalTime
    elseif waitTime == 0 then
      waitTimers[timerToUse].waitParameters[2] = (waitTimers[timerToUse].waitParameters[2] or 0) - initialWait
    end
  
  elseif funcName == fadeAndStopFiles then
    if rehearsalTime > initialWait then
      waitTimers[timerToUse].waitParameters[2] = waitTimers[timerToUse].waitParameters[2] + initialWait
    else    
      waitTimers[timerToUse].waitParameters[2] = waitTimers[timerToUse].waitParameters[2] + rehearsalTime
    end
  end
  
  waitTimers[timerToUse].waitTimer:Start(waitTime)
end

--set up first timer
createNewTimer(1)


--------------------------
--   ACTION FUNCTIONS   --
--------------------------

--EXTERNAL CONTROL
sendAudioCentralCommand = function(message)
  log("sendAudioCentralCommand function called with message: " .. message)
  
  components["Audio Central Controller"].component.ExternalCommand.String = message
end

sendToLighting = function(message) --Send Command to lighting controller as defined at the component section of script
  log("sendToLighting function called with message: " .. message)
  
  components["Lighting Controller"].component.ExternalCommand.String = message
end

sendToVideo = function(message)
  log("sendToVideo function called with message: " .. message)
  
  components["Video Controller"].component.ExternalCommand.String = message
end

--AUDIO ROUTING
setMixerCrosspoint = function(mixerName, inputs, outputs, gain, rampTime) --Change the values of the crosspoints in a given mixer
  log("setMixerCrossPoint function called with mixerName: " .. mixerName .. ' inputs: ' .. inputs .. ' outputs: ' .. outputs .. ' gain: ' .. gain .. ' rampTime: ' .. rampTime)
  
  local mixer = Component.New(mixerName)
  inputs = convertToTable(inputs) --Allow for integer input
  outputs = convertToTable(outputs) --Allow for integer input
  
  for i = 1, #inputs do
    for j = 1, #outputs do
      mixer["input." .. inputs[i] .. ".output." .. outputs[j] .. ".gain"].RampTime = rampTime
      mixer["input." .. inputs[i] .. ".output." .. outputs[j] .. ".gain"].Value = gain
    end
  end
end

fade = function(target, value, fadeEndTime) --Changes value of a particular fader over ramptime
  log("fade function called with target: " .. tostring(target) .. ' value:' .. value .. ' fadeEndTime: ' .. fadeEndTime)
  
  local rampTime = nil
  
  --accomodate rehearsal time
  if fadeEndTime >= rehearsalTime then
    rampTime = fadeEndTime - rehearsalTime
  else
    rampTime = 0
  end
  
  --set the target
  target.RampTime = rampTime
  if type(value) == "string" then
    target.String = value
  else
    target.Value = value
  end
end

recallSnapshot = function(compName, snapshotNum, rampTime) --Recalls a snapshot in a Snapshot Controller
  log("recallSnapshot function called with compName: " .. compName .. ' snapshotNum:' .. snapshotNum .. ' rampTime: ' .. rampTime)
  
  local snapshotController = Component.New(compName)
  
  --accomodate rehearsal time
  if rampTime >= rehearsalTime then
    rampTime = rampTime - rehearsalTime
  else
    rampTime = 0
  end
  
  --set the ramp time
  snapshotController['ramp.time'].Value = rampTime
  
  --Load the snapshot
  local snapshotStr = "load." .. snapshotNum
  snapshotController[snapshotStr].Boolean = true
end


--AUDIO PLAYBACK
stop = function(newTime) --Stops all playback and timers for wait functions
  log("stop function called")
  
  local loopPlayer = components["Loop Player"].component
  local time = newTime or prefValues["Fade and Stop Time"]
  
  for i = 1, numLoopPlayerChannels do
    loopPlayer["output."..i..".gain"].RampTime = time
    loopPlayer["output."..i..".gain"].Value = -100
  end
  
  if Controls.UCI_Stop.Boolean then
    Controls.UCI_StatusDisplayMeter.Color = "green"
    stopPlayerAnimTimer:Start(1/prefValues["Stopping Animation Frame Rate"])
  end
  
  stopPlayerTimer:Start(time)
  stopWaitTimersTimer:Start(time + 0.2)
  lockUCIGo(time + 0.4)
  
end

stopFiles = function(filesTable)
  log('stopFiles function called with ' .. filesTable)
  
  filesTable = stringToTable(filesTable) -- allow for string input
  local playerChannelsToStop = {}
  
  for i = 1, #filesTable do
    for j = 1, numLoopPlayerChannels do
      if components["Loop Player"].component["output."..j..".status"].String == filesTable[i] then
        table.insert(playerChannelsToStop, j)
      end
    end
  end
  
  if System.IsEmulating then
    log("Cannot stop files in loop player. The system is in emulation mode.", 3)
  else
    LoopPlayer.Stop({
      Name = components["Loop Player"].name,
      Outputs = playerChannelsToStop,
    })
    
    checkForLongestFile(loopPlayerOutputs)
  end
  
end

fadeAndStopFiles = function(filesTable, fadeTime)
  fadeTime = fadeTime or prefValues["Fade and Stop Time"]
  log('fadeAndStopFiles function called with ' .. filesTable .. ' fading over ' .. fadeTime .. ' seconds')
  
  filesTable = stringToTable(filesTable) -- allow for string input
  
  local loopPlayer = components["Loop Player"].component
  
  --allow for rehearsal seeking
  if fadeTime < rehearsalTime then
    fadeTime = 0 
  else
    fadeTime = fadeTime - rehearsalTime
  end
  
  for i = 1, #filesTable do
    for j = 1, numLoopPlayerChannels do
      if loopPlayer["output."..j..".status"].String == filesTable[i] then
        loopPlayer["output."..j..".gain"].EventHandler = function () --when file fades out..
          if loopPlayer["output."..j..".gain"].Value == -100 then
            loopPlayer["output."..j..".gain"].EventHandler = function () end --delete event handler
            
            if System.IsEmulating then
              log("Cannot stop files in loop player. The system is in emulation mode.", 3)
            else
              LoopPlayer.Stop({
                Name = components["Loop Player"].name,
                Outputs = {j},
              })
            end
            
          end
        end
        components["Loop Player"].component["output."..j..".gain"].RampTime = fadeTime
        components["Loop Player"].component["output."..j..".gain"].Value = -100 --fade out file
      end
    end
  end
end

playAudioFiles = function (filesTable, seekTime, loop, logEvent) --Uses first available player channel to play audio
  --filesTable format: {{fileName = str, gain = int, outputs = {int1, int2 , int3, ...},}, ...}
  --print(filesTable[1].fileName)
  
  log("playAudioFiles function called")
  
  local startCommandFilesTable = {}
  local lastChannelUsed = 0
  local playerChannelsUsed = {}
  local routerOutputsUsed = {}
  local playbackRoutingSuccessful = false
  local loopPlayer = components["Loop Player"].component
  local playbackRouter = components["Playback Router"].component
  
  for i = 1,#filesTable do
  
    local fileName = filesTable[i].fileName
    local routerOutputs = filesTable[i].outputs
    
    if not fileName then -- make sure we have a file name
      log("File play failed in outputs" .. table.unpack(routerOutputs) .. ": File name field required", 1)
    elseif routerOutputs == {} then -- make sure we have outputs
      log("File " .. fileName .. " failed to play: Outputs field required", 1)
    else    
      
      --find available player channel
      local channelToUse = nil
      
      --start looking 1 after the last one you use
      for j = lastChannelUsed + 1, numLoopPlayerChannels do
        
        --if nothing playing in that channel
        if loopPlayer["output."..j..".status"].String == "" then
          channelToUse = j
          table.insert(playerChannelsUsed, j)
          lastChannelUsed = j
          break --stop searching for available loop player channel
        
        --didn't find an available loop player channel
        elseif j == numLoopPlayerChannels then
          log("No available channel to play a file. " .. filesTable[i].fileName .. " did not play.", 1)
        end
      end
      
      --if there is an available channel...
      if channelToUse then
        
        --add file to startCommandTable
        local file = {}
          file.Name = filesTable[i].fileName
          file.Mode = "mono"
          file.Output = channelToUse
        
        table.insert(startCommandFilesTable,file)
        
        --patch crosspoints in router & unmute router output
        for k = 1, #filesTable[i].outputs do
          local routerOutputChannel = filesTable[i].outputs[k]
          
          -- check for required field: Outputs
          if not routerOutputChannel or routerOutputChannel == "" then
            log("File " .. file.Name .. " failed to play because no output was assigned.", 1)
            
          else
            --check that attempted route actually exists
            if routerOutputChannel > numPlaybackRouterOutputChannels or routerOutputChannel < 1 then
              log("Router output ".. routerOutputChannel .. " does not exist. " .. filesTable[i].fileName .. " tried to play there.", 1)
            else
              
              --configure router
              local channelToCheck = playbackRouter["select." .. routerOutputChannel].Value
              playbackRouter["select." .. routerOutputChannel].Value = channelToUse
              if playbackRouter["mute." .. routerOutputChannel].Boolean == false then
                log("Router output conflict: Channel "..routerOutputChannel.." was overridden by "..filesTable[i].fileName..".", 2)
                if prefValues["Auto-Stop Unrouted Channels"] then
                  checkForRouting(channelToCheck)
                end
              end
              playbackRouter["mute." .. routerOutputChannel].Boolean = false
              playbackRoutingSuccessful = true
              
              --scan for router output conflict
              for l = 1, #routerOutputsUsed do
                if routerOutputChannel == routerOutputsUsed[l] then
                  
                  log("Router output ".. routerOutputChannel .. " is being used multiple times in this play command. " .. filesTable[i].fileName .. " bumped a different file.", 2)
                  break
                end
              end
              table.insert(routerOutputsUsed, routerOutputChannel)
              
              --set gain of loop player
              loopPlayer["output."..channelToUse..".gain"].RampTime = 0
              loopPlayer["output."..channelToUse..".gain"].Value = filesTable[i].gain or prefValues["Default Player Gain"]
            
            end
          end
        end
      end
    end      
  end
  
  --if at least one file was successfully routed...
  if playbackRoutingSuccessful then
    
    --play files in player
    local params = {
      Name = components["Loop Player"].name,
      StartTime = -1,--loopPlayer["utc"].Value + prefValues["Player Load Time"],
      Files = startCommandFilesTable,
      Seek = seekTime or 0, --don't seek unless explicitly told to
      Loop = loop or false, --don't loop unless explicitly told to
      Log = logEvent or prefValues["Log Play Commands"],
    }
    params.Seek = params.Seek + rehearsalTime

    --TODO figre out how to get a file's length so we can enable this error checking
    --if params.Seek < fileLength then     
      if System.IsEmulating then
        log("Cannot play files in loop player. The system is in emulation mode.", 3)
      else
        LoopPlayer.Start(params) --Actually plays the files
      end
    --else
      --log("File " .. params.Name .. "failed to play: Attempted to seek past end of file", 1) 
    --end
    
    --update user readback
    getNumAvailableLoopPlayerChannels()
    
    --set UCI time remaining
    if prefValues["Update Longest Played Per Play Command"] then
      wait(prefValues["Player Load Time"], checkForLongestFile, playerChannelsUsed)
    else
      wait(prefValues["Player Load Time"], checkForLongestFile, loopPlayerOutputs)
    end
    
  end
end

blaster = function()
  print("pew pew")
end

queueAudioFile = function(fileToPlay, fileToFollow, seekTime, loop, logEvent)
  log("queueAudioFile function called with Audio file "..fileToPlay.." being queued to follow "..fileToFollow)
  
  local startCommandFilesTable = {}
  
  --Make table that has fileToPlay on every channel that fileToFollow is currently on
  for i  = 1, numLoopPlayerChannels do
    if components["Loop Player"].component["output."..i..".status"].String == fileToFollow then
      local file = {}
        file.Name = fileToPlay
        file.Mode = "mono"
        file.Output = i
      table.insert(startCommandFilesTable,file)
    end
  end
  
  --if found, actually play
  if startCommandFilesTable[1] then
    local params = {
      Name = components["Loop Player"].name,
      StartTime = -2,
      Files = startCommandFilesTable,
      Seek = seekTime or 0, --don't seek unless explicitly told to
      Loop = loop or false, --don't loop unless explicitly told to
      Log = logEvent or prefValues["Log Play Command"], -- this is the Loop Player component logging to Administrator
    }
    
    if System.IsEmulating then
      log("Cannot play files in loop player. The system is in emulation mode.", 3)
    else
      LoopPlayer.Start(params) --Actually plays the files
    end
    
  else
    log("queueAudioFile function did not find " .. fileToFollow .. ", so " .. fileToPlay .. " did not play", 1)
  end
end

cancelQueuedFiles = function(filesTable)
  log('cancelQueuedFiles function called with ' .. filesTable)
  
  filesTable = convertToTable(filesTable) -- allow for string input
  local playerChannelsToStop = {}
  local loopPlayer = components["Loop Player"].component
  
  --figure out which loop player channels to stop
  for i = 1, #filesTable do
    for j = 1, numLoopPlayerChannels do
      if loopPlayer["output."..j..".next"].String == "{\"Name\":\"" .. filesTable[i] .. "\",\"StartTime\":-2.0}" then
        table.insert(playerChannelsToStop, j)
      end
    end
  end
  
  --stop loop player channels
  if System.IsEmulating then
    log("Cannot cancel queued files in loop player. The system is in emulation mode.", 3)
  else
    LoopPlayer.Cancel({
      Name = components["Loop Player"].name,
      Outputs = playerChannelsToStop,
    })
  end
end

cancelAllQueuedFiles = function()
  log('cancelAllQueuedFiles function called')
  
  if System.IsEmulating then
    log("Cannot cancel queued files in loop player. The system is in emulation mode.", 3)
  else
    LoopPlayer.Cancel({
      Name = components["Loop Player"].name,
      Outputs = loopPlayerOutputChannels,
    })
  end
end

--------------------------
--      END OF AFs      --
--------------------------


--------------------------
--     FUNCTION LIST    --
--------------------------

--add functions here
funcs = {}

--BACK END
funcs["-----"] = {
  description = "This has no functional purpose. It's just to make a line break.",
  params = {
    --Nothing should be here
  },
  func = function ()
    --Nothing should happen here
  end
}

funcs["Log"] = {
  description = "Write a message to the Q-SYS Administrator Event Log.",
  params = {
    {
      name = "Message",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Message you want to log",
    },
    {
      name = "Severity",
      varType = "Integer",
      isRequired = false,
      default = 4,
      note = "1 = Error, 2 = Warning, 3 = Message, 4 = Note (default)",
    },
  },
  func = function (message, severity)
    log(message, severity)
  end
}


--META
funcs["Run Another Cue"] = {
  description = "This runs another cue. Handy if you want to build some cues as subroutines, then call them within other cues.\n\nCAUTION: This has the potential to create infinite loops!",
  params = {
    {
      name = "Cue Name",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the cue you want to run.",
    },
  },
  func = function (cueName)
    executeCue(cueName)
  end
}

funcs["Set Condition"] = {
  description = "This sets a condition that can be checked in the \"Check Condition\" function",
  params = {
    {
      name = "Condition Name",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the condition you want to set.",
    },
    {
      name = "Value",
      varType = "Integer",
      isRequired = true,
      default = "",
      note = "State you want the condition to be.",
    },
  },
  func = function (condition, value)
    local index = getConditionIndex(condition)
    conditions[index].currentValue = value 
    Controls.Conditions_CurrentValue[index].String = value
  end
}

funcs["Check Condition"] = {
  description = "This runs another cue only if the condition is set to the value you want.",
  params = {
    {
      name = "Condition Name",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Condition that, if true will run the subsequent cue.",
    },
    {
      name = "Value",
      varType = "Integer",
      isRequired = true,
      default = "",
      note = "State the condition must be in.",
    },
    {
      name = "Cue Name",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the cue you want to run.",
    },
  },
  func = function (condition, value, cueName)
    if conditions[getConditionIndex(condition)].currentValue == value then
      executeCue(cueName)
    end
  end
}

funcs["Select Another Cue"] = {
  description = "This will bring the next cue to be whatever you put in this field. This allows you to jump from cue to cue quickly",
  params = {
    {
      name = "Cue List",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the Cue List you want to select.",
    },
    {
      name = "Cue Number",
      varType = "Integer",
      isRequired = false,
      default = -1,
      note = "Number of the cue you want to select.\nUse this OR name of cue, not both.",
    },
    {
      name = "Cue Name",
      varType = "String",
      isRequired = false,
      default = "",
      note = "Name of the cue you want to select.\nUse this OR number of cue, not both.",
    },
  },
  func = function (cueList, cueNum, cueName)
    goToCue(cueList, cueNum, cueName)
  end
}


--EXTERNAL COMMUNICATION
funcs["Send Message to Audio Central"] = {
  description = "Send the Audio Central system a message.",
  params = {
    {
      name = "Message",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Message you want to send to Audio Central",
    },
  },
  func = function(message) --Send Command to lighting controller as defined at the component section of script
    sendAudioCentralCommand(message)
  end
}

funcs["Send Message to Lighting"] = {
  description = "Send the Lighting system a message.",
  params = {
    {
      name = "Message",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Message you want to send to Lighting",
    },
  },
  func = function(message) --Send Command to lighting controller as defined at the component section of script
    sendToLighting(message)
  end
}

funcs["Send Message to Video"] = {
  description = "Send the Video system a message.",
  params = {
    {
      name = "Message",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Message you want to send to Video",
    },
  },
  func = function(message)
    sendToVideo(message)
  end
}


--AUDIO PLAYBACK
funcs["Play Audio Files"] = {
  description = "This plays audio files. Use the File Table Maker for a more intuitive way to see the info.",
  params = {
    {
      name = "Audio Files Table",
      varType = "Table",
      isRequired = true,
      default = {}, -- should never be used because this parameter is required
      note = "Which files play where how loud. Use the File Table Maker.",
      --table format: {{fileName = str, gain = int, outputs = {int1, int2 , int3, ...},}, ...}
    },
    {
      name = "Seek Time",
      varType = "Value",
      isRequired = false,
      default = 0,
      note = "How far into the file do you want to start playing, in seconds. Default is 0.",
    },
    {
      name = "Loop",
      varType = "Boolean",
      isRequired = false,
      default = false,
      note = "Does this file loop indefinitely. Default is false.",
    },
    {
      name = "Log Event",
      varType = "Boolean",
      isRequired = false,
      default = prefValues["Log Play Commands"],
      note = "Does this Loop Player command write to the Q-Sys Administrator Event Log. Default is your defined Preference.",
    },
  },
  func = function (files, seekTime, loop, log)
    files = getOutputs(files)
    playAudioFiles(files, seekTime, loop, log)
  end
}

funcs["Stop All Playback"] = {
  description = "This stops all loop player channels.",
  params = {
    {
      name = "Fade Time",
      varType = "Value",
      isRequired = false,
      default = prefValues["Fade and Stop Time"],
      note = "How Quickly would you like to stop playback"
    }
  },
  func = function(fadeTime) --Stops all playback and timers for wait functions
    stop(fadeTime)
  end
}

funcs["Stop File"] = {
  description = "This stops the files you designate in files parameter",
  params = {
    {
      name = "File",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Which file do you want to stop?",
    }
  },
  func = function(file)
    stopFiles(file)
  end
}

funcs["Fade and Stop Files"] = {
  description = "This fades out the files you specify and then stops those files",
  params = {
  {
    name = "Files",
    varType = "String",
    isRequired = true,
    default = "",
    note = "Which files do you want to fade and then stop?"
  },
  {
    name = "Fade Time",
    varType = "Value",
    isRequired = false,
    default = prefValues["Fade and Stop Time"],
    note = "Default value is your \"Fade and Stop Time\" value set in preferences"
  },
  },
  func = function(files, fadeTime)
    fadeAndStopFiles(files, fadeTime)
  end
}

funcs["Fade and Stop Files by Output"] = {
  description = "This fades out the files that are outputting on the channels you sepecify and then stops those files",
  params = {
  {
    name = "Outputs",
    varType = "String (CSV)",
    isRequired = true,
    default = "",
    note = "Which outputs do you want to fade and then stop?"
  },
  {
    name = "Fade Time",
    varType = "Value",
    isRequired = false,
    default = prefValues["Fade and Stop Time"],
    note = "Default value is your fadeAndStopTime value set in preferences"
  },
  {
    name = "Ignore Additional Routing",
    varType = "Boolean",
    isRequired = false,
    default = prefValues["Ignore Additional Routing"],
    note = "Default value is \"Ignore Additional Routing\" Preference"
  },
  },
  func = function(outputs, fadeTime, ignore)
    local files = getCurrentFilesByOutput(outputs, ignore)
    fadeAndStopFiles(files, fadeTime)
  end
}

funcs["Fade and Stop All Files"] = {
  description = "This fades out the files you specify and then stops those files",
  params = {
  {
    name = "Fade Time",
    varType = "Value",
    isRequired = false,
    default = prefValues["Fade and Stop Time"],
    note = "Default value is your fadeAndStopTime value set in preferences"
  },
  },
  func = function(fadeTime)
    local files = getCurrentFiles()
    fadeAndStopFiles(files, fadeTime)
  end
}


--FILE QUEUEING
funcs["Queue Audio File"] = {
  description = "Queue up an audio file to play after a specific audio file that is currently playing",
  params = {
  {
    name = "File To Play",
    varType = "String",
    isRequired = true,
    default = "",
    note = "Which files do you want to play next?"
  },
  {
    name = "File to Follow",
    varType = "String",
    isRequired = true,
    default = "",
    note = "Which file's ending will trigger the new file to play?"
  },
  {
    name = "Seek Time",
    varType = "Value",
    isRequired = false,
    default = 0,
    note = "Do you want to skip ahead in the new track?"
  },
  {
    name = "Loop",
    varType = "Boolean",
    isRequired = false,
    default = false,
    note = "Default value is false."
  },
  {
    name = "Log Event",
    varType = "Boolean",
    isRequired = false,
    default = false,
    note = "Do you want to log it?"
  },
  },
  func = function(fileToPlay, fileToFollow, seekTime, loop, logEvent)
    queueAudioFile(fileToPlay, fileToFollow, seekTime, loop, logEvent)
  end
}

funcs["Cancel Queued File"] = {
  description = "Cancel a queued file before it plays",
  params = {
  {
    name = "File To Cancel",
    varType = "String",
    isRequired = true,
    default = "",
    note = "Which files do you want to cancel?"
  },
  },
  func = function(filesToCancel)
    cancelQueuedFiles(filesToCancel)
  end
}

funcs["Cancel All Queued Files"] = {
  description = "Cancels all files that are queued up.",
  params = {},
  func = function()
    cancelAllQueuedFiles()
  end
}


--AUDIO ROUTING
funcs["Set Mixer Crosspoint"] = {
  description = "Sets a crosspoint (or multiple) of a mixer.",
  params = {
    {
      name = "Mixer Name",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the mixer component. The mixer must be given a custom name while the design is offline.",
    },
    {
      name = "Inputs",
      varType = "String (CSV)",
      isRequired = true,
      default = "",
      note = "Number of the input(s) you want to set.",
    },
    {
      name = "Outputs",
      varType = "String (CSV)",
      isRequired = true,
      default = "",
      note = "Number of the output(s) you want to set.",
    },
    {
      name = "Gain",
      varType = "Value",
      isRequired = true,
      default = false, -- is this an okay default value?
      note = "Absolute dB value of what you want the crosspoint set to.",
    },
    {
      name = "Ramp Time",
      varType = "Value",
      isRequired = true,
      default = false,
      note = "How long it takes for the crosspoint to go from its previous value to the new value.",
    },
  },
  func = function(mixerName, inputs, outputs, gain, rampTime) --Change the values of the crosspoints in a given mixer
    setMixerCrosspoint(mixerName, inputs, outputs, gain, rampTime)
  end
}

funcs["Fade"] = {
  description = "Changes value of a particular fader over time.",
  params = {
    {
      name = "Component",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the mixer that should be fading",
    },
    {
      name = "Control",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Which fader should be fading",
    },
    {
      name = "Destination Value",
      varType = "Value",
      isRequired = true,
      default = false,
      note = "Destination level (absolute)",
    },
    {
      name = "Ramp Time",
      varType = "Value",
      isRequired = true,
      default = false,
      note = "How long the fade should take",
    },
  },
  func = function(comp, control, value, fadeEndTime) --Changes value of a particular fader over ramptime
    fade(Component.New(comp)[control], value, fadeEndTime)
  end
}

funcs["Set Control Value"] = {
  description = "Changes value of a particular control instantaneously.",
  params = {
    {
      name = "Component",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the component to control",
    },
    {
      name = "Control",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Which control inside the component to change",
    },
    {
      name = "Value",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Destination value (absolute)",
    },
  },
  func = function(comp, control, value) --Changes value of a particular fader over ramptime
    fade(Component.New(comp)[control], value, 0)
  end
}

funcs["Recall Snapshot"] = {
  description = "Changes value of a particular control instantaneously.",
  params = {
    {
      name = "Snapshot Controller",
      varType = "String",
      isRequired = true,
      default = "",
      note = "Name of the Snapshot Controller component to control",
    },
    {
      name = "Snapshot Number",
      varType = "Value",
      isRequired = true,
      default = "",
      note = "Which snapshot to recall",
    },
    {
      name = "Ramp Time",
      varType = "Value",
      isRequired = false,
      default = "",
      note = "Which snapshot to recall",
    },
  },
  func = function(comp, snapshotNum, rampTime)
    recallSnapshot(comp, snapshotNum, rampTime)
  end
}

--VIEW FUNCTION INFO
populateFunctionList = function ()
  log('populateFunctionList function called')
  
  --get and sort function names
  local funcNameList = {}
  for k,v in pairs(funcs) do
    table.insert(funcNameList, k)
  end
  table.sort(funcNameList)
  
  --write to Controls in Function List
  local numFuncs = #funcNameList
  for i = 1, #Controls.FunctionList_Name do
    Controls.FunctionList_Name[i].String = funcNameList[i] or ""
    Controls.FunctionList_Name[i].IsInvisible = (i > numFuncs)
    Controls.FunctionList_Select[i].IsInvisible = (i > numFuncs)
  end
  
  --write to Function Dropdowns in Cue Editor
  for i = 1, #Controls.CueEditor_Function do
    Controls.CueEditor_Function[i].Choices = funcNameList
  end
end

displayFunctionInfo = function (funcNum)
  log('displayFunctionInfo function called with funcNum ' .. funcNum)
  
  local selectedFunc = funcs[Controls.FunctionList_Name[funcNum].String]
  
  Controls.FunctionList_Description.String = selectedFunc.description
  local numParams = #selectedFunc.params
  for i = 1, #Controls.FunctionList_Parameter do
    if i <= numParams then
      Controls.FunctionList_Parameter[i].String = selectedFunc.params[i].name
      Controls.FunctionList_Type[i].String = selectedFunc.params[i].varType
      Controls.FunctionList_Note[i].String = selectedFunc.params[i].note
      Controls.FunctionList_Required[i].String = tostring(selectedFunc.params[i].isRequired)
      
      --show used rows
      Controls.FunctionList_Parameter[i].IsInvisible = false
      Controls.FunctionList_Type[i].IsInvisible = false
      Controls.FunctionList_Note[i].IsInvisible = false
      Controls.FunctionList_Required[i].IsInvisible = false
    else
      Controls.FunctionList_Parameter[i].String = ""
      Controls.FunctionList_Type[i].String = ""
      Controls.FunctionList_Note[i].String = ""
      Controls.FunctionList_Required[i].String = ""
      
      --hide unused rows
      Controls.FunctionList_Parameter[i].IsInvisible = true
      Controls.FunctionList_Type[i].IsInvisible = true
      Controls.FunctionList_Note[i].IsInvisible = true
      Controls.FunctionList_Required[i].IsInvisible = true
    end
  end
end

--select buttons display info
for i = 1, #Controls.FunctionList_Select do
  Controls.FunctionList_Select[i].EventHandler = function (cc)
    log('FunctionList_Select #' ..i.. " button pressed", 3)
    
    --radio buttons
    for j = 1, #Controls.FunctionList_Select do
      Controls.FunctionList_Select[j].Boolean = (i == j)
    end
    
    --display info
    displayFunctionInfo(i)
  end
end


--------------------------
--       PLAYBACK       --
--------------------------

numLoopPlayerChannels = nil
loopPlayerOutputChannels = {}

getOutputs = function(audioFilesTable)

  local newAudioTable = copy(audioFilesTable)
  
  -- search through the outputs
  for i = 1, #audioFilesTable do
    --print("Number of outputs: " .. #audioFilesTable[i].outputs)
  
    -- check each to see if one is available
    for j = 1, #audioFilesTable[i].outputs do
    
      --check for alternates
      if type(audioFilesTable[i].outputs[j]) == "table" then
        if #audioFilesTable[i].outputs[j] > 1 then
          for k = 1, #audioFilesTable[i].outputs[j] do
            if components["Playback Router"].component["mute.".. audioFilesTable[i].outputs[j][k]].Boolean then -- if it's available
              -- print("Channel " .. audioFilesTable[i].outputs[j][k] .. " is available.")
              newAudioTable[i].outputs[j] = tonumber(newAudioTable[i].outputs[j][k]) -- use it
              break
            
            elseif k == #audioFilesTable[i].outputs[j] then -- if you can't use any of the channels
              log("No alternate channels available" .. audioFilesTable[i].fileName .. " will use first channel", 2)
              newAudioTable[i].outputs[j] = tonumber(newAudioTable[i].outputs[j][1]) -- use the first channel
            end
          end
        end
      end
      
    end
  
  end
  
  return newAudioTable
  
end

checkForRouting = function(loopPlayerChannel)

  -- check each channel in the router
  for i = 1, numPlaybackRouterOutputChannels do
    -- if it's unmuted and routing that loopPlayer channel
    if (not components["Playback Router"].component["mute."..i].Boolean) and components["Playback Router"].component["select."..i].Value == loopPlayerChannel then
      break -- leave it alone
    elseif i == numPlaybackRouterOutputChannels then -- once we're at the end
      LoopPlayer.Stop({
      Name = components["Loop Player"].name,
      Outputs = {loopPlayerChannel},
    })
    end
  end
  
end

getCurrentFilesByOutput = function(outputs, ignore)
  
  if ignore == nil then
    ignore = prefValues["Ignore Additional Routing"]
  end

  local filesToStop = ""
  
  outputs = stringToTable(outputs)
  
  -- search through all the router channels
  for i = 1, #outputs do
    local fileChannel = nil
    -- if a file is playing in that output
    if not components["Playback Router"].component["mute."..outputs[i]].Boolean then
      fileChannel = math.floor(components["Playback Router"].component["select."..outputs[i]].Value)
    end
    
    -- if we don't want to ignore the other outputs
    -- search the router channels again
    if not ignore then
      for routerChannel = 1, numPlaybackRouterOutputChannels do
        -- if you find the file is routed elsewhere
        --print("Router Channel:" .. type(routerChannel) .. "Output to search for: " .. type(outputs[1]), contains(outputs, routerChannel))
        
        if (not containsNumber(outputs, routerChannel)) and (not components["Playback Router"].component["mute."..routerChannel].Boolean) and components["Playback Router"].component["select."..routerChannel].Value == fileChannel then
          log("Channel " .. fileChannel .. " is also routed in output " .. routerChannel .. " file will not be stopped.", 2)
          fileChannel = nil
          -- don't stop it
          break
        end
      end
    end
    
    -- stop it
    if fileChannel then
      print("Got here" .. fileChannel)
      filesToStop = filesToStop .. components["Loop Player"].component["output."..fileChannel..".status"].String .. ","
    end
    
  end
  
  return filesToStop
  
end

getCurrentFiles = function()
  local files = ""
  
  -- search through each channel in the loop player
  for i = 1, numLoopPlayerChannels do
    if components["Loop Player"].component["output."..i..".status"].String ~= "" then
      -- add each track title
      files = files .. components["Loop Player"].component["output."..i..".status"].String .. ","
    end
  end
  
  return files
end

countLoopPlayerChannels = function ()
  log('countLoopPlayerChannels function called')
  
  --count channels
  numLoopPlayerChannels = tonumber(components["Loop Player"].properties["Output Count"])
  
  --put channels in a table
  loopPlayerOutputChannels = {}
  for i = 1, numLoopPlayerChannels do
    table.insert(loopPlayerOutputChannels, i)
  end
end

numPlaybackRouterOutputChannels = nil
routerOutputChannels = {}

countPlaybackRouterOutputChannels = function ()
  log('countPlaybackRouterOutputChannels function called')
  
  --count channels
  numPlaybackRouterOutputChannels = tonumber(components["Playback Router"].properties["Output Count"])
  
  --put channels in a table
  routerOutputChannels = {}
  for i = 1, numPlaybackRouterOutputChannels do
    table.insert(routerOutputChannels, i)
  end
end

getNumAvailableLoopPlayerChannels = function () --Checks for number of loop player not currently playing a file
  log("getNumAvailableLoopPlayerChannels function called")
  
  local availableChannels = 0
  local loopPlayer = components["Loop Player"].component
  
  --count available channels
  for i = 1, numLoopPlayerChannels do
    if loopPlayer["output."..i..".status"].String == "" then
      availableChannels = availableChannels + 1
    end
  end
  
  Controls.Debug_NumAvailableLoopPlayerChannels.Value = availableChannels
  
  --set color of control
  if availableChannels == 0 then
    Controls.Debug_NumAvailableLoopPlayerChannels.Color = "#FF5800"
    log("There are no more loop player channels available. Don't play a file before one of these finishes.", 2)
  elseif availableChannels < 4 then
    Controls.Debug_NumAvailableLoopPlayerChannels.Color = "orange"
    log("There are only "..availableChannels.." loop player channels available. Be careful.", 3)
  elseif availableChannels < 9 then
    Controls.Debug_NumAvailableLoopPlayerChannels.Color = "yellow"
  else
    Controls.Debug_NumAvailableLoopPlayerChannels.Color = "lime"
  end
  
  return availableChannels
end

checkForLongestFile = function (channelsToCheck)
  log("checkForLongestFile function called with channelsToCheck: " .. table.unpack(channelsToCheck))
  
  --Checks the given table for the longest file
  local channelWithLongestFile = channelsToCheck[1]
  local loopPlayer = components["Loop Player"].component
  
  --search for player channel with the longest file playing
  for i = 1, #channelsToCheck do
    if loopPlayer["output."..channelsToCheck[i]..".remaining"].Value > loopPlayer["output."..channelWithLongestFile..".remaining"].Value then
      channelWithLongestFile = channelsToCheck[i]
    end
  end
  
  --clears previous event handlers
  for i = 1, numLoopPlayerChannels do
    if i == channelWithLongestFile then
      loopPlayer["output." .. channelWithLongestFile .. ".elapsed"].EventHandler = function (cc)
        Controls.UCI_TimeRemaining.String = loopPlayer["output." .. channelWithLongestFile .. ".remaining"].String
        Controls.UCI_TimeRemainingMeterBackground.Position = cc.Position
      end
    else
      loopPlayer["output."..i..".elapsed"].EventHandler = nil
    end
  end
end

animTimer = Timer.New()
animTimer.EventHandler = function(time, dec)

  --increment the meter
  Controls.UCI_StatusDisplayMeter.Position = Controls.UCI_StatusDisplayMeter.Position + 1/prefValues["Stopping Animation Frame Rate"] / prefValues["Press and Hold Stop Time"]
  updateStatusDisplay("Stopping in ".. math.ceil(prefValues["Press and Hold Stop Time"] - Controls.UCI_StatusDisplayMeter.Position * prefValues["Press and Hold Stop Time"]) .." seconds")
  
  -- end animation
  if Controls.UCI_StatusDisplayMeter.Position >= 1 then
    Controls.UCI_StatusDisplayMeter.Position = 0
    animTimer:Stop()
  end
end

stopPlayerAnimTimer = Timer.New()
stopPlayerAnimTimer.EventHandler = function()
  
  --increment the meter
  Controls.UCI_StatusDisplayMeter.Position = Controls.UCI_StatusDisplayMeter.Position + 1/prefValues["Stopping Animation Frame Rate"] / prefValues["Fade and Stop Time"]
  updateStatusDisplay("Stopping...")
  
  -- end animation
  if Controls.UCI_StatusDisplayMeter.Position >= 1 then
    updateStatusDisplay()
    Controls.UCI_StatusDisplayMeter.Position = 0
    stopPlayerAnimTimer:Stop()
  end
  
end

stopWaitTimersTimer = Timer.New() --Stops the wait timers
stopWaitTimersTimer.EventHandler = function()
  stopWaitTimersTimer:Stop()
  
  updateStatusDisplay("")
  
  for i = 1,#waitTimers do
    waitTimers[i].waitTimer:Stop()
  end
end

stopPlayerTimer = Timer.New()
stopPlayerTimer.EventHandler = function() --Stop player AFTER the wait timers have been stopped
  stopPlayerTimer:Stop()
  
  if System.IsEmulating then
    log("Cannot stop files in loop player. The system is in emulation mode.", 3)
  else
    LoopPlayer.Stop({
      Name = components["Loop Player"].name,
      Outputs = routerOutputChannels,
    })
  end
end

holdToStop = Timer.New()
holdToStop.EventHandler = function()
  holdToStop:Stop()
  updateStatusDisplay("")
  stop()
end


--Auto-mute of stopped playback channels
setUpAutoMuteOfPlaybackChannels = function ()
  log("setUpAutoMuteOfPlaybackChannels function called")
  
  local loopPlayer = components["Loop Player"].component
  local playbackRouter = components["Playback Router"].component

  numLoopPlayerChannels = tonumber(components["Loop Player"].properties["Output Count"])
  
  --this table is useful for LoopPlayer commands
  loopPlayerOutputChannels = {}
  for i = 1, numLoopPlayerChannels do
    table.insert(loopPlayerOutputChannels, i)
    
    --watch each channel's playback
    loopPlayer["output."..i..".status"].EventHandler = function (cc)
      
      --update user display
      getNumAvailableLoopPlayerChannels()
      
      --if the channel is stopped...
      if cc.String == "" then
        log("Loop Player channel "..i.." stopped. Router channel(s) muting automatically.")
        
        --look for all router outputs assigned to that channel
        for j = 1, numPlaybackRouterOutputChannels do
          
          --if it matches, mute it
          if playbackRouter["select."..j].Value == i then
            playbackRouter["mute."..j].Boolean = true
          end
        end
      end
    end
  end
end

updateRouterInfo = function()
  log("updateRouterInfo function called")
  
  numPlaybackRouterOutputChannels = tonumber(components["Playback Router"].properties["Output Count"])
  routerOutputChannels = {}
  
  for i = 1, numPlaybackRouterOutputChannels do
    table.insert(routerOutputChannels, i)
  end
  
end

--------------------------
--      CUE LIBRARY     --
--------------------------

getNumberOfCues = function () -- counts cues
  return getCountOfTable(cues)
end

--NAMES
populateCueNames = function () --updates names of cues everywhere
  log('populateCueNames function called')
  
  local numCues = getNumberOfCues()
  
  --write to Cue Library Names
  for i = 1, #Controls.CueLibrary_Name do
    Controls.CueLibrary_Name[i].String = ""
  end
  for k, v in pairs (cues) do
    local name = k
    local orderNum = v.displayOrder
    Controls.CueLibrary_Name[orderNum].String = name
  end
  
  --hide unused Cue Library controls
  for i = 1, #Controls.CueLibrary_MoveDown do
    Controls.CueLibrary_MoveDown[i].IsInvisible = (i >= numCues) --intentionally >=. can't move bottom row down.
  end
  for i = 1, #Controls.CueLibrary_OrderText do
    Controls.CueLibrary_OrderText[i].IsInvisible = (i > numCues)
  end
  for i = 1, #Controls.CueLibrary_Name do
    Controls.CueLibrary_Name[i].IsInvisible = (i > numCues)
  end
  for i = 1, #Controls.CueLibrary_Select do
    Controls.CueLibrary_Select[i].IsInvisible = (i > numCues)
  end
  for i = 1, #Controls.CueLibrary_Test do
    Controls.CueLibrary_Test[i].IsInvisible = (i > numCues)
  end
  
  --write to dropdowns everywhere
  local cueTable = {}
  for i = 1, numCues do
    table.insert(cueTable, Controls.CueLibrary_Name[i].String)
  end
  Controls.CueEditor_Cue.Choices = cueTable
  for i = 1, #Controls.TimeOfDay_Cue do
    Controls.TimeOfDay_Cue[i].Choices = cueTable
  end
  for i = 1, #Controls.DirectRecall_Cue do
    Controls.DirectRecall_Cue[i].Choices = cueTable
  end
  for i = 1, #Controls.CueListEditor_Cue do
    Controls.CueListEditor_Cue[i].Choices = cueTable
  end
  for i = 1, #Controls.Timecode_Cue do
    Controls.Timecode_Cue[i].Choices = cueTable
  end
  for i = 1, #Controls.NetworkTriggers_Cue do
    Controls.NetworkTriggers_Cue[i].Choices = cueTable
  end
  for i = 1, #Controls.ControlWatcher_Cue do
    Controls.ControlWatcher_Cue[i].Choices = cueTable
  end
end

getCueNameFromPosition = function (position) --returns name of cue, given position in list. checks actual cues table instead of Controls
  log('getCueNameFromPosition function called with position #' .. position)
  
  for k,v in pairs (cues) do
    if v.displayOrder == position then
      return k
    end
  end
end

--EDIT CUE NAME
for i = 1, #Controls.CueLibrary_Name do
  Controls.CueLibrary_Name[i].EventHandler = function (cc) --rename cues in tables when user renames
    log('CueLibrary_Name #' .. i .. " text field changed to " .. cc.String)
    
    local oldName = getCueNameFromPosition(i)
    local newName = scrubString(cc.String)
    
    --check for other problems
    if cues[newName] then
      log("Did not rename cue. Cue with name " .. newName .. " already exists.", 2)
      cc.String = oldName
    elseif newName == "" then
      log("Did not rename cue. Cannot use blank name for a cue.", 2)
      cc.String = oldName
    else --okay, you can rename the cue
      cues[newName] = cues[oldName]
      cues[oldName] = nil
      
      --update names everywhere
      if Controls.CueEditor_Cue.String == oldName then
        Controls.CueEditor_Cue.String = newName
      end
      findAndReplace(oldName, newName, true)--search through triggers for references to this cuename
      
      populateCueNames()
      
      writeCurrentDB()
      
      selectCueByName(newName)
    end
  end
end


--SELECTING CUES
selectCueByPosition = function (selectedCuePosition) --selects a cue, given a number in the list
  log('selectCueByPosition function called with position ' ..selectedCuePosition)
  
  local numCues = getNumberOfCues()
  
  if selectedCuePosition > 0 and selectedCuePosition <= numCues then
    
    --radio buttons
    for i = 1, #Controls.CueLibrary_Select do
      Controls.CueLibrary_Select[i].Boolean = (i == selectedCuePosition)
    end
    
    --populate Cue Editor
    local selectedCueName = Controls.CueLibrary_Name[selectedCuePosition].String
    displayCueByName(selectedCueName)
    
  else --cue # is out of bounds of existing cues
    --show nothing is selected
    for i = 1, #Controls.CueLibrary_Select do
      Controls.CueLibrary_Select[i].Boolean = false
    end
    
    displayCueByName("")
    
    log ('Did not select Cue #' .. selectedCuePosition .. ". It does not exist.", 3)
  end
end

selectCueByName = function (name) --selects a cue, given its name
  if not name then
    log('selectCueByName function did not select a cue because no name provided', 2)
  else
    log('selectCueByName function called with name: ' .. name)
    
    local cueNum = nil
    
    --look for number of cue with this name
    for i = 1, #Controls.CueLibrary_Select do
      if Controls.CueLibrary_Name[i].String == name then
        cueNum = i
        break
      end
    end
    
    --select cue using the number you found, or didn't
    if cueNum then
      selectCueByPosition(cueNum)
    else
      log ('Did not select Cue ' .. name .. ". It does not exist in the Cue Library.", 2)
    end
  end
end

getSelectedCueNumber = function () --returns the order# of the selected cue
  log('getSelectedCueNumber function called')
  
  for i = 1, #Controls.CueLibrary_Select do
    if Controls.CueLibrary_Select[i].Boolean then
      return i
    end
  end
end

getSelectedCueName = function () --returns the name of the selected cue
  log('getSelectedCueName function called')
  
  for i = 1, #Controls.CueLibrary_Select do
    if Controls.CueLibrary_Select[i].Boolean then
      return Controls.CueLibrary_Name[i].String
    end
  end
end

--Select buttons
for i = 1, #Controls.CueLibrary_Select do
  Controls.CueLibrary_Select[i].EventHandler = function (cc)
    log('CueLibrary_Select #' .. i .. " button pressed", 3)
    
    selectCueByPosition(i)
  end
end


--MOVE CUES
moveCue = function (fromPosition, toPosition)
  log('moveCue function called. Moving from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingCueName = Controls.CueLibrary_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfCues() then --only move it if there's a place to move to
    
    --get selected cue name
    local selectedCueName = getSelectedCueName()
    
    --make table of order of cues
    local cueLibraryList = {}
    for k,v in pairs (cues) do
      cueLibraryList[v.displayOrder] = k
    end
    
    --shuffle order    
    table.insert(cueLibraryList, toPosition, table.remove(cueLibraryList, fromPosition))
    
    --write new order back to normal table
    for i = 1, #cueLibraryList do
      local cueName = cueLibraryList[i]
      cues[cueName].displayOrder = i
    end
    
    writeCurrentDB()
    
    --write to Controls
    populateCueNames()
    
    --select same cue as before
    selectCueByName(selectedCueName)
    
    log("Moved cue in Cue Libary List. " .. movingCueName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move cue in Cue Library List. No position " .. toPosition .. " exists to move cue " .. movingCueName .. " to.", 2)
  end
end

--Reordering by move buttons
for i = 1, #Controls.CueLibrary_MoveDown do
  Controls.CueLibrary_MoveDown[i].EventHandler = function (cc)
    log('CueLibrary_MoveDown #' .. i .. " button pressed", 3)
    
    moveCue(i, i + 1)
  end
end

--Reordering by order text box
relistCueLibraryOrder = function ()
  log('relistCueLibraryOrder function called')
  
  for i = 1, #Controls.CueLibrary_OrderText do
    Controls.CueLibrary_OrderText[i].String = i
  end
end

for i = 1, #Controls.CueLibrary_OrderText do
  Controls.CueLibrary_OrderText[i].EventHandler = function (cc)
    log('CueLibrary_OrderText #' .. i .. " text field changed to " .. cc.String)
    
    moveCue(i, tonumber(cc.String))
    cc.String = i
  end
end

--Reordering Alphabetically
Controls.CueLibrary_SortAlpha.EventHandler = function ()
  log('CueLibrary_SortAlpha button pressed', 3)
  
  --get selected cue name
  local selectedCueName = getSelectedCueName()
  
  --reorder the table
  local cueTable = {}
  for k,v in pairs (cues) do
    table.insert(cueTable, k)
  end
  table.sort(cueTable)
  for i = 1, #cueTable do
    local cueName = cueTable[i]
    cues[cueName].displayOrder = i
  end
  
  writeCurrentDB()
  
  --reorder controls
  populateCueNames()
  
  --select same cue as before
  selectCueByName(selectedCueName)
  
  log("Sorted Cue Libary List alphabetically.", 3)
end


--COPY/CUT/INSERT/DELETE CUES
copiedCue = nil
copiedCueName = ""
Controls.CueLibrary_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

updateCueDisplayOrdersFromOrderedTable = function (cueTable) --writes new displayOrders to the cues table, given an indexed table
  log('updateCueDisplayOrdersFromOrderedTable function ran')
  
  for i = 1, #cueTable do
    local name = cueTable[i]    
    cues[name].displayOrder = i
  end
end

copyCue = function (cueName) --copies a cue to the "clipboard"
  log('copyCue function called with cueName ' .. cueName)
  
  copiedCue = copy(cues[cueName])
  copiedCueName = cueName
  
  Controls.CueLibrary_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

getOrderedCueTable = function () --returns an indexed table: index = cue order #, value = cue name
  log('getOrderedCueTable function called')
  
  local cueTable = {}
  
  for k,v in pairs (cues) do
    local position = cues[k].displayOrder
    local name = k
    cueTable[position] = name
  end
  
  return cueTable
end

deleteCue = function (cueName) --deletes a cue from the library & shifts everything up.
  log('deleteCue function called with cueName ' .. cueName)
  
  --get ordered table
  local cueTable = getOrderedCueTable()
  
  --remove deleted cue
  cues[cueName] = nil --must remove this after pulling the ordered table so that everything stays sequential with no gaps
  
  for i = 1, #cueTable do --also remove from ordered table
    if cueTable[i] == cueName then
      table.remove(cueTable, i)
      break
    end
  end
  
  --write new displayOrders to cues table
  updateCueDisplayOrdersFromOrderedTable(cueTable)
  
  writeCurrentDB()
  
  --write to Controls
  populateCueNames()
  
  --select next cue
  local numCues = getNumberOfCues()
  local thisCue = getSelectedCueNumber()
  local cueToSelect = math.min(numCues, thisCue) --what if you deleted last cue? choose the last cue in the new list
  selectCueByPosition(cueToSelect)
end

addCue = function (cueData, cueName, destinationOrder) --duplicates the cue in the clipboard to the selected position. bumps cues down.
  log('addCue function called with cueName ' .. cueName .. ' into position ' .. destinationOrder)
  
  if getNumberOfCues() + 1 <= #Controls.CueLibrary_Name then
    
    local cueTable = getOrderedCueTable() --get ordered table of existing cues
    local cueNameToPaste = cueName --get what to name this cue
    
    --change name of copied cue if pasting it would cause duplicate name
    local spotToCheck = 1
    while #cueTable >= spotToCheck do
      if cueTable[spotToCheck] == cueNameToPaste then
        spotToCheck = 0 --start over, because what if earlier name is now a duplicate?
        cueNameToPaste = cueNameToPaste .. "^"
      end
      spotToCheck = spotToCheck + 1
    end
    
    --add copied cue to main table
    cueData.displayOrder = destinationOrder
    cues[cueNameToPaste] = copy(cueData)
    
    --add copied cue to local ordered table
    table.insert(cueTable, destinationOrder, cueNameToPaste)
    
    --write new displayOrders to the cues table from the ordered table
    updateCueDisplayOrdersFromOrderedTable(cueTable)
    
    writeCurrentDB()
    
    --write to Controls
    populateCueNames()
    
    --select this cue
    selectCueByPosition(destinationOrder)
    
    log("Cue " .. cueNameToPaste .. " added in position " .. destinationOrder, 3)
    
  else
    log("Cue was not added. There isn't enough room in the Cue Library Controls: Controls.CueLibrary_Name", 2)
  end
end

Controls.CueLibrary_Copy.EventHandler = function ()
  log('CueLibrary_Copy button pressed', 3)
  
  local name = getSelectedCueName()
  
  copyCue(name)
end

Controls.CueLibrary_Delete.EventHandler = function ()
  log('CueLibrary_Delete button pressed', 3)
  
  local name = getSelectedCueName()
  
  deleteCue(name)
end

Controls.CueLibrary_Cut.EventHandler = function ()
  log('CueLibrary_Cut button pressed', 3)
  
  local name = getSelectedCueName()
  
  copyCue(name)
  deleteCue(name)
end

Controls.CueLibrary_Insert.EventHandler = function ()
  log('CueLibrary_Insert button pressed', 3)
  
  if not copiedCue then
    log("No cue inserted. No cue has been copied or cut.", 2)
    
  else
    local destinationOrder = getSelectedCueNumber() or 1
    
    addCue(copiedCue, copiedCueName, destinationOrder)
  end
end

Controls.CueLibrary_New.EventHandler = function ()
  log('CueLibrary_New button pressed', 3)
  
  -- add the cue
  local newCueData = {cueLines = {}}
  local cueName = "New Cue"
  local destinationOrder = ( getSelectedCueNumber() or 0 ) + 1 --if selected is nil, there aren't any cues yet, so make this in position 1
  
  addCue(newCueData, cueName, destinationOrder)
  
  -- add the default cue line
  local newCueLineData = {name = "New Cue Line", wait = 0, func = "-----", }
  local destinationOrder = 1

  addCueLine(newCueLineData, destinationOrder)
  
end

--TEST CUES
for i = 1, #Controls.CueLibrary_Test do
  Controls.CueLibrary_Test[i].EventHandler = function ()
    log('CueLibrary_Test button #' .. i .. ' pressed', 3)
    
    local cueToExecute = Controls.CueLibrary_Name[i].String
    
    rehearsalTime = 0 --reset to 0, in case there's a leftover rehearsal time
    
    executeCue(cueToExecute)
  end
end


--------------------------
--      CUE EDITOR      --
--------------------------

--SELECT CUE
Controls.CueEditor_Cue.EventHandler = function (cc)
  selectCueByName(cc.String)
end

--DISPLAY CUE INFO
displayCueByName = function (cueName)
  log('displayCueByName function called with cueName ' .. cueName)
  
  --display name in Cue Editor selection dropdown
  Controls.CueEditor_Cue.String = cueName
  
  --display cue lines
  local numCueLines = 0
  if cues[cueName] then
    numCueLines = #cues[cueName].cueLines
  end
  
  for i = 1, numCueLines do
    Controls.CueEditor_TestCueLine[i].IsInvisible = false
    
    Controls.CueEditor_MoveDown[i].IsInvisible = false
    
    Controls.CueEditor_OrderText[i].IsInvisible = false
    
    Controls.CueEditor_Name[i].String = cues[cueName].cueLines[i].name
    Controls.CueEditor_Name[i].IsInvisible = false
    
    Controls.CueEditor_Wait[i].String = cues[cueName].cueLines[i].wait
    Controls.CueEditor_Wait[i].IsInvisible = false
    
    Controls.CueEditor_Function[i].String = cues[cueName].cueLines[i].func
    Controls.CueEditor_Function[i].IsInvisible = false
    
    Controls.CueEditor_Info[i].IsInvisible = false
    
    Controls.CueEditor_Select[i].IsInvisible = false
  end
  
  --hide unused cue lines  --There's probably cleaner way to do this invisibility thing. Not if we're counting each Control set individually.
  for i = numCueLines + 1, #Controls.CueEditor_TestCueLine do
    Controls.CueEditor_TestCueLine[i].IsInvisible = true
  end
  for i = math.max(numCueLines, 1), #Controls.CueEditor_MoveDown do--must be at least 1 because no Control #0. Intentionally not + 1. Can't move the bottom row down.
    Controls.CueEditor_MoveDown[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_OrderText do
    Controls.CueEditor_OrderText[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_Name do
    Controls.CueEditor_Name[i].String = ""
    Controls.CueEditor_Name[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_Wait do
    Controls.CueEditor_Wait[i].String = ""
    Controls.CueEditor_Wait[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_Function do
    Controls.CueEditor_Function[i].String = ""
    Controls.CueEditor_Function[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_Info do
    Controls.CueEditor_Info[i].IsInvisible = true
  end
  for i = numCueLines + 1, #Controls.CueEditor_Select do
    Controls.CueEditor_Select[i].IsInvisible = true
  end
  
  --select the first cue line, in case this cue doesn't have multiple cue lines
  selectCueLine(1)
end


--SELECT CUE LINE
getSelectedCueLineNumber = function ()
  local cueLineNumber = nil
  
  for i = 1, #Controls.CueEditor_Select do
    if Controls.CueEditor_Select[i].Boolean then
      cueLineNumber = i
      break
    end
  end
  
  return cueLineNumber
end

clearTableMakerControls = function ()
  log('clearTableMakerControls function called')
  
  for i = 1, #Controls.CueEditor_Type do
    Controls.CueEditor_Value[i].IsDisabled = false
  end
  
  Controls.TableMaker_Filter.IsInvisible = true
  
  for i = 1, #Controls.TableMaker_FileNameText do
    Controls.TableMaker_FileNameText[i].String = ""
    Controls.TableMaker_FileNameText[i].IsInvisible = true
  end
  for i = 1, #Controls.TableMaker_FileNameCombo do
    Controls.TableMaker_FileNameCombo[i].String = "..."
    Controls.TableMaker_FileNameCombo[i].IsInvisible = true
  end
  for i = 1, #Controls.TableMaker_Gain do
    Controls.TableMaker_Gain[i].String = ""
    Controls.TableMaker_Gain[i].IsInvisible = true
    
  end
  for i = 1, #Controls.TableMaker_Outputs do
    Controls.TableMaker_Outputs[i].String = ""
    Controls.TableMaker_Outputs[i].IsInvisible = true
    
  end
end

selectCueLine = function (cueLineNumber)
  log('selectCueLine function called with cue line #' .. cueLineNumber)
  
  local numCueLines = getNumberOfCueLines()
  
  if cueLineNumber > 0 and cueLineNumber <= numCueLines then
    
    --radio buttons
    for i = 1, #Controls.CueEditor_Select do
      Controls.CueEditor_Select[i].Boolean = (i == cueLineNumber)
    end
    
    local cueName = Controls.CueEditor_Cue.String
    local funcName = cues[cueName].cueLines[cueLineNumber].func
    
    if funcName == funcs[funcName] then
      log('Function Parameters cannot display. ' .. funcName .. ' does not exist.')
      
    else
      local numFunctionParameters = #funcs[funcName].params
      local tableMakerUsed = false
      
      for i = 1, numFunctionParameters do
        --get list of parameters from function library
        local parameterName = funcs[funcName].params[i].name
        Controls.CueEditor_Parameter[i].String = parameterName
        Controls.CueEditor_Type[i].String = funcs[funcName].params[i].varType
        Controls.CueEditor_Required[i].String = tostring(funcs[funcName].params[i].isRequired)
        
        --get info specific to this cue
        local parameter = cues[cueName].cueLines[cueLineNumber].funcParams[parameterName]
        local formattedParameter = parameter
        
        --display string in control. will vary based on parameter type
        if funcs[funcName].params[i].varType == "Table" and (funcName == "Play Audio Files" or funcName == "Play with alternate output") then
          
          --use empty table if otherwise nil
          parameter = parameter or {}
          
          --Function Parameter Control
          formattedParameter = "Please use Table Maker"
          Controls.CueEditor_Value[i].IsDisabled = true
            
          --Table Maker controls
          tableMakerUsed = true
          
          Controls.TableMaker_Filter.IsInvisible = not tableMakerUsed
          
          for i = 1, #Controls.TableMaker_Gain do
            Controls.TableMaker_Gain[i].IsInvisible = false
            Controls.TableMaker_Outputs[i].IsInvisible = false
            Controls.TableMaker_FileNameCombo[i].IsInvisible = false
            Controls.TableMaker_FileNameText[i].IsInvisible = false
          end
          
          --get info from parameter
          for i = 1, #parameter do
            --if not yet defined, then make table
            parameter[i] = parameter[i] or {fileName = nil, gain = nil, outputs = {}}
            
            Controls.TableMaker_FileNameText[i].String = parameter[i].fileName or ""
            Controls.TableMaker_Gain[i].String = parameter[i].gain or ""
            if type(parameter[i].outputs) == "table" then
              Controls.TableMaker_Outputs[i].String = tableToString(parameter[i].outputs)
            else
              Controls.TableMaker_Outputs[i].String = parameter[i].outputs or ""
            end
          end
          
          --show blanks for extra rows
          for i = #parameter + 1, #Controls.TableMaker_FileNameText do
            Controls.TableMaker_FileNameText[i].String = ""
          end
          for i = #parameter + 1, #Controls.TableMaker_FileNameCombo do
            Controls.TableMaker_FileNameCombo[i].String = "..."
          end
          for i = #parameter + 1, #Controls.TableMaker_Gain do
            Controls.TableMaker_Gain[i].String = ""
          end
          for i = #parameter + 1, #Controls.TableMaker_Outputs do
            Controls.TableMaker_Outputs[i].String = ""
          end
          
          --populate dropdown choices with file names
          local dropdownChoices = {}
          if not System.IsEmulating then
            dropdownChoices = filter(getDirectoryFileNames(), Controls.TableMaker_Filter.String)
          end
          for i = 1, #Controls.TableMaker_FileNameCombo do
            Controls.TableMaker_FileNameCombo[i].Choices = dropdownChoices
          end

        elseif parameter == nil then
          formattedParameter = ""
        else
          formattedParameter = tostring(parameter)
        end
        
        Controls.CueEditor_Value[i].String = formattedParameter
        
        --show used rows
        Controls.CueEditor_Parameter[i].IsInvisible = false
        Controls.CueEditor_Type[i].IsInvisible = false
        Controls.CueEditor_Required[i].IsInvisible = false
        Controls.CueEditor_Value[i].IsInvisible = false
      end
      
      --clear out table maker if it's not used
      if not tableMakerUsed then
        clearTableMakerControls()
      end
      
      --hide unused rows
      for i = numFunctionParameters + 1, #Controls.CueEditor_Parameter do
        Controls.CueEditor_Parameter[i].IsInvisible = true
      end
      for i = numFunctionParameters + 1, #Controls.CueEditor_Type do
        Controls.CueEditor_Type[i].IsInvisible = true
      end
      for i = numFunctionParameters + 1, #Controls.CueEditor_Required do
        Controls.CueEditor_Required[i].IsInvisible = true
      end
      for i = numFunctionParameters + 1, #Controls.CueEditor_Value do
        Controls.CueEditor_Value[i].IsInvisible = true
      end
    end
    
  else --if selected cue line # is outside of range of existing cue lines
    log('Did not select Cue Line #' .. cueLineNumber .. '. It does not exist in this cue.', 3)
    
    --show nothing is selected
    for i = 1, #Controls.CueEditor_Select do
      Controls.CueEditor_Select[i].Boolean = false
    end
    
    --hide function parameters
    for i = 1, #Controls.CueEditor_Parameter do
      Controls.CueEditor_Parameter[i].IsInvisible = true
    end
    for i = 1, #Controls.CueEditor_Type do
      Controls.CueEditor_Type[i].IsInvisible = true
    end
    for i = 1, #Controls.CueEditor_Required do
      Controls.CueEditor_Required[i].IsInvisible = true
    end
    for i = 1, #Controls.CueEditor_Value do
      Controls.CueEditor_Value[i].IsInvisible = true
    end
  end
end

for i = 1, #Controls.CueEditor_Select do
  Controls.CueEditor_Select[i].EventHandler = function ()
    log('CueEditor_Select #' .. i .. ' button pressed', 3)
    
    selectCueLine(i)
  end
end


--EDIT CUE LINE
for i = 1, #Controls.CueEditor_Name do
  Controls.CueEditor_Name[i].EventHandler = function (cc) --rename cue lines in table when user renames
    local newName = scrubString(cc.String)
    
    log('CueEditor_Name #' .. i .. " text field changed to " .. newName)
    
    local selectedCue = getSelectedCueName()
    cues[selectedCue].cueLines[i].name = newName
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.CueEditor_Wait do
  Controls.CueEditor_Wait[i].EventHandler = function (cc) --update cue lines in table when user edits
    log('CueEditor_Wait #' .. i .. " text field changed to " .. cc.String)
    
    local selectedCue = getSelectedCueName()
    cues[selectedCue].cueLines[i].wait = tonumber(cc.String)
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.CueEditor_Function do
  Controls.CueEditor_Function[i].EventHandler = function (cc) --update cue lines in table when user chooses new function
    log('CueEditor_Function #' .. i .. " text field changed to " .. cc.String)
    
    local selectedCue = getSelectedCueName()
    local selectedCueLine = cues[selectedCue].cueLines[i]
    selectedCueLine.func = cc.String
    selectedCueLine.funcParams = {} --clear out old parameters
    
    selectCueLine(i) --update Function Parameters with new function's info
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.CueEditor_Value do
  Controls.CueEditor_Value[i].EventHandler = function (cc) --rename cue lines in table when user renames
    log('CueEditor_Value #' .. i .. " text field changed to " .. cc.String)
    
    local selectedCue = getSelectedCueName()
    local selectedCueLine = getSelectedCueLineNumber()
    local funcName = cues[selectedCue].cueLines[selectedCueLine].func
    local variableType = string.lower(funcs[funcName].params[i].varType)
    local parameterName = Controls.CueEditor_Parameter[i].String
    
    --clean up incomming parameter from user
    local formattedParameter = nil
    if variableType == "value" or variableType == "integer" or variableType == "number" then
      formattedParameter = tonumber(cc.String)
    elseif variableType == "boolean" or variableType == "bool" then
      formattedParameter = toboolean(cc.String)
    elseif variableType == "table" then
      formattedParameter = stringToTable(cc.String)
    else
      formattedParameter = cc.String
    end
    
    --write clean parameter to lua table, Control, and database
    cues[selectedCue].cueLines[selectedCueLine].funcParams[parameterName] = formattedParameter
    cc.String = tostring(formattedParameter)
    writeCurrentDB()
  end
end


--MOVING CUE LINES
getNumberOfCueLines = function ()
  log('getNumberOfCueLines function called')
  
  local selectedCue = getSelectedCueName()
  local numCueLines = 0
  if cues[selectedCue] then
    numCueLines = #cues[selectedCue].cueLines
  end
  
  return numCueLines
end

moveCueLine = function (fromPosition, toPosition)
  log('moveCueLine function called. Moving cue line from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingCueLineName = Controls.CueEditor_Name[fromPosition].String
  local selectedCueLineNumber = getSelectedCueLineNumber()
  
  if toPosition > 0 and toPosition <= getNumberOfCueLines() then --only move it if there's a place to move to
    
    --get info of currently selected things
    local selectedCueName = getSelectedCueName()
    local selectedCueLine = nil
    
    for i = 1, #Controls.CueEditor_Select do
      if Controls.CueEditor_Select[i].Boolean then
        selectedCueLine = i
        break
      end
    end
    
    --update table of cues
    local cueLineTable = cues[selectedCueName].cueLines
    cues[selectedCueName].cueLines[selectedCueLine].IsSelected = true --mark this cue line so we can trace it through the move
    table.insert(cueLineTable, toPosition, table.remove(cueLineTable, fromPosition))
    
    --select this cue to display updated cue lines
    selectCueByName(selectedCueName)
    
    --select same cue line as before
    local cueLineToSelect = nil
    for i = 1, #cues[selectedCueName].cueLines do --find the marked cue line
      if cues[selectedCueName].cueLines[i].IsSelected then
        cueLineToSelect = i
        break
      end
    end
    selectCueLine(cueLineToSelect)
    cues[selectedCueName].cueLines[selectedCueLine].IsSelected = nil
    
    relistCueEditorOrder()
     
    writeCurrentDB()
    
    log("Moved cue line in Cue Editor. " .. movingCueLineName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move cue in Cue Editor. No position " .. toPosition .. " exists to move cue " .. movingCueLineName .. " to.", 2)
  end
end

for i = 1, #Controls.CueEditor_MoveDown do
  Controls.CueEditor_MoveDown[i].EventHandler = function ()
    log('CueEditor_MoveDown button #' .. i .. ' pressed', 3)
    
    moveCueLine(i, i + 1)
  end
end

relistCueEditorOrder = function ()
  log('relistCueEditorOrder function called')
  
  for i = 1, #Controls.CueEditor_OrderText do
    Controls.CueEditor_OrderText[i].String = i
  end
end

for i = 1, #Controls.CueEditor_OrderText do
  Controls.CueEditor_OrderText[i].EventHandler = function (cc)
    log('CueEditor_OrderText #' .. i .. ' changed to ' .. cc.String)
    
    moveCueLine(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end


--COPY/CUT/INSERT/DELETE CUE LINES
copiedCueLine = nil
copiedCueLineName = ""
Controls.CueEditor_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyCueLine = function ()
  log('copyCueLine function called')
  
  local selectedCue = getSelectedCueName()
  
  if not selectedCue then
    log("No Cue Line was copied. There is no Cue selected to copy the Cue Line from.", 2)
    
  else --actually copy the cue line
    local selectedCueLineNumber = getSelectedCueLineNumber()
    local selectedCueLine = cues[selectedCue].cueLines[selectedCueLineNumber]
    
    copiedCueLine = copy(selectedCueLine)
    copiedCueLineName = Controls.CueEditor_Name[selectedCueLineNumber].String
    
    Controls.CueEditor_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
  end
end

deleteCueLine = function ()
  log('deleteCueLine function called')
  
  local selectedCue = getSelectedCueName()
  local selectedCueLineNumber = getSelectedCueLineNumber()
  
  if not selectedCue then
    log("No Cue Line was deleted. There is no Cue selected to delete the Cue Line from.", 2)
  
  else--actually delete the cue line
    table.remove(cues[selectedCue].cueLines, selectedCueLineNumber)  
    selectCueByName(selectedCue) --refresh Cue Editor
    
    local numCueLines = getNumberOfCueLines()
    local cueLineToSelect = math.min(selectedCueLineNumber, numCueLines)--what if you deleted last cue in the stack? then pick the last cue
    selectCueLine(cueLineToSelect) --refresh Function Parameters
    
    writeCurrentDB()
  end
  
  -- TODO this is a workaround for a bug. To recreate: delete all cue lines from a cue, rename the cue. New cue lines in that cue won't save to json database.
  if getNumberOfCueLines() < 1 then 
    local newCueLineData = {name = "New Cue Line", wait = 0, func = "-----", }
    local destinationOrder = 1

    addCueLine(newCueLineData, destinationOrder)
  end
  
end

addCueLine = function (cueLineData, destinationOrder)
  log('addCueLine function called with destinationOrder: ' .. destinationOrder)
  
  local selectedCue = getSelectedCueName()
  
  if not selectedCue then
    log("No Cue Line was created. There is no Cue selected to create the Cue Line in.", 2)
    
  elseif #cues[selectedCue].cueLines + 1 > #Controls.CueEditor_Name then
    log("No Cue Line was created. There isn't enough room in the Cue Editor controls: Controls.CueEditor_Name", 2)
  
  else --actually make the cue line
    table.insert(cues[selectedCue].cueLines, destinationOrder, cueLineData)  
    selectCueByName(selectedCue) --refresh Cue Editor
    selectCueLine(destinationOrder)
    
    writeCurrentDB()
  end
end

Controls.CueEditor_Copy.EventHandler = function ()
  log('CueEditor_Copy button pressed', 3)
  
  copyCueLine()
end

Controls.CueEditor_Delete.EventHandler = function ()
  log('CueEditor_Delete button pressed', 3)
  
  deleteCueLine()
end

Controls.CueEditor_Cut.EventHandler = function ()
  log('CueEditor_Cut button pressed', 3)
  
  copyCueLine()
  deleteCueLine()
end

Controls.CueEditor_Insert.EventHandler = function ()
  log('CueEditor_Insert button pressed', 3)
  
  local cueLineData = copy(copiedCueLine)
  local destinationOrder = getSelectedCueLineNumber() or 1
  
  addCueLine(cueLineData, destinationOrder)
end

Controls.CueEditor_New.EventHandler = function ()
  log('CueEditor_New button pressed', 3)
  
  local newCueLineData = {name = "New Cue Line", wait = 0, func = "-----", }
  local destinationOrder = ( getSelectedCueLineNumber() or 0 ) + 1

  addCueLine(newCueLineData, destinationOrder)
end


--TEST CUE
executeCue = function (cueName)
  log('executeCue function called with cueName ' .. cueName, 3)
  
  if not cues[cueName] then
    log('Did not execute cue. Cue ' .. cueName .. ' not found in Cue Library.', 2)
  
  else
    for i = 1, #cues[cueName].cueLines do
      executeCueLine(cueName, i, true)
    end
  end
end

Controls.CueEditor_TestCue.EventHandler = function ()
  log('CueEditor_TestCue button pressed', 3)
  
  local selectedCueName = getSelectedCueName()

  rehearsalTime = 0 --reset to 0, in case there's a leftover rehearsal time

  executeCue(selectedCueName)
end


--TEST CUE LINES
executeCueLine = function (cueName, cueLineNumber, includeWaitTime)
  log('executeCueLine function called. cueName = ' .. cueName .. '  cueLineNumber = ' .. cueLineNumber .. '  includeWaitTime = ' .. tostring(includeWaitTime))
  
  local cueLine = cues[cueName].cueLines[cueLineNumber]
  local paramsTable = cueLine.funcParams
  local missingInfo = false
  
  --set wait time
  local waitTime = 0
  if includeWaitTime then
    waitTime = cueLine.wait
  end
  
  local funcName = cueLine.func
  
  if not funcs[funcName] then
    log('Did not execute Cue Line ' .. cueName .. ' #' .. cueLineNumber .. '. Function ' .. funcName .. " not found in Script's Function List.")
    
  else
    local actualFunction = funcs[funcName].func
    local orderedParamsTable = {}
    
    for i = 1, #funcs[funcName].params do
      local paramName = funcs[funcName].params[i].name
      local paramValue = paramsTable[paramName]
      if paramValue == nil and funcs[funcName].params[i].isRequired then
        log("Cue \"" .. cueName .. " Line " .. cueLineNumber .. "\" did not trigger: " .. paramName .. " required.", 1)
        missingInfo = true
        break
      end
      orderedParamsTable[i] = paramValue or funcs[funcName].params[i].default
    end
    
    if not missingInfo then
      wait(waitTime, actualFunction, table.unpack(orderedParamsTable))
    end
  end
end

for i = 1, #Controls.CueEditor_TestCueLine do
  Controls.CueEditor_TestCueLine[i].EventHandler = function ()
    log('CueEditor_TestCueLine button #' .. i .. ' pressed', 3)
    
    local selectedCue = getSelectedCueName()
    local includeWaitTime = prefValues["Include Wait in Cue Line Test"]
    
    executeCueLine(selectedCue, i, includeWaitTime)
  end
end

--------------------------
--      TABLE MAKER     --
--------------------------

getAudioFilesTable = function ()
  log('getAudioFilesTable function called')
  
  --build table of rows that have data
  local audioFilesTable = {}
  
  for i = 1, #Controls.TableMaker_FileNameText do
    local fileName = Controls.TableMaker_FileNameText[i].String
    local gain = tonumber(Controls.TableMaker_Gain[i].String)
    
    -- get outputs from string
    local outputs = {}
    for num in string.gmatch(Controls.TableMaker_Outputs[i].String, "[%d^/]+") do
      local numTable = {}
      
      -- if alternate outputs have been input
      if string.find(num, "/") then
        for alt in string.gmatch(num, "%d+") do
          table.insert(numTable, alt)
        end
        table.insert(outputs, numTable)
        
      else
        table.insert(outputs, tonumber(num))
      end
    end
    
    if fileName ~= "" or gain or #outputs ~= 0 then
      local audioFileRow = {fileName = fileName, gain = gain, outputs = outputs}
      table.insert(audioFilesTable, audioFileRow)
    end
  end
  
  return audioFilesTable
end

checkTableMakerValues = function (index)
  if Controls.TableMaker_Outputs[index].String == "" and Controls.TableMaker_FileNameText[index].String ~= "" and Controls.TableMaker_FileNameText[index].String ~= "Please enter a file name" then
    Controls.TableMaker_Outputs[index].Color = "red"
  else
    Controls.TableMaker_Outputs[index].Color = ""
  end
  
  if Controls.TableMaker_FileNameText[index].String == "" and Controls.TableMaker_Outputs[index].String ~= "" and Controls.TableMaker_Outputs[index].String ~= "Please enter an output value" then
    Controls.TableMaker_FileNameText[index].Color = "red"
  else
    Controls.TableMaker_FileNameText[index].Color = ""
  end
  
end

writeTableMakerToDatabase = function ()
  log('writeTableMakerToDatabase function called')
  
  local selectedCue = getSelectedCueName()
  local selectedCueLineNumber = getSelectedCueLineNumber()
  local selectedCueLine = cues[selectedCue].cueLines[selectedCueLineNumber]
  local selectedParameter = nil
  
  for i = 1, #Controls.CueEditor_Type do
    if Controls.CueEditor_Type[i].String == "Table" then
      selectedParameter = i
      break
    end
  end
  
  selectedCueLine.funcParams["Audio Files Table"] = getAudioFilesTable()
  
  writeCurrentDB()
end

Controls.TableMaker_Filter.EventHandler = function(cc)
  
  local files = filter(getDirectoryFileNames(), cc.String)
  for i = 1, #Controls.TableMaker_FileNameCombo do
    Controls.TableMaker_FileNameCombo[i].Choices = files
  end
end

for i = 1, #Controls.TableMaker_FileNameText do
  Controls.TableMaker_FileNameText[i].EventHandler = function (cc) --update cue lines in table when user chooses new function
    log('TableMaker_FileNameText #' .. i .. " text field changed to " .. cc.String)
    
    Controls.TableMaker_FileNameCombo[i].String = cc.String
    
    checkTableMakerValues(i)
    
    writeTableMakerToDatabase()
  end
end

for i = 1, #Controls.TableMaker_FileNameCombo do
  Controls.TableMaker_FileNameCombo[i].EventHandler = function (cc) --update cue lines in table when user chooses new function
    log('TableMaker_FileNameCombo #' .. i .. " text field changed to " .. cc.String)
    
    Controls.TableMaker_FileNameText[i].String = cc.String
    cc.String = "..."
    checkTableMakerValues(i)
    
    writeTableMakerToDatabase()
  end
end

for i = 1, #Controls.TableMaker_Gain do
  Controls.TableMaker_Gain[i].EventHandler = function (cc) --update cue lines in table when user chooses new function
    log('TableMaker_Gain #' .. i .. " text field changed to " .. cc.String)
    
    writeTableMakerToDatabase()
  end
end

for i = 1, #Controls.TableMaker_Outputs do
  Controls.TableMaker_Outputs[i].EventHandler = function (cc) --update cue lines in table when user chooses new function
    log('TableMaker_Outputs #' .. i .. " text field changed to " .. cc.String)
    
    checkTableMakerValues(i)
    
    writeTableMakerToDatabase()
  end
end

--Reordering Alphabetically
Controls.TableMaker_SortAlpha.EventHandler = function ()
  log('TableMaker_SortAlpha button pressed', 3)
  
  --reorder the table
  local audioFilesTable = getAudioFilesTable()
  table.sort(audioFilesTable, sortByFileName)

  --save
  local selectedCue = getSelectedCueName()
  local selectedCueLineNumber = getSelectedCueLineNumber()
  local selectedCueLine = cues[selectedCue].cueLines[selectedCueLineNumber]
  local selectedParameter = nil
  
  for i = 1, #Controls.CueEditor_Type do
    if Controls.CueEditor_Type[i].String == "Table" then
      selectedParameter = i
      break
    end
  end
  
  selectedCueLine.funcParams["Audio Files Table"] = audioFilesTable
  
  writeCurrentDB()
  
  --reorder controls
  selectCueLine(selectedCueLineNumber)
  
  for i = 1, #Controls.TableMaker_Outputs do
    checkTableMakerValues(i)
  end
  
  log("Sorted Audio Files alphabetically.", 3)
end

--Reordering By Output
Controls.TableMaker_SortOutputs.EventHandler = function ()
  log('TableMaker_SortOutputs button pressed', 3)
  
  --reorder the table
  local audioFilesTable = getAudioFilesTable()
  table.sort(audioFilesTable, sortByoutputs)
  
  --save
  local selectedCue = getSelectedCueName()
  local selectedCueLineNumber = getSelectedCueLineNumber()
  local selectedCueLine = cues[selectedCue].cueLines[selectedCueLineNumber]
  local selectedParameter = nil
  
  for i = 1, #Controls.CueEditor_Type do
    if Controls.CueEditor_Type[i].String == "Table" then
      selectedParameter = i
      break
    end
  end
  
  selectedCueLine.funcParams["Audio Files Table"] = audioFilesTable
  
  writeCurrentDB()
  
  --reorder controls
  selectCueLine(selectedCueLineNumber)
  
  for i = 1, #Controls.TableMaker_Outputs do
    checkTableMakerValues(i)
  end
  
  log("Sorted Audio Files by Outputs.", 3)
end



--------------------------
--    DIRECT RECALLS    --
--------------------------

--DISPLAY DIRECT RECALLS
populateDirectRecalls = function ()
  log('populateDirectRecalls function called')
  
  --show the info for existing data
  for i = 1, #directRecalls do
    Controls.DirectRecall_Trigger[i].Legend = directRecalls[i].name
    Controls.DirectRecall_Trigger[i].IsInvisible = false
    
    Controls.DirectRecall_Name[i].String = directRecalls[i].name
    Controls.DirectRecall_Name[i].IsInvisible = false
    
    Controls.DirectRecall_Cue[i].String = directRecalls[i].cue
    Controls.DirectRecall_Cue[i].IsInvisible = false
    
    Controls.DirectRecall_MoveDown[i].IsInvisible = false
    Controls.DirectRecall_OrderText[i].IsInvisible = false
    Controls.DirectRecall_Select[i].IsInvisible = false
  end
  --hide the rest
  for i = #directRecalls + 1, #Controls.DirectRecall_Trigger do
    Controls.DirectRecall_Trigger[i].Legend = ""
    Controls.DirectRecall_Trigger[i].IsInvisible = true
  end
  for i = #directRecalls + 1, #Controls.DirectRecall_Name do
    Controls.DirectRecall_Name[i].String = ""
    Controls.DirectRecall_Name[i].IsInvisible = true
  end
  for i = #directRecalls + 1, #Controls.DirectRecall_Cue do
    Controls.DirectRecall_Cue[i].String = ""
    Controls.DirectRecall_Cue[i].IsInvisible = true
  end
  for i = math.max(#directRecalls, 1), #Controls.DirectRecall_MoveDown do --can't move the last one down
    Controls.DirectRecall_MoveDown[i].IsInvisible = true
  end
  for i = #directRecalls + 1, #Controls.DirectRecall_OrderText do
    Controls.DirectRecall_OrderText[i].IsInvisible = true
  end
  for i = #directRecalls + 1, #Controls.DirectRecall_Select do
    Controls.DirectRecall_Select[i].IsInvisible = true
  end
end

for i = 1, #Controls.DirectRecall_Trigger do
  Controls.DirectRecall_Trigger[i].EventHandler = function ()
    log('DirectRecall_Trigger button # ' .. i .. " pressed", 3)
    
    local cueName = Controls.DirectRecall_Cue[i].String
    
    executeCue(cueName)
  end
end

--EDIT DIRECT RECALLS
for i = 1, #Controls.DirectRecall_Name do
  Controls.DirectRecall_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('DirectRecall_Name # ' .. i .. " changed to " .. newName)
    
    directRecalls[i].name = newName
    Controls.DirectRecall_Trigger[i].Legend = newName
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.DirectRecall_Cue do
  Controls.DirectRecall_Cue[i].EventHandler = function (cc)
    log('DirectRecall_Cue # ' .. i .. " changed to " .. cc.String)
    directRecalls[i].cue = cc.String
    writeCurrentDB()
  end
end


--SELECT DIRECT RECALLS
getSelectedDirectRecallNumber = function ()
  log('getSelectedDirectRecallNumber function called')
  
  local directRecallNumber = nil
  
  for i = 1, #Controls.DirectRecall_Select do
    if Controls.DirectRecall_Select[i].Boolean then
      directRecallNumber = i
      break
    end
  end
  
  return directRecallNumber
end

selectDirectRecall = function (directRecallNumber)
  log('selectDirectRecall function called with direct recall #' .. directRecallNumber)
  
  local numDirectRecalls = getNumberOfDirectRecalls()
  
  if directRecallNumber > 0 and directRecallNumber <= numDirectRecalls then
    
    --radio buttons
    for i = 1, #Controls.DirectRecall_Select do
      Controls.DirectRecall_Select[i].Boolean = (i == directRecallNumber)
    end
  
  else --if selected direct recall # is outside of range of existing direct recall
    
    --show nothing is selected
    for i = 1, #Controls.DirectRecall_Select do
      Controls.DirectRecall_Select[i].Boolean = false
    end
    
    log('Did not select Direct Recall #' .. directRecallNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.DirectRecall_Select do
  Controls.DirectRecall_Select[i].EventHandler = function ()
    log('DirectRecall_Select #' .. i .. ' button pressed', 3)
    
    selectDirectRecall(i)
  end
end


--MOVING DIRECT RECALLS
getNumberOfDirectRecalls = function ()
  log('getNumberOfDirectRecalls function called')
  
  return #directRecalls
end

moveDirectRecall = function (fromPosition, toPosition)
  log('moveDirectRecall function called. Moving direct recall from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingDirectRecallName = Controls.DirectRecall_Name[fromPosition].String
  
  if toPosition <= 0 or toPosition > getNumberOfDirectRecalls() then --only move it if there's a place to move to
    log("Did not move direct recall. No position " .. toPosition .. " exists to move " .. movingDirectRecallName .. " to.", 2)
    
  else
    local selectedDirectRecall = nil
    for i = 1, #Controls.DirectRecall_Select do
      if Controls.DirectRecall_Select[i].Boolean then
        selectedDirectRecall = i
        break
      end
    end
    
    --update database
    directRecalls[selectedDirectRecall].IsSelected = true
    table.insert(directRecalls, toPosition, table.remove(directRecalls, fromPosition))
    writeCurrentDB()
    
    local directRecallToSelect = nil
    for i = 1, #directRecalls do
      if directRecalls[i].IsSelected then
        directRecallToSelect = i
        break
      end
    end
    directRecalls[selectedDirectRecall].IsSelected = nil
    
    
    --update view
    populateDirectRecalls()
    selectDirectRecall(directRecallToSelect)
    
    log("Moved direct recall. " .. movingDirectRecallName .. " moved to position " .. toPosition, 3)
  end
end

for i = 1, #Controls.DirectRecall_MoveDown do
  Controls.DirectRecall_MoveDown[i].EventHandler = function ()
    log('DirectRecall_MoveDown button #' .. i .. ' pressed', 3)
    
    moveDirectRecall(i, i + 1)
  end
end

--Reordering by order text box
relistDirectRecallOrder = function ()
  log('relistDirectRecallOrder function called')
  
  for i = 1, #Controls.DirectRecall_OrderText do
    Controls.DirectRecall_OrderText[i].String = i
  end
end

for i = 1, #Controls.DirectRecall_OrderText do
  Controls.DirectRecall_OrderText[i].EventHandler = function (cc)
    log('DirectRecall_OrderText #' .. i .. ' changed to ' .. cc.String)
    
    moveDirectRecall(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end


--COPY/CUT/INSERT/DELETE DIRECT RECALLS
copiedDirectRecall = nil
copiedDirectRecallName = ""
Controls.DirectRecall_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyDirectRecall = function ()
  log('copyDirectRecall function called')
  
  local selectedDirectRecallNumber = getSelectedDirectRecallNumber()
  local selectedDirectRecall = directRecalls[selectedDirectRecallNumber]
  
  copiedDirectRecall = copy(selectedDirectRecall)
  copiedDirectRecallName = Controls.DirectRecall_Name[selectedDirectRecallNumber].String
  
  Controls.DirectRecall_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteDirectRecall = function ()
  log('deleteDirectRecall function called')
  
  --remove from database
  local selectedDirectRecallNumber = getSelectedDirectRecallNumber()
  table.remove(directRecalls, selectedDirectRecallNumber)  
  
  --update view
  populateDirectRecalls()
  
  local numDirectRecalls = getNumberOfDirectRecalls()
  local directRecallToSelect = math.min(selectedDirectRecallNumber, numDirectRecalls)--what if you deleted last cue in the stack? then pick the last cue
  selectDirectRecall(directRecallToSelect)
  
  writeCurrentDB()
end

addDirectRecall = function (directRecallData, destinationOrder)
  log('addDirectRecall function called. Adding direct recall to position ' .. destinationOrder)
  
  if #directRecalls + 1 <= #Controls.DirectRecall_Name then
    table.insert(directRecalls, destinationOrder, directRecallData)  
    selectDirectRecall(destinationOrder)
    populateDirectRecalls()
    writeCurrentDB()
  else
    log("No direct recall was created. There isn't enough room in the Direct Recall controls: Controls.DirectRecall_Name", 2)
  end
end

Controls.DirectRecall_Copy.EventHandler = function ()
  log('DirectRecall_Copy button pressed', 3)
  copyDirectRecall()
end

Controls.DirectRecall_Delete.EventHandler = function ()
  log('DirectRecall_Delete button pressed', 3)
  deleteDirectRecall()
end

Controls.DirectRecall_Cut.EventHandler = function ()
  log('DirectRecall_Cut button pressed', 3)
  copyDirectRecall()
  deleteDirectRecall()
end

Controls.DirectRecall_Insert.EventHandler = function ()
  log('DirectRecall_Insert button pressed', 3)
  
  local directRecallData = copy(copiedDirectRecall)
  local destinationOrder = getSelectedDirectRecallNumber() or 1
  
  addDirectRecall(directRecallData, destinationOrder)
end

Controls.DirectRecall_New.EventHandler = function ()
  log('DirectRecall_New button pressed', 3)
  
  local newDirectRecallData = {name = "New Direct Recall", cue = "", }
  local destinationOrder = 1
  if getNumberOfDirectRecalls() > 0 then
    destinationOrder = ( getSelectedDirectRecallNumber() or 0 ) + 1
  end
  
  addDirectRecall(newDirectRecallData, destinationOrder)
end


--------------------------
-- TIME OF DAY TRIGGERS --
--------------------------
getNumberOfTodTriggers = function ()
  log('getNumberOfTodTriggers function called')
  
  return #todTriggers
end

populateTodTriggers = function ()
  log('populateTodTriggers function called')
  
  --show the info for existing data
  for i = 1, #todTriggers do
    Controls.TimeOfDay_MoveDown[i].IsInvisible = false
    Controls.TimeOfDay_OrderText[i].IsInvisible = false
    
    Controls.TimeOfDay_Time[i].String = todTriggers[i].time
    Controls.TimeOfDay_Time[i].IsInvisible = false
    
    Controls.TimeOfDay_Name[i].String = todTriggers[i].name
    Controls.TimeOfDay_Name[i].IsInvisible = false
    
    Controls.TimeOfDay_Cue[i].String = todTriggers[i].cue
    Controls.TimeOfDay_Cue[i].IsInvisible = false
    
    Controls.TimeOfDay_Select[i].IsInvisible = false
  end
  
  --hide the rest
  for i = #todTriggers + 1, #Controls.TimeOfDay_MoveDown do
    Controls.TimeOfDay_MoveDown[i].IsInvisible = true
  end
  for i = #todTriggers + 1, #Controls.TimeOfDay_OrderText do
    Controls.TimeOfDay_OrderText[i].IsInvisible = true
  end
  for i = #todTriggers + 1, #Controls.TimeOfDay_Time do
    Controls.TimeOfDay_Time[i].String = ""
    Controls.TimeOfDay_Time[i].IsInvisible = true
  end
  for i = #todTriggers + 1, #Controls.TimeOfDay_Name do
    Controls.TimeOfDay_Name[i].String = ""
    Controls.TimeOfDay_Name[i].IsInvisible = true
  end
  for i = #todTriggers + 1, #Controls.TimeOfDay_Cue do
    Controls.TimeOfDay_Cue[i].String = ""
    Controls.TimeOfDay_Cue[i].IsInvisible = true
  end
  for i = #todTriggers + 1, #Controls.TimeOfDay_Select do
    Controls.TimeOfDay_Select[i].IsInvisible = true
  end
end


--EDIT TIME OF DAY TRIGGERS
for i = 1, #Controls.TimeOfDay_Time do
  Controls.TimeOfDay_Time[i].EventHandler = function (cc)
    log('TimeOfDay_Time #' .. i .. ' changed to ' .. cc.String)
    
    todTriggers[i].time = cc.String
    writeCurrentDB()
  end
end

for i = 1, #Controls.TimeOfDay_Name do
  Controls.TimeOfDay_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('TimeOfDay_Name #' .. i .. ' changed to ' .. newName)
    
    todTriggers[i].name = newName
    writeCurrentDB()
  end
end

for i = 1, #Controls.TimeOfDay_Cue do
  Controls.TimeOfDay_Cue[i].EventHandler = function (cc)
    log('TimeOfDay_Cue button #' .. i .. ' changed to '.. cc.String)
    
    todTriggers[i].cue = cc.String
    writeCurrentDB()
  end
end


--SELECT TIME OF DAY TRIGGERS
getSelectedTodTriggerNumber = function ()
  log('getSelectedTodTriggerNumber function called')
  
  local todTriggerNumber = nil
  
  for i = 1, #Controls.TimeOfDay_Select do
    if Controls.TimeOfDay_Select[i].Boolean then
      todTriggerNumber = i
      break
    end
  end
  
  return todTriggerNumber
end

selectTodTrigger = function (todTriggerNumber)
  log('selectTodTrigger function called with time of day trigger #' .. todTriggerNumber)
  
  local numTodTriggers = getNumberOfTodTriggers()
  
  if todTriggerNumber > 0 and todTriggerNumber <= numTodTriggers then
    
    --radio buttons
    for i = 1, #Controls.TimeOfDay_Select do
      Controls.TimeOfDay_Select[i].Boolean = (i == todTriggerNumber)
    end
  
  else --if selected tod trigger # is outside of range of existing tod triggers
    
    --show nothing is selected
    for i = 1, #Controls.TimeOfDay_Select do
      Controls.TimeOfDay_Select[i].Boolean = false
    end
    
    log('Did not select Time Of Day Trigger #' .. todTriggerNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.TimeOfDay_Select do
  Controls.TimeOfDay_Select[i].EventHandler = function ()
    log('TimeOfDay_Select #' .. i .. ' button pressed', 3)
    
    selectTodTrigger(i)
  end
end


--MOVING TIME OF DAY TRIGGERS
moveTodTrigger = function (fromPosition, toPosition)
  log('moveTodTrigger function called. Moving time of day trigger from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingTodTriggerName = Controls.TimeOfDay_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfTodTriggers() then --only move it if there's a place to move to
    
    local selectedTodTrigger = nil
    for i = 1, #Controls.TimeOfDay_Select do
      if Controls.TimeOfDay_Select[i].Boolean then
        selectedTodTrigger = i
        break
      end
    end
    
    --update database
    todTriggers[selectedTodTrigger].IsSelected = true
    table.insert(todTriggers, toPosition, table.remove(todTriggers, fromPosition))
    writeCurrentDB()
    
    local todTriggerToSelect = nil
    for i = 1, #todTriggers do
      if todTriggers[i].IsSelected then
        todTriggerToSelect = i
        break
      end
    end
    todTriggers[selectedTodTrigger].IsSelected = nil
    
    
    --update view
    populateTodTriggers()
    selectTodTrigger(todTriggerToSelect)
    
    log("Moved time of day trigger. " .. movingTodTriggerName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move time of day trigger. No position " .. toPosition .. " exists to move " .. movingTodTriggerName .. " to.", 2)
  end
end

for i = 1, #Controls.TimeOfDay_MoveDown do
  Controls.TimeOfDay_MoveDown[i].EventHandler = function ()
    log('TimeOfDay_MoveDown button #' .. i .. ' pressed', 3)
    
    moveTodTrigger(i, i + 1)
  end
end

--Reordering by order text box
relistTodTriggerOrder = function ()
  log('relistTodTriggerOrder function called')
  
  for i = 1, #Controls.TimeOfDay_OrderText do
    Controls.TimeOfDay_OrderText[i].String = i
  end
end

for i = 1, #Controls.TimeOfDay_OrderText do
  Controls.TimeOfDay_OrderText[i].EventHandler = function (cc)
    log('TimeOfDay_OrderText button #' .. i .. ' pressed', 3)
    
    moveTodTrigger(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end

--Reordering in time order
Controls.TimeOfDay_SortTime.EventHandler = function ()
  log('TimeOfDay_SortTime button presed')
  
  table.sort(todTriggers, sortByTime)
  
  populateTodTriggers()
  writeCurrentDB()
end


--COPY/CUT/INSERT/DELETE TIME OF DAY TRIGGERS
copiedTodTrigger = nil
copiedTodTriggerName = ""
Controls.TimeOfDay_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyTodTrigger = function ()
  log('copyTodTrigger function called')
  
  local selectedTodTriggerNumber = getSelectedTodTriggerNumber()
  local selectedTodTrigger = todTriggers[selectedTodTriggerNumber]
  
  copiedTodTrigger = copy(selectedTodTrigger)
  copiedTodTriggerName = Controls.TimeOfDay_Name[selectedTodTriggerNumber].String
  
  Controls.TimeOfDay_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteTodTrigger = function ()
  log('deleteTodTrigger function called')
  
  --remove from database
  local selectedTodTriggerNumber = getSelectedTodTriggerNumber()
  table.remove(todTriggers, selectedTodTriggerNumber)  
  
  --update view
  populateTodTriggers()
  
  local numTodTriggers = getNumberOfTodTriggers()
  local todTriggerToSelect = math.min(selectedTodTriggerNumber, numTodTriggers)--what if you deleted last cue in the stack? then pick the last cue
  selectTodTrigger(todTriggerToSelect)
  
  writeCurrentDB()
end

addTodTrigger = function (todTriggerData, destinationOrder)
  log('addTodTrigger function called. Adding TOD trigger to position ' .. destinationOrder)
  
  
  if #todTriggers < #Controls.TimeOfDay_Name then
    table.insert(todTriggers, destinationOrder, todTriggerData)  
    selectTodTrigger(destinationOrder)
    populateTodTriggers()
    writeCurrentDB()
  else
    log("No time of day trigger was created. There isn't enough room in the Time Of Day Triggers controls: Controls.TimeOfDay_Name", 2)
  end
end

Controls.TimeOfDay_Copy.EventHandler = function ()
  log('TimeOfDay_Copy button pressed', 3)
  copyTodTrigger()
end

Controls.TimeOfDay_Delete.EventHandler = function ()
  log('TimeOfDay_Delete button pressed', 3)
  deleteTodTrigger()
end

Controls.TimeOfDay_Cut.EventHandler = function ()
  log('TimeOfDay_Cut button pressed', 3)
  copyTodTrigger()
  deleteTodTrigger()
end

Controls.TimeOfDay_Insert.EventHandler = function ()
  log('TimeOfDay_Insert button pressed', 3)
  
  local todTriggerData = copy(copiedTodTrigger)
  local destinationOrder = getSelectedTodTriggerNumber() or 1
  
  addTodTrigger(todTriggerData, destinationOrder)
end

Controls.TimeOfDay_New.EventHandler = function ()
  log('TimeOfDay_New button pressed', 3)
  
  local newTodTriggerData = {name = "New Trigger", cue = "", time = "00:00:00"}
  local destinationOrder = 1
  if getNumberOfTodTriggers() > 0 then
    destinationOrder = ( getSelectedTodTriggerNumber() or 0 ) + 1
  end
  
  addTodTrigger(newTodTriggerData, destinationOrder)
end


--TRIGGER BASED ON TIMES
--Enable
writeTodEnableLegend = function ()
  if Controls.TimeOfDay_Enable.Boolean then
    Controls.TimeOfDay_Enable.Legend = "Enabled"
  else
    Controls.TimeOfDay_Enable.Legend = "Disabled"
  end
end

Controls.TimeOfDay_Enable.EventHandler = function ()
  writeTodEnableLegend()
end

--Check every second 
timeTriggerTimer = Timer.New()
checkTimeTriggers = function ()
  --log('checkTimeTriggers function called') --No way are we spamming the log with this every second
  
  -- syntax for retrieving time information % followed by capital letters for hour, minute, and second
  local currentTime = os.date("%H:%M:%S")
  
  Controls.TimeOfDay_CurrentTime.String = currentTime
  
  --look for triggers at this time
  for k,v in pairs (todTriggers) do
    if todTriggers[k].time == currentTime then
      log("Time of Day cue " .. todTriggers[k].name .. " was triggered. Cue is " .. todTriggers[k].cue, 3)
      
      --check if TOD triggers are enabled
      if not Controls.TimeOfDay_Enable.Boolean then
        log("Time of Day cue " .. todTriggers[k].name .. " didn't do anything because TOD triggers are disabled.", 2)
      else
        local cueName = todTriggers[k].cue
        executeCue(cueName)
      end
    end
  end
end

-- create the timer and start it to check every second for a function
timeTriggerTimer.EventHandler = checkTimeTriggers
timeTriggerTimer:Start(1)


--------------------------
--   TIMECODE TRIGGERS  --
--------------------------
getNumberOfTimecodeTriggers = function ()
  log('getNumberOfTimecodeTriggers function called')
  
  return #timecodeTriggers
end

populateTimecodeTriggers = function ()
  log('populateTimecodeTriggers function called')
  
  --show the info for existing data
  for i = 1, #timecodeTriggers do
    Controls.Timecode_MoveDown[i].IsInvisible = false
    Controls.Timecode_OrderText[i].IsInvisible = false
    
    Controls.Timecode_Time[i].String = timecodeTriggers[i].time
    Controls.Timecode_Time[i].IsInvisible = false
    
    Controls.Timecode_Name[i].String = timecodeTriggers[i].name
    Controls.Timecode_Name[i].IsInvisible = false
    
    Controls.Timecode_Cue[i].String = timecodeTriggers[i].cue
    Controls.Timecode_Cue[i].IsInvisible = false
    
    Controls.Timecode_Select[i].IsInvisible = false
  end
  
  --hide the rest
  for i = #timecodeTriggers + 1, #Controls.Timecode_MoveDown do
    Controls.Timecode_MoveDown[i].IsInvisible = true
  end
  for i = #timecodeTriggers + 1, #Controls.Timecode_OrderText do
    Controls.Timecode_OrderText[i].IsInvisible = true
  end
  for i = #timecodeTriggers + 1, #Controls.Timecode_Time do
    Controls.Timecode_Time[i].String = ""
    Controls.Timecode_Time[i].IsInvisible = true
  end
  for i = #timecodeTriggers + 1, #Controls.Timecode_Name do
    Controls.Timecode_Name[i].String = ""
    Controls.Timecode_Name[i].IsInvisible = true
  end
  for i = #timecodeTriggers + 1, #Controls.Timecode_Cue do
    Controls.Timecode_Cue[i].String = ""
    Controls.Timecode_Cue[i].IsInvisible = true
  end
  for i = #timecodeTriggers + 1, #Controls.Timecode_Select do
    Controls.Timecode_Select[i].IsInvisible = true
  end
end

--EDIT TIME OF DAY TRIGGERS
for i = 1, #Controls.Timecode_Time do
  Controls.Timecode_Time[i].EventHandler = function (cc)
    log('Timecode_Time #' .. i .. ' changed to ' .. cc.String)
    
    timecodeTriggers[i].time = cc.String
    writeCurrentDB()
  end
end

for i = 1, #Controls.Timecode_Name do
  Controls.Timecode_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('Timecode_Name #' .. i .. ' changed to ' .. newName)
    
    timecodeTriggers[i].name = newName
    writeCurrentDB()
  end
end

for i = 1, #Controls.Timecode_Cue do
  Controls.Timecode_Cue[i].EventHandler = function (cc)
    log('Timecode_Cue button #' .. i .. ' changed to '.. cc.String)
    
    timecodeTriggers[i].cue = cc.String
    writeCurrentDB()
  end
end

--SELECT TIME OF DAY TRIGGERS
getSelectedTimecodeTriggerNumber = function ()
  log('getSelectedTimecodeTriggerNumber function called')
  
  local timecodeTriggerNumber = nil
  
  for i = 1, #Controls.Timecode_Select do
    if Controls.Timecode_Select[i].Boolean then
      timecodeTriggerNumber = i
      break
    end
  end
  
  return timecodeTriggerNumber
end

selectTimecodeTrigger = function (timecodeTriggerNumber)
  log('selectTimecodeTrigger function called with timecode trigger #' .. timecodeTriggerNumber)
  
  local numTimecodeTriggers = getNumberOfTimecodeTriggers()
  
  if timecodeTriggerNumber > 0 and timecodeTriggerNumber <= numTimecodeTriggers then
    
    --radio buttons
    for i = 1, #Controls.Timecode_Select do
      Controls.Timecode_Select[i].Boolean = (i == timecodeTriggerNumber)
    end
  
  else --if selected timecode trigger # is outside of range of existing timecode triggers
    
    --show nothing is selected
    for i = 1, #Controls.Timecode_Select do
      Controls.Timecode_Select[i].Boolean = false
    end
    
    log('Did not select Timecode Trigger #' .. timecodeTriggerNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.Timecode_Select do
  Controls.Timecode_Select[i].EventHandler = function ()
    log('Timecode_Select #' .. i .. ' button pressed', 3)
    
    selectTimecodeTrigger(i)
  end
end


--MOVING TIMECODE TRIGGERS
moveTimecodeTrigger = function (fromPosition, toPosition)
  log('moveTimecodeTrigger function called. Moving timecode trigger from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingTimecodeTriggerName = Controls.Timecode_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfTimecodeTriggers() then --only move it if there's a place to move to
    
    local selectedTimecodeTrigger = nil
    for i = 1, #Controls.Timecode_Select do
      if Controls.Timecode_Select[i].Boolean then
        selectedTimecodeTrigger = i
        break
      end
    end
    
    --update database
    timecodeTriggers[selectedTimecodeTrigger].IsSelected = true
    table.insert(timecodeTriggers, toPosition, table.remove(timecodeTriggers, fromPosition))
    writeCurrentDB()
    
    local timecodeTriggerToSelect = nil
    for i = 1, #timecodeTriggers do
      if timecodeTriggers[i].IsSelected then
        timecodeTriggerToSelect = i
        break
      end
    end
    timecodeTriggers[selectedTimecodeTrigger].IsSelected = nil
    
    
    --update view
    populateTimecodeTriggers()
    selectTimecodeTrigger(timecodeTriggerToSelect)
    
    log("Moved timecode trigger. " .. movingTimecodeTriggerName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move timecode trigger. No position " .. toPosition .. " exists to move " .. movingTimecodeTriggerName .. " to.", 2)
  end
end

for i = 1, #Controls.Timecode_MoveDown do
  Controls.Timecode_MoveDown[i].EventHandler = function ()
    log('Timecode_MoveDown button #' .. i .. ' pressed', 3)
    
    moveTimecodeTrigger(i, i + 1)
  end
end

--Reordering by order text box
relistTimecodeTriggerOrder = function ()
  log('relistTimecodeTriggerOrder function called')
  
  for i = 1, #Controls.Timecode_OrderText do
    Controls.Timecode_OrderText[i].String = i
  end
end

for i = 1, #Controls.Timecode_OrderText do
  Controls.Timecode_OrderText[i].EventHandler = function (cc)
    log('Timecode_OrderText button #' .. i .. ' pressed', 3)
    
    moveTimecodeTrigger(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end

--Reordering in time order
Controls.Timecode_SortTime.EventHandler = function ()
  log('Timecode_SortTime button presed')
  
  table.sort(timecodeTriggers, sortByTime)
  
  populateTimeocodeTriggers()
  writeCurrentDB()
end


--COPY/CUT/INSERT/DELETE TIMECODE TRIGGERS
copiedTimecodeTrigger = nil
copiedTimecodeTriggerName = ""
Controls.Timecode_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyTimecodeTrigger = function ()
  log('copyTimecodeTrigger function called')
  
  local selectedTimecodeTriggerNumber = getSelectedTimecodeTriggerNumber()
  local selectedTimecodeTrigger = timecodeTriggers[selectedTimecodeTriggerNumber]
  
  copiedTimecodeTrigger = copy(selectedTimecodeTrigger)
  copiedTimecodeTriggerName = Controls.Timecode_Name[selectedTimecodeTriggerNumber].String
  
  Controls.Timecode_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteTimecodeTrigger = function ()
  log('deleteTimecodeTrigger function called')
  
  --remove from database
  local selectedTimecodeTriggerNumber = getSelectedTimecodeTriggerNumber()
  table.remove(timecodeTriggers, selectedTimecodeTriggerNumber)  
  
  --update view
  populateTimecodeTriggers()
  
  local numTimecodeTriggers = getNumberOfTimecodeTriggers()
  local timecodeTriggerToSelect = math.min(selectedTimecodeTriggerNumber, numTimecodeTriggers)--what if you deleted last cue in the stack? then pick the last cue
  selectTimecodeTrigger(timecodeTriggerToSelect)
  
  writeCurrentDB()
end

addTimecodeTrigger = function (timecodeTriggerData, destinationOrder)
  log('addTimecodeTrigger function called. Adding Timecode trigger to position ' .. destinationOrder)
  
  if #timecodeTriggers + 1 <= #Controls.Timecode_Name then
    table.insert(timecodeTriggers, destinationOrder, timecodeTriggerData)  
    selectTimecodeTrigger(destinationOrder)
    populateTimecodeTriggers()
    writeCurrentDB()
  else
    log("No timecode trigger was created. There isn't enough room in the Timecode Triggers controls: Controls.Timecode_Name", 2)
  end
end

Controls.Timecode_Copy.EventHandler = function ()
  log('Timecode_Copy button pressed', 3)
  copyTimecodeTrigger()
end

Controls.Timecode_Delete.EventHandler = function ()
  log('Timecode_Delete button pressed', 3)
  deleteTimecodeTrigger()
end

Controls.Timecode_Cut.EventHandler = function ()
  log('Timecode_Cut button pressed', 3)
  copyTimecodeTrigger()
  deleteTimecodeTrigger()
end

Controls.Timecode_Insert.EventHandler = function ()
  log('Timecode_Insert button pressed', 3)
  
  local timecodeTriggerData = copy(copiedTimecodeTrigger)
  local destinationOrder = getSelectedTimecodeTriggerNumber() or 1
  
  addTimecodeTrigger(timecodeTriggerData, destinationOrder)
end

Controls.Timecode_New.EventHandler = function ()
  log('Timecode_New button pressed', 3)
  
  local newTimecodeTriggerData = {name = "New Trigger", cue = "", time = "00:00:00:00"}
  local destinationOrder = 1
  if getNumberOfTimecodeTriggers() > 0 then
    destinationOrder = ( getSelectedTimecodeTriggerNumber() or 0 ) + 1
  end
  
  addTimecodeTrigger(newTimecodeTriggerData, destinationOrder)
end


--TRIGGER BASED ON TIMES
--Enable
writeTimecodeEnableLegend = function ()
  log('writeTimecodeEnableLegend function called')
  
  watchTimecodeReader() --this function will enable/disable the event handler
  
  if Controls.Timecode_Enable.Boolean then
    Controls.Timecode_Enable.Legend = "Enabled"
  else
    Controls.Timecode_Enable.Legend = "Disabled"
  end
end

Controls.Timecode_Enable.EventHandler = function ()
  log('Timecode_Enable button pressed', 3)
  
  writeTimecodeEnableLegend()
end

--Watch component
getTimecodeFromReader = function ()
  --log('getTimecodeFromReader function called') --leave commneted out, unless you want to spam the logs
  
  local reader = components['SMPTE LTC Timecode Reader'].component
  local readerTime = ""
  
  if not reader.hours.Value then
    log("No timecode reader found, so no timecode retrieved.", 2)
  else
    --get time from reader
    local readerHours = math.floor(reader.hours.Value)
    if readerHours < 10 then readerHours = "0" .. readerHours end
    
    local readerMinutes = math.floor(reader.minutes.Value)
    if readerMinutes < 10 then readerMinutes = "0" .. readerMinutes end
    
    local readerSeconds = math.floor(reader.seconds.Value)
    if readerSeconds < 10 then readerSeconds = "0" .. readerSeconds end
    
    local readerFrames = math.floor(reader.frames.Value)
    if readerFrames < 10 then readerFrames = "0" .. readerFrames end
    
    local readerTime = readerHours .. ":" .. readerMinutes .. ":" .. readerSeconds .. ":" .. readerFrames
  end
  
  return readerTime
end

watchTimecodeReader = function ()
  log('watchTimecodeReader function called')
  
  local reader = components['SMPTE LTC Timecode Reader'].component
  
  if Controls.Timecode_Enable.Boolean then
  
    --update now
    local readerTime = getTimecodeFromReader()
    Controls.Timecode_CurrentTime.String = readerTime

    --update every time it changes
    reader['frames'].EventHandler = function ()
      local readerTime = getTimecodeFromReader()
      
      Controls.Timecode_CurrentTime.String = readerTime
      
      --look for triggers at this time
      for k,v in pairs (timecodeTriggers) do
        if timecodeTriggers[k].time == readerTime then
          log("Timecode cue " .. timecodeTriggers[k].name .. " was triggered. Cue is " .. timecodeTriggers[k].cue, 3)
          
          --check if Timecode triggers are enabled
          if not Controls.Timecode_Enable.Boolean then
            log("Timecode cue " .. timecodeTriggers[k].name .. " didn't do anything because Timecode triggers are disabled.", 2)
          else
            local cueName = timecodeTriggers[k].cue
            executeCue(cueName)
          end
        end
      end
    end
  
  else --disabled, so turn off event handler
    reader['frames'].EventHandler = function () end
  end
  
end


--------------------------
--   NETWORK TRIGGERS   --
--------------------------

getNumberOfNetworkTriggers = function ()
  log('getNumberOfNetworkTriggers function called')
  
  return #networkTriggers
end

populateNetworkTriggers = function ()
  log('populateNetworkTriggers function called')
  
  --show the info for existing data
  for i = 1, #networkTriggers do
    Controls.NetworkTriggers_MoveDown[i].IsInvisible = false
    Controls.NetworkTriggers_OrderText[i].IsInvisible = false
    
    Controls.NetworkTriggers_String[i].String = networkTriggers[i].string
    Controls.NetworkTriggers_String[i].IsInvisible = false
    
    Controls.NetworkTriggers_Name[i].String = networkTriggers[i].name
    Controls.NetworkTriggers_Name[i].IsInvisible = false
    
    Controls.NetworkTriggers_Cue[i].String = networkTriggers[i].cue
    Controls.NetworkTriggers_Cue[i].IsInvisible = false
    
    Controls.NetworkTriggers_Select[i].IsInvisible = false
  end
  
  --hide the rest
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_MoveDown do
    Controls.NetworkTriggers_MoveDown[i].IsInvisible = true
  end
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_OrderText do
    Controls.NetworkTriggers_OrderText[i].IsInvisible = true
  end
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_String do
    Controls.NetworkTriggers_String[i].String = ""
    Controls.NetworkTriggers_String[i].IsInvisible = true
  end
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_Name do
    Controls.NetworkTriggers_Name[i].String = ""
    Controls.NetworkTriggers_Name[i].IsInvisible = true
  end
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_Cue do
    Controls.NetworkTriggers_Cue[i].String = ""
    Controls.NetworkTriggers_Cue[i].IsInvisible = true
  end
  for i = #networkTriggers + 1, #Controls.NetworkTriggers_Select do
    Controls.NetworkTriggers_Select[i].IsInvisible = true
  end
end


--EDIT NETWORK TRIGGERS
for i = 1, #Controls.NetworkTriggers_String do
  Controls.NetworkTriggers_String[i].EventHandler = function (cc)
    log('NetworkTriggers_String #' .. i .. ' changed to ' .. cc.String)
    
    networkTriggers[i].string = cc.String
    writeCurrentDB()
  end
end

for i = 1, #Controls.NetworkTriggers_Name do
  Controls.NetworkTriggers_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('NetworkTriggers_Name #' .. i .. ' changed to ' .. newName)
    
    networkTriggers[i].name = newName
    writeCurrentDB()
  end
end

for i = 1, #Controls.NetworkTriggers_Cue do
  Controls.NetworkTriggers_Cue[i].EventHandler = function (cc)
    log('NetworkTriggers_Cue button #' .. i .. ' changed to '.. cc.String)
    
    networkTriggers[i].cue = cc.String
    writeCurrentDB()
  end
end


--SELECT NETWORK TRIGGERS
getSelectedNetworkTriggerNumber = function ()
  log('getSelectedNetworkTriggerNumber function called')
  
  local triggerNumber = nil
  
  for i = 1, #Controls.NetworkTriggers_Select do
    if Controls.NetworkTriggers_Select[i].Boolean then
      triggerNumber = i
      break
    end
  end
  
  return triggerNumber
end


selectNetworkTrigger = function (triggerNumber)
  log('selectNetworkTrigger function called with trigger #' .. triggerNumber)
  
  local numTriggers = getNumberOfNetworkTriggers()
  
  if triggerNumber > 0 and triggerNumber <= numTriggers then
    
    --radio buttons
    for i = 1, #Controls.NetworkTriggers_Select do
      Controls.NetworkTriggers_Select[i].Boolean = (i == triggerNumber)
    end
  
  else --if selected trigger # is outside of range of existing triggers
    
    --show nothing is selected
    for i = 1, #Controls.NetworkTriggers_Select do
      Controls.NetworkTriggers_Select[i].Boolean = false
    end
    
    log('Did not select Network Trigger #' .. triggerNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.NetworkTriggers_Select do
  Controls.NetworkTriggers_Select[i].EventHandler = function ()
    log('NetworkTriggers_Select #' .. i .. ' button pressed', 3)
    
    selectNetworkTrigger(i)
  end
end


--MOVING NETWORK TRIGGERS
moveNetworkTrigger = function (fromPosition, toPosition)
  log('moveNetworkTrigger function called. Moving network trigger from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingTriggerName = Controls.NetworkTriggers_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfNetworkTriggers() then --only move it if there's a place to move to
    
    local selectedTrigger = nil
    for i = 1, #Controls.NetworkTriggers_Select do
      if Controls.NetworkTriggers_Select[i].Boolean then
        selectedTrigger = i
        break
      end
    end
    
    --update database
    networkTriggers[selectedTrigger].IsSelected = true
    table.insert(networkTriggers, toPosition, table.remove(networkTriggers, fromPosition))
    writeCurrentDB()
    
    local triggerToSelect = nil
    for i = 1, #networkTriggers do
      if networkTriggers[i].IsSelected then
        triggerToSelect = i
        break
      end
    end
    networkTriggers[selectedTrigger].IsSelected = nil
    
    
    --update view
    populateNetworkTriggers()
    selectNetworkTrigger(triggerToSelect)
    
    log("Moved network trigger. " .. movingTriggerName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move network trigger. No position " .. toPosition .. " exists to move " .. movingTriggerName .. " to.", 2)
  end
end

for i = 1, #Controls.NetworkTriggers_MoveDown do
  Controls.NetworkTriggers_MoveDown[i].EventHandler = function ()
    log('NetworkTriggers_MoveDown button #' .. i .. ' pressed', 3)
    
    moveNetworkTrigger(i, i + 1)
  end
end

--Reordering by order text box
relistNetworkTriggerOrder = function ()
  log('relistNetworkTriggerOrder function called')
  
  for i = 1, #Controls.NetworkTriggers_OrderText do
    Controls.NetworkTriggers_OrderText[i].String = i
  end
end

for i = 1, #Controls.NetworkTriggers_OrderText do
  Controls.NetworkTriggers_OrderText[i].EventHandler = function (cc)
    log('NetworkTriggers_OrderText button #' .. i .. ' pressed', 3)
    
    moveNetworkTrigger(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end

--Reordering in alpha order
Controls.NetworkTriggers_SortAlpha.EventHandler = function ()
  log('NetworkTriggers_SortAlpha button presed')
  
  table.sort(networkTriggers, sortByAlpha)
  
  populateNetworkTriggers()
  writeCurrentDB()
end


--COPY/CUT/INSERT/DELETE NETWORK TRIGGERS
copiedNetworkTrigger = nil
copiedNetworkTriggerName = ""
Controls.NetworkTriggers_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyNetworkTrigger = function ()
  log('copyNetworkTrigger function called')
  
  local selectedtriggerNumber = getSelectedNetworkTriggerNumber()
  local selectedtrigger = networkTriggers[selectedtriggerNumber]
  
  copiedNetworkTrigger = copy(selectedtrigger)
  copiedNetworkTriggerName = Controls.NetworkTriggers_Name[selectedtriggerNumber].String
  
  Controls.NetworkTriggers_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end


deleteNetworkTrigger = function ()
  log('deleteNetworkTrigger function called')
  
  --remove from database
  local selectedTriggerNumber = getSelectedNetworkTriggerNumber()
  table.remove(networkTriggers, selectedtriggerNumber)  
  
  --update view
  populateNetworkTriggers()
  
  local numTriggers = getNumberOfNetworkTriggers()
  local triggerToSelect = math.min(selectedTriggerNumber, numTriggers)--what if you deleted last cue in the stack? then pick the last cue
  selectNetworkTrigger(triggerToSelect)
  
  writeCurrentDB()
end

addNetworkTrigger = function (triggerData, destinationOrder)
  log('addNetworkTrigger function called. Adding trigger to position ' .. destinationOrder)
  
  if #networkTriggers + 1 <= #Controls.NetworkTriggers_Name then
    table.insert(networkTriggers, destinationOrder, triggerData)  
    selectNetworkTrigger(destinationOrder)
    populateNetworkTriggers()
    writeCurrentDB()
  else
    log("No network trigger was created. There isn't enough room in the Network Triggers controls: Controls.NetworkTriggers_Name", 2)
  end
end

Controls.NetworkTriggers_Copy.EventHandler = function ()
  log('NetworkTriggers_Copy button pressed', 3)
  copyNetworkTrigger()
end

Controls.NetworkTriggers_Delete.EventHandler = function ()
  log('NetworkTriggers_Delete button pressed', 3)
  deleteNetworkTrigger()
end

Controls.NetworkTriggers_Cut.EventHandler = function ()
  log('NetworkTriggers_Cut button pressed', 3)
  copyNetworkTrigger()
  deleteNetworkTrigger()
end

Controls.NetworkTriggers_Insert.EventHandler = function ()
  log('NetworkTriggers_Insert button pressed', 3)
  
  local triggerData = copy(copiedNetworkTrigger)
  local destinationOrder = getSelectedNetworkTriggerNumber() or 1
  
  addNetworkTrigger(triggerData, destinationOrder)
end

Controls.NetworkTriggers_New.EventHandler = function ()
  log('NetworkTriggers_New button pressed', 3)
  
  local newTriggerData = {name = "New Trigger", cue = "", string = ""}
  local destinationOrder = 1
  if getNumberOfNetworkTriggers() > 0 then
    destinationOrder = ( getSelectedNetworkTriggerNumber() or 0 ) + 1
  end
  
  addNetworkTrigger(newTriggerData, destinationOrder)
end


--RECEIVE INCOMING NETWORK TRIGGERS FROM OTHER SCRIPTS IN THIS DESIGN
--Enable
writeNetworkTriggersEnableLegend = function ()
  log('writeNetworkEnableLegend function called')
  
  if Controls.NetworkTriggers_Enable.Boolean then
    Controls.NetworkTriggers_Enable.Legend = "Enabled"
  else
    Controls.NetworkTriggers_Enable.Legend = "Disabled"
  end
end

Controls.NetworkTriggers_Enable.EventHandler = function ()
  log('NetworkTriggers_Enable button pressed', 3)
  
  writeNetworkTriggersEnableLegend()
end

processIncomingNetworkTrigger = function (name, data)
  log('processIncomingNetworkTrigger function called')
  
  --parse data for multiple strings in one command TODO
  local str = data
  
  --log/display received message
  log('Network Trigger String received: "' .. str .. '"', 3)
  Controls.NetworkTriggers_LastReceived.String = str .. " at " .. os.date("%H:%M:%S %x")
  
  --look up which cue to execute
  for k,v in pairs (networkTriggers) do --no break, in case multiple cues from same string
    if networkTriggers[k].string == str then
      log("Network cue " .. networkTriggers[k].name .. " was triggered. Cue is " .. networkTriggers[k].cue, 3)
      
      --check if Network triggers are enabled
      if not Controls.NetworkTriggers_Enable.Boolean then
        log("Timecode cue " .. timecodeTriggers[k].name .. " didn't do anything because Network triggers are disabled.", 2)
      else
        local cueName = networkTriggers[k].cue
        executeCue(cueName)
      end
    end
  end
end

networkTriggerSubscription = Notifications.Subscribe ("EasyShow Network Trigger", processIncomingNetworkTrigger)


--------------------------
--   CONTROL WATCHER    --
--------------------------

signs = {"=", "~=", "<", ">", "<=", ">="}
for i = 1, #Controls.ControlWatcher_Sign do
  Controls.ControlWatcher_Sign[i].Choices = signs
end

controlTypes = {"Boolean", "String", "Value"}
for i = 1, #Controls.ControlWatcher_Type do
  Controls.ControlWatcher_Type[i].Choices = controlTypes
end

getNumberOfControlWatcherTriggers = function ()
  log('getNumberOfControlWatcherTriggers function called')
  
  return #controlWatcherTriggers
end


populateControlWatcherTriggers = function ()
  log('populateControlWatcherTriggers function called')
  
  --show the info for existing data
  for i = 1, #controlWatcherTriggers do
    Controls.ControlWatcher_MoveDown[i].IsInvisible = false
    Controls.ControlWatcher_OrderText[i].IsInvisible = false
    
    Controls.ControlWatcher_Component[i].String = controlWatcherTriggers[i].component
    Controls.ControlWatcher_Component[i].IsInvisible = false
    
    Controls.ControlWatcher_Control[i].String = controlWatcherTriggers[i].control
    Controls.ControlWatcher_Control[i].IsInvisible = false
    
    Controls.ControlWatcher_Sign[i].String = controlWatcherTriggers[i].sign
    Controls.ControlWatcher_Sign[i].IsInvisible = false
    
    Controls.ControlWatcher_Value[i].String = controlWatcherTriggers[i].value
    Controls.ControlWatcher_Value[i].IsInvisible = false
    
    Controls.ControlWatcher_Name[i].String = controlWatcherTriggers[i].name
    Controls.ControlWatcher_Name[i].IsInvisible = false
    
    Controls.ControlWatcher_Type[i].String = controlWatcherTriggers[i].controlType
    Controls.ControlWatcher_Type[i].IsInvisible = false
    
    Controls.ControlWatcher_Cue[i].String = controlWatcherTriggers[i].cue
    Controls.ControlWatcher_Cue[i].IsInvisible = false
    
    Controls.ControlWatcher_Select[i].IsInvisible = false
    
    setControlWatcherControlDropdownChoices(i)
  end
  
  --hide the rest
  for i = math.max(#controlWatcherTriggers, 1), #Controls.ControlWatcher_MoveDown do
    Controls.ControlWatcher_MoveDown[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_OrderText do
    Controls.ControlWatcher_OrderText[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Component do
    Controls.ControlWatcher_Component[i].String = ""
    Controls.ControlWatcher_Component[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Control do
    Controls.ControlWatcher_Control[i].String = ""
    Controls.ControlWatcher_Control[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Sign do
    Controls.ControlWatcher_Sign[i].String = ""
    Controls.ControlWatcher_Sign[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Value do
    Controls.ControlWatcher_Value[i].String = ""
    Controls.ControlWatcher_Value[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Type do
    Controls.ControlWatcher_Type[i].String = ""
    Controls.ControlWatcher_Type[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Name do
    Controls.ControlWatcher_Name[i].String = ""
    Controls.ControlWatcher_Name[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Cue do
    Controls.ControlWatcher_Cue[i].String = ""
    Controls.ControlWatcher_Cue[i].IsInvisible = true
  end
  for i = #controlWatcherTriggers + 1, #Controls.ControlWatcher_Select do
    Controls.ControlWatcher_Select[i].IsInvisible = true
  end
end

--EDIT CONTROL WATCHER TRIGGERS
checkIfShouldMakeControlWatcherEventHandlers = function (chNum)
  local compName = Controls.ControlWatcher_Component[chNum].String
  local cont = Controls.ControlWatcher_Control[chNum].String
  local sign = Controls.ControlWatcher_Sign[chNum].String
  local value = Controls.ControlWatcher_Value[chNum].String
  local controlType = Controls.ControlWatcher_Type[chNum].String
  local cue = Controls.ControlWatcher_Cue[chNum].String
  
  --if the row is completely populated with data
  if compName ~= "" and cont ~= "" and sign ~= "" and value ~= "" and controlType ~= "" and cue ~= "" then
    makeControlWatcherEventHandlers()
  end
end

setControlWatcherControlDropdownChoices = function (chNum)
  log('setControlWatcherControlDropdownChoices function called')
  
  local compName = Controls.ControlWatcher_Component[chNum].String
  local comp = nil
  local choices = {}
  
  --make sure you have data to work with
  if compName ~= "" then
    comp = Component.New(compName)
    if comp then
      
      --add choices to list
      table.insert(choices, "") --add empty option
      for k,v in pairs (comp) do
        table.insert(choices, k)
      end
    end
  end
  
  Controls.ControlWatcher_Control[chNum].Choices = choices
end

for i = 1, #Controls.ControlWatcher_Component do
  Controls.ControlWatcher_Component[i].EventHandler = function (cc)
    log('ControlWatcher_Component #' .. i .. ' changed to ' .. cc.String)
    
    --remove old event handler
    local compName = controlWatcherTriggers[i].component
    local comp = Component.New(compName)
    local cont = controlWatcherTriggers[i].control
    if comp then
      --comp[cont].EventHandler = function () end
    end
    
    --save to database
    controlWatcherTriggers[i].component = cc.String
    controlWatcherTriggers[i].control = ""
    writeCurrentDB()
    
    Controls.ControlWatcher_Control[i].String = ""
    setControlWatcherControlDropdownChoices(i)
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
    
    setControlWatcherControlDropdownChoices(i)
  end
end

for i = 1, #Controls.ControlWatcher_Control do
  Controls.ControlWatcher_Control[i].EventHandler = function (cc)
    log('ControlWatcher_Control #' .. i .. ' changed to ' .. cc.String)
    
    --remove old event handler
    local compName = controlWatcherTriggers[i].component
    local comp = Component.New(compName)
    local cont = controlWatcherTriggers[i].control
    --comp[cont].EventHandler = function () end
    
    --save to database
    controlWatcherTriggers[i].control = cc.String
    writeCurrentDB()
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
  end
end

for i = 1, #Controls.ControlWatcher_Sign do
  Controls.ControlWatcher_Sign[i].EventHandler = function (cc)
    log('ControlWatcher_Sign #' .. i .. ' changed to ' .. cc.String)
    
    controlWatcherTriggers[i].sign = cc.String
    writeCurrentDB()
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
  end
end

for i = 1, #Controls.ControlWatcher_Value do
  Controls.ControlWatcher_Value[i].EventHandler = function (cc)
    log('ControlWatcher_Value #' .. i .. ' changed to ' .. cc.String)
    
    controlWatcherTriggers[i].value = cc.String
    writeCurrentDB()
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
  end
end

for i = 1, #Controls.ControlWatcher_Type do
  Controls.ControlWatcher_Type[i].EventHandler = function (cc)
    log('ControlWatcher_Type #' .. i .. ' changed to ' .. cc.String)
    
    controlWatcherTriggers[i].controlType = cc.String
    writeCurrentDB()
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
  end
end

for i = 1, #Controls.ControlWatcher_Name do
  Controls.ControlWatcher_Name[i].EventHandler = function (cc)
    log('ControlWatcher_Name #' .. i .. ' changed to ' .. cc.String)
    
    controlWatcherTriggers[i].name = cc.String
    writeCurrentDB()
  end
end

for i = 1, #Controls.ControlWatcher_Cue do
  Controls.ControlWatcher_Cue[i].EventHandler = function (cc)
    log('ControlWatcher_Cue #' .. i .. ' changed to ' .. cc.String)
    
    controlWatcherTriggers[i].cue = cc.String
    writeCurrentDB()
    
    checkIfShouldMakeControlWatcherEventHandlers(i)
  end
end

--SELECT CONTROL WATCHER TRIGGERS
getSelectedControlWatcherTriggerNumber = function ()
  log('getSelectedControlWatcherTriggerNumber function called')
  
  local triggerNumber = nil
  
  for i = 1, #Controls.ControlWatcher_Select do
    if Controls.ControlWatcher_Select[i].Boolean then
      triggerNumber = i
      break
    end
  end
  
  return triggerNumber
end

selectControlWatcherTrigger = function (triggerNumber)
  log('selectControlWatcherTrigger function called with trigger #' .. triggerNumber)
  
  local numTriggers = getNumberOfControlWatcherTriggers()
  
  if triggerNumber > 0 and triggerNumber <= numTriggers then
    
    --radio buttons
    for i = 1, #Controls.ControlWatcher_Select do
      Controls.ControlWatcher_Select[i].Boolean = (i == triggerNumber)
    end
  
  else --if selected trigger # is outside of range of existing triggers
    
    --show nothing is selected
    for i = 1, #Controls.ControlWatcher_Select do
      Controls.ControlWatcher_Select[i].Boolean = false
    end
    
    log('Did not select Control Watcher Trigger #' .. triggerNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.ControlWatcher_Select do
  Controls.ControlWatcher_Select[i].EventHandler = function ()
    log('ControlWatcher_Select #' .. i .. ' button pressed', 3)
    
    selectControlWatcherTrigger(i)
  end
end


--MOVING CONTROL WATCHER TRIGGERS
moveControlWatcherTrigger = function (fromPosition, toPosition)
  log('moveControlWatcherTrigger function called. Moving trigger from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingTriggerName = Controls.ControlWatcher_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfControlWatcherTriggers() then --only move it if there's a place to move to
    
    local selectedTrigger = nil
    for i = 1, #Controls.ControlWatcher_Select do
      if Controls.ControlWatcher_Select[i].Boolean then
        selectedTrigger = i
        break
      end
    end
    
    --update database
    controlWatcherTriggers[selectedTrigger].IsSelected = true
    table.insert(controlWatcherTriggers, toPosition, table.remove(controlWatcherTriggers, fromPosition))
    writeCurrentDB()
    
    local triggerToSelect = nil
    for i = 1, #controlWatcherTriggers do
      if controlWatcherTriggers[i].IsSelected then
        triggerToSelect = i
        break
      end
    end
    controlWatcherTriggers[selectedTrigger].IsSelected = nil
    
    
    --update view
    populateControlWatcherTriggers()
    selectControlWatcherTrigger(triggerToSelect)
    
    for i = math.min(fromPosition, toPosition), math.max(fromPosition, toPosition) do
      setControlWatcherControlDropdownChoices(i)
    end
    
    log("Moved control watcher trigger. " .. movingTriggerName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move control watcher trigger. No position " .. toPosition .. " exists to move " .. movingTriggerName .. " to.", 2)
  end
end

for i = 1, #Controls.ControlWatcher_MoveDown do
  Controls.ControlWatcher_MoveDown[i].EventHandler = function ()
    log('ControlWatcher_MoveDown button #' .. i .. ' pressed', 3)
    
    moveControlWatcherTrigger(i, i + 1)
  end
end

--Reordering by order text box
relistControlWatcherTriggerOrder = function ()
  log('relistControlWatcherTriggerOrder function called')
  
  for i = 1, #Controls.ControlWatcher_OrderText do
    Controls.ControlWatcher_OrderText[i].String = i
  end
end

for i = 1, #Controls.ControlWatcher_OrderText do
  Controls.ControlWatcher_OrderText[i].EventHandler = function (cc)
    log('ControlWatcher_OrderText button #' .. i .. ' pressed', 3)
    
    moveControlWatcherTrigger(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end

--Reordering in alpha order
Controls.ControlWatcher_SortAlpha.EventHandler = function ()
  log('ControlWatcher_SortAlpha button presed')
  
  table.sort(controlWatcherTriggers, sortByAlpha)
  
  populateControlWatcherTriggers()
  writeCurrentDB()
end

--Reordering in component order
Controls.ControlWatcher_SortComponent.EventHandler = function ()
  log('ControlWatcher_SortComponent button presed')
  
  table.sort(controlWatcherTriggers, sortByControl)
  table.sort(controlWatcherTriggers, sortByComponent)
  
  populateControlWatcherTriggers()
  writeCurrentDB()
end


--COPY/CUT/INSERT/DELETE CONTROL WATCHER TRIGGERS
copiedControlWatcherTrigger = nil
copiedControlWatcherTriggerName = ""
Controls.ControlWatcher_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyControlWatcherTrigger = function ()
  log('copyControlWatcherTrigger function called')
  
  local selectedtriggerNumber = getSelectedControlWatcherTriggerNumber()
  local selectedtrigger = controlWatcherTriggers[selectedtriggerNumber]
  
  copiedControlWatcherTrigger = copy(selectedtrigger)
  copiedControlWatcherTriggerName = Controls.ControlWatcher_Name[selectedtriggerNumber].String
  
  Controls.ControlWatcher_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteControlWatcherTrigger = function ()
  log('deleteControlWatcherTrigger function called')
  
  local selectedTriggerNumber = getSelectedControlWatcherTriggerNumber()
  
  --remove old event handler
  local compName = controlWatcherTriggers[selectedTriggerNumber].component
  local comp = Component.New(compName)
  local cont = controlWatcherTriggers[selectedTriggerNumber].control
  comp[cont].EventHandler = function () end
  
  --remove from database
  table.remove(controlWatcherTriggers, selectedtriggerNumber)  
  
  --update view
  populateControlWatcherTriggers()
  
  local numTriggers = getNumberOfControlWatcherTriggers()
  local triggerToSelect = math.min(selectedTriggerNumber, numTriggers)--what if you deleted last cue in the stack? then pick the last cue
  selectControlWatcherTrigger(triggerToSelect)
  
  writeCurrentDB()
end

addControlWatcherTrigger = function (triggerData, destinationOrder)
  log('addControlWatcherTrigger function called. Adding trigger to position ' .. destinationOrder)
  
  if #controlWatcherTriggers + 1 <= #Controls.ControlWatcher_Name then
    table.insert(controlWatcherTriggers, destinationOrder, triggerData)  
    selectControlWatcherTrigger(destinationOrder)
    populateControlWatcherTriggers()
    writeCurrentDB()
  else
    log("No control watcher trigger was created. There isn't enough room in the controls: Controls.ControlWatcher_Name", 2)
  end
end

Controls.ControlWatcher_Copy.EventHandler = function ()
  log('ControlWatcher_Copy button pressed', 3)
  copyControlWatcherTrigger()
end

Controls.ControlWatcher_Delete.EventHandler = function ()
  log('ControlWatcher_Delete button pressed', 3)
  deleteControlWatcherTrigger()
end

Controls.ControlWatcher_Cut.EventHandler = function ()
  log('ControlWatcher_Cut button pressed', 3)
  copyControlWatcherTrigger()
  deleteControlWatcherTrigger()
end

Controls.ControlWatcher_Insert.EventHandler = function ()
  log('ControlWatcher_Insert button pressed', 3)
  
  local triggerData = copy(copiedControlWatcherTrigger)
  local destinationOrder = getSelectedControlWatcherTriggerNumber() or 1
  
  addControlWatcherTrigger(triggerData, destinationOrder)
end

Controls.ControlWatcher_New.EventHandler = function ()
  log('ControlWatcher_New button pressed', 3)
  
  local newTriggerData = {name = "New Trigger", cue = "", component = "", control = "", sign = "=", value = "", controlType = ""}
  local destinationOrder = 1
  if getNumberOfControlWatcherTriggers() > 0 then
    destinationOrder = ( getSelectedControlWatcherTriggerNumber() or 0 ) + 1
  end
  
  addControlWatcherTrigger(newTriggerData, destinationOrder)
end

--WATCH COMPONENTS IN THIS DESIGN
--Enable
writeControlWatcherTriggersEnableLegend = function ()
  log('writeControlWatcherTriggersEnableLegend function called')
  
  if Controls.ControlWatcher_Enable.Boolean then
    Controls.ControlWatcher_Enable.Legend = "Enabled"
  else
    Controls.ControlWatcher_Enable.Legend = "Disabled"
  end
end

Controls.ControlWatcher_Enable.EventHandler = function ()
  log('ControlWatcher_Enable button pressed', 3)
  
  writeControlWatcherTriggersEnableLegend()
end

makeControlWatcherEventHandlers = function ()
  log('makeControlWatcherEventHandlers function called')
  
  --clear old EHs
  for i = 1, #controlWatcherTriggers do
    local comp = controlWatcherTriggers[i].component
    local cont = controlWatcherTriggers[i].control
    
    if comp and cont and comp[cont] then
      comp[cont].EventHandler = function () end
    end
  end
  
  --make new EHs
  for i = 1, #Controls.ControlWatcher_Component do
    local compName = Controls.ControlWatcher_Component[i].String
    local comp = Component.New(compName)
    local cont = Controls.ControlWatcher_Control[i].String
    local sign = Controls.ControlWatcher_Sign[i].String
    local cue = Controls.ControlWatcher_Cue[i].String
    local value = nil
    local controlType = Controls.ControlWatcher_Type[i].String
    
    --get the the proper type of the thing to compare to
    if controlType == "Boolean" then
      value = Controls.ControlWatcher_Value[i].String
    elseif controlType == "String" then
      value = Controls.ControlWatcher_Value[i].String
    elseif controlType == "Value" then
      value = tonumber(Controls.ControlWatcher_Value[i].String)
    end
    
    --if the row is populated with data
    if compName ~= "" and cont ~= "" and sign ~= "" and value ~= "" and cue ~= "" then
      log('Creating Control Watcher trigger for # ' .. i)
      
      comp[cont].EventHandler = function (cc)
        log('Control Watcher triggered for ' .. compName .. ' ' .. cont)
        
        --look through table matching lines
        for j = 1, #controlWatcherTriggers do
          
          --first check for correct control
          if compName == controlWatcherTriggers[j].component and cont == controlWatcherTriggers[j].control then
            
            --get control's value/string
            local controlValue = nil
            if controlType == "Boolean" then
              controlValue = cc.String
            elseif controlType == "String" then
              controlValue = cc.String
            elseif controlType == "Value" then
              controlValue = cc.Value
            end
            
            --next check for matching value
            --this seems inelegant. (in fact, this whole thing does.) if you find a better method, let me know!
            local matchFound = false
            
            if sign == "=" and controlValue == value then
              matchFound = true
            elseif sign == "~=" and controlValue ~= value then
              matchFound = true
            elseif sign == "<" and controlValue < value then
              matchFound = true
            elseif sign == ">" and controlValue > value then
              matchFound = true
            elseif sign == "<=" and cc.String <= value then
              matchFound = true
            elseif sign == ">=" and controlValue >= value then
              matchFound = true
            end
            
            if matchFound then
              log('Control Watcher found a matching value. Triggering a cue: ' .. cue, 3)
              executeCue(cue)
            else
              log('Control Watcher did not find a matching value. Cue not triggered.')
            end
          end
        end
      end
    end
  end
end



--------------------------
--      CUE LISTS       --
--------------------------

getNumberOfCueLists = function () -- counts cue lists
  log('getNumberOfCueLists function called')
  return getCountOfTable(cueLists)
end

populateCueListNames = function () --updates names of cues everywhere
  log('populateCueListNames function called')
  
  local numCueLists = getNumberOfCueLists()
  
  --write to Cue List names
  for i = 1, #Controls.CueLists_Name do
    Controls.CueLists_Name[i].String = ""
  end
  for k, v in pairs (cueLists) do
    local name = k
    local orderNum = v.displayOrder
    Controls.CueLists_Name[orderNum].String = name
  end
  --hide unused Cue List controls
  for i = 1, #Controls.CueLists_MoveDown do
    Controls.CueLists_MoveDown[i].IsInvisible = (i >= numCueLists) --intentionally >=. can't move bottom row down.
  end
  for i = 1, #Controls.CueLists_OrderText do
    Controls.CueLists_OrderText[i].IsInvisible = (i > numCueLists)
  end
  for i = 1, #Controls.CueLists_Name do
    Controls.CueLists_Name[i].IsInvisible = (i > numCueLists)
  end
  for i = 1, #Controls.CueLists_Select do
    Controls.CueLists_Select[i].IsInvisible = (i > numCueLists)
  end
  
  --write to dropdowns everywhere
  local cueListTable = {}
  for i = 1, numCueLists do
    table.insert(cueListTable, Controls.CueLists_Name[i].String)
  end
  
  Controls.CueListEditor_CueList.Choices = cueListTable
  Controls.UCI_ShowSelect.Choices = cueListTable
  
  --add empty option for Rehearsal Points page
  local cueListTableForRP = cueListTable
  table.insert(cueListTableForRP, 1, "")
  
  for i = 1, #Controls.RehearsalPoints_CueList do
    Controls.RehearsalPoints_CueList[i].Choices = cueListTable
  end
end

getCueListNameFromPosition = function (position) --returns name of cue list, given position in list. checks actual cues table instead of Controls
  log('getCueListNameFromPosition function called with position ' .. position)
  
  for k,v in pairs (cueLists) do
    if v.displayOrder == position then
      return k
    end
  end
end

--EDIT CUE LIST NAME
for i = 1, #Controls.CueLists_Name do
  Controls.CueLists_Name[i].EventHandler = function (cc) --rename cues in tables when user renames
    local newName = scrubString(cc.String)
    
    log('CueLists_Name #' .. i .. " text field changed to " .. newName)
    
    local oldName = getCueListNameFromPosition(i)
    
    if cueLists[newName] then
      log("Did not rename cue list. Cue list with name " .. newName .. " already exists.", 2)
      cc.String = oldName
    elseif newName == "" then
      log("Did not rename cue list. Cannot use blank name for a cue list.", 2)
      cc.String = oldName
    else --okay, you can rename the cue
      
      --update database
      cueLists[newName] = cueLists[oldName]
      cueLists[oldName] = nil
      writeCurrentDB()
      
      --update interface
      populateCueListNames()
      if Controls.UCI_ShowSelect.String == oldName then
        Controls.UCI_ShowSelect.String = newName
      end
      
      --select updated cue list
      local selectedCueListName = getSelectedCueListName()
      selectCueListByName(selectedCueListName)
    end
  end
end


--SELECTING CUE LISTS
selectCueListByPosition = function (selectedCueListPosition) --selects a cue, given a number in the list
  log('selectCueListByPosition function called with position ' .. selectedCueListPosition)
  
  local numCueLists = getNumberOfCueLists()
  
  if selectedCueListPosition > 0 and selectedCueListPosition <= numCueLists then
    
    --radio buttons
    for i = 1, #Controls.CueLists_Select do
      Controls.CueLists_Select[i].Boolean = (i == selectedCueListPosition)
    end
    
    --populate Cue List Editor
    local selectedCueListName = Controls.CueLists_Name[selectedCueListPosition].String
    displayCueListByName(selectedCueListName)
  else --cue list # is out of bounds of existing cues
    --show nothing is selected
    for i = 1, #Controls.CueLists_Select do
      Controls.CueLists_Select[i].Boolean = false
    end
    
    log ('Did not select Cue List #' .. selectedCueListPosition .. ". It does not exist.", 2)
  end
end

selectCueListByName = function (name) --selects a cue, given its name
  if not name then
    log('selectCueByListName function could not select a cue list because no name name was provided', 2)
  else
    log('selectCueByListName function called with name ' .. name)
    
    local cueListNum = nil
    
    for i = 1, #Controls.CueLists_Select do
      if Controls.CueLists_Name[i].String == name then
        cueListNum = i
        break
      end
    end
    
    selectCueListByPosition(cueListNum)
  end
end

getSelectedCueListNumber = function () --returns the order# of the selected cue list
  log('getSelectedCueListNumber function called')
  
  for i = 1, #Controls.CueLists_Select do
    if Controls.CueLists_Select[i].Boolean then
      return i
    end
  end
end

getSelectedCueListName = function () --returns the name of the selected cue list
  log('getSelectedCueListName function called')
  
  for i = 1, #Controls.CueLists_Select do
    if Controls.CueLists_Select[i].Boolean then
      return Controls.CueLists_Name[i].String
    end
  end
end

--Select buttons
for i = 1, #Controls.CueLists_Select do
  Controls.CueLists_Select[i].EventHandler = function (cc)
    log('CueLists_Select #' .. i .. " button pressed", 3)
    
    selectCueListByPosition(i)
  end
end


--MOVE CUE LISTS
moveCueList = function (fromPosition, toPosition)
  log('moveCueList function called. Moving Cue List from position ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingCueListName = Controls.CueLists_Name[fromPosition].String
  
  if toPosition > 0 and toPosition <= getNumberOfCueLists() then --only move it if there's a place to move to
    
    --get selected cue list name
    local selectedCueListName = getSelectedCueListName()
    
    --make table of order of cues
    local listOfCueLists = {}
    for k,v in pairs (cueLists) do
      listOfCueLists[v.displayOrder] = k
    end
    
    --shuffle order    
    table.insert(listOfCueLists, toPosition, table.remove(listOfCueLists, fromPosition))
    
    --write new order back to normal table
    for i = 1, #listOfCueLists do
      local cueListName = listOfCueLists[i]
      cueLists[cueListName].displayOrder = i
    end
    
    writeCurrentDB()
    
    --write to Controls
    populateCueListNames()
    
    --select same cue as before
    selectCueListByName(selectedCueListName)
    
    log("Moved cue list in Cue Lists. " .. movingCueListName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move cue list in Cue Lists. No position " .. toPosition .. " exists to move cue list" .. movingCueListName .. " to.", 2)
  end
end

--Reordering by move buttons
for i = 1, #Controls.CueLists_MoveDown do
  Controls.CueLists_MoveDown[i].EventHandler = function (cc)
    log('CueLists_MoveDown #' .. i .. " button pressed", 3)
    
    moveCueList(i, i + 1)
  end
end

--Reordering by order text box
relistCueListsOrder = function ()
  log('relistCueListsOrder function called')
  
  for i = 1, #Controls.CueLists_OrderText do
    Controls.CueLists_OrderText[i].String = i
  end
end

for i = 1, #Controls.CueLists_OrderText do
  Controls.CueLists_OrderText[i].EventHandler = function (cc)
    log('CueLists_OrderText #' .. i .. " text field changed to " .. cc.String)
    
    moveCueList(i, tonumber(cc.String))
    cc.String = i
  end
end

--Reordering Alphabetically
Controls.CueLists_SortAlpha.EventHandler = function ()
  log('CueLists_SortAlpha button pressed', 3)
  
  --get selected cue list name
  local selectedCueListName = getSelectedCueListName()
  
  --reorder the table
  local cueListTable = {}
  for k,v in pairs (cueLists) do
    table.insert(cueListTable, k)
  end
  table.sort(cueListTable)
  for i = 1, #cueListTable do
    local cueListName = cueListTable[i]
    cueLists[cueListName].displayOrder = i
  end
  
  writeCurrentDB()
  
  --reorder controls
  populateCueNames()
  
  --select same cue as before
  selectCueListByName(selectedCueListName)
  
  log("Sorted Cue Lists alphabetically.", 3)
end


--COPY/CUT/INSERT/DELETE CUE LISTS
copiedCueList = nil
copiedCueListName = ""
Controls.CueLists_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

updateCueListDisplayOrdersFromOrderedTable = function (cueListTable) --writes new displayOrders to the cues table, given an indexed table
  log('updateCueListDisplayOrdersFromOrderedTable function called')
  
  for i = 1, #cueListTable do
    local name = cueListTable[i]
    cueLists[name].displayOrder = i
  end
end

copyCueList = function (cueListName) --copies a cue list to the "clipboard"
  log('copyCueList function called with cue list ' .. cueListName)
  
  copiedCueList = copy(cueLists[cueListName])
  copiedCueListName = cueListName
  
  Controls.CueLists_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

getOrderedCueListTable = function () --returns an indexed table: index = cue list order #, value = cue list name
  log('getOrderedCueListTable function called')
  
  local cueListTable = {}
  
  for k,v in pairs (cueLists) do
    local position = cueLists[k].displayOrder
    local name = k
    cueListTable[position] = name
  end
  
  return cueListTable
end

deleteCueList = function (cueListName) --deletes a cue list from the list & shifts everything up.
  log('deleteCueList function called with cue list ' .. cueListName)
  
  --get ordered table
  local cueListTable = getOrderedCueListTable()
  
  --remove deleted cue list
  cueLists[cueListName] = nil --must remove this after pulling the ordered table so that everything stays sequential with no gaps
  
  for i = 1, #cueListTable do --also remove from ordered table
    if cueListTable[i] == cueListName then
      table.remove(cueListTable, i)
      break
    end
  end
  
  --write new displayOrders to cues list table
  updateCueListDisplayOrdersFromOrderedTable(cueListTable)
  
  writeCurrentDB()
  
  --write to Controls
  populateCueListNames()
  
  --select next cue
  local numCueLists = getNumberOfCueLists()
  local thisCueList = getSelectedCueListNumber()
  local cueListToSelect = math.min(numCueLists, thisCueList) --what if you deleted last cue list? choose the last cue list in the new list
  selectCueListByPosition(cueListToSelect)
end

addCueList = function (cueListData, cueListName, destinationOrder) --duplicates the cue list in the clipboard to the selected position. bumps cues down.
  log('addCueList function called with cue list ' .. cueListName .. ' and position ' .. destinationOrder)

  if getNumberOfCueLists() + 1 <= #Controls.CueLists_Name then
    
    local cueListTable = getOrderedCueListTable() --get ordered table of existing cue lists
    local cueListNameToPaste = cueListName --get what to name this cue list
    
    --change name of copied cue list if pasting it would cause duplicate name
    local spotToCheck = 1
    while #cueListTable >= spotToCheck do
      if cueListTable[spotToCheck] == cueListNameToPaste then
        spotToCheck = 0 --start over, because what if earlier name is now a duplicate?
        cueListNameToPaste = cueListNameToPaste .. "^"
      end
      spotToCheck = spotToCheck + 1
    end
    
    --add copied cue list to main table
    cueListData.displayOrder = destinationOrder
    cueLists[cueListNameToPaste] = copy(cueListData)
    
    --add copied cue list to local ordered table
    table.insert(cueListTable, destinationOrder, cueListNameToPaste)
    
    --write new displayOrders to the cue lists table from the ordered table
    updateCueListDisplayOrdersFromOrderedTable(cueListTable)
    
    writeCurrentDB()
    
    --write to Controls
    populateCueListNames()
    
    --select this cue list
    selectCueListByPosition(destinationOrder)
    
    log("Cue list " .. cueListNameToPaste .. " added in position " .. destinationOrder, 3)
    
  else
    log("Cue list was not added. There isn't enough room in the Cue Lists Controls: Controls.CueLists_Name", 2)
  end
end

Controls.CueLists_Copy.EventHandler = function ()
  log('CueLists_Copy button pressed', 3)
  
  local name = getSelectedCueListName()
  copyCueList(name)
end

Controls.CueLists_Delete.EventHandler = function ()
  log('CueLists_Delete button pressed', 3)
  
  local name = getSelectedCueListName()
  deleteCueList(name)
end

Controls.CueLibrary_Cut.EventHandler = function ()
  log('CueLists_Cut button pressed', 3)
  
  local name = getSelectedCueListName()
  
  copyCueList(name)
  deleteCueList(name)
end

Controls.CueLists_Insert.EventHandler = function ()
  log('CueLists_Insert button pressed', 3)
  
  if not copiedCueList then
    log("No cue list inserted. No cue has been copied or cut.", 2)
    
  else
    local destinationOrder = getSelectedCueListNumber() or 1
    
    addCueList(copiedCueList, copiedCueListName, destinationOrder)
  end
end

Controls.CueLists_New.EventHandler = function ()
  log('CueLists_New button pressed', 3)
  
  local newCueListData = {cues = {}}
  local cueListName = "New Cue List"
  local destinationOrder = ( getSelectedCueListNumber() or 0 ) + 1
  
  addCueList(newCueListData, cueListName, destinationOrder)
end


--------------------------
-- CUE LIST NAVIGATION  --
--------------------------
selectedUciCueEntry = 1
selectedUciShow = ""

changeCue = function(num) --Increments and displays selected cue
  log("changeCue function called")
  
  --update selected cue
  selectedUciCueEntry = selectedUciCueEntry + num
  loopbackselectedUciCueEntry()
  
  --update interface
  updateUCINextCueDisplay()
end

goToCue = function(cueList, num, name)

  Controls.UCI_ShowDisplay.String = cueList
  
  selectedUciShow = cueList
  
  if num < 0 then -- number takes precedence
    for i = 1, #cueLists[selectedUciShow].cues do
      if cueLists[selectedUciShow].cues[i].name == name then -- find the cue name
        num = i
        break
      end
    end
  end
  
  Controls.UCI_ShowSelect.String = Controls.UCI_ShowDisplay.String

  selectedUciCueEntry = tonumber(num)
  -- check for out of bounds
  loopbackselectedUciCueEntry()
  
  updateUCINextCueDisplay()
end

updateUCINextCueDisplay = function() --Displays selected cue name
  log("updateUCINextCueDisplay function called")
  
  if not cueLists[selectedUciShow] then
    log('Could not update Next Cue display in UCI. Selected Show ' .. selectedUciShow .. ' does not exist in Cue Lists.', 2)
    
  elseif not cueLists[selectedUciShow].cues[selectedUciCueEntry] then
    log('Could not update Next Cue display in UCI. Selected Cue ' .. selectedUciCueEntry .. ' does not exist in Cue List ' .. selectedUciShow .. '.', 2)
    
  else --actually update the display
    local cueName = cueLists[selectedUciShow].cues[selectedUciCueEntry].name
    local cueLine = cueLists[selectedUciShow].cues[selectedUciCueEntry].cueLine
    
    Controls.UCI_CueLine.String = cueLine or ""
    Controls.UCI_NextCue.String = cueName or ""
  end
end

uciGoLockTimer = Timer.New()
uciGoLockTimer.EventHandler = function()
  uciGoLockTimer:Stop()
  Controls.UCI_Go.IsDisabled = false
end

lockUCIGo = function(time)
  Controls.UCI_Go.IsDisabled = true
  uciGoLockTimer:Start(time)
end


loopbackselectedUciCueEntry = function() --Once you've reached either end of the cuelist, go back to the other end of the list
  log("loopbackselectedUciCueEntry function called")
  
  if selectedUciCueEntry > #cueLists[selectedUciShow]["cues"] then
    selectedUciCueEntry = 1
  elseif selectedUciCueEntry < 1 then
    selectedUciCueEntry = #cueLists[selectedUciShow]["cues"]
  end
end

Controls.UCI_Go.EventHandler = function() --Plays selectedUciCueEntry and auto advances if preferred
  log("UCI_Go button pushed", 3)
  
  local cueName = cueLists[selectedUciShow].cues[selectedUciCueEntry].name
  local cue = cueLists[selectedUciShow].cues[selectedUciCueEntry].cue
  
  --check for errors
  if not cueLists[selectedUciShow] then
    log('UCI Go button did not trigger a cue. There is no Cue List named ' .. selectedUciShow)
  
  elseif not cueLists[selectedUciShow] then
    log('UCI Go button did not trigger a cue. There is no Cue ' .. cue)
  
  else --actually trigger a cue
    lockUCIGo(prefValues["Double Tap Time"])
    
    Controls.UCI_LastPlayed.String = cueName
    
    rehearsalTime = Controls.UCI_RehearsalSeekTime.Value
    resetRehearsalTimer:Start(.1)  --Wait for everything to execute before resetting rehearsal slider
    
    executeCue(cue)
    
    if prefValues["Auto Advance On Go"] then
      changeCue(1)
    end
    
  end
end

Controls.UCI_Next.EventHandler = function() --Increments selectedUciCueEntry up one
  log("UCI_Next button pushed", 3)
  
  changeCue(1)
end


Controls.UCI_Previous.EventHandler = function() --Increments selectedUciCueEntry down one
  log("UCI_Previous button pushed", 3)
  
  changeCue(-1)
end

Controls.UCI_Stop.EventHandler = function() --Begins timer to stop files and wait timers
  log("UCI_Stop button pushed " .. Controls.UCI_Stop.String, 3)
  
  local time = prefValues["Press and Hold Stop Time"]
  
  if Controls.UCI_Stop.Boolean then
    Controls.UCI_StatusDisplayMeter.Color = ""
    animTimer:Start(1/prefValues["Stopping Animation Frame Rate"]) -- start animation for stopping bar
    holdToStop:Start(time)
  elseif Controls.UCI_Stop.Boolean == false then
    animTimer:Stop()
    holdToStop:Stop()
    if string.find(Controls.UCI_StatusDisplay.String, "Stopping in ") then
      Controls.UCI_StatusDisplayMeter.Position = 0
      updateStatusDisplay("")
    end
  end
end

Controls.UCI_ShowSelect.EventHandler = function(cc) --Changes between cueLists
  log("UCI_ShowSelect dropdown changed. Selected show changed to "..selectedUciShow, 3)
  
  Controls.UCI_ShowDisplay.String = Controls.UCI_ShowSelect.String
  
  selectedUciShow = cc.String
  
  if prefValues["Reset Cue List When New Show Selected"] then
    selectedUciCueEntry = 1
  end
  
  updateUCINextCueDisplay()
end


--------------------------
--   CUE LIST EDITOR    --
--------------------------

--SELECT CUE LIST
Controls.CueListEditor_CueList.EventHandler = function (cc)
  log('CueListEditor_CueList changed to ' .. cc.String)
  
  selectCueListByName(cc.String)
end

--DISPLAY CUE LIST INFO
displayCueListByName = function (cueListName)
  log('displayCueListByName function called with cue list ' .. cueListName)
  
  --display name in Cue List Editor selection dropdown
  Controls.CueListEditor_CueList.String = cueListName
  
  --display cues in cue list
  local numCuesInCueList = #cueLists[cueListName].cues
  for i = 1, numCuesInCueList do
    Controls.CueListEditor_TestCue[i].IsInvisible = false
    
    Controls.CueListEditor_MoveDown[i].IsInvisible = false
    
    Controls.CueListEditor_OrderText[i].IsInvisible = false
    
    Controls.CueListEditor_Name[i].String = cueLists[cueListName].cues[i].name
    Controls.CueListEditor_Name[i].IsInvisible = false
    
    Controls.CueListEditor_Cue[i].String = cueLists[cueListName].cues[i].cue
    Controls.CueListEditor_Cue[i].IsInvisible = false
    
    Controls.CueListEditor_CueLine[i].String = cueLists[cueListName].cues[i].cueLine
    Controls.CueListEditor_CueLine[i].IsInvisible = false
    
    Controls.CueListEditor_Select[i].IsInvisible = false
  end
  
  --hide unused cues  --There's probably cleaner way to do this invisibility thing. Not if we're counting each Control set individually.
  for i = numCuesInCueList + 1, #Controls.CueListEditor_TestCue do
    Controls.CueListEditor_TestCue[i].IsInvisible = true
  end
  for i = math.max(numCuesInCueList, 1), #Controls.CueListEditor_MoveDown do--must be at least 1 because no Control #0. Intentionally not + 1. Can't move the bottom row down.
    Controls.CueListEditor_MoveDown[i].IsInvisible = true
  end
  for i = numCuesInCueList + 1, #Controls.CueListEditor_OrderText do
    Controls.CueListEditor_OrderText[i].IsInvisible = true
  end
  for i = numCuesInCueList + 1, #Controls.CueListEditor_Name do
    Controls.CueListEditor_Name[i].String = ""
    Controls.CueListEditor_Name[i].IsInvisible = true
  end
  for i = numCuesInCueList + 1, #Controls.CueListEditor_Cue do
    Controls.CueListEditor_Cue[i].String = ""
    Controls.CueListEditor_Cue[i].IsInvisible = true
  end
  for i = numCuesInCueList + 1, #Controls.CueListEditor_CueLine do
    Controls.CueListEditor_CueLine[i].String = ""
    Controls.CueListEditor_CueLine[i].IsInvisible = true
  end
  for i = numCuesInCueList + 1, #Controls.CueListEditor_Select do
    Controls.CueListEditor_Select[i].IsInvisible = true
  end
  
  --select the first cue, in case this cue doesn't have multiple cue lines
  selectCueEntry(1)
end



--SELECT CUE IN CUE LIST
getSelectedCueEntryNumber = function ()
  log('getSelectedCueEntryNumber function called')
  local cueNumber = nil
  
  for i = 1, #Controls.CueListEditor_Select do
    if Controls.CueListEditor_Select[i].Boolean then
      cueNumber = i
      break
    end
  end
  
  return cueNumber
end

selectCueEntry = function (cueNumber)
  log('selectCueEntry function called with cue #' .. cueNumber)
  
  local numCuesInCueList = getNumberOfCuesInCueList()
  
  if cueNumber > 0 and cueNumber <= numCuesInCueList then
    
    --radio buttons
    for i = 1, #Controls.CueListEditor_Select do
      Controls.CueListEditor_Select[i].Boolean = (i == cueNumber)
    end
    
    --select this cue in the Cue Editor
    local cueListName = Controls.CueListEditor_CueList.String
    local cueName = cueLists[cueListName].cues[cueNumber].cue
    selectCueByName(cueName)
  
  else --if selected cue # is outside of range of existing cues
    --show nothing is selected
    for i = 1, #Controls.CueListEditor_Select do
      Controls.CueListEditor_Select[i].Boolean = false
    end
    
    log('Did not select Cue #' .. cueNumber .. '. It does not exist in this cue list.', 2)
  end
end

for i = 1, #Controls.CueListEditor_Select do
  Controls.CueListEditor_Select[i].EventHandler = function ()
    log('CueListEditor_Select #' .. i .. ' button pressed', 3)
    
    selectCueEntry(i)
  end
end


--EDIT CUE IN CUE LIST
for i = 1, #Controls.CueListEditor_Name do
  Controls.CueListEditor_Name[i].EventHandler = function (cc) --rename cues in cueList table when user renames
    local newName = scrubString(cc.String)
    
    log('CueListEditor_Name #' .. i .. " text field changed to " .. newName)
    
    local selectedCueList = getSelectedCueListName()
    local selectedCueEntry = cueLists[selectedCueList].cues[i]
    selectedCueEntry.name = newName
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.CueListEditor_Cue do
  Controls.CueListEditor_Cue[i].EventHandler = function (cc) --update table when user chooses new cue
    log('CueListEditor_Cue #' .. i .. " text field changed to " .. cc.String)
    
    local selectedCueList = getSelectedCueListName()
    local selectedCueEntry = cueLists[selectedCueList].cues[i]
    selectedCueEntry.cue = cc.String
    
    writeCurrentDB()
  end
end

for i = 1, #Controls.CueListEditor_CueLine do
  Controls.CueListEditor_CueLine[i].EventHandler = function (cc) --update table when user updates cue line
    log('CueListEditor_CueLine #' .. i .. " text field changed to " .. cc.String)
    
    local selectedCueList = getSelectedCueListName()
    local selectedCueEntry = cueLists[selectedCueList].cues[i]
    selectedCueEntry.cueLine = cc.String
    
    writeCurrentDB()
  end
end


--MOVING CUES IN CUE LIST
getNumberOfCuesInCueList = function ()
  log('getNumberOfCuesInCueList function called')
  
  local selectedCueList = getSelectedCueListName()
  local numCues = #cueLists[selectedCueList].cues
  
  return numCues
end

moveCueEntry = function (fromPosition, toPosition)
  log('moveCueEntry function called. Moving cue from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingCueName = Controls.CueListEditor_Name[fromPosition].String
  local selectedCueNumber = getSelectedCueNumber()
  
  if toPosition > 0 and toPosition <= getNumberOfCuesInCueList() then --only move it if there's a place to move to
    
    --get info of currently selected things
    local selectedCueListName = getSelectedCueListName()
    local selectedCueEntry = nil
    
    for i = 1, #Controls.CueListEditor_Select do
      if Controls.CueListEditor_Select[i].Boolean then
        selectedCueEntry = i
        break
      end
    end
    
    --update table of cue lists
    local cueTable = cueLists[selectedCueListName].cues
    cueLists[selectedCueListName].cues[selectedCueEntry].IsSelected = true --mark this cue so we can trace it through the move
    table.insert(cueTable, toPosition, table.remove(cueTable, fromPosition))
    
    --select this cue list to display updated cues
    selectCueListByName(selectedCueListName)
    
    --select same cue as before
    local cueToSelect = nil
    for i = 1, #cueLists[selectedCueListName].cues do --find the marked cue
      if cueLists[selectedCueListName].cues[i].IsSelected then
        cueToSelect = i
        break
      end
    end
    selectCueEntry(cueToSelect)
    cueLists[selectedCueListName].cues[selectedCueEntry].IsSelected = nil
     
    writeCurrentDB()
    
    log("Moved cue in Cue List Editor. " .. movingCueName .. " moved to position " .. toPosition, 3)
  else
    log("Did not move cue in Cue List Editor. No position " .. toPosition .. " exists to move cue " .. movingCueName .. " to.", 2)
  end
end

for i = 1, #Controls.CueListEditor_MoveDown do
  Controls.CueListEditor_MoveDown[i].EventHandler = function ()
    log('CueListEditor_MoveDown button #' .. i .. ' pressed', 3)
    
    moveCueEntry(i, i + 1)
  end
end

relistCueListEditorOrder = function ()
  log('relistCueListEditorOrder function called')
  
  for i = 1, #Controls.CueListEditor_OrderText do
    Controls.CueListEditor_OrderText[i].String = i
  end
end

for i = 1, #Controls.CueListEditor_OrderText do
  Controls.CueListEditor_OrderText[i].EventHandler = function (cc)
    log('CueListEditor_OrderText #' .. i .. ' changed to ' .. cc.String)
    
    moveCueEntry(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end


--COPY/CUT/INSERT/DELETE CUE IN CUE LIST
copiedCueEntry = nil
copiedCueEntryName = ""
Controls.CueListEditor_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert


copyCueEntry = function ()
  log('copyCueEntry function called')
  
  local selectedCueList = getSelectedCueListName()
  local selectedCueEntryNumber = getSelectedCueEntryNumber()
  local selectedCueEntry = cueLists[selectedCueList].cues[selectedCueEntryNumber]
  
  copiedCueEntry = copy(selectedCueEntry)
  copiedCueEntryName = Controls.CueListEditor_Name[selectedCueEntryNumber].String
  
  Controls.CueListEditor_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteCueEntry = function ()
  log('deleteCueEntry function called')
  
  local selectedCueList = getSelectedCueListName()
  local selectedCueEntryNumber = getSelectedCueEntryNumber()
  table.remove(cueLists[selectedCueList].cues, selectedCueEntryNumber)  
  selectCueListByName(selectedCueList) --refresh Cue List Editor
  
  local numCuesInCueList = getNumberOfCuesInCueList()
  local cueToSelect = math.min(selectedCueEntryNumber, numCuesInCueList)--what if you deleted last cue in the stack? then pick the last cue
  selectCueEntry(cueToSelect) --select new cue
  
  writeCurrentDB()
end

addCueEntry = function (cueEntryData, destinationOrder)
  log('addCueEntry function called. Adding to position ' .. destinationOrder)
  
  local selectedCueList = getSelectedCueListName()
  local numCuesInCueList = getNumberOfCuesInCueList()
  
  if numCuesInCueList + 1 <= #Controls.CueListEditor_Name then
    table.insert(cueLists[selectedCueList].cues, destinationOrder, cueEntryData)  
    selectCueListByName(selectedCueList) --refresh Cue List Editor
    selectCueEntry(destinationOrder)
    writeCurrentDB()
  else
    log("No cue was added. There isn't enough room in the Cue List Editor controls: Controls.CueListEditor_Name", 2)
  end
end

Controls.CueListEditor_Copy.EventHandler = function ()
  log('CueListEditor_Copy button pressed', 3)
  copyCueEntry()
end

Controls.CueListEditor_Delete.EventHandler = function ()
  log('CueListEditor_Delete button pressed', 3)
  deleteCueEntry()
end

Controls.CueListEditor_Cut.EventHandler = function ()
  log('CueListEditor_Cut button pressed', 3)
  copyCueEntry()
  deleteCueEntry()
end

Controls.CueListEditor_Insert.EventHandler = function ()
  log('CueListEditor_Insert button pressed', 3)
  
  local cueEntryData = copy(copiedCueEntry)
  local destinationOrder = getSelectedCueEntryNumber() or 1
  
  addCueEntry(cueEntryData, destinationOrder)
end

Controls.CueListEditor_New.EventHandler = function ()
  log('CueListEditor_New button pressed', 3)
  
  local newCueEntryData = {name = "New Entry", cue = "", cueLine = "", }
  local destinationOrder = ( getSelectedCueEntryNumber() or 0 ) + 1
  
  addCueEntry(newCueEntryData, destinationOrder)
end


--TEST CUE IN CUE LIST EDITOR
for i = 1, #Controls.CueListEditor_TestCue do
  Controls.CueListEditor_TestCue[i].EventHandler = function ()
    log('CueEditor_TestCue button #' .. i .. ' pressed', 3)
    
    local selectedCueName = Controls.CueListEditor_Cue[i].String
    executeCue(selectedCueName)
  end
end


--------------------------
--   REHEARSAL POINTS   --
--------------------------

rehearsalTime = 0
resetRehearsalTimer = Timer.New()
resetRehearsalTimer.EventHandler = function() --After playing cue, sets rehearsalSeekTime to 0
  resetRehearsalTimer:Stop()
  Controls.UCI_RehearsalSeekTime.Value = 0
end

getNumberOfRehearsalPoints = function ()
  log('getNumberOfRehearsalPoints function called')
  
  return #rehearsalPoints
end

populateRehearsalPoints = function ()
  log('populateRehearsalPoints function called')
  
  --show the info for existing data
  for i = 1, #rehearsalPoints do
    Controls.RehearsalPoints_MoveDown[i].IsInvisible = false
    Controls.RehearsalPoints_OrderText[i].IsInvisible = false
    
    Controls.RehearsalPoints_Name[i].String = rehearsalPoints[i].name
    Controls.RehearsalPoints_Name[i].IsInvisible = false
    
    Controls.RehearsalPoints_CueList[i].String = rehearsalPoints[i].cueList
    Controls.RehearsalPoints_CueList[i].IsInvisible = false
    
    Controls.RehearsalPoints_CueName[i].String = rehearsalPoints[i].cueName
    Controls.RehearsalPoints_CueName[i].IsInvisible = false
    
    Controls.RehearsalPoints_Time[i].String = rehearsalPoints[i].time
    Controls.RehearsalPoints_Time[i].IsInvisible = false
    
    Controls.RehearsalPoints_Select[i].IsInvisible = false
    
    Controls.RehearsalPoints_Load[i].IsInvisible = false
  end
  
  --hide the rest
  for i = math.max(#rehearsalPoints, 1), #Controls.RehearsalPoints_MoveDown do
    Controls.RehearsalPoints_MoveDown[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_OrderText do
    Controls.RehearsalPoints_OrderText[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_Name do
    Controls.RehearsalPoints_Name[i].String = ""
    Controls.RehearsalPoints_Name[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_CueList do
    Controls.RehearsalPoints_CueList[i].String = ""
    Controls.RehearsalPoints_CueList[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_CueName do
    Controls.RehearsalPoints_CueName[i].String = ""
    Controls.RehearsalPoints_CueName[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_Time do
    Controls.RehearsalPoints_Time[i].String = ""
    Controls.RehearsalPoints_Time[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_Select do
    Controls.RehearsalPoints_Select[i].IsInvisible = true
  end
  for i = #rehearsalPoints + 1, #Controls.RehearsalPoints_Load do
    Controls.RehearsalPoints_Load[i].IsInvisible = true
  end
  
  --disable rehearsal point controls, if necessary
  for i = 1, #Controls.RehearsalPoints_Load do
    setUciRehearsalPointLoadButtonIsDisabled(i)
  end
  for i = 1, #Controls.RehearsalPoints_CueName do
    setRehearsalPointsCueNameDropdownChoices(i)
  end
end

--EDIT REHEARSAL POINTS
for i = 1, #Controls.RehearsalPoints_Name do
  Controls.RehearsalPoints_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('RehearsalPoints_Name #' .. i .. ' changed to ' .. newName)
    
    rehearsalPoints[i].name = newName
    writeCurrentDB()
  end
end

for i = 1, #Controls.RehearsalPoints_CueList do
  Controls.RehearsalPoints_CueList[i].EventHandler = function (cc)
    log('RehearsalPoints_CueList button #' .. i .. ' changed to '.. cc.String)
    
    --update data
    rehearsalPoints[i].cueList = cc.String
    rehearsalPoints[i].cueName = "" --because the old cue probably doesn't exist in the new cue list
    writeCurrentDB()
    
    --populate list of cues in this cue list to the gui
    Controls.RehearsalPoints_CueName[i].String = ""
    setRehearsalPointsCueNameDropdownChoices(i)
  end
end

for i = 1, #Controls.RehearsalPoints_CueName do
  Controls.RehearsalPoints_CueName[i].EventHandler = function (cc)
    log('RehearsalPoints_CueName button #' .. i .. ' changed to '.. cc.String)
    
    rehearsalPoints[i].cueName = cc.String
    writeCurrentDB()
    
    setUciRehearsalPointLoadButtonIsDisabled(i)
  end
end

for i = 1, #Controls.RehearsalPoints_Time do
  Controls.RehearsalPoints_Time[i].EventHandler = function (cc)
    log('RehearsalPoints_Time #' .. i .. ' changed to ' .. cc.String)
    
    rehearsalPoints[i].time = cc.String
    writeCurrentDB()
    
    setUciRehearsalPointLoadButtonIsDisabled(i)
  end
end

--SELECT REHEARSAL POINTS
getSelectedRehearsalPointNumber = function ()
  log('getSelectedRehearsalPointNumber function called')
  
  local number = nil
  
  for i = 1, #Controls.RehearsalPoints_Select do
    if Controls.RehearsalPoints_Select[i].Boolean then
      number = i
      break
    end
  end
  
  return number
end

selectRehearsalPoint = function (selectionNumber)
  log('selectRehearsalPoint function called with #' .. selectionNumber)
  
  local numExisting = getNumberOfRehearsalPoints()
  
  if selectionNumber > 0 and selectionNumber <= numExisting then
    
    --radio buttons
    for i = 1, #Controls.RehearsalPoints_Select do
      Controls.RehearsalPoints_Select[i].Boolean = (i == selectionNumber)
    end
  
  else --if selected # is outside of range of existing
    
    --show nothing is selected
    for i = 1, #Controls.RehearsalPoints_Select do
      Controls.RehearsalPoints_Select[i].Boolean = false
    end
    
    log('Did not select Rehearsal Point #' .. selectionNumber .. '. It does not exist.', 2)
  end
end

for i = 1, #Controls.RehearsalPoints_Select do
  Controls.RehearsalPoints_Select[i].EventHandler = function ()
    log('RehearsalPoints_Select #' .. i .. ' button pressed', 3)
    
    selectRehearsalPoint(i)
  end
end


--MOVING REHEARSAL POINTS
moveRehearsalPoint = function (fromPosition, toPosition)
  log('moveRehearsalPoint function called. Moving rehearsal point from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingName = Controls.RehearsalPoints_Name[fromPosition].String
  
  if toPosition <= 0 or toPosition > getNumberOfRehearsalPoints() then --only move it if there's a place to move to
    log("Did not move rehearsal point. No position " .. toPosition .. " exists to move " .. movingName .. " to.", 2)
  else
    
    local selectedItem = nil
    for i = 1, #Controls.RehearsalPoints_Select do
      if Controls.RehearsalPoints_Select[i].Boolean then
        selectedItem = i
        break
      end
    end
    
    --update database
    rehearsalPoints[selectedItem].IsSelected = true
    table.insert(rehearsalPoints, toPosition, table.remove(rehearsalPoints, fromPosition))
    writeCurrentDB()
    
    local itemToSelect = nil
    for i = 1, #rehearsalPoints do
      if rehearsalPoints[i].IsSelected then
        itemToSelect = i
        break
      end
    end
    rehearsalPoints[selectedItem].IsSelected = nil
    
    
    --update view
    populateRehearsalPoints()
    selectRehearsalPoint(itemToSelect)
    
    --update rehearsal point controls' disabled on changed rows
    for i = math.min(fromPosition, toPosition), math.max(fromPosition, toPosition) do
      setUciRehearsalPointLoadButtonIsDisabled(i)
      setRehearsalPointsCueNameDropdownChoices(i)
    end
    
    log("Moved rehearsal point. " .. movingName .. " moved to position " .. toPosition, 3)
  end
end

for i = 1, #Controls.RehearsalPoints_MoveDown do
  Controls.RehearsalPoints_MoveDown[i].EventHandler = function ()
    log('RehearsalPoints_MoveDown button #' .. i .. ' pressed', 3)
    
    moveRehearsalPoint(i, i + 1)
  end
end

--Reordering by order text box
relistRehearsalPointsOrder = function ()
  log('relistRehearsalPointOrder function called')
  
  for i = 1, #Controls.RehearsalPoints_OrderText do
    Controls.RehearsalPoints_OrderText[i].String = i
  end
end

for i = 1, #Controls.RehearsalPoints_OrderText do
  Controls.RehearsalPoints_OrderText[i].EventHandler = function (cc)
    log('RehearsalPoints_OrderText button #' .. i .. ' pressed', 3)
    
    moveRehearsalPoint(i, tonumber(cc.String))
    cc.String = i --reset text edit field for next change
  end
end

--Reordering in name order
Controls.RehearsalPoints_SortAlphaName.EventHandler = function ()
  log('RehearsalPoints_SortAlphaName button presed')
  
  table.sort(rehearsalPoints, sortByname)
  
  populateRehearsalPoints()
  writeCurrentDB()
end

--Reordering in cue list order
Controls.RehearsalPoints_SortAlphaCueList.EventHandler = function ()
  log('RehearsalPoints_SortAlphaCueList button presed')
  
  table.sort(rehearsalPoints, sortByTime)
  table.sort(rehearsalPoints, sortByCueName)
  table.sort(rehearsalPoints, sortByCueList)
  
  populateRehearsalPoints()
  writeCurrentDB()
end

--COPY/CUT/INSERT/DELETE REHEARSAL POINTS
copiedRehearsalPoint = nil
copiedRehearsalPointName = ""
Controls.RehearsalPoints_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyRehearsalPoint = function ()
  log('copyRehearsalPoint function called')
  
  local selectedNumber = getSelectedRehearsalPointNumber()
  local selectedItem = rehearsalPoints[selectedNumber]
  
  copiedRehearsalPoint = copy(selectedItem)
  copiedRehearsalPointName = Controls.RehearsalPoints_Name[selectedNumber].String
  
  Controls.RehearsalPoints_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

deleteRehearsalPoint = function ()
  log('deleteRehearsalPoint function called')
  
  --remove from database
  local selectedNumber = getSelectedRehearsalPointNumber()
  table.remove(rehearsalPoints, selectedNumber)  
  
  --update view
  populateRehearsalPoints()
  
  local numItems = getNumberOfRehearsalPoints()
  local itemToSelect = math.min(selectedNumber, numItems)--what if you deleted last in the list? then pick the last one
  selectRehearsalPoint(itemToSelect)
  
  writeCurrentDB()
end

addRehearsalPoint = function (itemData, destinationOrder)
  log('addRehearsalPoint function called. Adding Rehearsal Point to position ' .. destinationOrder)
  
  if #rehearsalPoints + 1 > #Controls.RehearsalPoints_Name then
    log("No rehearsal point was created. There isn't enough room in the controls: Controls.RehearsalPoints_Name", 2)
  else
    table.insert(rehearsalPoints, destinationOrder, itemData)  
    selectRehearsalPoint(destinationOrder)
    populateRehearsalPoints()
    writeCurrentDB()
  end
end

Controls.RehearsalPoints_Copy.EventHandler = function ()
  log('RehearsalPoints_Copy button pressed', 3)
  copyRehearsalPoint()
end

Controls.RehearsalPoints_Delete.EventHandler = function ()
  log('RehearsalPoints_Delete button pressed', 3)
  deleteRehearsalPoint()
end

Controls.RehearsalPoints_Cut.EventHandler = function ()
  log('RehearsalPoints_Cut button pressed', 3)
  copyRehearsalPoint()
  deleteRehearsalPoint()
end

Controls.RehearsalPoints_Insert.EventHandler = function ()
  log('RehearsalPoints_Insert button pressed', 3)
  
  local itemData = copy(copiedRehearsalPoint)
  local destinationOrder = getSelectedRehearsalPointNumber() or 1
  
  addRehearsalPoint(itemData, destinationOrder)
end

Controls.RehearsalPoints_New.EventHandler = function ()
  log('RehearsalPoints_New button pressed', 3)
  
  local newData = {name = "New Rehearsal Point", cueList = "", cueName = "", time = "0"}
  local destinationOrder = 1
  if getNumberOfRehearsalPoints() > 0 then
    destinationOrder = ( getSelectedRehearsalPointNumber() or 0 ) + 1
  end
  
  addRehearsalPoint(newData, destinationOrder)
end



--Selecting cue list populates Cue Name dropdown
setRehearsalPointsCueNameDropdownChoices = function(controlNum)
  local listOfCues = {}
  local cueListName = Controls.RehearsalPoints_CueList[controlNum].String
  
  if cueLists[cueListName] then
    for i = 1, #cueLists[cueListName].cues do
      table.insert(listOfCues, cueLists[cueListName].cues[i].name)
    end
  end
  
  --set display of cues dropdown
  Controls.RehearsalPoints_CueName[controlNum].Choices = listOfCues
  Controls.RehearsalPoints_CueName[controlNum].IsDisabled = (Controls.RehearsalPoints_CueList[controlNum].String == "")
  
  setUciRehearsalPointLoadButtonIsDisabled(controlNum)
end

for i = 1, #Controls.RehearsalPoints_Load do
  Controls.RehearsalPoints_Load[i].EventHandler = function()
    log("Rehearsal Point Load button #" .. i .. " pressed", 3)
    
    --select show
    selectedUciShow = Controls.RehearsalPoints_CueList[i].String
    Controls.UCI_ShowDisplay.String = selectedUciShow
    Controls.UCI_ShowSelect.String = selectedUciShow
    
    --select cue
    for j = 1, #cueLists[selectedUciShow].cues do
      if Controls.RehearsalPoints_CueName[i].String == cueLists[selectedUciShow].cues[j].name then
        selectedUciCueEntry = j
        break
      end
    end
    
    --set time
    Controls.UCI_RehearsalSeekTime.Value = Controls.RehearsalPoints_Time[i].String
 
    updateStatusDisplay("Rehearsal point loaded")
      
    updateUCINextCueDisplay()
  end
end

setUciRehearsalPointLoadButtonIsDisabled = function (buttonNum)
  local isDisabled = false
  
  if Controls.RehearsalPoints_CueList[buttonNum].String == "" or Controls.RehearsalPoints_CueName[buttonNum].String == "" or Controls.RehearsalPoints_Time[buttonNum].String == "" then
    isDisabled = true
  end
  
  if Controls.RehearsalPoints_CueList[buttonNum].String == "" then
  --asdfasdfasdf
  end
  
  Controls.RehearsalPoints_Load[buttonNum].IsDisabled = isDisabled
end


--------------------------
--    CONTINGENCIES     --
--------------------------

--TODO Add Controls for contingencies
conditions = {}
displayConditions = function()
  log("displayConditions function called. " .. #conditions .. " conditions found", 4)
  for i = 1, #Controls.Conditions_Name do
    if i <= #conditions then
      -- if there's a condition, add its info to the controls
      Controls.Conditions_Name[i].String = conditions[i].name
      Controls.Conditions_InitValue[i].String = conditions[i].initValue
      Controls.Conditions_MinValue[i].String = conditions[i].minValue
      Controls.Conditions_MaxValue[i].String = conditions[i].maxValue
      Controls.Conditions_CurrentValue[i].String = conditions[i].currentValue
      Controls.Conditions_Note[i].String = conditions[i].note
    else
      -- otherwise, remove info from controls
      Controls.Conditions_Name[i].Color = ""
      Controls.Conditions_Name[i].String = ""
      Controls.Conditions_InitValue[i].String = ""
      Controls.Conditions_MinValue[i].String = ""
      Controls.Conditions_MaxValue[i].String = ""
      Controls.Conditions_CurrentValue[i].String = ""
      Controls.Conditions_Note[i].String = ""
    end
    -- change visibility
    Controls.Conditions_Name[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_InitValue[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_MinValue[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_MaxValue[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_CurrentValue[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_Note[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_OrderUp[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_OrderDown[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_OrderPlace[i].IsInvisible = i > #conditions + 1
    Controls.Conditions_OrderPlace[i].String = i
  end
end

getConditionIndex = function(str)
  log("getConditionIndex function called. Looking for "..str..".", 4)
  for k,v in pairs(conditions) do
    if v.name == str then
      return k
    end
  end
end

checkConditionValues = function(index)
  if Controls.Conditions_InitValue[index].String == "" then
    Controls.Conditions_InitValue[index].String = "0"
  end
  if Controls.Conditions_MinValue[index].String == "" then
    Controls.Conditions_MinValue[index].String = "0"
  end
  if Controls.Conditions_MaxValue[index].String == "" then
    Controls.Conditions_MaxValue[index].String = "1"
  end
  if Controls.Conditions_CurrentValue[index].String == "" then
    Controls.Conditions_CurrentValue[index].String = "0"
  end
  if Controls.Conditions_Name[index].String == "" then
    Controls.Conditions_Name[index].Color = "red"
    return false
  end
  Controls.Conditions_Name[index].Color = ""
  return true
end

saveCondition = function(index)
  log("saveCondition function called with index "..index..".", 4)
  local condition = conditions[index]
  if type(condition) ~= "table" then condition = {} end
  condition.name = Controls.Conditions_Name[index].String
  condition.initValue = tonumber(Controls.Conditions_InitValue[index].String)
  condition.minValue = tonumber(Controls.Conditions_MinValue[index].String)
  condition.maxValue = tonumber(Controls.Conditions_MaxValue[index].String)
  condition.currentValue = tonumber(Controls.Conditions_CurrentValue[index].String)
  condition.note = Controls.Conditions_Note[index].String
  conditions[index] = condition
  log("Condition "..condition.name.." added", 3)
  writeCurrentDB()
end

deleteCondition = function(index)
  local name = conditions[index].name
  table.remove(conditions,index)
  table.sort(conditions)
  displayConditions()
  log("Condition "..name.." removed.", 3)
  writeCurrentDB()
end

----------------------
--  EVENT HANDLERS  --
----------------------

for i = 1,#Controls.Conditions_Name do --Defines event handlers for all contingency buttons
  Controls.Conditions_Name[i].EventHandler = function(cc) --Activates contingency
    log("Condition Name EventHandler triggered", 4)
    if checkConditionValues(i) then
      saveCondition(i)
    else
      deleteCondition(i)
    end
  end
  Controls.Conditions_InitValue[i].EventHandler = function() --Activates contingency
    log("Condition init value eventhandler triggered.", 4)
    if checkConditionValues(i) then
      saveCondition(i)
    end
  end
  Controls.Conditions_MinValue[i].EventHandler = function(cc) --Activates contingency
    log("Condition min value eventhandler triggered.", 4)
    if checkConditionValues(i) then
      saveCondition(i)
    end
  end
  Controls.Conditions_MaxValue[i].EventHandler = function(cc) --Activates contingency
    log("Condition max value eventhandler triggered.", 4)
    if checkConditionValues(i) then
      saveCondition(i)
    end
  end
  Controls.Conditions_Note[i].EventHandler = function(cc) --Activates contingency
    log("Condition note eventhandler triggered.", 4)
    if checkConditionValues(i) then
      saveCondition(i)
    end
  end
end

Controls.Conditions_New.EventHandler = function()
  displayConditions()
end

Controls.Conditions_Alpha.EventHandler = function()
  table.sort(conditions, sortByname)
  displayConditions()
end

moveCondition = function(prev, new)
  log("Moving "..conditions[prev].name.." from " .. prev .. " to " .. new, 4)
  -- get entry to move
  --local entry = table.remove(conditions, prev)
  -- put it in place
  table.insert(conditions, new, table.remove(conditions, prev))
end

for i = 1, #Controls.Conditions_OrderPlace do

  Controls.Conditions_OrderPlace[i].EventHandler = function(cc)
    moveCondition(i, tonumber(cc.String))
    displayConditions()
    cc.String = i
  end
  
  Controls.Conditions_OrderUp[i].EventHandler = function(cc)
    moveCondition(i+1, i)
    displayConditions()
  end
  
  Controls.Conditions_OrderDown[i].EventHandler = function(cc)
    moveCondition(i, i+1)
    displayConditions()
  end

end
--------------------------
--       DATABASE       --
--------------------------

--CURRENTLY RUNNING DB
writeCurrentDB = function ()
  log('writeCurrentDB function called')
  
  local database = {}
  database.cues = cues
  database.rehearsalPoints = rehearsalPoints
  database.cueLists = cueLists
  database.conditions = conditions
  database.directRecalls = directRecalls
  database.todTriggers = todTriggers
  database.timecodeTriggers = timecodeTriggers
  database.networkTriggers = networkTriggers
  database.controlWatcherTriggers = controlWatcherTriggers
  database.prefValues = prefValues
  database.componentValues = componentValues
   
  Controls.Database_CurrentDB.String = json.encode(database)
  
  log('Database successfully written to Currently Running Database')
end


readCurrentDB = function ()
  log('readCurrentDB function called')
  
  --DATABASE
  local database = {}
  
  --if the control is empty, load the example
  if Controls.Database_CurrentDB.String == "" then 
    Controls.Database_CurrentDB.String = json.encode(exampleDatabase)
    database = exampleDatabase
  else
    database = json.decode(Controls.Database_CurrentDB.String)
  end
  
  cues = database.cues or {}
  rehearsalPoints = database.rehearsalPoints or {}
  directRecalls = database.directRecalls or {}
  todTriggers = database.todTriggers or {}
  timecodeTriggers = database.timecodeTriggers or {}
  networkTriggers = database.networkTriggers or {}
  controlWatcherTriggers = database.controlWatcherTriggers or {}
  conditions = database.conditions or {}
  cueLists = database.cueLists or {}
  prefValues = database.prefValues
  componentValues = database.componentValues
  
  --CUE LIBRARY
  populateCueNames()
  relistCueLibraryOrder()
  selectCueByPosition(1)
  
  --CUE EDITOR
  --selectCueLine(1) --already happens as subfunction of cue library init
  
  --REHEARSAL POINTS
  populateRehearsalPoints()
  relistRehearsalPointsOrder()
  selectRehearsalPoint(1)
  
  --CUE LISTS
  populateCueListNames()
  relistCueListsOrder()
  selectCueListByPosition(1)
  --TODO put the name of the first cue list to Controls.UCI_ShowSelect.String
  
  --CUE LIST EDITOR
  --selectCueEntry(1) --already happens as subfunction of cue lists init
  relistCueListEditorOrder()
  
  --DIRECT RECALLS
  populateDirectRecalls()
  relistDirectRecallOrder()
  
  --TIME OF DAY TRIGGERS
  populateTodTriggers()
  relistTodTriggerOrder()

  --CONDITIONS
  displayConditions()
  
  --TIMECODE TRIGGERS
  populateTimecodeTriggers()
  relistTimecodeTriggerOrder()
  
  --NETWORK TRIGGERS
  populateNetworkTriggers()
  relistNetworkTriggerOrder()
  
  --CONTROL WATCHER
  populateControlWatcherTriggers()
  makeControlWatcherEventHandlers()
  relistControlWatcherTriggerOrder()
  
  --PREFERENCES
  populatePrefs()
  
  --COMPONENTS
  populateComponentInfo()
  
  return database
end

saveDatabase = function (dbToSave, destination)
  log('saveDatabase function called. Saving Current DB to ' .. tostring(destination), 3) --TODO make this more useful
  
  if type(dbToSave) == "table" then
    dbToSave = json.encode(dbToSave)
  end
  
  destination.String = dbToSave
end

loadDatabase = function (dbToLoad, name)
  log('loadDatabase function called. Loading DB: ' .. name, 3)
  
  if type(dbToLoad) == "table" then
    dbToLoad = json.encode(dbToLoad)
  end
  
  Controls.Database_CurrentName.String = name
  Controls.Database_CurrentDB.String = dbToLoad
  
  readCurrentDB()
  log("Database ".. name .. " successfully loaded.", 3)
end


--EXAMPLE DB
Controls.Database_SaveExampleDB.EventHandler = function ()
  log('Database_SaveExampleDB button pressed', 3)
  
  local dbToSave = Controls.Database_CurrentDB.String
  local destination = Controls.Database_ExampleDB
  
  saveDatabase(dbToSave, destination)
end

Controls.Database_ExampleDB.IsDisabled = true


Controls.Database_LoadExampleDB.EventHandler = function ()
  log('Database_LoadExampleDB button pressed', 3)
  
  local dbToLoad = Controls.Database_ExampleDB.String
  local name = "Example Database"
  
  loadDatabase(dbToLoad, name)
end

Controls.Debug_EnableExampleDatabaseSave.EventHandler = function (cc)
  Controls.Database_SaveExampleDB.IsDisabled = not cc.Boolean
end

Controls.Database_SaveExampleDB.IsDisabled = not Controls.Debug_EnableExampleDatabaseSave.Boolean


--SAVED DB
for i = 1, #Controls.Database_Name do
  Controls.Database_Name[i].EventHandler = function (cc)
    local newName = scrubString(cc.String)
    
    log('Database_Name #' .. i .. " text field changed to " .. newName)
    
    --There's nothing really to do here. This data is just stored in the Control until it's needed later.
  end
end

for i = 1, #Controls.Database_Database do
  Controls.Database_Database[i].EventHandler = function (cc)
    log('Database_Database #' .. i .. " text field changed", 3)
    
    --There's nothing really to do here. This data is just stored in the Control until it's needed later.
  end
end

for i = 1, #Controls.Database_Save do
  Controls.Database_Save[i].EventHandler = function ()
    log('Database_Save button #' .. i .. " pressed", 3)
    
    local dbToSave = Controls.Database_CurrentDB.String
    local destination = Controls.Database_Database[i]
    Controls.Database_Name[i].String = Controls.Database_CurrentName.String
    
    saveDatabase(dbToSave, destination)
  end
end

for i = 1, #Controls.Database_Load do
  Controls.Database_Load[i].EventHandler = function ()
    log('Database_Load button #' .. i .. " pressed", 3)
    
    local dbToLoad = Controls.Database_Database[i].String
    local name = Controls.Database_Name[i].String
    
    loadDatabase(dbToLoad, name)
  end
end

--Reordering Alphabetically
Controls.Database_SortAlpha.EventHandler = function ()
  log('Database_SortAlpha button pressed', 3)
  
  local savedDatabases = {}
  
  --build table
  for i = 1, #Controls.Database_Name do
    if Controls.Database_Name[i].String ~= "" then
      local savedDatabase = {name = Controls.Database_Name[i].String, database = Controls.Database_Database[i].String}
      table.insert(savedDatabases, savedDatabase)
    end
  end
  
  --reorder table
  table.sort(savedDatabases, sortByname)
  
  --repopulate controls
  for i = 1, #savedDatabases do
    Controls.Database_Name[i].String = savedDatabases[i].name
    Controls.Database_Database[i].String = savedDatabases[i].database
  end
  for i = #savedDatabases + 1, #Controls.Database_Name do
    Controls.Database_Name[i].String = ""
  end
  for i = #savedDatabases + 1, #Controls.Database_Database do
    Controls.Database_Database[i].String = ""
  end
  
  log("Sorted Saved Databases alphabetically.", 3)
end


--MOVING
moveDatabase = function (fromPosition, toPosition)
  log('moveDatabase function called. Moving from ' .. fromPosition .. ' to ' .. toPosition)
  
  local movingDatabaseName = Controls.Database_Name[fromPosition].String
  local numDatabaseControls = #Controls.Database_Name
  
  if toPosition <= 0 or toPosition > numDatabaseControls then --only move it if there's a place to move to
    log("Did not move Database. No position " .. toPosition .. " exists to move database " .. movingDatabaseName .. " to.", 2)
    
  else
    --make table of moving databases
    local movingDatabases = {}
    local tableLength = math.abs(fromPosition - toPosition) + 1
    local tableStart = math.min(fromPosition, toPosition)
    
    for i = 1, tableLength do
      local controlsPosition = tableStart + i - 1
      
      local name = Controls.Database_Name[controlsPosition].String
      local database = Controls.Database_Database[controlsPosition].String
      local isSelected = Controls.Database_Select[controlsPosition].Boolean
      
      local databaseTable = {name = name, database = database, isSelected = isSelected}
      
      table.insert(movingDatabases, databaseTable)
    end
    
    --reorder table of moving databases
    local movingDatabaseToPosition = toPosition - tableStart + 1
    local movingDatabaseFromPosition = fromPosition - tableStart + 1
    
    table.insert(movingDatabases, movingDatabaseToPosition, table.remove(movingDatabases, movingDatabaseFromPosition))
    
    --put info back into controls
    for i = 1, tableLength do
      local controlsPosition = tableStart + i - 1
      
      Controls.Database_Name[controlsPosition].String = movingDatabases[i].name
      Controls.Database_Database[controlsPosition].String = movingDatabases[i].database
      Controls.Database_Select[controlsPosition].Boolean = movingDatabases[i].isSelected
    end
    
    log("Moved database. " .. movingDatabaseName .. " moved to position " .. toPosition, 3)
  end
end

for i = 1, #Controls.Database_MoveDown do
  Controls.Database_MoveDown[i].EventHandler = function ()
    moveDatabase(i, i + 1)
  end
end

--Reordering by order text box
relistDatabaseOrder = function ()
  log('relistDatabaseOrder function called')
  
  for i = 1, #Controls.Database_OrderText do
    Controls.Database_OrderText[i].String = i
  end
end

for i = 1, #Controls.Database_OrderText do
  Controls.Database_OrderText[i].EventHandler = function (cc)
    log('Database_OrderText #' .. i .. " text field changed to " .. cc.String)
    
    moveDatabase(i, tonumber(cc.String))
    cc.String = i
  end
end


--SELECT DATABASE
getSelectedDatabaseNumber = function () --returns the order# of the selected database
  log('getSelectedDatabaseNumber function called')
  
  for i = 1, #Controls.Database_Select do
    if Controls.Database_Select[i].Boolean then
      return i
    end
  end
end

selectDatabaseByPosition = function (selectedDatabasePosition) --selects a database, given a number in the list
  log('selectDatabaseByPosition function called with position ' ..selectedDatabasePosition)
  
  local numDatabaseControls = #Controls.Database_Select
  
  if selectedDatabasePosition > 0 and selectedDatabasePosition <= numDatabaseControls then
    
    --radio buttons
    for i = 1, numDatabaseControls do
      Controls.Database_Select[i].Boolean = (i == selectedDatabasePosition)
    end
    
    --populate Controls
    local selectedDatabaseName = Controls.Database_Name[selectedDatabasePosition].String
    
  else --database # is out of bounds of existing database
    --show nothing is selected
    for i = 1, #Controls.Database_Select do
      Controls.Database_Select[i].Boolean = false
    end
    
    log ('Did not select Database #' .. selectedDatabasePosition .. ". It does not exist.", 2)
  end
end

--Select buttons
for i = 1, #Controls.Database_Select do
  Controls.Database_Select[i].EventHandler = function ()
    log('Database_Select #' .. i .. " button pressed", 3)
    
    selectDatabaseByPosition(i)
  end
end


--NEW/COPY/INSERT/DELETE
copiedDatabase = nil
copiedDatabaseName = ""
Controls.Database_Insert.IsDisabled = true --if nothing is copied yet, you shouldn't be able to Insert

copyDatabase = function (numDatabase) --copies a database to the "clipboard"
  log('copyDatabase function called with numDatabase ' .. numDatabase)
  
  copiedDatabase = Controls.Database_Database[numDatabase].String
  copiedDatabaseName = Controls.Database_Name[numDatabase].String
  
  Controls.Database_Insert.IsDisabled = false --now that something is copied, you should be able to Insert
end

hideUnusedDatabaseRows = function ()
  log('hideUnusedDatabaseRows function called')
  
  local hideRow = true
  
  for i = #Controls.Database_Database, 1, -1 do --start from the bottom
    
    --if this row isn't empty, all rows (this and above) should be not invisible
    if Controls.Database_Database[i].String ~= "" or Controls.Database_Name[i].String ~= "" then
      hideRow = false
    end
    
    Controls.Database_MoveDown[i].IsInvisible = hideRow
    Controls.Database_OrderText[i].IsInvisible = hideRow
    Controls.Database_Name[i].IsInvisible = hideRow
    Controls.Database_Database[i].IsInvisible = hideRow
    Controls.Database_Select[i].IsInvisible = hideRow
    Controls.Database_Save[i].IsInvisible = hideRow
    Controls.Database_Load[i].IsInvisible = hideRow
  end
end

deleteDatabase = function (numDatabase) --deletes a database from the list & shifts everything up.
  log('deleteDatabase function called with numDatabase ' .. numDatabase)
  
  --remove deleted cue
  Controls.Database_Database[numDatabase].String = ""
  Controls.Database_Name[numDatabase].String = ""
  
  --shift everything up (by moving the empty one to the bottom)
  moveDatabase(numDatabase, #Controls.Database_Database)
  
  --select the next database if you just deleted the selected one
  if Controls.Database_Select[#Controls.Database_Database].Boolean then
    selectDatabaseByPosition(numDatabase)
  end
  
  hideUnusedDatabaseRows()
  
end

addDatabase = function (databaseTable, databaseName, destinationOrder) --adds the provided database to the selected position. bumps cues down.
  log('addDatabase function called with databaseName ' .. databaseName .. ' into position ' .. destinationOrder)
  
  if destinationOrder < 1 or destinationOrder > #Controls.Database_Database then
    log("Database was not added. Position #" .. destinationOrder .. " doesn't exist in the Database Controls: Controls.Database_Database", 2)
    
  else
    --create table of existing databases
    local movingDatabaseTable = {}
    local foundEmptySpot = false
    
    for i = destinationOrder, #Controls.Database_Database do
      local name = Controls.Database_Name[i].String
      local database = Controls.Database_Database[i].String
      local isSelected = Controls.Database_Select[i].Boolean
      
      --stop if you find an empty spot
      if name == "" and database == "" then
        foundEmptySpot = true
        break
      end
      
      local databaseToInsert = {name = name, database = database, isSelected = isSelected}
      
      table.insert(movingDatabaseTable, databaseToInsert)
    end
    
    --insert new database
    if not foundEmptySpot then
      log("Database was not added. Inserting at Position #" .. destinationOrder .. " would push a database out the bottom. Try inserting above an empty row.")
    
    else
      --put info back into Controls
      Controls.Database_Name[destinationOrder].String = databaseName
      Controls.Database_Database[destinationOrder].String = databaseTable
      
      for i = 1, #movingDatabaseTable do
        local controlsRowToWrite = destinationOrder + i
        Controls.Database_Name[controlsRowToWrite].String = movingDatabaseTable[i].name
        Controls.Database_Database[controlsRowToWrite].String = movingDatabaseTable[i].database
        Controls.Database_Select[controlsRowToWrite].Boolean = movingDatabaseTable[i].isSelected
      end
      
      --select the new database
      selectDatabaseByPosition(destinationOrder)
      
      hideUnusedDatabaseRows()
      
      log("Database " .. databaseName .. " added in position " .. destinationOrder, 3)
    end
  end
end

Controls.Database_Copy.EventHandler = function ()
  log('Database_Copy button pressed', 3)
  
  local numDatabase = getSelectedDatabaseNumber()
  
  copyDatabase(numDatabase)
end

Controls.Database_Delete.EventHandler = function ()
  log('Database_Delete button pressed', 3)
  
  local numDatabase = getSelectedDatabaseNumber()
  deleteDatabase(numDatabase)
end

Controls.Database_Cut.EventHandler = function ()
  log('Database_Cut button pressed', 3)
  
  local numDatabase = getSelectedDatabaseNumber()
  
  copyDatabase(numDatabase)
  deleteDatabase(numDatabase)
end

Controls.Database_Insert.EventHandler = function ()
  log('Database_Insert button pressed', 3)
  
  if not copiedDatabase then
    log("No database inserted. No database has been copied or cut.", 2)
    
  else
    local destinationOrder = getSelectedDatabaseNumber() or 1
    
    addDatabase(copiedDatabase, copiedDatabaseName, destinationOrder)
  end
end

Controls.Database_New.EventHandler = function ()
  log('Database_New button pressed', 3)
  
  local newDatabase = ""
  local databaseName = "New Database"
  local destinationOrder = getSelectedDatabaseNumber()
  
  addDatabase(newDatabase, databaseName, destinationOrder)
end


--------------------------
--         TOOLS        --
--------------------------
findAndReplace = function (fromString, toString, wholeString) --searches through database for string and replaces it
  log('findAndReplace function called. Replacing ' .. fromString .. ' with ' .. toString .. '. Searching only for whole strings is ' .. tostring(wholeString))
  
  local jsonDatabase = Controls.Database_CurrentDB.String
  local numReplacements = 0
  
  if wholeString ~= false then
    fromString = "\"" .. fromString .. "\""
    toString = "\"" .. toString .. "\""
  end
  
  jsonDatabase, numReplacements = string.gsub(jsonDatabase, fromString, toString)
  
  Controls.Database_CurrentDB.String = jsonDatabase
  readCurrentDB()
  
  --inform user
  local msg = 'Replaced ' .. fromString .. ' with ' .. toString .. ' ' .. numReplacements .. ' times'
  Controls.FindAndReplace_Readback.String = msg
  log(msg)
end

writeFindAndReplaceWholeStringLegend = function ()
  log('writeFindAndReplaceWholeStringLegend function called')
  
  local button = Controls.FindAndReplace_WholeString
  
  if button.Boolean then
    button.Legend = "Whole Strings only"
  else
    button.Legend = "Partial Strings ok"
  end
  
  log('Find and Replace now set to: ' .. button.Legend)
end

Controls.FindAndReplace_WholeString.EventHandler = function (cc)
  log('FindAndReplace_WholeString button pressed', 3)
  
  writeFindAndReplaceWholeStringLegend()
end

Controls.FindAndReplace_Search.EventHandler = function ()
  log('FindAndReplace_Search button pressed', 3)
  
  local fromString = Controls.FindAndReplace_FromString.String
  local toString = Controls.FindAndReplace_ToString.String
  local wholeString = Controls.FindAndReplace_WholeString.Boolean
  
  findAndReplace(fromString, toString, wholeString)
end



--------------------------
--         DEBUG        --
--------------------------

Controls.Debug_RestartEasyCueScript.EventHandler = function ()
  log('Debug_RestartEasyCueScript button pressed', 0)
  
  local comp = Component.New('EasyCue')
  comp['reload'].Boolean = true
end


--------------------------
--    INITIALIZATION    --
--------------------------
log('EasyCue is initializing.', 0)

--LOG
clearStatusLED()

--FUNCTION LIST
populateFunctionList()

--update function list with current info
for i = 1,#Controls.FunctionList_Select do
  if Controls.FunctionList_Select[i].Boolean then
    displayFunctionInfo(i)
    break
  end
end

--AUDIO FILES TABLE MAKER
for i = 1, #Controls.TableMaker_FileNameCombo do
  Controls.TableMaker_FileNameCombo[i].IsDisabled = System.IsEmulating
end

--DATABASE
relistDatabaseOrder()
hideUnusedDatabaseRows()
--writeCurrentDB()
readCurrentDB()

--COMPONENTS
updateAllComponentDesignNameValues()

watchTimecodeReader()

--PLAYBACK
countLoopPlayerChannels()
countPlaybackRouterOutputChannels()
setUpAutoMuteOfPlaybackChannels()
getNumAvailableLoopPlayerChannels()
--Mute router outputs
for i = 1, numPlaybackRouterOutputChannels do
  components["Playback Router"].component["mute."..i].Boolean = true
end

--UCI
Controls.UCI_Go.IsDisabled = false
Controls.UCI_RehearsalSeekTime.Value = 0
selectedUciShow = Controls.UCI_ShowSelect.String
Controls.UCI_ShowDisplay.String = Controls.UCI_ShowSelect.String
selectedUciCueEntry = 1
updateUCINextCueDisplay()
for i = 1, #Controls.RehearsalPoints_Load do
  setUciRehearsalPointLoadButtonIsDisabled(i)
end
for i = 1, #Controls.RehearsalPoints_CueName do
  setRehearsalPointsCueNameDropdownChoices(i)
end

--Update Contingency info
for i = 1, #conditions do
  -- Controls.ContingencyOnLED[i].Boolean = conditions[i].active
  -- Controls.ContingencyNameDisplay[i].String = conditions[i].name
end

--TOOLS
writeFindAndReplaceWholeStringLegend()
writeTodEnableLegend()
writeTimecodeEnableLegend()
writeNetworkTriggersEnableLegend()
writeControlWatcherTriggersEnableLegend()


log('EasyCue is ready. Enjoy!', 0)



--------------------------
--       TESTING        --
--------------------------

Controls.Debug_TestTrigger.EventHandler = function ()
  log('Debug_TestTrigger button pressed', 3)
  
  --go nuts, supercoder
  
end

for i = 1, #Controls.CueEditor_ValueDropDown do
  Controls.CueEditor_ValueDropDown[i].IsInvisible = true
end

--This gets all the possible control names for a component
--[[
controlList = ""
for key, value in pairs (audioCentral) do
  controlList = controlList .. key .. "\n"
end
print(controlList)
]]

--This gets all the possible component names in the design
--[[
componentList = ""
for key, value in pairs (Component.GetComponents()) do
  componentList = componentList .. value.Type .. "\n"
end
print(componentList)
]]

--This gets info from a 2D Panner
--[[
for i = 1,2 do
  nameOf2DPanner["input."..i..".position"].EventHandler = function(cc)
    print(cc.Positions[1]..cc.Positions[2])
  end
end
]]

--Prints the active IP addresses of the core in version 7+
--[[
ipList = ""
ni = Network.Interfaces()
for _, item in ipairs(ni) do
  ipList = ipList .. item.Interface .. " = " .. item.Address .."\n"
end
print(ipList)
]]
