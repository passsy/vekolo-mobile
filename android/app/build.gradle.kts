plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.vekolo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "cc.vekolo.beta"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("dev") {
            keyAlias = "key0"
            keyPassword = "phntmrockz"
            storeFile = file("play.jks")
            storePassword = "phntmrockz"
        }
        create("play-upload") {
            keyAlias = System.getenv("ANDROID_PLAY_KEY_ALIAS") ?: "key0"
            keyPassword = System.getenv("ANDROID_PLAY_KEY_PASSWORD") ?: ""
            storeFile = file(System.getenv("ANDROID_PLAY_KEYSTORE") ?: "play.jks")
            storePassword = System.getenv("ANDROID_PLAY_STORE_PASSWORD") ?: ""
        }
        create("ad-hoc") {
            keyAlias = System.getenv("ANDROID_ADHOC_KEY_ALIAS") ?: "key0"
            keyPassword = System.getenv("ANDROID_ADHOC_KEY_PASSWORD") ?: ""
            storeFile = file(System.getenv("ANDROID_ADHOC_KEYSTORE") ?: "adhoc.jks")
            storePassword = System.getenv("ANDROID_ADHOC_STORE_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            // begin: release signingConfig
            signingConfig = signingConfigs.getByName("dev")
            // end: release signingConfig
        }
    }
}

flutter {
    source = "../.."
}
