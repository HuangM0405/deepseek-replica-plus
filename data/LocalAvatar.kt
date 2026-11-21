package com.simplechat.app.data

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.core.graphics.scale
import java.io.File
import java.io.FileOutputStream
import kotlin.math.min

/**
 * 本地用户头像的落盘与清理。
 *
 * 头像存进应用私有目录，而不是记住 `content://` URI：相册授权通常只在本次会话有效，
 * 重启后 URI 打不开，头像会变成空白。每次选图写一个新文件（文件名带时间戳），
 * 这样 DataStore 里的路径一定变化，界面才会重新解码；旧文件由调用方在保存成功后删除。
 */
object LocalAvatar {

    /** 头像最长边。256px 足够 44~88dp 的显示，也避免把几 MB 的原图塞进应用目录。 */
    const val MAX_EDGE = 256

    private const val DIR = "profile"

    /**
     * 导入一张图片作为头像，返回落盘后的绝对路径；解码失败 / 不支持 / 写入失败返回 null。
     *
     * 解码前先读边界并按 2 的幂降采样，避免 8000px 的原图在 `decodeStream` 时 OOM。
     */
    fun save(context: Context, uri: Uri): String? {
        val bitmap = decode(context, uri) ?: return null
        val square = cropSquare(bitmap)
        val scaled = if (square.width == MAX_EDGE) square else square.scale(MAX_EDGE, MAX_EDGE)
        return try {
            val dir = File(context.filesDir, DIR).apply { mkdirs() }
            val target = File(dir, "avatar-${System.currentTimeMillis()}.png")
            FileOutputStream(target).use { out ->
                if (!scaled.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                    target.delete()
                    return null
                }
            }
            target.absolutePath
        } catch (error: Exception) {
            null
        } catch (error: OutOfMemoryError) {
            null
        } finally {
            if (scaled !== square) scaled.recycle()
            if (square !== bitmap) square.recycle()
            bitmap.recycle()
        }
    }

    /** 删掉一张旧头像；路径为空或文件已不存在时什么也不做。 */
    fun delete(path: String) {
        if (path.isBlank()) return
        runCatching { File(path).takeIf { it.isFile }?.delete() }
    }

    /** 清除全部头像文件（「删除所有数据」时调用）。 */
    fun clear(context: Context) {
        runCatching { File(context.filesDir, DIR).deleteRecursively() }
    }

    private fun cropSquare(bitmap: Bitmap): Bitmap {
        val edge = min(bitmap.width, bitmap.height)
        val left = (bitmap.width - edge) / 2
        val top = (bitmap.height - edge) / 2
        return Bitmap.createBitmap(bitmap, left, top, edge, edge)
    }

    @SuppressLint("ExifInterface")
    private fun decode(context: Context, uri: Uri): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_EDGE && bounds.outHeight / (sample * 2) >= MAX_EDGE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        } ?: return null

        // 相机照片常把方向写在 EXIF 里；BitmapFactory 不管这个，不转正头像会躺倒。
        val orientation = resolver.openInputStream(uri)?.use { stream ->
            runCatching {
                android.media.ExifInterface(stream).getAttributeInt(
                    android.media.ExifInterface.TAG_ORIENTATION,
                    android.media.ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(android.media.ExifInterface.ORIENTATION_NORMAL)
        } ?: android.media.ExifInterface.ORIENTATION_NORMAL
        return rotate(decoded, orientation) ?: decoded
    }

    @SuppressLint("ExifInterface")
    private fun rotate(bitmap: Bitmap, orientation: Int): Bitmap? {
        if (orientation == android.media.ExifInterface.ORIENTATION_NORMAL) return null
        val matrix = Matrix()
        when (orientation) {
            android.media.ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            android.media.ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            android.media.ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            android.media.ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            android.media.ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            android.media.ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            android.media.ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return null
        }
        return runCatching {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }.getOrNull()
    }
}
