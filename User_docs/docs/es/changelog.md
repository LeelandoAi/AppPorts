---
outline: deep
---

# Registro de Cambios

## v1.8.2 (en desarrollo)

### Cambios importantes

- **Los datos de contenedores pasan a la migración por montaje**: los directorios de `~/Library/Containers/` y `~/Library/Group Containers/` ya no se migran mediante enlaces simbólicos. AppPorts crea un volumen dedicado en un disco externo APFS y lo monta en el directorio original, sin modificar la firma de la aplicación. Se requiere un disco externo APFS; la primera vez que se abra la aplicación hay que permitir el acceso a «Volúmenes extraíbles». Consulta la [migración por montaje](/es/datamigrae/mount-migration).
- **Las aplicaciones aisladas ya no se vuelven a firmar en ningún caso**: el menú contextual, la opción «Volver a firmar después de la migración» y el script de firma al iniciar sesión las omiten. La firma aplicada por versiones anteriores a una aplicación aislada puede impedir que se abra en macOS 27. Consulta la [guía de actualización a macOS 27](/es/macos-27).
- **Corrección de «Restaurar firma original»**: antes de volver a firmar se guarda una copia completa de la aplicación original, y la sustitución se realiza de forma segura tras verificar una copia de trabajo. Se pueden restaurar la firma y las autorizaciones originales sin la clave privada del desarrollador. Para registros antiguos se puede seleccionar una copia oficial de la misma versión como solución; no se fuerzan sustituciones cuando la aplicación se ha actualizado o la copia de seguridad está dañada.
- **Detección automática de firmas sustituidas y guía de reparación**: la lista muestra la insignia roja «Firma sustituida» y se presenta un aviso una vez al inicio. «Ver los pasos de reparación» en el menú contextual abre un panel que guía, en este orden, la restauración de datos, la devolución de la aplicación al Mac, la reinstalación y la migración por montaje, sin eliminar datos. Tras reinstalar y recuperar la firma, la insignia desaparece. El análisis conserva los materiales de restauración; las copias de seguridad se limpian una vez completada la restauración mediante AppPorts.
- **Modo clásico de migración de datos**: una nueva opción en la configuración está desactivada de forma predeterminada y exige confirmar los riesgos antes de activarla. Recupera el método de la versión 1.8.1, con enlaces simbólicos y nueva firma, solo para quienes ya dependen del método anterior. Si el disco externo no es APFS, se recomienda conservar la situación actual en lugar de activar este modo.
- «Re-firmado al iniciar sesión» está desactivado de forma predeterminada en instalaciones nuevas; quienes ya tienen instalado el agente de inicio de sesión conservan su ajuste.
- Fuera del modo clásico, «Normalizar», «Volver a enlazar» y «Detalles del enlace» están desactivados para los directorios de contenedores, para evitar que se vuelvan a crear enlaces simbólicos.

### Mejoras

