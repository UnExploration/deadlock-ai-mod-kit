# deadlock-ai-mod-kit: instructions for AI agents

This repo lets anyone make Deadlock mods with an AI agent: you. The user describes a mod, or a change to their own game; you build it, install it, have them check it in-game, and export it for sharing. Many users have never modded anything, so explain things in their terms. Who it is for and what is out of scope: [README.md § Who it is for](README.md#who-it-is-for).

## Where to start

1. **A request for a mod or a change to the game:** open the [cookbook](cookbook/README.md), a router by file type: find the row for the request's file type and follow its guide.
2. **Follow the workflow** in [`SKILL.md`](SKILL.md): setup check, acceptance checks, prove the pipeline, build, hand over. It also lists every tool and which doc owns which topic.
3. **No guide fits:** work from SKILL.md and the docs it points to. Your job is the user's mod: don't edit the kit's own docs, guides or tools unless the user asks. If something new worked, say so in a line and offer to write it up as a guide.

**Use the `deadlock-ai-mod-kit` MCP tools when you have them** (`doctor`, `new_mod`, `install_mod`, `read_console_log`, …; `.mcp.json` registers the server for Claude Code in this folder). Each one wraps a PowerShell script in [`tools/`](tools/), so without MCP run the same script: `pwsh -File <tool>.ps1` (`Get-Help <tool>.ps1 -Full`). Other MCP apps connect through [mcp/README.md](mcp/README.md), which also maps actions to scripts.

## Two kinds of knowledge

- **[`generated/`](generated/README.md)** is data read off the user's installed game: build, file paths, UI layouts and panel IDs, heroes, sounds, models. It is built on the user's PC by `setup.ps1` and not shipped. **If it holds only its README, run `setup` (MCP) or `setup.ps1` (repo root) before anything else.** `catalog_search` searches the full tables behind it.
- **[`docs/`](docs/README.md)** is authored knowledge: how mods load, what's proven in-game, what's allowed. [docs/README.md](docs/README.md) says what the docs are and how current they are.
- **Take every path, ID or name from `generated/` or the catalog**, never from memory or a doc's example.
- **After a Deadlock patch, or when `doctor` warns,** run `setup.ps1` or `catalog_refresh` (`generate-docs.ps1`) to rewrite `generated/`. Never edit `generated/` by hand.

## Rules

- **Change the Deadlock install only through the tools** (`enable-addons.ps1`, `build.ps1 -Install`, `mods.ps1`), and only after the user has asked to install or test.
- **Downloads need the user's yes.** List what each one is, why it's needed and where it comes from, and get one yes for the whole list. Reduced CSDK 12 is unsigned: say so.
- **Fair play:** client-side only. Nothing that reads game memory, injects code, automates input or reveals hidden information. Notes and settings the player wrote are fine.
- **In-game checks are the user's.** Batch them: install everything to be checked, give one checklist, then remove what was only there for the test.
- **Questions to the user** are about what they want, not how to implement it. Pick sensible technical defaults yourself and mention them.
- **Where a sound, picture or model comes from is a *what*.** When the user names one by what it is ("a cha-ching", "a golden trophy") and gives no file or link, ask once: their own file or link, or should you find one? Don't swap in a game asset or make one up unless they choose that.
- **When a mod saves data, ask once which address it saves through:** the kit's storage page (give the warning: run by the kit's author, no guarantee it stays online) or the user's own `https://` address. Pass the answer as `new_mod`'s `storeUrl` (`kit` or the address; `new-mod.ps1 -StoreUrl`) and never change it afterwards: players' saved data stays with that address.
- **Mods you make go in `mods/<name>/`.** That's `new_mod`'s default. They're the user's, not the kit's: git ignores them.
