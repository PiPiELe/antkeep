package com.pipiele.antkeep

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Pass file paths across Flutter's channel, never whole backup byte arrays. */
class BackupBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private val requestCode = 48271

    init {
        MethodChannel(messenger, "com.pipiele.antkeep/backup").setMethodCallHandler { call, result ->
            when (call.method) {
                "resources" -> try {
                    val info = ActivityManager.MemoryInfo()
                    (activity.getSystemService(Activity.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
                    val directory = call.argument<String>("path") ?: activity.filesDir.path
                    result.success(mapOf(
                        "availableMemory" to info.availMem,
                        "totalMemory" to info.totalMem,
                        "lowMemory" to info.lowMemory,
                        "freeDisk" to StatFs(directory).availableBytes
                    ))
                } catch (error: Exception) {
                    result.error("resources_failed", "无法获取设备资源信息", null)
                }
                "saveBackup" -> {
                    if (pending != null) {
                        result.error("busy", "正在保存备份", null)
                    } else {
                        val file = call.argument<String>("path")?.let { File(it) }
                        val name = call.argument<String>("name")
                        if (file == null || !file.isFile || name == null) {
                            result.error("invalid_file", "备份文件不存在", null)
                        } else {
                            pending = result
                            source = file
                            try {
                                activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/zip"
                                    putExtra(Intent.EXTRA_TITLE, name)
                                }, requestCode)
                            } catch (error: Exception) {
                                pending = null
                                source = null
                                result.error("save_failed", "无法打开文件保存窗口", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != requestCode) return false
        val result = pending ?: return true
        val file = source
        pending = null
        source = null
        if (code != Activity.RESULT_OK || data?.data == null) {
            result.success(false)
            return true
        }
        val uri = data.data!!
        Thread {
            try {
                requireNotNull(file)
                val output = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("无法写入文件")
                output.use { destination -> file.inputStream().use { it.copyTo(destination, 256 * 1024) } }
                activity.runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                // Remove an incomplete newly-created document on failed export.
                runCatching { android.provider.DocumentsContract.deleteDocument(activity.contentResolver, uri) }
                activity.runOnUiThread { result.error("save_failed", "备份保存失败，请检查目标存储空间后重试", null) }
            }
        }.start()
        return true
    }
}
