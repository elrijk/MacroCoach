# Changelog

## 1.2.2

- "Hide macro names" is off by default. After this update it is unticked once for everyone; tick it again in the settings if you want macro names hidden.

## 1.2.1

- **Fix window**: when the automatic check (on login and after the trainer) finds something it can fix - old ranks on the bars, macros in another language, spell numbers instead of names, a split line, English spell names - a window in the centre of the screen lists it. Each fix has a tick and shows what it is now and what it will become. A fix you left alone is not offered again; the "Offer fixes" setting turns the window off.
- The Check tab shows the same "before and after" and lets you tick which macros to fix.
- Names left from another game language: the check now finds spell names and macro names in the old language, offers the translation, and merges a spare copy of a ready-made macro into the current one (its bar buttons are moved, the copy is removed, undo brings it back).
- The fix window also lists remarks the addon cannot fix by itself. `/mc fix` opens the window by hand.
- "Hide macro names" and the font size reach every action bar again, however the bar is built.
- New setting "Spell ID in tooltips" (off by default): the spell's ID at the bottom of its tooltip.
- Macro name settings (hide, font size) apply to the game's own action bars.
- One wording everywhere: "Ready-made macros".
- Lighter: about 150 unused translation strings are removed.

## 1.2.0

- **Language change**: switch the game language and MacroCoach macros already on your bars switch to it by themselves, both ways - ready-made ones, the ones you edited, and your own.
- **"Macro language" check** on the Check tab: lists macros still in another language, macros with spell numbers instead of names, and macros with a split line; fixes them with one button and can undo the fix.
- **Smart consumables**: potion, bandage and food macros show the item you actually have in your bags.
- **Chat link**: an icon on every macro puts a link in chat; other MacroCoach users open it with a click.
- **Send a macro to the author**: pick any macro - from the addon or from the game's /macro window - describe it, and the addon builds a link to a pre-filled GitHub issue.
- **Copy icon** on every macro card: the macro text as it is written in the game.
- **Learning mode** can be switched on the Helper page and now also explains a macro in its tooltip on the action bar.
- The window opens on the Helper page and appears beside the game's macro window by itself (`/mc beside` turns this off).
- Settings and import/export moved to the addon's page in the game options, grouped into sections.
- The command is now `/mc`; `/coach` still works. Russian command aliases are removed.
- One-screen introduction on first open; "?" in the header shows it again.
- On an English client, macro names on the bars are English.
- All new strings are translated into the 8 other languages (machine translation).
- Internal: the main file is split into five; fallbacks for clients other than WoW Forever are removed.

## 1.1.0

- Backup of every macro in the /macro window, with restore.
- `/coach update`: top spell ranks on your bars and refreshed ready-made macros in one go.
- Option "Only macros I can use" hides macros whose spells you have not learned yet.

## 1.0.0

First public release.

- 294 ready-made macros for all 9 classes plus general ones, stored by spell ID.
- "Why macros" intro with before/after pictures built from your own class spells.
- Recommended starter macros for each class.
- Line-by-line explanation of any macro in plain words.
- Macro builder with drop-down conditions; text mode with translation of English spell names.
- Check page: old spell ranks on action bars, typos, unknown spells, things removed in WoW Forever.
- Import and export of your own macros as a text code.
- Macros deleted with "Clear macros" can be restored with one button.
- 10 languages. Translations other than English and Russian are machine-made.
- Entry in the addon menu at the minimap.
