# ChaseLab

Visual slice sequencer and FFGL effects for Resolume Arena. **Independent project**, not affiliated with or endorsed by Resolume or Hybrid Constructs.

**Beta 0.15.0-beta.1 — macOS only.** Original editor/effect functions were verified in Arena 7.23.0 on an Apple Silicon Mac. The renamed distribution and installer are a new beta. Intel is an experimental build awaiting testing on an Intel Mac. Windows is not implemented.

## Download and install

Packages are published under [Releases](https://github.com/AndresMego/chaselab/releases). They are local ad-hoc signed test builds, **not Developer ID signed or notarized**.

1. Save and close Arena. Close older running copies of ChaseLab Live.
2. Install the package matching your Mac: AppleSilicon or Intel-experimental.
3. Open **ChaseLab** from Applications. Choose **Instalar efectos en Arena…** in its menu and select your Resolume Arena `Extra Effects` folder in Documents.
4. Reopen Arena and search for `CL`: **CL Player**, **CL Bumper**, **CL Outliner**, **CL Wiper**, **CL Random**. Source: **CL Outline Src**.
5. Keep ChaseLab open and connect Arena in the editor. For comparison, enable one masking effect at a time.

The installer preserves project recovery/envelope locations and stable app/plugin identifiers. Existing copies of the same plugin files are backed up under your user's Application Support/ChaseLab-Installer/Backups, outside Arena's scan folder. It does not remove user compositions or presets. If an older app lives elsewhere, remove that app copy manually after saving and verifying the new one.

## Features

- Slice XML import and optional following of **saved** Advanced Output changes.
- Factory patterns; drawing cells, copying steps, per-step durations and undo.
- Preview zoom/pan and middle mouse hand tool.
- Bézier envelopes with a shared named library.
- Player with BPM/manual playback and echoes; percussive Bumper; animated Outliner effect/source; Wiper; automatic/manual Random.

The masks use input polygons. Output warping, soft edges and calibration are not reproduced. Custom Views/groups are pending. Some time/direction scales are independent implementations and are not claimed numerically identical to other software.

## Compatibility

- Built for macOS 13+; only the development Mac's macOS 26.6.2 / Arena 7.23.0 has been exercised natively so far.
- Apple Silicon editor and experimental Intel editor are separate packages; FFGL bundles include both architectures.
- Resolume 7.4.1 is an **unverified technical floor** for dynamic selectors; Apple Silicon native Arena begins at 7.11. Do not treat these as certified minimum versions. [FFGL SDK](https://github.com/resolume/ffgl)
- Avenue, other host versions and Windows are unverified/unsupported in this beta. Preset discovery currently targets Arena.
- Editor and plugins must run under the same user on the same computer. No network bridge or plugin-only offline mode.

## Build

On macOS with Xcode Command Line Tools and Python 3:

```sh
python3 scripts/build.py --arch arm64
python3 scripts/package.py --arch arm64
python3 scripts/build.py --arch x86_64 --skip-plugins
python3 scripts/package.py --arch x86_64
python3 scripts/test.py
# Real local GPU context required for FFGL pixel tests:
python3 scripts/test.py --gpu
```

Build outputs live in `build/`; installers in `dist/`. No original Chaser binaries, private user projects, media or original-software inspection records are part of this repository. `examples/demo.chaselab` is synthetic.

## License

Original ChaseLab code: **Apache-2.0**. See LICENSE and NOTICE. Vendored FFGL SDK: **BSD-3-Clause**, with its own license preserved; see THIRD_PARTY_NOTICES.md. These notices are also included inside the distributed app.

## Español

ChaseLab es un editor visual de secuencias y efectos FFGL para Arena. Instalación, pruebas y limitaciones: [guía en español](docs/INSTALACION.md). La versión Intel está preparada para pruebas, no certificada. Guarda siempre tu composición antes de actualizar.
