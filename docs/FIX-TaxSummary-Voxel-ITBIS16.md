# Incidente y corrección: TaxSummary Voxel — "No hay líneas ITBIS para reconstruir la base de la tasa 16"

**Fecha:** 2026-10-06
**Audiencia:** equipo técnico y funcional de Dextra
**Componentes:** Reenvidador Voxel (codeunit 51102 "RV Voxel Tax XML") · Facturación Electrónica BC26/27 y BC28 (codeunit "EF VoxelRequest", "EF XML Tax Modifier")

---

## 1. Resumen

- Fallo causado por un cambio en la integración con Voxel. Voxel indicó que, cuando un grupo de ITBIS presente en las líneas falta en el TaxSummary, lo reporta como **MontoNoFacturable**.
- Para atenderlo, en la rama **REALSON** se cambió la generación del XML para emitir **siempre** los 4 grupos del TaxSummary (ITBIS 18, ITBIS 16, ITBIS 0 y Exento), aunque no hubiera líneas.
- El entorno online recibió esa versión nueva y empezó a producir grupos vacíos, por ejemplo ITBIS 16 con Base 0 y Amount 0. Al reenviar, Reenvidador no encontraba líneas de esa tasa para reconstruir la base y fallaba.
- Un POS que sigue con la lógica antigua (emisión condicional) funciona con normalidad.
- Corrección en dos frentes:
  1. **Reenvidador 26.0.0.7**: tolera los grupos sin líneas con Amount 0.
  2. **Origen (FE 26/27 y 28)**: el TaxSummary se arma desde las líneas y solo incluye los grupos que tienen líneas, aunque sumen 0.
- Estado: compilado sin errores en todas las apps afectadas. El usuario confirma que el entorno ya funciona.

## 2. Síntoma

Error en producción:

```
No hay líneas ITBIS para reconstruir la base de la tasa 16.
```

Pila:

```
"RV Voxel Tax XML"(CodeUnit 51102).SetSummaryBases line 31
"RV Voxel Tax XML"(CodeUnit 51102).ForResend line 2
"RV Transaction Register"(Page 51100)."Download XML - OnAction" line 17
```

App: **Reenvidador Voxel by Dextra 26.0.0.4**.

## 3. Causa raíz

### 3.1 Cambio REALSON en el origen

| Commit | Repositorio / versión | Nota |
|---|---|---|
| `65eeb47` | Facturación Electrónica BC26/27 | También está en `origin/deploy` |
| `68057c8` | Facturación Electrónica BC28 | — |

Ambos commits cambiaron `BuildTaxesNode` del codeunit "EF VoxelRequest":

| | Antes (lógica antigua) | Después (REALSON) |
|---|---|---|
| Emisión de grupos | Condicional, p. ej. `if (MontoGravadoI1<>0) or (TotalITBIS1<>0) or HasItbis1Lines then ...` | Siempre los 4 grupos (18, 16, 0, Exento) con tasas por defecto |
| Grupo sin líneas | No se emite | Se emite con Base 0 y Amount 0 |

### 3.2 Por qué fallaba Reenvidador

`SetSummaryBases` reconstruye la base de cada grupo ITBIS del TaxSummary a partir de las líneas de ProductList con esa tasa. El grupo ITBIS 16 vacío no tenía líneas, por lo que se lanzaba el error.

```xml
<!-- TaxSummary generado por REALSON en un documento sin líneas al 16 % -->
<Tax Type="ITBIS" Rate="18" Base="16271.19" Amount="2928.81"/>
<Tax Type="ITBIS" Rate="16" Base="0.00"     Amount="0.00"/>   <!-- sin líneas -> error -->
<Tax Type="ITBIS" Rate="0"  Base="0.00"     Amount="0.00"/>
<Tax Type="Exento"          Base="0.00"     Amount="0.00"/>
```

### 3.3 Efecto colateral

También se inventaban grupos en tipos que hoy se aceptan con un solo grupo. Por ejemplo, el **E47** (pagos al exterior) se acepta solo con `<Tax Type="Exento" .../>`.

### 3.4 Por qué el POS antiguo no falló

El POS sigue con la generación anterior (condicional), que no inventa grupos. El entorno online recibió la versión REALSON y fue el único afectado.

## 4. Regla correcta

