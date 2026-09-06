---
name: bitacora
description: "Work with the project logbook (bitácora) as a collaborator — read the project's context, write dated entries, record decisions already made, and keep the shared record of what happened and why. Use when the user mentions the bitácora / logbook, wants to record something that happened, log a finding or a decision, check what was decided, read the project context, or asks what the logbook says about a topic."
---

# /bitacora — the project logbook, as a collaborator

The **bitácora** is the project's shared workspace: the place where complex topics get
analyzed, decisions get recorded one by one — already made, with their frame and their verdict — and the day-to-day record of what happened
— and why — accumulates. It lives as a web app the owner runs; you talk to it over HTTP
with the `bitacora-api` client, and you read it in the browser with your email login.

**You are a collaborator.** Everything you write is stamped with your name by the
server, and the web shows every record's author — yours in one color, everyone else's
in another. Write freely: attribution is the mechanism of trust here, and visible
authorship replaces asking for permission.

**Step zero, every time this skill is invoked: `bitacora-api version`.** The plugin
updates itself, but a new version only takes effect in the next session — this very
document may be the previous one without anything saying so. The command compares the
installed version against the latest published one (the server knows it: the same push
deploys both), and if there is a newer one it prints how to bring it in. In that case:
run the update it prints, tell the user this session's instructions are the installed
ones, and carry on — whatever the API answers is the truth in force, and its 400 errors
name the right door whenever something moved. And if the check can't reach the server
— no network, or your key expired — it stops nothing either: carry on with the work,
writes queue themselves, and an expired key is renewed with `bitacora-api renovar`.

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
   front, the pending plans (that is where work resumes), the freshest thing that happened
   — and ask what they'd like to do: resume a plan, write an analysis, log something that
   happened, record a decision that was made, or just read. For example: *"The board is
   open in your browser. Two threads are moving — the search migration and the pricing
   page — with three pending plans between them. What would you like to dig into?"*
   Always offer from the REAL board, never a generic menu.

From there, conversation: answer questions from the logbook's content (search, threads,
documents, decisions), record what they tell you as entries, record decision points when
a real trade-off gets settled. You are the project's memory speaking.

## The rest of the routing

| The user says | What you do |
|---|---|
| `/bitacora <thread>` | Open that thread (`$API hilo <slug>`): its brief, pending plans, latest entries and documents. The argument may be an alias — the server resolves it. |
| `/bitacora <thread> <something that happened>` | Write the dated entry (see *Writing entries* below). |
| `/bitacora <thread> decision <what was decided>` | Record the point — ALREADY made — in the thread's decision book, with its full frame and its verdict, or the server rejects it. |
| `/bitacora <thread> we need to <something to do>` | Open the plan: how it gets solved and where it closes. |
| `/bitacora plan <topic>` | Build the plan out of what was just discussed: ask FIRST which area or thread it joins, require where it closes, and write it into the thread (see *Planning* below). |
| `/bitacora what is left to do` | The project's execution front. |
| `/bitacora area <name>` | Read that area (`$API area <slug>`): its name and the threads living in it, each with its state. What is open to decide there, and its timeline, live on the area's page in the browser. |
| Something that matches nothing | It's probably a thread that doesn't exist yet — list the threads and ask, rather than failing. |

Nothing runs on its own: the logbook is written when invoked, never by a hook — a
record that writes itself stops being judgment and becomes a log.

## The client

```bash
API=~/.local/bin/bitacora-api

$API -p <project> contexto      # FIRST READ on arrival: language + stack + flows + the cycle instructions, in one call
$API -p <project> instrucciones # how the job cycle runs HERE, as raw markdown (404 until the owner loads them)
$API -p <project> skills        # the tools at hand here: what each one is for, and whether it is the project's own or inherited
$API -p <project> skill <name>  # one whole: how it is told, what it chains with, and its SKILL.md
$API -p <project> nota-skill <name>   # tell it for a person: {"paraQue":"…","cuando":"…","deja":"…","ojo":"…"}
                                #   write it right after reading that skill's text — the catalogue lists it uncounted until someone does
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

# A decision is recorded ALREADY MADE, and goes in whole or not at all — the server
# rejects one without its frame or its verdict:
$API -p <project> decision <thread-slug> <<'JSON'
{"titulo":"…","veredicto":"what was decided",
 "bloquea":"what was blocked while this stayed undecided",
 "opciones":[{"titulo":"…","implica":"what choosing it costs"},
             {"titulo":"…","implica":"what choosing it costs"}],
 "recomiendo":0,"recomendacion":"why that one and not the others",
 "cierraEn":"…","cuerpo":"…"}
JSON

$API -p <project> corregir <id> <<< '{"veredicto":"…"}'
```

