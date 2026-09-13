-- Targeted 3.3.5a runtime reconciliation. XML text attributes are copied
-- before addons load; quest list/map code also writes English during updates.
-- Only known stock writers are hooked: never the global FontString:SetText.
local W = CreateFrame("Frame")
local function qdata(id) return id and QTR_QuestData and QTR_QuestData[tostring(id)] end
local function title(id) local q=qdata(id); return q and q.Title ~= "" and q.Title end
local function suffix(s) return s and s:match("(%s*[:%-]?%s*%d+%s*/%s*%d+%s*)$") or "" end
local function set(name,text)
  local f=_G[name]
  if f and text then
    f:SetText(text)
    -- UIPanelButtonTemplate can retain its pre-addon FontString value even
    -- when the button object has been enabled/disabled by stock FrameXML.
    local fs=f.GetFontString and f:GetFontString()
    if fs then fs:SetText(text) end
  end
end
local function regionText(frame,en,it)
  if not frame then return end
  for i=1,select("#",frame:GetRegions()) do local r=select(i,frame:GetRegions()); if r and r.GetText and r:GetText()==en then r:SetText(it) end end
end
-- Stock FrameXML assigns these texts during its render calls.  Defer exactly
-- one frame so this runs after the final Blizzard write, not just after a
-- nearby event notification.
W.pending = {}
function W:Defer(kind)
  self.pending[kind]=true
  self:SetScript("OnUpdate",function(frame)
    frame:SetScript("OnUpdate",nil)
    local p=frame.pending; frame.pending={}
    if p.watch then frame:WatchNow() end
    if p.map then frame:WorldMapQuestsNow() end
    if p.ui then frame:CoreUI(); frame:WorldMapUI() end
    if p.stats then frame:CompactStats() end
  end)
end
local function liveObjective(it,live)
  if not it or it=="" then return live end
  -- GetQuestLogLeaderBoard normally returns "Name: 0/8".  Both stock
  -- WatchFrame and WorldMap reverse that into "0/8 Name" before display.
  -- Keep the live token, but preserve that actual rendered presentation.
  local prefix=live and live:match("^(%s*%d+%s*/%s*%d+)%s*")
  if prefix then return prefix.." "..it end
  local tail=live and live:match("(%s*[:%-]?%s*%d+%s*/%s*%d+%s*)$")
  if tail then
    local progress=tail:match("(%d+%s*/%s*%d+)")
    return progress and (progress.." "..it) or (it..tail)
  end
  return it
end
-- A tracker leaderboard is not the general quest Objectives paragraph.
-- Absent records deliberately retain Blizzard text for review rather than
-- guessing or applying a title/objective from another quest.
local function objectiveLine(id,index)
  local q=WIT_QuestObjectiveLines and WIT_QuestObjectiveLines[id]
  return q and q[index]
end
-- QuestLog renders its leaderboard directly from this API, while WatchFrame
-- and WorldMap use it as their live source.  Translate only the semantic
-- objective portion and retain Blizzard's current counter/completion state.

-- ---------------------------------------------------------------------------
-- Canonical quest-log API localization.
--
-- WatchFrame rewrites its title/completion rows repeatedly.  Translating only
-- the visible FontStrings is therefore temporary: on the next stock refresh
-- the English text comes back.  Localize the API values instead, preserving
-- every non-text return value and the canonical quest ID.
-- ---------------------------------------------------------------------------

local WIT_GetQuestLogTitle=GetQuestLogTitle

function GetQuestLogTitle(index)
  local en,level,questTag,suggestedGroup,isHeader,isCollapsed,isComplete,isDaily,id =
    WIT_GetQuestLogTitle(index)

  if en and id and not isHeader then
    local it=title(id)
    if it and it~="" then en=it end
  end

  return en,level,questTag,suggestedGroup,isHeader,isCollapsed,isComplete,isDaily,id
end

