# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-11-04

### Changed
- No more guessing: every puzzle, at every size and level, can now be
  solved line by line -- look at one row or column, fill or cross the
  cells its clue forces, move on -- without ever having to try a cell
  and see whether it breaks. Before, about 1 15×15 Easy puzzle in 3 (and
  1 10×10 Easy puzzle in 9) could not be finished without such a guess.
- The levels now mean how long the chain of reasoning is: Easy puzzles
  are fuller pictures that come apart in a few sweeps over the rows and
  columns, Hard ones are sparser and need many more back-and-forths
  between rows and columns. (Easy used to be the sparsest picture, which
  actually made it the hardest to reason out.) As a result most puzzles,
  including the Daily Challenge, are new ones.
- 15×15 puzzles no longer take ages now and then: the slowest took up to
  3 s on a desktop (over a minute on a Kobo); now every puzzle is ready
  in under 0.04 s on a desktop.
- The solution check also only re-examines the rows and columns that a
  change affects.
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.5.1] - 2026-11-04

### Fixed
- Undo no longer crashes the game: the board's move history was stored
  under the same name as the Undo action, which hid it.

## [1.5.0] - 2026-11-04

### Changed
- Faster 15×15 Easy puzzles: up to 0.4 s on a desktop (about 10 s on a
  Kobo) down to under 0.1 s. The solution check works on rows and columns
  as bit masks; same puzzles as before.
- A "Generating puzzle…" progress bar shows when a puzzle takes more than a
  moment. Needs game-common 1.12.0.

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

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
