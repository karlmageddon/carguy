# Learning and offline behavior

The device saves a JSON snapshot atomically in its Documents directory with iOS file protection. Pairing tokens live in Keychain; backend credentials are never bundled. Do not uninstall before syncing: unsynced answers, car changes and photos are local-only.

## Quiz scheduling

Only published facts belonging to active cars are eligible. Flagged facts and removed cars are excluded. Due facts are ordered by due date; never-seen facts come first. A session targets 5, 10, 15, 20, 25 or 30 minutes and can finish early. Any session explicitly finished after at least one answer counts toward a study day. Answers are persisted immediately; if the app is terminated before Finish, they remain in learning history but the unfinished session does not count toward the streak.

The timer uses a wall-clock deadline, so backgrounding does not pause the target. On returning, an expired deadline completes the session. A wrong answer is due after one minute, and correct answers advance an exponential day interval capped at 30 days. Question choices shuffle per presentation. A new fact revision has no inherited success interval; historical attempts remain tied to their original revision.

Typed recall uses case/diacritic/punctuation normalization and explicit accepted aliases. Numeric questions require a matching supplied unit and an explicit tolerance; vague semantic answers are not silently marked correct. Multiple-choice and typed responses share grading rules. The server recomputes correctness when syncing; the UI's local grading is provisional until synced.

Photos can identify the car, so research is instructed not to ask identity questions that the photo/name would answer. Quiz feedback gives the correct short answer; statements, explanations, research links and citations are in fact details outside the quiz.

## Streaks and freezes

A study day is the Gregorian local date at session completion, stored with its IANA time zone. Multiple sessions on the same date count once. A missing past day uses a freeze only while a streak is active; at most three are used in each calendar month. Freezes do not add study days. A fourth uncovered missed day resets the streak. Today is never frozen before it ends. Remaining freezes reset monthly and do not accumulate. The streak is derived from stored completed sessions, so offline sessions count immediately and replay deterministically after sync.

Travel can create non-monotonic local dates; original recorded dates are retained. This is a personal learning aid, not an anti-cheating or authoritative time service.

## Sync and conflicts

Sync is manual. Research/review first uploads the current local library. Upload order is exhibits, cars, attempts, sessions, then reports, in batches of 100 per collection; the current remote snapshot is fetched afterwards. Edits made while a request is awaiting a response are retained by timestamp/ID merge and sent in a subsequent sync.

Car/exhibit conflicts use last updated timestamp; avoid editing the same car on two offline devices at the same time. Immutable attempt/session IDs make retries idempotent. The backend retains fact revisions so answers to an old revision can still sync. Reports keep suspect facts quarantined until a sourced correction or reaffirmation; unresolved provider calls do not return the fact to quizzes.

This first version uploads existing history again in bounded batches and receives full snapshots. It is intended for one personal library. Incremental sync cursors, background sync, account sharing and automatic remote photo caching are future work.