- **Al hacer clic en «Migración por montaje» se realiza primero una comprobación de solo lectura y después se ofrecen indicaciones según el caso**: si el almacenamiento es APFS sin cifrar, AppPorts explica la migración, cuánto espacio se puede liberar, el permiso de la primera apertura y la necesidad de mantener el disco conectado. Si es exFAT / NTFS / HFS+, está cifrado, falta espacio o no está conectado, explica el motivo y ofrece opciones como «Dejar como está», «Elegir otra ubicación» y «Ver cómo prepararlo», sin cambiar nada. Las comprobaciones de preparación de la bienvenida y la configuración siguen los mismos criterios y ya no dirigen al modo clásico a quienes no tienen APFS.
- **Los volúmenes de datos ya no aparecen en Finder**: los nuevos volúmenes no se montan automáticamente en `/Volumes` y se montan con `nobrowse`. Los volúmenes montados por versiones anteriores se ocultarán en su ubicación actual en el próximo inicio o conexión del disco, sin desmontarlos.
- **La migración por montaje todavía no admite discos APFS cifrados**: un volumen de datos nuevo no hereda la contraseña del volumen original. AppPorts se detiene y lo explica, en vez de crear silenciosamente un volumen sin cifrar.
- **Se comprueba el espacio libre antes de migrar y restaurar**: si falta espacio en el disco externo o el Mac, la operación se detiene antes de crear el volumen o copiar los datos.
- **Restauración más segura**: tras desmontar, solo se eliminan los puntos de montaje vacíos, sin borrado recursivo. Los directorios temporales usan nombres ocultos. Si no se completa el último paso, el volumen externo y su registro se conservan, y AppPorts indica dónde está la copia local.
- **AppPorts solo actúa sobre sus propios volúmenes**: antes de montar, desmontar o restaurar, comprueba la identidad del volumen en el punto de montaje. La operación no comienza si no obtiene el bloqueo compartido con el agente de inicio de sesión. Un archivo de registros ilegible no se interpreta como una lista vacía ni se sobrescribe.
- **Corrección automática de la ruta del agente de inicio de sesión**: cada vez que se inicia, AppPorts comprueba la ruta del programa al que apunta el agente y la actualiza tras un traslado o actualización. Si AppPorts se ejecuta directamente desde un DMG o «Descargas», con una ruta temporal de App Translocation, se bloquean las nuevas migraciones por montaje y se indica que primero se coloque en «Aplicaciones».
- En sistemas que requieren permisos de administrador, como macOS 12, la migración por montaje vuelve a intentarlo después de mostrar el diálogo de contraseña del sistema.
- Los volúmenes de contenedores se vuelven a montar automáticamente tras iniciar sesión y al conectar el disco mientras AppPorts está abierto. El agente también vigila `/Volumes` para completar el montaje antes de que se abran las aplicaciones de inicio de sesión. Un bloqueo entre procesos evita que el agente y AppPorts compitan por los puntos de montaje durante una migración o restauración.
- **El agente de inicio de sesión ya no espera hasta después de los ítems de inicio**: ahora declara que necesita ejecutarse mediante `KeepAlive`, con reinicio solo en caso de fallo, y elimina `ProcessType: Background`. El dominio del usuario permanece un tiempo en modo on-demand-only después de iniciar sesión: launchd retrasaba la definición anterior unos 20 segundos, mientras que las aplicaciones de inicio se abrían en 3 segundos.
- **Remontaje automático si el sistema monta primero el volumen**: cuando el sistema ya ha montado el volumen en `/Volumes`, `diskutil mount -mountPoint` ignora el punto de montaje solicitado, imprime `mounted` y devuelve 0 sin informar de un error. Ocurrió los días 2026-09-21 y 09-23: la orden se completó correctamente, pero el punto de montaje estaba vacío y WeChat leyó después un directorio vacío. Ahora, tras cada montaje, se comprueba que el volumen esté realmente en la ruta de destino. Si no lo está, se desmonta de `/Volumes` y se vuelve a montar, hasta un máximo de 3 ciclos.
- **El montaje evita la consulta de `diskutil` más costosa al arrancar**: al arrancar o conectar el disco, el sistema monta primero los volúmenes en `/Volumes/<卷名>`. El agente ahora los reconoce directamente con `statfs` y el marcador de la raíz del volumen, en microsegundos, sin llamar a `diskutil info`, que en las pruebas tardaba 9 segundos. En un equipo real, la secuencia desde la búsqueda del punto de montaje hasta el montaje completo se reduce a las órdenes `unmount` y `mount`, alrededor de 1 segundo.
- **El agente ya no hace un único intento si el disco tarda en aparecer**: vigila `/Volumes` dentro del proceso y vuelve a intentarlo con el siguiente cambio real. Las pruebas muestran alrededor de 1 segundo desde la aparición del volumen hasta completar el montaje. Si no hay eventos, se realiza una comprobación de respaldo cada 20 segundos, durante una ventana total de 180 segundos. Mientras espera al volumen, no retiene el bloqueo compartido con AppPorts.
- **Los ciclos sin trabajo del agente ya no saturan los registros**: launchd compara `WatchPaths` con los prefijos de rutas de FSEvents, por lo que cualquier escritura en el disco externo despierta al agente, aunque casi siempre no tenga nada que hacer. Un ciclo sin trabajo ahora solo escribe 3 líneas; los detalles se registran únicamente cuando hay un montaje real, un volumen desconectado o un fallo.
- **La mitad de llamadas a diskutil en la ruta de montaje**: las consultas pasan de 4 a 2 por volumen. La comprobación de si el volumen está en línea y de dónde está montado se combina en una sola llamada a `diskutil info`. Con el sistema ocupado al arrancar, cada consulta tarda alrededor de un segundo; este cambio ahorra directamente varios segundos.
- **Spotlight ya no indexa los volúmenes**: tras crear un volumen, AppPorts escribe `.metadata_never_index` en su raíz y elimina el `.Spotlight-V100` que el sistema ya haya creado; en las pruebas, los dos volúmenes de WeChat sumaban 110 MB. Los volúmenes migrados anteriormente recibirán el marcador en el próximo montaje. El marcador permanece en el volumen y no se devuelve al directorio local al restaurar.
- Se corrige la asociación con contenedores de otras aplicaciones cuando el último segmento del Bundle ID es una palabra genérica como `mac` o `desktop`, por ejemplo cuando Termius mostraba contenedores de QQ Music.
- Se corrige la omisión de subdirectorios en el análisis cuando la ruta del contenedor empieza por `/private/var`.

