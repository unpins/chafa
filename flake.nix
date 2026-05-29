{
  description = "Standalone build of chafa";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # chafa: terminal graphics. All format loaders live in the CLI tool
  # (configure.ac gates them behind --with-tools); libchafa core carries
  # none. Full-codec scope: built-ins (PNG via lodepng, GIF via libnsgif,
  # QOI, XWD) + freetype (required by the font/symbol loader) + the seven
  # optional external loaders: JPEG, WebP, TIFF, SVG, AVIF, HEIF, JXL.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;

      # Wire the full codec chain onto a (static) pkgs scope and return the
      # chafa derivation with every loader lib linked in. Shared by the
      # native `build` (pkgsStatic) and `windowsBuild` (mingw cross) paths.
      #
      # Codec-chain fixes are layered so each sees the prior fix. Layer 1
      # holds everything a top-level loader depends on AND that fails to
      # build vanilla in this scope: libyuv (drops its SHARED target),
      # graphite2 (libtool .la names a phantom .so), and on darwin the
      # glib/fontconfig/pango/cairo/dav1d chain librsvg pulls (same
      # cross-within-darwin fixes ffmpeg/rsvg-convert use; each is identity
      # off darwin so linux/windows pass through). Layer 2 fixes the top
      # consumers (libavif/librsvg/libjxl/libheif) — they must sit ABOVE
      # layer 1 so their transitive deps resolve to the fixed versions
      # (overrideAttrs doesn't rewire already-resolved deps).
      mkChafa = scope:
        let
          lib = scope.lib;
          host = scope.stdenv.hostPlatform;
          pYuv = scope.extend (final: prev:
            {
              libyuv = ulib.nativeFixes.libyuv prev;
              graphite2 = ulib.nativeFixes.graphite2 prev;
            } // lib.optionalAttrs host.isRiscV {
              # riscv64: libjpeg-turbo's RVV SIMD coverage helper fails to
              # compile (jsimd_can_encode_mcu_AC_refine_prepare undeclared in
              # the new RVV port). Pulled here via the chafa JPEG loader and
              # transitively (gdk-pixbuf → libtiff/libwebp). Gate to riscv so
              # the other arches keep the unmodified (cache-hit) libjpeg.
              libjpeg = ulib.nativeFixes."libjpeg-turbo" prev;
            } // lib.optionalAttrs host.isDarwin {
              glib = ulib.nativeFixes.glib prev;
              fontconfig = ulib.nativeFixes.fontconfig prev;
              pango = ulib.nativeFixes.pango prev;
              cairo = ulib.nativeFixes.cairo prev;
              dav1d = ulib.nativeFixes.dav1d prev;
            });
          p = pYuv.extend (final: prev: {
            libavif = ulib.nativeFixes.libavif prev;
            librsvg = ulib.nativeFixes.librsvg prev;
            # libjxl: lib-only (drop GDK/GIMP shared plugins + doxygen's
            # graphviz→gd chain that fails to link here).
            libjxl = ulib.nativeFixes.libjxl prev;
            # libheif: decode-only (drop rav1e/x265/libaom encoders + the
            # gdk-pixbuf plugin .so).
            libheif = ulib.nativeFixes.libheif prev;
          });
        in
        p.chafa.overrideAttrs (old: {
          # Add the loader libs nixpkgs' chafa doesn't pull (it ships only
          # glib/libavif/libjxl/librsvg). pkgsStatic propagates only `out`;
          # the .pc lives in .dev, so add both or PKG_CHECK_MODULES misses it.
          buildInputs = (old.buildInputs or [ ])
            ++ builtins.concatMap (x: [ x (x.dev or x) ]) [
            p.freetype
            p.libjpeg
            p.libwebp
            p.libtiff
            p.libheif
          ]
          # librsvg-2.0.pc Libs.private carries `-lunwind` only on musl
          # (rustc's --print=native-static-libs emits it there); a
          # `pkg-config --static librsvg` consumer must have libunwind.a on
          # its link path. Not present on darwin/mingw, so gate to musl.
          ++ lib.optionals host.isMusl [ p.libunwind ]
          # chafa's configure adds `-pthread` to the link; mingw gcc maps that
          # to `-lpthread`, which only exists in the winpthreads package
          # (`cannot find -lpthread` otherwise). Same input ffmpeg's mingw
          # build pulls.
          ++ lib.optionals host.isMinGW [ p.windows.pthreads ]
          # mingwStaticCross does NOT auto-promote buildInputs →
          # propagatedBuildInputs the way pkgsStatic does, so a loader lib's
          # Requires.private chain never reaches chafa's PKG_CONFIG_PATH. With
          # `pkg-config --static` chafa probes `--exists libheif/libjxl/
          # librsvg-2.0`, the probe can't resolve the transitive .pc, and chafa
          # silently drops the HEIF/JXL/SVG loaders (Linux/darwin propagate, so
          # only mingw needs this). Add the missing transitive .pc providers
          # explicitly (dav1d/freetype/glib/brotli/tiff/jpeg are already on the
          # path via other inputs):
          #   libheif  → libde265
          #   libjxl   → libhwy lcms2
          #   librsvg  → cairo pango harfbuzz gdk-pixbuf libxml2 pixman
          #              fontconfig fribidi graphite2
          ++ lib.optionals host.isMinGW (builtins.concatMap (x: [ x (x.dev or x) ]) [
            p.libde265
            p.libhwy
            p.lcms2
            p.cairo
            p.pango
            p.harfbuzz
            p.gdk-pixbuf
            p.libxml2
            p.pixman
            p.fontconfig
            p.fribidi
            p.graphite2
          ]);
        }
        # darwin: chafa builds its own libchafa. pkgsStatic-darwin keeps shared
        # enabled (isStatic is true, but mkStandaloneFlake's
        # filterEnableStaticOnDarwin strips --enable-static/--disable-shared to
        # dodge the `--enable-static → LDFLAGS=-static` probe breakage, and
        # dropSharedLibs is a no-op when isStatic), so libtool builds
        # libchafa.dylib and links the chafa tool against it — otool then shows
        # a /nix/store libchafa.0.dylib, breaking the single-binary promise on
        # a user's Mac. Disable shared via the `--enable-shared=no` spelling:
        # libtool treats it as --disable-shared (libchafa.a only, linked in),
        # but it isn't the literal flag the filter removes, and unlike
        # --enable-static it never forces LDFLAGS=-static.
        // lib.optionalAttrs host.isDarwin {
          configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-shared=no" ];
        }
        # mingw: force `pkg-config --static`. pkgsStatic's pkg-config wrapper
        # is static-by-default (the platform is isStatic from the start), but
        # mingwStaticCross only flips isStatic via overlay *after* the wrapper
        # was built, so it stays dynamic — PKG_CHECK_MODULES then drops every
        # Requires.private/Libs.private/Cflags.private. That loses the codec
        # archives libavif/libheif/libjxl pull (libyuv/aom/dav1d/de265/
        # sharpyuv), the Win32 system libs (bcrypt/ole32/uuid/userenv) and
        # libheif's `-DLIBHEIF_STATIC_BUILD` (Cflags.private) that turns off
        # its `__declspec(dllimport)` decoration. Same consumer-level knob
        # ffmpeg passes as `--pkg-config-flags=--static`. Gated as a separate
        # attr so native/darwin keep their (cached) preConfigure-less drv.
        // lib.optionalAttrs host.isMinGW {
          preConfigure = ''
            export PKG_CONFIG="${host.config}-pkg-config --static"
            # chafa is a C program linked with gcc, but the codec chain pulls
            # C++ archives (libvmaf/libheif/libjxl/libaom) whose ABI symbols
            # (vtables, std::runtime_error, __cxxabiv1) need libstdc++. The C
            # driver doesn't add it; put it in LIBS so autoconf appends it at
            # the very end of the link, after every codec archive.
            export LIBS="-lstdc++ ''${LIBS:-}"
            # libheif/libjxl headers decorate their API with
            # __declspec(dllimport) under _WIN32 unless a static-build macro is
            # defined; chafa's heif/jxl loaders then reference __imp_* thunks
            # absent from the static .a. Both libs ship the macro in their .pc
            # Cflags.private (-DLIBHEIF_STATIC_BUILD / -DJXL_STATIC_DEFINE), but
            # freedesktop pkg-config 0.29.2 (this wrapper) silently ignores
            # Cflags.private even with --static (only pkgconf emits it). Define
            # them globally so every chafa TU compiles against the static decls.
            export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -DLIBHEIF_STATIC_BUILD -DJXL_STATIC_DEFINE"
          '' + (old.preConfigure or "");
          # Without this, libtool links the .dll.a import libs it finds on the
          # path (libstdc++/libgcc_s/libwinpthread/libmcfgthread) and the
          # DLL-link hook drops the matching DLLs next to chafa.exe — the
          # unpins single-binary promise broken. `-all-static` (make-time, as
          # mingwStaticBinary does it — NIX_LDFLAGS at configure trips the
          # "C compiler works" probe) forces every -l to resolve to its .a.
          makeFlags = (old.makeFlags or [ ]) ++ [ "LDFLAGS=-all-static" ];
        });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "chafa";
      smoke = [ "--version" ];
      smokePattern = "Chafa version";
      build = pkgs: mkChafa pkgs.pkgsStatic;
      windowsBuild = pkgs: mkChafa (ulib.mingwStaticCross pkgs);
    };
}
