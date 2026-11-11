-------------------------------------------------------------------------------
--  MacroCoach - помощник (боковая вкладка «Помощник»)
--  Зачем макросы - онбординг: проблемы, которые решает макрос, с картинками
--      «до -> после» из значков заклинаний вашего класса.
--  Советы - 6-8 макросов для старта на класс и карточка «Зачем» к каждому.
--      Серые откроются, когда заклинание выучено у тренера.
--  Проверка - старые ранги на панелях (замена на высший), проверка макросов
--      в игре (опечатки, английские названия, невыученное, убранное в Forever)
--      и проверка ID в данных аддона.
--  Импорт/экспорт (вкладка «Свои макросы») - код для копирования: все свои
--      макросы и правки или один макрос, чтобы предложить его автору аддона.
--  Здесь же: перевод английских названий в ID (H.Translate, для редактора и
--  «Исправить»), безопасное лечение (H.SafeBody), объяснение макроса по
--  строкам (H.Explain), пометки-значки «Новичку / Продвинутый / PvP» и
--  подсказки в чат после похода к тренеру.
--  Окно и общие функции берутся из MacroCoach.lua через ns.UI.
-------------------------------------------------------------------------------
local ADDON, ns = ...
local T = ns.T
local D = ns.HelperData
local B = ns.Builder
local UI = ns.UI
local H = {}
ns.Helper = H

local GOLD, LIGHT, GREY = UI.GOLD, UI.LIGHT, UI.GREY
local CODE = { 0.65, 1, 0.65 }
local RED = "|cffff6060"
local GREEN = "|cff4dff4d"
local YELLOW = "|cffffd100"
local GREYC = "|cff9d9d9d"

local function Print(msg) UI.Print(msg) end

-------------------------------------------------------------------------------
--  Настройки помощника (MacroCoachDB.helper)
-------------------------------------------------------------------------------
-- showCode: текст макроса на карточках открыт сразу (иначе - по щелчку на «?»).
local DEFAULTS = { safeHeal = true, altSelf = false, learn = false, tips = true, showCode = false }

