package com.dustella.nsnc

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 1001
        private const val STORAGE_PERMISSION_REQUEST = 1002
        private const val DOWNLOAD_CHANNEL = "com.dustella.nsnc/downloads"
    }

    private data class ExportRequest(
        val sourcePath: String,
        val fileName: String,
        val mimeType: String,
        val collection: String,
        val title: String,
        val artist: String,
        val album: String,
    )

    private var pendingLegacyExport: Pair<ExportRequest, MethodChannel.Result>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOAD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportAudio" -> handleExport(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val request = ExportRequest(
            sourcePath = call.argument<String>("sourcePath").orEmpty(),
            fileName = call.argument<String>("fileName").orEmpty(),
            mimeType = call.argument<String>("mimeType") ?: "application/octet-stream",
            collection = call.argument<String>("collection") ?: "music",
            title = call.argument<String>("title").orEmpty(),
            artist = call.argument<String>("artist").orEmpty(),
            album = call.argument<String>("album").orEmpty(),
        )
        if (request.sourcePath.isBlank() || request.fileName.isBlank()) {
            result.error("invalid_arguments", "缺少下载源文件或文件名", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exportWithMediaStore(request, result)
            return
        }

        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            exportLegacy(request, result)
        } else {
            pendingLegacyExport = request to result
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
        }
    }

    private fun exportWithMediaStore(
        request: ExportRequest,
        result: MethodChannel.Result,
    ) {
        Thread {
            val resolver = applicationContext.contentResolver
            val isDownloads = request.collection == "downloads"
            val relativePath = if (isDownloads) {
                "${Environment.DIRECTORY_DOWNLOADS}/NSNC"
            } else {
                "${Environment.DIRECTORY_MUSIC}/NSNC"
            }
            val collectionUri = if (isDownloads) {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, request.fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, request.mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                if (!isDownloads) {
                    put(MediaStore.Audio.Media.TITLE, request.title)
                    put(MediaStore.Audio.Media.ARTIST, request.artist)
                    put(MediaStore.Audio.Media.ALBUM, request.album)
                    put(MediaStore.Audio.Media.IS_MUSIC, 1)
                }
            }
            var outputUri: android.net.Uri? = null
            try {
                val source = File(request.sourcePath)
                if (!source.isFile) throw IllegalStateException("下载源文件不存在")
                outputUri = resolver.insert(collectionUri, values)
                    ?: throw IllegalStateException("无法在系统媒体库中创建文件")
                resolver.openOutputStream(outputUri, "w")?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("无法打开系统下载位置")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(outputUri, values, null, null)
                runOnUiThread { result.success("$relativePath/${request.fileName}") }
            } catch (error: Exception) {
                outputUri?.let { resolver.delete(it, null, null) }
                runOnUiThread {
                    result.error("export_failed", error.message ?: "导出失败", null)
                }
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun exportLegacy(
        request: ExportRequest,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val publicDirectory = if (request.collection == "downloads") {
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS,
                    )
                } else {
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                }
                val directory = File(publicDirectory, "NSNC")
                if (!directory.exists() && !directory.mkdirs()) {
                    throw IllegalStateException("无法创建下载目录")
                }
                val source = File(request.sourcePath)
                if (!source.isFile) throw IllegalStateException("下载源文件不存在")
                val target = File(directory, request.fileName)
                source.copyTo(target, overwrite = true)
                runOnUiThread { result.success(target.absolutePath) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("export_failed", error.message ?: "导出失败", null)
                }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val pending = pendingLegacyExport ?: return
        pendingLegacyExport = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            exportLegacy(pending.first, pending.second)
        } else {
            pending.second.error(
                "storage_permission_denied",
                "需要存储权限才能写入 Music 或 Downloads，请在系统设置中授权后重试",
                null,
            )
        }
    }
}