## A thread holds SEVEN TYPES, each with its own door

A **thread** is the ticket, and what hangs from it has a type. The type is what sets its
door, its desks and its colour:

| Type | What it is | What opening it costs | Desks |
|---|---|---|---|
| **Analysis** | what was understood about a topic | its body | none: it is material you read |
| **Plan** | how something gets solved — strategy AND execution; it also carries a dispatched job | its body and where it closes | pendiente · encargado · en-curso · entregado · hecho · descartado |
| **Bug** | a defect found while doing something else | its body, with What happens · Where · How to reproduce | abierto · arreglado · descartado |
| **Client-Report** | what goes to the client, from the draft on | its body | preparacion · aprobado · entregado |
| **Decision** | a trade-off ALREADY made, with its analysis | the whole frame and its verdict | resuelta, the only one: it is a record |
| **Simulation** | the experiment before adopting a change: the session runs the arms, a person grades | its body, the hypothesis, the success criterion, two arms, the sample and the rubric | disenada · aprobada · corriendo · calificando · concluida · descartada |
| **Consultation** | the human in the loop: what the session asks the person, point by point, and the person answers ON THE WEB | its body and its points, each with what changes and what the session would do | abierta · contestada · aplicada · descartada |

```bash
$API -p <project> analisis <thread> <<'JSON'
{"titulo":"…","queEs":"what the reader will find","cuerpo":{"en":"# …"}}
JSON
$API -p <project> plan <thread> <<'JSON'
{"titulo":"…","cierraEn":"the PR that brings it","cuerpo":{"en":"# How it gets solved\n…"}}
JSON
$API -p <project> bug <thread> <<'JSON'
{"titulo":"…","cuerpo":{"en":"# What happens\n…\n\n# Where\n…\n\n# How to reproduce\n1. …\n2. …"}}
JSON
$API -p <project> client-report <thread> <<'JSON'
{"titulo":"…","ficha":{"For":"who receives it"},"cuerpo":{"en":"# …"}}
JSON

$API -p <project> del-hilo <thread> planes    # a thread's plans, with their bodies
$API -p <project> tipo planes                 # every plan in the project
$API -p <project> abiertos bugs               # the bugs still open, across threads
$API -p <project> item planes <id>            # one whole: its body and how it moved
$API -p <project> mover planes <id> <<< '{"estado":"hecho","nota":"how it closed"}'
$API -p <project> mover planes <id> <<< '{"hilo":"the-thread-it-belongs-to"}'   # move it to its thread (slug or alias)
```

**A piece hangs from the thread that already holds its topic.** Before writing, ask which
thread this is the analysis (or plan, or bug) of, and write it there; a new thread opens
when the person asks for one. A piece left on the wrong sibling thread moves with `mover`
and `hilo`: it lands after the ones already there and keeps its address unless it clashes.

**An analysis goes up SETTLED.** Clear the open questions first, in the session where
the person who can answer them is — then write. An analysis arriving with ten questions
inside hands the work back in the one shape nobody can act on: prose with no desk, absent
from every front. Ask what changes what has to be done now; when one option covers the
other and costs the same, take the one that covers and say so. **What stayed unanswered
goes up as a PLAN**, one per item, its `cierraEn` naming what closes it — a plan shows up
on the front and gets closed, and the same question buried in an analysis shows up nowhere.

**The Plan is what has to be DONE.** It is the plan you would write to solve something,
with its execution — which is why it has a desk and gets closed. A **Bug** is a fact, not a
decision — no trade-off frame, which belongs to the decision — so a defect found outside
your scope gets written down with its analysis and you carry on without the fix.

