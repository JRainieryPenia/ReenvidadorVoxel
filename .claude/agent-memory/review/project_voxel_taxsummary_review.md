---
name: project-voxel-taxsummary-review
description: Facts from the 2026-10-06 review of the Voxel TaxSummary line-based change (EF repos BC26/27 and BC28); where validation exists and where detail lines are populated
metadata:
  type: project
---

EF Voxel TaxSummary (branch T20260915.0014_REALSON_RPENA) was reviewed 2026-10-06 in DR-Localization-BC26-BC27 and BELLON/BC-Facturacion-Electronica.

- Live detail-line generators: 4 TableExts (Sales/Purch Inv/CrMemo), EFBulkCreditMemoHandler, LS LSEFLSCTransactionHeader. EFSoapDocument.FillFrom*Table are dead code (no callers, never set VatAmount). EFCreditMemoGenerator creates header only (no detail rows).
- Only the 4 TableExts already Error on indicator vs VAT% (exact 18/16/0). Bulk handler and LS have no such validation, so a new strict check can newly block them. LS sets "% ITBIS" only when Net Amount <> 0.
- EFXmlTaxModifier.ModifyTaxAmounts has no production callers (tests only).
- No docs/specs/<RAMA> folder exists in either repo; 26/27 repo has no tests for this change.

**Why:** avoids re-deriving these when the next review touches EFVoxelRequest/NodeBuilder.
**How to apply:** check these paths first when a change adds validation or reads Details lines.

Final review 2026-10-06 (2nd pass) facts:
- CreateVoxelRequest routes only E34 (not E33) to BuildTaxesNodeEx for ref 43/44; E33 ref 44 goes to BuildTaxesNode, so it became line-based (differs from "exact pre-REALSON" rule). Same in 26/27 and 28.
- Test 77220 REALSON replica used VatAmount 2654.24+274.58=2928.82 but asserts 2928.81 (fixture arithmetic bug). Format(0,0,'<Precision,2:2>...') on an Integer literal may yield "0" not "0.00" (ModifyTaxAmounts zero branch).
- EF Inv. Tax Indicator enum default 0 = "No Facturable"; bulk handler lines with blank indicator + amounts now Error; Enable Indicator Override uses VAT Posting Setup indicator vs line VAT%.
- Reenvidador repo branch is `main` (no REALSON markers possible); 26/27 g.xlf already contains the 5 labels, es-MX has 0 of them in both repos.
