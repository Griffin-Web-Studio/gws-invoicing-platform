# GWS Invoicing Platform: Architecture Specification

|||
| -- | -- |
| Status | Draft |
| Version | 0.1 |
| Authors | Rihards Simanovics |
| Co-Authors | Claude Opus 4.9 (high), TBC |
| Owner | Griffin Web Studio Ltd |
| Working product name | TBD (referred to below as "the platform" and "the Core") |

## How to read this document

Each section carries a status tag:

- `Settled` means we have discussed it and agreed the approach. It can still change, but the reasoning is recorded.
- `Draft` means the shape is right but detail is still being filled in.
- `Open` means we know the section is needed but have not worked through it yet. These are placeholders with notes on what must be resolved.

Nothing here is frozen until the first durable release (see section 11).

## 1. Purpose and goals

Status: `Settled`

The platform is sovereign, free and open source invoicing software, built and maintained in Europe, with the United Kingdom as the home country and first fully supported locale.

Primary goals:

- A lean, stable, reusable Core that is correct about money, identity of documents, and the integrity of the financial record.
- Country specific behaviour (tax rules, e-invoicing formats, legislative quirks) delivered as extensions, not baked into the Core.
- Compliance taken seriously from the first line, in particular an immutable, auditable financial record that assumes the host machine may be compromised.
- A clean extension model that allows both open source community extensions and proprietary, third party hosted extensions, without the Core having to trust either blindly.

## 2. Guiding principles

Status: `Settled`

1. Build it right. Design decisions favour long term correctness over short term convenience. We do not take routes that force a future rewrite to escape.
2. Assume the box is compromised. The operator controls the machine, the clock, the database and the local keys. Security properties that depend on trusting the operator are treated as worthless. Trust comes from external anchors and from third party verifiability.
3. The Core is lean. The Core owns only what must be central: document identity and numbering, the financial ledger, the canonical data model, permission enforcement, and event brokering. Everything else is an extension.
4. Self describing data. Records carry enough metadata to be read, verified and migrated by software that has no access to the Core's source code, including a future reimplementation in another language.
5. Tamper evidence, not tamper prevention. We cannot prevent a determined operator from altering their own data. We make any alteration detectable after the fact by an independent party. The break is the product.

## 3. Scope and non goals

Status: Settled

In scope for the Core:

- Customer, product and document data models.
- Draft creation and editing.
- Issuing documents (invoices, credit notes) as immutable, numbered, chained
  ledger events.
- The tamper evident financial ledger, anchoring and verification.
- Signing and key handling.
- The extension runtime, permission model and event broker.
- Authentication as an OIDC relying party.
- Two principal types: Instance Admin and Company, with separate session
  management.
- A CLI recovery path for IdP lockout.

The data models are the canonical structures all extensions build on: field
complete against EN 16931 (section 7), lean on behaviour, not on data. Drafts
are fully mutable, not chained, not signed; mutability ends at issue
(section 11.7). Issuance is a single serialised atomic transaction covering
number allocation, snapshot, hash, sign and append (section 12). The ledger,
anchoring and verification subsystems are specified in sections 11, 13
and 14. Key handling covers the instance signing key for ledger events and
verification of extension manifest signatures against pinned or GWS root keys
(section 10.2). The extension runtime covers manifest validation, permission
enforcement, sandboxing and the brokering of all events; extensions never
hold a direct channel to one another (sections 8 to 10).

On authentication, the Core never stores or verifies credentials. The default
deployment bundles a lightweight, preconfigured IdP; bring your own IdP is a
configuration change. Machine to machine auth (extensions, API clients) uses
OAuth client credentials against the same IdP. Instance Admin covers service
administration, Company covers day to day operation; client access, where
offered, is scoped under a Company. IdP lockout recovery is local CLI only:
the platform owner can extract data or re link the Core to a new IdP and
re map accounts. It is never a remote action.

Explicit non goals for the Core:

- A user interface.
- Identity provision.
- Tax calculation logic.
- Country specific e-invoicing format generation.
- Double entry bookkeeping.
- Payroll.
- Presentation customisation by third parties.
- Bank connectivity and reconciliation.

