# nivis-aws-form-action

An altcha-protected HTML-form backend, packaged as a [nivis](https://github.com/nivis-project/nivis)
module. A Go Lambda (upstream `altcha-lib-go` for the proof-of-work captcha, SES
for delivery) sits behind an API Gateway v2 HTTP API with two routes:
`GET /challenge` issues a challenge, `POST /submit` verifies the solution and
emails the form. The HMAC key lives in an SSM SecureString and is read at
runtime, so it never reaches nivis state or the Lambda environment.

The repo ships the module (`module.nix`), the handler source and its Nix
derivation (`pkgs/altcha-handler/`), and a flake exposing
`nivisModules.default` plus `lib.mkLambdaZip`. Consumers carry no Go source:
they build the zip with their own nixpkgs and pass it in as `cfg.lambdaZip`.

Successor of the OpenTofu-era `terraform-aws-html-form-action`. First deployed
for technative.eu v2026. See README.md for the consumer-facing usage, the API
contract, and the prerequisites the module does not manage.

## Commands

```bash
nix flake check                      # build, tests, coverage gate (the ship gate)
nix build .#lambda-zip               # build the Lambda deployment zip
nix develop                          # dev shell with the Go toolchain

beans list --ready                   # what is ready to pick up
beans show <id>                      # full bean
openspec list                        # active changes

scripts/ship-change.sh <change-name> # stage, gate, archive, commit, push
```

When Go dependencies change, in `pkgs/altcha-handler/`: `go mod tidy`, set
`vendorHash = lib.fakeHash;` in `default.nix`, build once, paste the "got:"
hash back in.

## Beans

When I refer to issues like nivis-aws-form-action-rn3b checkout the task
in @.beans/nivis-aws-form-action-rn3b-*.md

In this project we will use these tasks as epics for making openspec proposals.

WHEN you create a proposal at a link to this task in the proposal.md.
WHEN a bean is used to create an proposal change the status to "in-progress"
WHEN a proposal is archived add the link to the archived proposal in the frontmatter of this task like this:

```
openspec-link: openspec/changes/archive/....
```

You are allowed to update these statuses in the task frontmatter:

- in-progress
- todo
- draft
- completed
- scrapped

When making changes you are allowed to update the date/time in `updated_at` in the task frontmatter

Besides updating status and openspec-link, you are NOT ALLOWED to modify the contents of the task file.