**Its door charges the three questions that make it workable**, as headings in the body:
**What happens** (what the system does and what it should do), **Where** (the piece, route
or screen, and in which environment) and **How to reproduce** (the steps or the command
that show it again). They are charged when it is opened, because a defect is told while it
is fresh: whoever saw it is the only one who can write them, and without them whoever picks
it up months later has to rediscover the defect first. And the reproduction is what gives a
bug its own expiry: it gets run before the fix, and one that no longer shows up is closed
saying exactly that.

**The Simulation is the experiment before adopting a change**, and the run produces while
the grading decides: the session designs it and runs the arms over a sample, leaving what
each arm produced; a person approves the design, grades the outputs blind on the web,
picks the right one and concludes. See *Simulations* below — grading is a collaborator's
job as much as anyone's.

**The decision enters and gets corrected through its own door** — `decision` and
`corregir`. It is born already made, with its frame and its verdict, so a generic door
that skipped those would be the shortcut a passing thought takes into the book. What
still needs deciding is a **plan** ("decide X"): pending work lives where the desks are.

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
- **Titles inform, stand alone, and fit in one phrase.** "Notes from Tuesday" says
  nothing: the title states the processed conclusion, so that reading it alone on the
  board you know what's inside. It names the topic in the words the topic is asked for —
  one leaning on another thread ("Case B: …") sends whoever opens it looking for case A.
  And the API measures it: **60 characters** for a thread's name, **80** for the title of
  what hangs from it and of the day's entry, with the rule inside the 400. It can be short
  because the substance has its own fields — the `brief` on the thread, `queEs` and
  `cuerpo` on the item.
- **The writing test:** *can this be reconstructed from the diff, the issue tracker or
  an existing analysis?* If yes, don't write it. The logbook keeps what has no other
  owner: the discovery, the why, what blocked you, what was discarded and under what
  condition it comes back.
- **Dates are real.** An entry reconstructing a past event carries its real `fecha`
  (`"fecha":"YYYY-MM-DD"`); measurements typed from memory don't go in prose — name
  the fact in words instead.

## Decisions — recorded already made, and each one stands alone

**A decision is a trade-off that was ALREADY settled, recorded with its whole analysis.**
It is read on its own and understood on its own, without opening any other document —
which is why it has its own page and why the server **demands its frame and its verdict**
when you record it:

| Field | What it carries |
|---|---|
| `veredicto` | **What was decided**, in one sentence — what the record answers without opening the point |
| `bloquea` | What was blocked while this stayed undecided |
| `opciones[]` | Two at minimum, each with `titulo` and a **developed** `implica` — the server asks for real substance, because an option without its consequences is just a title |
| `recomiendo` | The position of the option that was recommended (`0` is the first) |
| `recomendacion` | Why that one and not the others, **with the full reasoning** |
| `cierraEn` | Where it closes: a PR, an entry in the client record, or nothing |
| `cuerpo` | What triggered the point and where the work is. **The longest of them all** — it is the analysis, and the server measures it |

**The long fields carry a minimum length and the server says so when it rejects them.**
Don't write them with ellipses or leave them for later: a point is what someone reads two
months from now with none of today's context in their head.

A point without its frame or its verdict gets a 400 naming what is missing. That friction
is the mechanism: the book used to fill with points that were a passing thought with a
number, because opening cost three sentences.

A point enters the book only when the trade-off was real: two live options and choosing
mattered. What a doc, a standard or the repo's law settles leaves no point — look it up
and write the answer. **And something still to DO is a plan, not a point** — that detour
is what filled the book. Work them **individually**: origin, position, verdict, one at a
time.

**No desks.** The decision is born `resuelta` and stays recorded: what in the old model
was an open decision is now a plan ("decide X"), and what was a deferred one is a plan
with its trigger written in the body — pending work lives where the desks are. `corregir`
fixes the verdict, the frame or the text of a recorded point. `cerrar` remains as the way
out for INHERITED points that were left open under the old model — it closes one stating
its verdict (`$API -p <project> cerrar <id> <<< '{"veredicto":"…"}'`) — and `diferir`
answers with the current gesture.

A point is written short and self-contained, so someone reading it in two months
understands what was decided and why without any of today's context. References (PR
numbers, links) go in `cierraEn`. The verdict is dated in the point's history with your
name — that history is the project's "how we decided" view.