local function questObjectivesIT(id)
  if not id or not QTR_QuestData then return nil end

  local q=QTR_QuestData[tostring(id)] or QTR_QuestData[id]
  local text=q and q["Objectives"]

  if not text or text=="" then return nil end

  -- QuestTradutor transport tokens -> ordinary tracker text.
  text=text:gsub("NEW_LINE"," ")

  local playerName=UnitName("player") or ""
  local playerClass=UnitClass("player") or ""
  local playerRace=UnitRace("player") or ""

  text=text:gsub("YOUR_NAME",playerName)
  text=text:gsub("YOUR_CLASS",playerClass)
  text=text:gsub("YOUR_RACE",playerRace)

  -- QuestTradutor gender token: YOUR_GENDER(maschio;femmina)
  text=text:gsub(
    "YOUR_GENDER%(%s*(.-)%s*;%s*(.-)%s*%)",
    function(male,female)
      local v=(UnitSex("player")==3) and female or male
      return (v:gsub("^%s+",""):gsub("%s+$",""))
    end
  )

  -- Tracker/WorldMap fanno già il wrapping: niente newline artificiali.
  text=text:gsub("%s+"," ")
  text=text:gsub("^%s+",""):gsub("%s+$","")

  return text~="" and text or nil
end

local WIT_GetQuestLogCompletionText=GetQuestLogCompletionText

function GetQuestLogCompletionText(index)
  local live=WIT_GetQuestLogCompletionText(index)

  local questLogIndex=index
  if not questLogIndex and GetQuestLogSelection then
    questLogIndex=GetQuestLogSelection()
  end

  if not questLogIndex then return live end

  local _,_,_,_,isHeader,_,_,_,id=WIT_GetQuestLogTitle(questLogIndex)
  if isHeader or not id then return live end

  -- QuestTradutor's Objectives field is already the translated instruction
  -- for the quest.  For a completed tracked quest this is preferable to
  -- Blizzard's untranslated QuestCompletionLog line.
  return questObjectivesIT(id) or live
end


local WIT_GetQuestLogLeaderBoard=GetQuestLogLeaderBoard
function GetQuestLogLeaderBoard(objectiveIndex,questLogIndex)
  local live,objectiveType,finished=WIT_GetQuestLogLeaderBoard(objectiveIndex,questLogIndex)
  if not live then return live,objectiveType,finished end
  local _,_,_,_,header,_,_,_,questID=GetQuestLogTitle(questLogIndex)
  local objective=not header and objectiveLine(questID,objectiveIndex)
  return objective and liveObjective(objective.target or objective.text,live) or live,objectiveType,finished
end

-- Gossip APIs have no quest ID in 3.3.5a: use only unique canonical titles.
local function normal(s) return s and s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("^%s*%[.-%]%s*",""):gsub("^%s*",""):gsub("%s*$",""):lower() end
local function titleID(en) local t=WIT_QuestTitleIndex and WIT_QuestTitleIndex[normal(en)]; return t and #t==1 and t[1] end
local function gossipButton(b,en,trivial) local it=title(titleID(en)); if b and it then b:SetFormattedText(trivial and TRIVIAL_QUEST_DISPLAY or NORMAL_QUEST_DISPLAY,it) end end
function W:Gossip()
  local n=1; local a={GetGossipAvailableQuests()}; for i=1,#a,5 do gossipButton(_G["GossipTitleButton"..n],a[i],a[i+2]); n=n+1 end
  if #a>0 then n=n+1 end; a={GetGossipActiveQuests()}; for i=1,#a,4 do gossipButton(_G["GossipTitleButton"..n],a[i],a[i+2]); n=n+1 end
  set("GossipFrameGreetingGoodbyeButton","Arrivederci")
end
function W:Greeting()
  local n=GetNumActiveQuests(); for i=1,n do gossipButton(_G["QuestTitleButton"..i],GetActiveTitle(i),IsActiveQuestTrivial(i)) end
  for i=1,GetNumAvailableQuests() do local trivial=GetAvailableQuestInfo(i); gossipButton(_G["QuestTitleButton"..(n+i)],GetAvailableTitle(i),trivial) end
  set("QuestFrameGreetingGoodbyeButton","Arrivederci")
end

-- QuestLog_Update is the stock English writer for visible HybridScroll rows.
function W:QuestLog()
  if QuestLogScrollFrame and QuestLogScrollFrame.buttons then for _,b in ipairs(QuestLogScrollFrame.buttons) do
    local i=b:GetID(); local _,_,_,_,header,_,_,_,id=GetQuestLogTitle(i); local it=not header and title(id)
    if it then b:SetText("  "..it); QuestLogTitleButton_Resize(b) end
  end end
  set("QuestLogFrameAbandonButton","Abbandona"); set("QuestLogFramePushQuestButton","Condividi"); set("QuestLogFrameTrackButton","Traccia"); set("QuestLogFrameCancelButton","Chiudi"); set("QuestLogFrameShowMapButtonText","Mostra mappa")
