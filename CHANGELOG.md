# Changelog

All notable changes to this project will be documented in this file.

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Added
- "New game" once the picture is solved (or the solution is shown): the
  action bar shows it in place of the game's buttons, so the next puzzle no
  longer needs the menu.

### Changed
- Redesigned play screen, in line with the other games: a full-width action
  bar (on two rows in landscape, where five buttons don't fit one), a
  larger board -- clues and grid together are fitted to both the width and
  the height available -- and one frame around it. The status line reads
  "size · difficulty · Remaining: n" and wraps in landscape instead of
  being cut off; the Fill/Cross mode is shown on its button only.
- Title-bar menu in the same order as every other game, with the current
  values shown: "Size: 10×10" (was "Grid: 10x10"), "Difficulty: …" (was
  "Diff: …"), and "Show solution" (was "Reveal").
- New README screenshot.

### Fixed
- Show solution now also clears wrongly filled cells, so the revealed board
  is actually solved. A wrong fill left in place kept it unsolved, and the
  round never read as over.
- Clue numbers were sized off the cell and then scaled again by the screen
  DPI, so two-digit clues overflowed their slots; they are now fitted and
  centred.
- Using Hint wiped the saved game: the board was saved as nothing. And when
  a hint fills the last cell, the status now shows the win message.
- The grid's closing lines were drawn just past its edges.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.
- `i18n_fr.lua` shipped to the device but was never loaded: nothing called
  `i18n.extend()` on it, so the whole table was dead weight. main.lua now
  merges it in before the menu entry is built.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps, not one: the first says which cell is about to
  give, the second acts on it -- a player who is told where to look usually
  finds the rest themselves, and only pays for the full reveal if they want
  it. A cell that contradicts the solution is always reported before a fresh
  one is revealed, and on a mistake the hint empties the cell rather than
  solving it.

## [1.1.8] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification at all — measured as
  low as 2 in 15 puzzles actually having a unique solution at some
  size/difficulty combinations (larger, sparser grids were the worst
  affected). Added a line-solving uniqueness solver and reworked
  generation to verify each puzzle before accepting it. Every size and
  difficulty is now guaranteed unique.
