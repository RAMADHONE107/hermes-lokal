package com.hermesagent.hermes_android

import android.app.Application
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/** Owns the embedded runtime: download, unpack, supervise, log. */
class HermesEngineController private constructor(private val app: Application) {
    enum class State { ABSENT, DOWNLOADING, EXTRACTING, CONFIGURING, READY, RUNNING, STOPPING, ERROR }

    data class Status(
        val state: State,
        val progress: Int = 0,
        val message: String = "",
        val version: String? = null,
    )

    companion object {
        @Volatile
        private var instance: HermesEngineController? = null

        fun install(app: Application): HermesEngineController {
            val existing = instance
            if (existing != null) return existing
            synchronized(this) {
                return instance ?: HermesEngineController(app).also { instance = it }
            }
        }

        fun instance(): HermesEngineController =
            instance ?: error("HermesEngineController.install() has not been called")
    }

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "hermes-engine").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<(Status) -> Unit>()

    @Volatile
    private var status = Status(State.ABSENT)
    @Volatile
    private var process: Process? = null
    @Volatile
    private var wakeLock: PowerManager.WakeLock? = null
    private val logLock = Any()

    val runtimeDir: File get() = File(app.filesDir, "hermes-runtime")
    val dataDir: File get() = File(app.filesDir, "hermes-data")
    val logFile: File get() = File(app.filesDir, "hermes-engine.log")

    fun currentStatus(): Status = status

    fun addListener(listener: (Status) -> Unit) {
        listeners.add(listener)
        listener(status)
    }

    fun removeListener(listener: (Status) -> Unit) {
        listeners.remove(listener)
    }

    fun apiKey(): String {
        dataDir.mkdirs()
        val envFile = File(dataDir, ".env")
        if (envFile.exists()) {
            val existing = envFile.readLines().firstOrNull { it.startsWith("API_SERVER_KEY=") }
            val value = existing?.removePrefix("API_SERVER_KEY=")?.trim().orEmpty()
            if (value.isNotEmpty()) return value
        }
        val generated = HermesEngine.generateApiKey()
        writeEnv(generated, HermesEngine.DEFAULT_PORT)
        return generated
    }

    fun prepare() {
        executor.execute {
            try {
                val manifest = readManifest()
                val marker = File(runtimeDir, ".ready")
                if (marker.exists() && marker.readText().trim() == manifest.version) {
                    update(Status(State.READY, 100, "Runtime siap", manifest.version))
                    return@execute
                }
                stopProcessIfAny()
                update(Status(State.DOWNLOADING, 0, "Mengunduh runtime…", manifest.version))

                if (app.filesDir.usableSpace < manifest.sizeBytes * 2) {
                    throw IllegalStateException("Ruang penyimpanan tidak cukup")
                }
                val archive = File(app.cacheDir, "hermes-runtime-${manifest.version}.tar.gz")
                download(manifest, archive) { percent ->
                    update(Status(State.DOWNLOADING, percent, "Mengunduh runtime…", manifest.version))
                }
                val actual = HermesEngine.sha256Hex(archive)
                if (!actual.equals(manifest.sha256, ignoreCase = true)) {
                    archive.delete()
                    throw IllegalStateException("Checksum runtime tidak cocok")
                }

                update(Status(State.EXTRACTING, 0, "Mengekstrak runtime…", manifest.version))
                val staging = File(app.filesDir, "hermes-runtime-new")
                staging.deleteRecursively()
                HermesTar.extract(archive, staging) { extracted, _ ->
                    val percent = if (manifest.sizeBytes > 0) {
                        ((extracted * 100) / (manifest.sizeBytes * 3)).toInt().coerceIn(0, 99)
                    } else -1
                    if (percent >= 0) {
                        update(Status(State.EXTRACTING, percent, "Mengekstrak runtime…", manifest.version))
                    }
                }
                archive.delete()
                runtimeDir.deleteRecursively()
                if (!staging.renameTo(runtimeDir)) {
                    throw IllegalStateException("Gagal memasang runtime")
                }

                update(Status(State.CONFIGURING, 95, "Menyiapkan konfigurasi…", manifest.version))
                val key = apiKey()
                writeEnv(key, HermesEngine.DEFAULT_PORT)
                File(runtimeDir, ".ready").writeText(manifest.version)
                update(Status(State.READY, 100, "Runtime siap", manifest.version))
            } catch (error: Exception) {
                update(Status(State.ERROR, 0, error.message ?: "Gagal menyiapkan runtime", null))
            }
        }
    }

    fun start() {
        executor.execute {
            try {
                val manifest = readManifest()
                val marker = File(runtimeDir, ".ready")
                if (!marker.exists() || marker.readText().trim() != manifest.version) {
                    update(Status(State.ABSENT, 0, "Runtime belum disiapkan", manifest.version))
                    return@execute
                }
                if (process?.isAlive == true) {
                    update(Status(State.RUNNING, 100, "Mesin berjalan", manifest.version))
                    return@execute
                }
                update(Status(State.CONFIGURING, 50, "Menjalankan mesin…", manifest.version))
                dataDir.mkdirs()
                File(dataDir, "tmp").mkdirs()
                val proot = File(runtimeDir, "bin/proot")
                val launcher = File(runtimeDir, "rootfs/usr/local/bin/hermes-start.sh")
                if (!proot.exists() || !launcher.exists()) {
                    throw IllegalStateException("Runtime tidak lengkap")
                }

                val env = HermesEngine.buildEnv(runtimeDir, dataDir, apiKey())
                val builder = ProcessBuilder(listOf(proot.absolutePath) + HermesEngine.gatewayArgs(runtimeDir, dataDir))
                    .directory(dataDir)
                    .redirectErrorStream(true)
                builder.environment().clear()
                builder.environment().putAll(env)

                val child = builder.start()
                process = child
                acquireWakeLock()
                try {
                    startForeground()
                } catch (error: Exception) {
                    // OEM background-start restrictions can refuse the FGS.
                    // The process still runs while the app is foreground;
                    // reconnect-on-resume remains the fallback.
                    appendLog("foreground service refused: ${error.message}")
                }
                appendLog("--- hermes gateway started ---")
                Thread({
                    child.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line -> appendLog(line) }
                    }
                }, "hermes-engine-log").apply { isDaemon = true }.start()

                update(Status(State.RUNNING, 100, "Mesin berjalan", manifest.version))
                Thread({
                    val code = child.waitFor()
                    if (process === child) {
                        process = null
                        releaseWakeLock()
                        val message = if (code == 0) "Mesin berhenti" else "Mesin berhenti (kode $code)"
                        update(Status(State.READY, 100, message, manifest.version))
                    }
                }, "hermes-engine-monitor").apply { isDaemon = true }.start()
            } catch (error: Exception) {
                releaseWakeLock()
                update(Status(State.ERROR, 0, error.message ?: "Gagal menjalankan mesin", null))
            }
        }
    }

    fun stop() {
        executor.execute {
            update(Status(State.STOPPING, 0, "Menghentikan mesin…", null))
            stopProcessIfAny()
            update(Status(State.READY, 100, "Mesin dihentikan", null))
        }
    }

    fun stopForNotification() {
        stop()
        app.stopService(Intent(app, HermesEngineService::class.java))
    }

    fun logTail(maxLines: Int = 200): String = synchronized(logLock) {
        if (!logFile.exists()) return@synchronized ""
        logFile.readLines().takeLast(maxLines).joinToString("\n")
    }

    private fun stopProcessIfAny() {
        val child = process ?: return
        try {
            child.destroy()
            if (!child.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) child.destroyForcibly()
        } catch (_: Exception) {
            child.destroyForcibly()
        }
        process = null
        releaseWakeLock()
    }

    private fun readManifest(): HermesEngine.Manifest {
        val raw = app.assets.open(HermesEngine.MANIFEST_ASSET).bufferedReader().use { it.readText() }
        return HermesEngine.parseManifest(raw)
    }

    private fun download(manifest: HermesEngine.Manifest, target: File, onProgress: (Int) -> Unit) {
        val connection = URL(manifest.url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 20_000
        connection.readTimeout = 30_000
        try {
            connection.connect()
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException("Unduh gagal (HTTP $code)")
            val length = connection.contentLengthLong
            target.parentFile?.mkdirs()
            FileOutputStream(target).use { out ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    var lastPercent = -1
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        out.write(buffer, 0, read)
                        total += read
                        if (length > 0) {
                            val percent = ((total * 100) / length).toInt().coerceIn(0, 100)
                            if (percent != lastPercent) {
                                lastPercent = percent
                                onProgress(percent)
                            }
                        }
                    }
                    out.flush()
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun writeEnv(apiKey: String, port: Int) {
        dataDir.mkdirs()
        val file = File(dataDir, ".env")
        val kept = if (file.exists()) {
            file.readLines().filterNot { line ->
                line.trim().startsWith("API_SERVER_") || line.trim().startsWith("HERMES_HOME=")
            }
        } else emptyList()
        val lines = kept + listOf(
            "HERMES_HOME=${dataDir.absolutePath}",
            "API_SERVER_ENABLED=true",
            "API_SERVER_HOST=127.0.0.1",
            "API_SERVER_PORT=$port",
            "API_SERVER_KEY=$apiKey",
        )
        file.writeText(lines.joinToString("\n") + "\n")
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val manager = app.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hermes:engine").apply { acquire() }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun startForeground() {
        val intent = Intent(app, HermesEngineService::class.java)
        app.startForegroundService(intent)
    }

    private fun appendLog(line: String) = synchronized(logLock) {
        FileOutputStream(logFile, true).use { out ->
            out.write((line + "\n").toByteArray(Charsets.UTF_8))
        }
        if (logFile.length() > 2L * 1024 * 1024) {
            val kept = logFile.readLines().takeLast(500).joinToString("\n") + "\n"
            logFile.writeText(kept)
        }
    }

    private fun update(next: Status) {
        status = next
        mainHandler.post { listeners.forEach { it(next) } }
    }
}