end
function W:WatchNow()
  if not WATCHFRAME_QUESTLINES or not VISIBLE_WATCHES then return end
  -- WatchFrame_DisplayTrackedQuests has already applied filters, wrapping and
  -- available-height clipping, then records exactly the rendered log indexes
  -- in VISIBLE_WATCHES.  Walking that list keeps us aligned with its cached
  -- WatchFrameLine objects; walking GetNumQuestWatches did not.
  local line=1
  for _,index in ipairs(VISIBLE_WATCHES) do
    local en,_,_,_,header,_,complete,_,id=GetQuestLogTitle(index)
    if not id then id=titleID(en) end -- only accepts a unique canonical title
    if not header then
      local f=WATCHFRAME_QUESTLINES[line]
      if f and f.text and title(id) then f.text:SetText(title(id)) end
      line=line+1
      if complete then
        -- Blizzard renders one completion line after a completed title.
        line=line+1
      else
        for o=1,GetNumQuestLeaderBoards(index) do
          local live,_,done=GetQuestLogLeaderBoard(o,index)
          if not done then
            local x=WATCHFRAME_QUESTLINES[line]
            local objective=objectiveLine(id,o)
            if x and x.text and objective then x.text:SetText(liveObjective(objective.target or objective.text,live)) end
            line=line+1
          end
        end
        if GetQuestLogRequiredMoney and GetMoney and GetQuestLogRequiredMoney(index)>GetMoney() then line=line+1 end
      end
    end
  end
end
function W:Watch() self:Defer("watch") end
-- WorldMapFrame_UpdateQuests sets questId before this post-hook runs.
function W:WorldMapQuestsNow()
  for i=1,(WorldMapFrame and WorldMapFrame.numQuests or 0) do local f=_G["WorldMapQuestFrame"..i]; if f and f.questId then
    if title(f.questId) then f.title:SetText(title(f.questId)) end
    if not f.completed then
      -- The stock writer has just assembled the English objective text from
      -- Rebuild every visible leaderboard row by its original objective
      -- index; finished rows remain omitted just like FrameXML.  This is not
      -- the general Objectives paragraph and never freezes progress counters.
      local objectiveText,dashes="",""
      for o=1,GetNumQuestLeaderBoards(f.questLogIndex) do
        local live,_,finished=GetQuestLogLeaderBoard(o,f.questLogIndex)
        local objective=objectiveLine(f.questId,o)
        if live and not finished then
          objectiveText=objectiveText..liveObjective(objective and (objective.target or objective.text),live).."|n"
          local ref=WorldMapQuestFrameReference or f
          ref.objectives:SetText(live)
          local h=(ref.objectives:GetHeight()+(ref.lineSpacing or 0))/(ref.lineHeight or 1)
          dashes=dashes..QUEST_DASH..string.rep("|n",math.max(0,math.floor(h+0.5)-1))
        end
      end
      if objectiveText~="" then f.objectives:SetText(objectiveText); f.dashes:SetText(dashes) end
    else
      -- Completed quests use Blizzard's QuestCompletionLog instead of the
      -- normal leaderboard.  Our API wrapper above supplies Italian text.
      local completion=GetQuestLogCompletionText(f.questLogIndex)
      if completion and completion~="" then
        f.objectives:SetText(completion)
        f.dashes:SetText(QUEST_DASH)
      end
    end
    f:SetHeight(math.max(f.title:GetHeight()+f.objectives:GetHeight()+QUESTFRAME_PADDING,QUESTFRAME_MINHEIGHT))
  end end
end
function W:WorldMapQuests() self:Defer("map") end
function W:WorldMapUI()
  set("WorldMapZoomOutButton","Riduci"); set("WorldMapTrackQuestText","Traccia missione"); set("WorldMapQuestShowObjectivesText","Mostra obiettivi missione")
  regionText(WorldMapContinentDropDown,"Continent","Continente"); regionText(WorldMapZoneDropDown,"Zone","Zona")
  -- Unnamed FontString in WorldMapFrame.xml, not dropdown entry text.
  -- WorldMapFrame.xml uses BATTLEFIELD_MINIMAP, not the literal "Zone Map",
  -- and the FontString is unnamed.  This is the visible label in the test.
  regionText(WorldMapZoneMinimapDropDown,"Zone Map","Mappa della zona")
  regionText(WorldMapZoneMinimapDropDown,BATTLEFIELD_MINIMAP,"Mappa della zona")
  if WorldMapQuestShowObjectives_AdjustPosition then WorldMapQuestShowObjectives_AdjustPosition() end
