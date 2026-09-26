---
outline: deep
---

# Guía de actualización a macOS 27

::: tip Lo esencial
Si migró datos de contenedores de WeChat u otras apps con AppPorts y aceptó volver a firmarlas, tras actualizar a macOS 27 **pueden** cerrarse inmediatamente al hacer doble clic. Ocurre con WeChat; QQ Music y otras siguen abriéndose en las pruebas. **Los datos no están dañados** y no hay que migrarlos de nuevo. Restáurelos en el Mac y reinstale la app desde una fuente oficial. Para volver a guardarlos en el disco externo, use la nueva [migración por montaje](/es/datamigrae/mount-migration).
:::

## A quién afecta

| Elemento | Explicación |
|------|------|
| Desencadenante | Actualización a macOS 27 |
| Apps afectadas | Apps cuyos datos de `~/Library/Containers/` o `~/Library/Group Containers/` se migraron y que se volvieron a firmar con Ad-hoc, o apps aisladas firmadas manualmente desde el menú contextual |
| Síntomas habituales | Doble clic en Finder / Dock sin respuesta; el icono aparece y desaparece sin diálogo de error. No ocurre con todas las apps: QQ Music funciona en el mismo Mac con 27 |
| Datos | Intactos, incluidos historial y sesión |
| Caso confirmado | WeChat 4.1.15, macOS 27.0 (26A428) |

Volver a firmar elimina la identidad aislada. Cuando macOS 27 comprueba si la app puede acceder al contenedor, una autorización guardada para su firma antigua puede no coincidir con la nueva y se rechaza el acceso. WeChat registra `Failed to match existing code requirement`. Las apps sin registros antiguos, como QQ Music, aún pueden pasar, pero no recuperan los derechos perdidos, como los del llavero. Consulte [Datos de contenedores, aislamiento e identidad de firma](/es/datamigrae/container-identity).

## Antes de actualizar: comprobar

Este script muestra las apps cuya firma sustituyó AppPorts. Cada resultado es una app que podría presentar problemas después de actualizar.

```bash
BACKUP_DIR="$HOME/Library/Application Support/AppPorts/signature-backups"
for plist in "$BACKUP_DIR"/*.plist; do
  [ -f "$plist" ] || continue
  original=$(/usr/libexec/PlistBuddy -c "Print :signingIdentity" "$plist" 2>/dev/null)
  app=$(/usr/libexec/PlistBuddy -c "Print :originalPath" "$plist" 2>/dev/null)
  case "$original" in ""|ad-hoc) continue ;; esac   # 本来就是 ad-hoc 的跳过
  [ -d "$app" ] || continue
  if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
    printf "%s\n    原始签名: %s\n" "$app" "$original"
  fi
done
```

