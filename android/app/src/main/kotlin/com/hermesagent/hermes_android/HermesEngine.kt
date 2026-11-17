package com.hermesagent.hermes_android

import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Pure helpers for the embedded Hermes runtime. No Android framework types are
 * used here so the parsing and safety rules can be unit-tested on the JVM.
 */
object HermesEngine {
    const val DEFAULT_PORT = 8642
    const val MANIFEST_ASSET = "hermes/runtime-manifest.json"
    const val METHOD_CHANNEL = "com.hermesagent.hermes_android/hermes_engine"
    const val EVENT_CHANNEL = "com.hermesagent.hermes_android/hermes_engine_events"

    data class Manifest(
        val version: String,
        val url: String,
        val sha256: String,
        val sizeBytes: Long,
        val hermesVersion: String,
        val pythonVersion: String,
    ) {
        init {
            require(version.isNotBlank()) { "version is required" }
            require(url.startsWith("https://")) { "runtime URL must be https" }
            require(sha256.matches(Regex("[0-9a-fA-F]{64}"))) { "sha256 must be 64 hex chars" }
            require(sizeBytes >= 0) { "sizeBytes must be non-negative" }
        }
    }

    fun parseManifest(raw: String): Manifest {
        val json = JSONObject(raw)
        return Manifest(
            version = json.getString("version"),
            url = json.getString("url"),
            sha256 = json.getString("sha256"),
            sizeBytes = json.optLong("sizeBytes", 0L),
            hermesVersion = json.optString("hermesVersion", ""),
            pythonVersion = json.optString("pythonVersion", ""),
        )
    }

    /** Reject tar entries that could escape the extraction root. */
    fun isSafeEntry(name: String): Boolean {
        if (name.isEmpty() || name.contains('\u0000')) return false
        if (name.startsWith("/") || name.startsWith("\\")) return false
        if (Regex("^[A-Za-z]:").containsMatchIn(name)) return false
        val segments = name.split('/')
        if (segments.any { it == ".." }) return false
        return true
    }

    /**
     * Resolve a tar symlink target to a path relative to the link's parent.
     * Absolute targets are interpreted inside the extracted root, matching
     * proot's chroot. Targets that leave the root (or point at the host Termux
     * prefix) are rejected. Null means the link must be skipped.
     */
    fun safeSymlinkTarget(root: File, link: File, raw: String): String? {
        if (raw.isEmpty() || raw.contains('\u0000')) return null
        if (raw.startsWith("/data/data/") || raw.startsWith("\\\\")) return null
        if (Regex("^[A-Za-z]:").containsMatchIn(raw)) return null

        val resolved = try {
            if (raw.startsWith("/")) {
                // Absolute targets are rootfs-absolute (the launcher chroots
                // into <prefix>/rootfs), not prefix-absolute.
                File(File(root, "rootfs"), raw.trimStart('/')).canonicalFile
            } else {
                File(link.parentFile, raw).canonicalFile
            }
        } catch (_: Exception) {
            return null
        }
        val rootPath = root.canonicalFile.absolutePath
        if (resolved.absolutePath != rootPath &&
            !resolved.absolutePath.startsWith(rootPath + File.separator)
        ) return null

        return relativePath(link.parentFile?.canonicalFile ?: root.canonicalFile, resolved)
    }

    private fun relativePath(from: File, to: File): String {
        val fromParts = from.absolutePath.split(File.separatorChar)
        val toParts = to.absolutePath.split(File.separatorChar)
        var common = 0
        while (common < fromParts.size && common < toParts.size && fromParts[common] == toParts[common]) {
            common++
        }
        val parts = List(fromParts.size - common) { ".." } + toParts.drop(common)
        return if (parts.isEmpty()) "." else parts.joinToString(File.separator)
    }

    fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun generateApiKey(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Environment for the proot process itself. proot is a relocatable ELF:
     * its own libraries live next to the bundle and its loader/tmp paths are
     * supplied explicitly so no Termux installation is needed.
     */
    fun buildEnv(prefix: File, dataDir: File, apiKey: String, port: Int = DEFAULT_PORT): Map<String, String> {
        val lib = File(prefix, "lib").absolutePath
        val libexec = File(prefix, "libexec/proot").absolutePath
        val tmp = File(dataDir, "tmp").absolutePath
        return mapOf(
            "PROOT_LOADER" to "$libexec/loader",
            "PROOT_LOADER_32" to "$libexec/loader32",
            "PROOT_TMP_DIR" to tmp,
            "PROOT_DONT_POLLUTE_ROOTFS" to "1",
            "LD_LIBRARY_PATH" to lib,
            "PATH" to "/system/bin:/system/xbin",
            "HERMES_DATA_DIR" to dataDir.absolutePath,
            "API_SERVER_ENABLED" to "true",
            "API_SERVER_HOST" to "127.0.0.1",
            "API_SERVER_PORT" to port.toString(),
            "API_SERVER_KEY" to apiKey,
            "API_SERVER_CORS_ORIGINS" to "",
        )
    }

    /** Run the launcher inside the bundled Ubuntu rootfs via proot. */
    fun gatewayArgs(prefix: File, dataDir: File): List<String> = listOf(
        "-R", File(prefix, "rootfs").absolutePath,
        "-b", "${dataDir.absolutePath}:/data",
        "-b", "/dev:/dev",
        "-b", "/proc:/proc",
        "-b", "/sys:/sys",
        "-w", "/data",
        "/usr/local/bin/hermes-start.sh",
    )
}
