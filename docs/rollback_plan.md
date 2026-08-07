# Rollback Plan

1. Pause store / closed rollout (manual).
2. Disable or gate failing server endpoints via Vercel redeploy of last known good.
3. Feature-flag style: hide incomplete features in UI (EOD/backup already not advertised).
4. Firestore rules: redeploy previous rules revision if a rules bug ships.
5. Client: ship hotfix build with incremented version; do not force wipe user data.
6. Communicate known issue to beta testers.

Do not force-push destructive data migrations without backup evidence.
