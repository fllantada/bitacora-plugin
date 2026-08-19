# bitacora-plugin

Claude Code plugin marketplace for the **bitácora** — a project logbook where
decisions, analyses and the day-to-day record of a project live.

If you were invited to a project's logbook, install the collaborator plugin:

```bash
claude plugin marketplace add fllantada/bitacora-plugin
claude plugin install bitacora-colaborador
bitacora-api alta <code-from-your-invitation-email>
```

See [`bitacora-colaborador/README.md`](./bitacora-colaborador/README.md) for details.

This repository holds only the client and its skill. The logbook's content lives in
the engine's private database, behind per-person keys — nothing here grants access.
It is republished automatically with every engine deployment, so client and server
stay in sync.
