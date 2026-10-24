# SOP: Demo de Faro, el agente personal que funciona sin internet

## Qué hace

Faro es un agente personal que vive en el iPhone. En tiempos normales conoce a tu hogar: quién vive contigo, qué tienes guardado, qué necesitarían y a quién avisar. Si tiembla y se cae la señal, actúa por ti dentro de los límites que le diste. Avisa a tu familia que estás bien, pide lo que falta, ofrece lo que sobra, negocia entregas con los agentes de los vecinos por Bluetooth, te da seguimiento y deja listos los mensajes para cuando vuelva la señal.

## Por qué se construyó así (build/buy/kill)

**Build.** La tesis es que un agente personal tiene que seguir siendo útil justo cuando la nube desaparece. Un chatbot en la nube o una API remota romperían esa tesis, y no existe un producto que se pueda comprar para combinar memoria personal, permisos previos y negociación entre agentes sin internet.

Decisiones concretas:
- **El cerebro del agente es determinista** (`PersonalAgent`): se puede probar, explicar y auditar, y funciona en cualquier iPhone.
- **El lenguaje natural va en el dispositivo** con Apple Foundation Models, incluido tool calling, cuando el teléfono lo soporta. En los demás hay un intérprete local.
- **Nunca se necesita una API key.**

**Kill:** si en las pruebas con dos iPhones no hay conexión estable en primer plano, se presenta solo el modo de vecinos simulados y se dice explícitamente que es una simulación.

**A 10× de uso:** antes de agregar funciones hacen falta identidades firmadas, pairing autenticado, límites de reenvío y pruebas de campo bajo congestión de radio.

## Cómo correrlo

1. Instalar Xcode 15 o posterior en una Mac.
2. Clonar el repositorio y validar la lógica del agente sin un iPhone:

   ```bash
   git clone https://github.com/MirandaCavalie/phone-app.git
   cd phone-app
   swift test
   swift run CoreChecks
   ```

3. Abrir `BarrioMesh.xcodeproj` en Xcode. El target y el bundle conservan el nombre técnico `BarrioMesh`; la app se muestra como **Faro**.
4. En el target **BarrioMesh** → **Signing & Capabilities**, elegir el Personal Team. Si el bundle ID está ocupado, cambiar `com.mirandacavalie.barriomesh` por uno único.
5. Instalar en dos iPhones con iOS 17 o posterior (Developer Mode activo) y aceptar Bluetooth y Red local.
6. En cada teléfono, completar el onboarding:
   - Nombre, país y barrio. El país define el número de emergencias: 123 en Colombia, 911 en Venezuela y México.
   - Describir el hogar en una frase.
   - Poner el mismo código de familia en ambos teléfonos si se quiere mostrar el "estoy bien".
   - Revisar los permisos.

**Guion con dos teléfonos:**
1. Configurar el teléfono A con una necesidad, por ejemplo "no tenemos agua guardada".
2. Configurar el teléfono B con suministros, por ejemplo "tengo 12 botellas de agua".
3. Poner ambos en modo avión y volver a encender solo Bluetooth y Wi-Fi, sin conectarse a ninguna red.
4. Faro se activa solo. Si un teléfono no detecta el corte, usar **Activar modo emergencia** o **Perfil → Simular corte de internet**.
5. Mostrar la pantalla **Faro** en ambos teléfonos:
   - el aviso a la familia
   - el pedido y la oferta publicados
   - la propuesta, la contraoferta o la aceptación entre agentes
   - el acuerdo con punto de encuentro y hora
6. Si algo requiere aprobación (medicinas, o una cantidad mayor al límite), aparece en **Faro necesita tu OK**.
7. Quitar el modo avión. En **Familia**, los mensajes preparados se abren por SMS o WhatsApp para que la persona los envíe.

**Con un solo teléfono:** abrir **Perfil → Simular vecinos cercanos**, o lanzar la app con el argumento `-faro-demo`. Aparecen "Luis (simulado)" con suministros y un familiar simulado en tu círculo, todo marcado como simulado.

## Entradas y salidas

