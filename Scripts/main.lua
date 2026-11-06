-- Each racer's time for the race, after their name, on the 12-row results of the modes with points
-- or online ratings.
local ROW_CLASS = "/Game/01_Union/UI/Result/WBP_Result_Sub_RankingTable_GP_02.WBP_Result_Sub_RankingTable_GP_02_C"
local LINE_CLASS = "/Game/01_Union/UI/Result/WBP_Result_Sub_RankingTable_GP_Line.WBP_Result_Sub_RankingTable_GP_Line_C"
local LOADING_CLASS = "/Game/01_Union/UI/System/WBP_System_Loading_BG.WBP_System_Loading_BG_C"
local LINE_ROWS = 12
local RESULTS = "/Script/UNION.Default__AppRaceResultDataAccessor"
local RACE_CONFIG = "/Script/UNION.Default__AppRaceConfigDataAccessor"
local FORMATTER = "/Script/UNION.Default__RaceResultSequenceStateParty"
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
local NO_PADDING = { Left = 0, Top = 0, Right = 0, Bottom = 0 }
local ALIGN_CENTER = 2
local VIS_VISIBLE, VIS_HIDDEN = 0, 2

local function child(w, name)
  return StaticFindObject(w.WidgetTree:GetFullName():match("^%S+ (.+)$") .. "." .. name)
end

local function seconds(t)
  return t.MinutePart * 60 + t.SecondPart + t.MillimeterSecondPart / 1000
end

-- The results keep each racer's total time before and after this race.
local function raceTime(racerIndex)
  local data, pin = {}, {}
  find(RESULTS):GetAppRacePlayerResultData(racerIndex, data, pin)
  if pin.OutExecsPin ~= RESULT_FOUND then return end
  local t = seconds(data.RacerTotalTimes) - seconds(data.TotalTimesPrev)
  if t > 0 then return t end
end

local function addSlot(box, widget, padding)
  local slot = box:AddChildToHorizontalBox(widget)
  slot:SetVerticalAlignment(ALIGN_CENTER)
  slot:SetPadding(padding)
  return slot
end

-- The row's own time text (after the points) moves in front of the rating and points, at a smaller
-- size. Done once per row.
local function moveTime(row)
  local box, rating = row.TXT_Time:GetParent(), row.DSP_Online
  if box:GetChildIndex(row.TXT_Time) < box:GetChildIndex(rating) then return end
  local points, spacer = row.SizeBox_Offline, child(row, "Spacer_102")
  for _, w in ipairs({ row.TXT_Time, rating, points, spacer }) do box:RemoveChild(w) end
  addSlot(box, row.TXT_Time, NO_PADDING)
  addSlot(box, rating, RATING_PADDING):SetHorizontalAlignment(ALIGN_CENTER)
  addSlot(box, points, POINTS_PADDING):SetHorizontalAlignment(ALIGN_CENTER)
  addSlot(box, spacer, NO_PADDING)
  local font = row.TXT_Time.Font
  font.Size = TIME_FONT_SIZE
  row.TXT_Time:SetFont(font)
end

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

local function showTime(row)
  if not isResultsTable(owner(row)) then return end
  moveTime(row)
  local online = find(RACE_CONFIG):GetIsOnlineGameMode()
  row.TXT_Time.Slot:SetPadding(online and TIME_PADDING_ONLINE or NO_PADDING)
  child(row, "SizeBox_Name"):SetWidthOverride(online and ONLINE_NAME_WIDTH or NAME_WIDTH)
  local t = raceTime(row.RacerIndex)
  row.TXT_Time:SetText(FText(t and find(FORMATTER):FloatTimeToString(t):ToString() or " "))
  row.TXT_Time:SetVisibility(VIS_VISIBLE)
end

-- Hidden rather than collapsed, so nothing else in the row moves.
local function hideTime(row)
  row.TXT_Time:SetVisibility(VIS_HIDDEN)
end

-- The cup standings, once the results card flips over to them.
local function hideLineTimes(line)
  if not isResultsTable(line) then return end
  for i = 1, LINE_ROWS do hideTime(line[("WBP_Result_Sub_RankingTable_GP_%02d"):format(i)]) end
end

local hooks = {
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
    if not h.done and StaticFindObject(h.path):IsValid() and pcall(RegisterHook, h.path, safely(h.fn)) then
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