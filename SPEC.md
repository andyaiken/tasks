# Shared Recurring Task List — Draft Spec v0.10

## Changes since v0.9

- **Scheduling fixes (§4, §5, §6).** A one-off due today, or already overdue when created, now shows up straight away. A fixed task's first occurrence now has a defined cycle start. Under *skip*, a late completion no longer counts for the next occurrence. A fixed task with several missed occurrences now shows as due, not overdue. Occurrences before a task was created are ignored. Urgency bands have exact boundaries.
- **Calendar dates are stored as dates, not moments (§3, §4).** `anchorDate` and `createdOn` are stored as `YYYY-MM-DD`, and every log entry records its own `day`, set by the device that recorded it. This settles the household time-zone question (§12.2).
- **Deleting a task is a log entry (§3)**, so it syncs cleanly and can be undone.
- **Solo use (§8, §9).** A list nobody else has joined shows one unsectioned list with unassigned tasks treated as yours, so solo users and App Review see a sensible screen and still get a digest.
- **Local-only identity (§3, §7).** Local-only users get a local ID that is rewritten once when their list moves to iCloud.
- **Sharing details (§7, §8).** Participants are read-write. The share sheet hides the public-link option. Matching now has a fallback if non-owners can't see invite details. Phone normalisation uses a library.
- **Digest threshold (§9):** Due or worse.
- **Persistence route decided (§11):** CKSyncEngine over a plain local store.
- **New open decisions (§13):** what happens when a second list would appear.
- **"At some point" one-offs (§3, §4):** a one-off with no due date, which the app treats as due four weeks after it was added and never shows a date for.
- **Creating a task in plain words (§4)**, and an **All tasks screen (§8)** so tasks that aren't due yet can still be found and edited.

## 1. Problem

Existing to-do apps assume tasks have deadlines. Mine mostly have rhythms. The bin goes out weekly, the plants get watered every three days, the boiler gets serviced annually. What I need to know each morning is not "what is due today" but "what has gone longest past when it should have been done".

A few things are genuinely one-off — book the chimney sweep, renew the passport — and they belong on the same list, ranked the same way, rather than in a second app.

Secondary requirement: my household needs to see the same list, so that a task done by one person counts as done for everyone.

## 2. Scope

**In scope (v1)**

- Create a task with a title and a repeat rhythm, or a one-off with or without a due date
- A single prioritised "what needs doing" view showing everyone's tasks, with your own first
- An All tasks screen listing every task, due or not, for finding and editing
- Mark done; next occurrence reschedules automatically
- Skip an occurrence, pause a task, undo a mistaken tick, delete a task (and undo that)
- Sync your list across your own iPhone and Mac through iCloud
- Share a list with other people; completions sync
- Assign tasks to named people, and give each person their own daily digest
- A fully usable local-only mode for anyone not signed into iCloud
- iPhone and Mac (not iPad), shipped publicly on the App Store

**Out of scope (v1)**

- Subtasks, projects, dependencies
- Points, streaks, rewards, leaderboards
- Calendar/EventKit integration
- Android, web, or any non-Apple participant — permanently, not just for v1
- Automatic rotation of assignees (see §10)

## 3. Core model

A **calendar date** is a year, month and day with no time and no time zone, stored as a `YYYY-MM-DD` string. CloudKit has no date-only type, and a CloudKit date field is a moment, which different time zones read as different days.

### Task

| Field | Notes |
|---|---|
| id | UUID |
| title | |
| notes | optional |
| createdOn | calendar date — the day (§4) on the device that created the task |
| interval | count + unit (days / weeks / months / years). Empty for a one-off |
| anchorMode | floating or fixed — see §4. Ignored for one-offs |
| anchorDate | calendar date. Start of the schedule for fixed; first cycle start for floating (so "last done" in the UI); the due date for a one-off. Defaults to creation day. Ignored for "at some point" one-offs |
| someday | true for an "at some point" one-off, which has no due date (§4). Ignored for repeating tasks |
| backlogPolicy | skip / debt, fixed tasks only — see §6 |
| assigneeId | optional participant ref — see §8 |
| listId | |

