---
name: bitacora
description: "Work with the project logbook (bitácora) as a collaborator — read the project's context, write dated entries, record decisions —made, or open as a consultation for whoever decides them—, and keep the shared record of what happened and why. Use when the user mentions the bitácora / logbook, wants to record something that happened, log a finding or a decision, check what was decided, read the project context, or asks what the logbook says about a topic."
---

# /bitacora — the project logbook, as a collaborator

The **bitácora** is the project's shared workspace: the place where complex topics get
analyzed, decisions get recorded one by one — each with its frame, made with its verdict or open for whoever decides it — and the day-to-day record of what happened
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

**And if step zero prints «⚠ Adaptación pendiente», the logbook's model changed and this
project's material still carries the previous shape.** The notice says what changed and
which gesture adapts it. Tell the person in one line and leave the call to them: adapting
means reclassifying the project's own material, and that belongs to whoever owns it.

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
4. **Present a two-line pulse and ask.** Name what's actually alive — the areas at the
   front, the pending plans (that is where work resumes), the freshest thing that happened
   — and ask what they'd like to do: resume a plan, write an analysis, log something that
   happened, record a decision that was made, or just read. For example: *"The board is
   open in your browser. Two areas are moving — search and pricing — with three pending
   plans between them. What would you like to dig into?"*
   Always offer from the REAL board, never a generic menu.

From there, conversation: answer questions from the logbook's content (search, areas,
documents, decisions), record what they tell you as entries, record decision points when
a real trade-off gets settled. You are the project's memory speaking.

## The rest of the routing

