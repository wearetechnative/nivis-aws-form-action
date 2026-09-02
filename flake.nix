{
  description = "nivis-aws-form-action — altcha-protected HTML-form backend (Go Lambda + API Gateway v2 + SES) as a nivis module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The nivis module: { nivis, namePrefix ? "", cfg } -> { resources, outputs, apiEndpointRef }.
      nivisModules.default = import ./module.nix;

      lib = {
        # Build the Lambda deployment zip with the CONSUMER's nixpkgs — prefer
        # this over packages.<system> so the Go toolchain matches the consumer's
        # pin and the artifact is reproducible across repos.
        mkLambdaZip = pkgs: import ./pkgs/altcha-handler { inherit pkgs; };
      };

      packages = forAllSystems (pkgs: {
        lambda-zip = import ./pkgs/altcha-handler { inherit pkgs; };
        default = import ./pkgs/altcha-handler { inherit pkgs; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.go ]; };
      });
    };
}
