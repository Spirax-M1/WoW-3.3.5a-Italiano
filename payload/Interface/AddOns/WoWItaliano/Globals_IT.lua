-- Generated core runtime overrides.  The master build appends validated UI and
-- binding records here; these navigation/quest labels are required at startup.
local G = {
  ACCEPT = "Accetta", ACCEPT_ALT = "Accetta", DECLINE = "Rifiuta",
  CONTINUE = "Continua", CANCEL = "Annulla", COMPLETE_QUEST = "Completa missione",
  GOODBYE = "Arrivederci", OBJECTIVES = "Obiettivi", QUEST_OBJECTIVES = "Obiettivi",
  CURRENT_QUESTS = "Missioni attuali", AVAILABLE_QUESTS = "Missioni disponibili",
  BINDING_HEADER_ACTIONBAR = "Funzioni barra delle azioni",
  BINDING_HEADER_CAMERA = "Funzioni fotocamera",
  BINDING_HEADER_CHAT = "Funzioni chat",
}
for key, value in pairs(G) do _G[key] = value end
