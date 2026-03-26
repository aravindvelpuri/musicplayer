package com.aravindprojects.musicplayer

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

class DeviceMusicRepository(private val context: Context) {
    @Suppress("DEPRECATION")
    fun getMusicFiles(): List<Map<String, Any?>> {
        val musicFiles = mutableListOf<Map<String, Any?>>()
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(MediaStore.Audio.Media.RELATIVE_PATH)
            } else {
                add(MediaStore.Audio.Media.DATA)
            }
        }.toTypedArray()

        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        context.contentResolver.query(
            collection,
            projection,
            selection,
            null,
            sortOrder,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val displayNameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val titleColumn = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val durationColumn = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val relativePathColumn = cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
            val dataColumn = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val displayName = cursor.stringOrNull(displayNameColumn).orEmpty()
                val title = friendlyText(cursor.stringOrNull(titleColumn), "Unknown title")
                val artist = friendlyText(cursor.stringOrNull(artistColumn), "Unknown artist")
                val album = friendlyText(cursor.stringOrNull(albumColumn), "Unknown album")
                val durationMs = cursor.longOrZero(durationColumn)
                val relativePath = cursor.stringOrNull(relativePathColumn).orEmpty()
                val absolutePath = cursor.stringOrNull(dataColumn).orEmpty()
                val contentUri = ContentUris.withAppendedId(collection, id).toString()
                val path = when {
                    absolutePath.isNotBlank() -> absolutePath
                    relativePath.isNotBlank() && displayName.isNotBlank() -> "$relativePath$displayName"
                    else -> displayName
                }

                musicFiles.add(
                    mapOf(
                        "id" to id.toString(),
                        "displayName" to displayName,
                        "title" to title,
                        "artist" to artist,
                        "album" to album,
                        "path" to path,
                        "uri" to contentUri,
                        "durationMs" to durationMs.toInt(),
                    ),
                )
            }
        }

        return musicFiles
    }

    fun getArtwork(uriString: String): ByteArray? {
        val retriever = MediaMetadataRetriever()

        return try {
            retriever.setDataSource(context, Uri.parse(uriString))
            retriever.embeddedPicture
        } finally {
            retriever.release()
        }
    }

    fun deleteMusicFile(uriString: String): Boolean {
        val resolver = context.contentResolver
        val uri = Uri.parse(uriString)
        
        return try {
            val deletedRows = resolver.delete(uri, null, null)
            deletedRows > 0
        } catch (securityException: SecurityException) {
            // Handle Scoped Storage permissions on Android 10+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && 
                securityException is android.app.RecoverableSecurityException) {
                // We could launch the intent to ask for permission here, 
                // but for now we'll just throw the exception to handle it in MainActivity
                throw securityException
            } else {
                throw securityException
            }
        }
    }

    private fun friendlyText(value: String?, fallback: String): String {
        val trimmedValue = value?.trim().orEmpty()
        return if (trimmedValue.isBlank() || trimmedValue.equals("<unknown>", ignoreCase = true)) {
            fallback
        } else {
            trimmedValue
        }
    }

    private fun Cursor.stringOrNull(columnIndex: Int): String? {
        return if (columnIndex >= 0 && !isNull(columnIndex)) {
            getString(columnIndex)
        } else {
            null
        }
    }

    private fun Cursor.longOrZero(columnIndex: Int): Long {
        return if (columnIndex >= 0 && !isNull(columnIndex)) {
            getLong(columnIndex)
        } else {
            0L
        }
    }
}
