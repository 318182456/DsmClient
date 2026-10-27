package io.github.user318182456.dsmclient

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class TorrentReceiver(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dsmclient/torrent_import")
    private val pending = mutableListOf<Map<String, String>>()
    private val worker = Executors.newSingleThreadExecutor()
    private var handled = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> result.success(if (pending.isEmpty()) null else pending.removeAt(0))
                "isTorrentIntent" -> result.success(handled)
                "discard" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val file = File(path)
                        if (file.canonicalFile.parentFile == directory().canonicalFile) file.delete()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun directory() = File(activity.cacheDir, "torrent_import")
    private fun name(uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) return cursor.getString(0) ?: ""
                }
            } catch (_: Exception) { }
        }
        return uri.lastPathSegment ?: ""
    }
    @Suppress("DEPRECATION")
    fun receive(source: Intent?) {
        handled = false
        if (source == null) return
        val uris: List<Uri> = when (source.action) {
            Intent.ACTION_VIEW -> listOfNotNull(source.data)
            Intent.ACTION_SEND -> listOfNotNull(source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE -> source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else -> emptyList()
        }
        if (uris.isEmpty()) return
        val entries = uris.take(8).map { uri -> Pair(uri, name(uri)) }
        if (uris.size > 8 || entries.any { (uri, name) ->
            val mime = try { activity.contentResolver.getType(uri) ?: source.type } catch (_: Exception) { source.type }
            uri.scheme !in listOf("content", "file") ||
                (!name.endsWith(".torrent", ignoreCase = true) && mime !in listOf("application/x-bittorrent", "application/x-torrent"))
        }) return
        handled = true
        // Preserve the sender's temporary URI grant before login or backend selection.
        worker.execute {
            val folder = directory().apply { mkdirs() }
            folder.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000L }?.forEach { it.delete() }
            for ((uri, originalName) in entries) {
                val displayName = originalName.substringAfterLast('/').substringAfterLast('\\').take(160).ifEmpty { "download.torrent" }
                val target = File(folder, "${UUID.randomUUID()}.torrent")
                val item: Map<String, String> = try {
                    activity.contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output ->
                            val buffer = ByteArray(8192)
                            var total = 0
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                total += count
                                if (total > 8 * 1024 * 1024) throw IllegalArgumentException("size")
                                output.write(buffer, 0, count)
                            }
                            if (total == 0) throw IllegalArgumentException("empty")
                        }
                    } ?: throw IllegalArgumentException("unreadable")
                    mapOf("path" to target.absolutePath, "name" to displayName)
                } catch (_: Exception) {
                    target.delete()
                    mapOf("error" to "无法读取种子文件，请确认文件可访问且大小在 1 字节至 8 MB 之间。")
                }
                activity.runOnUiThread {
                    pending.add(item)
                    channel.invokeMethod("available", null)
                }
            }
        }
    }
}
