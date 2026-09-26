---
outline: deep
---

# Guía de actualización a macOS 27

::: tip Lo esencial
Si WeChat u otra app deja de abrirse desde Finder / Dock en macOS 27 tras aceptar una nueva firma en una versión antigua o de prueba de AppPorts, siga la reparación de abajo. Restaure los enlaces de contenedores antiguos y después la app original, o reinstale su versión oficial. **No borre las carpetas de datos ni vuelva a firmar la app.** Un error de firma no demuestra que los datos estén dañados.
:::

## Reparación

Pulse **«Reparar»** directamente en la fila de la app, o «Ver los pasos de reparación» en su menú contextual. No necesita comandos de Terminal. Esta guía corresponde a la versión en desarrollo; las versiones sin panel también permiten seguir los pasos manuales. Conecte el disco original, cierre completamente la app y conserve datos y copias de seguridad.

::: tip Firma automática al iniciar sesión
La versión de desarrollo actual desactiva la firma automática al iniciar sesión en macOS 27 o posterior, y detiene y elimina la tarea anterior. Si la limpieza no se completa, vuelve a intentarlo en Ajustes.

**Actualiza y abre AppPorts una vez antes de actualizar macOS** para que la tarea en segundo plano instalada reciba la comprobación de versión. Descargar la nueva versión sin abrirla no actualiza la tarea anterior.
:::

### 1. Restaurar los datos trasladados mediante enlaces antiguos

Si el panel encuentra enlaces de contenedores hacia el disco externo, pulse «Restaurar todo». Si no existen, omita este paso. Ruta manual: Directorios de datos → Datos de apps → seleccionar la app → restaurar los contenedores enlazados. Los datos que ya usan montaje APFS no necesitan volver al Mac solo para reparar la firma.

### 2. Restaurar la app original o reinstalar oficialmente

- **Copia completa de la app original:** use «Restaurar firma original». Puede restaurar directamente la app real del disco externo, sin moverla antes al Mac. AppPorts comprueba que la app actual coincida con la copia. Si se ha actualizado o modificado, necesita un original oficial coincidente.
- **Solo un registro antiguo de identidad:** seleccione una `.app` oficial de la misma versión o reinstale desde App Store / la web del desarrollador. El nombre del certificado no puede reconstruir la firma.
- **Instalación encima de una app externa:** devuélvala primero al Mac para que el instalador no sustituya únicamente el lanzador local.

**No borre las carpetas de datos de contenedores.** Guarde aparte una copia de los datos importantes. El acceso al historial y a las sesiones también depende de versiones, permisos y estado de los datos. Véase [Copias y restauración de firmas](/es/datamigrae/resign).

### 3. Comprobar de nuevo y abrir desde Finder / Dock

Pulse «Comprobar de nuevo» y después abra la app desde Finder / Dock y verifique sus datos. Una comprobación no disponible no significa firma sustituida ni reparación completa: conecte el disco y repita. Los análisis conservan las copias. Puede atender más tarde una app que aún se abre, pero abrirse no demuestra que haya recuperado su firma original.

### 4. Opcional: continuar la migración de datos

