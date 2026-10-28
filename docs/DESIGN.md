# Rally design

Garage and quizzes use rounded cards, sunshine yellow actions, warm ivory backgrounds (with system dark backgrounds), and a cartoon Michèle Mouton rally guide. Garage retains exhibit filters, removed-car history, plaque import, manual entry, and sync. Study is the first tab and default landing page. Its quick-start card opens an exhibit checklist, with every exhibit selected by default. Quizzes are multiple choice with no timer or duration setting. Unassigned cars have their own checkbox. Garage has no study CTA.

Multiple-choice quizzes now let you select or change an answer before tapping **Check answer**. Selection alone records nothing. Checking uses the existing answer persistence and scheduling logic. Reporting, session completion, offline photos, per-car photo rotation, and photo attribution remain available. Quiz progress shows the number of recorded answers. Users finish whenever they choose.

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

Option A moves the welcome guide and primary Start quiz action to Study. The existing simplified RallyGuide asset is unchanged. The original duration and quiz-style settings were subsequently removed: quizzes are now untimed multiple choice, with exhibit selection after Start quiz. Offline copy accurately describes manual sync. Simulator testing confirms Study opens first, Garage has no study CTA, and Start quiz opens the quiz. All 19 iOS tests pass.

## Guide idle animation

`RallyGuide` uses a subtle 4.2-second breathing cycle and a 160 ms blink every 7.3 seconds. Only the eye region switches frames. Outer curl masks sway independently on a 5.8-second cycle, rotating up to 0.9 degrees on the left and 0.7 degrees in the opposite direction on the right. The face and outfit remain registered; breathing adds a small overall stretch anchored at the bottom. Animation pauses while the scene is inactive and is disabled by the iOS Reduce Motion setting. The guide remains decorative and does not intercept touches.

Blink asset: `ios/Carguy/Assets.xcassets/RallyGuideBlink.imageset/blink.png`. Generated with the built-in image-generation tool using the original guide as the edit target. Prompt:

> Precise localized edit for animation: preserve this exact character image, exact framing, dimensions, pose, outlines, colors, mouth, hair, suit, hands and transparent background. Change ONLY the two eyes to naturally CLOSED eyelids mid-blink with thin curved dark lashes. Do not change eyebrows or cheeks. This is a blink frame to alternate with the original, so registration and all other pixels must match as closely as possible. No other changes.

The final hair-sway build was also inspected in the simulator. No API or credential changes are included in this design work.

## Untimed quiz update

Removed the session-settings card and typed-recall UI. Start quiz now opens a checkbox sheet with All exhibits selected by default, individual exhibit rows, and Unassigned cars where applicable. Begin quiz is disabled for an empty selection or a selection with no due facts. Cancel does not start a quiz. Multiple selections filter the existing due-fact queue; removed cars remain excluded. The countdown, timer publisher, and deadline checks are removed.

Verified the checklist defaults, deselection disabling Begin quiz, and transition to an untimed multiple-choice quiz in the iPhone 16 Pro simulator. This library currently has only unassigned cars; multi-exhibit combinations and unassigned/removed-car filtering are covered by the new regression test. All 20 iOS tests passed. No study answers were added during this preview.

Offline-study information and the Sync library action now live in Settings under Offline study and sync. The duplicate pairing-section sync action was consolidated there. Study contains the quiz entry point and progress, without offline/sync controls. The updated simulator build succeeds.

Final verification: all 20 iOS tests passed for the untimed quiz and multi-exhibit queue changes; the subsequent relocation of offline/sync controls to Settings built successfully. These checks do not constitute a new API sync or offline round-trip verification.
