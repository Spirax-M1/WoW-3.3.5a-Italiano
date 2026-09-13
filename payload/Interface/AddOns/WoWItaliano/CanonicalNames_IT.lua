-- Normalizzazione finale dei testi semantici WoWItaliano.
-- NON tocca il campo source inglese: serve ai lookup.

local function fix(s)
    if type(s) ~= "string" then return s end

    if QTR_CanonicalIT then
        return QTR_CanonicalIT(s)
    end

    return s
end

if WIT_QuestObjectiveLines then
    for _, quest in pairs(WIT_QuestObjectiveLines) do
        if type(quest) == "table" then
            for _, objective in pairs(quest) do
                if type(objective) == "table" then
                    if type(objective.target) == "string" then
                        objective.target = fix(objective.target)
                    end

                    if type(objective.text) == "string" then
                        objective.text = fix(objective.text)
                    end

                    -- objective.source NON va modificato.
                end
            end
        end
    end
end
