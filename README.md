# pi.nvim

A Neovim plugin for chatting with the [pi coding agent](https://github.com/badlogic/pi-mono) via JSONL RPC.

## Features

- 🚀 Two-window UI: chat output and input
- 💬 Real-time streaming responses
- 🛠️ Tool execution display
- 📎 File references (`@file` support)
- 🎨 Extension UI protocol support (select, confirm, input, editor)
- 🔧 Multiple layout options (horizontal, vertical, tab)

## Requirements

- Neovim 0.9+
- `pi` binary installed: `npm install -g @mariozechner/pi-coding-agent`
- (Optional) Telescope or fzf-lua for file picker

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'yourusername/pi.nvim',
  config = function()
    require('pi').setup({
      -- Optionally configure pi path
      pi_cmd = 'pi',
      
      -- Model selection
      -- provider = 'anthropic',
      -- model = 'claude-sonnet-4-20250514',
      
      -- Window layout: 'horizontal', 'vertical', 'tab'
      layout = 'horizontal',
      
      -- Chat window size (percentage)
      chat_height = 0.7,
      chat_width = 0.5,
      
      -- Input window lines
      input_height = 3,
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'yourusername/pi.nvim',
  config = function()
    require('pi').setup()
  end
}
```

## Usage

Start chatting:

```vim
:PiStart             " Start pi agent
:PiChat             " Open chat windows
:PiStop             " Stop pi agent
:PiNew              " Start new session
:PiAbort            " Abort current operation
```

Or in Lua:

```lua
require('pi').start()    -- Start chat
require('pi').send_message('Hello, write a function to reverse a string')
```

## Keymaps (Input Buffer)

| Key | Action |
|-----|--------|
| `<CR>` (normal mode) | Send message |
| `S-<CR>` (insert mode) | Send steering message |
| `<C-s>` (normal mode) | Send steering message |
| `<C-c>` | Clear input |
| `<C-c><C-c>` | Abort operation |
| `C-n` | New session |
| `@` | File picker (insert file reference) |

## Architecture

```
Neovim                          pi --mode rpc
┌─────────────────┐             ┌─────────────┐
│   Chat Buffer   │             │             │
│  (readonly)     │◄────Events─┤             │
└────────┬────────┘             │   Agent     │
         │                      │             │
┌────────┴────────┐             │             │
│  Input Buffer   │─────CMD────►│             │
│   (editable)    │             └─────────────┘
└─────────────────┘
```

### File Structure

```
lua/pi/
├── init.lua              # Main API
├── config.lua            # Configuration
├── rpc.lua               # JSONL RPC client
├── session.lua           # State management
├── extension_ui.lua      # Extension UI protocol
└── ui/
    ├── init.lua          # UI orchestration
    ├── chat.lua          # Chat buffer rendering
    └── input.lua         # Input buffer
```

## Protocol Compliance

This plugin follows the pi RPC protocol exactly:

- Strict LF (`\n`) JSONL framing
- Trailing `\r` handling for CRLF compatibility
- No use of generic line readers
- Proper event/response correlation via `id` field

## Development Status

Basic functionality is implemented:
- ✅ RPC connection and JSONL parsing
- ✅ Two-window UI layout
- ✅ Message streaming display
- ✅ Tool execution rendering
- ✅ User message display
- ✅ Extension UI protocol (select, confirm, input, editor, notify)
- ❌ Images in chat (terminal dependent)
- ⚠️ File picker (@ references) - basic implementation, needs polish

## License

MIT