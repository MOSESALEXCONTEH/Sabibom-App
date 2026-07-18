# SabiBom

## Authentication setup

Email/password and Google sign-in are configured in Firebase. Facebook sign-in needs a Meta App ID before it can be used:

1. Create or select a Meta app and add the Android package `com.sabibom.app`.
2. Add the Android key hashes used for debug and release builds in Meta's Facebook Login settings.
3. Replace `YOUR_FACEBOOK_APP_ID` in `android/app/src/main/res/values/facebook.xml` with the numeric Meta App ID. Do not add an app secret to the mobile app.
4. In Firebase Console, enable the Facebook provider and provide the Meta app ID and app secret there.
5. In Firebase Console, disable `Authentication -> Sign-in method -> Phone` because phone sign-in has been removed from the app.

Deploy the included Firestore rules with `firebase deploy --only firestore:rules` after reviewing them for your production roles.

## Dashboard data

The authenticated dashboard reads only the active member's business document and bounded business subcollections. Sales and expenses use a local reporting-period boundary against `createdAt`; activity is limited to five items; product and customer previews read at most 100 documents and show five entries. No composite Firestore index is required for the current queries.

For larger datasets, add a server-maintained aggregate at `businesses/{businessId}/analytics/daily_yyyyMMdd` with daily sales, expenses, order count, and item totals. The mobile dashboard is intentionally structured so that this aggregate can replace bounded client reads without changing the presentation layer.
# sabibom

A new Flutter project.
