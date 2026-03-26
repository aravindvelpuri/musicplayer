package com.aravindprojects.musicplayer

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.aravindprojects.musicplayer/media"
    private val eventChannelName = "com.aravindprojects.musicplayer/player_events"
    private val readPermissionRequestCode = 7001

    private var pendingReadResult: MethodChannel.Result? = null
    private var mediaMethodChannel: MethodChannel? = null

    private lateinit var musicRepository: DeviceMusicRepository
    private lateinit var audioPlayer: LocalAudioPlayer

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        musicRepository = DeviceMusicRepository(this)
        audioPlayer = PlaybackRuntime.player(this)

        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        mediaMethodChannel = methodChannel
        FlutterCommandBridge.attach(methodChannel)

        methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMusicFiles" -> handleGetMusicFiles(result)
                    "playTrack" -> handlePlayTrack(call, result)
                    "pausePlayback" -> audioPlayer.pause(result)
                    "resumePlayback" -> audioPlayer.resume(result)
                    "seekTo" -> {
                        val positionMs = call.argument<Int>("positionMs") ?: 0
                        audioPlayer.seekTo(positionMs, result)
                    }
                    "stopPlayback" -> audioPlayer.stop(result)
                    "getArtwork" -> handleGetArtwork(call, result)
                    "deleteMusicFile" -> handleDeleteMusicFile(call, result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        audioPlayer.setEventSink(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        audioPlayer.setEventSink(null)
                    }
                },
            )
    }

    override fun onDestroy() {
        FlutterCommandBridge.detach(mediaMethodChannel)
        mediaMethodChannel = null
        super.onDestroy()
    }

    private fun handleGetMusicFiles(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(musicRepository.getMusicFiles())
            return
        }

        if (pendingReadResult != null) {
            result.error(
                "permission_in_progress",
                "A permission request is already in progress.",
                null,
            )
            return
        }

        pendingReadResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(requiredReadPermission()),
            readPermissionRequestCode,
        )
    }

    private fun handlePlayTrack(call: MethodCall, result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            result.error("permission_denied", "Audio permission was denied.", null)
            return
        }

        val trackId = call.argument<String>("id")
        val uriString = call.argument<String>("uri")
        val title = call.argument<String>("title").orEmpty()
        val artist = call.argument<String>("artist").orEmpty()
        val album = call.argument<String>("album").orEmpty()
        if (trackId.isNullOrBlank() || uriString.isNullOrBlank()) {
            result.error("invalid_arguments", "Track id and uri are required.", null)
            return
        }

        PlaybackNotificationService.ensureStarted(this)
        audioPlayer.playTrack(trackId, uriString, title, artist, album, result)
    }

    private fun handleGetArtwork(call: MethodCall, result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            result.error("permission_denied", "Audio permission was denied.", null)
            return
        }

        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.error("invalid_arguments", "Track uri is required.", null)
            return
        }

        try {
            result.success(musicRepository.getArtwork(uriString))
        } catch (error: Exception) {
            result.error(
                "artwork_failed",
                error.message ?: "Unable to load artwork.",
                null,
            )
        }
    }

    private fun handleDeleteMusicFile(call: MethodCall, result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            result.error("permission_denied", "Audio permission was denied.", null)
            return
        }

        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.error("invalid_arguments", "Track uri is required.", null)
            return
        }

        try {
            val success = musicRepository.deleteMusicFile(uriString)
            result.success(success)
        } catch (securityException: SecurityException) {
            result.error(
                "deletion_security_error",
                "Permission required to delete this file.",
                null,
            )
        } catch (error: Exception) {
            result.error(
                "deletion_failed",
                error.message ?: "Unable to delete file.",
                null,
            )
        }
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, requiredReadPermission()) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requiredReadPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            readPermissionRequestCode -> {
                val result = pendingReadResult ?: return
                pendingReadResult = null

                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(musicRepository.getMusicFiles())
                } else {
                    result.error("permission_denied", "Audio permission was denied.", null)
                }
            }
        }
    }
}
