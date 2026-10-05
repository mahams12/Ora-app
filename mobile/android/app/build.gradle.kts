import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Must follow com.android.application: it hooks the Android variants to
    // parse google-services.json.  Build fails with an explicit "File
    // google-services.json is missing" until that file is supplied.
    id("com.google.gms.google-services")
}

// Production release identity — credentials live in android/key.properties (gitignored).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ora.ora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ora.ora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("key.properties missing keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("key.properties missing keyPassword")
                storeFile = file(
                    keystoreProperties.getProperty("storeFile")
                        ?: error("key.properties missing storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("key.properties missing storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Fail closed for release artifacts only — not during debug configuration.
afterEvaluate {
    val releaseKeystoreMessage =
        "Release build requires android/key.properties with a production keystore. " +
            "Copy key.properties.example and provision an authorized upload keystore. " +
            "Debug signing is not permitted for release artifacts."
    tasks.matching { task ->
        val name = task.name
        name.endsWith("Release") &&
            (name.startsWith("assemble") ||
                name.startsWith("bundle") ||
                name.startsWith("install"))
    }.configureEach {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(releaseKeystoreMessage)
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
