# Third-party notices

RoType currently links the following third-party component:

- **Argmax OSS / WhisperKit 1.1.0** — MIT License. The upstream package vendors components under the Apache License 2.0; see its `NOTICES` file for attribution and complete terms.

The build script copies the exact upstream `LICENSE` and `NOTICES` files resolved by Swift Package Manager into the generated App bundle under `Contents/Resources/ThirdParty/WhisperKit/`.

Squirrel is not linked or redistributed by this repository. Users install it separately under the GNU General Public License v3.0. The RoType Rime schema imports the Luna Pinyin dictionary supplied by that local Squirrel installation when the user redeploys Rime; the dictionary source is not copied into this repository or the generated RoType Voice App.

`Rime/rotype_flypy.schema.yaml` adapts the Xiaohe algebra and preedit rules from the official [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) project. That schema file is marked `GPL-3.0-or-later`; its upstream authors and modification are identified in the file header. The complete license text is included at `LICENSES/GPL-3.0.txt`.
