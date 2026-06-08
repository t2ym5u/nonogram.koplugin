# nonogram.koplugin

A Nonogram (Picross) plugin for [KOReader](https://github.com/koreader/koreader).

## Concept

Nonograms are logic puzzles where you fill cells in a grid according to numeric clues
on each row and column. The clues indicate the lengths of consecutive filled-cell groups
in that line. Solving the puzzle reveals a pixel-art picture.

## Planned Features

- **Multiple grid sizes** — 5×5, 10×10, 15×15, 20×20
- **Three difficulty levels** — Easy, Medium, Hard
- **Two cell states** — filled or crossed-out (to mark known-empty cells)
- **Clue highlighting** — tap a clue number to highlight its corresponding group
- **Check** — highlights contradictions with the clues
- **Reveal solution** — shows the full solution
- **Undo** — step back through your moves
- **Auto-save** — game state is saved and restored on next launch

## Controls

| Action | How |
|--------|-----|
| Fill a cell | Tap it |
| Cross out a cell (empty marker) | Long-press it |
| Undo last move | Tap **Undo** |
| Check progress | Tap **Check** |
| New game | Tap **New game** |
| Change grid size | Tap **Grid** |
| Change difficulty | Tap **Diff** |

## Why e-ink friendly?

Nonograms require no animation and rely purely on binary cell states (filled / empty),
making them ideal for e-ink displays with limited refresh rates.

## License

GPL-3.0
