package com.kitako.app

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Debug
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    // ── BENCH START ─────────────────────────────────────────────────────────
    // Cumulative trim-memory counters. Reset never; the bench takes
    // before/after snapshots and computes per-query deltas itself.
    private var trimCount: Int = 0
    private var trimMaxLevel: Int = 0

    private val trimCallback = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
            trimCount += 1
            if (level > trimMaxLevel) trimMaxLevel = level
        }

        override fun onConfigurationChanged(newConfig: Configuration) {}
        override fun onLowMemory() {
            trimCount += 1
            // TRIM_COMPLETE = 80 — treat onLowMemory at least that severe
            if (trimMaxLevel < ComponentCallbacks2.TRIM_MEMORY_COMPLETE) {
                trimMaxLevel = ComponentCallbacks2.TRIM_MEMORY_COMPLETE
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        application.registerComponentCallbacks(trimCallback)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kitako_app/bench")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPssBytes" -> {
                        val info = Debug.MemoryInfo()
                        Debug.getMemoryInfo(info)
                        // totalPss is in KB → convert to bytes
                        val pssBytes: Long = info.totalPss.toLong() * 1024L
                        result.success(pssBytes)
                    }
                    "getTrimStats" -> {
                        result.success(
                            mapOf(
                                "count" to trimCount,
                                "maxLevel" to trimMaxLevel,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Install-time asset-pack model extraction ────────────────────────
        // Models ship in the ":models_pack" install-time Play Asset Delivery
        // pack. install-time packs are fused into the app's AssetManager, so
        // their files are reachable via assets.open("models/<name>") on first
        // launch with no runtime network. We stream each model to a caller-
        // supplied destination path (the Flutter app documents directory) so
        // large files never cross the method channel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kitako_app/models")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyAsset" -> {
                        val assetPath = call.argument<String>("assetPath")
                        val destPath = call.argument<String>("destPath")
                        if (assetPath == null || destPath == null) {
                            result.error("ARG", "assetPath and destPath required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            assets.open(assetPath).use { input ->
                                File(destPath).outputStream().use { output ->
                                    input.copyTo(output, 1024 * 1024)
                                }
                            }
                            result.success(true)
                        } catch (e: Throwable) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        try {
            application.unregisterComponentCallbacks(trimCallback)
        } catch (_: Throwable) {}
        super.onDestroy()
    }
    // ── BENCH END ───────────────────────────────────────────────────────────
}
