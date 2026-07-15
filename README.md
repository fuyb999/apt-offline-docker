# Offline GUI and Node runtime builder

This project builds external first-start artifacts for the minimal desktop used
by `docker-kde-plasma`. Keeping them outside the core image makes the reusable
base small while preserving fully offline installation.

The GUI repository includes:

- Openbox, LXQt Panel and PCManFM-Qt desktop mode;
- Fcitx5 native pinyin without Rime or Qt WebEngine;
- GTK, WebKit and AppIndicator libraries required by CC Switch;
- CC Switch 3.14.1;
- the pinned development and Python package closure requested by the runtime.

The Node output includes NVM 0.40.4, Node.js 24.17.0 and one merged `tools`
environment with pinned pnpm, OpenCode, Codex, Claude Code and Claude Code
Router packages.

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

Copy the directories to the runtime project:

```text
docker-kde-plasma/addons/softwares/apt-offline-gui-repo/
docker-kde-plasma/addons/softwares/node-runtime/
```

Alternatively, bind-mount each output directory directly to the corresponding
`/opt/addons/softwares/...` path. The runtime reads the repository and archives
directly; it does not embed them in the Docker image.

On 2026-07-15, the generated GUI repository was approximately 266 MiB and the
Node runtime directory was approximately 271 MiB. The compressed Node tools
archive was approximately 241 MiB and expands to approximately 1.0 GiB when
installed.

## Native pinyin split

Ubuntu's `fcitx5-pinyin` package also contains a Qt WebEngine dictionary-manager
plugin. The builder creates `fcitx5-pinyin-runtime` by removing only that plugin
and its Qt WebEngine dependencies. The native pinyin engine, language model,
user learning, user dictionaries, emoji dictionary and chaizi dictionary remain
available.

## Offline guarantees

- APT dependencies are resolved with `--download-only --no-install-recommends`.
- The flat repository includes exact package metadata and checksums.
- NVM, Node and npm packages are pinned and checksummed in `manifest.env`.
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