| The user says | What you do |
|---|---|
| `/bitacora <area>` · `/bitacora area <name>` | Read that area: `$API area <slug>` (its state and its place) and `$API subarea <place>` (its pending plans, latest entries, decisions and documents). The argument may be an alias — `marketing` reaches Commercial, `posicionamiento` SEO. |
| `/bitacora <area> <something that happened>` | Write the dated entry (see *Writing entries* below). |
| `/bitacora <area> decision <what was decided>` | Record the point — ALREADY made — in the area's decision book, with its full frame and its verdict, or the server rejects it. What still waits on someone is a consultation (see *The Consultation*). |
| `/bitacora <area> we need to <something to do>` | Open the plan: how it gets solved and where it closes. |
| `/bitacora plan <topic>` | Build the plan out of what was just discussed: ask FIRST which area it joins, require where it closes, and write it into the area (see *Planning* below). |
| `/bitacora what is left to do` | The project's execution front. |
| `/bitacora sources` · `/bitacora what do we have on <topic>` | The source register: what the client handed over, how old each thing is and which one rules (see *The sources* below). |
| `/bitacora refresh the sources` · `/bitacora are the sources up to date?` | Fetches the live ones by their origin, compares the fingerprint and stamps the mirror (`refrescar`); the one it could not reach it names, with what to ask for (see *The sources*). |
| `/bitacora record this source <what arrived>` | Register it: its kind, where it is read from, who produced it, its date and its tags. |
| `/bitacora I just pulled <the source>` | Record the copy and move its date (`sincronizada`). |
| Something that matches nothing | It's probably a topic whose area you have not spotted — list the areas and ask, rather than failing. A good idea that waits for its moment goes to the area of its topic with the priority `algun-dia` («someday»). |

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
$API -p <project> tablero       # the board: every area with its pieces, and the goals apart
$API -p <project> areas         # the project's areas
$API -p <project> area <slug>   # ONE area: its name, its place, its `estado` —where that world stands today— and its `objetivos`, the open goals that cross it
$API -p <project> subarea <place> # the area's place: its pieces, entries, decisions and documents
$API -p <project> estado <slug> # the area's state in full: the current snapshot with its sections, its milestone and its chain of earlier ones
$API -p <project> libro <slug>  # the area's book: what was decided and done there, newest first · `libro objetivo <id>`, a goal's
$API -p <project> buscar "x"    # search across everything you can see
$API -p <project> documento linea <place> <doc>   # a document's raw markdown
```

The project resolves from your working directory when it sits under a workspace root —
`~/ProyectosDev-Local`, plus any `raiz=<path>` line in `~/.config/bitacora/config.local`,
which is how you add wherever your own projects live. A folder named differently from its
project is translated with an alias — `$API alias <folder> <project>` adds it, and
`$API alias` lists the roots, the aliases and the projects with a key without showing any
key; a numbered copy (`acme-2`, `acme3`) resolves to `acme` by itself. Outside every
root, `-p <slug>` sets it explicitly and always works. `$API proyecto` says which one
resolved.

Writes take a JSON body on stdin:

```bash
$API -p <project> entrada <area> <<'JSON'
{"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
JSON

# A decision goes in whole or not at all — the server rejects one without its frame. With
# its verdict it is born made; without it, it is born open —a consultation— and names who
# decides it (`decide`, see *The Consultation*):
$API -p <project> decision <area> <<'JSON'
{"titulo":"…","veredicto":"what was decided",
 "bloquea":"what was blocked while this stayed undecided",
 "opciones":[{"titulo":"…","implica":"what choosing it costs"},
             {"titulo":"…","implica":"what choosing it costs"}],
 "recomiendo":0,"recomendacion":"why that one and not the others",
 "cierraEn":"…","cuerpo":"…"}
JSON

$API -p <project> corregir <id> <<< '{"veredicto":"…"}'                 # a decision, through its own door
$API -p <project> corregir analisis <id> <<< '{"cuerpo":{"en":"…"},"diagramas":[…]}'   # any other piece
$API -p <project> mover analisis <id> <<< '{"estado":"descartado","nota":"why it stopped holding"}'
```

## An area holds ELEVEN TYPES, each with its own door

An **area** is a world of the project — search, the engine's infrastructure, the contract —
and the PLACE where its work lives: what hangs from it has a type. A topic of a few weeks is
a piece of the area it belongs to. The type is what sets its door, its desks and its
colour:

| Type | What it is | What opening it costs | Desks |
|---|---|---|---|
| **Analysis** | what was understood about a topic | its body | escrito, or descartado when it stopped holding: it is material you read |
| **Plan** | how something gets solved — strategy AND execution; it also carries a dispatched job | its body and where it closes | pendiente · encargado · en-curso · entregado · hecho · descartado |
| **Bug** | a defect found while doing something else | its body, with What happens · Where · How to reproduce | abierto · arreglado · descartado |
| **Client-Report** | what goes to the client, from the draft on | its body | preparacion · aprobado · entregado |
| **Decision** | a trade-off with its analysis: made, or open and waiting on whoever decides it | the whole frame, and its verdict or who decides it (`decide`) | abierta · decidida · aplicada · descartada — `resuelta`, the inherited one, reads as aplicada |
| **Simulation** | the experiment before adopting a change: the session runs the arms, a person grades | its body, the hypothesis, the success criterion, two arms, the sample and the rubric | disenada · aprobada · corriendo · calificando · concluida · descartada |
| **Consultation** · **Client Question** | something that holds something up: the OPEN decision, with who decides it —the person, the client or the session—; several gather in a BATCH the person answers in one go ON THE WEB, and the batch that is a client question gathers what the client decides (§The Consultation) | the batch, its title and its `queEs` —what it holds up and what happens with what is decided—; each decision, its whole frame and its `decide` | the batch's, read from its decisions: abierta · contestada · aplicada · descartada; the client's, por-preguntar · preguntada · respondida · aplicada · descartada |
| **Visual Check** | what gets approved by LOOKING: the run of screens a session produced; the person approves each step ON THE WEB, comparing the before with the after | its `queEs`, the run it verifies, and its steps: each with the capture under judgement, how you get there, what to look at and the recommendation | abierto · contestado · aplicado · descartado |
| **Jev Question** | a semantic judgement that runs at commit, with its evidence: the bench over the red, the green and the approved, and its real runs with the signer's verdict on each red | its body, its `queEs`, its `clave` —the id in the repo's rule— and the `pregunta` | propuesta · en-banco · informando · frena · retirada |
| **Goal** | what several pieces pursue TOGETHER —the back end, the web and the app of one feature—: it belongs to the project and is born with no place; each plan, bug or analysis names it in its `objetivo` field, and its page lists what pursues it with the progress (§The Goal) | its body with three sections: What we're after —no code, within the ceiling of «What changes»—, Why and When it's achieved | abierto · logrado · descartado — closing it takes its `nota` |

```bash
$API -p <project> analisis <area> <<'JSON'
{"titulo":"…","queEs":"what the reader will find","cuerpo":{"en":"# …"}}
JSON
$API -p <project> plan <area> <<'JSON'
{"titulo":"…","cierraEn":"the PR that brings it","prioridad":"alta","cuerpo":{"en":"# How it gets solved\n…"}}
JSON
$API -p <project> bug <area> <<'JSON'
{"titulo":"…","prioridad":"critico","cuerpo":{"en":"# What happens\n…\n\n# Where\n…\n\n# How to reproduce\n1. …\n2. …"}}
JSON
$API -p <project> client-report <area> <<'JSON'
{"titulo":"…","ficha":{"For":"who receives it"},"cuerpo":{"en":"# …"}}
JSON

$API -p <project> de-la-subarea <place> planes      # a place's plans, with their bodies
$API -p <project> tipo planes                 # every plan in the project
$API -p <project> abiertos bugs               # the bugs still open, across areas: critical ones first
$API -p <project> abiertos bugs critico       # only the critical ones still open
$API -p <project> item planes <id>            # one whole: its body, its place (`hilo`) and how it moved
$API -p <project> mover planes <id> <<< '{"estado":"hecho","nota":"how it closed"}'
$API -p <project> mover planes <id> <<< '{"hilo":"the-area-it-belongs-to"}'   # move it to its area (slug or alias)
$API -p <project> mover planes <id> <<< '{"tambienEn":["mobile"]}'   # also visible from other areas: the whole list, [] for one place
$API -p <project> fijar analisis <id>         # pin it to the top: the piece its area opens with
$API -p <project> soltar analisis <id>        # back to the work order
```

**A PIECE CAN BE SEEN FROM MORE THAN ONE AREA.** It is one single element: it lives in the
area where it is written —its address, its number, its screenshots— and `tambienEn` names
the other areas it is also seen from. The menu, each area's page, timeline and state show
it as their own. The test is the reader's question: does whoever opens that area need to
see this piece? A pricing plan that changes the whole app lives in Commercial and is also
seen from Mobile. Declare it in the same act you choose the area (`"tambienEn":["mobile"]`
when opening it), with the same names a route takes —slug or alias—.

**THE PIECE AN AREA OPENS WITH IS PINNED TO THE TOP.** An area orders its pieces by the
work — what is being built on top, what closed at the foot — and that order answers what is
being done right now. The other question, which of these pieces tells what the area is
about, is what pinning answers: it is usually an analysis, material that gets read and
therefore sits mid-list under every plan someone moved. Pinned, it comes first on the area
page and on its branch of the menu, marked `▲` in the margin, because the top of a list
also holds whatever was touched a minute ago. Between two pinned ones, the latest wins. The
field travels in the generic patch too (`{"fijado":true}`) and comes back in the place and
item reads, and the person pins from the web with the **«▲ Pin to top»** button in the
right-hand column of the piece's own page.

**A NEW ANALYSIS IS BORN PINNED.** A freshly written analysis is the one the person comes
looking for, and its place in the work order is mid-list. Opening one puts it first on the
area page and on its branch of the menu, marked `▲`, and the answer says so
(`"fijado": true`); several written in the same batch stay together on top, the latest
first. **Lowering it is the person's gesture**: they unpin it from its page once they have
read it. The session unpins one when the person asks (`soltar analisis <id>`).

**A piece is written naming its AREA.** Before writing, ask which area this is the analysis
(or plan, or bug) of, and name it: `$API plan <area>`, `analisis <area>`, `bug <area>` —
the server hangs the piece from the area's place, and creates the place when it is
missing. **When the topic is a world of its own that no area holds, open the area**
(`$API abrir-area <<< '{"nombre":"Sign-up"}'`) and say so in your report. A piece left in
the wrong area moves with `mover` and `hilo`, naming the right one: it lands after the ones
already there and keeps its address unless it clashes.

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
saying exactly that. A person can also close it from the bug's page, with **Resolve** (to `arreglado`, with a line saying what happened) and **Ignore** (to `descartado`, one click): the move lands in the history with its note, so a session coming back to the bug reads who closed it and why.

**Every bug has a `prioridad`, in the words of defects: `critico`, `mayor`, `menor` or
`algun-dia`** — critical, major, minor, the classic Jira scheme: the order it is taken in among
the bugs at its same desk, and last the «someday» bug that waits for its moment in the area of
its topic. A bug that declares none is `mayor`, and every read serves it with that value.
**An open critical bug HEADS every list that shows it**, ahead of the work order: on the
area's page, in the menu, on the by-type axis —where the critical ones open the page in their
own «Critical» batch across areas, with a «Critical» filter next to the tabs— and first in
`abiertos bugs`. It is declared when opening the bug if you know it, and corrected like the
plan's, in any desk: `corregir bugs <id> <<< '{"prioridad":"menor"}'`.

**The Simulation is the experiment before adopting a change**, and the run produces while
the grading decides: the session designs it and runs the arms over a sample, leaving what
each arm produced; a person approves the design, grades the outputs blind on the web,
picks the right one and concludes. See *Simulations* below — grading is a collaborator's
job as much as anyone's.

**The decision enters, gets corrected and moves through its own door** — `decision`,
`corregir`, `decidir` and `aplicar-decision`. It is born with its whole frame, so a generic
door that skipped it would be the shortcut a passing thought takes into the book. What
still needs deciding is a **consultation** —an open decision, with who decides it—, and the
work of getting to its frame is a plan.

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
$API -p <project> entrada <area> <<'JSON'
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
piece's title and its body are born together and in the same language. It defaults to the
project's first declared language; name it when you write in another one:

```bash
$API -p <project> entrada <area> <<'JSON'
{"escritoEn":"en","tipo":"hallazgo",
 "titulo":{"en":"Facets are counted per record","es":"Los facets se cuentan por registro"},
 "cuerpo":{"en":"# …","es":"# …"}}
JSON
```

**To READ in your language, the `-i` flag.** It applies to everything the command brings
back: the board, an area's place with its chronology, the glossary, the stack, the flows and
the search.

```bash
$API -p <project> -i en tablero     # the whole board, in English
$API -p <project> -i en contexto    # the triad, in English
```

Without the flag you get the project's own layer, and whatever lacks the language you asked
for falls back to its original — honest material in the language it was written in, never a
blank screen.

## The unit is the area

An **area** is a world of the project — search, the engine's infrastructure, the contract,
the commercial side — and the place where its work lives: it is still there once today's
work is done. Its dimensions: its **pieces** (the eleven types above), the **decision book**
(what was decided, one point at a time), the **chronology** (dated entries: what
happened, when, why in that order), its **state** (where it stands today) and its **book**
(what was decided and done there, newest first). A topic of a few weeks is a **piece** of its area.

**The area's page is where the work is read**: its state, its pieces, its attachments, its
decisions, its timeline and its access. The left menu is the list of areas, with each
area's pieces hanging straight from it, and a piece's route reads Home › Area. An area with
more than one place belongs to a project whose `sin-subareas` adaptation is pending: it is
read with its sub-areas, and the owner folds each one into its area
(`fusionar <sub-area> <area>`: its pieces keep the sub-area's name and brief as their
topic) or raises it to an area of its own (`ascender <sub-area>`).

**Four areas exist in every project**, even empty, called the same in all of them, with
their name and their existence fixed (renaming or deleting one answers 400 `areaObligada`):
**Commercial** (`comercial`, alias `marketing` — a project that already had `marketing`
keeps it as its Commercial, and both names lead there), **QA** (`qa`: what is tested and how), **SEO** (`seo`, alias `posicionamiento`: how the project gets found on Google, on Bing and in the AI assistants that answer by citing) and **Harness**
(`harness`: the tooling the project works with, one harness for every account —each
account's Harness area keeps its reports, and the centre, the owner's `bitacora` tenant, keeps
the analysis, the snapshot and the plans that improve it—). Whoever arrives at any project knows
without asking where selling, testing, being found and the tooling go. **What waits for its
moment lives in the area of its topic with the priority `algun-dia`** («someday», the last
word of the plan and of the bug): it hangs at the foot of its list and the area's count leaves
it out. Nice To Have was retired: its place is read while it holds something open, and writing
there answers where the new goes. A review leaves its results in two accumulators: what a
review finds travels as a finding with its fate, and what can wait lands in nit —read in «To
group» on the page of the area of the plan whose review left it— while what the process
learnt —each FIX, what did not hold— lands in Harness, «What reached the review». **The review of the session that builds is
a FIX loop; everything else piles up in harness and in nit, and gets processed when someone
opens the owner's /harness or /nit** —nit in the account, harness in the centre, which reads
every account. A review of another author's PR asks that author for
what breaks —each FIX with its Blocking row (a bug, a broken contract, security, data
integrity) and its ASKs, `al-autor`—; its style FIX is born `para-harness`, lands in Harness
and nowhere else, and harness turns it into a lint or a Jev question.

**And every area carries its state**: a snapshot of where that world stands today, read in
full on top of the area's page —its date, its milestone, the big picture, what happened since
and its sections, with «← Previous» to the earlier one— and with its history at
`/<project>/area/<slug>/estado`. It is a series of
snapshots and the latest one is read; each carries the milestone that produced it —a
relevant plan signed, a client decision, a source that moved the ground— and the earlier
ones are the history, walked one step back at a time with "Previous". **The body tells the
area's world**, from the broadest to the most specific, and the server requires its sections
in this order: `# Where we stand` (the big picture in a few sentences, without code), the
sixth section when the area carries one (below), and `# The map` (a `d2` drawing of the
pieces with their state, with its legend underneath). **The path of each piece of work lives
in its goal** (§The Goal): the order of its plans in its `# What's next`, and what is in
flight and what waits on others, derived on its page. **Snapshots written in the earlier
shape** carry `# In flight`, `# What's next` and `# Waiting on others` after the world, and
are read, corrected and painted with it; while the project's `caminos` adaptation is
pending, a snapshot that brings any of those headings is charged with that shape —with open
plans in the area, `# What's next` is their order, as in a goal, and `desde.planes` lists
the ones it does not name yet—. Once the project closes `caminos`, a snapshot that brings
any of the three answers 400 `caminoEnElArea`, naming each one.
**A snapshot is read whole every time it is written**, because a person reads it end to
end: each section fits its cap in visible characters —`# Where we stand` 500, `# The map`
400 (its legend; the drawing does not count), the sixth section 1200, and in the earlier
shape `# In flight`, `# What's next` and `# Waiting on others` 600 each, `# What's next`
with open plans 300 without its checklist items— and the whole snapshot fits the sum of its
sections' caps, text outside the sections included. A table counts as text; a drawing does not. Over a cap
the server answers 400 `seccionLarga` or `estadoLargo`, listing every section with what it
carries and what fits. It slims down by drawing what can be drawn, a checklist instead of
each table, dropping what closed or repeats, and moving what explains and lasts to an
analysis pinned in the area, linked from the snapshot in one line. **A new snapshot starts
from the area's live sources**: a live source tagged with the area whose copy is stale
answers 400 `fuentesSinRefrescar`, naming how to refresh it (`$API refrescar`, or its
skill and `sincronizada`); one that cannot be refreshed today —the Figma quota, missing
access— is declared in the body with its reason in one line,
`"sinRefrescar":[{"fuente":"<slug>","porque":"<why>"}]`, and stays on the snapshot
(declaring one that is up to date answers 400 `sinRefrescarDeMas`).
**QA's snapshot carries a sixth, fixed section right after `# Where we stand`:
`# How we test`** — what is tested, where each test lives, how it runs and what each layer
isolates, with its `d2` drawing —, required once the project closes its `areas`
adaptation; read it before testing a change. Harness carries its own sixth in the same
spot, `# How we work`, and SEO carries `# How we get found` —each surface where the project
has to show up (Google, Bing and the AI assistants that answer by citing), what each reads
from the site, what it understands of the project and how showing up is measured, with its
`d2` drawing—, required once the project closes its `seo` adaptation. Read it with `$API estado <slug>`; a new snapshot is taken at the close of an important
change (`$API escribir-estado <slug>`). **When that change is a signed-off plan, the session
that signs it off takes the snapshot**: a plan that changes its world's big picture is a
milestone, and the session takes the snapshot with that plan as its milestone and tells the
person in one line.

**The state says where a world stands today; its book, what was decided and done to get
there.** Every area and every goal has one, on its page next to the state
—`/<project>/area/<slug>/libro` and `/<project>/objetivo/<id>/libro`—, and it builds itself
from what settled and what was noted, month by month and newest first:

| Piece | Enters when | Its line says |
|---|---|---|
| Decision | it was decided —`decidida`, `aplicada`, or an inherited `resuelta`— | its title and its verdict; leads to its point |
| Plan | it was signed off (`hecho`) | its title and its summary |
| Bug | it was fixed | its title and the note it was closed with |
| Analysis | it was written | its title and its summary |
| Simulation | it concluded | its title and its summary |
| Client report | it was delivered | its title |
| Entry | it was noted | its type, its title and its text |

Each line carries the date it settled: the one of the history move that took it in there
—for a decision, when it was decided, even if it was applied later—, and the writing date
for an analysis and an entry. What is open reads in the state and
the menu, what was dropped in its list, and a superseded entry leaves the book. **The area's
book** gathers what settled among the pieces seen from its places, its decisions and the
entries written there; **a goal's book**, what settled among the pieces that name it —from
any area—, the decisions that name it and the entries that name it: **an entry takes `objetivo`** like any piece (§The
Goal). Whoever reads its page reads it, and a guest sees the lines seen from their places.
The menu's **Book** tag on the area's row, next to **Status**, leads there; so do the link in
the area's summary and, on a goal's page, the one under «What pursues it».

```bash
$API -p <project> libro <area>           # the area's book
$API -p <project> libro objetivo <id>    # a goal's
```

Each line comes with its `fecha`, its `clase` —`pieza` or `entrada`—, its `tipo` (the
piece's, or the entry's), its title, what its line reads underneath —`bajada` on a piece,
`texto` on an entry—, its `hilo`, its `area` and its `enlace`.

The API calls an area's place a `linea` — the collection and the `lineaSlug` field keep the
name they were born with — and the place usually carries the area's slug; `area <slug>`
names it, and a piece's read returns it as `hilo`. The commands that name a place
(`subarea`, `de-la-subarea`, `documento linea`, `superar`, `capturar`) take it that way;
`hilo` and `linea` are accepted as the same word as `subarea`.

## Writing entries — the craft

- `tipo` and `titulo` are required; the `cuerpo` is markdown, quick and raw. Useful
  sections: *Qué pasó* (what happened) · *Por qué se decidió así* (why this way) ·
  *Lo que se descartó* (what was discarded — the most valuable one).
- Common types: `hallazgo` (finding), `decisión`, `bloqueo` (blocker), `entrega`
  (delivery), `reunión` (meeting), `descarte` (discarded path), `incidente`.
- **Titles inform, stand alone, and fit in one phrase.** "Notes from Tuesday" says
  nothing: the title states the processed conclusion, so that reading it alone on the
  board you know what's inside. It names the topic in the words the topic is asked for —
  one leaning on another piece ("Case B: …") sends whoever opens it looking for case A.
  And the API measures it: **80 characters** for the title of a piece and of the day's
  entry, with the rule inside the 400. It can be short because the substance has its own
  fields — `queEs` and `cuerpo` on the item.
- **The writing test:** *can this be reconstructed from the diff, the issue tracker or
  an existing analysis?* If yes, don't write it. The logbook keeps what has no other
  owner: the discovery, the why, what blocked you, what was discarded and under what
  condition it comes back.
- **Dates are real.** An entry reconstructing a past event carries its real `fecha`
  (`"fecha":"YYYY-MM-DD"`); measurements typed from memory don't go in prose — name
  the fact in words instead.

## Decisions — made or open, and each one stands alone

**A decision is a trade-off recorded with its whole analysis**: already made, or open and
waiting on whoever decides it. The open one is **the consultation**: something that holds
something up (§The Consultation). It is read on its own and understood on its own, without
opening any other document — which is why it has its own page (`/<project>/punto/<id>`) and
why the server **demands its frame** when you record it, with its verdict or with who
decides it:

| Field | What it carries |
|---|---|
| `veredicto` | **What was decided**, in one sentence — what the record answers without opening the point. With it the decision is born made |
| `decide` | Without a verdict, who decides it: `fran` (the person), `cliente` (with its `pregunta` and `urgencia`, §The Consultation) or `sesion` (the session) |
| `bloquea` | What is held up while this stays undecided |
| `opciones[]` | Two at minimum, each with `titulo` and a **developed** `implica` — the server asks for real substance, because an option without its consequences is just a title |
| `recomiendo` | The position of the recommended option (`0` is the first) |
| `recomendacion` | Why that one and not the others, **with the full reasoning** |
| `cierraEn` | Where it closes: a PR, an entry in the client record, or nothing |
| `cuerpo` | What triggered the point and where the work is. **The longest of them all** — it is the analysis, and the server measures it |

Optional: `"tanda":"<id>"` adds it to a batch, `"objetivo"` names the goal it pursues,
`"flujos"` the runs it unblocks, and `"capturas"` the paths `capturar` returned when it is
decided by looking.

**The long fields carry a minimum length and the server says so when it rejects them.**
Don't write them with ellipses or leave them for later: a point is what someone reads two
months from now with none of today's context in their head.

A point without its frame gets a 400 naming what is missing, and an open one without
`decide` too (`sinQuienDecide`). That friction is the mechanism: the book used to fill with
points that were a passing thought with a number, because opening cost three sentences.

A point enters the book only when the trade-off was real: two live options and choosing
mattered. What a doc, a standard or the repo's law settles leaves no point — look it up
and write the answer. **And something still to DO is a plan, not a point** — that detour
is what filled the book. Work them **individually**: origin, position, verdict, one at a
time.

**Its cycle: open, decided, applied.**

| Desk | What it is | Who moves it |
|---|---|---|
| `abierta` | waiting on whoever decides it; the server serves whose hand it is in (§The Consultation) | born here without a verdict |
| `decidida` | carries its verdict and waits for the session that applies it | the answer that decides it, on the web; or the session, with `decidir` |
| `aplicada` | the session did what was decided, and its note says so | the session, with `aplicar-decision`; one recorded with its verdict is born here |
| `descartada` | the open one that stopped applying, with its note | the session, with `corregir` and its `estado` |

`resuelta` is the desk inherited from the earlier model and reads as `aplicada`. **The book
reads what was decided** —`decidida`, `aplicada` and `resuelta`—; the open one reads on its
page and in its batch.

```bash
$API -p <project> decidir <id> "<verdict>"                 # open → decidida: the one the session decides, or one that reached its verdict
$API -p <project> aplicar-decision <id> "<what was done>"  # decidida → aplicada
$API -p <project> corregir <id> <<< '{"estado":"descartada","nota":"why it stopped applying"}'   # open → descartada
$API -p <project> corregir <id> <<< '{"veredicto":"…"}'    # fixes what was decided, on a decided or applied one
```

`corregir` also fixes the frame or the text of a recorded point, and the frame never
degrades: once complete, the door demands it whole whenever one of its pieces is touched.
`cerrar` is the way out for INHERITED points left open or deferred under the earlier model —
it closes one stating its verdict (`$API -p <project> cerrar <id> <<< '{"veredicto":"…"}'`) —
and `diferir` answers with the current gesture.

A point is written short and self-contained, so someone reading it in two months
understands what was decided and why without any of today's context. References (PR
numbers, links) go in `cierraEn`. The verdict is dated in the point's history with your
name — that history is the project's "how we decided" view.

