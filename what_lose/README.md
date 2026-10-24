# what_lose

A new Flutter project.

## Local data storage

Expenses, debts, income goals, and currency preferences are stored in a local
SQLite database. Existing data saved by earlier versions in
`SharedPreferences` is imported automatically the first time the database opens.
On Windows, Linux, and macOS the database is placed in the application's
user data directory; on Android and iOS it uses the platform database
directory. The web target retains `SharedPreferences` storage because native
SQLite plugins are not available there.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android APK from GitHub Actions

The `Build Android APK` workflow runs on pushes to `main` or `master`. You can
also start it from the repository's **Actions** tab using **Run workflow**. It
regenerates the missing Android platform files, builds a debug APK, and uploads
it as the `what-lose-android-debug-apk` artifact. Download the artifact from the
completed workflow run.
