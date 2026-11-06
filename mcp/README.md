# deadlock-ai-mod-kit MCP server

How to connect the kit's MCP server to an AI app, and what actions it gives the AI. What the kit is: [../README.md](../README.md).

## Actions

| Group | Actions |
|---|---|
| Setup & check | `doctor`, `setup` (the root `setup.ps1`: check, list what's missing, install after the user's yes, build `generated/`), `mount_addons`, `reset_all` |
| Learn | `kit_docs` (cookbook, guides, docs, `generated/`), `catalog_search`, `catalog_refresh` (generate-docs.ps1: the catalog and `generated/`), `get_stock` |
| Create & build | `new_mod` (`storeUrl` for a mod that saves data), `prepare_audio` (audio.ps1; optional FFmpeg/yt-dlp from `setup` with `media`), `convert_model` (convert-model.ps1; optional Blender from `setup` with `models`, only for .dae/.fbx), `preview_model` (preview-model.ps1), `test_mod`, `build_mod` |
| Test | `install_mod`, `uninstall_mod`, `disable_mod`, `list_mods`, `read_console_log`, `vpk_list` |
| Share & maintain | `export_mod`, `storage`, `rebase_mod` |

Each action wraps one of the PowerShell tools in [`../tools/`](../tools/) (`setup` wraps [`../setup.ps1`](../setup.ps1)). The scripts stay the single source of behaviour and still work without MCP.

The server has **no dependencies**: Node.js 18 or later, and nothing to `npm install`. It only runs on Windows, like Deadlock modding itself. The tools need PowerShell 7, except `doctor` and `setup`, which also run in Windows PowerShell so they can install it.

## Connect it

Replace `C:\path\to\deadlock-ai-mod-kit` with the folder you downloaded the kit to.

**Claude Code:**
- **Opening the kit folder:** `.mcp.json` registers the server, and Claude Code asks once to allow it.
- **Elsewhere:**
  ```
  claude mcp add deadlock-ai-mod-kit -- node C:\path\to\deadlock-ai-mod-kit\mcp\server.js
  ```

**Claude Desktop:** in `%APPDATA%\Claude\claude_desktop_config.json`:
```json
{ "mcpServers": { "deadlock-ai-mod-kit": { "command": "node", "args": ["C:\\path\\to\\deadlock-ai-mod-kit\\mcp\\server.js"] } } }
```

**Codex CLI:** in `%USERPROFILE%\.codex\config.toml`:
```toml
[mcp_servers.deadlock-ai-mod-kit]
command = "node"
args = ['C:\path\to\deadlock-ai-mod-kit\mcp\server.js']
```

**Cursor** (`.cursor/mcp.json`) and **VS Code** (`.vscode/mcp.json`, with `"servers"` instead of `"mcpServers"`) take the same `command`/`args` as Claude Desktop.

## Develop

```powershell
cd mcp; node --test
```

- The tests drive the real server over stdio with a fake PowerShell (`DEADLOCK_MCP_RUNNER`) and a fake game folder (`DEADLOCK_MCP_CONTEXT`). They touch nothing real.
- Adding an action: give it a handler in `tools.js` that calls a PowerShell tool, then add a case to the "each action runs the right tool" test.
- Write the description for an AI that has never seen the kit. Say when to use the action, and which user approval it needs.
