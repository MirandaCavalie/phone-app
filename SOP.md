# SOP: Demo offline de Barrio Mesh

## Qué hace

Barrio Mesh incluye un agente personal que convierte una descripción cotidiana en una necesidad u oferta revisable. Luego conecta iPhones cercanos sin internet, conserva la información localmente, encuentra coincidencias y exige confirmación humana antes de coordinar. WhatsApp es solo una salida opcional cuando hay internet.

## Por qué se construyó así (build/buy/kill)

**Build:** se construyó un prototipo nativo porque la hipótesis de la hackathon es demostrar un agente personal que sigue siendo útil cuando desaparece la nube. Comprar un chatbot o usar una API remota rompería esa hipótesis. En teléfonos elegibles se usa el modelo de Apple en el dispositivo; en todos los demás se usa un intérprete determinista local, evitando que la demo dependa del hardware. Si las pruebas con dos iPhones no logran conexiones estables en primer plano, se debe presentar únicamente la simulación sin afirmar que existe conectividad real. A 10× de uso, antes de ampliar funciones se necesitan pairing autenticado, pruebas de campo, controles de abuso y una evaluación de las restricciones de background de iOS.

## Cómo correrlo

1. Instalar Xcode 15 o posterior en una Mac.
2. Clonar el repositorio:

   ```bash
   git clone https://github.com/MirandaCavalie/phone-app.git
   cd phone-app
   ```

3. Validar la lógica independiente de iOS:

   ```bash
   swift build
   swift run CoreChecks
   ```

4. Abrir `BarrioMesh.xcodeproj` en Xcode.
5. Seleccionar el target **BarrioMesh** y abrir **Signing & Capabilities**.
6. Elegir el Personal Team de la persona que hará la demo.
7. Si Xcode rechaza el bundle ID, reemplazar `com.mirandacavalie.barriomesh` por uno único.
8. Conectar el primer iPhone, confiar en la Mac, habilitar Developer Mode y ejecutar la app.
9. Repetir el paso anterior con el segundo iPhone.
10. Aceptar Bluetooth y Local Network en ambos teléfonos.
11. Mantener la app abierta en primer plano en ambos dispositivos.
12. Esperar a que ambos indiquen **1 teléfono conectado**.
13. En **Agente**, describir una necesidad en lenguaje natural, revisar el borrador estructurado y publicarlo.
14. En el otro teléfono, describir una oferta compatible y revisar el borrador antes de publicar.
15. Abrir **Matches**, confirmar en ambos teléfonos y luego marcar la ayuda como entregada en ambos.
16. Para probar el handoff, tocar **Abrir en WhatsApp**, elegir un contacto y revisar el mensaje antes de enviarlo. Este paso necesita internet y nunca envía automáticamente.

Para ensayar sin dispositivos, usar **Red → Cargar un caso de prueba local**. Ese modo solo demuestra la interfaz y no prueba la conexión.

## Entradas y salidas

- **Entrada:** texto cotidiano escrito al agente o publicaciones creadas manualmente, con tipo, recurso, cantidad, prioridad, zona aproximada, vencimiento y nota opcional. También entran estados JSON recibidos directamente desde otros iPhones.
- **Salida:** publicaciones sincronizadas, coincidencias ordenadas localmente y propuestas con estados de aprobación y entrega. Todo se guarda como JSON en Application Support del iPhone. Si la persona toca **Abrir en WhatsApp**, se genera un enlace `wa.me` con un mensaje prellenado que contiene recurso, cantidades, nombres, zona aproximada y estado.

## Casos límite conocidos

- Una persona no puede hacer match con su propia publicación.
- Si Apple Intelligence no está disponible, el agente cambia automáticamente al intérprete determinista local.
- Si el agente no reconoce un recurso o una zona, el borrador lo marca como pendiente y la persona lo completa antes de publicar.
- Si el texto parece contener una dirección exacta, el agente no la copia al borrador y solicita una zona aproximada.
- Las solicitudes médicas solo se clasifican como recursos; el agente no diagnostica ni recomienda dosis. Frases de riesgo muestran una advertencia para llamar al 911 cuando sea posible.
- Las publicaciones cerradas o vencidas no generan nuevos matches.
- Una oferta con cantidad menor puede mostrarse como ayuda parcial; la cantidad queda visible para aprobación humana.
- Dos aprobaciones realizadas al mismo tiempo se unen sin que una sobrescriba la otra.
- Si no hay peers, el cambio permanece guardado y se envía cuando aparece una conexión.
- Si ambos teléfonos se invitan simultáneamente, el identificador lexicográficamente menor inicia la conexión para evitar sesiones duplicadas.
- La app deja de descubrir teléfonos de manera confiable al pasar a segundo plano; mantenerla abierta.
- Con dos teléfonos se prueba sincronización directa. Se necesita un tercero para probar un relay A → B → C.
- El botón para borrar datos afecta solo al teléfono actual. Si otro peer todavía conserva publicaciones, puede retransmitirlas; para una limpieza total, cerrar la app y borrar los datos en todos los dispositivos.
- Los dispositivos cercanos con esta misma versión se aceptan automáticamente. Esto es solo para la demo; no es un modelo de confianza apto para producción.
- No hay mapa offline ni ubicación precisa. La zona es texto ingresado por la persona.
- WhatsApp no funciona sin internet y puede abrir WhatsApp Web si la app no está instalada. La persona siempre debe escoger el contacto y confirmar el envío.

## Umbral de aprobación humana

El agente solo propone un borrador: una persona debe revisarlo y tocar **Publicar**. El matching es automático, pero la necesidad y la oferta deben ser confirmadas por ambos autores; después, ambos marcan la entrega. El handoff a WhatsApp solo prepara texto: elegir destinatario y enviar son acciones humanas. No se revelan direcciones exactas, no se hacen pagos y no se toman decisiones médicas. Cualquier caso de primeros auxilios requiere intervención humana y los servicios oficiales siguen teniendo prioridad.

## Mantenimiento

Revisar el proyecto cuando cambien iOS, Foundation Models, los permisos de Local Network/Bluetooth, `MultipeerConnectivity` o el formato de enlaces `wa.me`. Los modelos de Apple pueden cambiar con una actualización del sistema: repetir las frases de prueba y confirmar el fallback. Cualquier cambio a `MeshPost`, `MatchProposal` o `MeshWireMessage` debe incrementar `currentProtocolVersion` y agregar una migración. La persona responsable debe correr `swift test` y `swift run CoreChecks`, instalar en dos iPhones físicos y repetir el guion antes de cada demo.
