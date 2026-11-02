# Additional guide poses

Generated on 2026-11-02 with the built-in image-generation tool. The approved simplified welcoming illustration was the reference, and both outputs have transparent backgrounds.

## Teaching

[Production asset](../../../ios/Carguy/Assets.xcassets/RallyGuideTeaching.imageset/guide.png)

Prompt:

> Use case: stylized-concept. Create ONE matching animation-ready app character asset, same simplified cartoon Michèle Mouton rally guide as reference. Preserve her identity: abundant rounded dark brown curls, friendly adult face, white golden yellow and charcoal Audi rally suit, flat shapes minimal shading. Waist-up pose of her EXPLAINING an interesting story: one hand raised in an open palm presenting gesture to her left, other hand resting at waist, warm curious expression, mouth smiling, open eyes. More variation from the waving reference, but same art style and costume. Whole hair and hands comfortably inside image, ample transparent padding, no cropping. Transparent background, single character only, no text, no speech bubble, no props or background. Face centered near horizontal .50, eyes near vertical .33 for animation alignment, composition centered and clean.

## Celebration

[Production asset](../../../ios/Carguy/Assets.xcassets/RallyGuideCelebrating.imageset/guide.png)

Prompt:

> Use case: stylized-concept. Create ONE matching animation-ready app character asset, same simplified cartoon Michèle Mouton rally guide as reference. Preserve her identity: abundant rounded dark brown curls, friendly adult face, white golden yellow and charcoal Audi rally suit, flat shapes minimal shading. Waist-up CELEBRATION pose: both arms bent with small fists raised enthusiastically, joyful eyes closed in cheerful curves, broad friendly smile. Same character and style, different pose. Whole curls and hands within canvas with ample transparent padding, no cropping. Transparent background, single character only, no text, no props, no background. Centered composition with face near horizontal .50 and vertical .33. No floor or shadow.

The SwiftUI guide uses separate hand/forearm masks for a mild gesture and the existing breathing animation. It keeps the original blink and hair masks specific to the welcome portrait so they cannot misalign with the new poses. Reduce Motion disables all movement. No skeleton rig or video asset is required.
