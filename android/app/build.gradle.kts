plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "it.lucabusi.nota_spese"
    // 36: required by fase-4 plugins (image_picker, mlkit scanner, share_plus).
    compileSdk = 36
    // 28.2: required by mlkit/jni/integration_test plugins (backward compatible).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "it.lucabusi.nota_spese"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 33
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // [FIX R8] missing-class rules for ML Kit optional language models.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // [FIX] google_mlkit_text_recognition dichiara i modelli non-latini come
    // compileOnly: senza questa riga TextRecognitionScript.japanese fallisce a
    // runtime (scontrini JP → testo vuoto). Cf. MlkitOcrService.scriptFor.
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
