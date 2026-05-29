import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config, loaded from android/key.properties (gitignored).
// If the file is absent (e.g. a fresh clone or CI without secrets), release
// builds fall back to the debug key so the project still compiles.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kitako.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.kitako.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real upload key when key.properties is present;
            // otherwise fall back to debug so the project still builds.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    // Install-time Play Asset Delivery pack holding the ONNX models.
    assetPacks += listOf(":models_pack")
}

flutter {
    source = "../.."
}

// ---------------------------------------------------------------------------
// Auto-push ONNX models to connected Android device during development.
//
// Looks for model files in <workspace>/models/ and pushes any that
// are missing from /data/local/tmp/ on the device. The app's
// copyModelsFromTmp() copies them to its private directory on first launch.
// ---------------------------------------------------------------------------
tasks.register("pushOnnxModels") {
    description = "Push ONNX model files to the connected Android device"
    group = "kitako"

    doLast {
        val modelsDir = file("../../../../models/kitako")
        if (!modelsDir.exists()) {
            logger.warn("pushOnnxModels: models/ not found at ${modelsDir.absolutePath}")
            return@doLast
        }

        val modelFiles = modelsDir.listFiles()?.filter { it.extension == "onnx" } ?: emptyList()
        if (modelFiles.isEmpty()) {
            logger.warn("pushOnnxModels: No .onnx files found in ${modelsDir.absolutePath}")
            return@doLast
        }

        val adb = android.adbExecutable.absolutePath

        for (modelFile in modelFiles) {
            val remotePath = "/data/local/tmp/${modelFile.name}"

            // Check if file already exists on device
            val checkProcess = ProcessBuilder(adb, "shell", "ls", remotePath)
                .redirectErrorStream(true)
                .start()
            checkProcess.inputStream.readBytes()
            val exitCode = checkProcess.waitFor()

            if (exitCode == 0) {
                logger.lifecycle("pushOnnxModels: ${modelFile.name} already on device, skipping")
                continue
            }

            logger.lifecycle("pushOnnxModels: Pushing ${modelFile.name} (${modelFile.length() / 1024 / 1024} MB)...")
            val pushProcess = ProcessBuilder(adb, "push", modelFile.absolutePath, remotePath)
                .inheritIO()
                .start()
            pushProcess.waitFor()
        }

        logger.lifecycle("pushOnnxModels: Done.")
    }
}

// Hook into the install task so models are pushed automatically on `flutter run`
tasks.configureEach {
    if (name.startsWith("install")) {
        finalizedBy("pushOnnxModels")
    }
}
