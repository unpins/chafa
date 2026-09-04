# Changelog

## [Unreleased]

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones, and is 28% smaller (52.2 MB to 37.5 MB). Checked on Windows 10 against
  the previous binary: same version banner and the same eleven image loaders,
  and PNG, JPEG, GIF, TIFF, WebP and SVG images render to byte-identical
  output in symbol, sixel, kitty and iTerm mode. It is still a single `.exe`
  with no companion DLLs.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
