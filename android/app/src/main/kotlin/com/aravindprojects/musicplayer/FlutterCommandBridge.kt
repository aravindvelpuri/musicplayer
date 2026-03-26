package com.aravindprojects.musicplayer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object FlutterCommandBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var methodChannel: MethodChannel? = null

    fun attach(channel: MethodChannel) {
        methodChannel = channel
    }

    fun detach(channel: MethodChannel? = null) {
        if (channel == null || methodChannel === channel) {
            methodChannel = null
        }
    }

    fun sendRemoteCommand(command: String) {
        val channel = methodChannel ?: return
        mainHandler.post {
            channel.invokeMethod(
                "remoteCommand",
                mapOf("command" to command),
            )
        }
    }
}
