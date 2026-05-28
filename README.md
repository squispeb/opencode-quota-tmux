# opencode-quota-tmux

A tmux plugin that displays your AI provider quotas directly in the status bar. Works with [tmux2k](https://github.com/2kabhishek/tmux2k).

## Supported Providers

| Provider | Data Source | Display |
|----------|-----------|---------|
| **OpenAI** | ChatGPT WHAM API | Remaining % + reset time |
| **GitHub Copilot** | GitHub billing API | Remaining % (tier-based) |
| **CrofAI** | CrofAI usage API | Remaining % + credits |

## Installation

### With TPM

Add to your `tmux.conf`:

```bash
set -g @plugin 'squispeb/opencode-quota-tmux'
```

Then press `prefix + I` to install.

### Manual

Copy `opencode-quota.sh` to your tmux plugin directory and source it from your status bar.

## Configuration

### Icons

Customize provider icons via tmux options:

```bash
set -g @tmux2k-openai-icon "󰎳"
set -g @tmux2k-copilot-icon "󰊤"
set -g @tmux2k-crofai-icon "󰚩"
set -g @tmux2k-quota-error-icon "󰅤"
```

### tmux2k Integration

Add `opencode-quota` to your right plugins:

```bash
set -g @tmux2k-right-plugins "network opencode-quota time"
```

### Required Files

- **OpenAI**: `~/.local/share/opencode/auth.json` with OpenAI tokens
- **Copilot**: `~/.config/opencode/copilot-quota-token.json` with GitHub token/username/tier
- **CrofAI**: `~/.config/opencode/crofai-key` with your API key

## Example Output

```
󰎳 72%   󰊤 90%   󰚩 86% $2.00
```

## License

MIT
