// Renders the platform icon PNGs from assets/icon/ftube.svg
// (docs/spec-v0.2.md D-29). flutter_launcher_icons needs PNG input.
//
//   npm i --prefix <dir> @resvg/resvg-js@2.6.2
//   NODE_PATH=<dir>/node_modules node tool/render_icon.mjs
//   dart run flutter_launcher_icons
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const require = createRequire(join(process.env.NODE_PATH ?? '.', 'x.js'));
const { Resvg } = require('@resvg/resvg-js');

const dir = 'assets/icon';
const svg = readFileSync(join(dir, 'ftube.svg'), 'utf8');
const tile = /<g id="tile">[\s\S]*?<\/g>/;

// The tile scaled up to fill [inset]..1024-[inset].
const inset = (n) =>
  svg.replace(
    tile,
    (g) =>
      `<g transform="translate(${n} ${n}) scale(${(1024 - 2 * n) / 824}) translate(-100 -100)">${g}</g>`,
  );

// name: [svg, size in px]
const variants = {
  // macOS: the 824px tile on a 1024px canvas, as Apple's grid expects.
  'ftube_macos.png': [svg, 1024],
  // Windows, Linux and the in-app asset: the tile almost edge to edge.
  'ftube.png': [inset(32), 1024],
  // The Linux window icon, bundled as a Flutter asset.
  'ftube_256.png': [inset(32), 256],
  // Android adaptive icon layers. flutter_launcher_icons insets the
  // foreground by 16%, so the glyph is drawn larger to end up inside the
  // 66dp safe zone at about half the icon's height.
  'ftube_foreground.png': [
    svg
      .replace(tile, '')
      .replace(
        /<g id="glyph"[\s\S]*?<\/g>/,
        (g) =>
          `<g transform="translate(512 505) scale(1.15) translate(-512 -505)">${g}</g>`,
      ),
    1024,
  ],
  'ftube_background.png': [
    svg.replace(tile, '<rect width="1024" height="1024" fill="url(#bg)"/>'),
    1024,
  ],
};

for (const [name, [source, size]] of Object.entries(variants)) {
  const png = new Resvg(source, { fitTo: { mode: 'width', value: size } })
    .render()
    .asPng();
  writeFileSync(join(dir, name), png);
  console.log(`${name}: ${png.length} bytes`);
}