end
function W:CoreUI()
  local menu={GameMenuButtonOptions="Video",GameMenuButtonSoundOptions="Audio",GameMenuButtonUIOptions="Interfaccia",GameMenuButtonKeybindings="Associazioni tasti",GameMenuButtonMacros="Macro",GameMenuButtonLogout="Disconnetti",GameMenuButtonQuit="Esci dal gioco",GameMenuButtonContinue="Torna al gioco"}; for n,t in pairs(menu) do set(n,t) end
  set("CharacterFrameTab1","Personaggio"); set("CharacterFrameTab3","Reputazione"); set("CharacterFrameTab4","Abilità"); set("QuestFrameGoodbyeButton","Annulla"); set("QuestFrameCompleteButton","Continua"); set("GossipFrameGreetingGoodbyeButton","Arrivederci")
  -- Unnamed FontString in GameMenuFrame.xml.
  regionText(GameMenuFrame,"Options","Opzioni")
  -- PaperDollFrame_SetLevel copied the old PLAYER_LEVEL before this addon.
  -- Race/class tokens deliberately remain DBC work, rather than fuzzy replace.
  if CharacterLevelText then CharacterLevelText:SetFormattedText(PLAYER_LEVEL,UnitLevel("player"),UnitRace("player"),UnitClass("player")) end
  if HonorLevelText then HonorLevelText:SetFormattedText(PLAYER_LEVEL,UnitLevel("player"),UnitRace("player"),UnitClass("player")) end
  for i=1,7 do local t=_G["ChatFrame"..i.."TabText"]; if t then if t:GetText()=="General" then t:SetText("Generale") elseif t:GetText()=="Combat Log" then t:SetText("Registro combattimento") end end end
end

-- Client-side display-only overlays for canonical IDs and exact fixed server
-- notices.  No protocol, channel name, hyperlink, or arbitrary server text is
-- changed.  Unknown/custom data intentionally passes through untouched.
local npcTitleByID = {
  [15285]="Istruttore dei ladri",
  [15291]="Mercante di stoffa e cuoio",
}
local frozenThrone = {
  ["Welcome to Frozen Throne!"]="Benvenuto su Frozen Throne!",
  ["Support the project at https://frozenthrone.cloud"]="Supporta il progetto su https://frozenthrone.cloud",
  ["Thank you for playing!"]="Grazie per aver giocato!",
  ["World Chat is enabled. Type /join world to join the channel."]="La chat mondiale è abilitata. Digita /join world per unirti al canale.",
}
local function plainChat(s) return s and s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","") end
local function chatOverlay(self,text,...)
  local translated=frozenThrone[plainChat(text)]
  if translated then return self:WIT_AddMessage(translated,...) end
  return self:WIT_AddMessage(text,...)
end
local function npcID(guid)
  -- 3.3.5a creature GUID: 0xF130 <server> <entry:4 hex> <spawn>.
  return guid and guid:match("^0xF130%x%x%x%x%x%x%x%x%x%x") and tonumber(guid:sub(9,12),16)
end
local function localizeTooltipTitle(tip)
  local _,unit=tip:GetUnit(); local id=unit and npcID(UnitGUID(unit)); local it=id and npcTitleByID[id]
  if not it then return end
  for i=1,tip:NumLines() do
    local line=_G[tip:GetName().."TextLeft"..i]
    if line and (line:GetText()=="Rogue Trainer" or line:GetText()=="Cloth & Leather Merchant") then line:SetText(it) end
  end
end
for i=1,7 do
  local cf=_G["ChatFrame"..i]
  if cf and not cf.WIT_AddMessage then cf.WIT_AddMessage=cf.AddMessage; cf.AddMessage=chatOverlay end
