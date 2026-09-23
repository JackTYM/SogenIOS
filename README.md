# sogen iOS app shell

An iOS app that embeds `sogen::windows_emulator` and runs Windows guest samples
(`native-gpu-clear-sample`, `mouse-input-test-sample`) inside it, presenting frames through a
`CALayer`. Two emulation backends are available -- FEX and Unicorn -- picked by a build setting,
and there are two Xcode targets so the app can be built for the Simulator without any of the
real-device-only JIT machinery.

`sogen` itself is vendored as a git submodule at `deps/sogen`, not a sibling checkout.

## One-time setup

```sh
git clone --recurse-submodules https://github.com/JackTYM/SogenIOS.git
cd SogenIOS
```

If you already have a clone without `--recurse-submodules`:

```sh
git submodule update --init --recursive
```

Build sogen's static libraries for both iOS SDKs, and stage the guest `.exe`s the app bundles:

```sh
brew install xcodegen mingw-w64
cd deps/sogen
cmake --workflow --preset=ios-embed-device
cmake --workflow --preset=ios-embed-simulator
cd ../..
deps/sogen/tools/stage-ios-emulation-root.sh
```

`stage-ios-emulation-root.sh` builds `native-gpu-clear-sample.exe`/`mouse-input-test-sample.exe`
with the 32-bit mingw-w64 toolchain and stages a trimmed emulation root into
`deps/sogen/build/ios-root/`. It defaults to reading a full sogen emulation root from
`build/release/artifacts/root` (i.e. a desktop `cmake --build --preset=release` run) -- pass an
explicit source root as its first argument if you don't already have one.

### Vendor dependencies

`project.yml` links a static MoltenVK into both Xcode targets from `Vendor/MoltenVK/`, which is
gitignored and not fetched by anything above. Obtain the two archives once:

```sh
mkdir -p /tmp/mvk
gh release download --repo KhronosGroup/MoltenVK --pattern 'MoltenVK-all.tar' --dir /tmp/mvk --clobber
tar xf /tmp/mvk/MoltenVK-all.tar -C /tmp/mvk
XCF=$(find /tmp/mvk -maxdepth 6 -name 'MoltenVK.xcframework' -type d | head -1)
mkdir -p Vendor/MoltenVK/ios-device Vendor/MoltenVK/ios-simulator
cp "$XCF"/ios-arm64/libMoltenVK.a   Vendor/MoltenVK/ios-device/libMoltenVK.a
cp "$XCF"/*simulator*/libMoltenVK.a Vendor/MoltenVK/ios-simulator/libMoltenVK.a
```

(If `gh release download` finds no matching asset, MoltenVK's own source build --
`./fetchDependencies --ios --iossim && make ios iossim` in a clone of
`KhronosGroup/MoltenVK` -- produces the same two archives, just slower.)

The real-device `SogenIOS` target additionally needs `Vendor/StikJIT-src` (StikJIT,
`StikDebug/StikJIT`, MPL-2.0, vendored from source) including its prebuilt, real-device-only
`libidevice_ffi.a`. That vendoring is outside the scope of this document -- but `xcodegen
generate` still validates every target's source paths regardless of which scheme you actually
build, so a Simulator-only build needs empty placeholders even without vendoring StikJIT for
real:

```sh
mkdir -p Vendor/StikJIT-src/Sources Vendor/StikJIT-src/Resources
```

## Choosing a backend and a target

Two Xcode targets exist, both built from the same `Sources/`:

