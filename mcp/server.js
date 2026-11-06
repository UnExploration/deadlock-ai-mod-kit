#!/usr/bin/env node
// deadlock-ai-mod-kit MCP server: stdio, newline-delimited JSON-RPC 2.0, no dependencies (Node 18+).
// Start: node mcp/server.js   (clients start it for you; see mcp/README.md)
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const { tools, callTool, REPO } = require('./tools');

const VERSION = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8')).version;
const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];

const INSTRUCTIONS = [
  'deadlock-ai-mod-kit: make, test and share Deadlock mods for the user. Many users have never modded: explain in their terms.',
  'Start: doctor (setup check). If generated/ holds only its README, or doctor says it is missing or for another build, run setup first (it lists missing tools and builds generated/ from the game; downloads nothing without approve). For any mod request, kit_docs with no path gives the cookbook index; find the row for the request\'s file type and follow its guide, and SKILL.md (kit_docs path "SKILL.md") for the full workflow.',
  'Game data (paths, panel IDs, heroes, file types) is in generated/ (kit_docs path "generated/README.md"), read off the installed build; take every path, ID or name from there or catalog_search, never from memory or an example in a doc.',
  'Authored knowledge (how mods load, what is proven, what is allowed) is in docs/ (kit_docs path "docs/README.md")',
  'After a Deadlock patch, run setup or catalog_refresh first; never edit generated/ by hand.',
  'Rules: change the Deadlock install (install_mod, mount_addons, uninstall_mod, reset_all) only after the user asked to install or test.',
  'Downloads (setup with approve) need one yes from the user for the whole list; Reduced CSDK 12 is unsigned, say so.',
  'In-game checks are the user\'s: batch them into one checklist, read_console_log afterwards, then uninstall what was only there for the test.',
  'Fair play: client-side only; nothing that reads game memory, injects code, automates input or reveals hidden information.',
  'Repo: ' + REPO,
].join('\n');

function send(msg) { process.stdout.write(JSON.stringify(msg) + '\n'); }
function reply(id, result) { send({ jsonrpc: '2.0', id, result }); }
function fail(id, code, message) { send({ jsonrpc: '2.0', id, error: { code, message } }); }

async function handle(msg) {
  const { id, method, params = {} } = msg;
  const isRequest = id !== undefined && id !== null;
  switch (method) {
    case 'initialize': {
      const asked = params.protocolVersion;
      return reply(id, {
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'deadlock-ai-mod-kit', title: 'Deadlock mod kit', version: VERSION },
        instructions: INSTRUCTIONS,
      });
    }
    case 'ping':
      return reply(id, {});
    case 'tools/list':
      return reply(id, { tools: tools.map(({ name, title, description, inputSchema, annotations }) => ({ name, title, description, inputSchema, annotations })) });
    case 'tools/call':
      return reply(id, await callTool(params.name, params.arguments || {}));
    default:
      if (isRequest) return fail(id, -32601, 'Method not found: ' + method);   // notifications (initialized, cancelled) need no answer
  }
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch (e) { return fail(null, -32700, 'Parse error'); }
  handle(msg).catch((e) => { if (msg.id !== undefined) fail(msg.id, -32603, e.message); });
});
rl.on('close', () => process.exit(0));
