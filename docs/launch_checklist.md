# Launch Checklist

## Security
- [ ] App Check enabled (prod)
- [ ] Firestore rules deployed + tested
- [ ] Backend auth tested
- [ ] No secrets in Flutter
- [ ] Rate limits enabled
- [ ] Account deletion path documented

## Business logic
- [ ] Sales / stock / balances / profit accurate on device
- [ ] Duplicate prevention verified
- [ ] EOD accurate **or** not advertised (KI-001)
- [ ] Backup accurate **or** not advertised (KI-002)

## UX
- [ ] Onboarding + setup checklist
- [ ] Demo mode
- [ ] Help / feedback
- [ ] Empty / loading / error states
- [ ] Large text / small screens

## Operations
- [ ] Crash monitoring process noted
- [ ] Feedback monitoring
- [ ] Support contact
- [ ] Privacy / terms links

## Release
- [ ] Version bumped when ready
- [ ] Signed release APK/AAB installs
- [ ] No debug banner
- [ ] Store listing draft ready
- [ ] Screenshots from demo data only
- [ ] **Do not upload to Play Store in Phase 12**
