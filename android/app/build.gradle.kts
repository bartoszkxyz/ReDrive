plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.redrive"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.redrive"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "OBDrive"
    }

    flavorDimensions += "default"

    productFlavors {
        create("headunit") {
            dimension = "default"
            applicationIdSuffix = ".headunit"
            manifestPlaceholders["appLabel"] = "OBDrive Headunit"
        }
        create("phone") {
            dimension = "default"
            applicationIdSuffix = ".phone"
            manifestPlaceholders["appLabel"] = "OBDrive Companion"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

tasks.matching { it.name.matches(Regex("assemble.*Release")) }.configureEach {
    doLast {
        val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
        if (!flutterApkDir.exists()) {
            flutterApkDir.mkdirs()
        }
        val flavors = listOf("headunit", "phone")
        for (flavor in flavors) {
            val gradleFlavorDir = layout.buildDirectory.dir("outputs/apk/$flavor/release").get().asFile
            val gradleSrc = File(gradleFlavorDir, "app-$flavor-release.apk")
            val flutterSrc = File(flutterApkDir, "app-$flavor-release.apk")
            val src = if (gradleSrc.exists()) gradleSrc else flutterSrc
            if (src.exists()) {
                val obdriveDest = File(flutterApkDir, "obdrive-$flavor-v${flutter.versionName}+${flutter.versionCode}-release.apk")
                src.copyTo(obdriveDest, overwrite = true)
                val redriveDest = File(flutterApkDir, "redrive-$flavor-v${flutter.versionName}+${flutter.versionCode}-release.apk")
                src.copyTo(redriveDest, overwrite = true)
                logger.lifecycle("✓ Generated versioned release APK: ${obdriveDest.name} (${obdriveDest.length()} bytes)")
            }
        }
        val gradleApkDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
        val gradleSrc = File(gradleApkDir, "app-release.apk")
        val fallbackSrc = File(flutterApkDir, "app-release.apk")
        val src = if (gradleSrc.exists()) gradleSrc else fallbackSrc
        if (src.exists()) {
            val obdriveDest = File(flutterApkDir, "obdrive-v${flutter.versionName}+${flutter.versionCode}-release.apk")
            src.copyTo(obdriveDest, overwrite = true)
            val redriveDest = File(flutterApkDir, "redrive-v${flutter.versionName}+${flutter.versionCode}-release.apk")
            src.copyTo(redriveDest, overwrite = true)
            logger.lifecycle("✓ Generated versioned release APK: ${obdriveDest.name} (${obdriveDest.length()} bytes)")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
