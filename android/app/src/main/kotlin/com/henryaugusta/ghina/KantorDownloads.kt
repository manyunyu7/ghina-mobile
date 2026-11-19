package com.henryaugusta.ghina

import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.io.File
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** System-owned transfers survive the Flutter engine, activity and screen lock.
 * Preview links need no bearer. Attachment retry credentials are encrypted
 * with an app-private Android Keystore key, never stored as plaintext prefs. */
class KantorDownloads(private val context: Context) : MethodChannel.MethodCallHandler {
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val prefs = context.getSharedPreferences("kantor_downloads", Context.MODE_PRIVATE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "enqueue" -> result.success(enqueue(call.argument<String>("url") ?: "",
                    call.argument<String>("name") ?: "berkas", call.argument<String>("mime") ?: "",
                    call.argument<String>("description") ?: "Berkas Kantor", call.argument<String>("authorization")))
                "list" -> result.success(records().map { row(it.first, it.second) }.sortedByDescending { it["created"] as Long })
                "cancel" -> {
                    val id = id(call)
                    val meta = metadata(id)
                    require(row(id, meta)["status"] in listOf("queued", "running", "waiting"))
                    manager.remove(id)
                    meta.put("cancelled", true)
                    prefs.edit().putString(id.toString(), meta.toString()).apply()
                    result.success(null)
                }
                "retry" -> {
                    val id = id(call)
                    val meta = metadata(id)
                    require(row(id, meta)["status"] in listOf("failed", "cancelled", "missing"))
                    val next = enqueue(meta.getString("url"), meta.getString("name"), meta.optString("mime"), meta.optString("description"),
                        if (meta.has("access")) decrypt(meta.getString("access")) else null)
                    prefs.edit().remove(id.toString()).apply()
                    result.success(next)
                }
                "open", "share" -> {
                    val id = id(call)
                    val meta = metadata(id) // restrict operations to transfers created here
                    require(row(id, meta)["status"] == "complete")
                    val name = meta.getString("location").substringAfterLast('/')
                    val file = if (Build.VERSION.SDK_INT >= 29)
                        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Ravel/$name")
                        else File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), name)
                    // FileProvider exposes the original display name, not a numeric DownloadManager id.
                    val uri = FileProvider.getUriForFile(context, "${context.packageName}.kantor.downloads", file, meta.getString("name"))
                    context.contentResolver.openFileDescriptor(uri, "r")?.close() ?: error("missing")
                    val mime = manager.getMimeTypeForDownloadedFile(id) ?: "application/octet-stream"
                    val intent = if (call.method == "share") Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                    } else Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    intent.clipData = ClipData.newRawUri("Unduhan", uri)
                    context.startActivity(Intent.createChooser(intent, if (call.method == "share") "Bagikan berkas" else "Buka berkas")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            // URLs may contain private signing keys: never echo exception text.
            result.error("download_error", "Tidak bisa memproses download. Periksa koneksi, ruang penyimpanan, atau buka ulang berkas.", null)
        }
    }

    private fun id(call: MethodCall) = (call.argument<Number>("id") ?: error("id")).toLong()
    private fun metadata(id: Long) = JSONObject(prefs.getString(id.toString(), null) ?: error("unknown"))
    private fun records() = prefs.all.mapNotNull { (key, value) ->
        try { key.toLong() to JSONObject(value as String) } catch (_: Exception) { null }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "kantor_download_access"
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }
    private fun decrypt(value: String): String {
        val parts = value.split(':'); require(parts.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
    }

    private fun enqueue(url: String, original: String, mime: String, description: String, authorization: String? = null): Long {
        val uri = Uri.parse(url)
        require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null)
        val preview = uri.path?.startsWith("/pv/") == true
        val attachment = Regex("^/api/attachments/[^/]+/raw$").matches(uri.path ?: "")
        require(preview || attachment)
        require(if (preview) authorization == null else authorization != null && Regex("^Bearer [^\\r\\n]+$").matches(authorization))
        records().forEach { (id, meta) ->
            if (meta.optString("url") == url && row(id, meta)["status"] in listOf("queued", "running", "waiting")) return id
        }
        val encryptedAccess = authorization?.let { encrypt(it) }
        val name = original.replace(Regex("[\\\\/\\p{Cntrl}]"), "_").trim().take(160).ifBlank { "berkas" }
        val saved = "${UUID.randomUUID().toString().take(8)}-$name"
        val request = DownloadManager.Request(uri).setTitle(name).setDescription(description.take(200))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedOverMetered(true).setAllowedOverRoaming(false)
        if (mime.isNotBlank()) request.setMimeType(mime)
        if (authorization != null) request.addRequestHeader("Authorization", authorization)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Ravel/$saved")
        } else request.setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, saved)
        val id = manager.enqueue(request)
        val meta = JSONObject().put("url", url).put("name", name).put("mime", mime)
            .put("description", description.take(200)).put("created", System.currentTimeMillis())
            .put("location", if (Build.VERSION.SDK_INT >= 29) "Download/Ravel/$saved" else "Penyimpanan aplikasi/$saved")
        if (encryptedAccess != null) meta.put("access", encryptedAccess)
        prefs.edit().putString(id.toString(), meta.toString()).apply()
        return id
    }

    private fun row(id: Long, meta: JSONObject): Map<String, Any> {
        var status = if (meta.optBoolean("cancelled")) "cancelled" else "missing"
        var received = 0L; var total = -1L; var reason = 0
        manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (cursor.moveToFirst()) {
                status = when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_PENDING -> "queued"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "waiting"
                    DownloadManager.STATUS_SUCCESSFUL -> "complete"
                    else -> "failed"
                }
                received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            }
        }
        return mapOf("id" to id, "name" to meta.getString("name"), "description" to meta.optString("description"),
            "created" to meta.getLong("created"), "location" to meta.optString("location"),
            "status" to status, "received" to received, "total" to total, "reason" to reason)
    }
}
