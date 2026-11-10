package shewa.tech.store_update

import android.app.Activity
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability

/** Names sent to Dart (lib/src/method_channel_store_update.dart) for Play's codes. */
internal object PlayMapping {
    fun availabilityName(availability: Int): String = when (availability) {
        UpdateAvailability.UPDATE_AVAILABLE -> "available"
        UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS -> "in_progress"
        UpdateAvailability.UPDATE_NOT_AVAILABLE -> "none"
        else -> "unknown"
    }

    fun statusName(status: Int): String = when (status) {
        InstallStatus.PENDING -> "pending"
        InstallStatus.DOWNLOADING -> "downloading"
        InstallStatus.DOWNLOADED -> "downloaded"
        InstallStatus.INSTALLING -> "installing"
        InstallStatus.INSTALLED -> "installed"
        InstallStatus.FAILED -> "failed"
        InstallStatus.CANCELED -> "canceled"
        else -> "unknown"
    }

    /** The result code of an update flow; anything but OK or CANCELED failed. */
    fun flowResultName(resultCode: Int): String = when (resultCode) {
        Activity.RESULT_OK -> "accepted"
        Activity.RESULT_CANCELED -> "cancelled"
        else -> "failed" // ActivityResult.RESULT_IN_APP_UPDATE_FAILED
    }
}