### Log entry

| Field | Notes |
|---|---|
| id | UUID |
| taskId | |
| kind | done / skipped / paused / resumed / deleted / retracted |
| at | timestamp — when it was recorded |
| day | calendar date — the day (§4) the entry belongs to, set once by the recording device |
| by | user ref — the real user record ID, never a placeholder (§8) |
| retracts | entry id, for retracted only |
| note | optional |

- **done** — the task was done; satisfies one occurrence.
- **skipped** — satisfies one occurrence without claiming the work ("no bin this week, we're away"). Scheduling treats it like done; the history stays honest.
- **paused / resumed** — for seasonal tasks. A paused task is hidden from every view and digest. Resuming starts a fresh cycle (§4), so a task paused all winter doesn't come back red. Whichever of the two is latest decides.
- **deleted** — the task is gone from every view. Retracting it brings the task back with its history.
- **retracted** — undo. The referenced entry is ignored from then on. A retraction can't itself be retracted; to redo, log the thing again.

Entries are ordered by `day`, then `at`, then `id`. Everything that says "latest" means latest in that order.

**Design rule:** the log is append-only. nextDue, paused state and deleted state are worked out from it, never stored. This is the single decision that makes sync painless — two devices that both append entries merge cleanly, whereas two devices that both mutate a nextDue field conflict.

Editing a task's interval or anchorMode reinterprets its whole history — switching weekly to daily can turn a task red instantly. That is accepted behaviour, not a bug.

**Local-only identity.** Someone not signed into iCloud has no user record ID, so `by` holds a local ID generated on first launch. When the list moves to iCloud (§7), every `by` equal to that local ID is rewritten to the real user record ID before anything is uploaded. This is a one-off migration of data no other device has seen, so it doesn't break the append-only rule.

## 4. Scheduling

Resolution is one day. Every date below is a calendar date, not a moment, so nothing is due "at 18:00", and DST can't push a due date across a day boundary.

A day runs from 04:00 to 04:00, in the local time zone of the device doing the work. A log entry recorded at 01:00 on Wednesday belongs to Tuesday, so ticking off the washing-up after midnight still counts for the evening it was meant for. The recording device works this out once and stores it in the entry's `day`; other devices never recompute it. "Today" in §5 means the viewer's current 04:00-to-04:00 day.

Three kinds of task. In all of them, only done and skipped entries that haven't been retracted count.

**floating** (default for repeating tasks) — `nextDue = cycleStart + interval`. `cycleStart` is the latest of `anchorDate`, the day of the latest done/skipped entry, and the day of the latest resumed entry. Lateness pushes everything back. Correct for plants, cleaning, haircuts. Setting `anchorDate` in the past means "last done then", so a new task can start out due.

**fixed** — occurrences fall at `anchorDate + k × interval` for any whole number k, always computed from the anchor, never from the previous due date. Correct for bin day, rent, anything tied to the outside world.

- Only occurrences on or after the **floor** count, where the floor is the later of `createdOn` and the day of the latest resumed entry. So anchoring a weekly bin to a date a year ago, to get the weekday right, doesn't create a year of backlog, and a resume forgets the occurrences it paused through.
- Only entries on or after the day of the latest resumed entry count.
- `cycleStart` is the occurrence before nextDue, which for the first occurrence is `anchorDate − interval`. A fixed task created on its own anchor day is therefore Due that day.

**One-off** — no interval. Due on `anchorDate`. The first counting entry completes it for good: it leaves every view and never recurs. Retracting that entry brings it back. `cycleStart = min(floor, anchorDate − 1 day)`, with the floor defined as for fixed. This makes a one-off due today Due today, and one added after its due date shows as late straight away.

**"At some point" one-off** (`someday`) — a one-off with no due date. It is treated as due four weeks after the floor: `cycleStart = floor`, `nextDue = floor + 4 weeks`. So it appears as Due soon after about three weeks, becomes Due at four, and Overdue at eight: it can't be forgotten, but it doesn't nag on day one. Because it counts from the floor, pausing and resuming restarts the four weeks. The app never shows this date anywhere; it's only a ranking device. Giving the task a real due date later just clears `someday`.

