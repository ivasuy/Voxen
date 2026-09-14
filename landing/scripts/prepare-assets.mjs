import sharp from 'sharp';
import { mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const project = path.resolve(root, '..');
const assets = path.join(root, 'public/assets');
await mkdir(assets, { recursive: true });
// Mechanical optimization only. Keep original generated artwork and app captures unchanged.
await sharp(path.join(project, 'VoiceIntentRouter/Resources/voxen-logo-v1.png')).resize(160, 160).png().toFile(path.join(assets, 'voxen-logo.png'));
// Lossless 4x native command-center render; keep thin native text and glyphs intact.
await sharp(path.join(project, 'build/command-hero-dark.png')).webp({ lossless: true }).toFile(path.join(assets, 'hero-native-v2-4x.webp'));
await sharp(path.join(project, 'build/command-hero-dark.png')).resize({ width: 1560 }).webp({ lossless: true }).toFile(path.join(assets, 'hero-native-v2-2x.webp'));
for (const name of ['mode', 'writing', 'writing-profile', 'writing-platforms', 'history']) {
  for (const theme of ['dark']) {
    await sharp(path.join(project, `build/command-${name}-${theme}.png`)).resize({ width: 1560, withoutEnlargement: true }).webp({ quality: 85 }).toFile(path.join(assets, `${name}-${theme}.webp`));
  }
}
for (const status of ['listening', 'writing', 'copied']) {
  await copyFile(path.join(project, `build/status-${status}.png`), path.join(assets, `status-${status}-v2-6x.png`));
}
console.log('Prepared local artwork and synthetic native previews.');
