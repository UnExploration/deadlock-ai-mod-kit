# deadlock-ai-mod-kit

Make Deadlock mods by asking an AI.

Download this folder, open your AI in it, and say what you want: "change my kill sound", "hide the minimap", "turn the soul orbs into pumpkins". The AI builds the mod, puts it in your game, and can pack it up for sharing on GameBanana.

No modding experience needed. Windows only. Works with any AI agent that can read files and run commands.

## Confirmed working in-game so far

The kit helps make any mod that changes a game file. These are the kinds seen working in the game, with more added as they are tried:

- **Sounds:** kill sound swapped for another game sound. An ability sound replaced with your own audio file or a clip from a link.
- **Images:** ability effect icons replaced with your own pictures, still and animated.
- **Models:** props and objects swapped for other models.
- **UI:** new things on screen: overlays, badges, buttons.
- **Mods that remember things:** a note saved in-game that survives closing and reopening Deadlock.

Not yet tried in-game but ready to go: hiding, moving or recolouring existing UI, voice lines, menu music, shop and HUD icons. Sharing a mod as a GameBanana-ready zip, repairing it after a patch and resetting back to vanilla Deadlock are built in.

## Who it is for

Players who want to change their own game, and mod makers who want to build and share mods.

## How to start

You need Windows 10 or 11, Steam with Deadlock installed, and an AI agent. Everything else is installed for you after one yes.

1. Download the kit (Code > Download ZIP, unzip) and open a terminal in the folder.
2. Run setup. It checks your PC and lists what is missing. It changes nothing yet.
   ```
   powershell -ExecutionPolicy Bypass -File setup.ps1
   ```
3. Approve the list by running it again with the ids it names, for example:
   ```
   powershell -ExecutionPolicy Bypass -File setup.ps1 -Approve csdk,s2v,pwsh
   ```
4. Open a new terminal and run the step 2 command once more. It reads your game and ends with "Ready".
5. Open your AI in the folder and ask for a mod.

From then on you describe, the AI builds and installs, you launch the game and say what you see. After a Deadlock patch, run setup again or ask the AI to.

Setup installs PowerShell 7, Node.js, Git, Source2Viewer and the community build of Valve's compiler (Reduced CSDK 12, unsigned, about 2.4 GB). Kit files go into `%LOCALAPPDATA%\deadlock-modding\`; delete that folder to remove them.

## Mods that remember things

Deadlock mods cannot write files. A mod that saves notes or settings does it through a small web page the game loads invisibly. The data stays in Steam's browser storage on the player's PC and is never sent anywhere.

The kit hosts one shared page for this at `https://unexploration.github.io/deadlock-mod-storage/`, explained in [deadlock-mod-storage](https://github.com/UnExploration/deadlock-mod-storage). A maker can host their own copy instead. The AI asks which one when it makes such a mod.

**Warning:** the kit's page is run by the kit's author, free, with no guarantee it stays online. If it goes away, mods using it stop saving until their maker hosts the page themselves, and old saved data does not carry over.

## Inside the folder

The AI reads [`AGENTS.md`](AGENTS.md) first, follows the workflow in [`SKILL.md`](SKILL.md), picks a recipe from the [cookbook](cookbook/README.md) and looks things up in [`docs/`](docs/README.md). The PowerShell tools live in [`tools/`](tools/), and [`mcp/`](mcp/README.md) wraps them as an MCP server for AI apps that speak it. Your mods go in [`mods/`](mods/README.md).

Tests: `pwsh -File tools/test/tools.tests.ps1` and `node --test` in `mcp/`. Both use a fake game install and touch nothing real.

Unofficial and not affiliated with Valve. [MIT licence](LICENSE).
