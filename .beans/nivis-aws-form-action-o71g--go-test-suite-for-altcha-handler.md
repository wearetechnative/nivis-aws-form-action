---
# nivis-aws-form-action-o71g
title: Go test suite for altcha-handler
status: todo
type: epic
created_at: 2026-10-06T16:11:52Z
updated_at: 2026-10-06T16:11:52Z
parent: nivis-aws-form-action-1kbr
---

Unit tests for pkgs/altcha-handler/main.go: challenge issuance, solution verification (valid, expired, tampered), request parsing for GET /challenge and POST /submit, and the field-to-email mapping. SES and SSM behind interfaces so the tests need no AWS.
