# Learning and offline behavior

The device saves a JSON snapshot atomically in its Documents directory with iOS file protection. Museum plaque photos are kept separately until research completes and never used as quiz imagery, so their text cannot reveal quiz answers. A validated research completion removes the plaque image while keeping its reviewed transcription; failed research retains it for retry. The reviewed on-device transcription is used as identification notes for research. Pairing tokens live in Keychain; backend credentials are never bundled. Do not uninstall before syncing: unsynced answers, car changes and photos are local-only.

## Quiz scheduling

Only published facts belonging to active cars are eligible. Flagged facts and removed cars are excluded. Due review facts are ordered by due date. New ideas are grouped into a single car chapter, with beginner fundamentals first. Lessons are untimed and use multiple-choice checks. Continue learning opens an exhibit checklist with all exhibits selected by default; users can select one or several exhibits, including unassigned cars where available. An empty selection or one with no eligible new ideas or due reviews cannot start a lesson. Study also offers individual car journeys. Any session explicitly finished after at least one answer counts toward a study day. Answers are persisted immediately; if the app is terminated before Finish, they remain in learning history but the unfinished session does not count toward the streak.

There is no countdown, deadline, or automatic time-based completion. Users tap Finish when ready. A wrong answer is due after one minute, and correct answers advance an exponential day interval capped at 30 days. Question choices shuffle per presentation. A finite lesson can include up to two due reviews followed by up to three new ideas from one car chapter; review-only lessons contain at most five questions. New ideas show their statement, explanation, photo and research links before their question. Chapters progress through Meet the car, The human story, then Under the skin where relevant sourced facts exist. A new fact revision has no inherited success interval; historical attempts remain tied to their original revision.

The shared grader retains case/diacritic/punctuation normalization and explicit accepted aliases for existing records. Numeric questions require a matching supplied unit and an explicit tolerance; vague semantic answers are not silently marked correct. The app presents selectable answer choices; selecting a choice records nothing until Check answer is tapped. The server recomputes correctness when syncing; the UI's local grading is provisional until synced.

Research seeks 3–5 distinct best-match representative photos. Each stored JPEG is at most 100 KiB; gallery bytes and credits sync with the library and persist offline. Questions for the same car cycle through that gallery independently of other cars. Your imported personal photo remains the fallback when no research gallery is available. Photo credit/license links appear with the image; fact citations are available on teaching and answer-feedback cards.

Photos can identify the car, so research is instructed not to ask identity questions that the photo/name would answer. Lesson feedback shows the answer, explanation and research links. New teaching cards also expose the supporting research before the check.

## Streaks and freezes

A study day is the Gregorian local date at session completion, stored with its IANA time zone. Multiple sessions on the same date count once. A missing past day uses a freeze only while a streak is active; at most three are used in each calendar month. Freezes do not add study days. A fourth uncovered missed day resets the streak. Today is never frozen before it ends. Remaining freezes reset monthly and do not accumulate. The streak is derived from stored completed sessions, so offline sessions count immediately and replay deterministically after sync.

Travel can create non-monotonic local dates; original recorded dates are retained. This is a personal learning aid, not an anti-cheating or authoritative time service.

## Sync and conflicts

Sync is manual, available in Settings → Offline study and sync → Sync library (and Garage → Sync). Research/review first uploads the current local library. Upload order is exhibits, cars, attempts, sessions, then reports, in batches of 100 per collection; the current remote snapshot is fetched afterwards. Edits made while a request is awaiting a response are retained by timestamp/ID merge and sent in a subsequent sync.

Car/exhibit conflicts use last updated timestamp; avoid editing the same car on two offline devices at the same time. Immutable attempt/session IDs make retries idempotent. The backend retains fact revisions so answers to an old revision can still sync. Reports keep suspect facts quarantined until a sourced correction or reaffirmation; unresolved provider calls do not return the fact to quizzes.

This first version uploads existing history again in bounded batches and receives full snapshots. It is intended for one personal library. Incremental sync cursors, background sync and account sharing are future work.

## Journey progress

Lessons use existing published, sourced, multiple-choice-usable facts. They exclude removed cars and flagged facts, continue an introduced car before starting another, and respect selected exhibits. A plan is fixed when the lesson opens so recording an answer does not change the remaining steps. Reading a card records no attempt and creates no study day. Each checked answer uses the existing persisted attempt format; Finish lesson or early Finish uses the existing completed-session format, so there is no backend schema migration.

Car familiarity is derived from attempts at current fact revisions: New means none attempted, Introduced means some attempted, Practicing means every eligible idea has an attempt, and Familiar requires every eligible idea to have correct retrievals on at least two separate local days with its latest answer correct. Immediate multiple-choice checks alone do not imply lasting recall. Lesson reading position is not persisted; interrupted lessons retain checked answers but restart from a newly planned lesson. Photos remain representative model-level images, not evidence of an exact exhibited variant.

Research now seeks two or three verifiable story facts for casual museum visitors, such as human experiences, cultural connections or surprising everyday context. The target is not a minimum quota. Existing cars need another research request after the backend update is deployed to receive that emphasis; existing story facts already work in the journey.

The lesson projection conservatively groups duplicate ideas within the same car and chapter, preferring the richer statement and carrying current-revision attempts across aliases only for planning. Exact question/statement matches require equivalent answers; identical substantive question topics can also match. Production-run questions additionally treat the same two years with and without month/day precision as one introductory idea. Different topics, dry/wet qualifiers and changed revisions stay separate. This does not delete or rewrite source facts or persisted answers.
