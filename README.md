# Offline GUI and Node runtime builder

This project builds external first-start artifacts for the minimal desktop used
by `docker-kde-plasma`. Keeping them outside the core image makes the reusable
base small while preserving fully offline installation.

The GUI repository includes:

- Openbox, LXQt Panel and PCManFM-Qt desktop mode;
- Fcitx5 native pinyin without Rime or Qt WebEngine;
- GTK, WebKit and AppIndicator libraries required by CC Switch;
- Chrome and TurboVNC hard dependencies such as `fonts-liberation`, `libnspr4`,
  `libnss3`, `libxfont2` and `xdg-utils`;
- GTK2/3/4 Fcitx5 frontends, fonts, portals, PipeWire/RTKit and Intel graphics
  packages used by local desktop applications;
- CC Switch 3.14.1;
- the pinned development and Python package closure requested by the runtime.

The compatibility set intentionally does not restore `pcmanfm`, Fcitx5 Rime,
Fcitx5 Table, the `fcitx5-chinese-addons` meta-package or wildcard Fcitx5
modules. PCManFM-Qt and the split native-pinyin runtime replace those packages.

The Node output includes NVM 0.40.4, Node.js 24.17.0, Bun 1.3.14 and one
merged `tools` environment with pinned pnpm, OpenCode, Codex, Claude Code and
Claude Code Router packages.

`node-tools.packages` is a mixed version inventory containing npm package
specifications and the Bun binary component version. It is not a per-package
integrity record for the installed npm contents.

## Required build order

First build the stripped `docker-kde-plasma` core image. It must not contain the
GUI repository packages, CC Switch, Node.js or the global Node tools.

Then set `CORE_IMAGE` to that exact immutable tag or digest:

```dotenv
CORE_IMAGE=aura/docker-kde-plasma:core-20260715
```

Do not build artifacts against a different or floating core image. The builder
records the exact installed package state in `core-packages.lock`, and the
runtime refuses a mismatched repository.

Build both artifact sets:

```bash
CORE_IMAGE=aura/docker-kde-plasma:core-20260715 docker compose build downloader
CORE_IMAGE=aura/docker-kde-plasma:core-20260715 docker compose run --rm downloader
```

## Output layout

```text
output/
├── apt-offline-gui-repo/
│   ├── Packages
│   ├── Packages.gz
│   ├── core-packages.lock
│   ├── download-packages.txt
│   ├── manifest.env
│   └── *.deb
└── node-runtime/
    ├── manifest.env
    ├── node-tools.packages
    ├── node-tools.tar.xz
    ├── node-v24.17.0-linux-x64.tar.xz
    └── nvm-v0.40.4.tar.gz
```

Bun and the relative `bin/bunx -> bun` symlink are bundled inside
`node-tools.tar.xz`, so Bun does not add a standalone archive or any new file
to the output tree.

Copy the directories to the runtime project:

```text
docker-kde-plasma/addons/softwares/apt-offline-gui-repo/
docker-kde-plasma/addons/softwares/node-runtime/
```

Alternatively, bind-mount each output directory directly to the corresponding
`/opt/addons/softwares/...` path. The runtime reads the repository and archives
directly; it does not embed them in the Docker image.

The generated GUI repository was approximately 361 MiB on 2026-07-15; it was
not rebuilt or refreshed for this measurement. On 2026-07-23, the current
`output/node-runtime` directory is 309,157,575 bytes (`du` reports approximately
295 MiB), and `node-tools.tar.xz` is 277,366,156 bytes (approximately 264.5 MiB).
The XZ record reports an uncompressed tar stream of 1,165,015,040 bytes
(approximately 1.085 GiB).

## Native pinyin split

Ubuntu's `fcitx5-pinyin` package also contains a Qt WebEngine dictionary-manager
plugin. The builder creates `fcitx5-pinyin-runtime` by removing only that plugin
and its Qt WebEngine dependencies. The native pinyin engine, language model,
user learning, user dictionaries, emoji dictionary and chaizi dictionary remain
available.

## Offline guarantees

- APT dependencies are resolved with `--download-only --no-install-recommends`.
- The flat repository includes exact package metadata and checksums.
- The Bun source ZIP is verified against its pinned SHA256 before extraction.
- The mixed component version inventory and final Node tools archive are
  checksummed in `manifest.env`.
- Runtime installation succeeds with Docker `--network=none`.
- Qt WebEngine, Fcitx5 Rime and floating npm `@latest` packages are prohibited
  by regression tests.

## Tests

```bash
bash tests/test-packages-index.sh
bash tests/test-repack-fcitx5-pinyin.sh
bash tests/test-node-runtime-builder.sh
bash tests/test-repository-builder.sh
```
