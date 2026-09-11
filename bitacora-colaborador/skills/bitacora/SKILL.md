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
| `/bitacora sources` · `/bitacora what do we have on <topic>` | The source register: what the client handed over, how old each thing is and which one rules (see *The sources* below). |
| `/bitacora refresh the sources` · `/bitacora are the sources up to date?` | Fetches the live ones by their origin, compares the fingerprint and stamps the mirror (`refrescar`); the one it could not reach it names, with what to ask for (see *The sources*). |
| `/bitacora record this source <what arrived>` | Register it: its kind, where it is read from, who produced it, its date and its tags. |
| `/bitacora I just pulled <the source>` | Record the copy and move its date (`sincronizada`). |
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

## A thread holds EIGHT TYPES, each with its own door

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
| **Consultation** | the human in the loop: what the session asks the person, point by point; the person accepts, rejects or asks for more context on each recommendation ON THE WEB | its `queEs` —where the points come from and what happens with what is decided— and its points, each with what changes, the recommendation and its why | abierta · contestada · aplicada · descartada |
| **Visual Check** | what gets approved by LOOKING: the run of screens a session produced; the person approves each step ON THE WEB, comparing the before with the after | its `queEs`, the run it verifies, and its steps: each with the capture under judgement, how you get there, what to look at and the recommendation | abierto · contestado · aplicado · descartado |

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
headings, each with content below: `# Task`, `# The idea`, `# Destination`, `# Context`,
`# Pattern to follow`, `# Scope`, `# Out of scope`. Reaching `entregado` requires
`ficha.pr` and a `reporte` with seven sections: `## Done`, `## How it turned out`,
`## Evidence`, `## Decisions along the way` with content, and `## Frictions`,
`## To decide`, `## Pending out of scope`, which are always present and read "None" when
there was nothing to report — an absent or empty section is a 400, because a blank reads
as forgotten, not as answered. The door answers 400 naming everything missing at once,
with what each section states. **`## Evidence` is one line**: the checks that passed,
named, and the link to the review, where the detail lives — the door measures its visible
text, each link counted by its text, and bounces a longer one. **`## Decisions along the
way` puts the decision first**: each item is two sentences, what was decided in bold and
then why. On a round, the report gets a `## Round N` block on top with the sections one
level down (`### Done`, …); the door enforces the contract on that newest round. Its
sections split in two kinds: the ones of the round tell only what this round did (Done,
Evidence, Decisions along the way, Frictions), and the state ones are rewritten whole (How
it turned out, To decide, Pending out of scope say how the work stands TODAY).

