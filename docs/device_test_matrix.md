# Device Test Matrix

| Device | Android | Screen | RAM | Build | Workflows | Bugs | Result |
|--------|---------|--------|-----|-------|-----------|------|--------|
| Emulator / local | API varies | Medium | — | 0.1.0+1 | Compile + unit tests (financial + EOD calculator) | — | Code validated; UI pending device |
| Physical phone | — | Small/Medium | — | 0.1.0+1 | Sale, EOD finalize, backup export, weekly report, feedback screenshot | — | Pending |
| Large text | — | — | — | — | Accessibility | — | Pending |
| Dark mode | — | — | — | — | Major screens | — | Pending |
| Notifications denied | — | — | — | — | FCM register | — | Pending |
| Slow network | — | — | — | — | Sale + Sabi + Pinata feedback | — | Pending |

Release APK: run `flutter build apk --release` on a clean machine and record SHA/size here before Stage 1 distribution.

Focus on devices common for small businesses in Sierra Leone / West Africa.
