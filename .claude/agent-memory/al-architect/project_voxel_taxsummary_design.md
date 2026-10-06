---
name: voxel-taxsummary-design
description: T20260915.0014_REALSON Voxel TaxSummary redesign (DR-Localization-BC26-BC27 FE app) - decisions, root-cause candidates, open checkpoints
metadata:
  type: project
---

Design proposed 2026-10-06 (not yet approved/implemented) for repo DR-Localization-BC26-BC27, branch feature/T20260915.0014_REALSON_RPENA.

- Origin: `Facturacion Electronica/src/Base/Codeunits/EFVoxelRequest.Codeunit.al` BuildTaxesNode/Exp/Ex (commit 65eeb47 made groups 18/16/0/Exento always emitted, rate defaults 18/16 when no lines).
- Decision: TaxSummary computed by iterating `EF Detalle Bienes o Servicios` (same filter as ProductList, CantidadItem <> 0), case on "EF Inv. Tax Indicator", fixed DGII rates 18/16/0, Base = MontoItem (post-discount net), Amount = VatAmount -> reconciles with TotalSummary (also built from details). Fallback to header fields when no detail lines (EFCreditMemoGenerator creates NO detail lines).
- LS app (facturacion-electronica-ls) has no own TaxSummary builder; it calls A's CreateVoxelRequest. B changes = hardening of header rates only (LSEFLSCTransactionHeader GenerateEFHeader takes rate from VAT Posting Setup, stale record on failed Get).
- Root-cause candidates for "No hay lineas ITBIS ... tasa 16": indicator override / bulk / CM generator put 18% lines in ITBIS2 group without rate validation; CM generator E34 has empty ProductList.
- Known pre-existing issue flagged: sales detail NetAmount = MontoItem + DescuentoMonto (pre-discount) used as product Tax Base.

**Why:** Downstream Reenvidador Voxel (codeunit 51102 SetSummaryBases) rebuilds summary bases from product Tax lines by rate; summary groups must be consistent with lines.
**How to apply:** Check whether this was implemented before re-designing; open checkpoints: Error vs. reclassify on rate/indicator mismatch, emitting 18/16 zero groups for E43/E44/E46.
