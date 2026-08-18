# SabiBom Production AdMob Setup

SabiBom uses Google Mobile Ads with the Google User Messaging Platform (UMP). The app requests updated consent information on every launch, presents any required message before requesting ads, initializes Mobile Ads only when `canRequestAds()` is true, and exposes **Privacy Choices** in the More screen when UMP requires a publisher-rendered entry point.

## Release application ID

Android release builds require the production AdMob application ID through the Gradle property `SABIBOM_ADMOB_APP_ID`. The build intentionally fails if this property is missing or still contains Google's sample application ID.

Store the value outside source control in either `android/gradle.properties` or the user-level Gradle file at `~/.gradle/gradle.properties`:

```properties
SABIBOM_ADMOB_APP_ID=ca-app-pub-<publisher-id>~<app-id>
```

The Android manifest receives this value through the `sabibomAdmobAppId` placeholder. Debug builds continue to use Google's sample application ID when no property is configured.

## Production banner unit

The production Android banner unit is read from Firestore document `platform_settings/public`:

```json
{
  "ads": {
    "mobile": {
      "enabled": true,
      "androidBannerUnitId": "ca-app-pub-<publisher-id>/<banner-unit-id>"
    }
  }
}
```

Debug builds always use Google's sample banner unit. Release builds never substitute a test banner unit; an absent production banner ID keeps ads hidden.

## Consent and privacy message

The European regulations message must remain published in AdMob **Privacy & messaging** for the Android app whose package is `com.sabibom.app`. When AdMob reports that a privacy options entry point is required, SabiBom shows **More → Support → Privacy Choices** and opens the UMP privacy-options form.

## Release verification

Before uploading an Android App Bundle, verify that the production property is available to Gradle and build with:

```text
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Then inspect the bundle metadata and confirm that the manifest contains the production AdMob application ID rather than `ca-app-pub-3940256099942544~3347511713`. Also confirm the bundle uses package `com.sabibom.app`, version name `1.0.0`, and version code `2`.
