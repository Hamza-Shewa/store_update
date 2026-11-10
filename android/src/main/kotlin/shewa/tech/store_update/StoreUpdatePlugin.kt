package shewa.tech.store_update

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google Play In-App Updates for Dart (lib/src/method_channel_store_update.dart).
 *
 * `store_update`:
 * - `check` → map: availability (available | in_progress | none | unknown), versionCode,
 *   priority, stalenessDays, immediateAllowed, flexibleAllowed, installStatus, bytes, total.
 *   Fails with code "play" when Play can't answer (e.g. a build not installed from Play).
 * - `startImmediate` / `startFlexible` → "accepted" | "cancelled" | "failed".
 * - `completeFlexible` installs a downloaded flexible update; the app restarts.
 * - `openStore` → true when Google Play (or the web listing) opened.
 *
 * `store_update/progress` streams {status, bytes, total} while listened to.
 */
class StoreUpdatePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var channel: MethodChannel? = null
    private var progressChannel: EventChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var manager: AppUpdateManager? = null
    private var sink: EventChannel.EventSink? = null

    private val listener = InstallStateUpdatedListener { state ->
        sink?.success(
            mapOf(
                "status" to PlayMapping.statusName(state.installStatus()),
                "bytes" to state.bytesDownloaded(),
                "total" to state.totalBytesToDownload(),
            ),
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        manager = AppUpdateManagerFactory.create(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "store_update").also {
            it.setMethodCallHandler(this)
        }
        progressChannel = EventChannel(binding.binaryMessenger, "store_update/progress").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopListening()
        channel?.setMethodCallHandler(null)
        progressChannel?.setStreamHandler(null)
        channel = null
        progressChannel = null
        manager = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val manager = manager ?: return result.error("play", "Not attached", null)
        when (call.method) {
            "check" -> manager.appUpdateInfo
                .addOnSuccessListener { result.success(describe(it)) }
                .addOnFailureListener { e -> result.error("play", e.message, null) }
            "startImmediate" -> start(manager, AppUpdateType.IMMEDIATE, result)
            "startFlexible" -> start(manager, AppUpdateType.FLEXIBLE, result)
            "completeFlexible" -> manager.completeUpdate()
                .addOnSuccessListener { result.success(null) }
                .addOnFailureListener { e -> result.error("play", e.message, null) }
            "openStore" -> result.success(openStore())
            else -> result.notImplemented()
        }
    }

    /** Each flow needs a fresh AppUpdateInfo: one can start only one flow. */
    private fun start(manager: AppUpdateManager, type: Int, result: MethodChannel.Result) {
        if (activity == null) return result.success("failed")
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                // The current activity: it may have been recreated (e.g. rotated) meanwhile.
                val activity = activity
                val resuming =
                    info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                if (activity == null || (!resuming && !info.isUpdateTypeAllowed(type))) {
                    result.success("failed")
                    return@addOnSuccessListener
                }
                try {
                    manager.startUpdateFlow(info, activity, AppUpdateOptions.newBuilder(type).build())
                        .addOnSuccessListener { code -> result.success(PlayMapping.flowResultName(code)) }
                        .addOnFailureListener { result.success("failed") }
                } catch (_: Exception) {
                    result.success("failed")
                }
            }
            .addOnFailureListener { result.success("failed") }
    }

    private fun openStore(): Boolean {
        val context = activity ?: context ?: return false
        val pkg = context.packageName
        for (uri in listOf("market://details?id=$pkg", "https://play.google.com/store/apps/details?id=$pkg")) {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // try the next link
            }
        }
        return false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        manager?.registerListener(listener)
    }

    override fun onCancel(arguments: Any?) {
        stopListening()
    }

    private fun stopListening() {
        manager?.unregisterListener(listener)
        sink = null
    }

    private fun describe(info: AppUpdateInfo): Map<String, Any?> = mapOf(
        "availability" to PlayMapping.availabilityName(info.updateAvailability()),
        "versionCode" to info.availableVersionCode(),
        "priority" to info.updatePriority(),
        "stalenessDays" to info.clientVersionStalenessDays(),
        "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
        "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        "installStatus" to PlayMapping.statusName(info.installStatus()),
        "bytes" to info.bytesDownloaded(),
        "total" to info.totalBytesToDownload(),
    )
}