## Plans — what is left to do

The decision book answers *what was decided*; the plans answer *what is left to do* —
**the front of an area is its pending plans**. A choice still open is a consultation
(§The Consultation); the work of getting to its frame is a plan.

**What its door asks for is the body and the named close** — without the close nobody can
say whether it is done. States: `pendiente` and `hecho` at the two ends, `encargado`,
`en-curso` and `entregado` for a dispatched job in between (next paragraph), and
`descartado` for what stopped applying — marking that one `hecho` would lie about work
nobody did.

**Every plan has a `prioridad`: `alta`, `media`, `baja` or `algun-dia`** — the order it is
taken in among the plans waiting at its same desk; `algun-dia` is the «someday» plan that waits
for its moment in the area of its topic, out of the area's count. It is declared when opening the plan if you know it, and
a plan that declares none is `media`: every read serves it, with that value. Within each step
of the work order, `alta` goes first and `baja` last, and the clock decides inside each one
—on the area's page, in the menu, in the home tray and on the by-type axis—; it orders what
is still open, and closed plans go back to the clock. Rows show it in words («↑ high
priority», «medium priority», «↓ low priority», «↓ someday»), the menu carries the arrow of
the high one and of the last two, and the plan's header shows it next to its desk. It is corrected in any desk
without moving the plan, and its history and contract stay as they were:

