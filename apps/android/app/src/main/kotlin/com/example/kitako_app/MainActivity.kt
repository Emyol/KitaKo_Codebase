package com.example.kitako_app

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.os.Debug
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }

    override fun onDestroy() {
        try {
            application.unregisterComponentCallbacks(trimCallback)
        } catch (_: Throwable) {}
        super.onDestroy()
    }
    // ── BENCH END ───────────────────────────────────────────────────────────
}
