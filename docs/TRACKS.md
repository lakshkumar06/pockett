# Challenge fit and implementation evidence

Challenge references: [HackUTD sponsor tracks](https://hackutd-2026.notion.site/Sponsor-Tracks-3bd63cec7740808c9e89e4e25cee23e7), [Photon 2.0 guidelines](https://somethingreat.notion.site/Hackathon-Guidelines-for-Photon-2-0-3f8e443f36bb81f9893fed0d08a4c01d). Recheck final submission requirements with organizers; eligibility is not certified by this code.

| Track | Challenge fit | Actual implementation | Remaining evidence |
| --- | --- | --- | --- |
| SpacetimeDB | Use Spacetime for the majority of the backend, with a public repository for judging | Accounts/sessions, listing registration, sharing/access revocation, notifications, build queue/leases, conversation links/deduplication, generated-app data and publication logic execute inside the Spacetime module | Maincloud deployment and public repo decision. Repo is currently private. No official 70% formula was found; do not invent one. |
| NVIDIA Nemotron | A multi-step agent using Nemotron and real tool execution | Hosted model → build specification → execute validation/persistence/isolation checks → feed failures back → repair → ready. Twelve-step cap; trace persisted in Spacetime. | Live Nemotron run with configured key/model. Tests use a clearly labeled fixture. |
| Photon | A working agent built on Photon 2.0, live on a messaging channel, retaining context and accomplishing work | Authenticated 2.0 messages API, explicit account pairing, persistent conversation/build context, build/change/status/publish commands, idempotent replies | Real project, provisioned sender, live conversation and demo. Notifications alone would not meet this challenge. |
| Vultr / MLH | Use Vultr cloud in the project | Reviewed plan → live price/availability preflight → provision host → SSH upload → HTTPS gateway and build worker | Real Vultr deployment and URL. The code has not provisioned billable resources. |
| HackUTD Virality | Product people naturally share | Build a small useful app, add it to Pocket, share access with friends; one shared dataset with revocation | Demonstrate an actual multi-person use case; no fabricated traction or virality claims. |

Backend responsibility is measured here by ownership, not lines of code: the durable product workflows are Spacetime-owned. The Node gateway does password hashing, transport, HTML rendering, and external API calls; it has no second product database. Generated apps do not move their data to Atlas, Firebase, or a competing backend.

Pocket's original iOS app and creator tools predate this implementation. `IMPORT.md` and the first commit preserve that provenance. Existing-project reuse may affect eligibility under HackUTD's rules; obtain an organizer ruling before claiming eligibility. Do not present the baseline as work created during the event.

## Technical limits

- Private JSON records in separate Spacetime tables simplify this migration; scans and HTTP procedure calls prioritize correctness and compatibility over large-scale efficiency. Typed columns, indexes, identity-bound views and SDK subscriptions are the next scaling step. Current generated pages refresh every five seconds, not via WebSocket subscriptions.
- The gateway uses a privileged publisher identity. Its token must stay server-side. Clients get account sessions or per-app capabilities, never the database token. The module rejects all other Spacetime callers.
- Generated specs cannot run arbitrary model code. This deliberately supports a bounded family of useful miniapps. Website listing registration and the old notification SDK still work.
- Live NVIDIA, Photon and Vultr claims require credentials and a real demonstration. Local compilation and mocked provider tests do not establish those outcomes.

## Provider sources

- [Spacetime TypeScript quickstart](https://spacetimedb.com/docs/quickstarts/typescript/), [procedures](https://spacetimedb.com/docs/functions/procedures/), [HTTP database API](https://spacetimedb.com/docs/http/database/).
- [NVIDIA Nemotron tool-calling API](https://docs.api.nvidia.com/nim/reference/nvidia-nemotron-3_5-bolt-e4b-infer). Model name remains configurable because hosted aliases and availability change.
- [Photon 2.0 docs](https://photon.codes/docs/beta): implementation checked against its OpenAPI `SendMessageRequest`, `MessagePage`, received-message and idempotency-header schemas.
- [Vultr Cloud-Init API guide](https://docs.vultr.com/how-to-deploy-a-vultr-server-with-cloudinit-userdata/).