```bash
$API -p <project> corregir planes <id> <<< '{"prioridad":"alta"}'
```

Each type that carries a priority says it in its own words —the plan `alta` · `media` ·
`baja` · `algun-dia`, the bug `critico` · `mayor` · `menor` · `algun-dia`— and both are read on
the same scale: the first word of each vocabulary weighs the same, and «someday» weighs the
same in both. A word from the other vocabulary gets a 400 naming
the valid ones for that type.

**On the web, a plan's desks read in THREE GROUPS**: **to do** is `pendiente`, **assigned**
holds `encargado` and `en-curso`, and **done** holds `entregado` and `hecho` —the delivered one
marked «awaiting your sign-off» and first within its group, since it is the only one that
needs the owner's hand—. They are the tabs of the by-type axis (`?estado=realizado`; the
older desk names, like `?estado=entregado`, open their group), each row's state label and the
pill in the plan's header; dropped plans leave the tabs for a link at the foot. **The model,
the API and the cycle keep the six desks as they are**: you write and read `encargado`,
`en-curso`, `entregado`, and the menu's dot with its hover names the exact desk.

**A plan also carries a dispatched job, end to end.** When a thinking session hands work
to a coding session, the plan is the handoff: its body is the brief, its `reporte` is what
came back, and its desk says whose hands it is in — `encargado` (the brief is in the body,
waiting for a session to take it), `en-curso` (a session took it; the note names its
worktree), `entregado` (the PR is open and the report written; waiting for sign-off), then
`hecho`. One plan is one PR. **The body and the report are a contract the server
enforces.** Entering `encargado` requires the body to carry eight sections as markdown
headings, each with content below — `# What changes` first: the plan's TL;DR in two to
four sentences, what happens today as the person using the system sees it and what
happens after, in the client's words and without code (the server rejects backticks and
code blocks there with `seccionConCodigo` and a long one with `seccionLarga`; a `d2`
drawing is allowed and not counted; the why belongs in Context and the mechanism in The
idea) — then `# Task`, `# The idea`, `# Destination`, `# Context`,
`# Pattern to follow`, `# Scope`, `# Out of scope`; plus the plan's `queEs`, its one-line
blurb for the lists, and its `visual` — what gets looked at in what it delivers (below).
Reaching `entregado` requires where the work went back to —`ficha.pr` for code;
`ficha.entregable`, the address of the piece, the commit or the campaign, for a content
job— and a `reporte` with seven sections: `## Done`, `## How it turned out`,
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
area": the present tense belongs to git. It carries the box diagram and the vertical
sequence diagram when the plan adds a new path, and reads "None" for a rename or an
adjustment with no new mechanism. **`## How it turned out` is its mirror on delivery**:
the same explanation in the present tense, about what exists, with the diagrams redrawn
where the build departed from the idea. Diagrams follow the house dialect, on top of the
`a1`..`a4` fills and `l1`..`l4` strokes: `entrada` and `salida` mark where the path starts
and where it lands —the only coloured boxes in a path—, `carril` groups by who —a
container whose label reads «01 / Name», drawn as a dashed frame—, `principal` marks the
path that matters and `lateral` what departs from it, and a box reads in three lines,
`"Name\nwhat it does\ntag"`. **They are drawn in the house stroke**: d2's sketch mode, the
line by hand in ink, the page's font in bold, the boxes on the paper, and colour at the
path's entry and exit. The page of a delivered plan reads as steps in
time — «Plan · Round 1 · … · Result» — and the Result opens by default with the chapter
«How the AI worked» on top and the current delivery below, folding «The idea» under «How it
turned out» — as it folds the round's request under Done and Out of scope under Pending
out of scope. Diagrams are written in `d2` and travel compiled, in
`diagramas`: the plugin compiles them with the house drawing (`bitacora-diagramas <
body.md`, from any project; `d2` installed is all it needs), which fails naming any block left uncompiled, and on delivery they
add to the ones the item already has. **The door charges the same**: a diagram block
without its drawing answers 400 naming it, and one written in another language answers 400
with the rule — diagrams here are written in `d2`, which is the one the page tints with the
house colors. That also covers the body you REWRITE: a drawing is paired by the hash of its
block, so touching one line of the code leaves the previous SVG ownerless and the page
starts serving the code. Recompile the whole body and send what the CLI prints in the same
`PATCH`. Without that access, write the section as prose alone.

**What it cost to build travels as data, in `consumo`.** One batch per round: each
engine's tokens —input, output, cache read, cache write— with the price per million that
ruled that day, and the day that table was checked (`preciosDe`). The price rides along
with the tokens because prices move, and what a closed plan has to answer is what it cost
WHEN it was built — that is what budgets the next job like it. The cost is derived on
read, so it is never sent. Each delivery ADDS its batch to the earlier ones, so a second
round declares its own without reading the first, and `ronda` names which round a batch
belongs to, so a round that arrived in two batches counts as one. `item planes <id>`
returns it summed per engine, with cost and tokens resolved.

**`visual` says what gets looked at in what the plan delivers, decided at design time.**
`ninguna` when nothing on a screen changes (backend, data, infra, scripts, tests, harness, a
refactor); `captura` when something on screen changes and the right result is already
written (a fix, a text, a configuration, data, a style that exists elsewhere, whatever an
ASK, a Figma file or a recorded decision already settled): whoever looks captures the
before and the after, and they sit at the foot of the plan as evidence; a state that has to
be manufactured to be seen goes to a test. `chequeo` when **a design decision stays open
that is only made by looking and whose answer changes the code**, before the work ships;
the plan names it in one line of its body: a visual check is opened declaring this plan,
the person answers it, and signing off closes it. **Where the push deploys** —the project
that commits straight to its production branch— **the default is `captura`**: what gets
looked at is already live. The door holds the rule: a check is born declaring a plan with
`visual: chequeo` that is not signed off yet (400 `chequeoSinPlan`, `planSinChequeo` or
`planCerrado`). **Signing off closes the check**, through the API or on the web: an
answered one moves to `aplicado`, and one still open to `descartado` with the note
«firmado sin mirar» (signed off without looking); the web band warns before. The guiding
question: *is there a design decision that is only made by looking, and does its answer
change the code?* → `chequeo`; *does it show, and is the right result already written?* →
`captura`; *nothing on screen?* → `ninguna`.

**And its review runs whole on the builder's side.** The review checks compliance and
produces two things: the FIX, a breach of the law —gross, with its Blocking row, or of
style—, and the ASK, what has more than one reasonable way out. The session that builds
loops review → fix until a round leaves no FIX to apply: any applied FIX asks for another
round, since one fix can bring another, and the round that reaches the cap with FIXes still
open says so in the report and leaves its row in Harness. On finishing it gives each result
its fate and uploads the review with its findings (`bitacora-api review <file.md> --pr … --hallazgos
findings.json`): on its own PR the applied FIX goes `aplicado` with its `commit` (Harness), the
ASK `diferido` (nit), the FIX outside the plan's Scope `diferido` and also into
«Pending out of scope», and the blocker the verification refutes `no-se-sostiene` with its
`porque` (Harness). The session that signs off reads the report, which says what was fixed and
what went to nit; «To decide» carries what the plan itself could not decide. A
finding's fate changes with `bitacora-api hallazgo <id> '{"suerte":"…"}'` —`plan` with the
`plan` that took it, `diferido`, `no-se-sostiene` or `descartado` with its `porque`, and
`aplicado` with its `commit` for a FIX—, and `bitacora-api hallazgos --bandeja nit|harness`
lists what each accumulator holds, each with its id.

