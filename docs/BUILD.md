# hiterm - Build Guide

## Prerequisites

| Tool | Version | Installation |
|------|---------|-------------|
| Xcode | 16+ (with Command Line Tools) | App Store |
| Metal Toolchain | Latest | `xcodebuild -downloadComponent MetalToolchain` |
| Zig | 0.15.x | `brew install zig` |
| CMake | 3.19+ | `brew install cmake` |
| Ninja | Latest | `brew install ninja` |
| xcodegen | Latest | `brew install xcodegen` |

## Step 1: Build libghostty

Build libghostty as a static library from the Ghostty source.

```bash
# Clone Ghostty source (first time only)
git clone --depth 1 https://github.com/ghostty-org/ghostty.git ../ghostty-src

# Build libghostty
cd ../ghostty-src
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false

# Copy artifacts
cp -r zig-out/lib/libghostty.a ../hiterm/libs/GhosttyKit/
cp include/ghostty.h ../hiterm/libs/GhosttyKit/include/
cp include/module.modulemap ../hiterm/libs/GhosttyKit/include/
```

### Build Options

| Option | Description |
|--------|-------------|
| `-Dapp-runtime=none` | Build as library (required) |
| `-Doptimize=ReleaseFast` | Optimized build |
| `-Dsentry=false` | Disable Sentry crash reporting |
| `-Dtarget=aarch64-macos` | Apple Silicon only build |

### Artifacts

```
libs/GhosttyKit/
├── include/
│   ├── ghostty.h           # C API header
│   └── module.modulemap    # Swift module map
└── libghostty.a            # Static library (all dependencies bundled)
```

libghostty.a bundles all of the following:
- Terminal emulation core
- Metal shaders (precompiled)
- FreeType (font rendering)
- HarfBuzz (text shaping)
- fontconfig
- libpng, zlib
- oniguruma (regex)
- libuv (event loop)

## Step 2: Generate Xcode Project

```bash
cd hiterm
xcodegen generate
```

This generates `hiterm.xcodeproj` based on `project.yml`.

## Step 3: Build and Run

```bash
# Command-line build
xcodebuild -scheme hiterm -configuration Debug build

# Or open in Xcode
open hiterm.xcodeproj
```

## Development Workflow

### Updating libghostty

When updating the Ghostty source and rebuilding:

```bash
cd ../ghostty-src
git pull
zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dsentry=false
cp zig-out/lib/libghostty.a ../hiterm/libs/GhosttyKit/
cp include/ghostty.h ../hiterm/libs/GhosttyKit/include/
```

### Debug Build

If you need a debug build of libghostty (very slow):

```bash
cd ../ghostty-src
zig build -Dapp-runtime=none
```

## Framework Dependencies

hiterm links against the following macOS system frameworks:

```
AppKit          - GUI framework
Metal           - GPU rendering
CoreFoundation  - Core system APIs
CoreGraphics    - Graphics / drawing
CoreText        - Font / text handling
CoreVideo       - Video frame handling
QuartzCore      - Rendering support (CALayer, CADisplayLink)
IOSurface       - GPU surface management
Carbon          - Legacy macOS support (keyboard layout)
```

## Troubleshooting

### Metal Toolchain Error

```
error: cannot execute tool 'metal' due to missing Metal Toolchain
```

Fix: `xcodebuild -downloadComponent MetalToolchain`

### Zig Version Mismatch

```
error: zig version mismatch
```

Fix: `brew upgrade zig` to ensure 0.15.x is installed.

### Linker Error (Undefined Symbols)

This occurs when a required framework is not linked. Check the frameworks section in `project.yml`.