| Situación | ¿Se emite el grupo? |
|---|---|
| El documento tiene líneas en el grupo (aunque la suma dé 0) | **Sí** |
| El documento no tiene líneas en el grupo | **No**, no se inventa |

No se emiten siempre los 4 grupos.

### Ejemplo 1 — E31 REALSON `E310000000652`

Tiene 2 líneas ITBIS 18 (14745.77 / 2654.24 y 1525.42 / 274.58) y 5 líneas acompañantes a precio 0 emitidas como Exento.

```xml
<!-- Recibido: falta el grupo Exento -->
<Tax Type="ITBIS" Rate="18" Base="16271.19" Amount="2928.81"/>

<!-- Correcto -->
<Tax Type="ITBIS" Rate="18" Base="16271.19" Amount="2928.81"/>
<Tax Type="Exento"          Base="0.00"     Amount="0.00"/>
```

### Ejemplo 2 — E47 `E470000000748`

Tiene una sola línea Exento por 10708.50.

```xml
<!-- Correcto: un solo grupo -->
<Tax Type="Exento" Base="10708.50" Amount="0.00"/>
<!-- TotalSummary: 10708.50 / 0.00 / 10708.50 -->
```

## 5. Solución en Reenvidador Voxel (este repositorio)

Archivo: `RVVoxelTaxXML.Codeunit.al` (codeunit 51102). Versión **26.0.0.7**, commit `1cecf5b`.

`SetSummaryBases`, para cada grupo ITBIS del TaxSummary:

| Caso | Comportamiento |
|---|---|
| Hay líneas de esa tasa | Reconstruye la base desde las líneas. `ForCancellation` usa la base histórica (base + Amount), salvo que se use `SetCorrectedBase(true)`. `ForResend` usa la base de línea. |
| No hay líneas y Amount = 0 | Conserva el grupo intacto. Cubre el grupo vacío y el grupo ITBIS 0 % cuyas líneas salen como Exento. |
| No hay líneas y Amount <> 0 | Error, porque la base no se puede deducir. |

## 6. Solución en el origen (FE 26/27 y 28)

Repositorios: **DR-Localization-BC26-BC27** (FE 26/27) y **BELLON BC-Facturacion-Electronica** (BC28).

### 6.1 Codeunit "EF VoxelRequest"

- Un helper común clasifica cada línea en el mismo grupo en que sale en ProductList: `IsItbisProductNode` (26/27) y `LineEmitsITBISNode` (28).
- `CollectTaxGroups` arma el resumen a partir de las líneas:
  - Base = Σ MontoItem; Amount = Σ VatAmount;
  - orden fijo: 18, 16, 0, Exento;
  - solo emite los grupos con al menos una línea, aunque sumen 0.
- Las líneas ITBIS 0 % (indicador 3) se resumen como Exento, igual que en ProductList.
- Las validaciones lanzan error; ninguna línea se reclasifica en silencio (ver sección 8).

Mapa de indicadores (`IndicadorFacturacion`):

| Indicador | Significado | Grupo en TaxSummary |
|---|---|---|
| 0 | No Facturable | Solo con montos en cero; cuenta para la presencia del grupo |
| 1 | ITBIS 18 | ITBIS 18 |
| 2 | ITBIS 16 | ITBIS 16 |
| 3 | ITBIS 0 | Exento |
| 4 | Exento | Exento |

### 6.2 Codeunit "EF XML Tax Modifier" (`ModifyTaxAmounts`)

| Caso | Acción |
|---|---|
| Monto = 0 | Escribe `0.00` en todos los nodos ITBIS |
| Un único grupo ITBIS con base <> 0 | Le asigna el monto |
| Más de un grupo ITBIS con base <> 0 | Error: 'Más de un grupo ITBIS del TaxSummary tiene base gravada; no se puede asignar el monto de impuesto.' |
| Ningún grupo ITBIS con base <> 0 | Asigna el monto al primer nodo ITBIS |

### 6.3 Otros

- Traducciones es-MX: 5 unidades nuevas.
- Apps LS Facturación Electrónica (26/27 y 28): sin cambios de código. Llaman a `CreateVoxelRequest` de FE y compilan contra el .app nuevo.
- Ateb/Rodaltech: no afectados. Arman sus totales DGII en `EFSoapDocument`, que no se modificó.

