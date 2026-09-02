# altcha-handler

The technative.eu v2026 contact-form Lambda. Runs on the AWS `provided.al2023`
custom runtime behind an API Gateway v2 HTTP API.

## Routes

| Method | Path         | Purpose                                             |
|--------|--------------|-----------------------------------------------------|
| GET    | `/challenge` | Issue a fresh altcha challenge                       |
| POST   | `/submit`    | Verify the altcha solution, then send the form (SES) |

## altcha

Challenge creation and solution verification are delegated to the upstream
[`github.com/altcha-org/altcha-lib-go`](https://github.com/altcha-org/altcha-lib-go)
library. No proof-of-work or HMAC logic is reimplemented here.

## Secrets

The HMAC key is read from SSM Parameter Store at cold start via
`ssm:GetParameter` (+ `kms:Decrypt`). Only the parameter **name** is passed in
through the `ALTCHA_HMAC_PARAM` environment variable — the value never appears
in the Lambda environment or in nivis state.

## Environment variables

| Variable            | Meaning                                  |
|---------------------|------------------------------------------|
| `ALTCHA_HMAC_PARAM` | SSM parameter name holding the HMAC key  |
| `SES_FROM`          | Verified SES sender address              |
| `SES_TO`            | Recipient for form submissions           |
| `ALLOWED_ORIGIN`    | CORS allow-origin for the form           |

## Building

The Nix build (`default.nix`) produces `$out/function.zip` containing a single
`bootstrap` binary.

When dependencies change:

1. `go mod tidy` in this directory to update `go.sum`.
2. Set `vendorHash = lib.fakeHash;` in `default.nix`, build once, and paste the
   "got:" hash from the error back in.
