package com.hermesagent.hermes_android

import android.system.Os
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.util.zip.GZIPInputStream

/** Minimal USTAR reader for the runtime bundle. Keeps the extraction root safe. */
object HermesTar {
    private const val BLOCK = 512

    /** @param onProgress receives (bytesExtracted, -1) because tar has no central size. */
    fun extract(archive: File, destination: File, onProgress: ((Long, Long) -> Unit)? = null) {
        destination.mkdirs()
        GZIPInputStream(FileInputStream(archive)).use { input -> extractStream(input, destination, onProgress) }
    }

    private fun extractStream(input: InputStream, destination: File, onProgress: ((Long, Long) -> Unit)?) {
        val header = ByteArray(BLOCK)
        val root = destination.canonicalFile
        val rootPrefix = root.absolutePath + File.separator
        var totalBytes = 0L
        while (true) {
            if (!readFully(input, header)) break
            if (header.all { it == 0.toByte() }) break

            val rawName = parseString(header, 0, 100)
            val prefix = parseString(header, 345, 155)
            val name = if (prefix.isEmpty()) rawName else "$prefix/$rawName"
            val size = parseOctal(header, 124, 12)
            val mode = parseOctal(header, 100, 8)
            val executable = (mode and 0b111111111L) != 0L
            val typeFlag = header[156].toInt().toChar()

            if (!HermesEngine.isSafeEntry(name)) {
                throw IllegalArgumentException("Unsafe archive entry: $name")
            }
            val target = File(destination, name).canonicalFile
            if (target != root && !target.absolutePath.startsWith(rootPrefix)) {
                throw IllegalArgumentException("Archive entry escapes root: $name")
            }

            when (typeFlag) {
                '0', '7', '\u0000' -> {
                    target.parentFile?.mkdirs()
                    FileOutputStream(target).use { out ->
                        var remaining = size
                        val buffer = ByteArray(16 * 1024)
                        while (remaining > 0) {
                            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                            if (read < 0) throw IllegalArgumentException("Truncated archive: $name")
                            out.write(buffer, 0, read)
                            remaining -= read
                            totalBytes += read
                            onProgress?.invoke(totalBytes, -1L)
                        }
                    }
                    if (executable) target.setExecutable(true, false)
                    val padding = (BLOCK - (size % BLOCK).toInt()) % BLOCK
                    if (padding > 0) skipExactly(input, padding.toLong())
                }
                '5' -> {
                    target.mkdirs()
                    if (executable) target.setExecutable(true, false)
                }
                '2' -> {
                    // Recreate symlinks with a safe, root-relative target. The
                    // builder must NOT dereference: rootfs links such as
                    // /usr/bin/X11 -> . otherwise recurse forever.
                    val linkName = parseString(header, 157, 100)
                    HermesEngine.safeSymlinkTarget(root, target, linkName)?.let { safeTarget ->
                        target.parentFile?.mkdirs()
                        target.delete()
                        Os.symlink(safeTarget, target.absolutePath)
                    }
                }
                else -> {
                    val padding = (BLOCK - (size % BLOCK).toInt()) % BLOCK
                    skipExactly(input, size + padding)
                }
            }
        }
    }

    private fun readFully(input: InputStream, buffer: ByteArray): Boolean {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            if (read < 0) {
                if (offset == 0) return false
                throw IllegalArgumentException("Truncated tar header")
            }
            offset += read
        }
        return true
    }

    private fun skipExactly(input: InputStream, count: Long) {
        var remaining = count
        val buffer = ByteArray(16 * 1024)
        while (remaining > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) throw IllegalArgumentException("Truncated archive")
            remaining -= read
        }
    }

    private fun parseString(header: ByteArray, offset: Int, length: Int): String {
        var end = offset
        val limit = minOf(offset + length, header.size)
        while (end < limit && header[end] != 0.toByte()) end++
        return String(header, offset, end - offset, Charsets.UTF_8)
    }

    private fun parseOctal(header: ByteArray, offset: Int, length: Int): Long {
        val text = parseString(header, offset, length).trim().trim('\u0000')
        if (text.isEmpty()) return 0L
        return text.toLong(8)
    }
}