```json
[{"tipo":"fix","accion":"1","clase":"comment-that-repeats-the-code","titulo":"the comment at x.ts:41 repeats the line below",
  "rule":".claude/rules/style.md §Comments","archivo":"src/x.ts","peldano":"mecanico","grosero":false,"suerte":"aplicado","commit":"<sha>"},
 {"tipo":"ask","accion":"2","titulo":"is the region searched as a facet?","contexto":"the index already stores it, and no screen filters by it",
  "suerte":"diferido"}]
```

**And a plan carries REQUESTS between sessions — the short round trip between
specialists.** The fronts of a project have roles (the one who builds, the one who looks
—QA: devices, captures, tests, the visual check—, the one who produces content), and small
work travels between them: the session that builds needs to SEE a screen mid-work and the
device belongs to another front; at close, that front produces the visual check on the PR.
A request is a sub-item of the plan (`plan.pedidos[]`), numbered inside it, read at the
foot of its page under «Between sessions» and nowhere else: it leaves a record without
taking a line of the home, the menu or the timeline. It carries `rol` (who takes it),
`que` (what is needed, one sentence), `sobre` (the branch or PR; defaults to the plan's
ficha), `aparato` (the device, when it matters) and `de` (the front that asked; defaults to
the plan's destination); it is born `abierto`, the role marks it `tomado` and closes it
`listo` with what came back —`nota`, `adjuntos` (the paths the upload returned) and
`chequeo` (the id of the check it opened)—; `descartado` belongs to whoever asked. The
message between sessions carries only the link; the record is the request.

```bash
$API -p <project> pedido <plan-id> <<'JSON'
{"rol":"qa","que":"The shelf with an empty store and with three products, on the phone","sobre":"feat/shelf","aparato":"the Galaxy"}
JSON
# → numero and enlace (the plan page with the request's anchor): send ONE line to the role's front
#   with the plan id and the link — «Request 2 of plan <plan-id> «<title>»: <link>» — since the taker's commands name the plan by id
$API -p <project> pedidos --rol qa                 # the role's tray: live requests across plans, each with its plan
$API -p <project> pedido <plan-id> 2 tomado
$API -p <project> pedido <plan-id> 2 nota "Halfway: the empty shelf is captured"   # a line on a live request, without moving it
$API -p <project> pedido <plan-id> 2 listo <<'JSON'
{"nota":"Both screens on the Galaxy, on feat/shelf at its last commit.","adjuntos":["<place>/shelf-empty.png","<place>/shelf-three.png"],"chequeo":"<id, when the request was the visual check>"}
JSON
$API -p <project> pedido <plan-id> 2                # what came back, each attachment with its address
$API -p <project> bajar <place>/shelf-empty.png      # downloads an attachment with your key
$API -p <project> pedido <plan-id> 2 descartado     # when it stopped being needed
```

```bash
$API -p <project> encargados                 # what can be taken · also: en-curso · entregados
$API bandeja                                 # without -p: every project this machine holds a key for
                                             # consultations in the person's hand or the client's, each with its `mano` and `falta`;
                                             # the client's come last, with the days they have waited
$API -p <project> tomar <id> "worktree …"    # → en-curso; the note also lands in ficha.destino
$API -p <project> entregar <id> <<'JSON'
{"reporte":{"en":"## Done\n…\n\n## How it turned out\n…\n\n## Evidence\n<one line: checks green, guardian score, review verdict with its link>\n\n## Decisions along the way\n1. **<What was decided.>** <Why.>\n\n## Frictions\nNone\n\n## To decide\n…\n\n## Pending out of scope\nNone"},
 "diagramas":[],
 "ficha":{"pr":"https://github.com/…/pull/…","rama":"…"},
 "consumo":{"ronda":1,"preciosDe":"YYYY-MM-DD","modelos":[{"modelo":"…","entrada":0,"salida":0,"cacheLectura":0,"cacheEscritura":0,"precio":{"entrada":0,"salida":0,"cacheLectura":0,"cacheEscritura":0}}]},
 "nota":"PR open, one point to decide"}
JSON
# a content job closes with "entregable":"<the piece's address>" in the ficha instead of "pr"
$API -p <project> firmar <id> "PR merged"    # → hecho
$API -p <project> devolver <id> <<'JSON'
{"cuerpo":{"en":"<the whole body, with a new ## Round 2 at the end>"},"nota":"back: why"}
JSON
```

**A plan that waits for its moment carries its trigger in the body**: what wakes it up
and why today is not the day. That is what the old model called a deferred decision — a
pending item with a trigger is work that waits, and the type that waits is the plan.

```bash
$API -p <project> plan <area> <<'JSON'
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
**person grading at the end**. The simulation is a piece of its topic's area, like an
analysis, and a decision in the area's book ratifies what it showed.

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
$API -p <project> simulacion <area> <<'JSON'
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

## The Consultation — something that holds something up

**A consultation is an OPEN DECISION**: the whole frame of a trade-off —what it holds up,
the options with what each implies, the recommended one with its why— and who decides it.
The session that analyses opens one when it reaches a decision that waits on someone else,
with `decision <area>` and no verdict (§Decisions), and **several gather in a BATCH**: the
person answers them in one go, on one page, and the batch takes a single row on the home
page. Each one also has its own page, `/<project>/punto/<id>`.

| `decide` | Who decides it | How it is answered |
|---|---|---|
| `fran` | the person | on the web: **accepts** the recommended option in one click, **rejects** it saying what goes instead —or picks another option in one click—, or **asks for more context** when what is written is not enough |
| `cliente` | the client, with the person as go-between | the person takes it to the client and marks it with «I asked the client», which dates its `preguntadaAt`; then loads on the web what the client answered: their words, the option they chose and where they said it |
| `sesion` | the session | `decidir <id> "<verdict>"` |

**The answer that decides it moves it to `decidida`, with its verdict**: the recommended
option when accepted, what goes instead when rejected, what the client answered. Asking for
context leaves it open with that answer and hands it back to the session, which rewrites it
with what was missing (`corregir <id>`); the request stays in `pedidos` as a record. **The
answer belongs to the person and enters through the web**: over the API it returns 400.

**Every option is picked in one click.** With `recomiendo` —the POSITION of the recommended
one, `0` is the first— tapping it accepts, and tapping any other rejects leaving that option
written as what goes instead. What the session reads when applying is the name of the
chosen option, exactly as it wrote it, so **write each option's `titulo` as the instruction
you will carry out** rather than as a label. When you rewrite `opciones`, send `recomiendo`
again: the list is replaced whole, and the door answers 400 when the index points outside it.

**It is read in one pass, and written in that order.** The page draws the title, **«What is
blocked»** (`bloquea`), **«Where it comes from»** (`cuerpo`) and **«What is chosen»** —the
options as a lettered list, the recommended one carrying its badge and its `recomendacion`—
with the buttons. The
`cuerpo` opens with the problem in one or two sentences, then one short subheading per front
with bullets underneath, tables for compared values, and the code references last, under
`### In the code`. What is SEEN —a screen, a component, a state— opens the `cuerpo` with its
capture: `capturar "$PLACE" <file…>` returns its path, the decision declares it in `capturas`
and the `cuerpo` shows it with `![what it shows](/adjunto/<path>)`. What each answer changes
goes in its option's `implica`, and `"flujos":["<slug>"]` names the runs it touches.

**The batch.** `tanda <area>` opens it empty with its title and its `queEs` —what it holds
up and what happens with what is decided, in a sentence or two: all the context the person
reads before the first one— and answers its id. **Each consultation that joins names it with
`"tanda":"<id>"`**, when opened or later with `corregir <id>`. A batch mixes hands: the
person's, the client's and the session's together. Its address is that of any piece of the
area, and a `#p2` in an older link lands on its decision's fold. **The batch's desk comes
from its decisions, by itself**: `abierta` (`por-preguntar` in a client question) while any
is open; `preguntada`, in a client question, when every open one is the client's and has gone
out; `contestada` (`respondida` in the client's) when none is open and a decided one waits to
be applied; `aplicada` when all closed with one applied; `descartada` when all were dropped.

**Whose hand it is in, the server serves.** Every decision read —`tipo decisiones`,
`abiertos decisiones`, `item decisiones <id>`— carries its `mano` and its `falta`: `persona`
for the open one of `fran`, the client's one still to be taken to them (`falta` `preguntar`,
with its `para`) and an inherited open one without `decide`; `cliente` for the client's one
once taken, with the days it has waited; `sesion` for one that asked for context, one the
session decides, and a `decidida` waiting to be applied. The hand belongs to what waits on
someone: the open ones and the decided ones. The home page reads that same hand in its
three rows —«Waiting on you», «In the client's hands», «In the sessions' hands»—,
and **a batch takes one row**, in its most urgent hand (person, then client, then session).

```bash
$API -p <project> tanda <area> <<'JSON'
{"titulo":"The record key and what goes into the index",
 "queEs":"Holds up the round that takes the record PR out of draft; with what is decided that round gets written."}
JSON
# → answers the batch id
$API -p <project> decision <area> <<'JSON'
{"titulo":"The key of each record","decide":"fran","tanda":"<batch id>",
 "bloquea":"the round that takes the PR out of draft: the record is written with its key",
 "opciones":[
   {"titulo":"Use Tour.id as the key","implica":"the permanent reference the contract declares; the records already there get reindexed once"},
   {"titulo":"Keep the route slug plus the tour slug","implica":"no migration today; a marketing rename orphans the record, and the tour slug can be null"}],
 "recomiendo":0,
 "recomendacion":"Tour.id: it is the permanent reference the contract declares, the three fronts agree, and the migration is a reindex that runs once",
 "cierraEn":"round 2 of the record plan",
 "cuerpo":"Today the record key is the route slug plus the tour slug. The tour slug can be null and marketing renames it when it adjusts the copy, so a rename orphans the record and the search serves a page that no longer exists. The contract declares Tour.id as the permanent reference, and the round 1 delivery left the question in «To decide»."}
JSON
# … the person answers on the web …
$API -p <project> decidido                       # what waits on the session: decided ones first, with their verdict and batch; those that asked for context; those it decides
$API -p <project> aplicar-decision <id> "round written"     # one decided → aplicada
$API -p <project> aplicar <batch> "round written"           # the whole batch: every decided one → aplicada; with any still open, 400 `sinContestar`
```

**What the client decides is a consultation with `decide: cliente`**, and the door requires
what the person sends (`preguntaIncompleta`): `pregunta` —the text ready to send, in the
client's words and language, with a copy button on the page— and `urgencia` (why it's
urgent), with `para` (YYYY-MM-DD) when there is a date. Its `cuerpo` is **what you need to know to
understand it without opening another piece**: today's situation, what the sources say and
where, the names and figures it uses; and every reference to another piece goes as a link,
or tells what that piece says. **Step one is CHECKING THE SOURCES**: the client already handed
material over, and what they wrote themselves is read before writing to them —asking anyway
spends the one thing the project can't replace, their time and the credit of whoever asks—.
`fuentes <area>,<alias>` says which ones there are and which one rules, and **one subagent per
source** —wide, independent readings— answers what each says about each question. What comes
back answered goes to the area's book as a decision already made, with its quote; what stays
open is what the client is asked, and its `cuerpo` says what was read and what stayed open.

