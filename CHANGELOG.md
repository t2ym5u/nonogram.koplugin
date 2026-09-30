# Changelog

All notable changes to this project will be documented in this file.

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