### In the UI

The create screen asks in plain words and never says "floating" or "fixed":

| The user says | Stored as |
|---|---|
| "Today" | one-off, `anchorDate` = today |
| "By …" (a date) | one-off, `anchorDate` = that date |
| "At some point" | one-off, `someday` |
| "Every week on Monday" (or every *n* days / weeks / months / years from a date) | fixed, `anchorDate` = the chosen weekday or date |
| "Roughly every two weeks" (counted from when it's done) | floating |

Backlog policy (§6) is an advanced option on fixed tasks, defaulting to skip.

Computing from the anchor matters for months: from 31 January, adding a month each time drifts (Jan 31 → Feb 28 → Mar 28); counting from the anchor doesn't (Jan 31 → Feb 28 → Mar 31). A month or year that lands on a day the target month doesn't have is clamped to its last day (29 February + 1 year = 28 February).

For fixed tasks, which occurrence an entry satisfies, and which occurrence is nextDue, depend on the backlog policy (§6).

A further variant worth considering later: fixed patterns that aren't intervals ("first Monday of the month", "every Tuesday").

## 5. Urgency

Rank by how far through its cycle a task is, not by absolute days late:

```
staleness = (today − cycleStart) / max(1, nextDue − cycleStart)   // in days
```

- cycleStart is defined per kind of task in §4.
- Both ends are real calendar dates, so a month is however long that month actually is.

A daily task one day late scores 2.0, the same as a monthly task a month late, which matches how it actually feels. A one-off is ranked by how much of the time you gave yourself has gone: something due in a year appears about ten weeks ahead; something due next week appears a day or two ahead.

Bands for display. Each range includes its lower bound and excludes its upper one; values often land exactly on a boundary (a weekly task on its due day is exactly 1.0).

| staleness | band | colour |
|---|---|---|
| below 0.8 | Not yet | grey |
| 0.8 up to 1.0 | Due soon | blue |
| 1.0 up to 1.5 | Due | amber |
| 1.5 up to 2.0 | Late | orange |
| 2.0 and above | Overdue | red |

The main screen shows tasks with staleness ≥ 0.8, sorted by staleness descending within each section (§8), so colour and order always agree. On a solo list the tasks sit under band headings — Overdue, Late, Due, Due soon — in that order, and empty bands are left out; the heading replaces a per-row band label. Paused, deleted and completed tasks never appear. No date columns, no calendar.

## 6. The overdue question

This only arises for fixed tasks. A floating task can't miss an occurrence — lateness simply moves the next one back — and a one-off has only one.

If a weekly bin-day task hasn't been done for a month, what happens when I finally do it? Two defensible answers, so make it a per-task setting:

**skip** — missed occurrences are dropped. Default.

- An entry satisfies the latest occurrence on or before its day. The exception is the night before: if the next occurrence is the following day and the interval is at least two days, the entry satisfies that one, so putting the bin out on Monday evening counts for Tuesday. An entry before the first counting occurrence satisfies the first one.
- nextDue is the most recent occurrence on or before today, if it comes after the latest satisfied one. Otherwise it is the first occurrence after the latest satisfied one.
- So a bin missed for a month shows as Due (it's bin day, or bin day has just passed), not Overdue: the missed weeks aren't coming back. Staleness for a skip task stays below 2.0.

**debt** — every missed occurrence must be cleared individually. Each entry satisfies the oldest unsatisfied occurrence, and nextDue is that oldest one, so staleness keeps climbing until the backlog is paid. Only correct for things where each instance is a real obligation. Two people ticking the same occurrence pay off two; the second is retracted like any other mistaken tick.

Getting this wrong is the most common reason people abandon apps in this category: a month away turns into thirty checkboxes and the app gets deleted. For planned absences, skipped and paused (§3) are the release valve.

## 7. Sharing

CloudKit shared record zones. No backend to write, host, or bring into GDPR scope; free at this scale; works across iOS and macOS from one codebase. Every participant needs an iCloud account and an Apple device. Decided: that is permanent — non-Apple participants are never supported, so there is no cross-platform backend to plan for.

- One shareable list; tasks belong to a list.
- **Invite-only.** People are invited by email address or phone number, and the share's public permission is none, so it can't be joined by link. In the system share sheet, restrict the options to invited recipients only (`CKAllowedSharingOptions` with `.specifiedRecipientsOnly`, or `availablePermissions` on `UICloudSharingController`) so the public-link choice never appears. Contact matching depends on this (§8).
- **Participants are read-write.** Everyone completes tasks, so nobody is read-only.
- **The invited address must belong to the invitee's Apple Account.** As far as I know, a private share can only be accepted by the Apple Account that owns the address it was sent to. The invite screen should say so: "use the email or phone number they use for iCloud".
- Any participant can complete any task, assigned or not (see §8).
- Log entries carry `by`, so "who did what" is visible without building a scoring system.
- Conflict handling falls out of §3: union on the log, and last-writer-wins on task metadata, *per field*. If one person renames a task while another reassigns it, both changes survive.

**The owner is a single point of failure.** The shared zone lives in the owner's private database, and CloudKit cannot transfer ownership. If the owner stops sharing, deletes the app's data, or leaves iCloud, everyone else loses the list. Provide an export *and an import*: importing creates a new list owned by the importer, who can then share it. User record IDs are the same for everyone in the app's container, so an imported log keeps who did what. Say plainly in the UI who owns the list.

**Your own devices.** The list lives in a custom zone (`List`) in your private iCloud database, so every iPhone and Mac signed into your Apple Account shows the same list. Changes sync through CKSyncEngine, which is told about other devices' changes by silent push.

- **Merged automatically.** The first time a device syncs, it downloads what's already in iCloud and uploads whatever it has that iCloud doesn't. The log is a union, so nothing is lost; the same task added separately on two devices shows up twice, and one can be deleted. The first device to sync fixes the list's ID; later devices move their tasks onto it.
- **Signing out** of iCloud keeps the list on the device as a local list. Signing back in merges again.
- **A different Apple Account** on the device removes the previous account's list from it. That list is still in the previous account's iCloud.
- **Deleting Tasks' data from iCloud** (Settings → Apple Account → iCloud) deletes the list from every device, because that's what that setting promises. If the zone disappears for any other reason, devices upload their copies again.

**Local-only mode.** Someone not signed into iCloud still gets a working app with a local list. Signing in later moves that list into a custom zone (§11), rewriting the local ID (§3) on the way. App Review and first-time users will both hit this path, so it is a feature, not a fallback.

## 8. Assignment

People come from the share itself rather than from a separate contacts list: each accepted CKShare participant carries an identity with a stable user record ID and, usually, a name. assigneeId stores that ID.

### Names and pictures

There is no nickname override; everything comes from the participant's Apple Account identity or the viewer's own Contacts.

**Label**, in order of preference:

1. **Apple Account name** — the first name (the given name in their CKUserIdentity), or their full name if there's no first name.
2. **Contact name**, when the identity carries no name — the first name of the matching contact in the viewer's own Contacts (found as described below), or its full name if there's no first name.
3. **Monogram**, when neither source has a name — the first letter of the email address the share provides.
4. **"User"**, when there is nothing to build a monogram from.

If two participants end up with the same first name, from either source, add the initial of their family name ("Sam K.", "Sam T."), where there is one.

**Picture.** CloudKit doesn't expose the Apple Account photo or Memoji — CKUserIdentity carries a name but no image. Instead:

- If the viewer has granted Contacts access, look the participant up in the viewer's own Contacts. If the matching contact has a photo, show it. This is often the picture or Memoji the person shares through Messages.
- Otherwise, show no picture. No placeholder image.

### Matching a participant to a contact

In practice everyone in the household has everyone else in their Contacts, so a failed match is a bug, not an edge case. To make it reliable:

- **Invite by email or phone, never by link (§7).** An invited participant's identity carries the email address or phone number they were invited with, which is what matching uses. Someone who joined by link may carry nothing to match on.
- **Match on every email address and phone number on every contact**, not just the primary ones. The address someone was invited with may be a secondary one on their card, and §7 means it's whichever one is on their Apple Account, not necessarily the one the viewer thinks of as theirs.
- **Normalise before comparing.** Email addresses case-insensitively. Phone numbers to international format, using the device's region for numbers without a country code, so "07700 900123" and "+44 7700 900123" match. Apple has no public API for this; use PhoneNumberKit (a Swift port of Google's libphonenumber).
- **Don't rely on contactIdentifiers.** I believe it's filled in by user discovery, which Apple has deprecated. Use it if present, but never as the only route.
- **Re-match when anything changes** — when the viewer's Contacts change, and when the share's participants change. Cache the result per participant, locally.
- **Ask for full Contacts access.** With iOS's limited access the viewer picks which contacts the app can see; the purpose string should say that full access is what makes names and pictures work.

**Unverified: what other participants' identities carry.** The owner invited everyone, so the owner's device can see each invitation's email or phone. Whether a non-owner's device can see those details for the other participants is the thing I'm least sure of. Prototype it first (§12.3).

**Fallback if it can't: a participant directory.** The owner's device writes one record into the shared zone mapping each participant's user record ID to the email or phone they were invited with, and rewrites it when the participants change. Only the owner writes it, so it never conflicts. Every device matches against it rather than against the share. The data stays in the users' own iCloud, never reaches a server of mine, and so doesn't affect privacy labels (§12.5).

### Consequences

- **Contact-derived details are per viewer.** Two household members may see different pictures of the same person, or one sees a photo and the other doesn't. The same goes for a label taken from Contacts: one viewer may see "Sam" where another sees "S". Nothing from Contacts is synced.
- **Contacts access is optional.** Ask for it only when a participant list is first shown. Declining costs only the pictures and the contact-name fallback.
- **Only accepted participants are assignable.** Someone invited but not yet joined has no usable identity, so the assignee picker shows pending invitees greyed out.
- **People leave.** An assigneeId that doesn't match a current participant is treated as unassigned when read. It is never rewritten — rewriting would need some device to own the change, which reintroduces the conflicts §3 avoids. If the person rejoins, their assignments return.
- **Beware the owner placeholder.** CloudKit often refers to the current user as `CKCurrentUserDefaultName` (`__defaultOwner__`) rather than their real user record ID. Fetch the real ID and store only that in assigneeId and by, or the owner's identity will mean different things on different devices.

### Rules

- **Assignment is a property of the task, not of each occurrence.** Per-occurrence assignment is what rotation needs, and rotation is deferred.
- **Assignment is advisory, not a lock.** Anyone can complete anything; the log records who actually did it. An app that refuses a tick because the wrong person offered it will lose to a whiteboard.
- **One assignee per task.** Multiple assignees means either "both must do it" or "either may" — two different features wearing one field.
- **Everyone sees every task.** Assignment decides what comes first, not what's visible. Unassigned tasks in particular must stay visible to all — the alternative, unassigned means nobody's problem, is how tasks quietly rot.

### The main list

One list, two sections, no toggle:

- **Yours** — tasks assigned to you.
- **Everyone else's** — tasks assigned to other people, and unassigned tasks. Each row shows the assignee's label and, if there is one, their picture — or "Anyone".

Each section is in urgency order (§5). An urgent task of someone else's can sit below a less urgent one of yours; that is the point of putting yours first. Because everything is always visible, there's no need for a rule that surfaces someone else's overdue task after a threshold — it's already there, coloured red.

**All tasks.** The main list hides anything below Due soon, so a task disappears from it as soon as it's done, or just after it's created. A separate All tasks screen lists every task that isn't deleted or completed — including paused ones, marked as paused — alphabetically, with its rhythm in words ("every week on Monday", "at some point"). This is where tasks are found, edited, paused and deleted. A newly created task that isn't due yet shows a brief confirmation saying when it will appear ("You'll see this again in about three weeks").

**Solo lists.** While nobody else has accepted the share — including local-only mode and a list that was never shared — every task is yours. Show one list with no section headings, treat unassigned tasks as yours, and hide the assignment controls. Otherwise a solo user would see every task under "Everyone else's", marked "Anyone", and never get a digest (§9).

## 9. Notifications

Two mechanisms, and they are not the same thing:

### Daily digest — local, per device

"4 tasks for you today, 1 overdue." There is no server, so nothing in the cloud can send a scheduled message at 08:00. Each device schedules its own local notifications for its own user, computing the content from the synced data it already holds. Configurable time, per person.

- **Your own tasks only, Due or worse.** The digest lists tasks assigned to you with staleness ≥ 1.0 (§5); "overdue" counts the Overdue band. Unassigned tasks and other people's tasks never appear in it — they're visible in the app, but four people shouldn't all be told about the same four tasks every morning. On a solo list, unassigned tasks are yours (§8). A person with nothing assigned and due gets no digest.
- The digest time must be 04:00 or later, so it never describes a day that hasn't started (§4).
- **Schedule days ahead.** Urgency depends only on the date and synced data, so with no new changes the next 14 days' digests can all be computed now (iOS allows 64 pending local notifications). Settings shows the next few, so the user can see what's coming.
- **Shown even when the app is open** at digest time. A sync then corrects upcoming digests rather than creating them, so a missed background refresh means a slightly stale digest, not a missing one.
- **Re-compute on every sync**, driven by a background refresh task plus a silent CloudKit push on record change, to pick up changes like a task assigned at 07:00.
- **One digest device per person.** Someone with an iPhone and a Mac should get one digest, not two. Default to the phone; the Mac's digest is off unless turned on, and a Mac-only user is offered it during setup.

### Event alerts — silent push, local notification

"Priya assigned you: descale the kettle." The shared database only supports database-wide subscriptions, not query subscriptions (verify against current docs). A database subscription can't be filtered to "assigned to me" or put record fields into the alert text, and a visible alert would fire on every change anyone makes. So:

1. Subscribe with a silent push — the owner on their private database, participants on the shared database.
2. On wake, fetch changes.
3. If a task was newly assigned to me — its assignee is now me, wasn't before, and the change wasn't made by me — post a local notification. The name comes from the task record's `lastModifiedUserRecordID`.

This puts event alerts in the same reliability class as the digest: silent pushes are throttled and aren't delivered to a force-quit app. Keep them to assignment events only.

Per-task individual reminders stay opt-in, for hard-deadline items. Default to quiet — a chore app that pings constantly gets muted, and a muted app is a dead app.

**This is the point where a backend starts to look tempting.** Everything above works serverless, but it's fiddly, and "why didn't my 8am list arrive?" will be the most common bug. A tiny server that computes each person's digest and pushes it would be more robust. Not for v1 — but this is the seam where v2 might split. It would still be Apple-only (§7), but it would change the App Store privacy labels (§12.5).

## 10. Deliberately deferred

- **Automatic rotation.** Now the obvious next request, and the one that turns a tool into a system for negotiating fairness — a different product with different failure modes. It also forces assignment down to the occurrence level, which is a real model change. Wait until shared use proves it's needed.
- **Workload balance views.** "Who has done more" is a fight generator. The log makes it possible later if you decide you want it.
- **Statistics and streaks.** Streaks punish the exact situation (a bad week) that this app is meant to absorb gracefully.
- **Templates.** Useful, but only once the model is settled.

## 11. Implementation sketch

Urgency is computed at read time, so there is no scheduler, no background job, and no server-side state. Widgets and a Shortcuts action for "mark X done" are cheap on this stack and disproportionately improve daily use.

**On the Mac.** Settings live in the standard Tasks → Settings… window (⌘,) rather than behind a gear button, and File → New Task (⌘N) replaces File → New Window, since there's only one list. Closing the window quits the app; the digest still arrives because it's booked with the system in advance, and sync catches up at next launch. The iPhone keeps the gear button.

**The icon** is the "rhythm ring": five arcs in the band colours going clockwise from grey at 12 o'clock to red, on navy, with a white centre dot. `Tools/make-icon.swift` draws every size into the asset catalog — full-bleed squares for iPhone (plus a darker dark-mode variant, no alpha as the App Store requires) and the standard rounded-square grid for the Mac.

**The widgets.** A To do widget in small, medium and large sizes (iPhone home screen and Mac desktop) and a Lock Screen size (iPhone), showing the main list most urgent first with band colours. A Next up widget shows just the top of the main list — the one thing to do next — with its band, in a small size (iPhone and Mac) and two Lock Screen sizes (iPhone), including a single line above the clock. Tapping either opens the app. The list file lives in the App Group container (`group.com.andyaiken.tasks`) so the widget can read it; the app moves an older file there on first launch and asks the widget to refresh after every change. Urgency only changes at 04:00, so each timeline plans a week of days ahead. The widgets are read-only, and tapping one opens the app — decided. (Ticking from the widget was considered: a tick made there runs in the widget's process, which can't run sync, so it would need the app to pick up and upload such ticks later. Not worth it while a tap gets to the app.)

Keep the domain logic (scheduling, urgency, log interpretation, labels) free of CloudKit types, in its own Swift package (`TasksCore`). It's the easiest part to test in isolation, and the part with the most edge cases (§12.2).

**Persistence: CKSyncEngine over a plain local store.** SwiftData's CloudKit integration covers the private database only. NSPersistentCloudKitContainer supports the shared database but still leaves sharing to CKShare and the CloudKit operations API directly. The routes considered:

| Route | Cost |
|---|---|
| Core Data + NSPersistentCloudKitContainer + manual CKShare | Most trodden path; verbose but documented by example; hides the records, which §8 and §9 need (`lastModifiedUserRecordID`, zones, share participants) |
| **CKSyncEngine over a local store — chosen** | Most control, most code. Its usual cost, writing your own conflict handling, is small here because §3 makes the log conflict-free and task metadata merges per field |
| A third-party package (e.g. SwiftDataSync) | Keeps SwiftData; inherits someone else's abstraction and its bugs |

The local store is plain files: the data is small (tens of tasks, a few thousand log entries after years), so it's held in memory and saved as a whole. That keeps it easy to share with a widget through an app group and easy to export (§7). Minimum OS: iOS 18 and macOS 15 (CKSyncEngine needs 17/14; 18 gives the current Contacts limited-access APIs).

Constraints that leak into §3 regardless of route: records in the default zone cannot be shared — the list must live in a custom zone from day one. Retrofitting a zone later means migrating everyone's data.

**Schema changes are asymmetric.** Fields can be added to a deployed production schema, but their types can't be changed. Deferring a field costs almost nothing; getting a type wrong is permanent. That's why calendar dates are strings (§3).

**The schema.** Container `iCloud.com.andyaiken.tasks`, zone `List`. Record names are `chore.<UUID>`, `entry.<UUID>` and `list`, so a record's kind is clear from its ID alone; record kinds a version doesn't recognise are ignored, so later versions can add new ones.

| Record type | Field | Type |
|---|---|---|
| Chore | title, notes | String |
| | createdOn, anchorDate | String (`YYYY-MM-DD`) |
| | intervalCount | Int64 (0 for a one-off) |
| | intervalUnit, anchorMode, backlogPolicy | String |
| | someday | Int64 (0 / 1) |
| | assigneeID, listID | String |
| LogEntry | choreID, kind, day, by, retracts, note | String (`day` is `YYYY-MM-DD`) |
| | at | Date/Time |
| List | listID | String |

Log entries are saved once and never changed or deleted. Task records merge per field (§7): each device remembers which fields it changed and hasn't had confirmed, and those win when iCloud reports a newer copy.

Before the first App Store release, the schema has to be deployed from the development environment to production in the CloudKit Console.

## 12. Where the effort actually goes

The domain logic is a weekend. These are the things that aren't:

### 12.1 CloudKit sharing

Per above. Share acceptance handling, participant roles, revocation, owner identity, and moving a local-only list into iCloud when someone signs in. Budget weeks, not days.

### 12.2 Calendar arithmetic

Day-level resolution and a 04:00 day start remove the worst of it, and storing each entry's day as recorded (§3, §4) settles household members in different time zones: an entry belongs to the day of the person who recorded it, and each viewer's "today" is their own. What remains is "monthly" from the 31st (clamped, §4) and leap days. Each has a wrong answer that looks fine in testing, so the domain package tests them explicitly.

### 12.3 Testing

Sharing cannot be meaningfully tested with one Apple Account. Two accounts, two real devices, and a CloudKit schema that behaves differently in development and production — where field types can't be changed once deployed.

**Prototype contact matching before anything else.** It needs three accounts: an owner and two participants, all invited by email or phone. On each participant's device, check what the share reveals about the other participant — name, email, phone. Two accounts can't show this, because the only other person a participant sees is the owner. If the answer is "nothing", §8's participant directory is the fallback.

### 12.4 The digest's reliability

§9 depends on background refresh and silent push, both of which iOS grants at its own discretion. The failure mode is silent and intermittent, which is the worst kind to debug. Scheduling digests days ahead limits the damage.

### 12.5 Shipping to the App Store

Decided: a public release rather than quarterly TestFlight re-uploads. Developer Program enrolment is already in place. What remains:

- **App Review can't test sharing.** A reviewer has one account and one device. Include a short screen recording of the share flow in the review notes.
- **Local-only mode must stand on its own (§7).** Reviewers and strangers will open the app without iCloud; the solo list (§8) is what they'll see.
- **Privacy labels** should be close to "no data collected", as long as there is no backend of mine and no analytics. Reading Contacts (§8) doesn't change that, provided contact data never leaves the device. The participant directory (§8) lives in the users' own iCloud, so it doesn't either. A v2 backend (§9) would, and brings GDPR back into scope.
- **Contacts purpose string.** App Review checks that the permission prompt explains why the app wants Contacts.
- Screenshots, a support URL, and a privacy policy URL. The pages are in `docs/` for GitHub Pages: `https://andyaiken.github.io/tasks/support.html` and `…/privacy.html`, with andy.aiken@live.co.uk as the contact. The privacy policy must be updated before sharing ships, because sharing reads Contacts (§8).

None of this is hard in the sense of requiring cleverness. It's hard in the sense of being numerous, undocumented, and only discoverable by hitting it.

## 13. Open decisions

- **What happens when a second list would appear** from someone else: accepting a household share while you already have your own tasks, or importing an export (§7). Records can't move between databases, so keeping one list means copying tasks and their logs. *Recommendation:* a person has exactly one list at a time. Whenever a second would appear, offer to copy the tasks (with their history) from the list being left into the one being kept, then remove the old one. (Your own devices merge automatically — decided, §7.)
- **Band headings on a shared list (§5, §8).** Solo lists group by band. Once there are Yours / Everyone else's sections, either band headings go inside each section, or bands become the sections and each row shows its assignee.
- **Result of the contact-matching prototype (§12.3)** — decides whether the participant directory (§8) is needed.
- **Subscriptions on the shared database (§9)** — confirm against current docs that only database subscriptions are supported.

### Decided

- **Weight:** dropped; sort by staleness alone (§5). Can be added later as a new field at almost no cost (§11).
- **Day boundary:** 04:00 local time (§4). An entry's day is fixed by the device that records it (§3).
- **Visibility:** everyone sees every task, their own first (§8). Solo lists have one section (§8).
- **Granularity:** day-level (§4).
- **One-offs:** in scope, as tasks with no interval and a due date (§4).
- **"At some point" one-offs:** no due date; ranked as if due four weeks after being added, and the date is never shown (§4).
- **Non-Apple participants:** never (§7).
- **Digest contents:** your own tasks only, Due or worse (§9).
- **Participant labels:** Apple Account name (first, else full), else the viewer's contact name (first, else full), else monogram, else "User"; no nickname override (§8).
- **Participant pictures:** from the viewer's own Contacts if a match has a photo; otherwise none (§8).
- **Distribution:** public App Store release (§12.5).
- **Devices:** iPhone and Mac only; no iPad (§2).
- **Your own devices:** one list in your iCloud, merged automatically when a device first syncs (§7).
- **Main list grouping:** band headings on solo lists (§5).
- **Persistence:** CKSyncEngine over plain local files; iOS 18 / macOS 15 minimum (§11).
