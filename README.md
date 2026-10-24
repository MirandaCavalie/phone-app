# Barrio Mesh

Barrio Mesh is an offline-first iPhone prototype for the **Personal Agents for San Francisco** hackathon. It lets nearby people publish structured needs and offers, exchange them directly between phones without an internet connection, and confirm a safe match together.

The product hypothesis is simple: during an outage, the useful network is the people already nearby. Each phone acts as a small personal agent that remembers what its person needs or can offer and coordinates only when it finds a compatible neighbor.

## What is implemented

- Native SwiftUI app for iOS 17+
- Direct encrypted sessions through `MultipeerConnectivity`
- Automatic nearby discovery while the app is open
- Offline JSON persistence on each phone
- Need and offer categories: water, power, transportation, translation, and first aid
- Deterministic local matching by resource, quantity, urgency, age, and approximate area
- Two-sided approval before a match is confirmed
- Two-sided completion before help is marked delivered
- Convergent merging of concurrent approvals
- Gossip behavior: newly learned state is sent to every currently connected peer
- Local demo data as a presentation fallback
- Optional WhatsApp handoff with a pre-filled, privacy-conscious match summary
- No account, SIM card, server, cloud model, or API key

## Architecture

```text
SwiftUI views
     │
     ▼
AppModel ─────────────── PeerSession
     │                  MultipeerConnectivity
     ▼                         │
MeshStore                      │ encrypted local link
JSON on device                 ▼
     │                    nearby iPhone
     ▼
MatchEngine
deterministic + offline
```

The shared state is intentionally small. Every phone stores immutable posts plus match proposals whose approval, decline, and completion sets only grow. Merging uses set union, so two people can confirm while temporarily disconnected without one confirmation overwriting the other.

## Requirements

- A Mac with Xcode 15 or newer
- Two physical iPhones running iOS 17 or newer
- A free Apple developer account
- Bluetooth and Wi-Fi enabled on both phones
- Developer Mode enabled on both phones

The mesh does not require the phones to have SIM cards or internet access after installation. Opening a prepared match in WhatsApp is optional and does require internet access.

## Install on two iPhones

1. Open `BarrioMesh.xcodeproj` in Xcode.
2. Select the **BarrioMesh** target, then **Signing & Capabilities**.
3. Choose your Personal Team.
4. If Xcode reports that the bundle identifier is unavailable, change `com.mirandacavalie.barriomesh` to a unique value.
5. Connect the first iPhone, trust the Mac, select the phone as the run destination, and press **Run**.
6. Repeat with the second iPhone.
7. On both phones, accept the Bluetooth and Local Network permission prompts.
8. Keep Barrio Mesh open in the foreground on both devices.

A free Personal Team provisioning profile expires after seven days. Re-run the app from Xcode to renew it.

## Two-phone demo script

1. Put both phones in Airplane Mode.
2. Manually turn Bluetooth and Wi-Fi back on; do not connect them to an internet service.
3. Open Barrio Mesh on both phones.
4. Wait until each displays **1 teléfono conectado**.
5. On phone A, publish an urgent need for one power charge in `Mission`.
6. On phone B, publish an offer for three power charges in `Mission`.
7. Open **Matches** on both phones. The same match should appear.
8. Confirm on phone A. Phone B should show that one person has confirmed.
9. Confirm on phone B. Both should show **Encuentro confirmado**.
10. Optionally tap **Abrir en WhatsApp**, choose a contact, review the pre-filled summary, and send it. Nothing is sent automatically.
11. Mark the help delivered on both phones to close the interaction.

If connectivity fails during a presentation, open **Red → Cargar un caso de prueba local**. This is explicitly labeled as fallback demo data and does not pretend a peer is connected.

## Verification

The domain layer is also a Swift package so its most failure-prone behavior can be checked without an iPhone SDK:

```bash
swift build
swift run CoreChecks
```

`CoreChecks` verifies matching, convergent concurrent approvals, and disk persistence. XCTest versions of the same cases live in `Tests/BarrioMeshCoreTests` for wiring into an Xcode test target later.

## Deliberate limitations

- **Foreground only:** iOS suspends discovery and advertising when the app is backgrounded.
- **Two phones prove direct offline synchronization, not multi-hop relay.** A third device is needed to visibly prove A → B → C store-and-forward behavior.
- **Hackathon trust model:** devices running the same protocol connect automatically. A production version needs visual pairing codes, signed identities, blocking, and abuse controls.
- **No exact locations:** only user-entered approximate areas are exchanged.
- **No medical triage:** “first aid” means requesting or offering a kit or trained person. The app does not diagnose or prioritize medical conditions.
- **Not an emergency service:** it complements, but never replaces, 911 or official alerts.
- **No guaranteed delivery:** disconnected messages remain on the originating phone until another peer is encountered.
- **WhatsApp is not part of the offline mesh:** the button uses WhatsApp's universal link to prepare a message. It needs internet and the user must choose a contact and confirm sending.

## Production path

The next technical milestones would be authenticated pairing, signed messages, background-friendly transport research, offline map tiles, accessibility and multilingual testing, relay expiration/hop limits, and field tests under realistic radio congestion. Those are intentionally outside this one-day prototype.
