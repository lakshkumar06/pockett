# Pocket: image-led art direction

The previous native implementation styled standard UI without giving the product a visual identity. This exploration changes the composition and introduces original raster artwork. `directions.png` is a generated concept board, not a screenshot or device verification.

Three candidates:
1. Folded Worlds: macro sculptural acetate and paper, forest/citron, continuous image-led Home hero, compact functional rows.
2. Offline Club: editorial architecture/photo collage, warm white/vermilion, asymmetric compositions.
3. Play Objects: screenprint abstract geometry, lilac/orange/charcoal.

Recommended direction: Folded Worlds. Its folded material metaphor fits collecting independent apps, works with existing green identity, and gives the product an immediately recognizable image language. Avoid scattering identical artwork onto every row. Home and welcome carry the main image; Activity and profile use quieter related crops or companion images. App identity remains creator supplied. Art never implies a fake activity, app or metric.

Implementation principles:
- Actual bundled images, not recreating pictures with SwiftUI primitive shapes.
- All text/buttons remain live, accessible SwiftUI, never baked into a screen image.
- Image-led Continue surface; compact pinned rows replace the repeated tile grid.
- Real account data, readable contrast, Dynamic Type expansion, no animations when Reduce Motion is on.
- Artwork belongs to Pocket's shell; creator-hosted pages retain their own design.

Generated using the built-in image-generation tool. Concept prompt: Three high-fidelity Pocket Home directions with identical real UI content (Continue/Little Notes, pinned Tiny Focus/Read Later, Home/Activity/You tabs): sculptural folded acetate and paper in forest/citron; editorial architecture and sky collage in vermilion; bold screenprint shapes in lilac/orange. Premium editorial composition, original imagery, geometric sans typography, no fake metrics, generic dashboard cards or wellness pastels.

## Production assets and prompts

Built-in image generation; original outputs copied unmodified into the project:

- `Pocket/Icons.xcassets/pocket-folded-world.imageset/art.png`: macro folded citron acetate, smoky translucent acrylic and ivory paper forming a pocket-like hollow against deep forest. Portrait composition, physical shadows, subtle grain, sculpture across center/upper area, quiet dark space for live controls. No lettering, icons, UI, watermark or phone frame.
- `Pocket/Icons.xcassets/pocket-quiet-fold.imageset/art.png`: landscape editorial studio still life of a folded ivory-paper envelope/sculpture with forest interior and citron acetate tab. Directional shadow, fiber detail, asymmetrical right-hand composition and quiet ivory negative space. No lettering, icons, UI or watermark.

The two images are bundled locally. Home uses the dark artwork behind actual wordmark/search/add/Continue controls; its smaller library entries are live rows. Welcome uses the dark image; Profile and empty Activity use the light companion. Images are decorative for VoiceOver. Text contrast is protected by a dark overlay on the hero; text can grow vertically with Dynamic Type. The 3-direction board remains exploratory; sample app names on that board are not injected into the product.

User selected 01 — Folded Worlds. Signed iOS build and checks are recorded in STATUS.md. No actual device screenshot is implied by the generated direction board.