## Plans — what is left to do

The decision book answers *what was decided*; the plans answer *what is left to do* —
**the front of a thread is its pending plans**, deciding included: a choice still open
lives as a plan ("decide X"), and when it settles, the decision is recorded already made.

**What its door asks for is the body and the named close** — without the close nobody can
say whether it is done. States: `pendiente` and `hecho` at the two ends, `encargado`,
`en-curso` and `entregado` for a dispatched job in between (next paragraph), and
`descartado` for what stopped applying — marking that one `hecho` would lie about work
nobody did.

**A plan also carries a dispatched job, end to end.** When a thinking session hands work
to a coding session, the plan is the handoff: its body is the brief, its `reporte` is what
came back, and its desk says whose hands it is in — `encargado` (the brief is in the body,
waiting for a session to take it), `en-curso` (a session took it; the note names its
worktree), `entregado` (the PR is open and the report written; waiting for sign-off), then
`hecho`. One plan is one PR. **The body and the report are a contract the server
enforces.** Entering `encargado` requires the body to carry six sections as markdown
headings, each with content below: `# Task`, `# Destination`, `# Context and why`,
`# Pattern to follow`, `# Exact scope`, `# Out of scope`. Reaching `entregado` requires
`ficha.pr` and a `reporte` with six sections: `## Done`, `## Evidence`, `## Decisions
along the way` with content, and `## Frictions`, `## To decide`, `## Pending out of scope`,
which are always present and read "None" when there was nothing to report — an absent or
empty section is a 400, because a blank reads as forgotten, not as answered. The door
answers 400 naming everything missing at once, with what each section states.

**What it cost to build travels as data, in `consumo`.** One batch per round: each
engine's tokens —input, output, cache read, cache write— with the price per million that
ruled that day, and the day that table was checked (`preciosDe`). The price rides along
with the tokens because prices move, and what a closed plan has to answer is what it cost
WHEN it was built — that is what budgets the next job like it. The cost is derived on
read, so it is never sent. Each delivery ADDS its batch to the earlier ones, so a second
round declares its own without reading the first, and `ronda` names which round a batch
belongs to, so a round that arrived in two batches counts as one. `item planes <id>`
returns it summed per engine, with cost and tokens resolved.

```bash
$API -p <project> encargados                 # what can be taken · also: en-curso · entregados
$API bandeja                                 # without -p: every project this machine holds a key for
$API -p <project> tomar <id> "worktree …"    # → en-curso; the note also lands in ficha.destino
$API -p <project> entregar <id> <<'JSON'
{"reporte":{"en":"## Done\n…\n\n## Evidence\n…\n\n## Decisions along the way\n…\n\n## Frictions\nNone\n\n## To decide\n…\n\n## Pending out of scope\nNone"},
 "ficha":{"pr":"https://github.com/…/pull/…","rama":"…"},
 "consumo":{"ronda":1,"preciosDe":"YYYY-MM-DD","modelos":[{"modelo":"…","entrada":0,"salida":0,"cacheLectura":0,"cacheEscritura":0,"precio":{"entrada":0,"salida":0,"cacheLectura":0,"cacheEscritura":0}}]},
 "nota":"PR open, one ASK"}
JSON
$API -p <project> firmar <id> "PR merged"    # → hecho
$API -p <project> devolver <id> <<'JSON'
{"cuerpo":{"en":"<the whole body, with a new ## Round 2 at the end>"},"nota":"back: why"}
JSON
```

**A plan that waits for its moment carries its trigger in the body**: what wakes it up
and why today is not the day. That is what the old model called a deferred decision — a
pending item with a trigger is work that waits, and the type that waits is the plan.

```bash
$API -p <project> plan <thread> <<'JSON'
{"titulo":"Decide where the axis rule lives","cierraEn":"the schema PR",
 "cuerpo":{"en":"# What wakes this up\nPete's second localisation proposal.\n\n# The analysis so far\n…"}}
JSON
```

Dropping goes through the same door as finishing:
`$API -p <project> mover planes <id> <<< '{"estado":"descartado","nota":"why it stopped applying"}'`.
`$API -p <project> tipo planes` returns everything; `abiertos planes` leaves only the front.

