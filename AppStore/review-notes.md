# App Review — information requested, 13 September 2026

Apple asked for more information because the developer account has a limited review history. Send the text below as the reply in App Store Connect, **and** paste it into **App Review Information → Notes** on each version page, as Apple asked. Attach the screen recording(s) to the reply.

## Reply / Notes text

1. SCREEN RECORDING
Attached, recorded on a physical device running the latest operating system. It starts by launching the app and shows the typical flow: adding tasks, ticking one off, undoing, the All tasks screen, a task's history, and Settings. Needs Doing has no account registration, login or account deletion, no user-generated content visible to other people, and no paid content or In-App Purchases.

2. PURPOSE AND AUDIENCE
Needs Doing is a list for household chores that recur: the bins every Monday, watering the plants every few days, changing the sheets every couple of weeks. Ordinary to-do apps are built around deadlines, so recurring chores either clutter them or get forgotten. Needs Doing instead ranks tasks by how far past due they are relative to how often they happen, so a daily job a day late ranks alongside a monthly job a month late. It is for anyone who keeps a home running and wants one calm list of what needs doing next.

3. HOW TO USE IT
No login, credentials or sample files are needed. The app opens with an empty list.
- Tap + to add a task. Enter a title and choose When: Today, By a date, At some point, On a schedule (for example every week on Monday), or Roughly every… (counted from when it was last done).
- The To do tab shows only tasks that are due or nearly due, grouped as Due soon, Due, Late and Overdue. A task that is not due yet is not shown on To do; the app confirms when it will appear, and every task is always listed on the All tasks tab.
- To see a task on To do straight away, choose Today, or choose Roughly every… and set Last done to a few days ago.
- Tap the circle beside a task to mark it done; an Undo banner appears briefly. Swipe right to mark done, or swipe left to skip a repeating task this time.
- Tap a task to edit it, see its history (swipe an entry to undo it), pause it or delete it.
- Settings (the gear on iPhone; Needs Doing > Settings… on Mac) controls the optional daily digest notification and its time, and shows iCloud sync status.
- Widgets: To do and Next up, for the Home Screen, Lock Screen and Mac desktop.
- If the device is signed into iCloud, the list syncs automatically between the user's own iPhone and Mac. Without iCloud the app works fully, keeping the list on the device.

4. EXTERNAL SERVICES
Only Apple frameworks and services:
- iCloud (CloudKit), using the user's own private database, to sync the list across their own devices.
- Apple Push Notification service, used by CloudKit to tell the app about changes from the user's other devices.
- Local notifications, scheduled on the device, for the optional daily digest.
- WidgetKit, for the widgets.
There are no third-party services or SDKs, no servers operated by the developer, no analytics, advertising, AI services, authentication services or payment processors.

5. REGIONAL DIFFERENCES
None. The app functions the same in all regions. The interface is in English; dates, times and weekday names follow the device's own regional settings.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app does not operate in a regulated industry and contains no protected third-party material.

## Screen recording — shot list

Apple wants it to begin with launching the app, on a physical device, on the latest OS. Aim for one to two minutes, no sound needed.

**iPhone** — add Screen Recording to Control Centre if it isn't there (Settings → Control Centre), start recording from the Home Screen, then:
1. Tap the Needs Doing icon to launch it.
2. **+** → "Water the plants", When: **Roughly every…** 3 days, Last done a few days ago → Add. It appears on To do.
3. **+** → "Clean the oven", When: **Roughly every…** 3 months, Last done today → Add. Show the confirmation of when it will appear — it is not on To do yet, which is the point to demonstrate.
4. Tap the circle on "Water the plants" to tick it off; tap **Undo** on the banner; tick it again.
5. Swipe a task to show Done / Skip.
6. **All tasks** tab — both tasks listed, including the oven. Tap one: show History and the Pause / Delete options, then Cancel.
7. Gear → Settings: the Daily digest toggle and time, and the iCloud status. Done.
8. Optional: go to the Home Screen and show a widget.

**Mac** — ⌘⇧5 → Record Entire Screen, then launch Needs Doing from the Dock or Launchpad and repeat the same flow, using **⌘N** for a new task and **Needs Doing → Settings…** (⌘,) for Settings.

Use a clean list rather than your real one, or delete the demo tasks afterwards — the recording is only seen by Apple, but it's a cleaner demo.
