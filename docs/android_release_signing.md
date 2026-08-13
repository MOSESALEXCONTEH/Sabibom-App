# Android Upload Key Setup

The project refuses to use the debug key for release builds.

1. Generate a private upload key outside Git:

```powershell
keytool -genkeypair -v -keystore C:\secure\sabibom-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Copy `android/key.properties.example` to `android/key.properties` and enter the chosen values. Use either an absolute path or a path resolved from `android/app` for `storeFile`.
3. Back up the JKS and passwords in two secure locations. Do not store them in Git, chat, email, screenshots, or project documentation.
4. Build:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

5. Verify the bundle exists at `build/app/outputs/bundle/release/app-release.aab` and upload it first to Google Play Internal testing.
6. Enroll in Play App Signing. The upload key signs uploads; Google manages the app-signing key delivered to users.
7. Register Google Play's app-signing SHA-256 fingerprint with Firebase App Check and authentication providers after Play displays it.
