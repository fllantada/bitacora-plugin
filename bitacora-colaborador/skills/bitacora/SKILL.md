---
name: bitacora
description: "Work with the project logbook (bitácora) as a collaborator — read the project's context, write dated entries, open and close decisions, and keep the shared record of what happened and why. Use when the user mentions the bitácora / logbook, wants to record something that happened, log a finding or a decision, check open decisions, read the project context, or asks what the logbook says about a topic."
---

# /bitacora — the project logbook, as a collaborator

The **bitácora** is the project's shared workspace: the place where complex topics get
analyzed, decisions get recorded one by one, and the day-to-day record of what happened
— and why — accumulates. It lives as a web app the owner runs; you talk to it over HTTP
with the `bitacora-api` client, and you read it in the browser with your email login.

**You are a collaborator.** Everything you write is stamped with your name by the
server, and the web shows every record's author — yours in one color, everyone else's
in another. Write freely: attribution is the mechanism of trust here, and visible
authorship replaces asking for permission.

## Setup — once per machine

Your invitation email carries a one-time claim code. Exchange it for your personal API
key (the key itself never travels by email):

```bash
bitacora-api alta <code>
```

That stores `<project>=<key>` in `~/.config/bitacora/config.local` (permissions 600,
never in git). The email also has your sign-in link for the web app.

## The client

```bash
API=~/.local/bin/bitacora-api

$API -p <project> contexto      # FIRST READ on arrival: language + stack + flows, in one call
$API -p <project> tablero       # the board: every line of work, freshest first
$API -p <project> linea <slug>  # one line: its entries, decisions and documents
$API -p <project> buscar "x"    # search across everything you can see
$API -p <project> documento linea <line> <doc>   # a document's raw markdown
```

The project resolves from your working directory when it matches; `-p <slug>` sets it
explicitly and always works. `$API proyecto` says which one resolved.

Writes take a JSON body on stdin:

```bash
$API -p <project> entrada <line-slug> <<'JSON'
{"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
JSON

$API -p <project> decision <line-slug> <<'JSON'
{"titulo":"…","cierraEn":"…","cuerpo":"…"}
JSON

$API -p <project> cerrar <decision-id> <<'JSON'
{"estado":"resuelta","cierraEn":"PR #42","nota":"what was decided, in one line"}
JSON
```

If you are offline, writes queue in `~/.config/bitacora/pendientes.jsonl` and upload
on the next write. Field values like `tipo` and `estado` are in Spanish — they are the
API's vocabulary.

## The unit is the line

A **line** (línea) is a topic worked over time — a migration, a feature area, a long
conversation. Its dimensions: the **analyses** (processed documents), the **decision
book** (what needs deciding, one point at a time), and the **chronology** (dated
entries: what happened, when, why in that order). The board orders lines by last touch;
writing content is what moves a line to the front.

## Writing entries — the craft

- `tipo` and `titulo` are required; the `cuerpo` is markdown, quick and raw. Useful
  sections: *Qué pasó* (what happened) · *Por qué se decidió así* (why this way) ·
  *Lo que se descartó* (what was discarded — the most valuable one).
- Common types: `hallazgo` (finding), `decisión`, `bloqueo` (blocker), `entrega`
  (delivery), `reunión` (meeting), `descarte` (discarded path), `incidente`.
- **Titles inform.** "Notes from Tuesday" says nothing; the title states the processed
  conclusion — reading it alone on the board, you know what's inside.
- **The writing test:** *can this be reconstructed from the diff, the issue tracker or
  an existing analysis?* If yes, don't write it. The logbook keeps what has no other
  owner: the discovery, the why, what blocked you, what was discarded and under what
  condition it comes back.
- **Dates are real.** An entry reconstructing a past event carries its real `fecha`
  (`"fecha":"YYYY-MM-DD"`); measurements typed from memory don't go in prose — name
  the fact in words instead.

## Decisions — one at a time

A decision point enters the book only when the trade-off is real: two live options and
choosing matters. Work them **individually** — origin, position, close — and don't open
the next until the one on the table is closed. Closing IS rewriting: an open point
carries its full live context; a closed one gets rewritten short and self-contained,
so someone reading it in two months understands what was decided and why without any
of today's context. References (PR numbers, links) go in `cierraEn`.

Every state change is recorded in the point's history with your name and the date —
that history is the project's "how we decided" view.

## What is someone else's

- **Supersede, never edit.** When your work makes an existing entry obsolete, mark it
  (`$API superar <line> <entry-id>` with `{"superadaPor":"…"}`) and write the new one.
  The record stays whole; the mark says history.
- **Deleting is the owner's.** Your key can't delete anything — if something should
  never have existed (a duplicate, a line opened by mistake), tell the owner.
- **The hours panel is the owner's.** It belongs to their client relationship and your
  key doesn't reach it.

## The project's system — read before deciding

`$API contexto` returns the triad that describes how this project works: the
**glossary** (what each word means HERE, and whose voice it is — the client's
vocabulary wins), the **stack** (each technology with its responsibility), and the
**flows** (end-to-end journeys, the project's integration tests). A decision taken
without reading it is taken blind. When you work with a piece or a term that has no
entry yet, add it — `$API anotar-pieza`, `$API definir` — while it's in front of you.

Full command list: `bitacora-api` with no arguments prints usage.
