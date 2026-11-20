import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// DEMO/REVIEW build — `ORA_DEMO_BUILD=true flutter build apk --release
// -t lib/main_demo.dart` produces a side-loadable "ORA Demo" APK with a
// distinct applicationId (installable next to the real app) signed with the
// debug key. The demo entrypoint never initializes Firebase, so the gms
// plugin is skipped and google-services.json is not required. Normal
// builds are byte-for-byte unaffected.
val oraDemoBuild = System.getenv("ORA_DEMO_BUILD")?.trim() == "true"

// google-services.json is gitignored client config — never committed. The gms
// plugin only generates Firebase resources, so debug builds (e.g. CI) compile
// without it; release builds still fail closed in afterEvaluate below.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists() && !oraDemoBuild) {
    apply(plugin = "com.google.gms.google-services")
}

// Production release identity — android/key.properties (gitignored) or ORA_ANDROID_KEY_PROPERTIES_FILE.
val keystorePropertiesFile = System.getenv("ORA_ANDROID_KEY_PROPERTIES_FILE")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?.let { file(it) }
    ?: rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties()
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

android {
    namespace = "com.ora.ora"
    compileSdk = flutter.compileSdkVersion
    // maplibre_gl 0.27.x pins NDK 28.2; keep highest for plugin compatibility (PoC dep).
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (oraDemoBuild) "com.ora.ora.demo" else "com.ora.ora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName + if (oraDemoBuild) "-demo" else ""
        resValue(
            "string",
            "app_name",
            if (oraDemoBuild) "ORA Demo" else "ORA",
        )

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
            if (oraDemoBuild) {
                // Review artifact — signed with the debug key, never the
                // production upload keystore.
                signingConfig = signingConfigs.getByName("debug")
            } else if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
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
            if (oraDemoBuild) {
                return@doFirst
            }
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(releaseKeystoreMessage)
            }
            if (!googleServicesFile.exists()) {
                throw GradleException(
                    "Release build requires android/app/google-services.json " +
                        "for Firebase. It is gitignored client config — supply " +
                        "it locally before building release artifacts.",
                )
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
