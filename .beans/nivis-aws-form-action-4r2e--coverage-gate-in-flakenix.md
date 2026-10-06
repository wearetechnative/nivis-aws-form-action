---
# nivis-aws-form-action-4r2e
title: Coverage gate in flake.nix
status: todo
type: epic
created_at: 2026-10-06T16:11:52Z
updated_at: 2026-10-06T16:11:52Z
parent: nivis-aws-form-action-1kbr
---

Add checks to flake.nix so nix flake check builds the Lambda, runs go test, and fails below 70% overall / 80% on pkgs/altcha-handler. This is the gate scripts/ship-change.sh runs before archiving.
