package com.aravindprojects.musicplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

class PlaybackNotificationService : Service() {
    private val player by lazy { PlaybackRuntime.player(applicationContext) }
    private lateinit var mediaSession: MediaSessionCompat
    private var isForeground = false
    private var hasSeenActiveTrack = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        mediaSession = MediaSessionCompat(this, "MusicPlayerSession").apply {
            isActive = true
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    if (FlutterCommandBridge.isAttached) {
                        FlutterCommandBridge.sendRemoteCommand("togglePlayback")
                    } else {
                        player.togglePlaybackDirect()
                    }
                }
                override fun onPause() {
                    if (FlutterCommandBridge.isAttached) {
                        FlutterCommandBridge.sendRemoteCommand("togglePlayback")
                    } else {
                        player.togglePlaybackDirect()
                    }
                }
                override fun onSkipToNext() {
                    if (FlutterCommandBridge.isAttached) {
                        FlutterCommandBridge.sendRemoteCommand("next")
                    } else {
                        player.playNextNative()
                    }
                }
                override fun onSkipToPrevious() {
                    if (FlutterCommandBridge.isAttached) {
                        FlutterCommandBridge.sendRemoteCommand("previous")
                    } else {
                        player.playPreviousNative()
                    }
                }
                override fun onStop() {
                    if (FlutterCommandBridge.isAttached) {
                        FlutterCommandBridge.sendRemoteCommand("stop")
                    } else {
                        player.stopDirect()
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
            })
        }
        player.setStateObserver(::handlePlaybackState)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Let MediaButtonReceiver handle hardware media button events first
        // (headset single-click, Bluetooth A2DP, etc.)
        MediaButtonReceiver.handleIntent(mediaSession, intent)

        when (intent?.action) {
            ACTION_TOGGLE_PLAYBACK -> {
                // Route through Flutter so the state machine stays in sync.
                // Fall back to native toggle if the Flutter bridge is not yet attached
                // (e.g. app process was killed and only the service is running).
                if (FlutterCommandBridge.isAttached) {
                    FlutterCommandBridge.sendRemoteCommand("togglePlayback")
                } else {
                    player.togglePlaybackDirect()
                }
            }
            ACTION_PREVIOUS -> {
                if (FlutterCommandBridge.isAttached) {
                    FlutterCommandBridge.sendRemoteCommand("previous")
                } else {
                    player.playPreviousNative()
                }
            }
            ACTION_NEXT -> {
                if (FlutterCommandBridge.isAttached) {
                    FlutterCommandBridge.sendRemoteCommand("next")
                } else {
                    player.playNextNative()
                }
            }
            ACTION_STOP -> {
                if (FlutterCommandBridge.isAttached) {
                    FlutterCommandBridge.sendRemoteCommand("stop")
                } else {
                    player.stopDirect()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        player.setStateObserver(null)
        mediaSession.release()
        isForeground = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun handlePlaybackState(state: NativePlaybackState) {
        updateMediaSession(state)

        if (state.trackId != null) {
            hasSeenActiveTrack = true
        }

        if (state.trackId == null || state.status == "idle") {
            if (!hasSeenActiveTrack) {
                return
            }
            NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
            if (isForeground) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                isForeground = false
            }
            stopSelf()
            return
        }

        val notification = buildNotification(state)
        if (state.isPlaying || state.status == "loading") {
            if (isForeground) {
                NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
            } else {
                startForeground(NOTIFICATION_ID, notification)
                isForeground = true
            }
        } else {
            if (isForeground) {
                stopForeground(STOP_FOREGROUND_DETACH)
                isForeground = false
            }
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(state: NativePlaybackState): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(state.title)
            .setContentText(state.artist)
            .setSubText(state.album)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(state.artwork)
            .setContentIntent(appLaunchIntent())
            .setDeleteIntent(serviceActionIntent(ACTION_STOP, 40))
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(state.isPlaying || state.status == "loading")
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    serviceActionIntent(ACTION_PREVIOUS, 10),
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    if (state.isPlaying) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                    if (state.isPlaying) "Pause" else "Play",
                    serviceActionIntent(ACTION_TOGGLE_PLAYBACK, 20),
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    serviceActionIntent(ACTION_NEXT, 30),
                ),
            )
            .setStyle(
                MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .build()
    }

    private fun updateMediaSession(state: NativePlaybackState) {
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_STOP,
            )
            .setState(
                if (state.isPlaying) {
                    PlaybackStateCompat.STATE_PLAYING
                } else {
                    PlaybackStateCompat.STATE_PAUSED
                },
                state.positionMs.toLong(),
                if (state.isPlaying) 1f else 0f,
            )
            .build()
        mediaSession.setPlaybackState(playbackState)
        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, state.title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, state.artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, state.album)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, state.durationMs.toLong())
                .apply {
                    state.artwork?.let {
                        putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
                    }
                }
                .build(),
        )
    }

    private fun serviceActionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackNotificationService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    private fun appLaunchIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        launchIntent.putExtra("open_player", true)
        return PendingIntent.getActivity(
            this,
            50,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Music playback",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows playback controls for background music"
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun immutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    companion object {
        private const val CHANNEL_ID = "music_playback"
        private const val NOTIFICATION_ID = 2407
        private const val ACTION_TOGGLE_PLAYBACK =
            "com.aravindprojects.musicplayer.action.TOGGLE_PLAYBACK"
        private const val ACTION_PREVIOUS = "com.aravindprojects.musicplayer.action.PREVIOUS"
        private const val ACTION_NEXT = "com.aravindprojects.musicplayer.action.NEXT"
        private const val ACTION_STOP = "com.aravindprojects.musicplayer.action.STOP"

        fun ensureStarted(context: Context) {
            val intent = Intent(context, PlaybackNotificationService::class.java)
            context.startService(intent)
        }
    }
}
