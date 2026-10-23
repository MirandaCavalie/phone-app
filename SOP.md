# SOP: Demo offline de Barrio Mesh

## Qué hace

Barrio Mesh conecta iPhones cercanos sin internet para compartir necesidades y recursos durante una interrupción. Cada teléfono conserva la información localmente, encuentra coincidencias y exige que ambas personas confirmen antes de coordinar una entrega.

## Por qué se construyó así (build/buy/kill)

**Build:** se construyó un prototipo nativo y pequeño porque la hipótesis de la hackathon es precisamente demostrar sincronización y coordinación directa entre teléfonos sin servidor; una herramienta comprada no demostraría esa capacidad. Se eligieron APIs incluidas en iOS y lógica determinista para obtener valor en un día y eliminar costos de infraestructura. Si las pruebas con dos iPhones no logran conexiones estables en primer plano, se debe detener el desarrollo del “mesh” y presentar únicamente la simulación, sin afirmar que existe conectividad real. A 10× de uso, la decisión cambia: antes de ampliar funciones se necesitan pairing autenticado, pruebas de campo, controles de abuso y una evaluación específica de las restricciones de background de iOS.

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
13. Publicar una necesidad en un teléfono y una oferta compatible en el otro.
14. Abrir **Matches**, confirmar en ambos teléfonos y luego marcar la ayuda como entregada en ambos.

Para ensayar sin dispositivos, usar **Red → Cargar un caso de prueba local**. Ese modo solo demuestra la interfaz y no prueba la conexión.

## Entradas y salidas

- **Entrada:** publicaciones creadas manualmente en un iPhone con tipo (necesidad u oferta), recurso, cantidad, prioridad, zona aproximada, vencimiento y nota opcional. También entran estados JSON recibidos directamente desde otros iPhones.
- **Salida:** publicaciones sincronizadas, coincidencias ordenadas localmente y propuestas con estados de aprobación y entrega. Todo se guarda como JSON en Application Support del iPhone; no se envía a una nube.

## Casos límite conocidos

- Una persona no puede hacer match con su propia publicación.
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

## Umbral de aprobación humana

El matching es automático, pero nunca coordina una entrega por sí solo. La necesidad y la oferta deben ser confirmadas por los dos autores; después, ambos deben marcar la entrega como completada. No se revelan direcciones exactas, no se hacen pagos y no se toman decisiones médicas. Cualquier caso de primeros auxilios requiere intervención humana y los servicios oficiales siguen teniendo prioridad.

## Mantenimiento

Revisar el proyecto cuando cambien iOS, los permisos de Local Network/Bluetooth o `MultipeerConnectivity`. Cualquier cambio al formato de `MeshPost`, `MatchProposal` o `MeshWireMessage` debe incrementar `currentProtocolVersion` y agregar una migración de datos antes de desplegarse. La persona responsable del código iOS debe correr `swift run CoreChecks`, instalar la compilación en al menos dos iPhones físicos y repetir el guion completo antes de cada demo.
