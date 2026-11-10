package shewa.tech.store_update

import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import kotlin.test.Test
import kotlin.test.assertEquals

/** The names Dart parses (lib/src/models.dart, lib/src/method_channel_store_update.dart). */
internal class PlayMappingTest {
    @Test
    fun availabilityNames() {
        assertEquals("available", PlayMapping.availabilityName(UpdateAvailability.UPDATE_AVAILABLE))
        assertEquals(
            "in_progress",
            PlayMapping.availabilityName(UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS),
        )
        assertEquals("none", PlayMapping.availabilityName(UpdateAvailability.UPDATE_NOT_AVAILABLE))
        assertEquals("unknown", PlayMapping.availabilityName(UpdateAvailability.UNKNOWN))
        assertEquals("unknown", PlayMapping.availabilityName(99))
    }

    @Test
    fun installStatusNamesMatchDart() {
        val names = mapOf(
            InstallStatus.PENDING to "pending",
            InstallStatus.DOWNLOADING to "downloading",
            InstallStatus.DOWNLOADED to "downloaded",
            InstallStatus.INSTALLING to "installing",
            InstallStatus.INSTALLED to "installed",
            InstallStatus.FAILED to "failed",
            InstallStatus.CANCELED to "canceled",
            InstallStatus.UNKNOWN to "unknown",
        )
        names.forEach { (code, name) -> assertEquals(name, PlayMapping.statusName(code)) }
        assertEquals("unknown", PlayMapping.statusName(-42))
    }

    @Test
    fun flowResults() {
        assertEquals("accepted", PlayMapping.flowResultName(android.app.Activity.RESULT_OK))
        assertEquals("cancelled", PlayMapping.flowResultName(android.app.Activity.RESULT_CANCELED))
        assertEquals("failed", PlayMapping.flowResultName(1)) // RESULT_IN_APP_UPDATE_FAILED
    }
}
