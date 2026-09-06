import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is provided via android/key.properties (created by CI from
// secrets, or locally by the developer). Falls back to debug signing.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.ahmadre.hinata"
    compileSdk = flutter.compileSdkVersion
    // Pin NDK r28+: it links native libraries with a 16 KB max-page-size by
    // default, which Google Play requires for apps targeting Android 15+.
    // Falls back to Flutter's bundled NDK (also r28 on Flutter 3.44) if newer.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ahmadre.hinata"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The locales worth keeping resources for — the ones this app can
        // actually speak. This is a filter, not a declaration: the app
        // translates itself at runtime from assets/i18n, so it brings no
        // Android string resources of its own, and what would otherwise ship is
        // every locale AndroidX and the plugins happen to carry. Dropping those
        // keeps a Portuguese reader on English system strings rather than a
        // half-Portuguese app, which is what the UI does anyway.
        //
        // Note this does NOT drive the language list on a Play listing — Play
        // has no such field, and shows the languages the *store listing* is
        // translated into. Same set as I18n.supportedLocales;
        // store_languages_test.dart guards the pair.
        resourceConfigurations += listOf(
            "en", "de", "zh", "hi", "es", "ja", "fr", "ru", "ar",
        )
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // 16 KB page-size support (required by Google Play for Android 15+):
    // ship native libraries uncompressed so the packager zip-aligns them to
    // 16 KB. AGP 8.5.1+ then aligns to the 16 KB boundary automatically.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}
