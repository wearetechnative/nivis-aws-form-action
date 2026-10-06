---
# nivis-aws-form-action-9bwd
title: Config validation
status: todo
type: epic
created_at: 2026-10-06T16:11:52Z
updated_at: 2026-10-06T16:11:52Z
parent: nivis-aws-form-action-a4bd
---

Validate cfg at evaluation time: required attrs present, region and account well-formed, ses.from and ses.to look like addresses, allowedOrigin is an origin and not a URL with a path. Fail with a message naming the offending attr.
