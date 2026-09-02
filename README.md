# nivis-aws-form-action

An altcha-protected HTML-form backend as a **[nivis](https://github.com/nivis-project/nivis) module**:
a Go Lambda (upstream [`altcha-lib-go`](https://github.com/altcha-org/altcha-lib-go)
for the proof-of-work captcha, SES for delivery) behind an API Gateway v2 HTTP
API with two routes:

| Method | Path         | Purpose                                              |
|--------|--------------|------------------------------------------------------|
| GET    | `/challenge` | issue a fresh altcha challenge (~10 min expiry)      |
| POST   | `/submit`    | verify the solution, then email the form via SES     |

Successor of the OpenTofu-era `terraform-aws-html-form-action`. First deployed
for technative.eu v2026.

## Usage

```nix
# flake input:
#   formAction.url = "git+ssh://git@github.com/wearetechnative/nivis-aws-form-action";

form = formAction.nivisModules.default {
  nivis = nivis.lib;
  # namePrefix = "";        # set when instantiating twice in one domain
  cfg = {
    baseName = "myorg-prod-website";        # -> "<baseName>-altcha", "<baseName>-form"
    region = "eu-central-1";
    account = "123456789012";
    hmacParam = "/myorg/altcha_hmac";       # SSM SecureString (see prerequisites)
    ses = {
      from = "no-reply@example.org";        # verified SES identity
      to = "forms@example.org";
      allowedOrigin = "https://example.org";
    };
    lambdaZip = formAction.lib.mkLambdaZip pkgs;  # consumer's nixpkgs
    tags = { ManagedBy = "nivis"; };
  };
};

# then in your domain's toIR:
#   resources = form.resources ++ ...;
#   outputs = form.outputs // ...;
# and optionally wire form.apiEndpointRef into an Amplify same-origin rewrite
# (see wearetechnative/nivis-aws-amplify-site's formProxy option).
```

## Module conventions (nivis bean `nixform2-l2hx`)

- **`namePrefix`** namespaces all resource names (nivis ids are a flat
  `provider.type.name` space); default `""` keeps canonical names.
- The module references provider id **`"aws"`** — the consumer supplies the
  provider and the state backend.
- **Artifact passing**: the Lambda zip is built by this repo
  (`lib.mkLambdaZip pkgs` / `packages.<system>.lambda-zip`) and passed in via
  `cfg.lambdaZip` — consumers carry no Go source, `go.sum`, or `vendorHash`.

## Prerequisites (not managed by the module)

- A **verified SES identity** for `cfg.ses.from`'s domain.
- An **SSM SecureString** at `cfg.hmacParam` holding the altcha HMAC key
  (e.g. `aws ssm put-parameter --type SecureString --name ... --value "$(openssl rand -hex 32)"`).
  The Lambda reads it at runtime (`ssm:GetParameter` + `kms:Decrypt` are in its
  role); the key never appears in nivis state or the Lambda environment.

## API contract (for the site wiring the form)

- Responses are JSON-only (`Cache-Control: no-store`); submit via `fetch`:
  `200 {"ok":true}` · `403` invalid/expired solution (challenges expire ~10 min
  — refresh the widget and retry) · `400` malformed body · `502` SES delivery
  failed. Replay within the expiry window is accepted by design.
- Every form field except `altcha` is emailed as a `key: value` line;
  `subject` (optional) becomes the email subject.

## When dependencies change

In `pkgs/altcha-handler/`: `go mod tidy`, then set
`vendorHash = lib.fakeHash;` in `default.nix`, build once, and paste the
"got:" hash back in.