## 7. Tipos de comprobante no afectados

Conservan exactamente la lógica previa a REALSON:

| Tipo | Ruta de código |
|---|---|
| E46 | `BuildTaxesNodeExp` |
| E47 | Lógica previa (un solo grupo Exento) |
| E43 / E44 | `BuildTaxesNodeEx` / camino de cabecera |
| E34 / E33 que modifican NCF 43/44 | `BuildTaxesNodeEx` / camino de cabecera |
| Documentos sin líneas de detalle | Lógica previa |

## 8. Validaciones y mensajes

| Caso | Mensaje (es-MX) | Observaciones |
|---|---|---|
| Indicador ≠ % ITBIS | 'La línea %1 del documento %2 tiene el indicador de impuesto %3 pero su porcentaje de ITBIS es %4.' | Se omite si la línea tiene MontoItem = 0 y VatAmount = 0. El % 1 heredado se acepta como 0 para los indicadores 3 y 4. |
| Indicador desconocido | 'La línea %1 del documento %2 tiene un indicador de impuesto desconocido %3.' | — |
| Indicador 0 (No Facturable) con montos | 'La línea %1 del documento %2 está marcada como no facturable pero tiene montos.' | Si los montos son cero, la línea sí cuenta para la presencia del grupo. |
| % ITBIS distinto de 18/16/0/1 | 'La línea %1 del documento %2 tiene un porcentaje de ITBIS no soportado %3.' | Aplica también a líneas en 0 (decisión de diseño). |
| Varios grupos ITBIS con base (ModifyTaxAmounts) | 'Más de un grupo ITBIS del TaxSummary tiene base gravada; no se puede asignar el monto de impuesto.' | — |

## 9. Pruebas y verificación

### Reenvidador

`Tests/RVVoxelTaxXML.Tests.al` (codeunit 51148, se compila con `/define:RV_TESTS`):

| Prueba | Qué cubre |
|---|---|
| `EmptyRate16GroupIsPreserved` | El grupo 16 vacío se conserva |
| `EmptyGroupsRepeatedTransformsAreIdempotent` | Las transformaciones repetidas no alteran los grupos vacíos |
| `EmptyGroupWithAmountCannotBeGuessed` | Un grupo sin líneas y con Amount da error |
| `Itbis3ZeroRateGroupIsPreserved` | El grupo ITBIS 0 % con líneas como Exento se conserva |
| `MissingTaxLinesCannotBeGuessed` | Prueba existente; se mantiene |

### FE BC28

Codeunit 77220 "FEVoxelRequestBuilderTests" (unos 30 casos):

- réplicas del E31 (con indicador 1 y con indicador 0 en cero) y del E47;
- combinaciones de grupos, ITBIS 0 → Exento y % 1 heredado;
- validaciones;
- rutas E46, E44, E43, E34, E33, E41 y E45;
- `ModifyTaxAmounts`.

FE BC26/27 no tiene app de pruebas.

### Compilación

0 errores en: Reenvidador (normal y con `RV_TESTS`), FE 26/27, FE 28, app de pruebas de 28, LS 26/27 y LS 28.

El usuario confirma que el entorno ya funciona.

## 10. Riesgos y pendientes

### Riesgos

- **Validación más estricta.** Puede bloquear documentos que antes se enviaban con datos desalineados, por ejemplo:
  - notas de crédito masivas (`EFBulkCreditMemoHandler`, que toma el indicador de la configuración de IVA);
  - líneas LS con % incorrecto.

  Validar con un lote real.
- **Línea en 0 con % no soportado.** Da error. Es una decisión de diseño.

### Seguimiento

- Confirmar con Voxel en QA que acepta grupos Exento/ITBIS en 0 cuando hay líneas.
- **POS con la lógica antigua.** Al actualizarlo a la versión corregida mantiene el comportamiento condicional y además añade los grupos con líneas en 0 que pide Voxel. Se recomienda actualizarlo en una ventana controlada, después de validar en QA.

### Fuera de alcance

- ITBIS 0 sale como Exento en ProductList.
- Base del producto antes del descuento en ventas tipo C.
- `EFCreditMemoGenerator` no crea líneas de detalle.
- Unidades es-MX pendientes de antes de este cambio.