The Core is headless: all UI is extension territory, including the first
party one, which consumes the same contract as any other extension.
Credential storage, login flows and MFA belong to the IdP. Tax logic and
e-invoicing format generation are extension territory (sections 15 and 7),
though the Core data model must be field complete enough to feed any required
format. Double entry bookkeeping is core extension territory: a projector
folding ledger events into a chart of accounts, inheriting the ledger's
tamper evidence; the Core's obligation is only that events carry enough
detail to derive postings. Payroll is a possible future core extension, not a
commitment. Presentation customisation by third parties (banners, promotions
and similar) must not leak into the Core. Bank connectivity and
reconciliation are proprietary feature extension territory.

Platform ambition: the long term trajectory is full accounting capability
delivered through extensions. The Core remains invoicing scoped.

## 4. System overview

Status: `Settled`

The platform is a Core plus a set of extensions. Extensions come in two types:

- Core extensions: owned by GWS, maintained kernel style with merge requests from their maintainers, signed by a GWS root key, loaded into the Core's trust zone. They have a kill switch (see section 8).
- Feature extensions: built by anyone, signed by their own author, sandboxed, never inside the Core's trust zone.

An extension's type is derived from who signed it and where it loads from, not from any self declared field. A feature extension cannot become a Core extension by claiming to be one.

Extensions may run inside the deployment's Docker Compose (local) or be hosted by a third party (for proprietary code, for example bank statement reconciliation).

All communication is over gRPC on HTTP/2 with mutual TLS. The Core acts as the broker for all events. Extensions never hold a direct channel to one another.

## 5. The Core

Status: `Settled`

Core responsibilities:

- Own the canonical data models for customers, products and documents.
- Allocate document numbers (gapless, see section 12).
- Own and protect the financial ledger (section 11).
- Enforce the permission model and broker events between extensions (sections 9 and 10).
- Provide a rich enough document data model that any required e-invoicing format can be generated by an extension (section 7).

What the Core deliberately does not do is listed in section 3.

## 6. Money and precision

Status: `Settled`

Two distinct numeric concepts, both decimal, never floating point.

- Money amounts: scoped to a currency and quantised to that currency's minor unit (2 decimal places for GBP, 0 for JPY, 3 for some). This is what lands on a document line and in the ledger.
- Rates and unit prices: high scale decimals, for example `NUMERIC(28, 12)` in PostgreSQL, `Decimal` in Python. Computation multiplies quantity by rate at full precision, then quantises to the money type once, at line level.

Floating point is forbidden for any monetary or rate value. Binary representation error compounds across line items and breaks reconciliation, which is the one class of bug the platform cannot ship.

Rounding strategy (per line versus per total) is jurisdiction dependent and is therefore configurable, owned by the tax extension, not hard coded in the Core (see section 15).

## 7. Invoice data model

Status: `Draft`

The Core invoice model must be structurally complete enough that an extension can emit any required structured e-invoicing format without the Core having to change.

North star: the EN 16931 semantic data model. The Core carries the fields EN 16931 defines (legal registration identifiers, payment means, tax breakdowns and so on) even where a given deployment does not use them yet.

This is the resolution of the lean Core tension: lean means lean on behaviour, not lean on data. Logic lives in extensions, but the data model must be field complete from the start, because no extension can emit a field the Core never captured.

Open detail: a full field mapping against EN 16931 still needs to be produced.

## 8. Extensions

Status: `Settled`

### 8.1 Core extensions

- Owned by GWS, maintained kernel style, merge requests accepted from their maintainers.
- Signed by a GWS root key, ideally held offline or on hardware.
- Loaded into the Core's trust zone.
- Kept lean. The spec discourages Core extension development by default and rejects feature extensions that try to enter the Core under the guise of being core.
- Carry a kill switch: the Core checks a GWS signed revocation list and can disable a Core extension if a vulnerability is found. The revocation list must also work offline for air gapped deployments, so it is bundled in updates with an optional online check.

### 8.2 Feature extensions

- Built by anyone, signed by the author.
- Sandboxed, never inside the Core's trust zone.
- Trust model is self signed with key pinning, trust on first use (see section 10).