- **Entrada:**
  - Texto del onboarding y del chat "Háblale a Faro".
  - Edición manual del perfil y de los permisos.
  - Estado JSON (`MeshWireMessage` v2) recibido de iPhones cercanos por MultipeerConnectivity.
  - El estado de conectividad del sistema (`NWPathMonitor`).
- **Salida:**
  - Publicaciones, propuestas, mensajes de negociación y check-ins sincronizados entre teléfonos.
  - El registro "Lo que hizo Faro".
  - Preguntas de aprobación.
  - Mensajes SMS o WhatsApp prellenados.
  - Todo se guarda como JSON en Application Support: `agent-profile.json`, `agent-policy.json`, `agent-memory.json` y `mesh-state.json`.
  - El perfil completo nunca sale del teléfono. Solo se comparten publicaciones pequeñas y check-ins.

## Casos límite conocidos

- Si la oferta es menor que el pedido, el agente que da contraoferta solo lo que tiene por encima de la reserva del hogar, y el que recibe acepta la ayuda parcial.
- Si todo lo disponible ya está comprometido, el agente rechaza con explicación.
- Dos teléfonos que negocian estando separados convergen: los mensajes son inmutables y se unen por conjunto.
- Cada necesidad tiene una sola negociación activa; no se propone a dos vecinos a la vez.
- Una pregunta descartada no se repite. Las preguntas que quedaron obsoletas, porque la negociación se resolvió por otro lado, se borran solas.
- Una persona dependiente sin reserva (por ejemplo, la mamá con insulina) genera un pedido urgente. Si es medicina, siempre requiere aprobación.
- Los check-ins solo los reconoce quien tiene el mismo código de familia. El código no se transmite; se transmite un hash corto. **No es seguridad criptográfica.**
- Los datos guardados por la versión 1 se siguen leyendo. Los teléfonos con protocolo 1 no se conectan con los de protocolo 2.
- iOS suspende el descubrimiento en segundo plano: la app debe estar abierta en ambos teléfonos.
- Con dos teléfonos se prueba la sincronización directa; para probar un relevo A → B → C hace falta un tercero.
- Algunos teléfonos no reportan el corte si siguen conectados a un Wi-Fi sin salida a internet. Para esos casos están el botón manual y el interruptor de simulación.
- "Borrar todo" afecta solo a este teléfono. Otros teléfonos pueden volver a retransmitir lo que conservan.
- Los vecinos simulados no se guardan; al relanzar la app se reconstruyen sin duplicar publicaciones.

## Umbral de aprobación humana

El agente actúa solo únicamente dentro de `AgentPolicy`:
- activar el modo emergencia al perder internet
- avisar "estoy bien"
- publicar necesidades
- ofrecer excedentes
- aceptar ayuda
- comprometer hasta N unidades por entrega (3 por defecto)

Requiere aprobación humana:
- **Siempre:** cualquier publicación o compromiso de **medicamentos o primeros auxilios**.
- Cualquier entrega por encima del límite autorizado.
- Cualquier permiso que la persona haya desactivado.
- Confirmar que una entrega se concretó (el seguimiento pregunta, no asume).
- **Enviar mensajes:** el agente los prepara, pero el envío por SMS o WhatsApp lo hace la persona.

Además, el agente no diagnostica, no recomienda dosis, no comparte direcciones exactas y no reemplaza al 123/911.

## Mantenimiento

Revisar cuando cambien:
- iOS
- Foundation Models (la API de `Tool` y `@Generable` ya cambió entre versiones)
- los permisos de Bluetooth y Red local
- MultipeerConnectivity
- los esquemas de URL `sms:` y `wa.me`

Cualquier cambio a `MeshPost`, `MatchProposal`, `AgentMessage`, `SafetyCheckIn` o `MeshState` debe subir `MeshWireMessage.currentProtocolVersion` y mantener la decodificación de datos viejos.

Antes de cada demo, la persona responsable (Miranda) corre `swift test` y `swift run CoreChecks`, instala en dos iPhones físicos y repite el guion.