Complete si es posible la [reparación](#reparacion) antes de actualizar. Como mínimo, guarde la lista para saber qué apps comprobar después.

## Después de actualizar: confirmar los síntomas

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

La aparición de `kTCCServiceSystemPolicyAppData ... denied` en el paso 2 confirma el problema. Hay una lista más completa en la [comprobación de identidad del contenedor](/es/datamigrae/container-identity#comprobacion).

## Reparación

AppPorts 1.8.2 detecta estas apps, muestra la insignia roja «Firma sustituida» y avisa una vez al arrancar. «Ver los pasos de reparación» en el menú contextual abre un panel con el estado y los botones de cada paso, sin eliminar datos. El procedimiento manual sigue el mismo orden. **No cambie el orden.**

### Paso 1: restaurar los datos de contenedores en el Mac

Pulse «Restaurar todo» en el panel, o abra «Directorios de datos» → «App Data», seleccione la app y use «Restaurar» en cada directorio de contenedor con estado «Enlazado». Como la app no puede abrirse, no bloqueará el control de app en ejecución.

Este paso debe ir primero: la app reinstalada recupera el aislamiento y no puede leer los datos detrás de enlaces simbólicos. Seguiría pareciendo vacía, como si la reparación no hubiera funcionado.

Después puede comprobarlo:

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### Paso 2: devolver la app al Mac

Solo hace falta si la app está en el disco externo. En ese caso, `/Applications` contiene el lanzador de AppPorts. Instalar encima lo sobrescribiría y dejaría huérfana la copia externa. Pulse «Devolver a este Mac» en el panel o seleccione la app en «Unidad externa» y use esa opción. Después de reinstalar puede volver a migrar la app al disco externo.

### Paso 3: reinstalar la app si no se abre

Si la app funciona normalmente en 27, puede saltar al paso 4. Si necesita reinstalar, ciérrela por completo e instale encima desde una fuente oficial: App Store para sus apps, con el botón «Abrir App Store» del panel, o la web oficial para las demás. **No elimine los contenedores.** La reinstalación no los modifica; el historial y la sesión siguen ahí.

Después pulse «Volver a comprobar» o use el primer comando de comprobación para confirmar una firma `Authority=Developer ID Application: ...` o `Apple Mac OS Application Signing`. La insignia «Firma sustituida» desaparece al restaurar la firma. Un análisis normal conserva las copias; solo una restauración completada mediante AppPorts elimina la copia correspondiente.

::: tip Una copia completa permite restaurar; una antigua necesita la app original
«Restaurar firma original» usa ahora una copia completa de la app original, sin clave privada del desarrollador. Los registros antiguos que solo contienen el nombre de la identidad no permiten restaurar directamente: elija un `.app` oficial de la misma versión o reinstale según los pasos anteriores. En todos los casos, restaure primero los contenedores migrados en modo clásico. Consulte [Copia de seguridad y restauración de la firma](/es/datamigrae/resign#copia-de-seguridad-y-restauracion-de-la-firma).
:::

### Paso 4, opcional: devolver los datos al disco externo mediante montaje

Tras reinstalar, abra AppPorts. Los contenedores muestran «Migración por montaje» en vez de «Migrate». Pulse y siga las indicaciones. Al abrir la app por primera vez, **permita** acceder a volúmenes extraíbles. El disco debe ser APFS sin encriptar. AppPorts comprobará primero su situación e indicará qué hacer. Si no es APFS, puede dejar los datos en el Mac; consulte [Por qué APFS](/es/why-apfs#what-to-do).

## Qué no hacer

| Acción | Por qué no basta |
|------|------|
| Dar por reparado el problema solo por restaurar los datos | Resuelve el acceso a datos externos, no la firma. La app firmada de nuevo puede seguir cerrándose |
| Volver a firmar otra vez | Es la causa del problema; solo vuelve a eliminar derechos |
| Añadir la app a Acceso total al disco | Puede evitar la comprobación del contenedor, pero los derechos del llavero ya se perdieron y la sesión sigue afectada. Solo sirve como medida temporal |
| Considerar que abrir desde Terminal equivale a reparar | La app toma prestados los permisos de Terminal. Compruebe desde Finder / Dock |

## Qué ha cambiado en AppPorts 1.8.2

- Los contenedores usan [migración por montaje](/es/datamigrae/mount-migration), sin enlaces simbólicos, independientemente del aislamiento del programa principal.
- Las apps aisladas no se vuelven a firmar desde el menú contextual, «Volver a firmar después de la migración» ni el script de inicio de sesión.
- «Restaurar firma original» restaura la app original completa, su firma y derechos, sin clave privada; para registros antiguos permite elegir el original oficial de la misma versión.
- Detecta firmas sustituidas: insignia roja «Firma sustituida», aviso al arrancar y panel «Ver los pasos de reparación».
- Los enlaces antiguos de contenedores siguen apareciendo como «Enlazado» y «Restaurar» sigue disponible. «Normalizar» y «Volver a enlazar» se desactivan para evitar recrear enlaces simbólicos.
- Se conserva un **modo clásico de migración de datos**, desactivado por defecto y con confirmación de riesgos, para quienes dependen del método antiguo. Consulte los [ajustes](/es/settings#classic-data-migration-mode). Tener un disco no APFS no exige activarlo: deje los datos de contenedores en el Mac.

Actualizar AppPorts no restaura automáticamente las apps ya firmadas de nuevo. Debe seguir los pasos anteriores.

## Preguntas frecuentes

### Perderé el historial de conversaciones

No. Reinstalar no afecta a los contenedores y la app sigue leyendo los datos existentes. AppPorts tampoco los elimina durante este proceso.

### He restaurado los datos pero la app sigue sin abrirse

La firma aún no está reparada. Restaurar y reinstalar son dos pasos independientes y ambos son necesarios. Consulte [Reparación](#reparacion).

### Solo le ocurre a WeChat

No necesariamente. QQ Music, firmado de nuevo en el mismo Mac con 27, funciona. Las pruebas actuales apuntan a si existe un registro de autorización de la firma antigua, algo que no se puede predecir. Por eso se muestran todas las apps con firma sustituida para revisarlas. El script de [comprobación previa](#antes-de-actualizar-comprobar) da la lista completa.

### AppPorts ha dañado mis datos

No; los datos están intactos. Sin embargo, la causa directa del fallo sí es la opción de aceptar una nueva firma de versiones antiguas. La versión 1.8.2 eliminó esa vía.

## Documentación relacionada

- [Datos de contenedores, aislamiento e identidad de firma](/es/datamigrae/container-identity): funcionamiento
- [Migración por montaje](/es/datamigrae/mount-migration): nuevo método
- [Por qué el disco externo debe ser APFS](/es/why-apfs)
- [Firma y prevención de cierres inesperados](/es/datamigrae/resign)
