# Faro

**The personal agent that keeps working when everything else fails.** Built in San Francisco for Latin America: when a big earthquake hits Mexico City, Quito or Bogotá, the cell network is the first thing to collapse, exactly when people need to reach family and find water, power or a ride.

Faro gets to know your household while things are calm: who lives with you, who depends on medicine or electricity, what you have stored, and who to tell. When the ground shakes or the network drops, it acts on your behalf, **entirely on the phone and over Bluetooth, with no servers, no accounts and no API keys**:

1. **Feels the earthquake.** An STA/LTA seismic trigger runs on the accelerometer, and nearby phones corroborate each other over Bluetooth.
2. **Tells your family you're OK.** An end-to-end encrypted check-in hops phone to phone until it reaches your family circle.
3. **Asks for what your household needs,** starting with the most vulnerable (for example, insulin for your mom).
4. **Offers what you can spare,** never touching the reserve you set.
5. **Negotiates with your neighbors' agents** (propose → counter → accept) on quantity, a public meeting point and a time. Urgent requests are served first and nobody is over-promised.
6. **Follows up** after the meeting time to close the loop.
7. **Handles the calls and the forms:** a 123/911 call script that names who is vulnerable, and a pre-filled damage and needs report exported as PDF.
8. **Talks and listens,** with on-device speech recognition and spoken updates.
9. **Leaves SMS/WhatsApp messages ready** for when signal returns. You tap send.

Anything outside the permissions you set ahead of time becomes a question in **"Faro necesita tu OK"**. Medicine and first aid always need a human.

> Built for the *Personal Agents for San Francisco* hackathon (Oct 24, 2026). The app UI is in Spanish. Pitch and demo script: [docs/PITCH.md](docs/PITCH.md).

## Architecture

```text
  Accelerometer ─► SeismicDetector (STA/LTA) ─┐      NWPathMonitor (outage)
                                               ▼              │
   AgentProfile ──► PersonalAgent.step()  ◄────┴──────────────┘ ◄── 20 s heartbeat (follow-ups)
   AgentPolicy        deterministic, auditable decision loop
                      │          │             │            │
               ActivityLog  PendingApproval  Outbox     Paperwork
           ("Lo que hizo     (human OK)    (SMS/WA)   (call script, PDF report)
             Faro", spoken)
                      │
   MeshState v4 ── posts · proposals · AgentMessage (negotiation) · SafetyCheckIn (sealed)
                   · SeismicReport · ItemSignature
                      │  grow-only sets merged by union, compacted → converges without a server
                      ▼
   MeshSecurity: Ed25519 signatures, key-derived agent ids, ChaCha20-Poly1305 family seal
                      │
   PeerSession (MultipeerConnectivity: Bluetooth + peer-to-peer Wi-Fi, encrypted session)

   AgentBrain: Apple Foundation Models on-device (profile extraction, Q&A with tool calling)
               └─ deterministic local engine on every other iPhone
```

**Why a deterministic core with an on-device LLM at the edges:** in an emergency the decisions (what to promise, to whom, when to ask a human) must be predictable, testable and explainable. Every action is logged with its reason. Language is where the model shines: understanding a household described in conversation, and answering questions by calling tools over the agent's memory.

| Layer | Files |
|---|---|
| Agent core (pure Swift, unit-tested) | `Sources/BarrioMeshCore/PersonalAgent.swift`, `AgentProfile.swift`, `AgentPolicy.swift`, `ProfileInterpreter.swift`, `Paperwork.swift`, `SeismicDetector.swift` |
| Shared state and security | `MeshModels.swift`, `MeshStore.swift`, `MeshSecurity.swift`, `MatchEngine.swift` |
| Evaluation | `NeighborhoodSimulation.swift`, `Sources/FaroSim` |
| On-device intelligence | `BarrioMesh/Agent/AgentBrain.swift`, `AgentInterpreter.swift`, `VoiceAgent.swift` |
| Runtime | `BarrioMesh/AppModel.swift`, `Agent/ConnectivityMonitor.swift`, `Agent/Seismometer.swift`, `Agent/IdentityStore.swift`, `Networking/PeerSession.swift` |
| UI | `BarrioMesh/Views/` (Home + radar, Quake alert, Family, Neighbors, Profile, Onboarding, Ask Faro, Paperwork), `Design/Theme.swift` |

## Security model

- **Self-certifying identities:** each phone has an Ed25519 key in the Keychain, and its agent id is derived from the public key. Every post, negotiation message, check-in and seismic report is signed, and peers drop anything unsigned, tampered or claiming someone else's id, even on first contact.
- **Approvals, declines and completions** are only accepted from the two participants of a handoff.
- **Family check-ins are sealed** with ChaCha20-Poly1305 under an HKDF-SHA256 key derived from the family code. Relaying phones see an opaque blob. The app suggests high-entropy four-part codes.
- **No exact addresses** ever leave the phone: only approximate neighborhoods and public meeting points.

## Evaluation

`FaroSim` runs a deterministic neighborhood under these conditions:
- Each household has its own agent, state and signing key.
- Phones gossip only with neighbors in Bluetooth range.
- Links fail at random.
- An attacker forges accepts and check-ins.
- Simulated humans answer approval requests after a few minutes.

```bash
swift run -c release FaroSim            # 40 households, 90 minutes, 60% link reliability
swift run -c release FaroSim 40 90 0.6 2026 1.5   # everyone in range
```

| Metric (seed 2026) | Sparse range | Everyone in range |
|---|---|---|
| Covered, out of what reachable neighbors could share | 98–100% | 100% |
| Urgent needs with help agreed | 54% | 86% |
| Median minutes to an agent-to-agent agreement | 3 | 2 |
| Relatives who learned their family is OK | 40/40 | 40/40 |
| Over-commitments | **0** | **0** |
| Forged items accepted | **0** (23 rejected) | **0** |
| All phones converged afterwards | yes | yes |

The harness has already caught three real bugs:
- a crash on the second sync
- a first-contact forgery hole
- over-commitment while a counter offer was pending

It now runs in CI.

## Run it

```bash
swift test                     # 50 tests: agent, negotiation, robustness, security, seismic, paperwork, simulation
swift run CoreChecks
swift run -c release FaroSim
```

Then open `BarrioMesh.xcodeproj` (the target keeps its technical name; the app displays as **Faro**), pick your Personal Team, and run it on two iPhones with iOS 17+. See [SOP.md](SOP.md) for the full two-phone demo.

**Rehearsal shortcuts:**
- `-faro-demo` starts simulated neighbors.
- `-faro-quake` plays the earthquake alert.
- `-faro-tab N` opens a tab and `-faro-sheet paperwork|chat` opens a sheet.
- In the app: **Perfil → Simular sismo / Simular vecinos cercanos / Simular corte de internet**.

## Deliberate limitations

- **Foreground only:** iOS suspends peer discovery in the background.
- **Range grows with phone density:** isolated households with nobody in Bluetooth range cannot be helped. The simulator measures exactly this.
- **Shaking detection is a "posible sismo",** not an official alert. One phone alone triggers a cancellable countdown; two or more corroborate.
- **No medical triage or emergency dispatch.** Faro complements 123/911 and never replaces them.
- **Speech and Apple Intelligence** depend on device support; the local engine keeps every flow working without them.
