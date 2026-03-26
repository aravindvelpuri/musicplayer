package com.aravindprojects.musicplayer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

data class NativePlaybackState(
    val trackId: String?,
    val title: String,
    val artist: String,
    val album: String,
    val artwork: Bitmap?,
    val isPlaying: Boolean,
    val positionMs: Int,
    val durationMs: Int,
    val status: String,
)

class LocalAudioPlayer(private val context: Context) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val playbackAudioAttributes = AudioAttributes.Builder()
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .build()
    private val progressHandler = Handler(Looper.getMainLooper())
    private val progressRunnable = object : Runnable {
        override fun run() {
            val player = mediaPlayer ?: return
            if (player.isPlaying) {
                emitState("playing")
                progressHandler.postDelayed(this, 500)
            }
        }
    }
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                if (resumeOnFocusGain) {
                    resumeOnFocusGain = false
                    resumePlayback(requestFocus = false)
                } else {
                    emitState()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                hasAudioFocus = false
                pausePlayback(
                    rememberForFocusGain = false,
                    abandonFocus = false,
                )
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                hasAudioFocus = false
                val shouldResume = mediaPlayer?.isPlaying == true || lastStatus == "loading"
                pausePlayback(
                    rememberForFocusGain = shouldResume,
                    abandonFocus = false,
                )
            }
        }
    }
    private val audioDeviceCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                emitState()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                emitState()
            }
        }
    } else {
        null
    }

    private var mediaPlayer: MediaPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentTrackId: String? = null
    private var currentDurationMs: Int = 0
    private var lastStatus: String = "idle"
    private var pendingPlayResult: MethodChannel.Result? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus: Boolean = false
    private var resumeOnFocusGain: Boolean = false
    private var currentTitle: String = "Unknown title"
    private var currentArtist: String = "Unknown artist"
    private var currentAlbum: String = "Unknown album"
    private var currentArtwork: Bitmap? = null
    private var stateObserver: ((NativePlaybackState) -> Unit)? = null

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioDeviceCallback?.let { callback ->
                audioManager.registerAudioDeviceCallback(
                    callback,
                    Handler(Looper.getMainLooper()),
                )
            }
        }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        emitState()
    }

    fun setStateObserver(observer: ((NativePlaybackState) -> Unit)?) {
        stateObserver = observer
        emitState()
    }

    fun playTrack(
        trackId: String,
        uriString: String,
        title: String,
        artist: String,
        album: String,
        result: MethodChannel.Result,
    ) {
        try {
            clearAutoResumeFlags()
            pendingPlayResult?.error(
                "playback_interrupted",
                "Playback request was interrupted by another selection.",
                null,
            )
            pendingPlayResult = result
            releasePlayer(clearSelection = false)

            if (!requestAudioFocus()) {
                lastStatus = "paused"
                pendingPlayResult?.error(
                    "audio_focus_denied",
                    "Unable to play because another app is using audio right now.",
                    null,
                )
                pendingPlayResult = null
                emitState()
                return
            }

            currentTrackId = trackId
            currentDurationMs = 0
            currentTitle = title.ifBlank { "Unknown title" }
            currentArtist = artist.ifBlank { "Unknown artist" }
            currentAlbum = album.ifBlank { "Unknown album" }
            currentArtwork = loadArtworkBitmap(uriString)
            lastStatus = "loading"
            emitState()

            val player = MediaPlayer()
            mediaPlayer = player
            player.setAudioAttributes(playbackAudioAttributes)
            player.setOnPreparedListener { preparedPlayer ->
                currentDurationMs = safeDuration(preparedPlayer)
                pendingPlayResult?.success(null)
                pendingPlayResult = null

                lastStatus = "playing"
                preparedPlayer.start()
                startProgressUpdates()
                emitState()
            }
            player.setOnCompletionListener { completedPlayer ->
                currentDurationMs = safeDuration(completedPlayer)
                lastStatus = "completed"
                stopProgressUpdates()
                emitState()
            }
            player.setOnErrorListener { _, _, _ ->
                lastStatus = "error"
                stopProgressUpdates()
                pendingPlayResult?.error(
                    "playback_failed",
                    "Unable to start playback.",
                    null,
                )
                pendingPlayResult = null
                emitState()
                true
            }
            player.setDataSource(context, Uri.parse(uriString))
            player.prepareAsync()
        } catch (error: Exception) {
            lastStatus = "error"
            stopProgressUpdates()
            pendingPlayResult?.error(
                "playback_failed",
                error.message ?: "Unable to start playback.",
                null,
            )
            pendingPlayResult = null
            emitState()
        }
    }

    fun pause(result: MethodChannel.Result) {
        clearAutoResumeFlags()
        pausePlayback(
            rememberForFocusGain = false,
            abandonFocus = true,
        )
        result.success(null)
    }

    fun resume(result: MethodChannel.Result) {
        clearAutoResumeFlags()
        resumePlayback(requestFocus = true)
        result.success(null)
    }

    fun seekTo(positionMs: Int, result: MethodChannel.Result) {
        val player = mediaPlayer
        if (player == null) {
            result.success(null)
            return
        }

        player.seekTo(positionMs)
        if (lastStatus == "completed" && positionMs < currentDurationMs) {
            lastStatus = "paused"
        }
        emitState()
        result.success(null)
    }

    fun stop(result: MethodChannel.Result) {
        clearAutoResumeFlags()
        releasePlayer(clearSelection = true)
        emitState("idle")
        result.success(null)
    }

    fun dispose() {
        clearAutoResumeFlags()
        releasePlayer(clearSelection = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioDeviceCallback?.let(audioManager::unregisterAudioDeviceCallback)
        }
        eventSink = null
    }

    fun togglePlaybackDirect() {
        if (mediaPlayer?.isPlaying == true) {
            clearAutoResumeFlags()
            pausePlayback(
                rememberForFocusGain = false,
                abandonFocus = true,
            )
            return
        }
        clearAutoResumeFlags()
        resumePlayback(requestFocus = true)
    }

    fun stopDirect() {
        clearAutoResumeFlags()
        releasePlayer(clearSelection = true)
        emitState("idle")
    }

    private fun startProgressUpdates() {
        progressHandler.removeCallbacks(progressRunnable)
        progressHandler.post(progressRunnable)
    }

    private fun stopProgressUpdates() {
        progressHandler.removeCallbacks(progressRunnable)
    }

    private fun emitState(statusOverride: String? = null) {
        if (statusOverride != null) {
            lastStatus = statusOverride
        }

        val player = mediaPlayer
        if (player != null) {
            currentDurationMs = safeDuration(player).coerceAtLeast(currentDurationMs)
        }

        val positionMs = when {
            lastStatus == "completed" -> currentDurationMs
            player != null -> safePosition(player)
            else -> 0
        }
        val (outputRoute, outputLabel) = currentOutputRoute()

        eventSink?.success(
            mapOf(
                "trackId" to currentTrackId,
                "isPlaying" to (player?.isPlaying ?: false),
                "positionMs" to positionMs,
                "durationMs" to currentDurationMs,
                "status" to lastStatus,
                "outputRoute" to outputRoute,
                "outputLabel" to outputLabel,
            ),
        )
        stateObserver?.invoke(
            NativePlaybackState(
                trackId = currentTrackId,
                title = currentTitle,
                artist = currentArtist,
                album = currentAlbum,
                artwork = currentArtwork,
                isPlaying = player?.isPlaying ?: false,
                positionMs = positionMs,
                durationMs = currentDurationMs,
                status = lastStatus,
            ),
        )
    }

    private fun pausePlayback(
        rememberForFocusGain: Boolean,
        abandonFocus: Boolean,
    ) {
        val player = mediaPlayer
        resumeOnFocusGain = rememberForFocusGain

        if (player == null) {
            if (abandonFocus) {
                abandonAudioFocus()
            }
            emitState()
            return
        }

        if (player.isPlaying) {
            player.pause()
        }

        if (lastStatus != "completed") {
            lastStatus = "paused"
        }

        stopProgressUpdates()

        if (abandonFocus) {
            abandonAudioFocus()
        }

        emitState()
    }

    private fun resumePlayback(requestFocus: Boolean) {
        val player = mediaPlayer ?: return

        if (requestFocus && !requestAudioFocus()) {
            emitState()
            return
        }

        if (lastStatus == "completed") {
            player.seekTo(0)
        }

        if (!player.isPlaying) {
            player.start()
        }

        if (player.isPlaying) {
            lastStatus = "playing"
            startProgressUpdates()
        }

        emitState()
    }

    private fun releasePlayer(clearSelection: Boolean) {
        stopProgressUpdates()
        mediaPlayer?.setOnPreparedListener(null)
        mediaPlayer?.setOnCompletionListener(null)
        mediaPlayer?.setOnErrorListener(null)
        mediaPlayer?.release()
        mediaPlayer = null
        abandonAudioFocus()

        if (clearSelection) {
            currentTrackId = null
            currentDurationMs = 0
            currentTitle = "Unknown title"
            currentArtist = "Unknown artist"
            currentAlbum = "Unknown album"
            currentArtwork = null
            lastStatus = "idle"
            pendingPlayResult = null
        }
    }

    private fun requestAudioFocus(): Boolean {
        val requestResult = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusRequest = audioFocusRequest
                ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(playbackAudioAttributes)
                    .setOnAudioFocusChangeListener(
                        audioFocusChangeListener,
                        Handler(Looper.getMainLooper()),
                    )
                    .setWillPauseWhenDucked(true)
                    .build()
                    .also { builtRequest ->
                        audioFocusRequest = builtRequest
                    }
            audioManager.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }

        hasAudioFocus = requestResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasAudioFocus
    }

    private fun abandonAudioFocus() {
        if (!hasAudioFocus && audioFocusRequest == null) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
        hasAudioFocus = false
    }

    private fun clearAutoResumeFlags() {
        resumeOnFocusGain = false
    }

    private fun safeDuration(player: MediaPlayer): Int {
        return try {
            player.duration.coerceAtLeast(0)
        } catch (_: IllegalStateException) {
            currentDurationMs
        }
    }

    private fun safePosition(player: MediaPlayer): Int {
        return try {
            player.currentPosition.coerceAtLeast(0)
        } catch (_: IllegalStateException) {
            0
        }
    }

    private fun loadArtworkBitmap(uriString: String): Bitmap? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(context, Uri.parse(uriString))
            val bytes = retriever.embeddedPicture
            retriever.release()
            if (bytes == null || bytes.isEmpty()) {
                null
            } else {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        } catch (_: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun currentOutputRoute(): Pair<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val preferredDevice = outputs.firstOrNull { device ->
                device.type in bluetoothDeviceTypes
            } ?: outputs.firstOrNull { device ->
                device.type in headsetDeviceTypes
            } ?: outputs.firstOrNull { device ->
                device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            } ?: outputs.firstOrNull { device ->
                device.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
            } ?: outputs.firstOrNull()

            preferredDevice?.let { device ->
                return outputInfoForType(device.type)
            }
        }

        return when {
            audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn -> "bluetooth" to "Bluetooth"
            audioManager.isWiredHeadsetOn -> "headphones" to "Headphones"
            audioManager.isSpeakerphoneOn -> "speaker" to "Phone speaker"
            else -> "speaker" to "Phone speaker"
        }
    }

    private fun outputInfoForType(type: Int): Pair<String, String> {
        return when (type) {
            in bluetoothDeviceTypes -> "bluetooth" to "Bluetooth"
            in headsetDeviceTypes -> "headphones" to "Headphones"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece" to "Phone earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker" to "Phone speaker"
            else -> "speaker" to "This device"
        }
    }

    companion object {
        private val bluetoothDeviceTypes = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
        )

        private val headsetDeviceTypes = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
        )
    }
}
