---
name: voxel-taxsummary-realson
description: T20260915.0014_REALSON_RPENA - Voxel TaxSummary always emits ITBIS 18/16/0 + Exento; v28 BELLON vs BC26/27 parity, LS gross-base flag, downstream RV impact
metadata:
  type: project
---

Decision (2026-10-06): Voxel TaxSummary must always emit ITBIS 18, ITBIS 16, ITBIS 0 and Exento groups even at 0 (Voxel confirmed). Change tag `//T20260915.0014_REALSON_RPENA`.

- v28 BELLON repo (BC-Facturacion-Electronica, branch T20260915.0014_REALSON_RPENA) commit 68057c8 already matches BC26/27 commit 65eeb47 (EFVoxelRequest BuildTaxesNode/Exp/Ex identical, header-driven).
- LS app (D) has no own TaxSummary builder; it calls C `DXR_VoxelRequest.CreateVoxelRequest`. Gross-base ("base + ITBIS") origin: `LSEFLSCTransactionHeader.TableExt.al` GenerateEFHeader adds VAT to MontoGrabado1/2 when setup `"Vat Indicator Header_DXR"` = false (default). Obsolete FillFromSalesPOSTables always gross.
- C sales inv/cr memo details: NetAmount = MontoItem + DescuentoMonto (pre-discount); MontoItem is the net post-discount base in both C and LS.
- Downstream Reenvidador Voxel codeunit 51102 SetSummaryBases must tolerate empty groups (Amount 0 and no matching lines -> keep).
- `DXR_XML Tax Modifier.ModifyTaxAmounts` and RV `ModifyTaxAmounts` use SelectSingleNode('//TaxSummary/Tax') but have no callers (as of 2026-10-06).

**Why:** production error "No hay líneas ITBIS para reconstruir la base de la tasa 16" after always-emit change.
**How to apply:** any TaxSummary change must be mirrored in both BC26/27 and v28 lines; prefer per-indicator detail sums with header fallback; treat LS flag change as a business checkpoint. Related: [[reenviador-voxel]]