### 8.3 Hosting

Extensions may be:

- Local: a service in the deployment's Docker Compose.
- Third party hosted: a remote service, typically for proprietary code such as bank reconciliation.

## 9. Core to extension communication

Status: `Settled`

Transport: gRPC over HTTP/2 with mutual TLS.

- Persistent channels with keepalive. The TLS and mTLS handshake is paid once at link time, not per call. Channels are established on link and kept warm.
- The Core is the event broker. Extensions publish to and subscribe through the Core. There is no direct extension to extension channel, so every event hop is governed by the permission manifest and is auditable. Each extension therefore holds exactly one connection.
- Request and response plus event streams, both over gRPC. For the event plane the Core acts as broker over bidirectional streams rather than introducing a separate message broker, which keeps the Core lean and avoids extra infrastructure.

Robustness requirements, all to be enforced in the contract:

- A deadline on every remote call. Nothing hangs forever.
- An idempotency key on every mutating call. Mutations are deduplicated on the key so that a retried call cannot, for example, record a payment twice.
- Retry with exponential backoff and jitter, for idempotent calls only. Never auto retry a mutation without its idempotency key.
- A circuit breaker. An unhealthy extension fails fast and is surfaced to the user rather than being hammered.
- gRPC health checking protocol for liveness.

Contract versioning: the gRPC schema and capability set are explicitly versioned and negotiated at handshake. Protobuf evolution rules apply, in particular fields are never renumbered.

## 10. Permissions and the manifest

Status: `Settled`

The model is phone style: declare, then grant once at install, then enforce at runtime.

### 10.1 Manifest contents

A static, signed document declaring at least:

- Extension identity and version.
- The permissions required (network, filesystem, specific Core capabilities).
- Events published and subscribed (`publishes`, `subscribes`), namespaced.
- Declared data residency (see section 16).

The Core reads the manifest and presents the requested permissions to the user before linking. On acceptance, the Core establishes the secure connection.

### 10.2 Signing

- Format: JWS (JSON Web Signature) with EdDSA over Ed25519. JWS signs a base64url encoded copy of the exact payload, which removes any ambiguity about which bytes were signed and avoids JSON canonicalisation pitfalls.
- Core extensions: signed by the GWS root key, whose public key ships baked into the Core. No GWS signature means it does not load as core.
- Feature extensions: self signed with key pinning, trust on first use. The user sees the author identity at install, the Core pins the key, and on update the Core verifies the new manifest is signed by the same key. A different signer is flagged and rejected.
- The signature covers the permission set, the extension identity and the version.
- A permission increase on update triggers fresh user consent, exactly as a phone re-prompts when an app update wants new permissions. Same key and same permissions means a silent update. Same key and more permissions means re-consent. Different key means reject.

### 10.3 Runtime enforcement

The manifest is a logical grant. The runtime must enforce it:

- Local extensions run as separate containers with no direct database access and network policies restricting them to the Core's gRPC endpoint.
- The manifest stating "no filesystem access" is made true by the sandbox, not just promised.

### 10.4 Secrets

Extension credentials (for example bank API keys) are not stored in the manifest. The Core injects secrets into an extension securely at link time. Mechanism to be specified.

## 11. The financial ledger

Status: `Settled`

### 11.1 Domain framing

The financial record is modelled as an append only, hash chained event store, the ledger. This is not an exotic pattern bolted on for security. A ledger has been append only and immutable for roughly five hundred years: entries are never erased, corrections are posted as reversing entries. We are modelling accounting the way accounting works.

### 11.2 Scoped event sourcing

