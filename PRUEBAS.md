# Descarga de notas de crédito y reemplazo de NCF

## Uso

- En LSC Transaction Register, seleccionar transacciones y ejecutar **Reemplazar NCF por serie**. Elegir la serie y confirmar la cantidad. El proceso asigna números con No. Series usando WorkDate(), actualiza LSDX NCF y guarda NCF antiguo / NCF Reemplazado en LSC Transaction Header. Actualiza también el registro RV si existe. No envía documentos a Voxel.
- **Descargar XML de nota de crédito** está disponible en LSC Transaction Register y RV Transaction Register. Descarga el XML completo conservado al enviar la nota de crédito, usando su NCF como nombre de archivo. Para registros anteriores busca el XML archivado POS por e-NCF. No genera ni consume un NCF.
- Una segunda sustitución queda bloqueada para conservar la pareja anterior/nuevo. Los reenvíos con nuevo NCF usan la misma rutina de reemplazo y reutilizan el NCF si ya está reemplazado. Un resultado de envío `false` deja el NCF asignado pendiente de reenvío; no restaura el anterior. Una excepción AL sigue las reglas de rollback de la sesión y de la dependencia.
- Las notas antiguas cuyo XML no se conservó completo no se reconstruyen a partir del texto truncado de 2.000 caracteres. La descarga informa que no está disponible.

## Pruebas de aceptación en sandbox (pendientes de ejecución)

| Caso | Preparación y acción | Resultado esperado |
| --- | --- | --- |
| XML completo | Enviar una nota de crédito cuyo XML exceda 2.000 caracteres; descargar desde ambas páginas | Contenido completo igual al enviado, XML válido y archivo con NCF de la nota |
| Histórico | Registro RV sin BLOB y archivo POS con XML para el mismo e-NCF | Descarga el archivo histórico |
| Sin XML | Nota sin BLOB ni archivo, o archivo con BLOB vacío | Error descriptivo; no crea documentos ni consume series |
| Sin nota | Transacción sin NCF de nota de crédito | Error descriptivo |
| Ambigüedad | Dos registros RV o archivos POS con el mismo NCF | Rechaza la descarga ambigua |
| Reemplazo múltiple | Dos transacciones del mismo tipo fiscal y serie válida | Nuevos NCF consecutivos; NCF antiguo conserva cada valor previo; NCF Reemplazado coincide con LSDX NCF; RV sincronizado |
| Cancelación | Cancelar selector o confirmación | Sin cambios ni consumo de serie |
| Tipo o longitud incorrectos | Serie con prefijo o longitud diferente | Error y rollback del lote y de la numeración |
| Duplicado | Serie que devuelve un NCF ya asignado | Error y rollback |
| Segunda sustitución | Intentar reemplazar una transacción ya reemplazada | Error sin sobrescribir historial |
| Fallo intermedio | Seleccionar una válida y otra sin NCF o ya reemplazada | Ninguna sustitución parcial persiste |
| Concurrencia | Dos sesiones intentan sustituir la misma transacción | El bloqueo y la relectura impiden sobrescribir el historial |

## Validación local

Compilar todo el proyecto con los símbolos de `.alpackages`. Las pruebas de XML están en `Tests/RVVoxelTaxXML.Tests.al`, codeunit 51148, habilitadas únicamente con `/define:RV_TESTS`. El paquete normal no incluye el objeto de pruebas. No hay conexión de test runner configurada; la compilación no acredita ejecución en tenant ni aceptación fiscal/proveedor.

## Flujo homologado y conservación de historial

La marca **NCF reemplazado (marca)** se almacena en LSC Transaction Header y se muestra mediante FlowField en RV, junto a NCF antiguo y NCF Reemplazado. ReSent se activa únicamente cuando el envío informa éxito. El NCF afectado, fecha, número y XML de la nota de crédito no se modifican al reemplazar o reenviar.

Cargar transacciones actualiza o agrega registros sin borrar el historial. Limpiar transacciones conserva registros anulados, reenviados, con reemplazo o con NCF de nota de crédito. Desmarcar anulación se bloquea si ya hay una nota de crédito; desmarcar envío conserva el XML. Se bloquea generar otra nota de crédito desde el registro LSC si ya existe una asociada, para no sobrescribirla.

La codeunit de upgrade marca las sustituciones previas que tienen NCF antiguo y nuevo y cuyo NCF actual coincide con el nuevo. No reconstruye sustituciones históricas sin esa evidencia.

Pruebas adicionales en sandbox (pendientes):

1. Anular A mediante nota C; reemplazar A por B; reenviar. Verificar marca=true, antiguo=A, reemplazado=B, LSDX NCF=B, ReSent=true, NCF anulado=A, nota=C y mismo XML de C.
2. Ejecutar cada ruta de reenvío con nuevo NCF después del reemplazo manual. Debe enviar B sin consumir otro número.
3. Simular respuesta false del proveedor: B y su historial se conservan, ReSent continúa false; reintentar utiliza B.
4. Reenvío con el mismo NCF: marca éxito sin vaciar el NCF actual ni alterar la nota de crédito, incluso sin archivo de respuesta.
5. Cargar y limpiar transacciones después del flujo completo: no perder historial, marca ni XML. Confirmar que cargar no usa TransferFields entre campos de IDs coincidentes y tipos distintos.
6. Ejecutar upgrade dos veces con sustitución previa documentada: marca activa, sin cambiar NCF ni información de nota de crédito.

## Compatibilidad con las bases históricas de Voxel Offline

El ajuste está limitado a este reenviador, después de generar el XML y antes de enviarlo. No modifica las dependencias ni el generador de producción.

| Documento | Base ITBIS en TaxSummary |
| --- | --- |
| Anulación de las facturas afectadas | Suma de bases de líneas ITBIS de la misma tasa + Amount del resumen de esa tasa |
| Factura reenviada | Suma de bases de líneas ITBIS de la misma tasa, sin añadir el impuesto |

En el ejemplo mixto: nota de crédito Base=188.99; factura reenviada Base=160.16. En ambos se conservan Amount=28.83, base exenta=75.45, SubTotal=235.61, Tax=28.83 y Total=264.44.

En el ejemplo totalmente gravado: nota de crédito Base=23800.00; factura reenviada Base=20169.49; ITBIS=3630.51.

Se reconstruye la base a partir de las líneas en cada llamada, por lo que no se acumula el impuesto al repetir el ajuste ni se depende de si el generador de producción ya fue corregido. No se usa el subtotal completo en documentos mixtos. Si una tasa ITBIS resumida no tiene líneas que permitan obtener su base, el proceso falla antes del envío.

Se aplica a VoidTransaction, VoidSelectedTransactions y ManualCreditMemoResend para anulaciones; y a ResentVoideTransaction, SendTransaction y ResendFromTransactionHeader para reenvíos. Las descargas de facturas generadas usan el XML corregido; la descarga de la nota conserva el XML guardado sin transformarlo. La acción antigua de nota sin ITBIS queda oculta y ya no fabrica una nota con NCF fijo; la antigua descarga de factura sin ITBIS ahora descarga el XML corregido manteniendo el impuesto.

Ocho pruebas AL compiladas: factura mixta histórica, factura mixta corregida, idempotencia, factura totalmente gravada, tasas 18/16 separadas, solo exentos, tasa sin líneas y referencia de nota sin nodo Client. Pendientes de ejecución en sandbox. Validar con Voxel una anulación del documento afectado y su posterior reemplazo/reenvío antes de considerar confirmada la aceptación del proveedor. Estas anulaciones son para las facturas históricas afectadas; reproducen deliberadamente su base errónea.
