# pi.nvim

A Neovim plugin for chatting with the [pi coding agent](https://github.com/badlogic/pi-mono) via JSONL RPC.

## Features

- 🚀 Two-window UI: chat output and input
- 💬 Real-time streaming responses
- 🛠️ Tool execution display
- 📎 File references (`@file` support)
- ⚡ Slash commands (`/clear`, `/help`, etc.)
- 🎨 Extension UI protocol support (select, confirm, input, editor)
- 🔧 Multiple layout options (horizontal, vertical, tab)

## Requirements

- Neovim 0.9+
- `pi` binary installed: `npm install -g @mariozechner/pi-coding-agent`

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

      -- Keymaps
      keymaps = {
        close = 'q',              -- Close/toggle pi windows
        cancel = '<C-x>',         -- Cancel the running agent (also works in chat buffer)
      },
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
:PiCancel           " Cancel current operation (alias for PiAbort)
```

Or in Lua:

```lua
require('pi').start()    -- Start chat
require('pi').send_message('Hello, write a function to reverse a string')
```

## Keymaps (Input Buffer)

| Key                    | Action                              |
| ---------------------- | ----------------------------------- |
| `<CR>` (normal mode)   | Send message                        |
| `S-<CR>` (insert mode) | Send steering message               |
| `<C-s>` (normal mode)  | Send steering message               |
| `<C-c>`                | Clear input                         |
| `<C-x>` (default)      | Cancel / abort operation            |
| `C-n`                  | New session                         |
| `@`                    | File picker (insert file reference) |
| `?`                    | Show slash commands help            |

> **Note:** The cancel keymap is configurable via `keymaps.cancel` and works in both the input and chat buffers.

## Slash Commands

Slash commands are provided by the pi agent and its extensions. They are invoked by typing `/` followed by the command name.

### Viewing Available Commands

- Press `?` in the input buffer, or
- Run `:PiCommands` to see a list of available commands

Commands include:

- **Extension commands** - Registered by extensions via `pi.registerCommand()`
- **Prompt templates** - Loaded from `.pi/agent/prompts/*.md` files
- **Skills** - Loaded from `.pi/agent/skills/`

Commands are loaded from pi when the connection is established. They are executed by pi, not the Neovim plugin.

### Example Usage

- `/my-extension-command` - Run a custom extension command
- `/fix-tests` - Run a prompt template
- `/skill:brave-search` - Use a skill

### Client-Side Commands

These commands are handled by the Neovim plugin:

| Command   | Description                            |
| --------- | -------------------------------------- |
| `/resume` | List and switch between saved sessions |
| `/new`    | Start new session                      |

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
├── commands.lua          # Slash commands
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
- ✅ Slash commands with custom command support
- ❌ Images in chat (terminal dependent)
- ✅ File picker (@ references) - built-in vim.ui.select

## License

MIT