```bash
$API -p <project> fuentes search,algolia         # step one: what to check against, in the order that rules
# … one subagent per source: what it says about each question, and where it says it …
$API -p <project> decision <area> <<'JSON'
{"titulo":"Do private tours go into the public catalogue?","decide":"cliente",
 "pregunta":"Should private tours be published on the website?",
 "urgencia":"the index demo is next week, and the index can't settle which records go in without this answer",
 "para":"2026-10-15",
 "bloquea":"the index can't settle which records go in",
 "opciones":[
   {"titulo":"They are published","implica":"they enter the index flagged as private, and the site's search shows them next to the rest"},
   {"titulo":"They are not published","implica":"they are filtered out before indexing, and reached only by direct link, as on today's site"}],
 "recomiendo":1,
 "recomendacion":"Not to publish them yet: the catalogue has no public price for private tours, and a listing without a price in search loses the sale",
 "cierraEn":"the index plan, and an entry in the record the client ratifies",
 "cuerpo":"The catalogue carries tours flagged private. The attribute register doesn't say whether they are published —it was read in full, and its visibility column doesn't name them—, and today's site shows them only by direct link. The new index has to settle which records go in before the demo, and the rule belongs to the client's business: what they sell in public and what through their own channel."}
JSON
# … the person takes it to the client and marks it on the web …
$API -p <project> corregir <id> <<< '{"preguntada":true}'   # or the session, when it knows it went out
# … the person loads what the client answered; the decision moves to «decidida» by itself …
$API -p <project> aplicar-decision <id> "to the index plan · the rule, to the client record"
```

**Earlier consultations.** Closed consultations and client questions read as always, with
their points —the earlier record, «The client decides» marks included—. The earlier routes
and verbs (`consulta <area>` with `puntos`, `consulta-cliente <area>` with `preguntas`,
`consultas`, `contestadas`, `respuestas`, `puntos`, `consultas-cliente`, `lo-que-contesto`,
`preguntas`, `preguntada`, `aplicar-cliente`) still answer, working on the batch's decisions,
and each one prints in a line which gesture is today's.

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
| `entrada` | **the direct address the screen opens at**, instead of `origen` and `gesto`: for the step you reach by its URL —a state prepared in the database, a page that opens on its own—, so it says how you really get there |
| `queCuenta` | **what to look at, from the seat of the user who uses that screen**: their situation, what the screen shows them, what changed for them and the question the approver decides (how to write it, below) |
| `propuesta` + `porque` | the session's recommendation and its reason, in one phrase |
| `flujo` | the slug of the run that moment belongs to |
| `dispositivo` | `escritorio` or `celular`: which device the captures come from, because it decides HOW the page compares them — side by side for phone captures, and for desktop ones stacked in the same place, with a Before and an After button to pick which one shows. The page infers it from the image when absent (landscape means desktop); **declare it when a desktop capture is full-page**, taller than wide, which would otherwise read as a phone |

**Captures go up first and the step names them by their path.** Each one enters through the
attachments door —one request per file, so a long check has no size ceiling— and `capturar`
returns each path: **no path is ever written by hand**, and the check's door verifies that
every one named exists as a file of the check's place and is an image. So the captures and
the check name the same place: the `hilo` of the plan the check reviews, which `item planes
<id>` returns. A mistyped path comes back as a 400 saying which, instead of showing up as a
hole where the owner had to decide.

**The context is half the value: which screen, of which run.** The check declares the runs
it verifies in `flujos` and each step names its own in `flujo`; with a single run declared,
the step inherits it. The door requires it, because a screen that does not say which run it
belongs to makes the approver reconstruct it. **And the navigation is paid from the second
step on**, in one of its two forms: `origen` with its `gesto` when you come from the previous
screen, or `entrada` when you reach the step by its address. The first step is spared, since
you enter it with no previous gesture. The form is the one that exists: an origin and a
gesture made up to pass the door tell the approver about a navigation the app does not
have.

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
| `aplicado` | the session took what was approved: rejections and requested changes become the next round of the plan, on the same branch | the session, with `aplicar-chequeo`, or the plan's sign-off on an answered one |
| `descartado` | it stopped applying, with its reason | the session, or the plan's sign-off on one still open, with the note «firmado sin mirar» |

```bash
# 0. The place: the plan's own.
PLACE="$($API -p <project> item planes <plan-id> | jq -r .hilo)"

# 1. The captures go up and return their path: that is what the step names them by.
$API -p <project> capturar "$PLACE" step1-origin.png step1-before.png step1-after.png
$API -p <project> capturar --reemplazar "$PLACE" step1-after.png   # a name already taken in the place returns 409 adjuntoTomado; the same capture redone goes up with --reemplazar
# → {"step1-origin.png":"<place>/step1-origin.png", …}

# 2. The check, with its run, the plan it reviews, and its steps.
$API -p <project> chequeo "$PLACE" <<'JSON'
{"titulo":"The prizes step of the wizard, on a Galaxy S21",
 "queEs":"PR #212 rebuilds the prizes step of the sign-up wizard. Nine screens of the run, on an S21: what changed is the order of the fields and the summary at the foot.",
 "plan":"<the id of the plan it reviews>",
 "flujos":["<run-slug>"],
 "pasos":[
   {"titulo":"The wizard, on the data step",
    "queCuenta":"You are signing up your tour and just finished the data: from here you go on to prizes. The Continue button is now pinned to the foot, so you see it with the keyboard open. Can you find it without scrolling?",
    "despues":"<place>/step1-after.png",
    "antes":"<place>/step1-before.png",
    "propuesta":"Keep it pinned to the foot.",
    "porque":"On an S21 the button fell below the fold with the keyboard open."},
   {"titulo":"Prizes, with the new summary",
    "queCuenta":"You picked your prizes and at the foot you see how many you have: the summary now adds them up. Does the total read well, with Continue in sight?",
    "origen":"<place>/step1-after.png",
    "gesto":"tap Continue",
    "despues":"<place>/step2-after.png",
    "antes":"<place>/step2-before.png",
    "propuesta":"Keep the summary as it is.",
    "porque":"The total reads in full and Continue stays in sight."}]}
JSON

# 3. … the person approves step by step on the web; the check moves to «contestado» by itself …
$API -p <project> visto <id>     # step by step: what was approved, what was rejected and with which comment
$API -p <project> pasos <id> <<'JSON'
{"pasos":[{"id":"p2","despues":"<place>/step2-recaptured.png","queCuenta":"…what was missing to see…"}]}
JSON
$API -p <project> aplicar-chequeo <id> "round 2 written in the plan · two screens rebuilt"
```