function H.Opt(key)
    local v = UI.DB().helper[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

-- Открытые и закрытые щелчком тексты макросов (до перезагрузки интерфейса).
local codeOpen = {}

function H.SetOpt(key, value)
    UI.DB().helper[key] = value
    if key == "showCode" then wipe(codeOpen) end
end

-- open: открыт без щелчка (свои макросы - их текст пишет сам игрок).
function H.CodeShown(key, open)
    if codeOpen[key] ~= nil then return codeOpen[key] end
    return (open or H.Opt("showCode")) and true or false
end

function H.ToggleCode(key, open)
    codeOpen[key] = not H.CodeShown(key, open)
end

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

-------------------------------------------------------------------------------
--  Разбор строки макроса
--  { cmd = "/cast", rest = "...", variants = { { lead, groups = {"@mouseover,help"}, arg } } }
--  Варианты - через «;», группы - квадратные скобки подряд перед аргументом.
-------------------------------------------------------------------------------
local NO_SPLIT = { ["/run"] = true, ["/script"] = true, ["/say"] = true, ["/s"] = true, ["/yell"] = true,
    ["/y"] = true, ["/p"] = true, ["/party"] = true, ["/ra"] = true, ["/raid"] = true, ["/rw"] = true,
    ["/e"] = true, ["/emote"] = true, ["/me"] = true, ["/g"] = true, ["/guild"] = true, ["/console"] = true }

local function ParseVariant(seg)
    local lead = seg:match("^(%s*)") or ""
    local s = seg:sub(#lead + 1)
    local groups = {}
    while true do
        local g, after = s:match("^(%b[])%s*(.*)$")
        if not g then break end
        groups[#groups + 1] = g:sub(2, -2)
        s = after
    end
    return { lead = lead, groups = groups, arg = strtrim(s) }
end

function H.ParseLine(line)
    local t = strtrim(line or "")
    local cmd, rest = t:match("^([/#]%S+)%s*(.*)$")
    if not cmd then return { cmd = "", rest = t, variants = {} } end
    local p = { cmd = cmd:lower(), rest = rest, variants = {} }
    if NO_SPLIT[p.cmd] then
        p.variants[1] = { lead = "", groups = {}, arg = rest }
        return p
    end
    for seg in (rest .. ";"):gmatch("(.-);") do p.variants[#p.variants + 1] = ParseVariant(seg) end
    return p
end

-- Аргумент /castsequence: «reset=...» и список через запятую.
local function SeqItems(arg)
    local reset, list = arg:match("^reset=(%S+)%s*(.*)$")
    if not reset then list = arg end
    local items = {}
    for item in (list .. ","):gmatch("(.-),") do
        item = strtrim(item)
        if item ~= "" then items[#items + 1] = item end
    end
    return items, reset
end

-------------------------------------------------------------------------------
--  Безопасное лечение
--  [@mouseover,help,nodead][] -> [@mouseover,help,nodead][help,nodead][@player]:
--  никого под курсором - лечит цель, только если это живой союзник, иначе вас.
--  Alt -> на себя: в начало ставится [mod:alt,@player].
--  Трогаем только /cast-варианты без модификаторов, где первая скобка -
--  живой союзник (help + nodead). Воскрешение ([help,dead]) не трогаем.
-------------------------------------------------------------------------------
local function HasToken(g, token)
    for t in g:gmatch("[^,]+") do
        if strtrim(t) == token then return true end
    end
    return false
end

local function HasMod(groups)
    for _, g in ipairs(groups) do
        for t in g:gmatch("[^,]+") do
            t = strtrim(t)
            if t:find("^no") then t = t:sub(3) end
            if t == "mod" or t:find("^mod:") or t == "modifier" or t:find("^modifier:") then return true end
        end
    end
    return false
end

function H.SafeBody(body, heal, alt)
    if not (heal or alt) or type(body) ~= "string" then return body end
    local out, changed = {}, false
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local p = H.ParseLine(line)
        if p.cmd == "/cast" and #p.variants > 0 then
            local parts, lineChanged = {}, false
            for _, v in ipairs(p.variants) do
                local g = v.groups
                local text
                if #g > 0 and v.arg:match("^{[sr]:%d+}$") and HasToken(g[1], "help") and HasToken(g[1], "nodead")
                    and not HasMod(g) then
                    local ng = {}
                    for i = 1, #g do ng[i] = g[i] end
                    -- Alt - только там, где запасной вариант и так вы или любая цель
                    -- (Божественное вмешательство на себя не применить).
                    local selfOk = ng[#ng] == "" or ng[#ng] == "@player"
                    if heal and ng[#ng] == "" then
                        ng[#ng] = "help,nodead"
                        ng[#ng + 1] = "@player"
                    end
                    if alt and selfOk then table.insert(ng, 1, "mod:alt,@player") end
                    text = v.lead .. "[" .. table.concat(ng, "][") .. "] " .. v.arg
                    if text ~= v.lead .. "[" .. table.concat(g, "][") .. "] " .. v.arg then lineChanged = true end
                end
                parts[#parts + 1] = text or (v.lead .. (#g > 0 and ("[" .. table.concat(g, "][") .. "] ") or "") .. v.arg)
            end
            if lineChanged then
                line = "/cast " .. table.concat(parts, ";")
                changed = true
            end
        end
        out[#out + 1] = line
    end
    if not changed then return body end
    return table.concat(out, "\n")
end

-- Текст готового макроса с учётом настроек (для Effective в MacroCoach.lua).
function ns.SafeBody(body)
    return H.SafeBody(body, H.Opt("safeHeal"), H.Opt("altSelf"))
end

-- Готовые макросы, уже созданные в игре, - под новые настройки. Трогаем
-- только те, что совпадают с одним из вариантов, созданных аддоном.
function H.ResyncReady()
    if InCombatLockdown() then
        UI.AfterCombat("resync", H.ResyncReady)
        return
    end
    local db, n = UI.DB(), 0
    for class, groups in pairs(ns.MACROS) do
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.list or {}) do
                if not db.edits[UI.Key(class, m)] and not m.best then
                    local em = UI.Effective(class, m)
                    local index = UI.FindMacro(em)
                    if index then
                        local name, icon, body = GetMacroInfo(index)
                        local want, missing = UI.Render(em.body)
                        local ours = false
                        for _, heal in ipairs({ false, true }) do
                            for _, alt in ipairs({ false, true }) do
                                if body == (UI.Render(H.SafeBody(m.body, heal, alt))) then ours = true end
                            end
                        end
                        if ours and not missing and want ~= body and UI.CharCount(want) <= UI.MAX_CHARS then
                            EditMacro(index, name, icon, want)
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    if n > 0 then Print((T("обновлено макросов в игре: %d.")):format(n)) end
end

-------------------------------------------------------------------------------
--  Объяснение макроса по строкам (знак «?» на карточке и режим «Учусь»)
--  Простыми словами: «Применяет «Волна исцеления» на того, кто под курсором
--  (если это живой союзник), иначе на себя». Стойки и облики - по именам.
-------------------------------------------------------------------------------
-- На кого (Применяет X ...), кого (Делает фокусом ...), у кого (та же цель, что у ...).
local UNIT_TEXT = {
    on = {
        mouseover = "на того, кто под курсором", target = "на текущую цель", focus = "на фокус", player = "на себя",
        targettarget = "на цель вашей цели", pet = "на питомца", pettarget = "на цель питомца",
        cursor = "в точку под курсором", focustarget = "на цель фокуса", mouseovertarget = "на цель того, кто под курсором",
        party1 = "на 1-го в группе", party2 = "на 2-го в группе", party3 = "на 3-го в группе", party4 = "на 4-го в группе",
        none = "без цели",
    },
    whom = {
        mouseover = "того, кто под курсором", target = "текущую цель", focus = "фокус", player = "себя",
        targettarget = "цель вашей цели", pet = "питомца", pettarget = "цель питомца", focustarget = "цель фокуса",
        mouseovertarget = "цель того, кто под курсором", party1 = "1-го в группе", party2 = "2-го в группе",
        party3 = "3-го в группе", party4 = "4-го в группе",
    },
    of = {
        mouseover = "того, кто под курсором", target = "текущей цели", focus = "фокуса", player = "вас", pet = "питомца",
        targettarget = "цели вашей цели", pettarget = "цели питомца", focustarget = "цели фокуса",
        mouseovertarget = "цели того, кто под курсором",
        party1 = "1-го в группе", party2 = "2-го в группе", party3 = "3-го в группе", party4 = "4-го в группе",
    },
}
local PLAIN_UNIT = { on = "на текущую цель", whom = "текущую цель", of = "текущей цели" }

-- Про кого условие: «это» (тот, на кого применяем), цель, фокус, под курсором, питомец.
local SUBJ = {
    it = { is = "это %s", dead = "он мёртв", nodead = "он жив", exists = "он есть", noexists = "его нет" },
    target = { is = "цель - %s", dead = "цель мертва", nodead = "цель жива", exists = "цель выбрана", noexists = "цели нет",
        noharm = "нет вражеской цели", nohelp = "нет дружественной цели" },
    focus = { is = "фокус - %s", dead = "фокус мёртв", nodead = "фокус жив", exists = "фокус есть", noexists = "фокуса нет" },
    mouseover = { is = "под курсором %s", dead = "под курсором мёртвый", nodead = "под курсором живой",
        exists = "под курсором кто-то есть", noexists = "под курсором никого" },
    pet = { is = "питомец - %s", dead = "питомец мёртв", nodead = "питомец жив", exists = "питомец есть", noexists = "питомца нет" },
}
local KIND = { help = "союзник", harm = "враг", nohelp = "не союзник", noharm = "не враг" }
local ALIVE = { help = { dead = "мёртвый союзник", nodead = "живой союзник" }, harm = { dead = "мёртвый враг", nodead = "живой враг" } }
local UNIT_CONDS = { help = 1, harm = 1, nohelp = 1, noharm = 1, dead = 1, nodead = 1, exists = 1, noexists = 1 }

-- Условия про вас и про кнопки.
local COND_TEXT = {
    combat = "в бою", nocombat = "вне боя", stealth = "в незаметности", nostealth = "не в незаметности",
    mounted = "верхом", nomounted = "не верхом", swimming = "в воде", noswimming = "не в воде",
    outdoors = "на улице", indoors = "в помещении", pet = "у вас есть питомец", nopet = "питомца нет",
    group = "в группе", nogroup = "не в группе", form = "вы в облике или стойке", noform = "вы без облика и стойки",
    stance = "вы в облике или стойке", nostance = "вы без облика и стойки",
    channeling = "идёт поддерживаемое заклинание", nochanneling = "нет поддерживаемого заклинания",
    mod = "зажат Shift, Ctrl или Alt", nomod = "Shift, Ctrl и Alt не зажаты", modifier = "зажат Shift, Ctrl или Alt",
    nomodifier = "Shift, Ctrl и Alt не зажаты", resting = "вы отдыхаете", noresting = "вы не отдыхаете",
    flying = "в полёте", noflying = "не в полёте",
}
local KEY_NAME = { shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local MARKER = { "Звезда", "Круг", "Ромб", "Треугольник", "Полумесяц", "Квадрат", "Крест", "Череп" }

-- Стойки и облики по номеру ([stance:1], [form:3]) - как их зовёт игра.
local STANCES = {
    WARRIOR = { 2457, 71, 2458 },             -- Боевая, Оборонительная, Берсерка
    DRUID = { 5487, 1066, 768, 783, 24858 },  -- Медведь, Водный, Кошка, Походный, Лунный совух
    PRIEST = { 15473 },                       -- Облик Тьмы
    ROGUE = { 1784 },                         -- Незаметность
    SHAMAN = { 2645 },                        -- Призрачный волк
}
local explainClass -- класс объясняемого макроса (для имён стоек)

local function Quote(s) return (T("«%s»")):format(s) end

-- «A», «A или B», «A, B или C».
local function JoinOr(list, word)
    word = word or T(" или ")
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. word .. list[#list]
end

-- Названия стоек по номерам; второе значение - был ли номер 0 («без облика»).
local function StanceNames(val)
    local list = STANCES[explainClass or select(2, UnitClass("player")) or ""]
    local names, zero = {}, false
    for n in tostring(val):gmatch("[^/]+") do
        if tonumber(n) == 0 then
            zero = true
        else
            local id = list and list[tonumber(n)]
            local name = id and C_Spell.GetSpellName(id)
            names[#names + 1] = name and Quote(name) or (T("облик %s")):format(n)
        end
    end
    return names, zero
end

-- Название заклинания: из игры, иначе английское из наших списков. Номер
-- заклинания игроку ни о чём не говорит - его не показываем.
local enByID
function H.SpellName(id)
    local n = id and C_Spell.GetSpellName(id)
    if n then return n end
    if not enByID then
        enByID = {}
        for _, list in pairs(D.EN_SPELLS or {}) do
            for name, sid in pairs(list) do enByID[sid] = enByID[sid] or name end
        end
    end
    return enByID[id] or T("заклинание")
end

-- Когда откроется заклинание, коротко: «26 ур.», «талант», «задание, 10 ур.»,
-- «20 ур., тотем воды». Уровень уже есть - «у учителя».
local TOTEM = { earth = "тотем земли", fire = "тотем огня", water = "тотем воды", air = "тотем воздуха" }
function H.LearnNote(id)
    local v = D.LEARN and D.LEARN[id]
    if not v then return nil end
    if v == "t" then return T("талант") end
    if v == "p" then return T("у питомца") end
    local lvl, kind = v, nil
    if type(v) == "table" then lvl, kind = v[1], v[2] end
    local reached = (UnitLevel("player") or 0) >= lvl
    if kind == "q" then
        return reached and T("задание у учителя") or (T("%d ур., задание")):format(lvl)
    elseif kind then
        return (reached and T("у учителя") or (T("%d ур.")):format(lvl)) .. ", " .. T(TOTEM[kind])
    end
    return reached and T("у учителя") or (T("%d ур.")):format(lvl)
end

local function TokenName(token)
    local bang = token:match("^!") ~= nil
    token = token:gsub("^!", "")
    local kind, id = token:match("^{([sr]):(%d+)}$")
    local name
    if kind then
        id = tonumber(id)
        name = H.SpellName(id)
        if kind == "r" then
            local r = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
            if r and r ~= "" then name = name .. " (" .. r .. ")" end
        end
        name = Quote(name)
    elseif token:match("^item:%d+$") then
        local iid = tonumber(token:match("%d+"))
        name = Quote((C_Item.GetItemNameByID and C_Item.GetItemNameByID(iid)) or tostring(iid))
    elseif token == "13" then
        name = T("верхний аксессуар")
    elseif token == "14" then
        name = T("нижний аксессуар")
    elseif token:match("^%d+$") then
        name = (T("предмет из ячейки %s")):format(token)
    elseif token:match("^%d+%s+%d+$") then
        local bag, slot = token:match("^(%d+)%s+(%d+)$")
        name = (T("предмет из сумки %s, ячейка %s")):format(bag, slot)
    else
        name = Quote(token)
    end
    if bang then name = name .. T(" (повторное нажатие не выключает)") end
    return name
end

-- Условие про вас или кнопки (не про цель).
local function CondText(token)
    if COND_TEXT[token] then return T(COND_TEXT[token]) end
    local neg = token:match("^no") and true or false
    local base = neg and token:sub(3) or token
    local key, val = base:match("^(%a+):(.+)$")
    if key == "mod" or key == "modifier" then
        local keys = {}
        for k in val:gmatch("[^/]+") do keys[#keys + 1] = KEY_NAME[k:lower()] or k end
        if neg and #keys > 1 then return (T("не зажаты ни %s")):format(table.concat(keys, T(", ни "))) end
        return (neg and T("%s не зажат") or T("зажат %s")):format(JoinOr(keys))
    elseif key == "form" or key == "stance" then
        -- «сейчас «Боевая стойка»» - без падежей, подходит к любому названию.
        local names, zero = StanceNames(val)
        local parts = {}
        if zero then parts[1] = neg and T("вы в облике или стойке") or T("вы без облика и стойки") end
        if #names > 0 then
            if neg then
                parts[#parts + 1] = #names > 1 and (T("сейчас ни %s")):format(table.concat(names, T(", ни ")))
                    or (T("сейчас не %s")):format(names[1])
            else
                parts[#parts + 1] = (T("сейчас %s")):format(JoinOr(names))
            end
        end
        return table.concat(parts, neg and T(" и ") or T(" или "))
    elseif key == "channeling" then
        local names = {}
        for s in val:gmatch("[^/]+") do names[#names + 1] = TokenName(s) end
        if neg and #names > 1 then return (T("не идёт ни %s")):format(table.concat(names, T(", ни "))) end
        return (neg and T("%s сейчас не идёт") or T("сейчас идёт %s")):format(JoinOr(names))
    elseif key == "btn" or key == "button" then
        if val == "2" then return T("нажали правой кнопкой мыши") end
        if val == "1" then return T("нажали левой кнопкой мыши") end
        return (T("нажали кнопкой мыши %s")):format(val)
    elseif key == "known" then
        return (neg and T("заклинание %s не выучено") or T("заклинание %s выучено")):format(TokenName(val))
    elseif key == "group" then
        local raid = val == "raid"
        if neg then return raid and T("не в рейде") or T("не в группе") end
        return raid and T("в рейде") or T("в группе")
    end
    return Quote(token)
end

-- Одна скобка [..]: на кого, условия про него, остальные условия.
local function ParseGroup(g)
    local r = { set = {}, conds = {} }
    for token in g:gmatch("[^,]+") do
        token = strtrim(token)
        local u = token:match("^@(.+)$") or token:match("^target=(.+)$")
        if u then
            r.unit = strtrim(u)
        elseif UNIT_CONDS[token] then
            r.set[token] = true
        elseif token ~= "" then
            r.conds[#r.conds + 1] = CondText(token)
        end
    end
    return r
end

-- «это живой союзник», «цель мертва», «под курсором враг».
local function UnitConds(set, subj)
    local S = SUBJ[subj] or SUBJ.it
    local out = {}
    local kind = (set.help and "help") or (set.harm and "harm") or (set.nohelp and "nohelp") or (set.noharm and "noharm")
    local life = (set.dead and "dead") or (set.nodead and "nodead")
    if kind and life and ALIVE[kind] then
        out[#out + 1] = (T(S.is)):format(T(ALIVE[kind][life]))
    else
        if kind then out[#out + 1] = S[kind] and T(S[kind]) or (T(S.is)):format(T(KIND[kind])) end
        if life then out[#out + 1] = T(S[life]) end
    end
    if set.exists and not kind and not life then out[#out + 1] = T(S.exists) end
    if set.noexists then out[#out + 1] = T(S.noexists) end
    return out
end

local function CondsOf(r, subj)
    local list = UnitConds(r.set, subj)
    for _, c in ipairs(r.conds) do list[#list + 1] = c end
    return #list > 0 and table.concat(list, T(" и ")) or nil
end

-- Скобки по порядку, срабатывает первая подходящая.
-- mode "on"/"whom"/"of": на кого (кого, у кого) + условия в скобках.
-- mode "cond": только условия («если ... или ...»); второе значение - true.
-- prep - предлог для «иначе ...» в mode "of": «у», «с».
local function GroupsText(groups, mode, prep)
    if #groups == 0 then return nil end
    local rs, anyUnit = {}, false
    for i, g in ipairs(groups) do
        rs[i] = ParseGroup(g)
        anyUnit = anyUnit or rs[i].unit ~= nil
    end
    if mode ~= "cond" and anyUnit then
        local parts = {}
        for i, r in ipairs(rs) do
            local where = r.unit and UNIT_TEXT[mode][r.unit]
            if where then
                where = T(where)
            elseif r.unit then
                where = mode == "on" and (T("на %s")):format(r.unit) or r.unit
            else
                where = T(PLAIN_UNIT[mode])
            end
            local c = CondsOf(r, "it")
            -- «...что у фокуса, иначе у текущей цели»: предлог повторяется.
            if prep and i > 1 then where = prep .. where end
            parts[i] = c and (where .. " (" .. T("если ") .. c .. ")") or where
        end
        return table.concat(parts, T(", иначе ")), false
    end
    local conds = {}
    for i, r in ipairs(rs) do
        local c = CondsOf(r, r.unit or "target")
        if not c then return nil end -- пустая скобка: срабатывает всегда
        conds[i] = c
    end
    return T("если ") .. JoinOr(conds), true
end

-- Кого/на кого из скобок; только условия - «текущую цель, если ...».
local function UnitOrPlain(groups, mode, prep)
    local g, isCond = GroupsText(groups, mode, prep)
    if not g then return T(PLAIN_UNIT[mode]) end
    if isCond then return T(PLAIN_UNIT[mode]) .. ", " .. g end
    return g
end

-- «X» + на кого или когда.
local function WithGroups(name, groups, mode)
    local g, isCond = GroupsText(groups, mode)
    if not g then return name end
    return name .. (isCond and ", " or " ") .. g
end

-- Варианты через «;»: сработает первый подходящий.
local function VariantsText(verb, p, mode, argFn)
    local out = {}
    for i, v in ipairs(p.variants) do
        local name = argFn and argFn(v.arg) or TokenName(v.arg)
        out[#out + 1] = (i == 1 and (verb .. " ") or "") .. WithGroups(name, v.groups, mode)
    end
    return table.concat(out, T("; иначе ")) .. "."
end

local function ResetText(reset)
    local parts = {}
    for r in reset:gmatch("[^/]+") do
        if r == "target" then
            parts[#parts + 1] = T("при смене цели")
        elseif r == "combat" then
            parts[#parts + 1] = T("после боя")
        elseif tonumber(r) then
            parts[#parts + 1] = (T("через %s сек. без нажатий этого макроса")):format(r)
        elseif KEY_NAME[r] then
            parts[#parts + 1] = (T("с зажатым %s")):format(KEY_NAME[r])
        else
            parts[#parts + 1] = r
        end
    end
    return JoinOr(parts)
end

-- Команды без заклинаний: что делают (и пояснение после условия).
local PLAIN = {
    ["/startattack"] = { "Включает автоатаку по цели", "Повторное нажатие её не выключает." },
    ["/stopattack"] = { "Выключает автоатаку", "Например, чтобы не разбудить цель под контролем." },
    ["/stopcasting"] = { "Обрывает ваше текущее заклинание", "Так следующее сработает сразу." },
    ["/dismount"] = { "Слезает с транспорта" },
    ["/cancelform"] = { "Снимает облик или стойку" },
    ["/clearfocus"] = { "Убирает фокус" },
    ["/cleartarget"] = { "Убирает цель" },
    ["/targetenemy"] = { "Выбирает ближайшего врага (как клавиша Tab)" },
    ["/targetfriend"] = { "Выбирает ближайшего союзника" },
    ["/targetlasttarget"] = { "Возвращает прошлую цель" },
    ["/petfollow"] = { "Питомец идёт за вами" },
    ["/petpassive"] = { "Питомец сам не нападает" },
    ["/petstay"] = { "Питомец стоит на месте" },
    ["/petdefensive"] = { "Питомец защищает вас" },
    ["/petaggressive"] = { "Питомец нападает на всех врагов рядом" },
    ["/readycheck"] = { "Запускает проверку готовности группы" },
    ["/reload"] = { "Перезагружает интерфейс" },
    ["/invite"] = { "Приглашает цель в группу" },
}
local CHAT = { ["/s"] = 1, ["/say"] = 1, ["/y"] = 1, ["/yell"] = 1, ["/p"] = 1, ["/party"] = 1, ["/ra"] = 1,
    ["/raid"] = 1, ["/rw"] = 1, ["/e"] = 1, ["/emote"] = 1, ["/me"] = 1, ["/g"] = 1, ["/guild"] = 1 }
-- Остальные команды конструктора: их описание из конструктора.
local CMD_KIND = {}
for _, k in ipairs(B and B.KINDS or {}) do
    if k.key and k.cmd and k.cmd ~= "" then CMD_KIND[k.cmd] = k end
end

-- Одна строка -> пояснение (nil - пустая строка).
function H.ExplainLine(line)
    local p = H.ParseLine(line)
    local cmd = p.cmd
    if cmd == "" then
        if p.rest == "" then return nil end
        return T("Это не команда: игра покажет её в чате как обычный текст.")
    end
    if cmd == "#showtooltip" or cmd == "#show" then
        if strtrim(p.rest) == "" then return T("На кнопке - значок того, что сработает.") end
        return VariantsText(T("На кнопке - значок"), p, "cond")
    end
    if cmd == "/cast" or cmd == "/use" then
        return VariantsText(cmd == "/cast" and T("Применяет") or T("Использует"), p, "on")
    end
    if cmd == "/castsequence" then
        local out = {}
        for i, v in ipairs(p.variants) do
            local items, reset = SeqItems(v.arg)
            local names = {}
            for _, it in ipairs(items) do names[#names + 1] = TokenName(it) end
            -- «По очереди на того, кто под курсором (...): «A», «B»».
            local head = i > 1 and T("Иначе по очереди") or T("По очереди, по одному за нажатие")
            local g, isCond = GroupsText(v.groups, "on")
            if g then head = head .. (isCond and ", " or " ") .. g end
            local t = head .. ": " .. table.concat(names, ", ")
            if reset then t = t .. ". " .. T("Начинает сначала ") .. ResetText(reset) end
            out[#out + 1] = t .. "."
        end
        return table.concat(out, " ")
    end
    if cmd == "/castrandom" or cmd == "/userandom" then
        local out = {}
        for i, v in ipairs(p.variants) do
            local names = {}
            for _, it in ipairs(SeqItems(v.arg or "")) do names[#names + 1] = TokenName(it) end
            local head = i > 1 and T("иначе одно случайное из")
                or (cmd == "/castrandom" and T("Применяет одно случайное из") or T("Использует одно случайное из"))
            local g, isCond = GroupsText(v.groups, "on")
            out[#out + 1] = head .. ": " .. table.concat(names, ", ") .. (g and ((isCond and ", " or " - ") .. g) or "")
        end
        return table.concat(out, "; ") .. "."
    end
    if cmd == "/focus" or cmd == "/target" or cmd == "/tar" then
        local verb = cmd == "/focus" and T("Делает фокусом") or T("Берёт в цель")
        local v = p.variants[1] or { groups = {}, arg = "" }
        local arg = strtrim(v.arg or "")
        if arg == "" then return verb .. " " .. UnitOrPlain(v.groups, "whom") .. "." end
        -- /focus [@focus,noexists] target: в скобках только условия, кого - после них
        local whom = UNIT_TEXT.whom[arg:lower()] and T(UNIT_TEXT.whom[arg:lower()]) or Quote(arg)
        return WithGroups(verb .. " " .. whom, v.groups, "cond") .. "."
    end
    if cmd == "/assist" then
        local v = p.variants[1] or { groups = {}, arg = "" }
        local arg = strtrim(v.arg or "")
        if arg ~= "" then
            local of = UNIT_TEXT.of[arg:lower()] and T(UNIT_TEXT.of[arg:lower()]) or Quote(arg)
            return WithGroups(T("Берёт ту же цель, что у ") .. of, v.groups, "cond") .. "."
        end
        return T("Берёт ту же цель, что у ") .. UnitOrPlain(v.groups, "of", T("у ")) .. "."
    end
    if cmd == "/targetmarker" or cmd == "/tm" then
        local v = p.variants[1]
        if #p.variants == 1 and strtrim(v.arg or "") == "0" then
            return T("Снимает метку с ") .. UnitOrPlain(v.groups, "of", T("с ")) .. "."
        end
        return VariantsText(T("Ставит метку"), p, "on", function(arg)
            local n = tonumber(strtrim(arg or ""))
            return Quote(n and MARKER[n] and T(MARKER[n]) or (arg or ""))
        end)
    end
    if cmd == "/petattack" then
        local v = p.variants[1] or { groups = {} }
        return T("Питомец атакует ") .. UnitOrPlain(v.groups, "whom") .. "."
    end
    if cmd == "/cancelaura" then return VariantsText(T("Снимает с вас"), p, "cond") end
    if cmd == "/equip" then return VariantsText(T("Надевает"), p, "cond") end
    if cmd == "/petautocasttoggle" or cmd == "/petautocaston" or cmd == "/petautocastoff" then
        local word = cmd == "/petautocaston" and T("Включает") or cmd == "/petautocastoff" and T("Выключает")
            or T("Включает или выключает")
        return VariantsText(word .. " " .. T("автоприменение у питомца:"), p, "cond")
    end
    if cmd == "/stopmacro" then
        local g = p.variants[1] and GroupsText(p.variants[1].groups, "cond")
        if not g then return T("Здесь макрос останавливается: строки ниже не выполняются.") end
        return (T("Если %s, строки ниже не выполняются.")):format((g:gsub("^" .. T("если "), "")))
    end
    if CHAT[cmd] then return (T("Пишет в чат: %s")):format(Quote(p.rest)) end
    if cmd == "/run" or cmd == "/script" then
        return T("Запускает скрипт (код на Lua). Заклинания и выбор цели из него не работают.")
    end
    if PLAIN[cmd] then
        local e = PLAIN[cmd]
        local v = p.variants[1]
        local g = v and GroupsText(v.groups, "cond")
        local text = T(e[1]) .. (g and (", " .. g) or "") .. "."
        if e[2] then text = text .. " " .. T(e[2]) end
        return text
    end
    local k = CMD_KIND[cmd]
    if k and k.desc then
        local v = p.variants[1]
        local text = T(k.desc)
        local g = v and GroupsText(v.groups, "cond")
        if g then text = text .. " " .. (T("Срабатывает, %s.")):format(g) end
        if v and strtrim(v.arg or "") ~= "" and k.arg ~= "text" and k.arg ~= "spell" then
            text = text .. " " .. (T("Аргумент: %s.")):format(strtrim(v.arg))
        end
        return text
    end
    return (T("Команда %s: игра выполнит её как есть.")):format(cmd)
end

-- «/use item:...» без условий -> ID предмета (несколько подряд объединяются).
local function ItemOnly(line)
    local p = H.ParseLine(line)
    local v = p.variants[1]
    if p.cmd ~= "/use" or #p.variants ~= 1 or #v.groups > 0 then return nil end
    local arg = strtrim(v.arg or "")
    return arg:match("^item:%d+$") and arg or nil
end

-- Макрос (текст с {s:ID}) -> { { code, text }, ... }. class - для имён стоек.
function H.ExplainList(body, class)
    explainClass = class ~= "GENERAL" and class ~= "CUSTOM" and class or nil
    local lines = {}
    for line in ((body or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = strtrim(line) end
    local list, i = {}, 1
    while i <= #lines do
        if ItemOnly(lines[i]) and ItemOnly(lines[i + 1] or "") then
            local names, j = {}, i
            while j <= #lines and ItemOnly(lines[j]) do
                names[#names + 1] = TokenName(ItemOnly(lines[j]))
                j = j + 1
            end
            local text = T("Использует первое, что найдётся в сумках: ") .. table.concat(names, ", ", 1, math.min(3, #names))
            if #names > 3 then text = text .. (T(" и ещё %d")):format(#names - 3) end
            list[#list + 1] = { code = lines[i] .. " …", text = text .. "." }
            i = j
        else
            local t = H.ExplainLine(lines[i])
            if t then list[#list + 1] = { code = lines[i], text = t } end
            i = i + 1
        end
    end
    explainClass = nil
    return list
end

-- Для FontString (режим «Учусь»): строка кода зелёным, под ней пояснение.
function H.ExplainText(body, class)
    local out = {}
    for i, e in ipairs(H.ExplainList(body, class)) do
        local code = UI.ToDisplay(e.code):gsub("|", "||")
        out[#out + 1] = ("|cff9de89d%d. %s|r\n%s"):format(i, code, e.text)
    end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
--  Заклинания персонажа: выученные, высший ранг по названию
-------------------------------------------------------------------------------
local function RankNum(sub)
    return type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
end

-- Обходит книгу заклинаний: fn(spellID, name, rankText).
local function ForEachBookSpell(fn)
    local SB = C_SpellBook
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for i = 1, SB.GetNumSpellBookSkillLines() or 0 do
            local line = SB.GetSpellBookSkillLineInfo(i)
            if line and line.itemIndexOffset and line.numSpellBookItems then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = SB.GetSpellBookItemInfo(slot, bank)
                    if info and info.spellID and (spellType == nil or info.itemType == spellType) then
                        fn(info.spellID, info.name, info.subName)
                    end
                end
            end
        end
        -- Способности питомца (охотник, чернокнижник).
        local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
        local numPet = pet and SB.HasPetSpells and SB.HasPetSpells()
        for slot = 1, (type(numPet) == "number" and numPet or 0) do
            local info = SB.GetSpellBookItemInfo(slot, pet)
            if info and info.spellID then fn(info.spellID, info.name, info.subName, true) end
        end
        return
    end
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        local book = BOOKTYPE_SPELL or "spell"
        for i = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(i)
            for slot = (offset or 0) + 1, (offset or 0) + (num or 0) do
                local kind, id = GetSpellBookItemInfo(slot, book)
                if kind == "SPELL" and id then
                    local name, rank = GetSpellBookItemName(slot, book)
                    fn(id, name, rank)
                end
            end
        end
    end
end

-- Снимок книги: byID[id] = true, byName[название] = { id, rank } (высший ранг),
-- own - только свои заклинания, без способностей питомца.
-- Снимок запоминается: книга меняется только по SPELLS_CHANGED (bookDirty).
-- Если какие-то названия ещё не загрузились - в следующий раз снимем заново.
local book, bookDirty = nil, true
local function ScanBook(force)
    if book and not bookDirty and not force then return book end
    local byID, byName, own, ranks = {}, {}, {}, {}
    local incomplete = false
    pcall(ForEachBookSpell, function(id, name, sub, isPet)
        byID[id] = true
        if not isPet then own[id] = true end
        name = name or C_Spell.GetSpellName(id)
        if not name then incomplete = true; return end
        local rank = RankNum(sub) or RankNum(C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id))
        if rank then
            ranks[name] = ranks[name] or {}
            ranks[name][rank] = id
        end
        local cur = byName[name]
        if not cur or (rank and (not cur.rank or rank > cur.rank)) then byName[name] = { id = id, rank = rank } end
    end)
    book = { byID = byID, byName = byName, own = own, ranks = ranks }
    bookDirty = incomplete
    return book
end
function H.BookChanged() bookDirty = true end

local function Book() return book or ScanBook() end
H.ScanBook = ScanBook

local function Known(id)
    local checks = { IsPlayerSpell, C_SpellBook and C_SpellBook.IsSpellKnown or nil, IsSpellKnown }
    for i = 1, 3 do
        local f = checks[i]
        if f then
            local ok, r = pcall(f, id)
            if ok and r then return true end
        end
    end
    -- Способность питомца.
    if IsSpellKnown then
        local ok, r = pcall(IsSpellKnown, id, true)
        if ok and r then return true end
    end
    local b = Book()
    if b.byID[id] then return true end
    -- Ранги: если выучен другой ранг того же заклинания - оно у вас есть.
    local name = C_Spell.GetSpellName(id)
    return name ~= nil and b.byName[name] ~= nil
end
H.Known = Known

-- Заклинание по названию на языке клиента (только из книги персонажа).
local function SpellByName(name)
    if C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.spellID then return info.spellID end
    end
    if GetSpellInfo then
        local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, name)
        if ok and id then return id end
    end
    local b = Book().byName[name]
    return b and b.id
end

local function ItemByName(name)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, id = pcall(C_Item.GetItemInfoInstant, name)
        if ok and id then return id end
    end
end

-------------------------------------------------------------------------------
--  Названия заклинаний: английские (словарь) и на языке клиента (по ID)
-------------------------------------------------------------------------------
local enLookup
local function EnglishLookup()
    if enLookup then return enLookup end
    enLookup = {}
    for class, list in pairs(D.EN_SPELLS) do
        local t = {}
        for name, id in pairs(list) do t[name:lower()] = id end
        enLookup[class] = t
    end
    return enLookup
end

local function EnglishID(name)
    local key = name:lower()
    local L = EnglishLookup()
    local class = PlayerClass()
    if L[class] and L[class][key] then return L[class][key] end
    if L.GENERAL[key] then return L.GENERAL[key] end
    for _, t in pairs(L) do
        if t[key] then return t[key] end
    end
end

-- Все ID, которые знает аддон: готовые макросы и словарь.
local function AllKnownIDs()
    local ids = {}
    for _, groups in pairs(ns.MACROS) do
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.list or {}) do
                for _, e in ipairs(UI.SpellIDs(m.body)) do ids[e.id] = true end
            end
        end
    end
    for _, list in pairs(D.EN_SPELLS) do
        for _, id in pairs(list) do ids[id] = true end
    end
    return ids
end

-- Название на языке клиента -> ID (для любых заклинаний, которые знает аддон).
-- Карта строится один раз; недогруженные ID запрашиваются один раз и
-- добавляются, когда игра их догрузит. На одно название - самый низкий ранг.
local localNames, pendingIDs, requested
local function AddLocal(id)
    local n = C_Spell.GetSpellName(id)
    if not n then return false end
    local cur = localNames[n]
    if cur then
        local r1 = RankNum(C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(cur)) or 0
        local r2 = RankNum(C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)) or 0
        if r2 < r1 then localNames[n] = id end
    else
        localNames[n] = id
    end
    return true
end
local function LocalNameID(name)
    if not localNames then
        localNames, pendingIDs, requested = {}, {}, {}
        for id in pairs(AllKnownIDs()) do
            if not AddLocal(id) then pendingIDs[id] = true end
        end
    end
    for id in pairs(pendingIDs) do
        if AddLocal(id) then
            pendingIDs[id] = nil
        elseif not requested[id] then
            requested[id] = true
            if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
        end
    end
    return localNames[name]
end

local function RemovedNote(name)
    local low = name:lower()
    for _, r in ipairs(D.REMOVED) do
        for _, n in ipairs(r.names) do
            if n == name or n:lower() == low then return ns.Pick(r) end
        end
    end
end

-------------------------------------------------------------------------------
--  Переводчик: английские названия -> {s:ID}
-------------------------------------------------------------------------------
local NAME_CMDS = { ["/cast"] = true, ["/castsequence"] = true, ["/castrandom"] = true, ["/use"] = true,
    ["/userandom"] = true, ["/cancelaura"] = true, ["#showtooltip"] = true, ["#show"] = true,
    ["/petautocaston"] = true, ["/petautocastoff"] = true, ["/petautocasttoggle"] = true }
local LIST_CMDS = { ["/castsequence"] = true, ["/castrandom"] = true, ["/userandom"] = true }

local function TranslateName(raw, res)
    local sp, body, tail = raw:match("^(%s*)(.-)(%s*)$")
    if body == "" then return raw end
    local bang = ""
    if body:sub(1, 1) == "!" then bang, body = "!", body:sub(2) end
    if body:match("^{[sr]:%d+}$") or body:match("^item:%d+$") or body:match("^%d+$") or body:match("^%d+%s+%d+$") then
        return raw
    end
    -- Сначала целиком («Faerie Fire (Feral)»), потом без ранга в скобках.
    local function Find(n) return EnglishID(n) or LocalNameID(n), SpellByName(n) end
    local name, rankNum = body, nil
    local id, bookID = Find(name)
    if not (id or bookID) then
        local base, rank = body:match("^(.-)%s*%((.-)%)$")
        if base and base ~= "" then
            name, rankNum = base, tonumber(rank:match("%d+"))
            id, bookID = Find(name)
        end
    end
    id = id or bookID
    if not id then
        if not ItemByName(name) then res.unknown[#res.unknown + 1] = name end
        return raw
    end
    res.count = res.count + 1
    local token = "{s:" .. id .. "}"
    if rankNum then
        -- Точный ранг: из книги заклинаний, иначе 1-й ранг из словаря.
        local local_ = C_Spell.GetSpellName(id)
        local exact = local_ and Book().ranks[local_] and Book().ranks[local_][rankNum]
        if exact then
            token = "{r:" .. exact .. "}"
        elseif rankNum == 1 and id ~= bookID then
            token = "{r:" .. id .. "}"
        elseif EnglishID(name) and name ~= local_ then
            -- Английское название без точного ранга: высший, иначе макрос не заработает.
            res.notes[#res.notes + 1] = (T("«%s»: ранг %d заменён на высший выученный.")):format(name, rankNum)
        else
            -- Название на языке клиента: оставить как написано, ранг не терять.
            res.count = res.count - 1
            return raw
        end
    end
    return sp .. bang .. token .. tail
end

local function TranslateLine(line, res)
    local p = H.ParseLine(line)
    if not NAME_CMDS[p.cmd] then return line end
    local cmdText = strtrim(line):match("^(%S+)")
    if strtrim(p.rest) == "" then return strtrim(line) end
    local parts = {}
    for _, v in ipairs(p.variants) do
        local arg = v.arg
        local reset
        if LIST_CMDS[p.cmd] then
            reset, arg = arg:match("^(reset=%S+)%s*(.*)$")
            if not reset then arg = v.arg end
            local items = {}
            for item in (arg .. ","):gmatch("(.-),") do items[#items + 1] = TranslateName(item, res) end
            arg = table.concat(items, ",")
        else
            arg = TranslateName(arg, res)
        end
        local head = #v.groups > 0 and ("[" .. table.concat(v.groups, "][") .. "]") or ""
        local tail = (reset and (reset .. " ") or "") .. arg
        parts[#parts + 1] = v.lead .. head .. ((head ~= "" and tail ~= "") and " " or "") .. tail
    end
    return cmdText .. " " .. table.concat(parts, ";")
end

-- Текст -> { text (с {s:ID}), count, unknown = {...}, notes = {...} }
function H.Translate(text)
    local res = { count = 0, unknown = {}, notes = {} }
    local out = {}
    for line in ((text or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = TranslateLine(line, res)
    end
    while #out > 0 and strtrim(out[#out]) == "" do out[#out] = nil end
    res.text = table.concat(out, "\n")
    return res
end

-------------------------------------------------------------------------------
--  Проверка макросов в игре
-------------------------------------------------------------------------------
local CHECK_CMDS = { ["/cast"] = true, ["/castsequence"] = true, ["/castrandom"] = true,
    ["#showtooltip"] = true, ["#show"] = true }
-- В #showtooltip могут быть предметы по названию, их не проверить:
-- там ищем только английские названия.
local SHOW_CMDS = { ["#showtooltip"] = true, ["#show"] = true }

-- Названия заклинаний в строке (без рангов, «!» и скобок условий).
local function SpellNames(p)
    local names = {}
    for _, v in ipairs(p.variants) do
        local items = LIST_CMDS[p.cmd] and (SeqItems(v.arg)) or { v.arg }
        for _, it in ipairs(items) do
            it = strtrim(it):gsub("^!", "")
            it = it:gsub("%s*%(.-%)$", "")
            if it ~= "" and not it:match("^item:%d+$") and not it:match("^%d+$") and not it:match("^%d+%s+%d+$") then
                names[#names + 1] = it
            end
        end
    end
    return names
end

-- Что не так с текстом макроса: { { kind, text } }, english.
function H.CheckBody(body)
    local issues, english, seen = {}, false, {}
    if strtrim(body or "") == "" then
        issues[1] = { kind = "empty", text = T("Пустой макрос: кнопка ничего не делает.") }
        return issues, false
    end
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local p = H.ParseLine(line)
        if CHECK_CMDS[p.cmd] then
            for _, name in ipairs(SpellNames(p)) do
                if not seen[name] and not (SHOW_CMDS[p.cmd] and not EnglishID(name)) then
                    seen[name] = true
                    local id = SpellByName(name)
                    local removed = RemovedNote(name)
                    if removed then
                        issues[#issues + 1] = { kind = "removed", text = Quote(name) .. ": " .. removed }
                    elseif id then
                        -- Не выучено - не ошибка (общие макросы видны всем персонажам).
                    elseif not ItemByName(name) then
                        local enID = EnglishID(name)
                        local localID = LocalNameID(name)
                        local client = GetLocale and GetLocale() or "enUS"
                        if localID then
                            -- Настоящее заклинание: не выучено или другого класса - не ошибка.
                        elseif enID and client ~= "enUS" and client ~= "enGB" then
                            english = true
                            local loc = C_Spell.GetSpellName(enID)
                            issues[#issues + 1] = { kind = "english", text = (T("%s записано по-английски, клиент такое не поймёт. На языке клиента: %s.")):format(Quote(name), Quote(loc or "?")) }
                        else
                            issues[#issues + 1] = { kind = "unknown", text = (T("%s: такого заклинания нет у персонажа. Опечатка, другой язык или его нет в WoW Forever.")):format(Quote(name)) }
                        end
                    end
                end
            end
        end
    end
    return issues, english
end

function H.CheckGameMacros()
    ScanBook()
    local list = {}
    local general, char = GetNumMacros()
    local base = MAX_ACCOUNT_MACROS or 120
    local indexes = {}
    for i = 1, general or 0 do indexes[#indexes + 1] = i end
    for i = base + 1, base + (char or 0) do indexes[#indexes + 1] = i end
    for _, index in ipairs(indexes) do
        local name, icon, body = GetMacroInfo(index)
        if name then
            local issues, english = H.CheckBody(body or "")
            if #issues > 0 then
                list[#list + 1] = { index = index, name = name, icon = icon, body = body or "", issues = issues, english = english }
            end
        end
    end
    return list, #indexes
end

-- Номер макроса мог устареть (макросы удаляли и добавляли): ищем по названию.
local function MacroIndex(index, name)
    if not name then return index end
    if GetMacroInfo(index) == name then return index end
    local i = GetMacroIndexByName(name)
    return (i and i > 0) and i or nil
end

-- Удалить макрос из окна /macro (страница «Проверка»).
function H.DeleteGameMacro(index, onDone, expect)
    if InCombatLockdown() then
        Print(T("в бою макросы менять нельзя."))
        return
    end
    index = MacroIndex(index, expect)
    if not index then return end
    local name = GetMacroInfo(index)
    if not name then return end
    DeleteMacro(index)
    Print((T("макрос «%s» удалён."))
        :format(name))
    if onDone then onDone() end
end

-- Английские названия в макросе игры -> названия клиента (EditMacro на месте).
function H.FixGameMacro(index, onDone, expect)
    if InCombatLockdown() then
        UI.AfterCombat("fix:" .. index, function() H.FixGameMacro(index, onDone, expect) end)
        Print(T("в бою макросы менять нельзя: макрос будет исправлен сразу после боя."))
        return
    end
    index = MacroIndex(index, expect)
    if not index then return end
    local name, icon, body = GetMacroInfo(index)
    if not name then return end
    local res = H.Translate(body or "")
    local text, missing = UI.Render(res.text)
    if missing then
        UI.RequestSpells(res.text)
        Print(T("не все заклинания загружены, попробуйте ещё раз через пару секунд."))
        return
    end
    if UI.CharCount(text) > UI.MAX_CHARS then
        Print(T("после перевода макрос длиннее 255 символов: сократите его в /macro."))
        return
    end
    EditMacro(index, name, icon, text)
    Print((T("макрос «%s» исправлен: названий переведено - %d.")):format(name, res.count))
    if #res.unknown > 0 then Print(T("не найдено, поправьте вручную: ") .. table.concat(res.unknown, ", ")) end
    for _, n in ipairs(res.notes) do Print(n) end
    if onDone then onDone() end
end

-- Проверка данных аддона: все ли ID есть в клиенте (после патча).
function H.CheckData(done)
    local ids = AllKnownIDs()
    for id in pairs(ids) do
        if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
    end
    C_Timer.After(1.5, function()
        local missing, total = {}, 0
        for id in pairs(ids) do
            total = total + 1
            if not C_Spell.GetSpellName(id) then missing[#missing + 1] = id end
        end
        table.sort(missing)
        -- Где используется: класс и макрос.
        local where = {}
        for class, groups in pairs(ns.MACROS) do
            for _, g in ipairs(groups) do
                for _, m in ipairs(g.list or {}) do
                    for _, e in ipairs(UI.SpellIDs(m.body)) do
                        where[e.id] = where[e.id] or (class .. "/" .. m.name)
                    end
                end
            end
        end
        done(missing, total, where)
    end)
end

-- /coach данные: результат в чат.
function H.PrintDataCheck()
    Print(T("проверка ID заклинаний в данных аддона..."))
    H.CheckData(function(missing, total, where)
        if #missing == 0 then
            Print((T("все %d заклинаний найдены в клиенте.")):format(total))
            return
        end
        Print((T("не найдено в клиенте: %d из %d.")):format(#missing, total))
        for i, id in ipairs(missing) do
            if i > 30 then
                Print((T("и ещё %d")):format(#missing - 30))
                break
            end
            Print("  " .. id .. (where[id] and (" - " .. where[id]) or ""))
        end
    end)
end

-------------------------------------------------------------------------------
--  Старые ранги на панелях
-------------------------------------------------------------------------------
local MAX_ACTION_SLOT = 180

-- Кнопки, где низкий ранг стоит нарочно: keep[кнопка] = ID заклинания.
local function KeptRanks()
    local h = UI.DB().helper
    h.keep = h.keep or {}
    local key = CharKey()
    h.keep[key] = h.keep[key] or {}
    return h.keep[key]
end

function H.KeepRank(e) KeptRanks()[e.slot] = e.id end
function H.KeepAll(list) for _, e in ipairs(list) do H.KeepRank(e) end end

function H.KeptCount()
    local n = 0
    for _ in pairs(KeptRanks()) do n = n + 1 end
    return n
end
function H.ClearKept() wipe(KeptRanks()) end

function H.OldRanks()
    local b = ScanBook()
    local keep = KeptRanks()
    local list = {}
    -- Высший ранг уже есть на панелях - низкий стоит рядом нарочно (лечение ради маны).
    local onBars = {}
    for slot = 1, MAX_ACTION_SLOT do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then onBars[id] = true end
    end
    for slot = 1, MAX_ACTION_SLOT do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id and keep[slot] ~= id then
            local name = C_Spell.GetSpellName(id)
            local best = name and b.byName[name]
            if best and best.id ~= id and best.rank and not onBars[best.id] then
                local rank = RankNum(C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id))
                if rank and rank < best.rank then
                    list[#list + 1] = { slot = slot, id = id, best = best.id, name = name, rank = rank, bestRank = best.rank }
                end
            end
        end
    end
    return list
end

local function PlaceSpell(slot, spellID)
    local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
    if not (pick and PlaceAction) then return false end
    ClearCursor()
    local ok = pcall(pick, spellID)
    if not ok or not GetCursorInfo() then
        ClearCursor()
        return false
    end
    ok = pcall(PlaceAction, slot)
    ClearCursor()
    return ok
end

-- Заменить старые ранги (list - из OldRanks, nil - все). Возвращает число.
function H.FixRanks(list, onDone)
    if InCombatLockdown() then
        UI.AfterCombat("ranks", function() H.FixRanks(list, onDone) end)
        Print(T("в бою панели менять нельзя: ранги будут обновлены сразу после боя."))
        return
    end
    list = list or H.OldRanks()
    local n, undo = 0, {}
    for _, e in ipairs(list) do
        local kind, id = GetActionInfo(e.slot)
        if kind == "spell" and id == e.id and PlaceSpell(e.slot, e.best) then
            n = n + 1
            undo[#undo + 1] = { slot = e.slot, id = e.id, best = e.best }
        end
    end
    if n > 0 then H.lastFix = undo end
    if n > 0 then
        Print((T("обновлено заклинаний на панелях: %d. Теперь там высшие ранги.")):format(n))
    elseif #list > 0 then
        Print(T("не получилось заменить ранги: перетащите заклинания из книги заклинаний вручную."))
    end
    ScanBook(true)
    if onDone then onDone(n) end
end

-- Вернуть ранги, заменённые последним обновлением.
function H.UndoRanks(onDone)
    if InCombatLockdown() or not H.lastFix then return end
    local n = 0
    for _, e in ipairs(H.lastFix) do
        local kind, id = GetActionInfo(e.slot)
        if kind == "spell" and id == e.best and PlaceSpell(e.slot, e.id) then n = n + 1 end
    end
    H.lastFix = nil
    Print((T("возвращено как было: %d.")):format(n))
    ScanBook(true)
    if onDone then onDone() end
end

-------------------------------------------------------------------------------
--  Советы для старта
-------------------------------------------------------------------------------
local function FindReady(class, name)
    for _, g in ipairs(ns.MACROS[class] or {}) do
        for _, m in ipairs(g.list or {}) do
            if m.name == name then return m end
        end
    end
end

-- Советы класса: { tip, class, m, why = { problem, what, when } }
function H.Tips(class)
    local list = {}
    for _, tip in ipairs(D.TIPS[class] or {}) do
        local refClass, name = tip.ref:match("^(%u+)/(.+)$")
        if not refClass then refClass, name = class, tip.ref end
        local m = FindReady(refClass, name)
        if m then
            local why = refClass == "GENERAL" and D.GENERAL_TIPS[name] or tip
            local t = why and ns.Pick(why)
            list[#list + 1] = { tip = tip, class = refClass, m = m, why = t }
        end
    end
    return list
end

local function ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id)
    return ok and n or 0
end

-- Пометки готовых макросов: «Новичку» - все из советов, «Продвинутый» и
-- «PvP» - из списков в HelperData.lua.
local tagIndex
local function Tags()
    if tagIndex then return tagIndex end
    tagIndex = {}
    local function Add(key, tag)
        tagIndex[key] = tagIndex[key] or {}
        tagIndex[key][tag] = true
    end
    for class, list in pairs(D.TIPS) do
        for _, tip in ipairs(list) do
            local refClass, name = tip.ref:match("^(%u+)/(.+)$")
            Add(refClass and (refClass .. "/" .. name) or (class .. "/" .. tip.ref), "new")
        end
    end
    for class, t in pairs(D.TAGS) do
        for _, name in ipairs(t.adv or {}) do Add(class .. "/" .. name, "adv") end
        for _, name in ipairs(t.pvp or {}) do Add(class .. "/" .. name, "pvp") end
    end
    return tagIndex
end

-- Пометки - маленькие значки после названия, при наведении - что значат.
-- «Новичку» значком не показываем: такие макросы и так во вкладке
-- «Рекомендации». PvP - знак фракции, как в окне персонажа.
local TAG_DEF = {
    { key = "adv", icon = "Interface\\Icons\\INV_Misc_Gear_01", name = "Продвинутый",
      text = "Для тех, кто уже освоился: больше условий и клавиш." },
    { key = "pvp", pvp = true, name = "PvP", text = "Пригодится в бою с другими игроками." },
}
-- Значок PvP: знак своей фракции (верхний левый угол файла игры).
local function PvPIcon()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Alliance" or f == "Horde" then return "Interface\\TargetingFrame\\UI-PVP-" .. f, { 0, 0.62, 0, 0.62 } end
    return "Interface\\Icons\\INV_Jewelry_TrinketPVP_01", nil
end
H.NEWBIE_ICON = "Interface\\Icons\\INV_Misc_Flower_02"
local TAG_SIZE = 18

-- Значки пометок для карточки: holder:Set(class, m, titleFontString) -> ширина.
function H.TagIcons(parent)
    local holder = { icons = {} }
    for i = 1, #TAG_DEF do
        local b = CreateFrame("Frame", nil, parent)
        b:SetSize(TAG_SIZE, TAG_SIZE)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(T(self.def.name))
            GameTooltip:AddLine(T(self.def.text), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        holder.icons[i] = b
    end
    -- Сколько места займут значки (чтобы сузить название).
    function holder:Width(class, m)
        local t = Tags()[class .. "/" .. m.name]
        local n = 0
        for _, d in ipairs(TAG_DEF) do if t and t[d.key] then n = n + 1 end end
        return n > 0 and (6 + n * (TAG_SIZE + 3)) or 0
    end
    -- Ставит значки сразу после текста названия (первая строка).
    function holder:Set(class, m, title)
        local t = Tags()[class .. "/" .. m.name]
        local x = math.min(title:GetStringWidth() or 0, title:GetWidth() or 0) + 6
        local n = 0
        for _, b in ipairs(self.icons) do b:Hide() end
        for _, d in ipairs(TAG_DEF) do
            if t and t[d.key] then
                n = n + 1
                local b = self.icons[n]
                b.def = d
                local icon, coords = d.icon, nil
                if d.pvp then icon, coords = PvPIcon() end
                b.tex:SetTexture(icon)
                local c = coords or { 0.08, 0.92, 0.08, 0.92 }
                b.tex:SetTexCoord(c[1], c[2], c[3], c[4])
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", title, "TOPLEFT", x + (n - 1) * (TAG_SIZE + 3), 0)
                b:Show()
            end
        end
    end
    return holder
end

-- Вкладка «Рекомендации»: макросы из советов класса (с общими - у них класс
-- GENERAL в m.homeClass), у «Для всех классов» - общие с пометкой «Новичку».
function H.Recommended(class)
    local list = {}
    if D.TIPS[class] then
        for _, e in ipairs(H.Tips(class)) do
            if e.class ~= class then e.m.homeClass = e.class end
            list[#list + 1] = e.m
        end
        return list
    end
    for _, g in ipairs(ns.MACROS[class] or {}) do
        for _, m in ipairs(g.list or {}) do
            local t = Tags()[class .. "/" .. m.name]
            if t and t.new then list[#list + 1] = m end
        end
    end
    return list
end

-- Зачем макрос: { проблема, что делает, когда жать } на языке клиента или nil.
local whyIndex
function H.Why(class, m)
    if class == "GENERAL" then
        local g = D.GENERAL_TIPS[m.name]
        return g and ns.Pick(g)
    end
    if not whyIndex then
        whyIndex = {}
        for c, list in pairs(D.TIPS) do
            for _, tip in ipairs(list) do
                if not tip.ref:find("/", 1, true) then whyIndex[c .. "/" .. tip.ref] = tip end
            end
        end
    end
    local tip = whyIndex[class .. "/" .. m.name]
    return tip and ns.Pick(tip)
end

-------------------------------------------------------------------------------
--  Картинка «Было -> Макрос» для карточки: какие кнопки заменяет макрос.
--  Заклинания и предметы из текста, плюс действия: выбрать цель, автоатака,
--  оборвать своё заклинание. Макрос по наведению или на фокус: «выбрать цель,
--  применить, вернуть цель» - три нажатия вместо одного.
-------------------------------------------------------------------------------
local ACT = {
    target = { icon = "Interface\\Icons\\Ability_Hunter_SniperShot", tip = "Выбрать цель" },
    attack = { icon = "Interface\\Icons\\INV_Sword_04", tip = "Автоатака" },
    stop = { icon = "Interface\\Icons\\Spell_Nature_Lightning", tip = "Ваше текущее заклинание" },
    mount = { icon = "Interface\\Icons\\Ability_Mount_RidingHorse", tip = "Слезть с транспорта" },
    mark = { icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", tip = "Метка на цель" },
    pet = { icon = "Interface\\Icons\\Ability_Physical_Taunt", tip = "Команда питомцу" },
    form = { icon = "Interface\\Icons\\Ability_Druid_CatForm", tip = "Снять облик" },
    clear = { icon = "Interface\\Icons\\Ability_Hunter_SniperShot", tip = "Сбросить цель" },
}
local ACT_CMDS = { ["/targetenemy"] = "target", ["/target"] = "target", ["/tar"] = "target", ["/assist"] = "target",
    ["/focus"] = "target", ["/cleartarget"] = "clear", ["/startattack"] = "attack", ["/stopcasting"] = "stop",
    ["/dismount"] = "mount", ["/tm"] = "mark", ["/targetmarker"] = "mark", ["/petattack"] = "pet",
    ["/cancelform"] = "form" }
local ART_MAX = 3

-- Текст макроса -> до трёх «было»: { act = "target" } / { spell = ID } /
-- { item = ID } / { slot = 13 }. Меньше двух - картинки «было» нет.
function H.ArtList(body)
    local list, seen, items, spells = {}, {}, {}, 0
    local switch = false
    local function Add(key, e)
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = e
    end
    for line in ((body or "") .. "\n"):gmatch("(.-)\n") do
        local p = H.ParseLine(line)
        if p.cmd:sub(1, 1) == "/" then
            if line:find("@mouseover", 1, true) or line:find("@focus", 1, true) then switch = true end
            if ACT_CMDS[p.cmd] then Add("act:" .. ACT_CMDS[p.cmd], { act = ACT_CMDS[p.cmd] }) end
            for id in line:gmatch("{[sr]:(%d+)}") do
                spells = spells + 1
                Add("s" .. id, { spell = tonumber(id) })
            end
            for id in line:gmatch("item:(%d+)") do
                items[#items + 1] = tonumber(id)
                Add("i" .. id, { item = tonumber(id) })
            end
            if p.cmd == "/use" then
                for _, v in ipairs(p.variants) do
                    local n = tonumber(strtrim(v.arg or ""))
                    if n and n >= 1 and n <= 19 then Add("slot" .. n, { slot = n }) end
                end
            end
        end
    end
    -- Только предметы (зелья, еда): показать самые слабые - лучшее будет у макроса.
    if spells == 0 and #items > ART_MAX and #list == #items then
        local out = {}
        for i = #items - ART_MAX + 1, #items do out[#out + 1] = { item = items[i] } end
        return out
    end
    if switch and not seen["act:target"] then
        table.insert(list, 1, { act = "target" })
        if #list == 2 then list[3] = { act = "target" } end
    end
    if #list < 2 then return {} end
    while #list > ART_MAX do table.remove(list) end
    return list
end

-- Состояние: "ready" - всё выучено, "part" - не всё, "later" - ничего.
-- missing - названия невыученного. items - для макросов с предметами.
function H.TipState(entry)
    local em = UI.Effective(entry.class, entry.m)
    local spells = UI.SpellIDs(em.body)
    if #spells == 0 then
        -- Без заклинаний: нужны предметы из текста (если они там есть).
        local any, have = false, false
        for id in em.body:gmatch("item:(%d+)") do
            any = true
            if ItemCount(tonumber(id)) > 0 then have = true break end
        end
        return (have or not any) and "ready" or "noitems", {}
    end
    local known, total, missing = 0, 0, {}
    for _, e in ipairs(spells) do
        if not C_Spell.GetSpellName(e.id) then
            -- такого заклинания в игре нет (WoW Forever убрала): не ждём его
        elseif Known(e.id) then
            known, total = known + 1, total + 1
        else
            total = total + 1
            local note = H.LearnNote(e.id)
            missing[#missing + 1] = H.SpellName(e.id) .. (note and (" (" .. note .. ")") or "")
        end
    end
    if total == 0 then return "gone", missing end -- всех заклинаний макроса в игре нет
    if known == total then return "ready", missing end
    if known > 0 then return "part", missing end
    return "later", missing
end

-------------------------------------------------------------------------------
--  Импорт и экспорт: код для копирования
--  Код: первая линия «MacroCoach:1», дальше по записи в линии:
--  C~название~описание~значок~текст - свой макрос,
--  E~КЛАСС/имя~название~значок~текст - правка готового.
--  Экранирование: \\ \n \s (~) \p (|).
-------------------------------------------------------------------------------
local HEADER = "MacroCoach:1"
-- коды, сделанные под прежним именем EasyMacros, тоже принимаются
local OLD_HEADER = "EasyMacros:1"
local function Esc(s)
    s = tostring(s or ""):gsub("\r", "")
    return (s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("~", "\\s"):gsub("|", "\\p"))
end
local UNESC = { ["\\"] = "\\", n = "\n", s = "~", p = "|" }
local function Unesc(s)
    return (s:gsub("\\(.)", function(c) return UNESC[c] or ("\\" .. c) end))
end
local function Fields(line)
    local f = {}
    for part in (line .. "~"):gmatch("(.-)~") do f[#f + 1] = Unesc(part) end
    return f
end
local function IconField(icon)
    if icon == nil then return "" end
    return tostring(icon)
end
local function IconValue(s)
    if s == nil or s == "" then return nil end
    if tonumber(s) then return tonumber(s) end
    if s:match("^[%w_\\%.%-]+$") then return s end
end

function H.RecordCustom(entry)
    return table.concat({ "C", Esc(entry.name), Esc(entry.desc), Esc(IconField(entry.icon)), Esc(B.Build(entry)) }, "~")
end

function H.Export()
    local db = UI.DB()
    local lines, nc, ne = { HEADER }, 0, 0
    for _, entry in ipairs(UI.CustomList()) do
        lines[#lines + 1] = H.RecordCustom(entry)
        nc = nc + 1
    end
    local keys = {}
    for key in pairs(db.edits) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local e = db.edits[key]
        lines[#lines + 1] = table.concat({ "E", Esc(key), Esc(e.name), Esc(IconField(e.icon)), Esc(e.body) }, "~")
        ne = ne + 1
    end
    return table.concat(lines, "\n"), nc, ne
end

-- Код одного макроса: чтобы предложить его автору аддона.
function H.ExportOne(entry)
    return HEADER .. "\n" .. H.RecordCustom(entry)
end

-- «Предложить»: открыть «Импорт/экспорт» с кодом этого макроса.
function H.Suggest(entry)
    H.shareDraft = entry
    UI.Open("CUSTOM", 3)
end

-- Свободное имя для своего макроса (до 16 символов).
-- Свободное название: нет ни среди своих макросов, ни в окне /macro (иначе
-- «Добавить» перезаписал бы чужой макрос с тем же названием).
local function FreeName(name)
    -- в игре название макроса - до 16 символов: длиннее игра обрежет, и
    -- макрос потом не найдётся по названию
    while UI.CharCount(name) > 16 and #name > 0 do
        name = name:sub(1, -2):gsub("[\192-\255][\128-\191]*$", "")
    end
    local taken = setmetatable({}, { __index = function(_, n) return GetMacroIndexByName(n) > 0 end })
    for _, e in ipairs(UI.CustomList()) do rawset(taken, e.name, true) end
    if not taken[name] then return name end
    for i = 2, 99 do
        local suffix = " " .. i
        local base = name
        while UI.CharCount(base .. suffix) > 16 and #base > 0 do
            base = base:sub(1, -2):gsub("[\192-\255][\128-\191]*$", "")
        end
        if not taken[base .. suffix] then return base .. suffix end
    end
    return name
end

local function ReadyExists(key)
    local class, name = key:match("^(%u+)/(.+)$")
    return class and FindReady(class, name) ~= nil
end

-- Одна запись -> true, что добавлено ("custom"/"edit") и имя.
local function ApplyRecord(line)
    local f = Fields(line)
    if f[1] == "C" and #f >= 5 then
        local body = f[5]
        if #body > 2000 or strtrim(f[2]) == "" then return false end
        -- такой же макрос уже есть (код загрузили второй раз) - не дублируем
        local name = strtrim(f[2]):gsub("\"", "")
        for _, e in ipairs(UI.CustomList()) do
            if e.name == name and B.Build(e) == body then return true, "same", name end
        end
        local m = B.New()
        m.name = FreeName((strtrim(f[2]):gsub("\"", "")))
        m.desc = f[3]
        m.icon = IconValue(f[4])
        B.Parse(body, m)
        local list = UI.CustomList()
        list[#list + 1] = m
        return true, "custom", m.name
    elseif f[1] == "E" and #f >= 5 and ReadyExists(f[2]) then
        if #f[5] > 2000 then return false end
        local e = { name = f[3] ~= "" and f[3] or nil, icon = IconValue(f[4]), body = f[5] ~= "" and f[5] or nil }
        if not (e.name or e.icon or e.body) then return false end
        -- Прошлое название, чтобы найти уже созданный в игре макрос.
        local old = UI.DB().edits[f[2]]
        if old then e.prev = (old.name and old.name ~= e.name) and old.name or old.prev end
        UI.DB().edits[f[2]] = e
        return true, "edit", f[2]
    end
    return false
end

-- Возвращает: добавлено своих, правок готовых, не распознано строк,
-- уже были такие же, был ли заголовок кода.
function H.Import(text)
    text = (text or ""):gsub("\r", "")
    local nc, ne, bad, same, head = 0, 0, 0, 0, false
    local first = true
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = strtrim(line)
        if line ~= "" then
            if first and (line == HEADER or line == OLD_HEADER) then
                head = true
            else
                local ok, kind = ApplyRecord(line)
                if ok and kind == "custom" then
                    nc = nc + 1
                elseif ok and kind == "same" then
                    same = same + 1
                elseif ok then
                    ne = ne + 1
                else
                    bad = bad + 1
                end
            end
            first = false
        end
    end
    return nc, ne, bad, same, head
end

-------------------------------------------------------------------------------
--  Подсказки после тренера: новые советы и старые ранги на панелях
-------------------------------------------------------------------------------
local function TipKey(e) return e.class .. "/" .. e.m.name end

local function SeenTips()
    local h = UI.DB().helper
    h.seen = h.seen or {}
    local key = CharKey()
    local first = h.seen[key] == nil
    h.seen[key] = h.seen[key] or {}
    return h.seen[key], first
end

local lastKnown
local function OnSpellsChanged(initial)
    local b = ScanBook()
    -- Выучено новое: появились свои заклинания (питомца не считаем).
    local learned = false
    if lastKnown then
        for id in pairs(b.own) do
            if not lastKnown[id] then
                learned = true
                break
            end
        end
    end
    lastKnown = b.own
    local class = PlayerClass()
    if not D.TIPS[class] then return end
    local seen, first = SeenTips()
    local fresh = {}
    for _, e in ipairs(H.Tips(class)) do
        if not seen[TipKey(e)] and H.TipState(e) == "ready" then
            seen[TipKey(e)] = true
            fresh[#fresh + 1] = e
        end
    end
    if initial or first or not H.Opt("tips") or not learned then return end
    -- Одна строка в чат: новые советы и старые ранги.
    local parts = {}
    if #fresh > 0 then
        local names = {}
        for i, e in ipairs(fresh) do
            if i <= 3 then
                local _, title = UI.Loc(e.class, e.m)
                names[#names + 1] = Quote(title)
            end
        end
        if #fresh > 3 then names[#names + 1] = (T("и ещё %d")):format(#fresh - 3) end
        parts[#parts + 1] = (T("новые полезные макросы: %s (/coach советы)")):format(table.concat(names, ", "))
    end
    local old = InCombatLockdown() and 0 or #H.OldRanks()
    if old > 0 then
        parts[#parts + 1] = (T("старых рангов на панелях: %d (/coach ранги)")):format(old)
    end
    if #parts > 0 then Print(table.concat(parts, "; ") .. ".") end
end

-- Один раз после обновления: макросы лечения, созданные аддоном раньше,
-- привести к безопасному виду (только те, что совпадают с текстом аддона).
local RESYNC_VERSION = 1
local function ResyncOnce()
    local h = UI.DB().helper
    if (h.resynced or 0) >= RESYNC_VERSION then return end
    h.resynced = RESYNC_VERSION
    H.ResyncReady()
end

local spellWatch = CreateFrame("Frame")
spellWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
spellWatch:RegisterEvent("SPELLS_CHANGED")
spellWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
local watchReady, watchPending, watchAfterCombat
spellWatch:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" then bookDirty = true end
    if event == "PLAYER_REGEN_ENABLED" then
        -- в бою книгу не перебирали (смена облика и стоек шлёт SPELLS_CHANGED)
        if not watchAfterCombat then return end
        watchAfterCombat = nil
    elseif event == "SPELLS_CHANGED" and InCombatLockdown() then
        watchAfterCombat = true
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if not watchReady then
            C_Timer.After(5, function()
                watchReady = true
                pcall(OnSpellsChanged, true)
                pcall(ResyncOnce)
            end)
        end
        return
    end
    if not watchReady or watchPending then return end
    watchPending = true
    C_Timer.After(2, function()
        watchPending = nil
        pcall(OnSpellsChanged, false)
    end)
end)

-------------------------------------------------------------------------------
--  Общие детали страниц
-------------------------------------------------------------------------------
local function NewPage(key)
    local f = UI.Frame()
    local page = CreateFrame("Frame", nil, f.child)
    page:SetPoint("TOPLEFT")
    local width = f.child:GetWidth()
    page:SetWidth(width)
    UI.Pages()[key] = page
    return page, width
end

local function NewCard(page, width)
    local c = CreateFrame("Frame", nil, page, "BackdropTemplate")
    UI.Card(c)
    c:SetWidth(width - 20)
    return c
end

local function Title(parent) return UI.Text(parent, "SystemFont_Large", "GameFontNormalLarge", GOLD) end
local function Body(parent, color) return UI.Text(parent, "SystemFont_Med2", "GameFontHighlight", color or LIGHT, true) end
local function Small(parent, color) return UI.Text(parent, "SystemFont_Med1", "GameFontHighlightSmall", color or GREY, true) end
local function Code(parent) return UI.Text(parent, "SystemFont_Med1", "GameFontHighlightSmall", CODE, true) end

-- Тёмная подложка под текстом кода, как на карточках макросов.
local function CodeBg(parent, fs)
    local bg = parent:CreateTexture(nil, "ARTWORK")
    bg:SetColorTexture(0, 0, 0, 0.7)
    bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 6)
    bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 6, -6)
    return bg
end

local function Button(parent, text, w, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

-- Ячейка со значком, как в книге заклинаний. mark - галочка или крестик.
local function IconSlot(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local k = size / 37
    -- подложка ровно под значком (картинка ячейки книги заклинаний вылезала
    -- снизу и справа жёлтой полосой)
    local slot = b:CreateTexture(nil, "BACKGROUND")
    slot:SetColorTexture(0, 0, 0, 0.6)
    slot:SetPoint("TOPLEFT", -1, 1)
    slot:SetPoint("BOTTOMRIGHT", 1, -1)
    b.tex = b:CreateTexture(nil, "BORDER")
    b.tex:SetAllPoints()
    local border = b:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(64 * k, 64 * k)
    border:SetPoint("CENTER")
    b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.mark:SetSize(size * 0.55, size * 0.55)
    b.mark:SetPoint("TOPRIGHT", size * 0.18, size * 0.18) -- галочка - в правом верхнем углу
    b.mark:Hide()
    function b:SetMark(kind)
        if kind == "ok" then
            self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        elseif kind == "no" then
            self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        elseif kind == "wait" then
            self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        end
        self.mark:SetShown(kind ~= nil)
    end
    return b
end
H.IconSlot = IconSlot

-------------------------------------------------------------------------------
--  Картинка «Было -> Макрос» на карточке макроса (левая колонка карточки).
--  art:Set(list, icon, mark, grey): list - из H.ArtList, icon - значок
--  макроса, mark - "ok" (на панели) / "wait" (не выучено). art.after -
--  значок макроса: карточка вешает на него перетаскивание на панель.
-------------------------------------------------------------------------------
local ART_W, ART_H = 206, 70
H.ART_W, H.ART_H = ART_W, ART_H
local SLOT_NAME = { [13] = "Верхний аксессуар", [14] = "Нижний аксессуар" }

local function ArtEntryIcon(e)
    if e.tex then return e.tex end
    if e.spell then return UI.SpellIcon(e.spell) or 134400 end
    if e.item then return UI.ItemIcon(e.item) or 134400 end
    if e.slot then
        return (GetInventoryItemTexture and GetInventoryItemTexture("player", e.slot))
            or "Interface\\Icons\\INV_Jewelry_Talisman_01"
    end
    return ACT[e.act] and ACT[e.act].icon or 134400
end

local function ArtTip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.spell and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(e.spell)
    elseif e.item and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(e.item)
    elseif e.slot then
        GameTooltip:SetText(T(SLOT_NAME[e.slot] or "Предмет из ячейки"))
    elseif e.act then
        GameTooltip:SetText(T(ACT[e.act] and ACT[e.act].tip or "?"))
    else
        GameTooltip:SetText(e.note or "")
    end
    -- e.note - своё пояснение (страница «Проверка»)
    if e.note and (e.spell or e.item or e.slot or e.act) then
        GameTooltip:AddLine(e.note, 0.6, 0.6, 0.6, true)
    elseif not e.note then
        GameTooltip:AddLine(T("Без макроса это отдельная кнопка или действие."), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function H.MacroArt(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:SetSize(ART_W, ART_H)
    art.before = {}
    for i = 1, ART_MAX do
        local b = IconSlot(art, 30)
        b:SetScript("OnEnter", ArtTip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        art.before[i] = b
    end
    art.arrow = art:CreateTexture(nil, "ARTWORK")
    art.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    art.arrow:SetSize(28, 28)
    art.after = IconSlot(art, 40)
    local hl = art.after:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    art.bTag = Small(art, { 1, 0.45, 0.45 })
    art.bTag:SetWordWrap(false)
    art.bTag:SetText(T("Было"))
    art.aTag = Small(art, { 0.4, 1, 0.4 })
    art.aTag:SetJustifyH("CENTER")
    art.aTag:SetWordWrap(false)
    art.aTag:SetText(T("Макрос"))
    -- labels - подписи вместо «Было» / «Макрос»: { "Ранг 1", "Высший" }.
    -- left - прижать к левому краю (а не по центру колонки); вернёт ширину.
    function art:Set(list, icon, mark, grey, labels, left)
        self.bTag:SetText(labels and labels[1] or T("Было"))
        self.aTag:SetText(labels and labels[2] or T("Макрос"))
        local n = #list
        local w = n > 0 and (n * 38 + 72) or 40
        local x0 = left and 2 or math.floor((ART_W - w) / 2)
        for i, b in ipairs(self.before) do
            local e = list[i]
            b.entry = e
            b:SetShown(e ~= nil)
            if e then
                b.tex:SetTexture(ArtEntryIcon(e))
                b.tex:SetDesaturated(true)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x0 + (i - 1) * 38, -10)
            end
        end
        self.arrow:SetShown(n > 0)
        self.bTag:SetShown(n > 0)
        self.after:ClearAllPoints()
        if n > 0 then
            self.arrow:ClearAllPoints()
            self.arrow:SetPoint("LEFT", self.before[n], "RIGHT", 6, 0)
            self.after:SetPoint("LEFT", self.arrow, "RIGHT", 6, 0)
            self.bTag:ClearAllPoints()
            self.bTag:SetPoint("TOPLEFT", self.before[1], "BOTTOMLEFT", -2, -8)
        else
            self.after:SetPoint("TOPLEFT", x0, -5)
        end
        self.after.tex:SetTexture(icon)
        self.after.tex:SetDesaturated(grey and true or false)
        self.after:SetMark(mark)
        self.aTag:ClearAllPoints()
        self.aTag:SetPoint("TOP", self.after, "BOTTOM", 0, -6)
        return w + 4
    end
    return art
end

-- Многострочное поле ввода с прокруткой, как поле текста в редакторе.
local boxCount = 0
local function TextBox(parent, w, h)
    boxCount = boxCount + 1
    local box = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate")
    box:SetSize(w, h)
    local sf = CreateFrame("ScrollFrame", "MacroCoachHelperBox" .. boxCount, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -30, 8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(w - 44)
    eb:SetHeight(h - 16)
    sf:SetScrollChild(eb)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    if type(sf.ScrollBar) ~= "table" then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local range = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - d * 20)))
        end)
    end
    if ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, sf) end)
    end
    eb:SetScript("OnTextChanged", function(self, user)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, sf) end
        if box.onChange then box.onChange(self:GetText() or "", user) end
    end)
    -- Буфер обмена аддону недоступен: копирует и вставляет игра по Ctrl+C и
    -- Ctrl+V, а мы только видим нажатие и пишем «Скопировано».
    eb:HookScript("OnKeyDown", function(_, key)
        if box.onCopy and key == "C" and IsControlKeyDown and IsControlKeyDown() then box.onCopy() end
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    -- код бывает длинным: без предела длины
    eb:SetMaxLetters(0)
    if eb.SetMaxBytes then eb:SetMaxBytes(0) end
    -- полоса прокрутки - только когда есть что прокручивать
    sf.scrollBarHideable = true
    if ScrollFrame_OnScrollRangeChanged then pcall(ScrollFrame_OnScrollRangeChanged, sf) end
    box.edit = eb
    return box
end

-- Значок для картинки онбординга: "rank"/"kick"/"mo"/"mod1".., ID предмета или файл.
local function ExampleSpell(key)
    local ex = D.EXAMPLE[PlayerClass()] or D.EXAMPLE.SHAMAN
    local n = key:match("^mod(%d)$")
    if n then return ex.mods[tonumber(n)] end
    return ex[key]
end

local function ArtIcon(what)
    if type(what) == "number" then return UI.ItemIcon(what) or 134400 end
    local id = ExampleSpell(what)
    if type(id) == "number" then return UI.SpellIcon(id) or 134400 end
    return "Interface\\Icons\\" .. what
end

local function ExampleCode(card)
    local ex = D.EXAMPLE[PlayerClass()] or D.EXAMPLE.SHAMAN
    local code = card.code
    if card.key == "best" and ex.best then
        -- лучшее сверху: макрос берёт первое, что есть в сумках
        local b = ex.best.before
        code = "#showtooltip\n/use item:" .. ex.best.after .. "\n/use item:" .. b[#b] .. "\n/use item:" .. b[#b - 1]
    end
    if card.key == "mo" then
        code = ex.moHelp and "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] {mo}"
            or "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] {mo}"
    end
    if not code then return nil end
    return (code:gsub("{(%w+)}", function(k)
        local id = ExampleSpell(k)
        if not id then return "{" .. k .. "}" end
        if k == "kick" and PlayerClass() == "SHAMAN" then return "{r:" .. id .. "}" end
        return "{s:" .. id .. "}"
    end))
end

-- Кнопка в углу карточки: показать или скрыть текст макроса - круглая
-- кнопка со стрелкой, как прокрутка чата: вниз - раскрыть, вверх - свернуть.
-- self.body, self.class, self.codeKey, self.codeOpen заполняет карточка,
-- b:SetOpen(open) - какую стрелку показать; onToggle - перерисовка.
local ARROW_DOWN, ARROW_UP = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp"
function H.CardHelp(parent, anchor, onToggle)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    function b:SetOpen(open)
        local base = open and ARROW_UP or ARROW_DOWN
        self:SetNormalTexture(base .. "-Up")
        self:SetPushedTexture(base .. "-Down")
    end
    b:SetOpen(false)
    b:SetScript("OnEnter", function(self)
        if not self.codeKey then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(H.CodeShown(self.codeKey, self.codeOpen) and T("Скрыть текст макроса") or T("Показать текст макроса"), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not self.codeKey then return end
        H.ToggleCode(self.codeKey, self.codeOpen)
        self:SetOpen(H.CodeShown(self.codeKey, self.codeOpen))
        if onToggle then onToggle() end
        -- подпись при наведении - уже с новым действием
        if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
    end)
    return b
end

-------------------------------------------------------------------------------
--  Страница «Зачем макросы»
-------------------------------------------------------------------------------
local ILL_W = 206 -- ширина картинки «до -> после»

local function OpenTarget(open)
    if open == "CLASS" or open == "REC" then
        -- «Рекомендации» - первая вкладка класса.
        local class = PlayerClass()
        class = ns.MACROS[class] and class or "GENERAL"
        UI.Open(class, open == "REC" and (UI.TabIndex(class, "Рекомендации") or 1) or nil)
    else
        UI.Open(open[1], type(open[2]) == "string" and UI.TabIndex(open[1], open[2]) or open[2])
    end
end

local function OnboardCard(page, width, def)
    local c = NewCard(page, width)
    local inner = width - 20 - 32
    local textX = 16 + ILL_W + 14
    local textW = inner - ILL_W - 14
    local L = ns.Pick(def)
    local title = Title(c)
    title:SetWidth(inner)
    title:SetText(L.title)
    -- «лучшее из сумок» - своё у класса: вода у заклинателей, зелья у остальных
    local ex = D.EXAMPLE[PlayerClass()] or D.EXAMPLE.SHAMAN
    local bestOf = def.key == "best" and ex.best or nil
    local beforeList = bestOf and bestOf.before or def.before
    local afterWhat = bestOf and bestOf.after or def.after
    -- Картинка: значки «до» серые, последний с крестиком, стрелка, «после» с галочкой.
    local art = CreateFrame("Frame", nil, c)
    art:SetSize(ILL_W, 70)
    local before = {}
    for i, what in ipairs(beforeList) do
        local s = IconSlot(art, 30)
        s:SetPoint("TOPLEFT", (i - 1) * 38, -10)
        s.what = what
        before[i] = s
    end
    local arrow = art:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    arrow:SetSize(28, 28)
    arrow:SetPoint("LEFT", before[#before], "RIGHT", 6, 0)
    local after = IconSlot(art, 40)
    after:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    after.what = afterWhat
    local bTag = Small(art, { 1, 0.45, 0.45 })
    bTag:SetPoint("TOPLEFT", before[1], "BOTTOMLEFT", -2, -8)
    bTag:SetWordWrap(false)
    bTag:SetText(T(def.beforeTag or "Было"))
    local aTag = Small(art, { 0.4, 1, 0.4 })
    aTag:SetPoint("TOP", after, "BOTTOM", 0, -6)
    aTag:SetJustifyH("CENTER")
    aTag:SetWordWrap(false)
    aTag:SetText(T(def.afterTag or "Макрос"))

    local text = Body(c)
    text:SetWidth(textW)
    text:SetText(RED .. T("Проблема:") .. "|r " .. L.problem .. "\n\n" .. GREEN .. T("Решение:") .. "|r " .. L.solution)
    local code = Code(c)
    code:SetWidth(textW - 12)
    local codeBg = CodeBg(c, code)
    local btn
    if def.open then
        btn = Button(c, T(def.button), 190, function() OpenTarget(def.open) end)
    end
    function c:Fit()
        local y = 14
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 16, -y)
        y = y + title:GetStringHeight() + 10
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", 16, -y)
        for i, s in ipairs(before) do
            s.tex:SetTexture(ArtIcon(s.what))
            s.tex:SetDesaturated(true)
            s:SetMark(i == #before and "no" or nil)
        end
        after.tex:SetTexture(ArtIcon(after.what))
        after:SetMark("ok")
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", textX, -y)
        local ty = y + text:GetStringHeight()
        local stored = ExampleCode(def)
        code:SetShown(stored ~= nil)
        codeBg:SetShown(stored ~= nil)
        if stored then
            -- Данные заклинаний запрашиваются один раз, не при каждой перерисовке
            -- (иначе событие загрузки снова вызывает перерисовку).
            if not self.requested then
                self.requested = true
                UI.RequestSpells(stored)
            end
            code:SetText(((UI.Render(stored)):gsub("|", "||")))
            code:ClearAllPoints()
            code:SetPoint("TOPLEFT", textX + 6, -(ty + 16))
            ty = ty + 16 + code:GetStringHeight() + 8
        end
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", textX, -(ty + 10))
            ty = ty + 10 + 22
        end
        local h = math.max(y + 70, ty) + 16
        self:SetHeight(h)
        return h
    end
    return c
end

local function BuildIntroPage(key)
    local page, width = NewPage(key)
    local I = ns.Pick(D.INTRO)
    -- Шапка без рамки (общая для всех страниц): заголовок, мысль, куда идти.
    local header = UI.PageHeader(page, width)
    header:Set(I.title, I.text)
    for i, st in ipairs(D.START) do
        local b = Button(page, T(st.label), 100, function() OpenTarget(st.open) end, T(st.tip))
        local fs = b:GetFontString()
        b:SetWidth(math.ceil((fs and fs:GetStringWidth() or 120) + 28))
        header.buttons[i] = b
    end

    local cards = {}
    local class = PlayerClass()
    for _, def in ipairs(D.ONBOARDING) do
        if not (def.skip and def.skip[class]) then cards[#cards + 1] = OnboardCard(page, width, def) end
    end

    function page:Layout()
        local y = -header:Layout(16)
        for _, c in ipairs(cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 10, y)
            y = y - c:Fit() - 10
        end
        self:SetHeight(-y)
        return -y
    end
    return page
end

-------------------------------------------------------------------------------
--  Страница «Проверка»
-------------------------------------------------------------------------------
local MAX_RANK_ROWS = 12
local ISSUE_COLOR = { removed = RED, unknown = RED, english = YELLOW, empty = GREYC }

-- Строка статуса со значком: зелёная галочка - всё хорошо, жёлтый знак - есть что сделать.
local function StatusText(ok, text)
    local icon = ok and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-Waiting"
    -- значок по середине строки (со сдвигом вниз он опускался ниже текста)
    return "|T" .. icon .. ":14:14:0:0|t " .. (ok and GREEN or YELLOW) .. text .. "|r"
end

-- Кнопка, которая просит второй щелчок: «Удалить» -> «Точно?» (3 секунды).
local function ArmedButton(parent, text, w, onConfirm, tip)
    local b
    b = Button(parent, text, w, function()
        if not b.armed then
            b.armed = true
            b:SetText(T("Точно?"))
            C_Timer.After(3, function()
                b.armed = nil
                b:SetText(b.label or text)
            end)
            return
        end
        b.armed = nil
        b:SetText(b.label or text)
        onConfirm(b)
    end, tip)
    return b
end

local function BuildCheckPage(key)
    local page, width = NewPage(key)
    local inner = width - 20 - 32
    local ROW_ICON = 22
    local rowPad = math.floor(ROW_ICON * (64 / 37 - 1) / 2 + 0.5) -- рамка ячейки шире значка
    local header = UI.PageHeader(page, width)
    header:Set(T("Проверка"), T("Аддон сам находит старые ранги на панелях и ошибки в ваших макросах. Исправить или удалить - одной кнопкой."))
    local function Refresh() UI.Relayout() end

    -- Карточка проверки: заголовок и «Проверить снова» сверху; ниже картинка
    -- слева, пояснение и итог справа; ниже - список и кнопки.
    local function CheckCard(title, note, labels)
        local c = NewCard(page, width)
        c.title = Title(c)
        c.title:SetWidth(inner - 150)
        c.title:SetText(title)
        c.again = Button(c, T("Проверить снова"), 140, function()
            Refresh()
            Print(T("проверка обновлена."))
        end, T("Проверить ещё раз: панели и макросы могли измениться."))
        c.again:SetPoint("TOPRIGHT", -14, -12)
        c.art = H.MacroArt(c)
        c.art.after:EnableMouse(false)
        c.labels = labels
        c.note = Small(c)
        c.note:SetText(note)
        c.status = Body(c)
        return c
    end
    -- Верх карточки, вернёт y под ним.
    local function TopLayout(c, list, icon, mark)
        c.title:ClearAllPoints()
        c.title:SetPoint("TOPLEFT", 16, -14)
        local y = 14 + math.max(c.title:GetStringHeight(), 22) + 12
        c.art:ClearAllPoints()
        c.art:SetPoint("TOPLEFT", 16, -y)
        local aw = c.art:Set(list, icon, mark, false, c.labels, true)
        local tx = 16 + aw + 18
        c.note:SetWidth(inner - aw - 18)
        c.note:ClearAllPoints()
        c.note:SetPoint("TOPLEFT", tx, -y)
        c.status:SetWidth(inner - aw - 18)
        c.status:ClearAllPoints()
        c.status:SetPoint("TOPLEFT", tx, -(y + c.note:GetStringHeight() + 8))
        local textH = c.note:GetStringHeight() + 8 + c.status:GetStringHeight()
        return y + math.max(H.ART_H, textH) + 12
    end
    -- Ряд кнопок слева направо; вернёт y под ним.
    local function ButtonRow(c, list, y)
        local x, any = 16, false
        for _, b in ipairs(list) do
            if b:IsShown() then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -y)
                x = x + b:GetWidth() + 10
                any = true
            end
        end
        return any and (y + 22 + 12) or y
    end

    -- Старые ранги
    local ranks = CheckCard(T("Старые ранги на панелях"),
        T("Новый ранг от тренера сам на панель не встаёт: аддон ставит на это место высший. Низкий ранг нужен нарочно (дешёвое прерывание, лечение ради маны) - нажмите «Оставить»."),
        { T("Ранг 1"), T("Высший") })
    local rRows = {}
    local rFix = Button(ranks, T("Обновить все"), 150, function() H.FixRanks(page.old, Refresh) end)
    local rKeepAll = Button(ranks, T("Оставить все так"), 150, function()
        H.KeepAll(page.old)
        Refresh()
    end, T("Низкие ранги на этих кнопках стоят нарочно: аддон не будет их менять и напоминать о них."))
    local rKept = Button(ranks, "", 200, function()
        H.ClearKept()
        Refresh()
    end, T("Снова показывать кнопки, где вы оставили низкий ранг."))
    local rUndo = Button(ranks, T("Вернуть как было"), 150, function() H.UndoRanks(Refresh) end,
        T("Вернуть на кнопки ранги, которые стояли до последнего обновления."))

    local function RankRow(i)
        if rRows[i] then return rRows[i] end
        local r = CreateFrame("Frame", nil, ranks)
        r:SetSize(inner, 28)
        r.icon = IconSlot(r, ROW_ICON)
        r.icon:SetPoint("LEFT", rowPad, 0)
        r.icon:SetScript("OnEnter", function(self)
            if not (r.entry and GameTooltip.SetSpellByID) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(r.entry.id)
            GameTooltip:Show()
        end)
        r.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.text = Body(r)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", rowPad + 8, 0)
        r.text:SetWidth(inner - 210 - ROW_ICON - rowPad * 2 - 8)
        r.text:SetWordWrap(false)
        r.keep = Button(r, T("Оставить"), 96, function()
            if r.entry then
                H.KeepRank(r.entry)
                Refresh()
            end
        end, T("Низкий ранг здесь нарочно: аддон не будет его менять и напоминать о нём."))
        r.keep:SetPoint("RIGHT", 0, 0)
        r.btn = Button(r, T("Обновить"), 96, function()
            if r.entry then H.FixRanks({ r.entry }, Refresh) end
        end)
        r.btn:SetPoint("RIGHT", r.keep, "LEFT", -6, 0)
        rRows[i] = r
        return r
    end

    -- Макросы в игре
    local mac = CheckCard(T("Мои макросы в игре"),
        T("Все макросы из окна /macro: опечатки в названиях, английские названия на русском клиенте, пустые и то, чего нет в WoW Forever."),
        { T("С ошибкой"), T("Работает") })
    local mRows = {}
    local mEmpty = ArmedButton(mac, "", 220, function()
        -- с конца, чтобы номера оставшихся не сдвигались
        local list = {}
        for _, m in ipairs(page.macros or {}) do if m.empty then list[#list + 1] = m.index end end
        table.sort(list, function(x, y) return x > y end)
        for _, index in ipairs(list) do H.DeleteGameMacro(index) end
        Refresh()
    end, T("Удалит из окна /macro все пустые макросы: такие кнопки ничего не делают."))

    local function MacroRow(i)
        if mRows[i] then return mRows[i] end
        local r = CreateFrame("Frame", nil, mac)
        r:SetWidth(inner)
        r.icon = IconSlot(r, ROW_ICON)
        r.icon:SetPoint("TOPLEFT", rowPad, -rowPad + 2)
        local tx = ROW_ICON + rowPad * 2 + 8
        r.name = UI.Text(r, "SystemFont_Med2", "GameFontHighlight", GOLD)
        r.name:SetPoint("TOPLEFT", tx, 0)
        r.name:SetWidth(inner - tx - 220)
        r.name:SetWordWrap(false)
        r.issues = Small(r, LIGHT)
        r.issues:SetWidth(inner - tx - 220)
        r.issues:SetPoint("TOPLEFT", tx, -18)
        r.del = ArmedButton(r, T("Удалить"), 100, function()
            if r.data then H.DeleteGameMacro(r.data.index, Refresh, r.data.name) end
        end, T("Удалит этот макрос из окна /macro. Щёлкните ещё раз, чтобы подтвердить."))
        r.del:SetPoint("TOPRIGHT", 0, 0)
        r.btn = Button(r, T("Исправить"), 110, function()
            if r.data then H.FixGameMacro(r.data.index, Refresh, r.data.name) end
        end, T("Заменит английские названия в этом макросе на названия на языке клиента. Название и значок макроса останутся."))
        r.btn:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
        mRows[i] = r
        return r
    end

    function page:Layout()
        local y = -header:Layout(16)
        -- Ранги
        page.old = H.OldRanks()
        ranks:ClearAllPoints()
        ranks:SetPoint("TOPLEFT", 10, y)
        local first = page.old[1]
        local spell = first and first.id or ExampleSpell("rank")
        local best = first and first.best or spell
        if #page.old == 0 then
            ranks.status:SetText(StatusText(true, T("Все заклинания на панелях - высших рангов.")))
        elseif #page.old > MAX_RANK_ROWS then
            ranks.status:SetText(StatusText(false, (T("Старых рангов: %d. Ниже первые %d, «Обновить все» обновит все.")):format(#page.old, MAX_RANK_ROWS)))
        else
            ranks.status:SetText(StatusText(false, (T("Старых рангов: %d.")):format(#page.old)))
        end
        local ry = TopLayout(ranks, { { spell = spell, note = T("На панели старый ранг, а выучен выше.") } },
            (best and UI.SpellIcon(best)) or 134400, "ok")
        for _, r in ipairs(rRows) do r:Hide() end
        for i, e in ipairs(page.old) do
            if i > MAX_RANK_ROWS then break end
            local r = RankRow(i)
            r.entry = e
            r.icon.tex:SetTexture(UI.SpellIcon(e.id) or 134400)
            r.text:SetText((T("%s: ранг %d -> %d")):format(e.name, e.rank, e.bestRank))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 16, -ry)
            r:Show()
            ry = ry + 32
        end
        local kept = H.KeptCount()
        rFix:SetShown(#page.old > 0)
        rKeepAll:SetShown(#page.old > 0)
        rUndo:SetShown(H.lastFix ~= nil)
        rKept:SetShown(kept > 0)
        rKept:SetText((T("Вернуть оставленные (%d)")):format(kept))
        if #page.old > 0 then ry = ry + 4 end
        ry = ButtonRow(ranks, { rFix, rKeepAll, rUndo, rKept }, ry)
        ranks:SetHeight(ry + 4)
        y = y - ry - 4 - 10

        -- Макросы: проверяются при каждом открытии и по «Проверить снова»
        page.macros, page.total = H.CheckGameMacros()
        mac:ClearAllPoints()
        mac:SetPoint("TOPLEFT", 10, y)
        local empties = 0
        for _, m in ipairs(page.macros) do
            m.empty = strtrim(m.body or "") == ""
            if m.empty then empties = empties + 1 end
        end
        if #page.macros == 0 then
            mac.status:SetText(StatusText(true, (T("Проверено макросов: %d. Ошибок нет.")):format(page.total or 0)))
        else
            mac.status:SetText(StatusText(false, (T("Проверено макросов: %d. С замечаниями: %d.")):format(page.total or 0, #page.macros)))
        end
        local m1 = page.macros[1]
        -- пример - макрос своего класса (значок заклинания по наведению)
        local mIcon = (m1 and m1.icon) or UI.SpellIcon(ExampleSpell("mo")) or "Interface\\Icons\\INV_Misc_Note_01"
        local my = TopLayout(mac, { { tex = mIcon, note = T("Макрос с ошибкой: кнопка не сработает или сработает не так.") } }, mIcon, "ok")
        for _, r in ipairs(mRows) do r:Hide() end
        for i, m in ipairs(page.macros) do
            local r = MacroRow(i)
            r.data = m
            -- строка взята из запаса: «Точно?» от прошлого макроса сбросить
            r.del.armed = nil
            r.del:SetText(r.del.label or T("Удалить"))
            r.icon.tex:SetTexture(m.icon or 134400)
            r.name:SetText(m.name)
            local lines = {}
            for _, is in ipairs(m.issues) do lines[#lines + 1] = (ISSUE_COLOR[is.kind] or "") .. "- " .. is.text .. "|r" end
            r.issues:SetText(table.concat(lines, "\n"))
            r.btn:SetShown(m.english)
            local h = math.max(18 + r.issues:GetStringHeight() + 4, ROW_ICON + rowPad * 2)
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 16, -my)
            r:Show()
            my = my + h + 10
        end
        mEmpty.label = (T("Удалить пустые (%d)")):format(empties)
        if not mEmpty.armed then mEmpty:SetText(mEmpty.label) end
        mEmpty:SetShown(empties > 1)
        my = ButtonRow(mac, { mEmpty }, my)
        mac:SetHeight(my + 4)
        y = y - my - 4 - 10
        self:SetHeight(-y)
        return -y
    end
    return page
end

-------------------------------------------------------------------------------
--  Страница «Импорт/экспорт» (во вкладке «Свои макросы»)
-------------------------------------------------------------------------------
local function BuildSharePage(key)
    local page, width = NewPage(key)
    local inner = width - 20 - 32
    local header = UI.PageHeader(page, width)
    header:Set(T("Импорт и экспорт"), T("Сохраните свои макросы кодом - на случай переустановки игры или чтобы поделиться с другом."))

    -- Экспорт
    local ex = NewCard(page, width)
    local eTitle = Title(ex)
    eTitle:SetText(T("Сохранить код"))
    local eNote = Small(ex)
    eNote:SetWidth(inner)
    eNote:SetText(T("Свои макросы и правки готовых - одним кодом. Скопируйте его в файл или отправьте другу."))
    local exBox = TextBox(ex, inner, 90)
    local eMake = Button(ex, T("Копировать код"), 150, function()
        local text, nc, ne = H.Export()
        page.exported = { nc = nc, ne = ne }
        page.suggested, page.copied = nil, nil
        if nc + ne == 0 then
            -- сохранять нечего: пустой код только запутает
            exBox.edit:SetText("")
            exBox.edit:ClearFocus()
        else
            exBox.edit:SetText(text)
            exBox.edit:SetFocus()
            exBox.edit:HighlightText()
        end
        UI.Relayout()
    end)
    local eInfo = Small(ex, LIGHT)
    eInfo:SetWidth(inner - 170)
    exBox.onCopy = function()
        if strtrim(exBox.edit:GetText() or "") == "" then return end
        page.copied = true
        UI.Relayout()
    end
    exBox.onChange = function(_, user) if user then page.copied = nil end end

    -- Импорт
    local im = NewCard(page, width)
    local iTitle = Title(im)
    iTitle:SetText(T("Загрузить код"))
    local iNote = Small(im)
    iNote:SetWidth(inner)
    iNote:SetText(T("Вставьте код (Ctrl+V) и нажмите «Загрузить». Макросы добавятся к вашим, такие же не повторятся."))
    local iBox = TextBox(im, inner, 90)
    local iInfo = Body(im)
    iInfo:SetWidth(inner - 300)
    local iGo = Button(im, T("Загрузить"), 150, function()
        local text = strtrim(iBox.edit:GetText() or "")
        if text == "" then
            page.imported = YELLOW .. T("Сначала вставьте код в поле выше (Ctrl+V).") .. "|r"
            UI.Relayout()
            return
        end
        local nc, ne, bad, same, head = H.Import(text)
        local msg
        if nc + ne + same == 0 and not head then
            msg = RED .. T("Это не код MacroCoach: скопируйте его целиком, вместе с первой строкой.") .. "|r"
        else
            msg = (T("Добавлено своих макросов: %d, правок готовых: %d.")):format(nc, ne)
            if same > 0 then msg = msg .. " " .. (T("Уже были: %d.")):format(same) end
            if bad > 0 then msg = msg .. " " .. RED .. (T("Не распознано строк: %d.")):format(bad) .. "|r" end
            Print(msg)
            -- загружено без ошибок - поле очистить, чтобы не загрузить дважды
            if bad == 0 then iBox.edit:SetText("") iBox.edit:ClearFocus() end
        end
        page.imported = msg
        if nc > 0 then UI.RefreshCustom(true) end
        UI.Relayout()
    end)
    iGo:SetEnabled(false)
    -- «Вставить»: пустое поле в фокусе - остаётся нажать Ctrl+V
    local iPaste = Button(im, T("Вставить"), 120, function()
        iBox.edit:SetText("")
        iBox.edit:SetFocus()
        page.imported = YELLOW .. T("Нажмите Ctrl+V.") .. "|r"
        UI.Relayout()
    end)
    iBox.onChange = function(text, user)
        local has = strtrim(text) ~= ""
        iGo:SetEnabled(has)
        -- вставили код целиком - подсказать следующий шаг
        if user and has and (text:find("MacroCoach:", 1, true) or text:find("EasyMacros:", 1, true)) and not page.pasted then
            page.pasted = true
            page.imported = GREEN .. T("Код вставлен: нажмите «Загрузить».") .. "|r"
            UI.Relayout()
        elseif not has then
            page.pasted = nil
        end
    end

    function page:Layout()
        -- «Предложить» с карточки своего макроса: код одного макроса.
        if H.shareDraft then
            local entry = H.shareDraft
            H.shareDraft = nil
            page.suggested, page.exported = entry.name, nil
            exBox.edit:SetText(H.ExportOne(entry))
            C_Timer.After(0, function()
                exBox.edit:SetFocus()
                exBox.edit:HighlightText()
            end)
        end
        local y = -header:Layout(16)
        ex:ClearAllPoints()
        ex:SetPoint("TOPLEFT", 10, y)
        eTitle:ClearAllPoints()
        eTitle:SetPoint("TOPLEFT", 16, -14)
        eNote:ClearAllPoints()
        eNote:SetPoint("TOPLEFT", eTitle, "BOTTOMLEFT", 0, -6)
        local ey = 14 + eTitle:GetStringHeight() + 6 + eNote:GetStringHeight() + 12
        eMake:ClearAllPoints()
        eMake:SetPoint("TOPLEFT", 16, -ey)
        eInfo:ClearAllPoints()
        eInfo:SetPoint("TOPLEFT", eMake, "TOPRIGHT", 12, -2)
        local S = ns.Pick(D.SUBMIT)
        if page.suggested then
            eInfo:SetText(GREEN .. (T("Код макроса «%s» выделен: нажмите Ctrl+C и отправьте автору.")):format(page.suggested) .. "|r\n" .. S)
        elseif page.exported and page.exported.nc + page.exported.ne == 0 then
            eInfo:SetText(YELLOW .. T("Пока нечего сохранять: своих макросов и правок готовых нет.") .. "|r")
        elseif page.exported and page.copied then
            eInfo:SetText(GREEN .. T("Скопировано. Вставьте код в файл или в сообщение другу.") .. "|r")
        elseif page.exported then
            eInfo:SetText(YELLOW .. T("Код выделен: нажмите Ctrl+C.") .. "|r\n" .. (T("Своих макросов: %d, правок готовых: %d.")):format(page.exported.nc, page.exported.ne))
        else
            local nEdits = 0
            for _ in pairs(UI.DB().edits) do nEdits = nEdits + 1 end
            eInfo:SetText((T("Своих макросов: %d, правок готовых: %d.")):format(#UI.CustomList(), nEdits))
        end
        ey = ey + math.max(22, eInfo:GetStringHeight()) + 10
        exBox:ClearAllPoints()
        exBox:SetPoint("TOPLEFT", 14, -ey)
        ey = ey + 90 + 14
        ex:SetHeight(ey)
        y = y - ey - 10

        im:ClearAllPoints()
        im:SetPoint("TOPLEFT", 10, y)
        iTitle:ClearAllPoints()
        iTitle:SetPoint("TOPLEFT", 16, -14)
        iNote:ClearAllPoints()
        iNote:SetPoint("TOPLEFT", iTitle, "BOTTOMLEFT", 0, -6)
        local iy = 14 + iTitle:GetStringHeight() + 6 + iNote:GetStringHeight() + 12
        iBox:ClearAllPoints()
        iBox:SetPoint("TOPLEFT", 14, -iy)
        iy = iy + 90 + 10
        iPaste:ClearAllPoints()
        iPaste:SetPoint("TOPLEFT", 16, -iy)
        iGo:ClearAllPoints()
        iGo:SetPoint("LEFT", iPaste, "RIGHT", 8, 0)
        iInfo:ClearAllPoints()
        iInfo:SetPoint("TOPLEFT", iGo, "TOPRIGHT", 12, -2)
        iInfo:SetText(page.imported or "")
        iy = iy + math.max(22, iInfo:GetStringHeight() + 2) + 14
        im:SetHeight(iy)
        y = y - iy - 10
        self:SetHeight(-y)
        return -y
    end
    return page
end

-------------------------------------------------------------------------------
--  Вкладки помощника (вызывается из ShowClass в MacroCoach.lua)
-------------------------------------------------------------------------------
local BUILDERS = {
    intro = BuildIntroPage,
    check = BuildCheckPage,
    share = BuildSharePage,
}

function ns.BuildHelperPage(kind, key)
    local f = BUILDERS[kind]
    return f and f(key)
end

