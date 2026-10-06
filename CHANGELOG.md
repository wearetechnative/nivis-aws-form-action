# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [0.1.0] - 2026-10-06

### Added

- Initial release: nivis module exposing `GET /challenge` and `POST /submit`
  behind an API Gateway v2 HTTP API, a Go Lambda verifying altcha proof-of-work
  solutions, and SES delivery of submitted form fields.
- `lib.mkLambdaZip` so consumers build the deployment zip with their own
  nixpkgs instead of vendoring the Go source.
- `namePrefix` for instantiating the module more than once in a single domain.
