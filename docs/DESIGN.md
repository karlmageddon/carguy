# Rally design

Garage and quizzes use rounded cards, sunshine yellow actions, warm ivory backgrounds (with system dark backgrounds), and a cartoon Michèle Mouton rally guide. Garage retains exhibit filters, removed-car history, plaque import, manual entry, and sync. Study is the first tab and default landing page. Its quick-start card uses the existing due-fact queue, with five minutes selected initially and configurable duration, quiz style, and exhibit below it. Garage has no study CTA.

Multiple-choice quizzes now let you select or change an answer before tapping **Check answer**. Selection alone records nothing. Checking uses the existing answer persistence and scheduling logic. Typed recall, reporting, session completion, offline photos, per-car photo rotation, and photo attribution remain available. Quiz progress shows elapsed session time and the number of recorded answers, rather than implying a fixed question count.

## Guide artwork

Asset: `ios/Carguy/Assets.xcassets/RallyGuide.imageset/guide.png`.
Generated with the built-in image-generation tool, using the approved yellow character sheet as a visual reference. Generation prompt:

> Create one production app asset based on the supplied character sheet: ONLY the friendly curly dark-haired female rally guide in the white, golden yellow and charcoal suit, waist-up welcoming pose smiling and waving one hand. Match the sheet's simplified cartoon character identity. Flat rounded shapes, large readable facial features, simplified curls and minimal shading. Center the whole character with a little padding, no cropping of hair or waving hand. Transparent background, no text, no floor, no props, no extra poses or extra characters. This will appear on a small yellow welcome card in the Carguy iPhone app.

The implementation reuses the welcoming pose for coaching and completion. The Study welcome places her beside the heading without overlap, with the full waving hand visible. Concept sheets and screen explorations are indexed in [the Michèle reference folder](design/michele/README.md). Additional celebration/retry poses remain future design work.

## Simulator verification — 2026-10-27

- Built and installed on the paired iPhone 16 Pro simulator, iOS 18.6.
- All 19 iOS unit tests passed. Final navigation adjustment also built successfully.
- Inspected Garage with the existing eight-car library, saved thumbnails, guide artwork, and warm yellow styling.
- Verified car detail navigation exposes Back and Edit.
- Verified selecting a quiz choice leaves the answer count at zero; checking records one correct answer and displays coaching feedback. This adds one local study answer; no API sync was performed for this design review.
- Verified the final quiz action remains pinned above the bottom safe area, and finishing a zero-answer preview reports that it does not count toward the streak.
- Photo credits remain accessible through the quiz disclosure. Existing offline and sync behavior was preserved, but a new offline/API round trip was not part of this visual review.

## Study landing update — 2026-10-27

Option A moves the welcome guide and primary Start quiz action to Study. The existing simplified RallyGuide asset is unchanged. Study defaults to five minutes and multiple choice; the settings retain 5–30 minute sessions, typed recall, and exhibit filtering. Offline copy accurately describes manual sync. Simulator testing confirms Study opens first, Garage has no study CTA, and Start quiz opens the quiz. All 19 iOS tests pass.

## Guide idle animation

`RallyGuide` uses a subtle 4.2-second breathing cycle and a 160 ms blink every 7.3 seconds. Only the eye region switches frames. Outer curl masks sway independently on a 5.8-second cycle, rotating up to 0.9 degrees on the left and 0.7 degrees in the opposite direction on the right. The face and outfit remain registered; breathing adds a small overall stretch anchored at the bottom. Animation pauses while the scene is inactive and is disabled by the iOS Reduce Motion setting. The guide remains decorative and does not intercept touches.

Blink asset: `ios/Carguy/Assets.xcassets/RallyGuideBlink.imageset/blink.png`. Generated with the built-in image-generation tool using the original guide as the edit target. Prompt:

> Precise localized edit for animation: preserve this exact character image, exact framing, dimensions, pose, outlines, colors, mouth, hair, suit, hands and transparent background. Change ONLY the two eyes to naturally CLOSED eyelids mid-blink with thin curved dark lashes. Do not change eyebrows or cheeks. This is a blink frame to alternate with the original, so registration and all other pixels must match as closely as possible. No other changes.

The final hair-sway build was also inspected in the simulator. No API or credential changes are included in this design work.