## Simulations — the experiment before adopting a change

Before a change in how the project works gets adopted — a harness piece, a process, a
tool, a model — it gets **simulated**: the same items —the **sample**— down two or more
**arms**, with a **rubric** and a **success criterion written BEFORE running**, and a
**person grading at the end**. The simulation hangs from the thread of its topic, like an
analysis does, and a decision in the thread's book ratifies what it showed.

**The run produces and the grading decides, and they have different owners.** The session
designs, runs the arms and leaves the **outputs** — what each arm produced for each item.
The person approves the design, grades the outputs **blind** — as "Option 1" and "Option
2", in an order that mirrors from one item to the next, the arm names hidden until the
end — scores each with the rubric, picks the right one, and concludes: whether each
expectation was met, whether the criterion held, and the verdict. **The API refuses the
person's part** (approving, grading, marking expectations, concluding) and names the web:
an experiment where whoever ran the arms grades it proves nothing.

**Its states carry that split.** `disenada` is the session's proposal; `aprobada` is the
person **fixing the design** — hypothesis, criterion, sample, rubric and expectations stop
accepting changes; `corriendo` is the session leaving outputs, links and cost per arm;
`calificando` is the simulation **waiting for the person** — all outputs are in; `concluida`
is her verdict. The server charges at every door: running requires approval, moving to
`calificando` requires every output, and the person's fields answer 400 over the API.

**Grading is done on the web, item by item.** The simulation's page shows a band when it
waits for you; the grader walks you through the sample: both outputs side by side, the
rubric with its anchors under each, which one is right at the foot, and the close at the
end. Whether the total favours an arm is derived from what you scored — including
criteria where lower is better, which the rubric declares.

**Registering one and running it** — the session's doors, the same as the owner's:

```bash
$API -p <project> simulacion <thread> <<'JSON'
{"titulo":"…","hipotesis":"what we believe will happen",
 "criterioExito":"metric, threshold and what disqualifies — written BEFORE running",
 "brazos":[{"clave":"A","nombre":"the proposed path","comoCorre":"model and mechanics"},
           {"clave":"B","nombre":"today's path","comoCorre":"model and mechanics"}],
 "muestra":[{"clave":"readme","nombre":"engine/README.md","queEs":"what verifiable fact it holds"}],
 "rubrica":[{"clave":"fidelity","nombre":"Fidelity","escala":{"min":1,"max":5},"mejor":"alto","ancla":"what each value deserves"},
            {"clave":"invented","nombre":"Invented facts","escala":{"min":0,"max":5},"mejor":"bajo","ancla":"each claim the code contradicts"}],
 "esperados":[{"texto":"verifiable expectation"},{"texto":"verifiable expectation"}],
 "cuerpo":{"en":"# The design\n\n## The judge\nthe person, blind, on the web\n\n## What disqualifies\n…"}}
JSON
# the person approves on the web — then:
$API -p <project> correr <id> "where it runs"               # → corriendo (400 without approval)
$API -p <project> salidas <id> <<'JSON'
[{"brazo":"A","item":"readme","texto":"what A produced for readme, whole, in markdown"},
 {"brazo":"B","item":"readme","texto":"what B produced for readme"}]
JSON
$API -p <project> brazos <id> <<< '[{"clave":"A","enlaces":{"compare":"https://…"},"consumo":{"preciosDe":"YYYY-MM-DD","modelos":[…]}}]'
$API -p <project> faltan <id>                               # which arm/item pairs still lack an output
$API -p <project> lista <id> "all outputs are in"           # → calificando (400 naming missing outputs)
# … the person grades on the web …
$API -p <project> calificacion <id>                         # what she decided: matrix, choices per item, expectations, verdict
```

`item simulaciones <id>` returns the grading matrix derived from what the person scored —
the mean per arm and criterion, items chosen per arm, the normalised total — plus each
arm's cost and the run's dates. Nobody writes the matrix by hand.

## The Consultation — the human in the loop

