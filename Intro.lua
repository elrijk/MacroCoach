local _, ns = ...
local T = ns.T
local UI = ns.UI
local S = ns.S
local floor, min, max = math.floor, math.min, math.max

-------------------------------------------------------------------------------
--  Знакомство с аддоном: отдельное окно, тот же вид, что в EasyCraft.
--  Показывается при первом открытии MacroCoach раньше самого окна; дальше -
--  по кнопке «?» у крестика окна и по /coach intro.
--  Заголовок по центру, золотая линия, строка пояснения; ниже шаги
--  карточками в один ряд - номер, крупный значок, что сделать (золотом),
--  строка пояснения. Высота окна - по содержимому, внизу точки-страницы.
--  Первая страница - что делает аддон: выбери -> добавь -> жми.
--  Подробный рассказ остался на вкладке «Зачем макросы».
-------------------------------------------------------------------------------
local WIDTH = 720
local SIDE = 28 -- поля окна слева и справа
local GAP = 12 -- между карточками шагов
local ICONS = "Interface\\Icons\\"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local PAGES = {
    { title = "Одна кнопка вместо трёх",
      text = "Макрос собирает несколько действий в одну кнопку. Здесь они готовые, и про каждый понятно, что он делает.",
      flow = {
        { "INV_Misc_Book_09", "Выбери", "готовый макрос своего класса" },
        { "INV_Misc_Note_01", "Добавь", "одной кнопкой на панель" },
        { "Ability_DualWield", "Жми", "одну кнопку вместо трёх" },
      } },
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
local MAX_TILES = 3

local win

-- Значок в золотой рамке, как значки макросов.
local function ring(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.edge = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f.edge:SetPoint("TOPLEFT", -4, 4)
    f.edge:SetPoint("BOTTOMRIGHT", 4, -4)
    if f.edge.SetBackdrop then
        f.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
        f.edge:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    return f
end

local function button(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    return b
end

local function centered(fs, width)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(width)
end

local function build()
    local f = CreateFrame("Frame", "MacroCoachIntroFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIDTH, 400)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Card(f)
    f:SetBackdropColor(0.04, 0.03, 0.02, 1)
    f:SetBackdropBorderColor(0.75, 0.6, 0.3, 1)
    tinsert(UISpecialFrames, "MacroCoachIntroFrame")
    -- фон не плоский: сверху тёплый коричневый, книзу уходит в чёрный
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 1), CreateColor(0.2, 0.14, 0.08, 1))
    if not ok then bg:SetColorTexture(0.1, 0.075, 0.05, 1) end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- шапка: заголовок по центру, золотая линия, строка пояснения
    f.title = UI.Text(f, "SystemFont_Huge1", "GameFontNormalHuge", UI.GOLD, true)
    centered(f.title, WIDTH - SIDE * 2 - 40)
    f.title:SetPoint("TOP", 0, -26)
    local file, _, flags = f.title:GetFont()
    if file then f.title:SetFont(file, 24, flags) end
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetSize(320, 1)
    f.rule:SetColorTexture(0.85, 0.68, 0.3, 0.8)
    f.rule:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
    f.text = UI.Text(f, "SystemFont_Med2", "GameFontHighlight", { 0.9, 0.87, 0.8 }, true)
    centered(f.text, WIDTH - SIDE * 2 - 60)
    f.text:SetPoint("TOP", f.rule, "BOTTOM", 0, -10)

    -- первая страница: три крупных значка со стрелками
    f.flow, f.arrows = {}, {}
    for i = 1, 3 do
        local c = CreateFrame("Frame", nil, f)
        c:SetSize(190, 150)
        c.icon = ring(c, 64)
        c.icon:SetPoint("TOP", 0, -4)
        c.label = UI.Text(c, "SystemFont_Large", "GameFontNormalLarge", UI.GOLD)
        centered(c.label, 190)
        c.label:SetPoint("TOP", c.icon, "BOTTOM", 0, -14)
        c.sub = UI.Text(c, "SystemFont_Med2", "GameFontHighlight", { 0.8, 0.77, 0.7 }, true)
        centered(c.sub, 180)
        c.sub:SetPoint("TOP", c.label, "BOTTOM", 0, -4)
        f.flow[i] = c
        if i > 1 then
            local a = f:CreateTexture(nil, "ARTWORK")
            a:SetSize(32, 32)
            a:SetTexture(ARROW)
            a:SetVertexColor(1, 0.82, 0)
            f.arrows[i - 1] = a
        end
    end

    -- шаги раздела: карточки в один ряд
    f.tiles = {}
    for i = 1, MAX_TILES do
        local c = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        UI.Card(c)
        c:SetBackdropColor(0, 0, 0, 0.45)
        c:SetBackdropBorderColor(0.6, 0.48, 0.25, 0.9)
        c.num = UI.Text(c, "SystemFont_Med3", "GameFontNormal", { 0.75, 0.6, 0.3 })
        c.num:SetPoint("TOPLEFT", 10, -8)
        c.icon = ring(c, 44)
        c.icon:SetPoint("TOP", 0, -22)
        c.head = UI.Text(c, "SystemFont_Med3", "GameFontNormal", UI.GOLD, true)
        c.head:SetJustifyH("CENTER")
        c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -14)
        c.text = UI.Text(c, "SystemFont_Med1", "GameFontHighlightSmall", { 0.9, 0.87, 0.8 }, true)
        c.text:SetJustifyH("CENTER")
        c.text:SetPoint("TOP", c.head, "BOTTOM", 0, -8)
        f.tiles[i] = c
    end

    -- низ: точки-страницы по центру, кнопки по краям
    f.dots = {}
    for i = 1, #PAGES do
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetSize(8, 8)
        f.dots[i] = d
    end
    f.next = button(f, 140, S.btnBig)
    f.next:SetPoint("BOTTOMRIGHT", -SIDE, 20)
    f.back = button(f, 110, S.btn)
    f.back:SetPoint("BOTTOMLEFT", SIDE, 22)
    f.more = button(f, 190, S.btn)
    f.more:SetPoint("BOTTOMLEFT", SIDE, 22)
    f:Hide()
    return f
end

local function show(f, n)
    n = max(1, min(n, #PAGES))
    local p = PAGES[n]
    f.title:SetText(T(p.title))
    f.text:SetText(T(p.text))
    local top = 26 + f.title:GetStringHeight() + 10 + 1 + 10 + f.text:GetStringHeight() + 26
    local bottom = top

    local flow = p.flow
    for _, c in ipairs(f.flow) do c:SetShown(flow ~= nil) end
    for _, a in ipairs(f.arrows) do a:SetShown(flow ~= nil) end
    if flow then
        local step = 220
        local x0 = floor((WIDTH - step * 2 - 190) / 2)
        local h = 0
        for i, c in ipairs(f.flow) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x0 + (i - 1) * step, -top)
            c.icon.icon:SetTexture(ICONS .. flow[i][1])
            c.label:SetText(T(flow[i][2]))
            c.sub:SetText(T(flow[i][3]))
            h = max(h, 4 + 64 + 14 + c.label:GetStringHeight() + 4 + c.sub:GetStringHeight())
            if i > 1 then
                f.arrows[i - 1]:ClearAllPoints()
                f.arrows[i - 1]:SetPoint("CENTER", f, "TOPLEFT", x0 + (i - 1) * step - 15, -(top + 36))
            end
        end
        bottom = top + h
    end

    local rows = p.rows or {}
    local cols = max(1, min(#rows, MAX_TILES))
    local colW = floor((WIDTH - SIDE * 2 - GAP * (cols - 1)) / cols)
    local rowH = 0
    for i, c in ipairs(f.tiles) do
        local r = rows[i]
        c:SetShown(r ~= nil)
        if r then
            c.num:SetText(tostring(i))
            c.icon.icon:SetTexture(ICONS .. r[1])
            c.head:SetWidth(colW - 20)
            c.head:SetText(T(r[2]))
            c.text:SetWidth(colW - 28)
            c.text:SetText(T(r[3]))
            rowH = max(rowH, 22 + 44 + 14 + c.head:GetStringHeight() + 8 + c.text:GetStringHeight() + 18)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", SIDE + (i - 1) * (colW + GAP), -top)
            c:SetWidth(colW)
        end
    end
    if #rows > 0 then
        for i, c in ipairs(f.tiles) do
            if rows[i] then c:SetHeight(rowH) end
        end
        bottom = top + rowH
    end

    -- высота окна - по содержимому
    f:SetHeight(bottom + 26 + S.btnBig + 20)

    local dotStep = 16
    local dx = floor((WIDTH - (#PAGES - 1) * dotStep - 8) / 2)
    for i, d in ipairs(f.dots) do
        d:ClearAllPoints()
        d:SetPoint("BOTTOMLEFT", dx + (i - 1) * dotStep, 29)
        if i == n then d:SetColorTexture(1, 0.82, 0, 1) else d:SetColorTexture(0.45, 0.38, 0.26, 1) end
    end

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

-- ВРЕМЕННО, ДЛЯ ПРОВЕРКИ: знакомство показывается при каждом открытии
-- аддона. Перед релизом поставить false.
local TEST_ALWAYS = true

-- Первое открытие аддона: сначала знакомство, само окно MacroCoach - когда
-- знакомство закроют. Возвращает true, если окно открывать пока не надо.
function ns.IntroFirst(openMain)
    if ns.skipIntro then ns.skipIntro = nil; return false end -- открываем окно после знакомства
    if UI.DB().onboarded and not TEST_ALWAYS then return false end
    ns.ShowIntro(function()
        ns.skipIntro = true
        openMain()
        ns.skipIntro = nil
    end)
    return true
end