- The financial facts (issued invoices, payments, credit notes, adjustments) are event sourced. The event is the source of truth.
- Operational data that is not a ledger fact (customers, products, drafts, settings) stays in conventional, mutable models.
- Any current state representation of a financial fact (an invoice's status, a balance) is a projection derived from the events, rebuildable by replay, never independently editable.

The rewrite trap to avoid is the inverse: an editable invoice row treated as truth with an audit log bolted alongside. That guarantees a future rewrite and is exactly what existing tools got wrong.

### 11.3 Event record

Each event in the append only log carries roughly:

```
event_log   (append only: only INSERT and SELECT permitted)
seq            gapless sequence number, per chain
event_type     "invoice.issued" | "invoice.paid" | "invoice.voided" | ...
payload        immutable snapshot of the document at this moment
payload_hash   H(canonical(payload))
prev_hash      this_hash of the previous event (fixed constant at seq 0)
this_hash      H(seq || event_type || payload_hash || prev_hash || recorded_at)
recorded_at    local timestamp (recorded, never trusted as legal time)
signature      sign(this_hash) with the instance key
schema_version event schema version, for upcasting
hash_alg       e.g. "sha256", for crypto agility
canon_scheme   e.g. "JCS / RFC 8785", so the hash is reproducible by others
```

Because `this_hash` folds in `prev_hash`, each record links to the one before it. Altering any past record changes its hash and breaks every record after it, which forces a full chain rebuild to stay consistent. The rebuild is what external anchoring catches (section 13).

### 11.4 Self describing records and reading them

- Records are self describing (`schema_version`, `hash_alg`, `canon_scheme`) so that an auditor, a tax authority or a future provider can verify and migrate them with no access to our code.
- The event store only appends and reads in order.
- An upcaster reads an old version event and lifts it into the current shape in memory, chained one version step at a time. Immutable events live forever, so the code must be able to read every version ever written. Versioned events and upcasters are mandatory from the first durable event.
- A projector folds events into a current state read model. The projection is disposable and rebuildable, never authoritative.

### 11.5 Serialisation

The payload must be serialised in a portable, language neutral, self describing format with a deterministic canonical form, so the exact bytes hashed are unambiguous and a future non Python implementation can read and verify the chain. JSON (canonicalised, RFC 8785) versus protobuf is an open sub decision.

### 11.6 Append only enforcement

Enforced at the database, not only in application code. The application's database role is granted only INSERT and SELECT on `event_log`, and a trigger raises on UPDATE or DELETE. A compromised superuser can still bypass this, which is what the chain and the anchor exist to catch. Three rings: role permissions stop accidents, the chain catches edits, the anchor catches rebuilds.

### 11.7 Mutability model

- Draft: fully mutable, not chained, not signed.
- Issue: the one way door. On transition the document is snapshotted, hashed, chained, signed, and becomes an immutable event.
- Paid, void, corrected: new append only events that reference the original, never edits to it. A correction is a credit note plus a fresh invoice, both chained.

### 11.8 Schema freeze

The event schema (v1) is frozen at the first release whose events are promised to be durable, not necessarily the first public release. The durability promise is set explicitly per release channel: alpha disposable, beta to be decided, stable durable. The first durable event is a one way door.

## 12. Issuing documents

Status: `Settled`

Issuing a document is a single atomic transaction, and a deliberately serialised one. Inside one transaction, with a lock held:

1. Lock and allocate the next number. Numbering is gapless and must only advance on commit.
2. Snapshot, hash and sign.
3. Append the event, with `prev_hash` set to the current chain tip.
4. Update the projection and flip the draft to issued.

Issuance is serialised for two reasons:

- Gapless numbering cannot use a database sequence or autoincrement, because those are non transactional and gap on rollback, which the law forbids. Instead a counter row is taken with a row lock (`SELECT ... FOR UPDATE`) and incremented inside the transaction, so it only sticks on commit and rolls back cleanly.
- The chain tip is a second serialisation point. `prev_hash` must be the current tip, so concurrent appends would fork a chain that must stay linear. The same lock protects both.

At invoice volumes single file issuance is a non issue, and the correctness it buys is non negotiable.

The boundary that matters: hashing and signing stay inside the transaction (microsecond work), but anything slow or external stays outside it. The anchor call, PDF generation and customer email all happen after commit. Anchoring is its own batched, out of band job. A network round trip held inside a row lock would serialise every issue behind the slowest call in the system.

Further requirements:

- Idempotent issue. Inside the locked transaction, check the draft is still in draft status. If it has already been issued, return the existing event rather than minting a second document. This protects against double clicks and retries after a timeout that actually succeeded.
- Numbering is plural. Invoices and credit notes use separate sequences, and some jurisdictions reset numbering annually. The number allocator is pluggable per document type and period (extension territory). The hash chain, by contrast, is singular and global: one chain, many numbering sequences threaded through it.
- `recorded_at` is a claimed local time, hashed into the event. It is the anchor, not the local clock, that substantiates when the claim was made.

## 13. External anchoring

Status: `Settled`

### 13.1 Why

Local signing and a local clock prove integrity, not time, against an operator who controls the key and the clock. To make a rebuild detectable, the chain's current state is committed periodically to somewhere the operator cannot retroactively rewrite.

### 13.2 What is anchored

A Merkle root over the events in the segment since the last anchor. Anchoring a Merkle root rather than the bare tip hash costs nothing extra now and enables compact inclusion proofs later: proving a single document is committed under an anchored root without revealing or re-walking the whole chain.

### 13.3 Where

Anchored to multiple authorities for redundancy and, more importantly, to avoid a single point of trust or coercion:

- RFC 3161 timestamping authorities (the standard tool). Free options exist.
- A GWS anchor service (optional, vendor anchored, breaks air gap so it is optional).
- Optionally a public transparency log, or OpenTimestamps anchoring to Bitcoin for the paranoid.

If everything anchored only to GWS, GWS would be a single point of failure and a single point of coercion. Plural anchors mean that even if one disappears or is compromised, the others hold the line.

### 13.4 Trust of the anchor source

The list of acceptable anchor authorities ships as part of the GWS signed Core, not as an operator editable config value, otherwise the operator simply adds their own authority and self validates. Verification prefers publicly known authorities so that an independent auditor needs nothing from the operator's machine.

### 13.5 GWS as an anchor authority

If GWS runs an anchor service:

- It becomes critical infrastructure, with an availability commitment and custody of a crown jewel signing key (offline or hardware backed, with a rotation plan).
- It should append every committed root to a public, append only transparency log, so that GWS itself cannot backdate and the pitch becomes "verify us" rather than "trust us". This protects both customers and GWS.

### 13.6 Regulatory boundary

In the EU, qualified timestamps are a regulated service provided by accredited Qualified Trust Service Providers under eIDAS. GWS should not chase QTSP accreditation early. GWS provides non qualified anchoring, which is sufficient for tamper evidence, and where a jurisdiction requires qualified timestamps the Core anchors to an existing QTSP. (Flag, not legal advice. To be confirmed with a specialist.)

### 13.7 Free tier

The free, self hosted default ships with anchoring to free public TSAs, so a self hoster gets real, auditable tamper evidence at no cost. The Core is never deliberately made non compliant to force an upgrade. Paid tiers sell convenience: a managed GWS anchor with an SLA, longer proof retention, the hosted transparency log, and audit export reports.

## 14. Verification

Status: `Settled`

Verification runs in layers, from cheap and local to slow and external. Only the last layer catches the operator.

1. Chain integrity. Walk genesis to tip. For each event, recompute `this_hash` from its stored fields using the record's own declared method, and check it matches. Check `prev_hash` equals the previous event's `this_hash`, and that `seq` is contiguous. Catches edits, insertions, deletions and reorders. Does not catch a full rebuild.
2. Signatures. Verify each event's signature against the signing key. Catches forgery by anyone without the key. Against the operator, proves integrity but not honesty about time.
3. Anchors. For each historical anchor, walk the current chain to that point, recompute the root, and check it still equals the anchored value, and that the timestamp token verifies against the authority's public certificate. A mismatch means history was rewritten after the anchor. Anchors also give a time floor: everything up to that point provably existed by then.

Critical subtlety: anchors must be sourced independently of the operator. If the only copy lives in the operator's database, they delete the inconvenient ones. The anchor history must be durable somewhere they cannot prune (the transparency log, the GWS anchor, the TSA's own records). The auditor fetches anchors from there, not from the box under audit.

