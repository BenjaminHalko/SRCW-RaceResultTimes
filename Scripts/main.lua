-- Each racer's time for the race, after their name, on the 12-row results of the modes with points
-- or online ratings.
local ROW_CLASS = "/Game/01_Union/UI/Result/WBP_Result_Sub_RankingTable_GP_02.WBP_Result_Sub_RankingTable_GP_02_C"
local LINE_CLASS = "/Game/01_Union/UI/Result/WBP_Result_Sub_RankingTable_GP_Line.WBP_Result_Sub_RankingTable_GP_Line_C"
local LOADING_CLASS = "/Game/01_Union/UI/System/WBP_System_Loading_BG.WBP_System_Loading_BG_C"
local RESULTS = "/Script/UNION.Default__AppRaceResultDataAccessor"
local RACE_CONFIG = "/Script/UNION.Default__AppRaceConfigDataAccessor"
local TIME_TRIAL = "/Script/UNION.Default__TimeTrialUtilityLibrary"
local RESULT_FOUND = 0
local RF_DEFAULT_OR_TEMPLATE = 0x30

local cache = {}
local function find(path)
  local o = cache[path]
  if not (o and o:IsValid()) then
    o = StaticFindObject(path)
    cache[path] = o
  end
  return o
end

-- Row layout, in the row's own units. The name column gives up the time's room, so rows keep their
-- width on every variant of the screen. Online, the rating block overlaps what is before it by
-- RATING_OVERLAP, so the time leaves that much room after it.
local TIME_FONT_SIZE = 44
local NAME_WIDTH = 600
local RATING_OVERLAP = 100
local ONLINE_NAME_WIDTH = NAME_WIDTH - RATING_OVERLAP
local TIME_PADDING_ONLINE = { Left = 0, Top = 0, Right = RATING_OVERLAP, Bottom = 0 }
-- The rating's and points' own slot settings, as the game lays them out.
local RATING_PADDING = { Left = -RATING_OVERLAP, Top = 0, Right = -70, Bottom = 10 }
local POINTS_PADDING = { Left = 100, Top = 0, Right = 0, Bottom = 0 }
local ALIGN_CENTER = 2
local VIS_VISIBLE, VIS_HIDDEN = 0, 2
local NO_TIME = FText(" ")

local LINE_ROWS = {}
for i = 1, 12 do LINE_ROWS[i] = ("WBP_Result_Sub_RankingTable_GP_%02d"):format(i) end

-- The widget whose layout holds w.
local function owner(w)
  return w:GetOuter():GetOuter()
end

local function isA(o, classPath)
  local class = find(classPath)
  return class:IsValid() and o:IsA(class)
end

-- Only the results' 12-row tables. The team results and the standings shown while the next race
-- loads use the same rows, and stay as they are.
local function isResultsTable(line)
  return isA(line, LINE_CLASS) and not isA(owner(line), LOADING_CLASS)
end

local function addCentered(box, widget, padding)
  local slot = box:AddChildToHorizontalBox(widget)
  slot:SetVerticalAlignment(ALIGN_CENTER)
  slot:SetHorizontalAlignment(ALIGN_CENTER)
  slot:SetPadding(padding)
end

-- The rating, points and the spacer that ends the row move after the row's own time text, which is
-- shown smaller. Done as the row is built, before it is first laid out.
local function layOutRow(row)
  if not isResultsTable(owner(row)) then return end
  local tree = row.WidgetTree:GetFullName():match("^%S+ (.+)$") .. "."
  local time, rating, points = row.TXT_Time, row.DSP_Online, row.SizeBox_Offline
  local box, spacer = time:GetParent(), StaticFindObject(tree .. "Spacer_102")
  for _, w in ipairs({ rating, points, spacer }) do box:RemoveChild(w) end
  addCentered(box, rating, RATING_PADDING)
  addCentered(box, points, POINTS_PADDING)
  box:AddChildToHorizontalBox(spacer)
  local online = find(RACE_CONFIG):GetIsOnlineGameMode()
  if online then time.Slot:SetPadding(TIME_PADDING_ONLINE) end
  local font = time.Font
  font.Size = TIME_FONT_SIZE
  time:SetFont(font)
  local nameBox = StaticFindObject(tree .. "SizeBox_Name")
  nameBox:SetWidthOverride(online and ONLINE_NAME_WIDTH or NAME_WIDTH)
end

local function milliseconds(t)
  return (t.MinutePart * 60 + t.SecondPart) * 1000 + t.MillimeterSecondPart
end

-- The results keep each racer's total time before and after this race.
local function raceTime(racer)
  local data, pin = {}, {}
  find(RESULTS):GetAppRacePlayerResultData(racer, data, pin)
  if pin.OutExecsPin ~= RESULT_FOUND then return end
  local ms = milliseconds(data.RacerTotalTimes) - milliseconds(data.TotalTimesPrev)
  if ms > 0 then return ms end
end

local function showTime(row)
  if not isResultsTable(owner(row)) then return end
  local ms, time = raceTime(row.RacerIndex), row.TXT_Time
  time:SetText(ms and find(TIME_TRIAL):LapTimeText(ms) or NO_TIME)
  time:SetVisibility(VIS_VISIBLE)
end

-- The cup standings, once the results card flips over to them. Hidden rather than collapsed, so
-- nothing else in the row moves.
local function hideLineTimes(line)
  if not isResultsTable(line) then return end
  for _, name in ipairs(LINE_ROWS) do line[name].TXT_Time:SetVisibility(VIS_HIDDEN) end
end

local hooks = {
  { path = ROW_CLASS .. ":Construct", fn = layOutRow },
  { path = ROW_CLASS .. ":SetRacerIndex", fn = showTime },
  { path = LINE_CLASS .. ":PlayTotalInAnimForResult", fn = hideLineTimes },
  { path = LINE_CLASS .. ":PlayTotalInAnim_Impl", fn = hideLineTimes },
}

local function safely(fn)
  return function(ctx)
    local ok, err = pcall(fn, ctx:get())
    if not ok then print("[RaceResultTimes] " .. tostring(err) .. "\n") end
  end
end

-- The results classes load with the first results screen, so the hooks are added once they exist.
-- Every table builds rows, so new rows are the cue to try again.
local pending = #hooks
local function tryHooks()
  for _, h in ipairs(hooks) do
    local ready = not h.done and StaticFindObject(h.path):IsValid()
    if ready and pcall(RegisterHook, h.path, safely(h.fn)) then
      h.done, pending = true, pending - 1
    end
  end
  return pending == 0
end
if not tryHooks() then
  NotifyOnNewObject(ROW_CLASS, function(o)
    if not o:HasAnyFlags(RF_DEFAULT_OR_TEMPLATE) then return tryHooks() end
  end)
end
