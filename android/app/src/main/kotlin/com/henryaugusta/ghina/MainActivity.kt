package com.henryaugusta.ghina

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.WindowManager
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import im.zoe.labs.flutter_notification_listener.NotificationsHandlerService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the small Ghina platform bridge (see lib/data/platform/platform_bridge.dart):
 *  - Android share target: ACTION_SEND / ACTION_SEND_MULTIPLE (text/..., image/...,
 *    application/pdf for "Impor mutasi"). Shared content:// images and PDFs are copied into cacheDir/share_intake right away (the
 *    read grant dies with the intent); Dart moves them into app documents.
 *    Every share (cold start or while running) is queued until Dart listens on the
 *    share EventChannel, so none is lost.
 *  - App settings shortcut + "should show rationale" for the mic permission.
 *  - Launcher icon = chosen mascot (LauncherIcon: one activity-alias per mascot).
 *  - Offline speech support query / model download (Android 13+ RecognitionSupport).
 *  - Launcher shortcuts come from the quick_actions plugin (dynamic shortcuts set
 *    from Dart; the plugin reads the launch extra on cold start and gets warm
 *    starts through onNewIntent). This activity only makes sure a shortcut
 *    doesn't fire twice (restored from Recents / re-attached plugin). The static
 *    "Chat Killa" shortcut (res/xml/shortcuts.xml) carries the same extra, so it
 *    takes the same path.
 *  - Log Notifikasi: launchable apps + app labels (apps.list / apps.label), and a
 *    hand-over of the flutter_notification_listener service to a background engine
 *    when this activity's engine dies (see onDestroy), and the listener watchdog
 *    (NotificationListenerWatchdog: scheduled here, checked on every resume).
 *
 * A FlutterFragmentActivity (not FlutterActivity) because local_auth ("Kunci
 * Kebiasaan") shows the BiometricPrompt as a fragment. The share / settings / speech
 * bridge above is unchanged: onCreate, onNewIntent and configureFlutterEngine behave
 * the same on both base classes.
 */
class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var shareSink: EventChannel.EventSink? = null
    private val pendingShares = mutableListOf<Map<String, Any?>>()
    private var fileSeq = 0
    private var uiEngine: FlutterEngine? = null

    // Kantor widget taps (KantorWidgetProvider): the route waits here until Dart asks
    // (cold start: "takeRoute"); once it has, later taps are pushed ("route").
    private var kantorRoute: String? = null
    private var kantorChannel: MethodChannel? = null
    private var kantorDartReady = false

    // Dikte: in-app download of the offline speech pack ("app/speech_model").
    private var speechModelChannel: MethodChannel? = null
    private var modelRecognizer: SpeechRecognizer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Restored (rotation / process death) or reopened from Recents: the share /
        // shortcut was already handled — don't import or open it twice.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState != null || fromHistory) intent.removeExtra(QUICK_ACTION_EXTRA)
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null && !fromHistory) {
            handleShareIntent(intent)
            handleKantorIntent(intent)
        }
        if (BuildConfig.FLAVOR != "ravel") ListenerWatchdogJob.schedule(this)
    }

    override fun onResume() {
        super.onResume()
        if (BuildConfig.FLAVOR != "ravel") NotificationListenerWatchdog.check(this, "resume")
    }

    override fun onStop() {
        super.onStop()
        // Dictation stops in the background (Dart); give the beeps back regardless.
        DictationAudioMuter.unmute(this)
        // A new launcher icon closes the task launched from the old one: switch it
        // only once Ghina is in the background.
        if (BuildConfig.FLAVOR != "ravel" && !isChangingConfigurations) LauncherIcon.applyPending(this)
    }

    override fun onNewIntent(intent: Intent) {
        // Plugins (quick_actions) read the shortcut extra synchronously in here.
        super.onNewIntent(intent)
        // Consumed: a later plugin re-attach re-reads getIntent() — don't re-open it.
        intent.removeExtra(QUICK_ACTION_EXTRA)
        setIntent(intent)
        handleShareIntent(intent)
        handleKantorIntent(intent)
    }

    /** A tap on the Kantor home-screen widget carries a /kantor… route. */
    private fun handleKantorIntent(intent: Intent?) {
        if (intent?.action != KantorWidgetProvider.ACTION_OPEN) return
        val route = intent.getStringExtra(KantorWidgetProvider.EXTRA_ROUTE)
        // Consumed: a recreate with the same intent must not re-open it.
        intent.action = null
        intent.removeExtra(KantorWidgetProvider.EXTRA_ROUTE)
        if (route == null || !route.startsWith("/kantor")) return
        val channel = kantorChannel
        if (kantorDartReady && channel != null) {
            channel.invokeMethod("route", route)
        } else {
            kantorRoute = route
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        uiEngine = flutterEngine
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, SHARE_EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                shareSink = events
                val queued = pendingShares.toList()
                pendingShares.clear()
                queued.forEach { events?.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                shareSink = null
            }
        })

        kantorChannel = MethodChannel(messenger, KANTOR_WIDGET).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takeRoute") {
                    kantorDartReady = true
                    result.success(kantorRoute)
                    kantorRoute = null
                } else {
                    result.notImplemented()
                }
            }
        }

        // Dikte: recognizer beeps muted while dictating (DictationAudioMuter). A
        // crash mid-dictation left them muted → restore first.
        DictationAudioMuter.unmute(this)
        MethodChannel(messenger, DICTATION_AUDIO).setMethodCallHandler { call, result ->
            when (call.method) {
                "mute" -> result.success(DictationAudioMuter.mute(this))
                "unmute" -> result.success(DictationAudioMuter.unmute(this))
                else -> result.notImplemented()
            }
        }

        // Dikte: offline speech pack download with progress / settings fallback.
        speechModelChannel = MethodChannel(messenger, SPEECH_MODEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "download" -> result.success(
                        downloadSpeechModelWithProgress(call.argument<String>("locale") ?: "id-ID")
                    )
                    "openSettings" -> result.success(openSpeechSettings())
                    else -> result.notImplemented()
                }
            }
        }

        // Ravel mode meja (Fold setengah terbuka di meja): layar tetap menyala
        // selama Dart memintanya (lib/.../session/kantor_tabletop.dart,
        // KantorScreenAwake). Di Ghina channel ini no-op.
        MethodChannel(messenger, SCREEN).setMethodCallHandler { call, result ->
            if (call.method != "keepOn") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (BuildConfig.FLAVOR == "ravel") {
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
            result.success(null)
        }

        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                // Shares are delivered through the event channel (queued until
                // listened); kept for API symmetry.
                "share.initial" -> result.success(null)
                "app.openSettings" -> result.success(openAppSettings())
                "mic.shouldShowRationale" -> result.success(
                    shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
                )
                "speech.support" -> speechSupport(
                    call.argument<String>("locale") ?: "id-ID"
                ) { result.success(it) }
                "speech.downloadModel" -> result.success(
                    downloadSpeechModel(call.argument<String>("locale") ?: "id-ID")
                )
                "apps.list" -> io.execute {
                    val apps = launchableApps()
                    main.post { result.success(apps) }
                }
                "apps.label" -> result.success(appLabel(call.argument<String>("package")))
                "battery.isIgnoring" -> result.success(isIgnoringBatteryOptimizations())
                "battery.openSettings" -> result.success(openBatteryOptimizationSettings())
                "launcherIcon.current" -> result.success(LauncherIcon.current(this))
                "launcherIcon.set" -> result.success(
                    LauncherIcon.set(this, call.argument<String>("id") ?: "")
                )
                else -> result.notImplemented()
            }
        }
    }

    // --- share target --------------------------------------------------------------

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val type = intent.type ?: ""
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val texts = mutableListOf<String>()
        val streams = mutableListOf<Uri>()

        if (action == Intent.ACTION_SEND) {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let { texts.add(it) }
            streamExtra(intent)?.let { streams.add(it) }
        } else {
            intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)?.forEach { texts.add(it.toString()) }
            streamListExtra(intent)?.let { streams.addAll(it) }
        }
        // Some apps only put the URIs in ClipData.
        if (streams.isEmpty()) {
            intent.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { streams.add(it) }
            }
        }
        // Consume it so a later recreate with the same intent doesn't re-import.
        intent.action = null

        io.execute {
            val images = mutableListOf<String>()
            val pdfs = mutableListOf<String>()
            for (uri in streams.take(MAX_IMAGES)) {
                val mime = runCatching { contentResolver.getType(uri) }.getOrNull() ?: type
                when {
                    mime == "application/pdf" -> {
                        if (pdfs.isEmpty()) copyPdfToCache(uri)?.let { pdfs.add(it) }
                    }
                    mime.startsWith("image/") -> copyToCache(uri, mime)?.let { images.add(it) }
                    mime.startsWith("text/") && texts.isEmpty() -> readText(uri)?.let { texts.add(it) }
                }
            }
            val payload = mapOf("subject" to subject, "texts" to texts, "images" to images, "pdfs" to pdfs)
            main.post { deliverShare(payload) }
        }
    }

    private fun deliverShare(payload: Map<String, Any?>) {
        val sink = shareSink
        if (sink != null) sink.success(payload) else pendingShares.add(payload)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }

    private fun copyToCache(uri: Uri, mime: String): String? = runCatching {
        val dir = File(cacheDir, "share_intake").apply { mkdirs() }
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "jpg"
        val out = File(dir, "${System.currentTimeMillis()}_${fileSeq++}.$ext")
        var total = 0L
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_IMAGE_BYTES) throw IllegalStateException("too large")
                    output.write(buf, 0, n)
                }
            }
        } ?: return@runCatching null
        out.absolutePath
    }.getOrElse { null }

    /**
     * Copies a shared PDF to cacheDir/share_intake/<n>/<original name>.pdf (the file
     * name is what the statement import shows). Up to MAX_PDF_BYTES; Dart rejects
     * anything over the server's 10 MB with a friendly message.
     */
    private fun copyPdfToCache(uri: Uri): String? {
        val dir = File(cacheDir, "share_intake/${System.currentTimeMillis()}_${fileSeq++}")
        return runCatching { copyPdfInto(dir, uri) }.getOrNull()
            ?: run { dir.deleteRecursively(); null } // too large / unreadable: no half copy left behind
    }

    private fun copyPdfInto(dir: File, uri: Uri): String? {
        dir.mkdirs()
        val name = displayName(uri)
            ?.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            ?.takeIf { it.isNotBlank() }
            ?: "mutasi.pdf"
        val out = File(dir, if (name.endsWith(".pdf", ignoreCase = true)) name else "$name.pdf")
        var total = 0L
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_PDF_BYTES) throw IllegalStateException("too large")
                    output.write(buf, 0, n)
                }
            }
        } ?: return null
        return out.absolutePath
    }

    private fun displayName(uri: Uri): String? = runCatching {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull()

    private fun readText(uri: Uri): String? = runCatching {
        contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readNBytesCompat(MAX_TEXT_BYTES)
            String(bytes, Charsets.UTF_8)
        }
    }.getOrNull()

    private fun java.io.InputStream.readNBytesCompat(max: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(8 * 1024)
        while (out.size() < max) {
            val n = read(buf, 0, minOf(buf.size, max - out.size()))
            if (n < 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    // --- settings ------------------------------------------------------------------

    private fun openAppSettings(): Boolean = runCatching {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    }.getOrDefault(false)

    // --- battery optimisation (Reminder Sholat) --------------------------------------

    /** Null below Android 6 (no Doze). */
    private fun isIgnoringBatteryOptimizations(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return null
        return runCatching { pm.isIgnoringBatteryOptimizations(packageName) }.getOrNull()
    }

    /**
     * Opens the system "battery optimisation" list (no REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
     * permission: Play restricts it), falling back to the app details page.
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val ok = runCatching {
                startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                true
            }.getOrDefault(false)
            if (ok) return true
        }
        return openAppSettings()
    }

    // --- speech --------------------------------------------------------------------

    private fun speechSupport(locale: String, reply: (Map<String, Any?>) -> Unit) {
        val sdk = Build.VERSION.SDK_INT
        val available = runCatching { SpeechRecognizer.isRecognitionAvailable(this) }.getOrDefault(false)
        val onDevice = sdk >= 31 &&
            runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(this) }.getOrDefault(false)
        val result = mutableMapOf<String, Any?>(
            "sdkInt" to sdk,
            "recognitionAvailable" to available,
            "onDeviceAvailable" to onDevice,
        )
        if (sdk < 33 || (!available && !onDevice)) {
            reply(result)
            return
        }
        val queries = mutableListOf<Pair<String, SpeechRecognizer>>()
        runCatching {
            if (available) queries.add("defaultService" to SpeechRecognizer.createSpeechRecognizer(this))
            if (onDevice) queries.add("onDeviceService" to SpeechRecognizer.createOnDeviceSpeechRecognizer(this))
        }
        if (queries.isEmpty()) {
            reply(result)
            return
        }
        var remaining = queries.size
        var replied = false
        fun finishOne() {
            remaining--
            if (remaining <= 0 && !replied) {
                replied = true
                reply(result)
            }
        }
        val timeout = Runnable {
            if (!replied) {
                replied = true
                reply(result)
            }
            queries.forEach { (_, r) -> runCatching { r.destroy() } }
        }
        main.postDelayed(timeout, 3000)
        val recognizeIntent = recognizeIntent(locale)
        for ((key, recognizer) in queries) {
            try {
                recognizer.checkRecognitionSupport(
                    recognizeIntent,
                    Executors.newSingleThreadExecutor(),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(support: RecognitionSupport) {
                            main.post {
                                result[key] = mapOf(
                                    "installed" to support.installedOnDeviceLanguages,
                                    "pending" to support.pendingOnDeviceLanguages,
                                    "supported" to support.supportedOnDeviceLanguages,
                                    "online" to support.onlineLanguages,
                                )
                                runCatching { recognizer.destroy() }
                                finishOne()
                            }
                        }

                        override fun onError(error: Int) {
                            main.post {
                                runCatching { recognizer.destroy() }
                                finishOne()
                            }
                        }
                    },
                )
            } catch (e: Exception) {
                runCatching { recognizer.destroy() }
                finishOne()
            }
        }
    }

    private fun downloadSpeechModel(locale: String): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        return runCatching {
            val onDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            val recognizer = if (onDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
            recognizer.triggerModelDownload(recognizeIntent(locale))
            // Give the service time to take the request before unbinding.
            main.postDelayed({ runCatching { recognizer.destroy() } }, 10_000)
            true
        }.getOrDefault(false)
    }

    /**
     * "Unduh sekarang" in the speech-pack sheet. Returns "progress" (Android 14+:
     * events progress / success / scheduled / error follow on [SPEECH_MODEL]),
     * "triggered" (Android 13: no progress, Dart polls the availability) or
     * "unsupported" (older Android / request refused → settings fallback).
     */
    private fun downloadSpeechModelWithProgress(locale: String): String {
        if (Build.VERSION.SDK_INT < 33) return "unsupported"
        return runCatching {
            releaseModelRecognizer()
            val onDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            val recognizer = if (onDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
            modelRecognizer = recognizer
            val intent = recognizeIntent(locale)
            if (Build.VERSION.SDK_INT >= 34) {
                recognizer.triggerModelDownload(intent, mainExecutor, object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {
                        sendModelEvent("progress", mapOf("percent" to completedPercent))
                    }

                    override fun onSuccess() {
                        sendModelEvent("success", null)
                        releaseModelRecognizer()
                    }

                    override fun onScheduled() {
                        sendModelEvent("scheduled", null)
                        releaseModelRecognizer()
                    }

                    override fun onError(error: Int) {
                        if (error == SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS) {
                            // The service can download but not report: plain request,
                            // Dart polls the availability instead.
                            val ok = runCatching {
                                recognizer.triggerModelDownload(intent)
                                true
                            }.getOrDefault(false)
                            sendModelEvent(if (ok) "triggered" else "error", mapOf("code" to error))
                            main.postDelayed({ releaseModelRecognizer() }, 10_000)
                        } else {
                            sendModelEvent("error", mapOf("code" to error))
                            releaseModelRecognizer()
                        }
                    }
                })
                "progress"
            } else {
                recognizer.triggerModelDownload(intent)
                // Give the service time to take the request before unbinding.
                main.postDelayed({ releaseModelRecognizer() }, 10_000)
                "triggered"
            }
        }.getOrElse {
            releaseModelRecognizer()
            "unsupported"
        }
    }

    private fun sendModelEvent(method: String, args: Map<String, Any?>?) {
        main.post { runCatching { speechModelChannel?.invokeMethod(method, args) } }
    }

    private fun releaseModelRecognizer() {
        val r = modelRecognizer ?: return
        modelRecognizer = null
        runCatching { r.destroy() }
    }

    /**
     * Fallback when the in-app download isn't possible: the most specific screen
     * that opens — Google's offline speech language packs, Android voice input
     * (on-device recognition), languages, settings home. Starting the activity is
     * the check (resolveActivity can't see the Google app without <queries>).
     */
    private fun openSpeechSettings(): String? {
        val candidates = listOf(
            "google_offline" to Intent().setComponent(
                ComponentName(
                    "com.google.android.googlequicksearchbox",
                    "com.google.android.voicesearch.greco3.languagepack.InstallActivity",
                )
            ),
            "voice_input" to Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            "language" to Intent(Settings.ACTION_LOCALE_SETTINGS),
            "settings" to Intent(Settings.ACTION_SETTINGS),
        )
        for ((key, intent) in candidates) {
            val opened = runCatching {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            }.getOrDefault(false)
            if (opened) return key
        }
        return null
    }

    private fun recognizeIntent(locale: String) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
    }

    // --- Log Notifikasi -------------------------------------------------------------

    private fun launchableApps(): List<Map<String, String>> = runCatching {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }.getOrDefault(emptyList())

    private fun appLabel(pkg: String?): String? {
        if (pkg.isNullOrBlank()) return null
        return runCatching {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        }.getOrNull()
    }

    /**
     * flutter_notification_listener keeps delivering notifications to the engine in
     * FlutterEngineCache ("flutter_engine_main" = this activity's engine while it
     * lives). When the activity finishes, that engine is destroyed but stays cached,
     * so events would go nowhere until the process dies. Drop it from the cache and
     * let the running listener service start its headless background engine, which
     * runs the Dart callback and keeps storing notifications.
     */
    private fun handOverNotificationListener() {
        runCatching {
            val cache = FlutterEngineCache.getInstance()
            val engine = uiEngine ?: return
            if (cache.get(LISTENER_ENGINE_KEY) !== engine) return
            cache.remove(LISTENER_ENGINE_KEY)
            if (NotificationsHandlerService.permissionGiven(applicationContext)) {
                NotificationsHandlerService.updateFlutterEngine(applicationContext)
            }
        }
    }

    override fun onDestroy() {
        releaseModelRecognizer()
        speechModelChannel = null
        DictationAudioMuter.unmute(this)
        io.shutdown()
        super.onDestroy()
        if (BuildConfig.FLAVOR != "ravel" && !isChangingConfigurations) handOverNotificationListener()
        uiEngine = null
    }

    companion object {
        private const val METHODS = "com.henryaugusta.ghina/platform"
        private const val SHARE_EVENTS = "com.henryaugusta.ghina/share"
        private const val KANTOR_WIDGET = "com.henryaugusta.ghina/kantor_widget"
        private const val SCREEN = "ravel/screen"
        private const val DICTATION_AUDIO = "app/dictation_audio"
        private const val SPEECH_MODEL = "app/speech_model"
        private const val MAX_IMAGES = 20
        private const val MAX_IMAGE_BYTES = 25L * 1024 * 1024
        private const val MAX_PDF_BYTES = 11L * 1024 * 1024
        private const val MAX_TEXT_BYTES = 100 * 1024

        /** FlutterNotificationListenerPlugin.FLUTTER_ENGINE_CACHE_KEY. */
        private const val LISTENER_ENGINE_KEY = "flutter_engine_main"

        /** quick_actions' launch extra (QuickActions.EXTRA_ACTION). */
        private const val QUICK_ACTION_EXTRA = "some unique action key"
    }
}
