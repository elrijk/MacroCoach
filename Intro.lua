local _, ns = ...
local T = ns.T
local UI = ns.UI
local S = ns.S

-------------------------------------------------------------------------------
--  Знакомство с аддоном: отдельное окно поверх главного, как в EasyCraft.
--  Показывается само один раз, при первом открытии MacroCoach; дальше - по
--  кнопке «?» у крестика окна и по /coach intro.
--  Первая страница - что делает аддон, картинкой: выбери -> добавь -> жми.
--  Дальше по странице на раздел: три шага значками, без длинных текстов.
--  Подробный рассказ остался на вкладке «Зачем макросы».
-------------------------------------------------------------------------------
local WIDTH, HEIGHT = 600, 400
local ICONS = "Interface\\Icons\\"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local PAGES = {
    { title = "Одна кнопка вместо трёх",
      text = "Макрос собирает несколько действий в одну кнопку. Здесь они готовые, и про каждый понятно, что он делает.",
      flow = { { "INV_Misc_Book_09", "Выбери" }, { "INV_Misc_Note_01", "Добавь" }, { "Ability_DualWield", "Жми" } } },
    { title = "Готовые макросы",
      text = "Вкладки справа - классы, сверху - специализации.",
      rows = {
        { "Ability_Rogue_Sprint", "Начни с «Рекомендаций»", "Самые полезные макросы твоего класса: что решает каждый и когда жать." },
        { "INV_Misc_Bag_08", "Бери набором", "На вкладке специализации кнопка добавит все её макросы сразу." },
        { "Ability_Hunter_SniperShot", "Положи на панель", "«Добавить» берёт макрос на курсор: щёлкни по ячейке панели." },
      } },
    { title = "Свои макросы",
      text = "Собираются из готовых строк - код писать не нужно.",
      rows = {
        { "INV_Misc_Gear_01", "Конструктор", "Команда, условие, заклинание - из списков. Аддон сам проверит текст." },
        { "INV_Letter_15", "Поделись", "Кнопка «В чат» даёт ссылку: друг с MacroCoach откроет макрос щелчком." },
        { "INV_Misc_Note_06", "Сохрани кодом", "Все свои макросы - одним кодом: на случай переустановки игры." },
      } },
    { title = "Проверка",
      text = "Аддон сам находит, что сломалось.",
      rows = {
        { "Spell_Holy_HolyBolt", "Старые ранги", "Заклинания низкого ранга на панелях заменит высшими одной кнопкой." },
        { "INV_Misc_QuestionMark", "Ошибки в макросах", "Опечатки, неизвестные заклинания и то, чего нет в WoW Forever." },
        { "INV_Misc_Book_11", "Смена языка игры", "Свои готовые макросы аддон переведёт на новый язык сам." },
      } },
}

local win

