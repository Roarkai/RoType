# Third-party notices

RoType currently links the following third-party component:

- **Argmax OSS / WhisperKit 1.1.0** — MIT License. The upstream package vendors components under the Apache License 2.0; see its `NOTICES` file for attribution and complete terms.

The build script copies the exact upstream `LICENSE` and `NOTICES` files resolved by Swift Package Manager into the generated App bundle under `Contents/Resources/ThirdParty/WhisperKit/`.

`Squirrel/` vendors Squirrel 1.1.2 at upstream commit `876adebaf2f612951dcdca8a591de65401222b9a` and carries RoType menu integration changes. Squirrel and RoType's modified Squirrel frontend are distributed under the GNU General Public License v3.0; the upstream license is preserved at `Squirrel/LICENSE.txt`. Its pinned librime, plum, and Sparkle dependencies remain Git submodules with their upstream license terms.

The RoType Rime schema imports the Luna Pinyin dictionary supplied by Squirrel when the user redeploys Rime. The dictionary source remains part of Squirrel's upstream data dependency and is not copied into the separately built RoType Voice App.

`Rime/rotype_flypy.schema.yaml` adapts the Xiaohe algebra and preedit rules from the official [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) project. That schema file is marked `GPL-3.0-or-later`; its upstream authors and modification are identified in the file header. The complete license text is included at `LICENSES/GPL-3.0.txt`.
