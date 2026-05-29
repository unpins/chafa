# chafa

Standalone build of [chafa](https://hpjansson.org/chafa/) — terminal graphics: render images and animations as ANSI/Unicode/sixel/kitty art.

[![CI](https://github.com/unpins/chafa/actions/workflows/chafa.yml/badge.svg)](https://github.com/unpins/chafa/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin chafa
```

Or run without installing:

```bash
unpin run chafa
```

## Build locally

```bash
nix build github:unpins/chafa
./result/bin/chafa --version
```

Or run directly:

```bash
nix run github:unpins/chafa -- image.png
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/chafa/releases) page has standalone binaries for manual download.

## Build notes

- **Full codec:** every image loader is enabled — AVIF, GIF, HEIF, JPEG, JXL, PNG, QOI, SVG, TIFF, WebP, XWD (plus CoreGraphics on macOS). No upstream features disabled.
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **macOS:** static `.a` codec chain linked in; only system frameworks/libSystem stay dynamic.

The full-codec loader chain is wired up across pkgsStatic / cross-darwin / mingw in [`nix-lib/native-overlay`](https://github.com/unpins/nix-lib/tree/main/native-overlay) (`libavif`, `libheif`, `libjxl`, `libyuv`, `graphite2`, …).
