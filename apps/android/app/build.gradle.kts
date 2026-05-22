plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.kitako_app"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.kitako_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
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

// ---------------------------------------------------------------------------
// Test dataset helpers — push/clear personal_1k images on the device.
//
// Target path: internal storage → DCIM → personal_1k
//   /sdcard/DCIM/personal_1k/
//
// The folder is visible in the Android Files app and Gallery and can be
// deleted there at any time. MediaStore is rescanned after each operation
// so changes appear in the gallery immediately without a reboot.
//
// Usage:
//   ./gradlew pushTestImages   — push missing images (skips existing)
//   ./gradlew clearTestImages  — delete the folder and rescan gallery
// ---------------------------------------------------------------------------
tasks.register("pushTestImages") {
    description = "Push personal_1k test images to /sdcard/DCIM/personal_1k/ on connected device"
    group = "kitako"

    doLast {
        val imagesDir = file("../../../test_datasets/personal_1k")
        if (!imagesDir.exists()) {
            logger.warn("pushTestImages: test_datasets/personal_1k not found at ${imagesDir.absolutePath}")
            return@doLast
        }

        val supportedExts = setOf("jpg", "jpeg", "png", "gif", "bmp", "webp")
        val imageFiles = imagesDir.listFiles()
            ?.filter { it.isFile && it.extension.lowercase() in supportedExts }
            ?: emptyList()

        if (imageFiles.isEmpty()) {
            logger.warn("pushTestImages: No image files found in ${imagesDir.absolutePath}")
            return@doLast
        }

        val adb = android.adbExecutable.absolutePath
        val remoteDir = "/sdcard/DCIM/personal_1k"

        // Ensure the target directory exists on the device
        ProcessBuilder(adb, "shell", "mkdir", "-p", remoteDir)
            .inheritIO().start().waitFor()

        var pushed = 0
        var skipped = 0
        for (imgFile in imageFiles) {
            val remotePath = "$remoteDir/${imgFile.name}"
            val check = ProcessBuilder(adb, "shell", "ls", remotePath)
                .redirectErrorStream(true).start()
            check.inputStream.readBytes()
            if (check.waitFor() == 0) {
                skipped++
                continue
            }
            logger.lifecycle("pushTestImages: Pushing ${imgFile.name}...")
            ProcessBuilder(adb, "push", imgFile.absolutePath, remotePath)
                .inheritIO().start().waitFor()
            pushed++
        }

        logger.lifecycle("pushTestImages: Pushed $pushed image(s), skipped $skipped (already present)")

        // Rescan so the folder appears as an album in the gallery right away
        if (pushed > 0) {
            logger.lifecycle("pushTestImages: Triggering MediaStore scan...")
            ProcessBuilder(adb, "shell", "cmd", "media", "scan", remoteDir)
                .inheritIO().start().waitFor()
        }

        logger.lifecycle("pushTestImages: Done — images at $remoteDir")
    }
}

tasks.register("clearTestImages") {
    description = "Remove /sdcard/DCIM/personal_1k/ from the connected device and rescan gallery"
    group = "kitako"

    doLast {
        val adb = android.adbExecutable.absolutePath
        val remoteDir = "/sdcard/DCIM/personal_1k"

        logger.lifecycle("clearTestImages: Removing $remoteDir...")
        ProcessBuilder(adb, "shell", "rm", "-rf", remoteDir)
            .inheritIO().start().waitFor()

        // Rescan the parent so MediaStore removes the stale album entries
        logger.lifecycle("clearTestImages: Triggering MediaStore rescan...")
        ProcessBuilder(adb, "shell", "cmd", "media", "scan", "/sdcard/DCIM")
            .inheritIO().start().waitFor()

        logger.lifecycle("clearTestImages: Done")
    }
}
