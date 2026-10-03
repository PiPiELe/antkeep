package com.pipiele.antkeep

import android.content.Intent
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var backupBridge: BackupBridge? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backupBridge = BackupBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pipiele.antkeep/share_image")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Older Android uses the system file picker without broad storage access.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.success("use_file_picker")
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || bytes.isEmpty() || name == null || !name.matches(Regex("antkeep-[0-9]+\\.png"))) {
                    result.error("invalid_image", "无效的图片", null)
                    return@setMethodCallHandler
                }
                Thread {
                    var uri: android.net.Uri? = null
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, name)
                            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/AntKeep")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        val destination = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("无法创建图片")
                        uri = destination
                        val stream = contentResolver.openOutputStream(destination)
                            ?: throw IllegalStateException("无法写入图片")
                        stream.use { it.write(bytes) }
                        val published = contentResolver.update(destination, ContentValues().apply {
                            put(MediaStore.Images.Media.IS_PENDING, 0)
                        }, null, null)
                        if (published != 1) throw IllegalStateException("图片保存未完成")
                        runOnUiThread { result.success("已保存到相册 Pictures/AntKeep") }
                    } catch (error: Exception) {
                        uri?.let { runCatching { contentResolver.delete(it, null, null) } }
                        runOnUiThread { result.error("save_failed", "图片保存失败，请重试", null) }
                    }
                }.start()
            }
    }
}