Two modes:

- Self check: the scheduled job the instance runs on itself (layers 1 and 2, plus anchors against locally stored copies). Catches corruption and partial tampering automatically, can alert. A malicious operator can disable it, so it is a health monitor, not proof.
- Independent audit: all three layers, anchors sourced externally, tokens re-checked against public certificate authorities. Trustworthy because it needs nothing from the operator beyond the chain itself.

Forensics: a failure localises. A `this_hash` mismatch at seq K points at K's content, a `prev_hash` mismatch at an insertion or deletion around K, an anchor mismatch covering up to seq N at history rewritten after that anchor's time. Comparing which anchors still reconcile brackets when the tampering happened.

Performance: walking from genesis is O(n). The routine self check verifies incrementally from a stored checkpoint, but a real audit re-walks from genesis or from the earliest independently held anchor, because incremental trusts everything before the checkpoint. Anchored segments are self contained and can be verified in parallel.

Two rules:

- Never self heal. A detected break is preserved and surfaced, never repaired. Repair means rewriting, which destroys the evidence. The break is the product.
- A clean run is evidence. Emit a signed verification report (verified to seq N, tip H, anchors checked and consistent, as of date). This is the artefact an auditor wants and a natural part of the paid audit export tier.

## 15. Compliance and localisation

Status: `Open`

