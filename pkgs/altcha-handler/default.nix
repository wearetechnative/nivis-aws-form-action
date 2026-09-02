# Builds the altcha form handler as an AWS Lambda deployment zip for the
# `provided.al2023` custom runtime: a single static `bootstrap` binary at the
# zip root. The output is $out/function.zip, referenced from domain.nix via
# nivis `drvFile`.
{ pkgs }:
let
  handler = pkgs.buildGoModule {
    pname = "altcha-handler";
    version = "0.1.0";
    src = ./.;

    # Vendor hash of the pinned module set (go.sum). Regenerate after changing
    # dependencies: set to `lib.fakeHash`, build, and copy the "got:" value.
    vendorHash = "sha256-ncbPE+6XX/Eo/81mKA2Qt6rY1tgFEupbRu1+CI8l4tk=";

    # provided.al2023 runs a plain Linux binary; no cgo.
    env.CGO_ENABLED = "0";
    ldflags = [ "-s" "-w" ];

    # The custom runtime requires the entrypoint to be named `bootstrap`.
    postInstall = ''
      mv "$out/bin/altcha-handler" "$out/bin/bootstrap"
    '';
  };
in
pkgs.runCommand "altcha-handler-lambda"
  {
    nativeBuildInputs = [ pkgs.zip pkgs.openssl ];
  }
  ''
    mkdir -p "$out"
    cp "${handler}/bin/bootstrap" ./bootstrap
    chmod +w ./bootstrap
    # Reproducible archive: zip embeds the file mtime (even with -X), so pin it
    # to a fixed date — the zip is then a pure function of the binary, and
    # source_code_hash only changes when the code does.
    touch -d '1980-01-02 00:00:00 UTC' ./bootstrap
    zip -X -j "$out/function.zip" ./bootstrap
    # Base64 SHA-256 of the zip. Doubles as the Lambda source_code_hash and,
    # via readFile in domain.nix, forces THIS derivation to build during nivis's
    # eval — so the drvFile output path exists in the store when nivis realises
    # it at apply (a never-built output path has no substituter).
    openssl dgst -sha256 -binary "$out/function.zip" | openssl base64 -A | tr -d '\n' \
      > "$out/function.zip.base64sha256"
  ''
