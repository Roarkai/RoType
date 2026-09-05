# Third-party notices

`Squirrel/` vendors Squirrel 1.1.2 at upstream commit `876adebaf2f612951dcdca8a591de65401222b9a` and carries RoType menu integration changes. Squirrel and RoType's modified Squirrel frontend are distributed under the GNU General Public License v3.0; the upstream license is preserved at `Squirrel/LICENSE.txt`. Its pinned librime and plum dependencies retain their upstream license terms. The upstream Sparkle source remains in the imported source tree for history, but RoType does not link, embed, or download Sparkle and does not consume the Squirrel update feed.

The RoType Rime schema imports the Luna Pinyin dictionary supplied inside the signed input method bundle. RoType factory schemas and Lua modules are also stored in the bundle's `Contents/SharedSupport`; per-user learning data remains under `~/Library/Rime`.

RoType bundles `zh-hant-t-essay-bgw.gram` from [lotem/rime-octagram-data](https://github.com/lotem/rime-octagram-data) branch commit `97bf55046aad163c3d1881abae5312040b1bbed9`. The model is distributed under LGPL v3; the license text is included at `LICENSES/LGPL-3.0.txt`. The build fetches the pinned model and verifies SHA-256 `0488ebd6688f900a39200f2b794f2f99bcbf1e8fc27280ae4a2324b08b1559c1`.

`Rime/rotype_flypy.schema.yaml` adapts the Xiaohe algebra and preedit rules from the official [rime-double-pinyin](https://github.com/rime/rime-double-pinyin) project. That schema file is marked `GPL-3.0-or-later`; its upstream authors and modification are identified in the file header. The complete license text is included at `LICENSES/GPL-3.0.txt`.
