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

## Key renewal — self-service, two commands

Your key expires on its own every few months. You never have to track the date:

- **Before it expires**, an email arrives automatically ("Your … logbook key needs
  renewal") with a fresh claim code — just run the `bitacora-api alta <code>` line it
  contains, and the key rotates in place. Done.
- **If it already expired**, the API tells you exactly that, and the fix is:

```bash
bitacora-api renovar        # sends a fresh code to your registered email
bitacora-api alta <code>    # exchange it — the renewed key is stored for you
```

`renovar` works with the expired key as proof (it goes through its own door), and the
code only ever lands in your inbox — holding the key alone is never enough to steal a
renewal. Nothing else changes: same access, same name, fresh key.

## When invoked bare — open the board, then talk with the project

`/bitacora` with nothing else is an invitation to **talk with the project**. Do this,
in order:

1. **Resolve the project** (cwd, or `-p`; if nothing resolves, list the projects in
   `~/.config/bitacora/config.local` and ask which one).
2. **Open the board in their browser**: run `$API abrir` — it fetches a fresh one-time
   sign-in link and opens the project's board, no login friction. The person now SEES
   the board while you talk.
3. **Read the project yourself, quietly**: `$API contexto` (the glossary, stack and
   flows — skip if you already read it this session) and `$API tablero`.
4. **Present a two-line pulse and ask.** Name what's actually alive — the threads at the
   front, how many decisions are open, the freshest thing that happened — and ask what
   they'd like to talk about. For example: *"The board is open in your browser. Two
   threads are moving — the search migration and the pricing page — with three open
   decisions between them. What would you like to dig into?"* Always offer from the
   REAL board, never a generic menu.

From there, conversation: answer questions from the logbook's content (search, threads,
documents, decisions), record what they tell you as entries, open decision points when
a real trade-off appears. You are the project's memory speaking.

## The rest of the routing

| The user says | What you do |
|---|---|
| `/bitacora <thread>` | Open that thread (`$API hilo <slug>`): its brief, open decisions, latest entries and documents. The argument may be an alias — the server resolves it. |
| `/bitacora <thread> <something that happened>` | Write the dated entry (see *Writing entries* below). |
| `/bitacora <thread> decision <what needs deciding>` | Add the point to the thread's decision book. |
| `/bitacora area <name>` | Read that area (`$API area <slug>`): its name and the threads living in it, each with its state. What is open to decide there, and its timeline, live on the area's page in the browser. |
| Something that matches nothing | It's probably a thread that doesn't exist yet — list the threads and ask, rather than failing. |

Nothing runs on its own: the logbook is written when invoked, never by a hook — a
record that writes itself stops being judgment and becomes a log.

## The client

```bash
API=~/.local/bin/bitacora-api

$API -p <project> contexto      # FIRST READ on arrival: language + stack + flows, in one call
$API -p <project> tablero       # the board: every thread of work, grouped by area
$API -p <project> hilo <slug>   # one thread: its entries, decisions and documents
$API -p <project> areas         # the project's areas, with how many threads live in each
$API -p <project> area <slug>   # ONE area: its name and the threads living in it
$API -p <project> buscar "x"    # search across everything you can see
$API -p <project> documento linea <thread> <doc>   # a document's raw markdown
```

The project resolves from your working directory when it sits under a workspace root —
`~/ProyectosDev-Local`, plus any `raiz=<path>` line in `~/.config/bitacora/config.local`,
which is how you add wherever your own projects live. A folder named differently from its
project is translated with `alias.<folder>=<project>` in the same file. Outside every
root, `-p <slug>` sets it explicitly and always works. `$API proyecto` says which one
resolved.

Writes take a JSON body on stdin:

```bash
$API -p <project> entrada <thread-slug> <<'JSON'
{"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
JSON

$API -p <project> decision <thread-slug> <<'JSON'
{"titulo":"…","cierraEn":"…","cuerpo":"…"}
JSON

$API -p <project> cerrar <decision-id> <<'JSON'
{"estado":"resuelta","cierraEn":"PR #42","nota":"what was decided, in one line"}
JSON
```

If you are offline, writes queue in `~/.config/bitacora/pendientes.jsonl` and upload
on the next write. Field values like `tipo` and `estado` are in Spanish — they are the
API's vocabulary.