Tax logic is extension territory and is where country specifics explode: reverse charge, EU OSS, place of supply, multiple rates per line, inclusive versus exclusive pricing, and the genuinely divergent question of rounding per line versus per total. The Core provides primitives, the tax extension provides logic.

Structured e-invoicing mandates (PEPPOL and EN 16931, Factur-X and ZUGFeRD, FatturaPA, SII) are spreading and the formats and deadlines are a moving target. Format generation is an extension, but the Core data model must be field complete enough to feed them (section 7).

To resolve: the tax primitive interface the Core exposes, the rounding strategy hook, and a concrete list of first wave countries from the community poll.

## 16. Data protection and sovereignty

Status: `Open`

The permission manifest grants an extension access to data but says nothing about returning or deleting it. A third party hosted extension holding personal data creates a processor relationship and a right to erasure obligation that must propagate to that extension. Right to erasure across a distributed extension system is hard and must be designed, not assumed.

Data residency: a feature extension hosted outside the UK or EU undermines the sovereignty claim. The manifest declares residency and the Core surfaces or blocks accordingly.

To resolve: the erasure propagation protocol and the residency policy enforcement.

## 17. Operational concerns

Status: `Open`

- Backup and restore consistency. Once the Core and extensions each own data, a backup is a distributed snapshot problem. Restoring the Core to an earlier point with an extension at a later one creates silent inconsistency. Decide whether extension state is reconstructable from Core events or needs coordinated snapshots.
- Observability. Correlation identifiers (OpenTelemetry context) propagated across gRPC calls, so a flow crossing the Core and several extensions can be traced when it breaks.
- Secrets management. Cross reference section 10.4.
- Rate limiting. The Core rate limits per extension to contain a buggy or malicious one.

## 18. Licensing

Status: `Open`

The Core licence shapes the business model. If the Core is AGPL, the network boundary between the Core and extensions is also the copyleft boundary, since a network call is not linking, which lets proprietary feature extensions sit cleanly on the far side. The licence should be chosen deliberately with the proprietary extension model in mind, not discovered later.

To resolve: confirm the Core licence and the contribution and copyright assignment policy.

## 19. Glossary

- Event store / ledger: the permanent, sequential, append only, auditable set of records.
- Upcaster: a run time converter that reads an old schema version event into the current schema.
- Projector: builds a current state read model from events. Disposable and rebuildable.
- Anchor: a periodic commitment of the chain's Merkle root to an external authority that the operator cannot rewrite.
- Manifest: a signed, static declaration of an extension's identity, version, permissions and event topics.
- Core extension: GWS owned, GWS signed, kernel style, in the Core trust zone.
- Feature extension: third party, self signed, sandboxed, outside the trust zone.

## 20. Open questions

- Product name.
- Single living spec or a set of RFCs for the deep dives.
- Payload serialisation: canonical JSON versus protobuf.
- Full EN 16931 field mapping for the Core invoice model.
- Tax primitive interface and rounding strategy hook.
- Erasure propagation protocol and residency enforcement.
- Backup and restore consistency strategy.
- Secrets injection mechanism.
- Core licence and contribution policy.
- First wave countries from the community poll.