## v1.8.0

### Nuevas funciones

- Directorios de escaneo local personalizados: el encabezado «Mac Apps Locales» ahora tiene un botón «+» para agregar directorios de escaneo de aplicaciones adicionales. Útil para herramientas como JetBrains Toolbox y Steam que instalan aplicaciones fuera de `/Applications`. Los directorios agregados se guardan y monitorean automáticamente (#48).
- Sincronización de versión Stub Portal: cuando una aplicación externa se actualiza a través de App Store, la información de versión del Stub Portal local se sincroniza automáticamente y la caché de macOS Launch Services se actualiza. El menú «Abrir con» ya no muestra números de versión obsoletos (#50).
- Detección de directorios de herramientas para Gradle (`~/.gradle`), datos de desarrollo Android (`~/.android`) y caché Flutter/Dart Pub (`~/.pub-cache`) (#49).
- Migración de directorios: agregue carpetas de usuario arbitrarias en la pestaña "Migración de Directorios", migre proyectos grandes, modelos, bibliotecas de recursos o cachés de herramientas al almacenamiento externo, y luego revincúlelos o restáurelos (#54).
- Advertencia de migración para apps protegidas: antes de migrar apps de App Store o apps propiedad de root, AppPorts advierte que la eliminación o sustitución automática puede fallar por permisos y sugiere mover primero la app manualmente en Finder antes de crear un enlace (#55).

### Mejoras

- Escaneo de aplicaciones más rápido: lecturas de Info.plist por aplicación reducidas de 7 a 1 (mediante caché en memoria).
- Protección de tiempo de espera de escaneo: el subproceso `codesign` ahora tiene un tiempo de espera de 10 segundos.
- Límite de seguridad para cálculo de tamaño: se agregó un límite de 500,000 archivos a los cálculos de tamaño recursivos.
- Registro de rastreo de escaneo: se agregó registro TRACE por aplicación al bucle de escaneo.
- Coincidencia más precisa de directorios de datos: las palabras TLD genéricas como `app`, `com`, `org` ahora se filtran.
- Detección de revinculación de directorios de herramientas más completa: si falta el directorio local pero sigue existiendo un directorio gestionado en la ubicación canónica del almacenamiento externo, AppPorts lo muestra como "Necesita Revinculación"; al cambiar de almacenamiento externo se actualiza automáticamente el estado.
- Mejoras de localización y accesibilidad: estados de apps, directorios de datos y directorios personalizados, etiquetas de ordenación/filtro, interruptores de configuración e insignias de estado siguen el idioma seleccionado de forma más consistente y exponen etiquetas de accesibilidad más claras.
- El tamaño de las apps usa ahora caché a nivel de sesión, reduciendo casos donde vuelve a "Calculando" o desaparece tras actualizar (#55).
- Rollback de migración de datos más seguro: antes de crear el enlace, AppPorts renombra el origen local como copia de seguridad oculta. Si falla la creación del enlace o la limpieza de la copia, conserva la copia local y la copia externa siempre que sea posible (#54).

### Correcciones

- Corregido: Trae y aplicaciones similares se escaneaban extremadamente lento.
- Corregido: la información de versión del Stub Portal no se actualizaba después de actualizaciones de App Store.
- Corregido: el botón de actualización no activaba la sincronización de versión.
- Corregido: la revinculación o normalización de directorios de datos podía tratar un archivo normal externo como directorio; ahora los archivos normales se rechazan y se conservan.
- Corregido: cuerpos de diálogos multilínea podían volver a mostrarse en chino en algunos idiomas; se completaron traducciones rusas de la interfaz y el diálogo del sistema "almacenamiento externo no conectado" de Stub Portal ahora sigue el idioma del sistema (#55).

## v1.7.0

### Nuevas funciones

- Añadido el estado «Pendiente de mover fuera»: cuando la app local real tiene una versión superior a la app con el mismo nombre en el almacenamiento externo, AppPorts la marca como pendiente de mover fuera, indicando que la nueva versión local puede migrarse de forma segura para reemplazar la copia externa antigua.
- Añadida confirmación de re-firmado para migración de datos: antes de migrar datos dentro del contenedor de una app, AppPorts puede preguntar si se debe aplicar automáticamente una firma Ad-hoc a la app relacionada después de la migración, reduciendo el riesgo de datos no reconocidos, advertencias o fallos de inicio tras migrar datos del contenedor (#44).

### Mejoras de interfaz

- Reorganizada la barra superior: los botones para cambiar entre la página de apps y la de directorios de datos ahora usan un estilo más compacto con icono + texto.
- Optimizada la barra de acciones de directorios de datos: el cambio «Directorios de herramientas / Datos de app», el interruptor de re-firmado tras migración, el botón para restaurar la firma original y el botón de actualizar ahora están en la barra superior.
- Añadida la insignia de estado «Pendiente de mover fuera» para identificar apps cuya versión local es superior a la copia externa antigua.
- Localizado el diálogo de confirmación de re-firmado para migración de datos, incluyendo título, texto y botones.

### Mejoras

- Reforzada la seguridad de migración de apps: cuando el destino externo ya existe, AppPorts solo lo limpia automáticamente si se identifica como un portal antiguo gestionado por AppPorts, un resto de migración anterior o si la app está en estado «Pendiente de mover fuera».
- Reforzada la validación de recuperación de directorios de datos: la recuperación automática ya no se basa en tamaños de directorio similares y ahora requiere coincidencia completa de AppPorts metadata.
- Escaneo de datos de app más estable: al cambiar rápidamente de app, los resultados de tareas de escaneo anteriores ya no sobrescriben la lista de directorios de datos de la app actualmente seleccionada.
- Mejorado el escape de comandos de administrador y AppleScript: las rutas con comillas, barras invertidas, espacios o caracteres chinos se gestionan de forma más segura.
- Localización mejorada: corregidos contenidos de ayuda, avisos y confirmaciones de migración de datos que podían seguir en chino o quedar incompletos tras cambiar de idioma; completadas las traducciones para todos los idiomas soportados (#43).

### Correcciones

- Corregido un caso donde la migración de directorios de datos podía tratar erróneamente un directorio externo real como destino recuperable.
- Corregido un caso donde la migración de apps podía eliminar por error una app externa real con el mismo nombre.
- Corregida la detección y limpieza inestable de antiguos portales AppPorts externos o restos de migraciones anteriores.
- Corregida la construcción incorrecta de AppleScript o comandos de administrador cuando la ruta contiene caracteres especiales.
- Corregido un caso donde la migración en segundo plano o el re-firmado posterior podía leer una app ya cambiada.
- Corregido que el estado «Pendiente de mover fuera» no apareciera como insignia en la lista de apps.

## v1.6.2

- Nuevo: Re-firmado automático al iniciar sesión. Re-firma automáticamente las apps migradas con caducadas cada vez que el usuario inicia sesión, sin acción manual. Activado por defecto, se puede desactivar en Ajustes
- Mejora: Stub Portal ahora usa un lanzador binario Mach-O nativo en lugar del script bash heredado, corrigiendo el problema de que hacer doble clic en documentos asociados en Finder no podía abrir la app externa (#42)
- Mejora: Diseño de la página Acerca de optimizado con área de contenido desplazable, corrigiendo que el contenido se cortara cuando la ventana era demasiado pequeña
- Corregido: El Stub Portal nativo se identificaba incorrectamente como una app local regular
- Corregido: No se podía limpiar correctamente el Stub Portal nativo al mover apps de vuelta al almacenamiento local
- Corregido: El shell de la app se trataba como una app completa durante las operaciones de vinculación inversa
- Corregido: AutoResignInstaller informaba éxito silenciosamente cuando la instalación fallaba

## v1.6.1

- Corregido: El re-firmado automático después de la migración del directorio de datos ahora firma correctamente la app real externa en lugar del shell stub local
- Corregido: Las operaciones de re-firmado y restauración de firma ahora resuelven correctamente la ruta real para apps vinculadas
- Corregido: La detección del estado 'Re-firmado' para apps vinculadas ahora identifica correctamente el estado de firma de la app real externa
- Mejorado: La salida de logs incluye códigos de error estructurados e información de rutas relacionadas

## v1.6.0

- Las apps migradas ya no muestran flechas de marcador
- Las apps de auto-actualización ya no se corrompen por actualizaciones después de la migración
- Añadida función de gestión de firma de apps para corregir mensajes de 'Dañado' después de la migración
- La desconexión del almacenamiento externo ahora muestra advertencias rojas de 'Enlace huérfano'
- Los usuarios de macOS 15.1+ pueden instalar apps de App Store directamente en discos externos
- Migración de directorios de datos más segura: previene la migración accidental del directorio del sistema, recuperación automática después de interrupción
- Escaneo y cálculo de tamaño más rápidos; la lista ya no salta
- Copia de archivos al almacenamiento externo más estable; sin errores por interrupción
- Insignias de estado de apps rediseñadas con información más rica y detalles clicables
- La lista de apps mantiene la selección después de actualizar; los directorios de datos soportan vista de árbol
- Mejoras de UI: búsqueda, ordenación, tarjetas de grupo, carga de iconos, etc.
- Añadida opción de idioma Marciano
- Actualización de pruebas automatizadas

## v1.5.5

- Añadido soporte de instalación externa de apps App Store en macOS 15.1+
- Añadida función de re-firmado automático (se ejecuta automáticamente después de la migración del directorio de datos)
- Añadidas pruebas de auditoría de localización `LocalizationAuditTests`
- Mejorada la lógica de generación de Info.plist de Stub Portal
- Corregido el problema de pérdida de iconos de Launchpad para algunas apps después de la migración

## v1.4.0

- Añadida vista de árbol de directorios de datos
- Añadida detección de directorios de herramientas (30+ herramientas de desarrollo)
- Añadida función de exportación de paquete de diagnóstico
- Mejorada la detección de auto-actualización (Chrome, Edge y otros actualizadores personalizados)
- Corregido el mecanismo de recuperación automática después de la interrupción de migración

## v1.3.0

- Añadida función de migración de directorios de datos
- Añadida gestión de firma de código (copia de seguridad/restauración de firmas originales)
- Añadida auto-detección de aplicaciones Sparkle y Electron
- Mejorada la protección de migración bloqueada (`chflags uchg`)
- Corregidos problemas de visualización de marcadores en Finder

## v1.2.0

- Añadida estrategia de migración Stub Portal (reemplazando Deep Contents Wrapper)
- Añadido soporte de migración de apps iOS (apps iOS versión Mac)
- Mejorado el rendimiento de migración por lotes
- Corregido el problema donde algunas apps no podían iniciarse después de la restauración

## v1.1.0

- Añadido soporte multi-idioma (20+ idiomas)
- Añadida migración de directorios de suites de apps (ej., Microsoft Office)
- Mejorada la detección de almacenamiento externo desconectado
- Corregido el problema de penetración de enlaces simbólicos con la estrategia Deep Contents Wrapper

## v1.0.0

- Primera versión oficial
- Soportada migración de apps al almacenamiento externo (Deep Contents Wrapper / Whole App Symlink)
- Soportada restauración de apps y gestión de enlaces
- Soportado monitoreo de sistema de archivos en tiempo real con FolderMonitor