**`# The idea` is the proposal, written as a proposal** — "the study would live in its
thread": the present tense belongs to git. It carries the box diagram and the vertical
sequence diagram when the plan adds a new path, and reads "None" for a rename or an
adjustment with no new mechanism. **`## How it turned out` is its mirror on delivery**:
the same explanation in the present tense, about what exists, with the diagrams redrawn
where the build departed from the idea. The page of a delivered plan reads as steps in
time — «Plan · Round 1 · … · Result» — and the Result opens by default with the chapter
«How the AI worked» on top and the current delivery below, folding «The idea» under «How it
turned out» — as it folds the round's request under Done and Out of scope under Pending
out of scope. Diagrams travel compiled, in
`diagramas`: whoever has the bitácora engine repo and
`d2` installed — normally the project owner — compiles them with its CLI (`npm run -s
diagramas < body.md`), and on delivery they add to the ones the item already has. Without
that access, write the section as prose alone: the door accepts it, and a `d2` code block
you leave in the text shows on the page as the code it is, until someone compiles it.

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
{"reporte":{"en":"## Done\n…\n\n## How it turned out\n…\n\n## Evidence\n<one line: checks green, guardian score, review verdict with its link>\n\n## Decisions along the way\n1. **<What was decided.>** <Why.>\n\n## Frictions\nNone\n\n## To decide\n…\n\n## Pending out of scope\nNone"},
 "diagramas":[],
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
carries its title, **what changes** with each decision, the live **options** when there is
more than one, and the **recommendation** with its **why** in a sentence or two; the person
**accepts** the recommendation in one click, **rejects** it saying what goes instead, or
**asks for more context** in one click when what is written is not enough to decide,
**on the web**. A point sent back for context returns to the session, which rewrites it
with what was missing (`puntos <id>`, by its id) and asks it again; the request stays on
the point as a record. Keep it brief and clear: what is needed to decide, nothing more. The consultation IS its
points: its `queEs` says in a sentence or two where they come from and what happens with
what is decided, and it is all the context the person reads before the first point. The consultation is born `abierta`, moves by
itself to `contestada` with the last answer, and the session moves it to `aplicada` once
it took the answers — decisions to the book with the answer as verdict, a round written.

```bash
$API -p <project> consulta <thread> <<'JSON'
{"titulo":"The seven changes to the record: what goes in",
 "queEs":"The record decisions that came out of the reviews; with the answers the next round gets written.",
 "puntos":[{"titulo":"The key of each record",
            "queCambia":"Today it is the route slug plus the tour slug; a rename orphans the record.",
            "opciones":[{"titulo":"Tour.id","implica":"the permanent reference the contract declares"}],
            "propuesta":"Use Tour.id.","porque":"The permanent reference the contract declares; the three fronts agree."}]}
JSON
# … the person answers on the web; the consultation moves to «contestada» by itself …
$API -p <project> decidido               # what the person already said and the session has to take: fully decided ones, and points that asked for context
$API -p <project> contestadas            # the ones fully decided, ready to apply
$API -p <project> respuestas <id>        # point by point: the recommendation, accepted, rejected or sent back for context, and the comment
$API -p <project> puntos <id> <<'JSON'
{"puntos":[{"id":"p2","queCambia":"…what was missing, written so it can be decided from this alone…","porque":"…"}]}
JSON
$API -p <project> aplicar <id> "round written · three decisions to the book"   # → aplicada
```

The answer belongs to the person: `respuesta` and the `contestada` state return 400 through
the API, naming the web. A decided point is never rewritten — what changed is a new point;
the point that asked for more context is the deliberate exception, because rewriting it is
how the request is answered.

## The Visual Check — what gets approved by LOOKING

**A branch that changes what the end user SEES needs the owner to approve what they see**,
and that is not decided by reading. The consultation is the door for what is decided by
reading; this is the door for what is decided with the eyes: an ordered **run of steps**,
each one carrying the screen under judgement, how you get to it, and which run of the system
that moment belongs to. The decision is the consultation's —accept with one click, reject
saying what goes instead, or ask for more context—; what it adds is what makes an image
judgeable.

| Field of the step | What it is |
|---|---|
| `titulo` | the screen or the moment, in a few words |
| `despues` | **the capture under judgement**: the screen as it ends up with the change. Always there |
| `antes` | that same screen on the base branch. **Always there when the screen already existed**, also when the check approves what ships in a release: without it the page marks the screen «New screen». **Empty only when the step DEBUTS the screen**, which turns the question from «did it improve» into «is it right as it is» |
| `origen` | the screen you come from, with the control you tap marked on it |
| `gesto` | what you tapped to go from `origen` to `despues` — «tap Discount» |
| `queCuenta` | **what to look at, from the seat of the user who uses that screen**: their situation, what the screen shows them, what changed for them and the question the approver decides (how to write it, below) |
| `propuesta` + `porque` | the session's recommendation and its reason, in one phrase |
| `flujo` | the slug of the run that moment belongs to |
| `dispositivo` | `escritorio` or `celular`: which device the captures come from, because it decides HOW the page compares them — side by side for phone captures, and for desktop ones stacked in the same place, with a Before and an After button to pick which one shows. The page infers it from the image when absent (landscape means desktop); **declare it when a desktop capture is full-page**, taller than wide, which would otherwise read as a phone |

**Captures go up first and the step names them by their path.** Each one enters through the
attachments door —one request per file, so a long check has no size ceiling— and `capturar`
returns each path: **no path is ever written by hand**, and the check's door verifies that
every one named exists as a file of that thread and is an image. A mistyped path comes back
as a 400 saying which, instead of showing up as a hole where the owner had to decide.

**The context is half the value: which screen, of which run.** The check declares the runs
it verifies in `flujos` and each step names its own in `flujo`; with a single run declared,
the step inherits it. The door requires it, because a screen that does not say which run it
belongs to makes the approver reconstruct it. **And the navigation is paid from the second
step on**: `origen` and `gesto` are always there except in the first, which you enter with
no previous gesture.

**What to look at is written from the seat of the user who uses the screen.** Whoever
approves judges the screen by putting themselves in that place, and `queCuenta` is what seats
them there. It carries four parts, in this order:

1. **The user's situation**: who they are, what they came to do and what happened before
   they got here.
2. **The screen, with what it says**: its texts and buttons as they appear. «Slider»,
   «card», «CTA» or a piece's internal name are words from the code.
3. **What changed for that user**, or what it solves for them if the screen is new.
4. **The question the approver decides**: what could be wrong from the user's side. A bare
   «check X» leaves them guessing what is being judged.

**The capture's technical trail goes to the «Evidence» of the plan's report**: the PRs, the
commits, the branch, the port, the paths, the device serial, the script or skill that
captured and how the test account was set up — including the provenance line a project's
capture skill produces. What every step shares, the device and the account, is said once in
the check's `queEs`, and when a step was captured on a different device, that device goes in
its `titulo`. **The test before uploading**: read it as the user looking over your shoulder;
every word that needs the repo to be understood gets rewritten.

Written from the code:

> The slider and the shortcut grid with the single scale (PR #122, #125), and the «You
> already have a 20% discount» warning because the 20 is already in the game. Check the
> four-column grid and the red warning. Captured with scripts/capture-step.sh: Galaxy S21
> (R58N12ABCDE), Metro on 8081 over the clone on master (66d7c1f).

The same step, written from the user:

> You are setting up a game that already has a 20% discount and went in to create a custom
> prize. You pick the percentage with the bar or by tapping one below —the same ones Discount
> offers—, and since the 20 is already in the game, it warns you in red «You already have a
> 20% discount». Is it clear how to pick, and does the warning tell you what to do?

| Desk | What it is | Who moves it |
|---|---|---|
| `abierto` | waiting for the person's eyes — or for the session, when what is left undecided asked for more context | it is born here |
| `contestado` | every step decided: the signal for the session | the server, with the last decision |
| `aplicado` | the session took what was approved: rejections become the next round of the plan, on the same branch | the session, with `aplicar-chequeo` |
| `descartado` | it stopped applying, with its reason | the session |

```bash
# 1. The captures go up and return their path: that is what the step names them by.
$API -p <project> capturar <thread> step1-origin.png step1-before.png step1-after.png
# → {"step1-origin.png":"<thread>/step1-origin.png", …}

# 2. The check, with its run and its steps.
$API -p <project> chequeo <thread> <<'JSON'
{"titulo":"The prizes step of the wizard, on a Galaxy S21",
 "queEs":"PR #212 rebuilds the prizes step of the sign-up wizard. Nine screens of the run, on an S21: what changed is the order of the fields and the summary at the foot.",
 "flujos":["<run-slug>"],
 "pasos":[
   {"titulo":"The wizard, on the data step",
    "queCuenta":"You are signing up your tour and just finished the data: from here you go on to prizes. The Continue button is now pinned to the foot, so you see it with the keyboard open. Can you find it without scrolling?",
    "despues":"<thread>/step1-after.png",
    "antes":"<thread>/step1-before.png",
    "propuesta":"Keep it pinned to the foot.",
    "porque":"On an S21 the button fell below the fold with the keyboard open."},
   {"titulo":"Prizes, with the new summary",
    "queCuenta":"You picked your prizes and at the foot you see how many you have: the summary now adds them up. Does the total read well, with Continue in sight?",
    "origen":"<thread>/step1-after.png",
    "gesto":"tap Continue",
    "despues":"<thread>/step2-after.png",
    "antes":"<thread>/step2-before.png",
    "propuesta":"Keep the summary as it is.",
    "porque":"The total reads in full and Continue stays in sight."}]}
JSON

# 3. … the person approves step by step on the web; the check moves to «contestado» by itself …
$API -p <project> visto <id>     # step by step: what was approved, what was rejected and with which comment
$API -p <project> pasos <id> <<'JSON'
{"pasos":[{"id":"p2","despues":"<thread>/step2-recaptured.png","queCuenta":"…what was missing to see…"}]}
JSON
$API -p <project> aplicar-chequeo <id> "round 2 written in the plan · two screens rebuilt"
```

**When you open a check and not a consultation.** The check is for what is decided with the
eyes: a screen, a component, a run of the app. The consultation is for what is decided by
reading: a vocabulary, a key, a path between two. One plan can open both, and each goes
through its own door.

Captures come from wherever the session works —Playwright on web, of the visible screen and
at double density (`deviceScaleFactor: 2`) so the small print reads sharp at 100% in the
viewer; the device or the simulator on mobile—; the type is indifferent to which of the two
produced them. The
decision belongs to the person and enters through the web, same as the consultation: a step
already decided is never rewritten, and the one that asked for more context is the
deliberate exception, because recapturing it is how the request is answered.

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
`$API plan <thread>` and finish the gesture by handing the user the `enlace` the response
returns — the item's full address — so they can keep reading it in the web app. The
tie-break between types is the standing one
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

`$API contexto` returns everything that describes how this project works: the
**domain** (`dominio`: what the client makes a living from, in THEIR words — what they
do, what they sell, to whom, and what sets them apart), the **glossary** (what each word
means HERE, and whose voice it is — the client's vocabulary wins), the **stack** (each
piece with its responsibility, its level and what it is built with), and the **flows**
(end-to-end journeys, step by step, the project's integration tests), the **sources**
(`fuentes`: what the client handed over, with how old each thing is and which one rules)
— plus the project's
**instructions** (`instrucciones`: how the job cycle runs here — where each session
stands, what gates a commit, how the PR goes out, how it is billed), as raw markdown
when the owner loaded them. They are project material: read them, and follow them
under the repo's own law. A decision taken
without reading it is taken blind.

**The domain and the glossary are two different things.** The domain is the BUSINESS; the
glossary is how each thing in it is named. Read the domain first: the stack reads
differently once you know which business it holds up.

When you work with a piece or a term that has no
entry yet, add it — `$API anotar-pieza`, `$API definir` — while it's in front of you.
A stack piece carries its `nivel` (`sistema` · `contenedor` · `componente` · `libreria`,
and `dentroDe` with the slug of the container it lives in — a library belongs inside the
service that uses it, not beside it), `tecnologia` (what it is built with: «Node · GraphQL
· Fargate»), `documentacion` (the URL of its official docs, shown as a
link on its card) and `notas` (the basics you need to work with it: version, plan,
account, the limit that bites) — fill them in when you have them at hand.

**A flow IS its steps.** Each one carries `que` (what happens, in a sentence anyone
understands without knowing how it is built — the only required field), `etapa` (the stage
that groups consecutive steps), `actor` (who triggers it), `pieza` (the stack slug that
acts) and `detalle` (the technical detail, folded away). The sentence is for the client and
the detail is for whoever builds it; both in the same row is what keeps a journey from
having to pick one of the two readers.

### The sources — what the client handed over, and which one rules

A **source** is what came from outside: a sheet the client keeps editing, a PDF, a Slack
channel, a Figma file, a board. It is registered once at PROJECT level and its `tags` make it
show up in every area and every thread it names — one channel talks about search, the CMS and
the infrastructure in the same week, so hanging it off a single thread hides it from the
other two.

What the card has to be enough for is **judging the material WITHOUT opening it**: which side
it comes from, how old it is, whether whoever produced it keeps editing it, and whether our
copy is current. Those four decide whether what it says still holds.

| Field | What it carries |
|---|---|
| `nombre` · `queEs` | What it is called and what it answers, in one sentence. Bilingual, like every card; `queEs` is left out when the material arrived with its name as its whole card |
| `clase` | What kind of thing it is: `documento` · `hoja` · `canal` · `tablero` · `diseno` · `pagina` |
| `procedencia` | Where it is read from: `google-sheets` · `google-docs` · `slack` · `jira` · `figma` · `miro` · `email` · `drive` · `mano` |
| `producidaPor` · `lado` | Who wrote it, and which side it is on: `cliente` · `equipo` · `nuestro` · `proveedor` |
| `fecha` | **The source's own date** (`AAAA-MM-DD`): when its author produced or sent it — not when you recorded it |
| `vigencia` | `viva` while its author keeps editing it; `fechada` when it is a snapshot of one moment |
| `superadaPor` | The slug of the one that replaced it: it gets marked and stays, like a glossary word |
| `url` · `ref` | Where it lives outside, and the handle it is refreshed by (the doc id, the channel id, `fileKey/nodeId`) |
| `espejo` | Our copy: its attachment, when it was taken, and the fingerprint of its content |
| `tags` | Free slugs — areas, threads, stack pieces, words: this is what makes it appear in each area |
| `nota` | What you need to know to use it: the quota, the sharing permission, the sheet that matters |

**Which one rules is DERIVED from the order**, so it cannot go stale: the client's live one
rules over a dated one, among dated ones the newest rules, and a superseded one says so,
dimmed at the foot. No field declares precedence — it comes out of vigencia, side and date.

```bash
$API fuentes                    # the whole register, in that order
$API fuentes algolia            # the ones on a topic: the slug of an area, a thread or a stack piece
$API fuentes "" hoja            # sheets only
$API fuente attribute-register  # one whole, with its mirror
$API por-sincronizar            # the live ones whose copy went stale, with their handle and fingerprint
```

**Before deciding anything on a topic, this answers what material exists and which one
rules** — which is why it travels inside `$API contexto`. A claim resting on a `nuestro`
source is a claim about our own draft, not about the domain: `lado` is what keeps that
distinction, the same one a glossary word's `voz` keeps.

```bash
$API anotar-fuente <<'JSON'
{"nombre":"The attribute spreadsheet",
 "queEs":"The register where the client sets the scope attribute by attribute: what gets tagged, which system it comes from, and its search configuration",
 "clase":"hoja","procedencia":"google-sheets","producidaPor":"Fran McCann","lado":"cliente",
 "fecha":"2026-09-08","vigencia":"viva",
 "url":"https://docs.google.com/spreadsheets/d/1Qc.../edit","ref":"1Qc...",
 "tags":["algolia","modelo"],
 "nota":"the sheet that matters is 1-attribute-register"}
JSON
# upsert by slug that writes the WHOLE card: one recorded again without `tags` loses them
# —and drops out of «The sources» of its area—, without `vigencia` goes back to `fechada`
# and without `lado` to `cliente`; the mirror is kept. A field is corrected with `editar-fuente`.
```

**The `nota` is what you need to know to USE it** —the quota that blocks it, the permission
that is missing, which tab of the workbook matters—, and the register reads
as a list: whatever goes there shows up as one more line on every row that carries it. What
the row already says —that the date came from the last refresh, how precisely it is known,
that the first refresh will move it— is read off the mirror line, which carries the day of
our copy next to the source's own date. With none of that to tell, a source is recorded
without a `nota`.

```bash
$API editar-fuente attribute-register <<< '{"sumarTags":["plp-taxonomia"],"fecha":"2026-09-09"}'
# `tags` replaces the whole list; `sumarTags` adds to the one already there
# {"superadaPor":"attribute-register"} marks one replaced · {"superadaPor":""} unmarks it
$API borrar /api/fuentes/<slug>   # the one recorded by mistake: leaves with its mirror (owner only)

$API sincronizada attribute-register ~/Downloads/_source.xlsx 2026-09-09
# uploads the copy, computes its sha1 and stamps the mirror; with the date it also
# moves the source's own date — the live one whose original was edited
```

The mirror lives where the files already live —the private bucket, served with a session—
and its fingerprint is what says whether the original changed without opening it. A live
source whose copy is more than **a week** old shows up in `por-sincronizar`, and the
workshop says so on its row.

**Refreshing the live ones is one command, and `/thinking` runs it in its step zero**: the
session that thinks refreshes what went stale on start and records the new source when it
shows up. Each project learns to sync with what it already has: the register is its list
—every live source with its `procedencia` and its `ref`— and the recipe per origin lives
here, once.

```bash
$API refrescar                     # the live ones awaiting refresh: fetch, compare the fingerprint, stamp
$API refrescar attribute-register  # that one, even if up to date
# closes with one line: how many up to date, how many changed, which ones unreachable, which ones go through their skill
```

| Origin | How it refreshes | When it fails, what to ask for |
|---|---|---|
| `google-sheets` · `google-docs` | The document's public export by its `ref` (the sheet's xlsx, the doc's text), no credential. The fingerprint says «up to date» or «changed»; when changed, it uploads the copy under the previous mirror's name and the date moves to today | Google answers a page instead of the file: the document's owner has to share it **by link** —«Anyone with the link», as viewer—. The line says so in those words, and you ask whoever produced it |
| `slack` · `jira` · `figma` | The profile skill that already holds the access (`/slack`, `/jira`, `/figma` within its quota), then `sincronizada <slug> <file>` | The skill says what it lacks: the workspace token, the site's API token, a View seat on the file. You get it there and come back |
| `email` · `drive` · `miro` · `mano` | A person: a dated source refreshes when its author sends another one, which enters as a new source superseding the previous | — |

**And a new source is recorded from the thread where it appeared.** A link to a sheet, a
document, a channel or a file that arrives while a topic is being thought enters with
`anotar-fuente` carrying the tags of its area and its thread, and `refrescar <slug>` takes
its first mirror: the area is a tag, so tying it is naming it.

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
