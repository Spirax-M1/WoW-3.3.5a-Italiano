-- WoW-IT canonical terminology layer.
-- Correzioni conservative supportate da terminologia Blizzard verificata.

local exact = {
    ["Icecrown"] = "Corona di Ghiaccio",
    ["Stormwind"] = "Roccavento",
    ["Sunstrider"] = "Solealto",
    ["Sunstriders"] = "Solealto",
}

-- Queste espressioni sono sufficientemente specifiche da poter comparire
-- anche all'interno di una frase completa.
local phrases = {
    { "Isola di Brumadoro",   "Isola di Solealto" },
    { "Isola dei Sunstrider", "Isola di Solealto" },
    { "Isola di Sunstrider",  "Isola di Solealto" },

    { "Sunstrider Isle",      "Isola di Solealto" },

    { "Foresta di Eversong",  "Boschi di Cantoeterno" },
    { "Eversong Woods",       "Boschi di Cantoeterno" },

    { "Goldenmist Village",   "Brumadoro" },
    { "Bloodmyst Isle",       "Isola Brumacremisi" },

    { "Brann Bronzebeard",    "Brann Barbabronzea" },
    { "Kael'thas Sunstrider", "Kael'thas Solealto" },
}

local function escapePattern(s)
    return (s:gsub(
        "([%(%)%.%%%+%-%*%?%[%]%^%$])",
        "%%%1"
    ))
end

function QTR_CanonicalIT(s)
    if type(s) ~= "string" or s == "" then
        return s
    end

    -- Solo stringa completa per nomi che sarebbero pericolosi
    -- come sostituzione parziale.
    local whole = exact[s]
    if whole then
        return whole
    end

    for _, p in ipairs(phrases) do
        s = s:gsub(
            escapePattern(p[1]),
            p[2]
        )
    end

    return s
end

if QTR_QuestData then
    for _, q in pairs(QTR_QuestData) do
        if type(q) == "table" then
            for k, v in pairs(q) do
                if type(v) == "string" then
                    q[k] = QTR_CanonicalIT(v)
                end
            end
        end
    end
end

if GS_Gossip then
    for k, v in pairs(GS_Gossip) do
        if type(v) == "string" then
            GS_Gossip[k] = QTR_CanonicalIT(v)
        end
    end
end

local function FixTitleTable(t)
    if not t then return end

    for _, row in pairs(t) do
        if type(row) == "table"
        and type(row.Title) == "string" then
            row.Title = QTR_CanonicalIT(row.Title)
        end
    end
end

FixTitleTable(WT_NPCs)
FixTitleTable(WT_QuestItemTemp)
