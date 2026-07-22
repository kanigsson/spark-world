# Changelog

All notable changes to this project will be documented in this file. Releases
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.1] - 2026-07-22

### Added

- Lower-bound-independent `Same_Bytes` and `Is_Byte_Concatenation` ghost
  relations with focused range, prefix, and whole-string lemmas.
- A reusable canonical-encoding injectivity theorem and a model-concatenation
  bridge for initialized result buffers.
- Proof clients for equality of active storage prefixes and model
  concatenation after appending valid UTF-8 text.

### Changed

- The plain-string equality bridge now derives byte equality through the
  shared encoding proof layer.
- Ghost model contracts and assertions use the static assertion level while
  executable contracts and assertions remain enabled at runtime.

## [0.3.0] - 2026-07-22

### Added

- Code-point length and indexed scalar access for valid ordinary strings.
- Source-safe forward cursors with byte offsets, model indices, strict
  progress, and model-order contracts.
- Plain-string prefix, suffix, and scalar-value lexicographic comparison.
- Equality, prefix, suffix, and comparison bridge lemmas connecting concrete
  strings to the shared text model.
- Public-only cursor proof clients and mixed-width runtime coverage.

### Changed

- GNATprove now uses all available provers with a 30-second timeout.

## [0.2.0] - 2026-07-21

### Added

- Strict UTF-8 sequence classification, validation, and zero-based error
  offsets.
- Single-scalar encoding and decoding with proved width and scalar bounds.
- Ghost mapping from valid Ada strings to the common text model, with a public
  byte/model relation and scalar round-trip theorem.
- Exhaustive scalar round-trip tests and systematic malformed-input coverage.

## [0.1.0] - 2026-07-21

### Added

- Unicode code-point and scalar-value types.
- Shared ghost text model based on functional scalar sequences.
- Prefix, append, concatenation, slice, and containment model relations.
- Associativity support and initial client proof-scaling experiments.
- Versioning and compatibility policy.
- Apache License 2.0 with LLVM Exceptions.