When a session reaches decisions that belong to the person — several points to read
calmly, each changing what a PR writes, a vocabulary, a key, a path between two — it
writes a **consultation** in the thread instead of a list in the chat. Each **point**
carries its title, **what changes** with each answer, the live **options** when there is
more than one, and **what the session would do**; the person answers under each one **on
the web**, with an input and a save button. The consultation is born `abierta`, moves by
itself to `contestada` with the last answer, and the session moves it to `aplicada` once
it took the answers — decisions to the book with the answer as verdict, a round written.

```bash
$API -p <project> consulta <thread> <<'JSON'
{"titulo":"The seven changes to the record: what goes in",
 "cuerpo":{"en":"# The context\n\nWhere the points come from…"},
 "puntos":[{"titulo":"The key of each record",
            "queCambia":"Today it is the route slug plus the tour slug; a rename orphans the record.",
            "opciones":[{"titulo":"Tour.id","implica":"the permanent reference the contract declares"}],
            "propuesta":"Tour.id — the three fronts agree."}]}
JSON
# … the person answers on the web; the consultation moves to «contestada» by itself …
$API -p <project> contestadas            # the ones fully answered, ready to apply
$API -p <project> respuestas <id>        # point by point: what was asked, proposed and answered
$API -p <project> aplicar <id> "round written · three decisions to the book"   # → aplicada
```

The answer belongs to the person: `respuesta` and the `contestada` state return 400 through
the API, naming the web. An answered point is never rewritten — what changed is a new point.

## Planning — the same gesture in every project

**Every piece of planning ends as a logbook plan, hanging from its thread.** The method
is one and it lives here: whichever project you plan in, planning is this same gesture
through the same doors.

**Where it hangs is settled first.** List the areas with their live threads
(`$API areas`) and ask the user which one the plan joins — the plan is theirs, and so is
the topic it belongs to. When no thread hosts the topic yet, offer to open one
(`$API abrir-hilo`, with its brief) and the plan is born inside it.

**The name fits in one phrase of up to 60 characters and stands on its own** (see *Writing
entries* above): its `brief` says what it is about.

**The plan comes out of what was already discussed.** A title that states the conclusion,
a `cierraEn` saying where it closes — the door demands it: without a close there is no
plan — and a body carrying the reasoning the conversation produced. Write it with
`$API plan <thread>` and finish the gesture by handing the user the item's address, so
they can keep reading it in the web app. The tie-break between types is the standing one
(see *Plans* above): understanding left asks for an analysis, executing asks for a plan,
choosing between exclusive paths asks for a decision.

**Claude Code's plan mode (`/plan`, shift+tab) is the harness's working mode** for
thinking a change through before touching it; the plan it produces is recorded through
this same gesture — what was thought out hangs from its thread and outlives the session.

```bash
$API -p <project> areas          # where it hangs: the areas with their live threads — ask BEFORE writing
$API -p <project> plan <thread> <<'JSON'
{"titulo":"…","cierraEn":"the PR that brings it","cuerpo":{"en":"# How it gets solved\n…"}}
JSON
```

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
**flows** (end-to-end journeys, the project's integration tests) — plus the project's
**instructions** (`instrucciones`: how the job cycle runs here — where each session
stands, what gates a commit, how the PR goes out, how it is billed), as raw markdown
when the owner loaded them. They are project material: read them, and follow them
under the repo's own law. A decision taken
without reading it is taken blind. When you work with a piece or a term that has no
entry yet, add it — `$API anotar-pieza`, `$API definir` — while it's in front of you.
A stack piece also carries `documentacion` (the URL of its official docs, shown as a
link on its card) and `notas` (the basics you need to work with it: version, plan,
account, the limit that bites) — fill them in when you have them at hand.

**`$API accesos` lists the project's quick links**, each with the credential it carries:
the outside addresses you enter every day — the engine, the repo, the ticket board, the
design file. They belong to the project
and not to a thread, and the workshop keeps them one click away in the right-hand column.
Anote one you had to hunt for with `$API anotar-acceso <<< '{"nombre":"…","url":"https://…","nota":"staging"}'`
— it is upsert by slug, so fixing a URL that moved is the same call. When the place asks you
to sign in, `usuario` and `clave` go with it: the workshop keeps them folded under that link,
one click from the address they open. They are project material and are stored as such — in
the clear, visible to everyone inside the tenant — so what belongs here is the credential the
project team shares.

Full command list: `bitacora-api` with no arguments prints usage.