- **`SogenIOS`** -- the real app; builds for a physical iPhone. Embeds `JITHelper` (an
  ExtensionKit extension that calls StikJIT's `enableJIT` against the host process), because on
  real iOS hardware neither backend's JIT can take its first W→X code-page transition without
  first negotiating the JIT26 breakpoint protocol -- see "JIT grant" below.
- **`SogenIOS-Simulator`** -- the same sources and settings (they share `project.yml`'s
  `&sogenIOSAppSettings`/`&sogenIOSInfoProperties` anchors) minus the `JITHelper`/StikJIT
  dependency chain, which fails to link for any Simulator architecture at all. This target exists
  purely so a Simulator build is possible; `SetupView.swift`'s
  `#if targetEnvironment(simulator)` branch skips the whole JIT-grant flow at runtime, since the
  Simulator has no TXM/SPTM enforcement and Unicorn's/FEX's `mmap(PROT_EXEC)` just works there.

Independently of the target, `project.yml`'s `settings.base.GCC_PREPROCESSOR_DEFINITIONS`
(currently `["SOGEN_IOS_USE_FEX=1"]`) picks which backend `SogenBridge.mm` constructs:

- **FEX** (`SOGEN_IOS_USE_FEX=1`, the current default) -- used for the real-device build; TSO
  memory-ordering emulation is disabled for it on-device (`EMULATOR_FEX_NO_TSO=1`) to avoid a
  misaligned-atomic fault class real hardware can't recover from.
- **Unicorn** (remove/clear the define) -- the original backend; also fine on the Simulator.

Edit that one line in `project.yml` and re-run `xcodegen generate` to switch backends. The
on-screen log always reports which one is active (`[sogen] backend: fex` / `unicorn`).

## Build (Simulator)

```sh
mkdir -p Resources
cp deps/sogen/build/ios-root/native-gpu-clear-sample.exe Resources/
cp deps/sogen/build/ios-root/mouse-input-test-sample.exe Resources/
xcodegen generate
xcodebuild -project SogenIOS.xcodeproj -scheme SogenIOS-Simulator -sdk iphonesimulator \
  -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
```

The `.xcodeproj` is generated by xcodegen and is gitignored -- edit `project.yml`, never the
project file. CMake and Xcode stay decoupled: Xcode never invokes CMake, it just links the static
archives the `ios-embed-*` presets already produced under `deps/sogen/build/`.

## Build (real device)

Same `Resources/` staging as above, then build the `SogenIOS` scheme instead, with a real
`-destination`/`DEVELOPMENT_TEAM` and (per "Vendor dependencies" above) `Vendor/StikJIT-src`
already in place:

```sh
xcodebuild -project SogenIOS.xcodeproj -scheme SogenIOS -sdk iphoneos \
  -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build build
```

`CODE_SIGN_STYLE: Automatic` in `project.yml` still needs an Apple ID signed into Xcode's own
Accounts preferences to actually fetch/create a matching provisioning profile -- that part is
interactive-only and isn't set by this file.

## Provision the emulation root

The root is ~1.8 GB and is deliberately **not** bundled in the `.app`; the app expects it at
`<Documents>/root` (`filesys/` and `registry/` present) and shows a visible on-screen error if
it's missing.

The simplest option: tap **Download Emulation Root** in the app itself. It fetches a ready-made
root from `https://sogen.dev/root.zip` and extracts it into `<Documents>/root` directly, no
Mac-side commands needed, on both Simulator and device.

For local iteration on the guest samples themselves (before any change to them is reflected in
that hosted zip), copy the just-staged `deps/sogen/build/ios-root/` in manually instead:

Simulator:
```sh
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/SogenIOS-Simulator.app
xcrun simctl launch booted com.jacksonyarger.sogenios.simulator
xcrun simctl terminate booted com.jacksonyarger.sogenios.simulator
DATA=$(xcrun simctl get_app_container booted com.jacksonyarger.sogenios.simulator data)
rsync -a --delete deps/sogen/build/ios-root/ "$DATA/Documents/root/"
```

Device:
```sh
xcrun devicectl device install app --device <udid> \
  build/Build/Products/Debug-iphoneos/SogenIOS.app
xcrun devicectl device copy to --device <udid> \
  --domain-type appDataContainer --domain-identifier com.jacksonyarger.sogenios \
  --source deps/sogen/build/ios-root --destination Documents/root
```

`UIFileSharingEnabled` is set, so dragging `deps/sogen/build/ios-root` in as `root` via Finder's
device file sharing is an equivalent fallback if `devicectl copy to` misbehaves.

## Run

`xcrun simctl launch --console-pty booted com.jacksonyarger.sogenios.simulator`

Expected: the view cycles blue → green → red → yellow → cyan → magenta → orange → violet at 400 ms
per frame and holds violet; the log ends with `[ngcs] done`. Tapping the view logs
`[ios-ui] delivering raw mouse input flags=0x0001` / `0x0002`.

Once the first guest has booted, a **Boot Input Test** button appears that restarts the emulator
against `mouse-input-test-sample.exe` instead. Inside a running guest, the top bar's cursor-arrow
button toggles touchscreen mode (direct taps) vs. trackpad mode (relative motion with a small
synthetic white-dot cursor drawn over the guest view, hidden automatically whenever the guest
itself hides its own cursor).

Note: the `[ngcs]`/`[sogen]` log lines only appear in the **on-screen** log, not in the
`simctl launch --console-pty` console output -- `SogenBridge.mm`'s `appendLog` routes through the
Swift `onLogLine` closure once `SetupView` sets it, bypassing `NSLog`/stdout entirely. Read the
log on the simulator screen (or via a screenshot) rather than grepping console output.

## JIT grant (real device only)

Both backends JIT-compile guest x86 into host ARM64 machine code and execute it directly; on real
iOS hardware, that first W→X page transition is rejected by TXM/SPTM enforcement unless the
process has already negotiated the JIT26 breakpoint protocol (a `brk #0xf00d`-based
self-attach/debugger dance). `Sources/JIT/` (`JIT26.{c,h}`, `JITExec.{c,h}`, `JITSelfAttach.{c,h}`,
`JITCoordinator.swift`, `JITGate.swift`, `JITBridge/JITMessage.swift`) implements this, and
`SetupView.swift` runs the full grant sequence before ever constructing the emulator -- a missing
pairing file or a failed grant surfaces as a visible on-screen `ERROR:` line, and the guest is
never started in that case (it would otherwise crash on the first JIT-buffer translation).

The grant needs a device-scoped pairing file, imported by dropping it into the app's Documents
folder via the Files app (`UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` are set) and
tapping **Check for Pairing File** -- see
https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md for how to obtain one.

It also needs a loopback tunnel so `JITHelper` can reach the device's own developer services.
Two implementations exist, picked by `project.yml`'s `SWIFT_ACTIVE_COMPILATION_CONDITIONS`:

- **LocalDevVPN** (`SOGEN_IOS_USE_LOCALDEVVPN`, the current default) -- delegates to the
  separately-installed App Store app
  [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), round-tripped via the
  `localdevvpn://`/`sogenios://` URL schemes. Works under an ordinary personal-team signing
  identity. If it isn't installed, the app shows an **Install LocalDevVPN** button and a
  **Retry** button once it is.
- **`TunnelExtension`** (an in-process `NEPacketTunnelProvider`, adapted from
  `SideStore/StosVPN`'s `TunnelManager`, MIT-licensed) -- fully self-contained, but requires the
  `com.apple.developer.networking.networkextension` entitlement, which Apple does not grant to
  free personal-team accounts. To use it instead: re-enable its `target: TunnelExtension`
  dependency (commented out in `project.yml`'s `SogenIOS` target) and drop
  `SOGEN_IOS_USE_LOCALDEVVPN` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. This needs either a paid
  Apple Developer Program account with Network Extensions approved as `DEVELOPMENT_TEAM` for at
  least that target, or an unsigned/third-party-resigned build outside the normal personal-team
  `xcodebuild` flow.