local function ring(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.edge = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f.edge:SetPoint("TOPLEFT", -3, 3)
    f.edge:SetPoint("BOTTOMRIGHT", 3, -3)
    if f.edge.SetBackdrop then
        f.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        f.edge:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    return f
end

local function button(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    return b
end

local function build()
    local f = CreateFrame("Frame", "MacroCoachIntroFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Card(f) -- та же подложка, что у карточек окна
    f:SetBackdropColor(0.05, 0.045, 0.04, 0.97)
    tinsert(UISpecialFrames, "MacroCoachIntroFrame")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    f.title = UI.Text(f, "SystemFont_Huge1", "GameFontNormalHuge", UI.GOLD, true)
    f.title:SetPoint("TOPLEFT", S.s5, -S.s5)
    f.title:SetWidth(WIDTH - S.s5 * 2 - 20)
    f.text = UI.Text(f, "SystemFont_Med2", "GameFontHighlight", UI.LIGHT, true)
    f.text:SetWidth(WIDTH - S.s5 * 2)

    f.flow, f.arrows = {}, {}
    for i = 1, 3 do
        local c = CreateFrame("Frame", nil, f)
        c:SetSize(120, 100)
        c.icon = ring(c, 52)
        c.icon:SetPoint("TOP", 0, -2)
        c.label = UI.Text(c, "SystemFont_Large", "GameFontNormalLarge", UI.GOLD)
        c.label:SetPoint("TOP", c.icon, "BOTTOM", 0, -S.s3)
        c.label:SetJustifyH("CENTER")
        f.flow[i] = c
        if i > 1 then
            local a = f:CreateTexture(nil, "ARTWORK")
            a:SetSize(24, 24)
            a:SetTexture(ARROW)
            a:SetVertexColor(1, 0.82, 0)
            f.arrows[i - 1] = a
        end
    end

    f.tiles = {}
    for i = 1, 3 do
        local c = CreateFrame("Frame", nil, f)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bg:SetColorTexture(0, 0, 0, 0.3)
        c.icon = ring(c, 30)
        c.icon:SetPoint("TOPLEFT", S.s2 + 3, -(S.s2 + 3))
        c.head = UI.Text(c, "SystemFont_Med3", "GameFontNormal", UI.GOLD, true)
        c.head:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", S.s3, 0)
        c.text = UI.Text(c, "SystemFont_Med1", "GameFontHighlightSmall", UI.LIGHT, true)
        f.tiles[i] = c
    end

    f.count = UI.Text(f, "SystemFont_Med1", "GameFontHighlightSmall", UI.GREY)
    f.count:SetPoint("BOTTOMLEFT", S.s5, S.s4 + 5)
    f.next = button(f, 130, S.btnBig)
    f.next:SetPoint("BOTTOMRIGHT", -S.s5, S.s4)
    f.back = button(f, 110, S.btn)
    f.back:SetPoint("RIGHT", f.next, "LEFT", -S.s2, 0)
    f.more = button(f, 170, S.btn)
    f.more:SetPoint("RIGHT", f.back, "LEFT", -S.s2, 0)
    f:Hide()
    return f
end

local function show(f, n)
    n = math.max(1, math.min(n, #PAGES))
    local p = PAGES[n]
    f.title:SetText(T(p.title))
    f.text:SetText(T(p.text))
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -S.s2)
    local top = S.s5 + f.title:GetStringHeight() + S.s2 + f.text:GetStringHeight() + S.s5

    local flow = p.flow
    for i, c in ipairs(f.flow) do c:SetShown(flow ~= nil) end
    for _, a in ipairs(f.arrows) do a:SetShown(flow ~= nil) end
    if flow then
        local step = 170
        local x0 = math.floor((WIDTH - step * 2 - 120) / 2)
        for i, c in ipairs(f.flow) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x0 + (i - 1) * step, -(top + S.s4))
            c.icon.icon:SetTexture(ICONS .. flow[i][1])
            c.label:SetText(T(flow[i][2]))
            if i > 1 then
                f.arrows[i - 1]:ClearAllPoints()
                f.arrows[i - 1]:SetPoint("CENTER", f, "TOPLEFT", x0 + (i - 1) * step - 25, -(top + S.s4 + 28))
            end
        end
    end

    local rows = p.rows or {}
    local cols = math.max(1, #rows)
    local colW = math.floor((WIDTH - S.s5 * 2 - S.s3 * (cols - 1)) / cols)
    local rowH = 0
    for i, c in ipairs(f.tiles) do
        local r = rows[i]
        c:SetShown(r ~= nil)
        if r then
            c.icon.icon:SetTexture(ICONS .. r[1])
            c.head:SetWidth(colW - S.s2 * 2 - 36 - S.s3)
            c.head:SetText(T(r[2]))
            c.text:SetWidth(colW - S.s2 * 2)
            c.text:SetText(T(r[3]))
            local headH = math.max(36, c.head:GetStringHeight())
            c.text:ClearAllPoints()
            c.text:SetPoint("TOPLEFT", S.s2, -(S.s2 + headH + S.s2))
            rowH = math.max(rowH, S.s2 + headH + S.s2 + c.text:GetStringHeight() + S.s3)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", S.s5 + (i - 1) * (colW + S.s3), -top)
            c:SetWidth(colW)
        end
    end
    for i, c in ipairs(f.tiles) do
        if rows[i] then c:SetHeight(rowH) end
    end

    f.count:SetText(n .. " / " .. #PAGES)
    local last = n == #PAGES
    f.next:SetText(last and T("Понятно") or T("Дальше"))
    f.next:SetScript("OnClick", function()
        if last then f:Hide() else show(f, n + 1) end
    end)
    f.back:SetText(T("Назад"))
    f.back:SetShown(n > 1)
    f.back:SetScript("OnClick", function() show(f, n - 1) end)
    -- подробный рассказ с примерами - на вкладке «Зачем макросы»
    f.more:SetText(T("Подробнее с примерами"))
    f.more:SetShown(n == 1)
    f.more:ClearAllPoints()
    f.more:SetPoint("RIGHT", f.next, "LEFT", -S.s2, 0)
    f.more:SetScript("OnClick", function()
        f:Hide()
        UI.Open("HELPER", 1)
    end)
end

-- after - что сделать, когда окно закроют (любым способом), один раз.
function ns.ShowIntro(after)
    local main = UI.Frame()
    if not win then
        win = build()
        win:SetScript("OnHide", function(s)
            local fn = s.after
            s.after = nil
            if fn then pcall(fn) end
        end)
    end
    local shown = main and main:IsShown()
    win:ClearAllPoints()
    win:SetPoint("CENTER", shown and main or UIParent, "CENTER", 0, shown and 0 or 40)
    UI.DB().onboarded = true
    win.after = after
    local ok, err = pcall(show, win, 1)
    if not ok then UI.Print(tostring(err)) end
    win:Show()
    win:Raise()
end

-- Первое открытие аддона: сначала знакомство, само окно MacroCoach - когда
-- знакомство закроют. Возвращает true, если окно открывать пока не надо.
function ns.IntroFirst(openMain)
    if UI.DB().onboarded then return false end
    ns.ShowIntro(openMain)
    return true
end
