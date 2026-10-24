# Faro — guion de pitch y demo (3 minutos)

> **Personal Agents Hackathon · SF · 24 oct 2026.** Los jueces buscan agentes que *se encarguen* de las cosas (llamadas, formularios, agenda, seguimientos), que funcionen en vivo y que la gente quiera seguir usando. Cada bloque de este guion responde a uno de esos criterios.

## Mensaje en una línea

**Faro es el agente personal que sigue trabajando cuando se cae todo: siente el sismo, avisa a tu familia, consigue lo que tu hogar necesita negociando con los agentes de tus vecinos por Bluetooth y te deja listos los trámites. Sin internet, sin servidores y sin API.**

Hecho en San Francisco para Latinoamérica: México 2017, Ecuador 2016… En cada sismo grande lo primero que colapsa es la red celular, justo cuando más la necesitas.

## Preparación (antes de subir)

- Dos iPhones con Faro instalado y el onboarding completo.
  - **A (Miranda):** vive con su mamá, que usa insulina, y no tiene agua guardada.
  - **B (Luis):** tiene 12 botellas y su reserva es de 8.
  - Ambos con el mismo **código de familia** si se quiere mostrar el aviso cruzado, o A con un familiar en un tercer teléfono.
- En **Perfil** de B, poner "Dar hasta 3 sin preguntar" para que aparezca la aprobación humana en vivo.
- **Modo avión en ambos**, y luego volver a encender solo Bluetooth y Wi-Fi, sin conectarse a ninguna red. La app abierta y en primer plano.
- **Plan B con un teléfono:** lanzar con `-faro-demo` o usar **Perfil → Simular vecinos cercanos**, y **Perfil → Simular sismo**. Todo lo simulado aparece marcado con "(simulado)" o un asterisco.

## Guion

| Tiempo | Qué se ve | Qué se dice |
|---|---|---|
| 0:00 | Teléfono A en la mano, pantalla "Todo tranquilo", puntaje de preparación | "Esto es Faro. Hoy me conoce: sabe que vivo con mi mamá, que ella depende de insulina y que no tengo agua guardada. Me dice qué me falta para estar preparada." |
| 0:20 | **Sacudir los dos teléfonos** | "Ahora imaginen que tiembla." |
| 0:25 | Alerta "¿Está temblando?". Como **dos teléfonos lo sintieron**, Faro se activa sin esperar la cuenta regresiva | "El acelerómetro detecta el sismo con el mismo algoritmo que usan los sismógrafos, STA/LTA. Y como el teléfono de Luis también lo sintió, se confirman entre ellos por Bluetooth y el agente arranca solo." |
| 0:40 | Inicio en modo emergencia, **radar** con Luis y la familia, registro "Lo que hizo Faro" | "Sin que yo toque nada: avisó a mi familia que estoy bien, pidió agua por mí y le propuso un encuentro al **agente** de Luis." |
| 1:00 | Teléfono B: **"¿Dar 4 botellas a Miranda?"** | "El agente de Luis tiene permiso para dar hasta 3 sin preguntar. Le piden 4, así que **le pregunta a Luis**. Esa es la regla: actúa solo dentro de los límites que tú le diste." Luis toca **Sí, hazlo**. |
| 1:15 | A: tarjeta **Encuentro acordado**, 4 botellas en el Parque de la 93 a las 15:45. **Faro lo dice en voz alta** | "Acuerdo cerrado entre dos agentes, con punto de encuentro público y hora. Y me lo dice en voz alta, porque en una emergencia nadie quiere mirar la pantalla." |
| 1:30 | Mantener el micrófono: **"¿Mi mamá está bien?"** | "Le hablo y me responde con el modelo de Apple **dentro del teléfono**, usando herramientas para consultar a mi familia, mis acuerdos y a los vecinos." |
| 1:50 | **Trámites listos**: guion para llamar al 123 y PDF del reporte | "También se encarga del papeleo: el guion para llamar al 123, que ya dice quién es vulnerable en mi casa, y el reporte de afectación prellenado para el registro de damnificados o la aseguradora." |
| 2:10 | Quitar el modo avión. **Familia**: mensajes listos para enviar | "Cuando vuelve la señal, los mensajes para mi familia ya están escritos. Los envío yo; el agente nunca manda nada solo." |
| 2:25 | Slide o README con la tabla del simulador | "No solo lo probamos con dos teléfonos: simulamos un barrio de 40 hogares con pérdida de enlaces y un atacante. Cubre el 98–100% de lo que los vecinos alcanzables podían compartir, con **cero sobrecompromisos y cero falsificaciones aceptadas**." |
| 2:45 | Cierre | "Firmas Ed25519, avisos familiares cifrados de extremo a extremo, todo en el teléfono. Faro: tu agente para el día que todo falla, y para estar preparado todos los demás días." |

## Preguntas probables de los jueces

- **"¿Dónde está la IA?"**
  - El cerebro de decisión es determinista a propósito: en una emergencia tiene que ser predecible, auditable y probado (50 tests más el simulador).
  - El lenguaje lo maneja Apple Foundation Models dentro del dispositivo: extrae el perfil del hogar a partir de una conversación y responde preguntas con *tool calling* sobre la memoria del agente.
  - Si el teléfono no tiene Apple Intelligence, hay un motor local que hace lo mismo.
- **"¿Qué pasa si alguien miente?"**
  - Cada mensaje va firmado y el ID del agente se deriva de su clave pública: nadie puede hablar por otro.
  - Las aprobaciones solo cuentan si vienen de los dos participantes.
  - Medicinas y primeros auxilios siempre requieren a un humano.
- **"¿Cuál es el alcance real?"**
  - MultipeerConnectivity llega a unas decenas de metros por teléfono.
  - El gossip salta de teléfono en teléfono, así que el alcance crece con la densidad de teléfonos.
  - El simulador muestra justamente eso: los hogares aislados son el límite, no el agente.
- **"¿Por qué alguien lo seguiría usando?"**
  - El modo normal es un asistente de preparación: qué falta en el kit, el código familiar y simulacros.
  - Es el mismo agente que el día del sismo ya sabe qué hacer.
- **"¿Funciona en segundo plano?"**
  - Hoy no: iOS suspende el descubrimiento de teléfonos. La app debe estar abierta, y lo decimos.
  - El siguiente paso es investigar Critical Alerts y BLE en segundo plano.

## Por qué este nombre

**Faro** se entiende igual en todo el español y se pronuncia fácil en inglés. Evoca exactamente el producto: una luz que guía cuando todo está oscuro y una señal que alcanza a otros. Lo comparamos con estas alternativas:
- **Minga:** muy latinoamericano, significa trabajo comunitario, pero es poco conocido en México y Venezuela.
- **Réplica:** tiene doble sentido, pero es demasiado negativo.
- **Aliado:** genérico.
- **Vecino:** describe la red, pero no al agente.