end
if GameTooltip then GameTooltip:HookScript("OnTooltipSetUnit",localizeTooltipTitle) end
-- StatFrameTemplate is 104px wide with a 30px right-aligned value field.
function W:CompactStat(statFrame,label)
  if not statFrame then return end
  local f=_G[statFrame:GetName().."Label"]; local value=_G[statFrame:GetName().."StatText"]
  if not f or not value then return end
  f:SetText(label)
  -- Restore the stock size before each checked render.  Only shrink when the
  -- measured label intrudes on the fixed numeric field; no geometry changes.
  if not f.WITFont then local font,size,flags=f:GetFont(); f.WITFont={font,size,flags} end
  local base=f.WITFont; f:SetFont(base[1],base[2],base[3])
  if f:GetLeft() and value:GetLeft() then
    local room=value:GetLeft()-f:GetLeft()-4
    local size=base[2]
    while room>0 and f:GetStringWidth()>room and size>10 do size=size-1; f:SetFont(base[1],size,base[3]) end
  end
end
function W:CompactStats() end -- exact post-writers below supply semantic labels.
function W:ApplyAll() self:CoreUI(); self:CompactStats(); self:QuestLog(); self:Watch(); self:WorldMapUI(); if GossipFrame and GossipFrame:IsShown() then self:Gossip() end; if QuestGreetingFrame and QuestGreetingFrame:IsShown() then self:Greeting() end; if WorldMapFrame and WorldMapFrame:IsShown() then self:WorldMapQuests() end end
W:RegisterEvent("PLAYER_LOGIN"); W:RegisterEvent("ADDON_LOADED"); W:RegisterEvent("QUEST_LOG_UPDATE"); W:RegisterEvent("QUEST_WATCH_UPDATE")
W:SetScript("OnEvent",function(self,event,addon) if event~="ADDON_LOADED" or addon=="Blizzard_WorldMap" then self:ApplyAll() end end)
hooksecurefunc("GossipFrameUpdate",function() W:Gossip() end); hooksecurefunc("QuestFrameGreetingPanel_OnShow",function() W:Greeting() end); hooksecurefunc("QuestLog_Update",function() W:QuestLog() end); hooksecurefunc("WatchFrame_DisplayTrackedQuests",function() W:Watch() end); hooksecurefunc("WorldMapFrame_UpdateQuests",function() W:WorldMapQuests() end); hooksecurefunc("WorldMapFrame_OnShow",function() W:Defer("ui"); W:WorldMapQuests() end)
hooksecurefunc("QuestFrameProgressPanel_OnShow",function() set("QuestFrameCompleteButton","Continua"); set("QuestFrameGoodbyeButton","Annulla"); W:Defer("ui") end)
-- These are the real 3.3.5a writers called by PaperDollFrame_UpdateStats;
-- UpdatePaperdollStats is not a 3.3.5a FrameXML function.
hooksecurefunc("PaperDollFrame_SetDamage",function(frame) W:CompactStat(frame,"Danno") end)
hooksecurefunc("PaperDollFrame_SetAttackSpeed",function(frame) W:CompactStat(frame,"Velocità") end)
hooksecurefunc("PaperDollFrame_SetRangedAttackSpeed",function(frame) W:CompactStat(frame,"Velocità") end)
hooksecurefunc("PaperDollFrame_SetAttackPower",function(frame) W:CompactStat(frame,"Potenza") end)
hooksecurefunc("PaperDollFrame_SetRangedAttackPower",function(frame) W:CompactStat(frame,"Potenza") end)
hooksecurefunc("PaperDollFrame_SetMeleeCritChance",function(frame) W:CompactStat(frame,"Critico") end)
hooksecurefunc("PaperDollFrame_SetRangedCritChance",function(frame) W:CompactStat(frame,"Critico") end)
hooksecurefunc("PaperDollFrame_SetSpellCritChance",function(frame) W:CompactStat(frame,"Critico") end)
hooksecurefunc("PaperDollFrame_SetExpertise",function(frame) W:CompactStat(frame,"Perizia") end)
hooksecurefunc("PaperDollFrame_SetRating",function(frame,rating)
  if rating==CR_HIT_MELEE or rating==CR_HIT_RANGED or rating==CR_HIT_SPELL then W:CompactStat(frame,"Indice colpo") end
end)
if GameMenuFrame then GameMenuFrame:HookScript("OnShow",function() W:CoreUI() end) end
if CharacterFrame then CharacterFrame:HookScript("OnShow",function() W:CoreUI() end) end