**The check is born declaring the plan it reviews** (`plan`, the plan's id, at creation):
that is what ties it to the PR it approves, and the door asks that plan to exist, to have
asked for `visual: chequeo` and to be still unsigned. The plan lists it in its access strip
as «Check», its page links it from the request that opened it, and signing off the plan
closes it. **Before sending the link, the session verifies it**: a subagent compares each
pair —the before and the after are the same screen at the same size, what the step asks to
approve is in sight, no defect shows, the captures come from committed code— and whatever
fails is recaptured through `pasos`. **A step accepted with a text is a change request**:
it is approved and asks for something more, the check's read gathers it in `cambiosPedidos`
(`{"paso","texto"}`), and the session does it before applying.

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

## The Jev Question — a semantic judgement, with its evidence

When a project runs Jev questions at commit, **each question is a piece** of the `harness`
area: its `clave` —the id the repo's rule gives it, unique in the project—, the `pregunta`
Jev is asked, the FIX `clase` it comes to replace, and its `banco`: Jev's probability on
each red, green and approved sample. Its desk is the path of every question —`propuesta`,
`en-banco`, `informando`, `frena`, `retirada`— and what moves it from reporting to blocking
comes from its real runs: the page reads the bench, the precision over the reds the signer
judged, and whether its class kept reaching the review.

```bash
$API -p <project> pregunta-jev harness <<'JSON'
{"titulo":"…","queEs":"what class of fault it catches, and on which files","clave":"<id in the repo's rule>",
 "pregunta":"<the question>","clase":"<the FIX class it replaces>","cuerpo":"<its scope in code and its criteria>"}
JSON
$API -p <project> corregir pregunta-jev <id> <<< '{"banco":{"rojo":[0.08],"verde":[0.91],"aprobado":[0.93]}}'
$API -p <project> jev-corrida <<< '{"clave":"…","archivo":"src/x.ts","commit":"<sha>","probabilidad":0.12,"resultado":"rojo"}'
$API -p <project> jev-veredicto <run> archivo      # the file was wrong: the question was right
$API -p <project> jev-veredicto <run> pregunta     # the question is miscalibrated
```

## The Goal — what several pieces pursue together

Work that takes several PRs —the back end, the web and the app of one feature; an index
built in stages; a migration in parts— is split into small plans, each in the area of its
world. **The goal is what those plans pursue together**: a project piece, with no place, that
says what we're after and when it's achieved, and that each plan, bug or analysis names as its
own. Its page shows
**«What pursues it»** under the body: the progress in one line and every piece that names
it, from any area, with its desk.

**Its door takes three sections when it opens**, as headings of the body: **What we're
after** (what will exist once it's achieved, as whoever uses the system sees it: no code, and
within the ceiling of a plan's «What changes»), **Why** (where it comes from and what problem
it solves, with its sources) and **When it's achieved** (the observable thing that marks it
achieved: what the session looks at to close it). The 400 `aperturaIncompleta` names them with
what each one states, and a «What we're after» with code or too long answers
`seccionConCodigo` or `seccionLarga`.

**Its path: «What's next» is written, the rest is derived.** **What's next** is one more
section of its body, after «When it's achieved» and at the same heading level: the order of
its plans by stage, which is judgement. Its shape is a `d2` drawing of stages —one lane per
stage, one box per plan saying what it changes and carrying `link:` to its plan, arrows are
dependencies—, then per stage a bold line with the stage and its checklist, one item per open
plan that names the goal, `- [ ] [Plan title](link) — moves when …`, and one or two
sentences on why that order, within 300 visible characters without the drawing or the
checklist items. The page paints each item with its plan's live desk and each box with its
card.

**The patch charges it** (`$API -p <project> corregir objetivos <id>`, with the whole
body) while the goal is open and has open plans that name it, once the project closes its
`caminos` adaptation or once the body already brings the heading: missing or empty answers
400 `caminoIncompleto` with its outline, without a drawing `seccionSinDibujo`, too long
`seccionLarga`, and an open plan the checklist does not name by its link `planesSinNombrar`,
with the items ready to paste. Any other goal carries the section free, within 600; its
opening takes only the three sections, because it is born before its plans.

**«In flight» and «Waiting on others» are derived when read** from the pieces that name
the goal, so they are always current: in flight, its plans in `encargado`, `en-curso` or
`entregado`, each with its desk, the front that holds it and the roles it waits on; waiting
on others, first the open decisions that name it, with who decides and what they block, then
the open consultations, client questions and visual checks still before their answer, then
every goal in its `dependeDe` that still holds it back —open or dropped—, with its progress,
in the list's order, then every live request of its plans with its role and what it needs,
linked to `…#pedido-N`. The goal's page shows both under its body, each saying "None" when
empty, before «What pursues it»; its read brings them in `camino` —`enVuelo`, `espera` with
each row's `clase` (`decision`, `pieza`, `objetivo` with its `avance`, `pedido`), and
`sinNombrar` with the open plans its «What's next» does not name yet, while it charges its
order—. What the path closed
is told by the goal's book, and the public mirror serves the body with «What's next».

**It opens in the project**: `$API -p <project> objetivo`, with no area (`POST /api/objetivos`),
and it takes its number and its slug in the project. An area that a session on the previous
client still names is accepted and left unused, and the response says so in its `aviso`. The
pieces that pursue it live in their areas; the patch turns down the place gestures on a goal
—`hilo`, `tambienEn`, `fijado`— with 400 `sinLugar`.

```bash
$API -p <project> objetivo <<'JSON'
{"titulo":"…","queEs":"what the back end, the web and the app pursue together",
 "cuerpo":{"en":"# What we're after\n…\n\n# Why\n…\n\n# When it's achieved\n…"}}
JSON
# → answers the goal's id: it is what each piece names

$API -p <project> plan <area> <<'JSON'
{"titulo":"…","cierraEn":"the PR that brings it","objetivo":"<goal id>","cuerpo":{"en":"# …"}}
JSON
$API -p <project> corregir planes <id> <<< '{"objetivo":"<goal id>"}'   # a piece already open joins it
$API -p <project> corregir planes <id> <<< '{"objetivo":null}'          # and leaves it
$API -p <project> corregir <decision id> <<< '{"objetivo":"<goal id>"}' # a decision, through its own door

$API -p <project> item objetivos <id>     # the goal with its `piezas`, its `avance` and its `camino`
$API -p <project> corregir objetivos <id> <<'JSON'   # orders its plans: the whole body goes
{"cuerpo":{"en":"# What we're after\n…\n\n# Why\n…\n\n# When it's achieved\n…\n\n# What's next\n…"}}
JSON
$API -p <project> abiertos objetivos      # what is pursued today in the project
$API -p <project> mover objetivos <id> <<< '{"estado":"logrado","nota":"what was achieved"}'
$API -p <project> mover objetivos <id> <<< '{"estado":"descartado","nota":"why it is no longer pursued"}'
```

**Every piece takes the `objetivo` field**, when opened or through `corregir`: the id of an
**open** goal of the same project. The door checks it the way a
visual check checks its plan: an id that does not exist answers 404 `objetivoInexistente`,
one that is `logrado` or `descartado` answers 400 `objetivoCerrado`, and **a goal does not
name another one** —there is a single level—: 400 `objetivoAnidado`, which says where the
order between goals goes: in `dependeDe`. `{"objetivo":null}` removes it. **You write the id
and read the address**: the piece's read brings it resolved,
`"objetivo":{"id":"…","titulo":"…","enlace":"https://…"}`.

**A goal that comes after another declares it in `dependeDe`**: the list of ids of the goals
that have to be achieved first, in the order they are waited on. It is a relation between
sibling goals —a piece's `objetivo` still says what it pursues—, the goal that waits declares
it, and the other side is derived on read. It goes in when the goal opens, in the JSON of
`$API -p <project> objetivo`, or with `corregir objetivos <id>`: the list arrives whole and
replaces the previous one, with each id once, and `[]` removes it. The door charges three
rules: 400 `dependeDeSiMismo` when the list holds its own id, 404 `dependenciaInexistente`
with every id that is not a goal of the project, and 400 `dependenciaCircular` when the list
closes a cycle, named by its titles —«A» waits on «B», which waits on «A»—.

```bash
$API -p <project> objetivo <<'JSON'
{"titulo":"…","queEs":"…","dependeDe":["<id of the goal achieved first>"],
 "cuerpo":{"en":"# What we're after\n…\n\n# Why\n…\n\n# When it's achieved\n…"}}
JSON
$API -p <project> corregir objetivos <id> <<< '{"dependeDe":["<id>","<id>"]}'   # the whole list, in its order
$API -p <project> corregir objetivos <id> <<< '{"dependeDe":[]}'                # and removes it
$API -p <project> item objetivos <id> | jq '{dependeDe, destraba}'
```

**The dependency orders and warns**: the plans of a goal that waits are commissioned all the
same, and what changes is what its page and its read tell. The awaited goal **holds it back**
while it is open or dropped —a dropped one shows as dropped and holds it back until someone
removes the dependency or changes it—, and once achieved it unblocks it. The goal's page says
on top **Waits on**, with every awaited goal and its progress —or its desk once closed—, and
**Unblocks**, with the goals waiting on it: open ones first, then achieved ones, without the
dropped. Every name leads to its page, and the page names the goals its reader opens: a
guest reads the ones seen from their lines or from a piece they see, in «Waiting on others»
too. The read brings them in `dependeDe`, in its order, and `destraba`, each
`{"id","titulo","estado","enlace"}`; an id that no longer exists travels with its id alone,
and each field travels when it has something.

**The goal reads at its project address, `/<project>/objetivo/<id>`**, which is the one its
`enlace` in the API, its menu row and the **Pursues** line of every piece carry. A goal born
in an area keeps its address from then, `/<project>/linea/<area>/<slug>`, and that address
leads there, so the links already going around keep working. Whoever sees the whole project
opens it, and a guest does when they see any of the pieces that pursue it: whoever works on a
piece reads where it is heading.

