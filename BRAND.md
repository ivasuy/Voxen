# Voxen

A short voice-derived name for a developer's native voice intent utility.

## Design direction

Requested skills: imagegen for original raster artwork, design-taste-frontend for the visual audit and design discipline. This is native macOS product UI, not a landing page. Web stack, SEO, hero, responsive website, and Lighthouse requirements are not applicable. SwiftUI, AppKit and SF Symbols remain the foundation.

DESIGN_VARIANCE: 3. Predictable native alignment.
MOTION_INTENSITY: 3. Audio-level feedback and a small processing indicator only, respecting reduced motion.
VISUAL_DENSITY: 2. One status, no subtitle.

Before: 312-by-76-point overlay with destination, category, shortcut badge, variable-height error paragraph; system type and green activity indicator. Settings had aligned rows and a waveform title.
After: 144-by-38-point visible charcoal capsule (160 by 54 including transparent shadow clearance), SF Mono 12 medium status, five mint audio bars. Settings preserve field order, shortcut editing, permission actions, native focus styles and blue Save behavior. Logo and one-word heading replace the old title. No automatic paste or transcription changes.

Palette: charcoal #202522, mint #62DFB0, off-white #ECF2EF. Settings use system surfaces and native link colors. Error amber is semantic, not a second brand accent. Saved controls remain native disabled grey; the requested blue Save action remains unchanged. Status capsule is intentionally dark in both appearances, following the supplied reference. Other controls follow system appearance. Radius rule: capsule for status; native rounded fields/buttons; 9-point logo crop.

Accessibility: status text plus icon, not color alone; full error remains in menu and accessibility value. Overlay never takes keyboard focus. No keyboard or permission functionality removed. Reduced motion disables waveform interpolation and processing animation.

## Generated artwork

Created with the built-in imagegen tool, not the API/CLI fallback. Original saved as `Voxen/Resources/voxen-logo-v1.png`. `Voxen.icns` contains mechanical macOS icon-size conversions only, reproducible with `bash scripts/package-icon.sh`. The logo is bundled by both build.sh and Xcode's Resources phase. SF Symbols remain the monochrome menu-bar/status glyphs for native contrast at tiny sizes.

The app's display name and current bundle name are Voxen (`build/Voxen.app`). Internal identifiers remain stable for saved keys/preferences. The previous named bundle is preserved by relaunch.sh in build/PreviousBuilds. Ad-hoc signing and moving the bundle can require Accessibility reauthorization.

## Command center update

The impeccable product-UI skill guided the sidebar and native control consistency. Three destinations: Mode, History, Settings. SF Pro labels and body text, SF Mono brand name, short icon-led mode rows, restrained green selection, and system surfaces. The physical use case is a developer moving between daytime and evening work in other macOS apps, so the command center follows system appearance rather than imposing a dark theme. History is a readable list, not nested cards. Error details now live in the command center because the menu contains only Mode, Settings and Quit. The status capsule remains unchanged.

Final image prompt:

```text
Use case: logo-brand
Asset type: final square macOS app icon for Voxen, a developer-focused voice intent utility.
Primary request: Create one original, exceptionally simple geometric mint symbol that combines a sharp V silhouette with an audio pulse. A confident abstract mark, not a microphone illustration. Strong recognizable silhouette readable at 24 pixels.
Composition: one centered mark occupying about 55 percent of a square charcoal tile. The tile fills the image edge to edge; perfectly flat solid charcoal #202522 background. No exterior border, no rounded corners baked in. Balanced negative space. Mint #62DFB0 mark with clean uniform geometric construction and subtly softened joins.
Style: minimal vector-like raster logo, polished developer-tool identity. Two flat colors only. No text, no wordmark, no extra glyphs, no gradients, no texture, no shadows, no glow, no 3D, no mockup or presentation sheet. Output one square image.
```
