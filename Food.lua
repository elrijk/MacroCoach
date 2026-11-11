-------------------------------------------------------------------------------
--  MacroCoach - еда и питьё из сумок
--  В WoW Forever любая приготовленная еда даёт «Сытость» (бонус и +5% опыта
--  за убийства), и такой еды нет в списках макросов. Поэтому макросы со scan
--  («Еда», «Сытная еда», «Питьё») смотрят сумки сами: что за предмет (еда,
--  питьё или еда с «Сытостью»), видно по заклинанию предмета и по строке
--  «Использование:» в его подсказке. Слова «Сытости» - на всех языках клиента.
-------------------------------------------------------------------------------
local _, ns = ...

local Food = { retries = 0 }
ns.Food = Food

local FED_WORDS = { "well fed", "сыт", "Сыт", "насыщ", "Насыщ", "satt", "sättig", "wohlgenährt", "bien nourri", "rassasi",
    "bien alimentad", "saciad", "ben nutrit", "bem alimentad", "포만", "进食充分", "進食充分", "饱食", "飽食" }
-- «Пища» и «Питьё» хлеба и воды из продажи: их названия на языке клиента.
local FOOD_SPELLS, DRINK_SPELLS = { 433, 434, 435 }, { 430, 431, 432 }
local foodNames, drinkNames

local function SpellNames()
    if foodNames then return foodNames, drinkNames end
    local f, d = { Food = true, ["Пища"] = true }, { Drink = true, ["Питье"] = true, ["Питьё"] = true }
    local loaded = true
    for _, list in ipairs({ { FOOD_SPELLS, f }, { DRINK_SPELLS, d } }) do
        for _, id in ipairs(list[1]) do
            local name = C_Spell.GetSpellName(id)
            if name then list[2][name] = true else loaded = false end
        end
    end
    if loaded then foodNames, drinkNames = f, d end
    return f, d
end

local function ItemSpellName(id)
    local f = C_Item.GetItemSpell
    if not f then return nil end
    local ok, name = pcall(f, id)
    return ok and name or nil
end

-- Строки подсказки предмета (подсказка на экране не появляется).
local scanTip
local function TipLines(id)
    local out = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
        if ok and data and data.lines then
            for _, l in ipairs(data.lines) do
                local t = l.leftText
                if not t and l.args then
                    for _, a in ipairs(l.args) do
                        if a.field == "leftText" then t = a.stringVal end
                    end
                end
                if t then out[#out + 1] = t end
            end
        end
        return out
    end
    scanTip = scanTip or CreateFrame("GameTooltip", "MacroCoachScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetItemByID(id)
    for i = 2, scanTip:NumLines() or 0 do
        local fs = _G["MacroCoachScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then out[#out + 1] = t end
    end
    scanTip:Hide()
    return out
end

-- Что за предмет: "food", "drink", "fed" (еда с «Сытостью») или nil.
-- Второе значение - сотворён ли он магом, третье - данные уже загружены.
local facts = {}
function Food.Facts(id)
    local f = facts[id]
    if f then return f.kind or nil, f.conj, true end
    local inst = C_Item.GetItemInfoInstant
    local classID = inst and select(6, inst(id))
    if classID and classID ~= 0 then
        facts[id] = { kind = false }
        return nil, false, true
    end
    local spell = ItemSpellName(id)
    if not spell then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil, false, false
    end
    local food, drink = SpellNames()
    local kind = (food[spell] and "food") or (drink[spell] and "drink") or nil
    local lines = TipLines(id)
    if #lines == 0 then return kind, false, false end
    local use, conj = ITEM_SPELL_TRIGGER_ONUSE, false
    for _, t in ipairs(lines) do
        if ITEM_CONJURED and t == ITEM_CONJURED then conj = true end
        if kind ~= "drink" and kind ~= "fed" and (not use or t:find(use, 1, true)) then
            local low = t:lower()
            for _, w in ipairs(FED_WORDS) do
                if low:find(w, 1, true) then
                    kind = "fed"
                    break
                end
            end
        end
    end
    facts[id] = { kind = kind or false, conj = conj }
    return kind, conj, true
end

-- Подходит ли предмет макросу со scan (для «своего» текста макроса в игре).
function Food.Fits(scan, id)
    local kind = Food.Facts(id)
    return kind ~= nil and (kind == scan or (scan == "food" and kind == "fed"))
end

local function BagItems()
    local C = C_Container
    local slots = C.GetContainerNumSlots
    local itemAt = C.GetContainerItemID
    if not slots or not itemAt then return nil end
    local list, seen = {}, {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, slots(bag) or 0 do
            local id = itemAt(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                list[#list + 1] = id
            end
        end
    end
    return list
end

local function RankLess(a, b)
    for i = 1, #a do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end

-- Лучший подходящий предмет в сумках (меньше ранг - лучше): сотворённое
-- магом, потом выше уровнем. «Еда» бережёт еду с «Сытостью»: берёт её,
-- только если другой нет. nil - ничего нет, false - сумки не прочитать.
-- Food.incomplete - часть предметов ещё не загружена (проверить позже).
function Food.Best(m)
    local bag = BagItems()
    if not bag then return false end
    local level = UnitLevel("player") or 0
    local order, n = {}, 0
    for id in m.body:gmatch("item:(%d+)") do
        id = tonumber(id)
        if not order[id] then
            n = n + 1
            order[id] = n
        end
    end
    local pick, best
    for _, id in ipairs(bag) do
        local kind, conj, loaded = Food.Facts(id)
        if not loaded then
            Food.incomplete = true
            -- предмет из списка макроса: уже известно, что это
            if order[id] and not kind then kind = m.scan end
        end
        local minLevel = select(5, C_Item.GetItemInfo(id)) or 0
        local group
        if kind == m.scan then group = conj and 0 or 1
        elseif m.scan == "food" and kind == "fed" then group = 2 end
        if group and minLevel <= level then
            local rank = { group, -minLevel, order[id] or 999, id }
            if not best or RankLess(rank, best) then pick, best = id, rank end
        end
    end
    return pick
end
