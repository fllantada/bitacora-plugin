# bitacora-colaborador

The Claude Code plugin for **project collaborators** on a bitácora (project logbook)
run by the project owner at their own deployment.

## Install

```bash
claude plugin marketplace add fllantada/bitacora-plugin
claude plugin install bitacora-colaborador
```

Then claim your key with the one-time code from your invitation email:

```bash
bitacora-api alta <code>
```

That's it. The `/bitacora` skill is available in every Claude Code session, and the
`bitacora-api` client is on your PATH via the `~/.local/bin/bitacora-api` shim.

## What you get

- **`/bitacora` skill** — the collaborator's craft: reading the project context,
  writing dated entries, opening and closing decisions, superseding what your work
  makes obsolete.
- **`bitacora-api`** — the HTTP client. Your key is scoped to your project and your
  name: everything you write is signed by the server.
- Your writes are visible in the web app with author attribution — yours in one
  color, everyone else's in another.

## Connect the MCP

To ask your agent what the project owner is working on and what is planned next, register
the project's MCP once, with your key:

```bash
bitacora-api mcp
```

Every Claude Code session then has the read-only tool `objetivos_abiertos`: the open goals,
each with its progress and the plans, bugs and manual steps pursuing it, plus their sources.
Texts come in their original language, marked with `idioma`, and your agent translates them.
When you renew your key, `bitacora-api alta` re-registers the MCP with the new one.

## What your key can't do

Deleting records and the hours panel belong to the project owner. Everything else —
lines, entries, decisions, documents, glossary, stack, flows — you work exactly like
the owner does, under your own name.

## Updates

The plugin is republished automatically with every deployment of the logbook engine,
so client and server stay in sync. `claude plugin update bitacora-colaborador` pulls
the latest.
