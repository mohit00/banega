import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (FCM push): the google-services plugin turns app/google-services.json
// into resources. It is applied only when that file exists, so the app still
// builds without a Firebase project (push then stays off at runtime).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing: android/key.properties (not committed) with storeFile
// (relative to android/app/), storePassword, keyAlias, keyPassword.
// - Building an App Bundle (bundleRelease: what Play takes) without it fails.
// - A release APK without it falls back to the debug key with a warning
//   (local testing only; never distribute it).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException("android/key.properties is missing: ${missing.joinToString()}")
    }
}
val buildsBundle = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) && it.contains("Release", ignoreCase = true) }
if (buildsBundle && !hasReleaseKeystore) {
    throw GradleException(
        "Refusing to build a release App Bundle without android/key.properties: Play needs it signed " +
            "with the upload key (see app/README.md, Release signing)."
    )
}

android {
    namespace = "in.kornea.banega"
    // 36: package_info_plus (via sentry_flutter) needs it; Flutter's default is older.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.kornea.banega"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")).also {
                    if (!it.exists()) throw GradleException("Upload keystore not found: $it (key.properties storeFile)")
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties not found - the release build is signed with the DEBUG key. " +
                        "Do not upload it to Play."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
