package com.hermesagent.hermes_android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class HermesEngineTest {
    private val manifestJson = """
        {
          "version": "local-1",
          "url": "https://example.com/runtime.tar.gz",
          "sha256": "${"a".repeat(64)}",
          "sizeBytes": 1234,
          "hermesVersion": "0.19.0",
          "pythonVersion": "3.12"
        }
    """.trimIndent()

    @Test
    fun parsesManifest() {
        val manifest = HermesEngine.parseManifest(manifestJson)
        assertEquals("local-1", manifest.version)
        assertEquals(1234L, manifest.sizeBytes)
        assertEquals("0.19.0", manifest.hermesVersion)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsInsecureManifestUrl() {
        HermesEngine.parseManifest(manifestJson.replace("https://", "http://"))
    }

    @Test
    fun rejectsEscapingTarEntries() {
        assertFalse(HermesEngine.isSafeEntry("../evil"))
        assertFalse(HermesEngine.isSafeEntry("/absolute"))
        assertFalse(HermesEngine.isSafeEntry("runtime/../../evil"))
        assertTrue(HermesEngine.isSafeEntry("runtime/bin/proot"))
        assertFalse(HermesEngine.isSafeEntry("link", "/etc/passwd"))
    }

    @Test
    fun buildsLoopbackProotEnvironment() {
        val prefix = File("/data/user/0/app/files/hermes-runtime")
        val data = File("/data/user/0/app/files/hermes-data")
        val env = HermesEngine.buildEnv(prefix, data, "secret", 8642)
        assertEquals("127.0.0.1", env["API_SERVER_HOST"])
        assertEquals("8642", env["API_SERVER_PORT"])
        assertEquals("secret", env["API_SERVER_KEY"])
        assertTrue(env["PROOT_LOADER"]!!.endsWith("/libexec/proot/loader"))
        assertTrue(env["PROOT_TMP_DIR"]!!.endsWith("/hermes-data/tmp"))
    }

    @Test
    fun gatewayRunsLauncherInsideRootfs() {
        val args = HermesEngine.gatewayArgs(File("/runtime"), File("/data"))
        assertEquals("-R", args[0])
        assertEquals("/runtime/rootfs", args[1])
        assertEquals("/usr/local/bin/hermes-start.sh", args.last())
    }
}