Tras reparar, seleccione el directorio en Datos de apps y pulse «Migrar». AppPorts comprueba el destino y usa [migración APFS mediante montaje](/es/datamigrae/mount-migration) para los contenedores, conservando la firma. Actualmente se requiere un **disco externo APFS sin cifrar**. Puede elegir otro disco o dejar los datos en el Mac. Permita el acceso a volúmenes extraíbles si macOS lo solicita y conecte el disco antes de usar la app. Véase [Preparar APFS](/es/why-apfs#what-to-do).

## A quién afecta

| Elemento | Explicación |
|------|------|
| Desencadenante | Actualización a macOS 27 |
| Apps afectadas | Apps cuyos datos de `~/Library/Containers/` o `~/Library/Group Containers/` se migraron y que se volvieron a firmar con Ad-hoc, o apps aisladas firmadas manualmente desde el menú contextual |
| Síntomas habituales | Doble clic en Finder / Dock sin respuesta; el icono aparece y desaparece sin diálogo de error. No ocurre con todas las apps: QQ Music funciona en el mismo Mac con 27 |
| Datos | Un error de firma no demuestra daños en los datos; conserve los originales y sus copias |
| Caso confirmado | WeChat 4.1.15, macOS 27.0 (26A428) |

Volver a firmar elimina la identidad aislada. Cuando macOS 27 comprueba si la app puede acceder al contenedor, una autorización guardada para su firma antigua puede no coincidir con la nueva y se rechaza el acceso. WeChat registra `Failed to match existing code requirement`. Las apps sin registros antiguos, como QQ Music, aún pueden pasar, pero no recuperan los derechos perdidos, como los del llavero. Consulte [Datos de contenedores, aislamiento e identidad de firma](/es/datamigrae/container-identity).

AppPorts solo indica sustitución si una copia registra una identidad original de desarrollador y la app real se confirma actualmente como Ad-hoc. Un tiempo de espera agotado o una app externa ilegible requieren repetir la comprobación. Una app originalmente Ad-hoc, su migración o un lanzador local no justifican volver a firmar.

## Qué no hacer

| Acción | Por qué no basta |
|------|------|
| Dar por reparado el problema solo por restaurar los datos | Resuelve el acceso a datos externos, no la firma. La app firmada de nuevo puede seguir cerrándose |
| Volver a firmar otra vez | Es la causa del problema; solo vuelve a eliminar derechos |
| Añadir la app a Acceso total al disco | Puede evitar la comprobación del contenedor, pero los derechos del llavero ya se perdieron y la sesión sigue afectada. Solo sirve como medida temporal |
| Considerar que abrir desde Terminal equivale a reparar | La app toma prestados los permisos de Terminal. Compruebe desde Finder / Dock |

## Antes de actualizar: comprobar

Revise primero las marcas «Firma sustituida» de AppPorts y siga la reparación anterior. La ausencia de avisos no garantiza compatibilidad con macOS 27. El script opcional solo comprueba rutas accesibles de copias antiguas; las apps movidas, discos desconectados y lanzadores pueden producir una lista incompleta.

::: details Opcional: comprobaciones técnicas
```bash
BACKUP_DIR="$HOME/Library/Application Support/AppPorts/signature-backups"
for plist in "$BACKUP_DIR"/*.plist; do
  [ -f "$plist" ] || continue
  original=$(/usr/libexec/PlistBuddy -c "Print :signingIdentity" "$plist" 2>/dev/null)
  app=$(/usr/libexec/PlistBuddy -c "Print :originalPath" "$plist" 2>/dev/null)
  case "$original" in ""|ad-hoc) continue ;; esac
  [ -d "$app" ] || continue
  if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
    printf "%s\n    %s\n" "$app" "$original"
  fi
done
```
:::

## Después de actualizar: confirmar los síntomas

Abra primero desde Finder / Dock. Si falla y se confirma que la firma fue sustituida, siga la reparación anterior. En otros casos, compruebe también la versión, los permisos y el disco externo.

::: details Opcional: comprobaciones técnicas
Cambie el ejemplo por la **ruta de la app real**, no la de su lanzador. Estos comandos solo leen información. Compare Ad-hoc con la identidad original; un registro de acceso denegado es una pista, no una prueba de su causa.

```bash
codesign -dv --verbose=4 "/Applications/WeChat.app" 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```
:::

## Qué ha cambiado en AppPorts 1.8.2

Estos comportamientos corresponden a la versión en desarrollo:

- El modo predeterminado migra contenedores mediante montaje APFS y rechaza volver a firmar apps aisladas.
- Las copias completas restauran la app original. Los registros antiguos necesitan una app oficial coincidente.
- Las sustituciones confirmadas y las comprobaciones no disponibles se muestran por separado; se conservan los materiales de recuperación.
- El [modo clásico de migración de datos](/es/settings#classic-data-migration-mode) está desactivado por defecto. Actualizar AppPorts no restaura automáticamente una firma sustituida.

## Preguntas frecuentes

### Perderé el historial de conversaciones

Un error de firma no significa que el historial esté dañado. Conserve contenedores, datos externos y copias. Evite desinstaladores que borren datos. Compruebe el acceso tras reparar; quizá deba restablecer algunos permisos de inicio de sesión.

### He restaurado los datos pero la app sigue sin abrirse

Restaurar las rutas no recupera la firma del desarrollador. Restaure la app original desde una copia completa o reinstale oficialmente y compruebe de nuevo. Si una firma correcta no resuelve el fallo, revise versión y permisos.

### Solo le ocurre a WeChat

No. Las pruebas existentes muestran diferencias entre apps. El aviso señala un riesgo que comprobar, no predice que todas fallen.

### AppPorts ha dañado mis datos

Los fallos observados se relacionan con la antigua nueva firma y no demuestran corrupción. Conserve los originales al investigar otros problemas. La migración APFS normal de contenedores conserva las firmas.

## Documentación relacionada

- [Datos de contenedores, aislamiento e identidad de firma](/es/datamigrae/container-identity): funcionamiento
- [Migración por montaje](/es/datamigrae/mount-migration): nuevo método
- [Por qué el disco externo debe ser APFS](/es/why-apfs)
- [Firma y prevención de cierres inesperados](/es/datamigrae/resign)
