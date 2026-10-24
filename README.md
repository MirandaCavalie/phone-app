# Faro

**A personal agent that keeps working when everything else fails.** Built in San Francisco for Latin America, where earthquakes and blackouts hit cities like Bogotá, Medellín, Caracas, Mexico City and Santiago.

Faro gets to know your household while things are calm: who lives with you, what you have stored, what you would need, and who to tell. When the network drops, it acts on your behalf, entirely on the phone and over Bluetooth:

1. **Detects the outage** and switches to emergency mode on its own.
2. **Tells your family you're OK.** A tiny check-in hops phone to phone until it reaches your family circle.
3. **Asks for what your household needs.** For example, insulin for your mom is published from your profile; no typing in a crisis.
4. **Offers what you can spare,** never touching the reserve you set.
5. **Negotiates with your neighbors' agents** (propose → counter → accept) on quantity, a public meeting point and a time.
6. **Follows up** after the meeting time to close the loop.
7. **Prepares SMS/WhatsApp messages** for when signal returns. You tap send.

Anything outside the limits you set ahead of time becomes a question in **"Faro necesita tu OK"**. Medicine and first aid always need a human.

> Built for the *Personal Agents for San Francisco* hackathon (Oct 24, 2026). App UI is in Spanish.

## Architecture

```text
              AgentProfile          AgentPolicy
        (on-device memory only)   (what it may do alone)
                     \                /
                      ▼              ▼
  NWPathMonitor ──► PersonalAgent.step()  ◄── timer (follow-ups)
  (outage = trigger)   deterministic, testable decision loop
                      │            │              │
                ActivityLog   PendingApproval   Outbox
             ("Lo que hizo Faro") (human OK)    (SMS/WhatsApp later)
                      │
     MeshState v2 ── posts · proposals · AgentMessage (negotiation) · SafetyCheckIn
                      │   grow-only sets, merged by union → converges without a server
                      ▼
               PeerSession (MultipeerConnectivity: Bluetooth + peer-to-peer Wi-Fi, encrypted)

  AgentBrain: Apple Foundation Models on-device (profile extraction + Q&A with tool calling)
              └─ falls back to ProfileInterpreter / OfflineAgent on any iPhone
```

| Layer | Files |
|---|---|
| Agent core (pure Swift, unit-tested) | `Sources/BarrioMeshCore/PersonalAgent.swift`, `AgentProfile.swift`, `AgentPolicy.swift`, `ProfileInterpreter.swift`, `MeshModels.swift`, `MeshStore.swift`, `MatchEngine.swift`, `OfflineAgent.swift` |
| On-device intelligence | `BarrioMesh/Agent/AgentBrain.swift`, `AgentInterpreter.swift` |
| Runtime | `BarrioMesh/AppModel.swift`, `Agent/ConnectivityMonitor.swift`, `Networking/PeerSession.swift` |
| UI | `BarrioMesh/Views/` (Home, Family, Neighbors, Profile, Onboarding, Ask Faro), `Design/Theme.swift` |

No accounts, servers, SIM cards, cloud models or API keys.

## Run it

```bash
swift test          # 20 tests, including a two-agent negotiation simulation
swift run CoreChecks
```

Then open `BarrioMesh.xcodeproj` (the target keeps its technical name; the app displays as **Faro**), pick your Personal Team, and run it on two iPhones with iOS 17+. See [SOP.md](SOP.md) for the full two-phone demo script. For a single phone, use **Perfil → Simular vecinos cercanos** or launch with `-faro-demo`.

## Deliberate limitations

- Foreground only: iOS suspends peer discovery in the background.
- Demo trust model: phones running the same protocol connect automatically; family codes are hashed, not cryptographically secured. Production needs signed identities and pairing.
- No exact locations, medical triage or emergency dispatch. Faro complements 123/911; it never replaces them.
- Multi-hop relay needs a third device to show visibly.