**A decision made along the way names it through its own door**, with the same check:
`"objetivo"` goes in the JSON of `$API -p <project> decision <area>` next to its frame, and
`corregir <id>` —without the type— adds or removes it. It shows in «What pursues it» with its
row, which leads to its point, and the progress leaves it uncounted:

```bash
$API -p <project> decision <area> <<'JSON'
{"titulo":"…","veredicto":"…","bloquea":"…",
 "opciones":[{"titulo":"…","implica":"…"},{"titulo":"…","implica":"…"}],
 "recomiendo":0,"recomendacion":"…","cierraEn":"…","cuerpo":"…","objetivo":"<goal id>"}
JSON
```

**The page of every piece opened through its type says on top what it pursues**: the
**Pursues** line, with the link to the goal's page, which opens by the same rule: whoever
reads the piece opens the goal it pursues. In the public mirror the link leads to the goal's
published address, and an unpublished goal reads by its name alone.

**The goal belongs to the project, and reads that way.** The menu has its own block, **«The
goals»**, between «The areas» and «Recent»: every goal its reader opens, folded like an area,
with its pieces from every area in the order of the work and each one's place in the margin.
Open goals come first, from the most recent activity —its own or its pieces'— to the oldest,
and achieved ones after them, dimmed; a dropped one leaves. The by-type axis
(`/<project>/tipo/objetivos`) lists them in a single batch, the project's, and the project's
timeline says «Goal» in the margin of its moves.

**Inside each area, the goal heads the place's pieces that pursue it**, with the glyph of its
desk and in the order of the work, and the group sits where its most advanced piece sits: the
plan in progress stays on top. An achieved one keeps grouping, dimmed, and a guest reads the
group of every piece they see, because seeing a piece opens its goal; a dropped one, and in
the public mirror one that is not published, leave their pieces loose, like whatever pursues
none. **`subarea <place>` lists the place's pieces with the
resolved `objetivo` on every row**, so a session reads the same grouping, and **`tablero`
brings the goals in their own list**, `objetivos`, each with its `id`, `titulo`, `queEs`,
`estado` and `url`, and its `dependeDe` and `destraba` when it has them:

```bash
$API -p <project> subarea <place> | jq '[.items[][] | select(.objetivo) | {titulo, objetivo: .objetivo.titulo}]'
$API -p <project> tablero | jq '.objetivos[] | {id, titulo, estado, dependeDe, destraba}'
```

**An entry names it too**: `"objetivo"` in the JSON of `$API -p <project> entrada <area>`,
and `corregir-entrada <area> <id>` adds or removes it, with the same check. That way what was
noted along the way —the meeting, the delivery, the incident— enters **its book**, next to
what settled among the pieces that pursue it: `$API -p <project> libro objetivo <id>`, and on
its page the link under «What pursues it».

```bash
$API -p <project> entrada <area> <<'JSON'
{"tipo":"entrega","titulo":"…","cuerpo":"…","objetivo":"<goal id>"}
JSON
$API -p <project> corregir-entrada <area> <entry id> <<< '{"objetivo":"<goal id>"}'   # an entry already written joins it
$API -p <project> corregir-entrada <area> <entry id> <<< '{"objetivo":null}'          # and leaves it
```

**The goal's read brings what pursues it**, derived on read: `piezas` —each with its `tipo`,
`titulo`, `estado`, `hilo`, `area` and `enlace`— and `avance`, which counts the work:

```json
{"avance":{"total":5,"cerradas":2,"abiertas":3,"enCurso":["<id of the plan in progress>"]}}
```

The progress counts plans and bugs: `cerradas` is what is done or fixed, `abiertas` the
rest, and `enCurso` names the plans a session has in hand. What is dropped leaves the count;
an analysis, a consultation or a decision is listed without counting. The page lists and counts what
the reader can see: on the public mirror, the published pieces; a guest, the ones seen from
the lines shared with them.

**Closing it takes its `nota`**: calling it achieved is a judgement, and so is no longer
pursuing it. `mover objetivos <id>` to `logrado` or `descartado` without a `nota` answers 400
`cierreSinNota`; reopening it goes through clean. **The session that signs off its last open
plan calls it achieved**: it reads «When it's achieved» against what was signed off, closes
the goal with a note on what was achieved when the condition holds and tells the person in
one line, which names every open goal it unblocked (its `destraba`), and when something is
missing, that is the next plan. Dropping a goal is the
person's call. The person closes it from the goal's page
too, with **Achieved** and **No longer pursued**, each with its line.

**An area the project opened to gather the plans of one initiative becomes a goal** of the
project, through the `objetivos` adaptation, which the owner runs: the goal opens in the
project, every piece of the area names it —one that already pursues another goal keeps it—,
each place merges into the area of its world with its old slug as an alias, and the area is
retired. The old addresses keep leading to the pieces, which now read under their goal.

## Planning — the same gesture in every project

**Every piece of planning ends as a logbook plan, in its area.** The method is one and it
lives here: whichever project you plan in, planning is this same gesture through the same
doors.

**Its area is settled first.** List the areas (`$API areas`) and ask the user which one the
plan joins — the plan is theirs, and so is the area it belongs to. What is good but not a
priority yet goes to the area of its topic with `"prioridad":"algun-dia"`; when the topic is a world no area holds, open its
area (`$API abrir-area`) and say so in your report.

**The plan comes out of what was already discussed.** A title that states the conclusion,
a `cierraEn` saying where it closes — the door demands it: without a close there is no
plan — and a body carrying the reasoning the conversation produced. Write it with
`$API plan <area>` and finish the gesture by handing the user the `enlace` the response
returns — the item's full address — so they can keep reading it in the web app. **When the
topic takes several PRs, open its goal first** (`$API objetivo`, in the project, §The Goal) and each
plan names it when opened, with `"objetivo":"<id>"`. The
tie-break between types is the standing one
(see *Plans* above): understanding left asks for an analysis, executing asks for a plan,
choosing between exclusive paths asks for a decision.

**Claude Code's plan mode (`/plan`, shift+tab) is the harness's working mode** for
thinking a change through before touching it; the plan it produces is recorded through
this same gesture — what was thought out lives in its area and outlives the session.

```bash
$API -p <project> areas          # where it goes: the project's areas — ask BEFORE writing
$API -p <project> objetivo <<'JSON'   # when the topic takes several PRs: what they pursue together, in the project
{"titulo":"…","queEs":"…","cuerpo":{"en":"# What we're after\n…\n\n# Why\n…\n\n# When it's achieved\n…"}}
JSON
$API -p <project> plan <area> <<'JSON'
{"titulo":"…","cierraEn":"the PR that brings it","objetivo":"<goal id, when it pursues one>",
 "cuerpo":{"en":"# How it gets solved\n…"}}
JSON
```

## What is someone else's

- **Supersede, never edit.** When your work makes an existing entry obsolete, mark it
  (`$API superar <place> <entry-id>` with `{"superadaPor":"…"}`) and write the new one.
  The record stays whole; the mark says history.
- **Deleting is the owner's.** Your key can't delete anything — if something should
  never have existed (a duplicate, an area opened by mistake), tell the owner.
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
having to pick one of the two readers. The flow's page opens its run with a map drawn from
those steps —one box per step carrying its sentence up to the first pause, grouped by stage
when the run is long—, so a `que` whose first clause names the step reads well in the map.

### The sources — what the client handed over, and which one rules

A **source** is what came from outside: a sheet the client keeps editing, a PDF, a Slack
channel, a Figma file, a board. It is registered once at PROJECT level and its `tags` make it
show up in every area it names — one channel talks about search, the CMS and the
infrastructure in the same week, so hanging it off a single area hides it from the other
two.

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
| `tags` | Free slugs — areas, stack pieces, words: this is what makes it appear in each area |
| `nota` | What you need to know to use it: the quota, the sharing permission, the sheet that matters |

**Which one rules is DERIVED from the order**, so it cannot go stale: the client's live one
rules over a dated one, among dated ones the newest rules, and a superseded one says so,
dimmed at the foot. No field declares precedence — it comes out of vigencia, side and date.

```bash
$API fuentes                    # the whole register, in that order
$API fuentes algolia            # the ones on a topic: the slug of an area or a stack piece
$API fuentes search,algolia     # several topics, comma-separated: one tag is enough for a source to show
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

**And a new source is recorded from the area where it appeared.** A link to a sheet, a
document, a channel or a file that arrives while a topic is being thought enters with
`anotar-fuente` carrying its area's tag, and `refrescar <slug>` takes its first mirror: the
area is a tag, so tying it is naming it.

**`$API accesos` lists the project's quick links**, each with the credential it carries:
the outside addresses you enter every day — the engine, the repo, the ticket board, the
design file. They belong to the whole project, and the workshop keeps them one click away
in the right-hand column.
Anote one you had to hunt for with `$API anotar-acceso <<< '{"nombre":"…","url":"https://…","nota":"staging"}'`
— it is upsert by slug, so fixing a URL that moved is the same call. When the place asks you
to sign in, `usuario` and `clave` go with it: the workshop keeps them folded under that link,
one click from the address they open. They are project material and are stored as such — in
the clear, visible to everyone inside the tenant — so what belongs here is the credential the
project team shares.

Full command list: `bitacora-api` with no arguments prints usage.
