local _, ns = ...
local T = ns.T
local UI = ns.UI

-------------------------------------------------------------------------------
--  Резервная копия всех макросов игры (окно /macro) и «Обновить всё».
--  Копия лежит в MacroCoachDB.backup: { t = время, general = { ... },
--  chars = { ["Имя-Сервер"] = { ... } } }, запись - { название, значок, текст }.
--  Общие макросы одни на учётную запись, макросы персонажа - у каждого свои.
-------------------------------------------------------------------------------
local B = {}
ns.Backup = B

local function CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

local function Snapshot(perChar)
  local general, char = GetNumMacros()
  local base = perChar and (MAX_ACCOUNT_MACROS or 120) or 0
  local n = perChar and (char or 0) or (general or 0)
  local list = {}
  for i = base + 1, base + n do
    local name, icon, body = GetMacroInfo(i)
    if name then list[#list + 1] = { name, icon, body } end
  end
  return list
end

function B.Save()
  local db = UI.DB()
  local old = db.backup or {}
  local chars = old.chars or {}
  chars[CharKey()] = Snapshot(true)
  db.backup = { t = time(), general = Snapshot(false), chars = chars }
  local n = #db.backup.general + #chars[CharKey()]
  UI.Print((T("копия сохранена: %d макросов.")):format(n))
end

-- Когда сохранена копия и сколько в ней макросов для этого персонажа
-- (общие и его собственные). nil - копии нет.
function B.Info()
  local b = UI.DB().backup
  if not b then return nil end
  local mine = b.chars and b.chars[CharKey()] or {}
  return b.t, #(b.general or {}) + #mine
end

-- Макрос с таким названием в своём разделе (общие или персонажа).
local function FindIn(name, perChar)
  local general, char = GetNumMacros()
  local base = perChar and (MAX_ACCOUNT_MACROS or 120) or 0
  local n = perChar and (char or 0) or (general or 0)
  for i = base + 1, base + n do
    if GetMacroInfo(i) == name then return i end
  end
end

local function RestoreList(list, perChar)
  local done, skipped = 0, 0
  for _, m in ipairs(list or {}) do
    local index = FindIn(m[1], perChar)
    if index then
      EditMacro(index, m[1], m[2], m[3] or "")
      done = done + 1
    else
      local general, char = GetNumMacros()
      local free = perChar and (MAX_CHARACTER_MACROS or 18) - (char or 0) or (MAX_ACCOUNT_MACROS or 120) - (general or 0)
      if free > 0 then
        CreateMacro(m[1], m[2] or 134400, m[3] or "", perChar and true or nil)
        done = done + 1
      else
        skipped = skipped + 1
      end
    end
  end
  return done, skipped
end

-- Вернуть макросы из копии: существующие с тем же названием получают текст
-- из копии, недостающие создаются. Лишние макросы не удаляются.
function B.Restore()
  if InCombatLockdown() then
    UI.Print(T("в бою макросы вернуть нельзя."))
    return
  end
  local b = UI.DB().backup
  if not b then return end
  local d1, s1 = RestoreList(b.general, false)
  local d2, s2 = RestoreList(b.chars and b.chars[CharKey()], true)
  UI.Print((T("из копии возвращено: %d, не хватило места: %d.")):format(d1 + d2, s1 + s2))
end

-- После тренера: высшие ранги на панели и готовые макросы под новые
-- заклинания - одним действием (/mc update).
function ns.UpdateAll()
  local H = ns.Helper
  if not H then return end
  H.FixRanks(nil, function(n)
    H.ResyncReady()
    if n == 0 then UI.Print(T("на панелях уже высшие ранги.")) end
  end)
end
