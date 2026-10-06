---
name: voxel-taxsummary-rules
description: Business rules (clarified 2026-10-06) for Voxel TaxSummary groups in FE origin (26/27 + 28) and Reenvidador Voxel — emit a group when it HAS LINES, even if its totals are 0
metadata:
  type: project
---

Rule: a TaxSummary group (ITBIS 18 / ITBIS 16 / ITBIS 0 / Exento) must be sent to Voxel when the document HAS LINES in that group, even if the group's Base/Amount sum to 0 (e.g. REALSON E31 with zero-priced side dishes emitted as Exento lines → TaxSummary must include Exento Base 0.00). Groups WITHOUT lines must NOT be invented.

NOT "always emit all four groups" — that was a misreading (REALSON commit 65eeb47/68057c8 did that) and it would add empty ITBIS groups to E47 (pagos al exterior), which today is accepted with only `<Tax Type="Exento" .../>` in TaxSummary.

**Why:** Voxel told the team that when a group that exists in the lines is missing from TaxSummary, Voxel reports it as MontoNoFacturable. User insists existing accepted E47 (and other types) behavior must be preserved.

**How to apply:**
- Build TaxSummary from detail lines, per group via `case`; presence = has lines.
- Indicator vs % ITBIS mismatch → Error (no reclassification); user approved 2026-10-06.
- LS FE 28 source stays as is. E46/E47/E48 behavior must stay as currently accepted in production.
- Reenvidador SetSummaryBases: preserve ITBIS groups without lines when Amount = 0; error only when Amount <> 0.