## Two languages: what you write travels in both

A project declares the languages its material is written in, and `$API -p <project>
contexto` tells you which. **When it declares more than one, every text you write travels
in all of them** — not only long prose: the title of an entry, the point you open, the word
you define. That text is what a reader sees before opening anything, so one language alone
leaves the workshop split: the interface in theirs, the board in someone else's.

Any text field takes its layers where it used to take a phrase:

```bash
$API -p <project> entrada <thread-slug> <<'JSON'
{"tipo":"hallazgo",
 "titulo":{"en":"Facets are counted per record","es":"Los facets se cuentan por registro"},
 "cuerpo":{"en":"# …","es":"# …"}}
JSON
```

**A bare phrase still works** and means what it always meant: that text goes into the
record's original layer. Losing a write because it came half-dressed costs more than
storing it in the language it was written in. Whatever is left without its other layer
shows up in `por-traducir` — the queue carries records as well as documents — so it can be
picked up later; writing both in the same act is what asserts they say the same thing, and
what keeps the board from reading half-and-half in the meantime.

**`escritoEn` is the record's original language**, declared once for the whole record: a
thread's name and its brief are born together and in the same language. It defaults to the
project's first declared language; name it when you write in another one:

```bash
$API -p <project> entrada <thread-slug> <<'JSON'
{"escritoEn":"en","tipo":"hallazgo",
 "titulo":{"en":"Facets are counted per record","es":"Los facets se cuentan por registro"},
 "cuerpo":{"en":"# …","es":"# …"}}
JSON
```

**To READ in your language, the `-i` flag.** It applies to everything the command brings
back: the board, a thread with its chronology, the glossary, the stack, the flows and the
search.

```bash
$API -p <project> -i en tablero     # the whole board, in English
$API -p <project> -i en contexto    # the triad, in English
```

Without the flag you get the project's own layer, and whatever lacks the language you asked
for falls back to its original — honest material in the language it was written in, never a
blank screen.

## The unit is the thread

A **thread** is a topic worked over time — a migration, a feature area, a long
conversation. Its dimensions: the **analyses** (processed documents), the **decision
book** (what needs deciding, one point at a time), and the **chronology** (dated
entries: what happened, when, why in that order).

**Every thread lives in an area**, and the area is how the workshop is navigated: the left
menu is the list of areas, each one holding its live threads, and every area has its own
board. Inside an area the order is last touch, so the thread being worked right now sits on
top of its world. A project small enough to need no areas keeps them all in one group.

The API stores a thread as `lineas` — the collection and the `lineaSlug` field keep the
name they were born with, and the client accepts both words (`hilo` and `linea`,
`editar-hilo` and `editar-linea`). Read «thread»; type either.

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
  (`$API superar <thread> <entry-id>` with `{"superadaPor":"…"}`) and write the new one.
  The record stays whole; the mark says history.
- **Deleting is the owner's.** Your key can't delete anything — if something should
  never have existed (a duplicate, a thread opened by mistake), tell the owner.
- **The hours panel is the owner's.** It belongs to their client relationship and your
  key doesn't reach it.

## The project's system — read before deciding

`$API contexto` returns the triad that describes how this project works: the
**glossary** (what each word means HERE, and whose voice it is — the client's
vocabulary wins), the **stack** (each technology with its responsibility), and the
**flows** (end-to-end journeys, the project's integration tests). A decision taken
without reading it is taken blind. When you work with a piece or a term that has no
entry yet, add it — `$API anotar-pieza`, `$API definir` — while it's in front of you.
A stack piece also carries `documentacion` (the URL of its official docs, shown as a
link on its card) and `notas` (the basics you need to work with it: version, plan,
account, the limit that bites) — fill them in when you have them at hand.

**`$API accesos` lists the project's quick links**: the outside addresses you enter every
day — the engine, the repo, the ticket board, the design file. They belong to the project
and not to a thread, and the workshop keeps them one click away in the right-hand column.
Anote one you had to hunt for with `$API anotar-acceso <<< '{"nombre":"…","url":"https://…","nota":"staging"}'`
— it is upsert by slug, so fixing a URL that moved is the same call.

Full command list: `bitacora-api` with no arguments prints usage.
