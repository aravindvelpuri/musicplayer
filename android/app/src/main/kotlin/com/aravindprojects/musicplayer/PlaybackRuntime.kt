package com.aravindprojects.musicplayer

import android.content.Context

object PlaybackRuntime {
    @Volatile
    private var playerInstance: LocalAudioPlayer? = null

    fun player(context: Context): LocalAudioPlayer {
        return playerInstance ?: synchronized(this) {
            playerInstance ?: LocalAudioPlayer(context.applicationContext).also { player ->
                playerInstance = player
            }
        }
    }

    fun dispose() {
        playerInstance?.dispose()
        playerInstance = null
    }
}
