# claude-color-rate

A Claude Code status line script that displays context window usage and rate limit consumption with **pace-based color warnings**.

## Features

- **Model name** display
- **Context window** usage with progress bar
- **5-hour & 7-day rate limits** with countdown to reset
- **Pace-based color system** — warns you when you're burning through your quota faster than expected

## Color Logic

Colors are based on your *actual usage vs expected usage* given how much time has elapsed in the current window:

| Color | Meaning |
|-------|---------|
| 🔵 Blue | On track — usage is within expected pace |
| 🟡 Yellow | Slightly over pace (>1× expected) |
| 🔴 Red | Significantly over pace (>1.5× expected) |

**Example:** 7-day window, 2 days elapsed → expected usage ≈ 28%. If you've used 40%, that's over 1.5× → red.

## Output

```
Sonnet 4.6 | ●●○○○○○○○○ 40k/200k (20%)
5h: 9% (↺2h30m) | 7d: 40% (↺5d14h)
```

Two lines to keep width narrow (useful for Obsidian and narrow terminals).

## Requirements

- [Claude Code](https://claude.ai/code)
- `jq`
- `awk`, `date` (standard on macOS/Linux)

## Installation

1. Copy the script:

```bash
mkdir -p ~/.claude/scripts
curl -o ~/.claude/scripts/status-line.sh \
  https://raw.githubusercontent.com/ClpPan/claude-color-rate/main/status-line.sh
chmod +x ~/.claude/scripts/status-line.sh
```

2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/status-line.sh"
  }
}
```

3. Restart Claude Code.

## License

MIT
