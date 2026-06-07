package com.prplegryn.livocut

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import kotlin.math.max

class NativeVideoPlayerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val path = params?.get("path") as? String ?: ""
        return NativeVideoPlayerView(context, messenger, viewId, path)
    }

    companion object {
        const val VIEW_TYPE = "livocut/native_video_player"
    }
}

@OptIn(UnstableApi::class)
private class NativeVideoPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    path: String,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val player: ExoPlayer = ExoPlayer.Builder(context).build()
    private val playerView: PlayerView = PlayerView(context)
    private val channel = MethodChannel(messenger, "livocut/native_video_player_$viewId")
    private var released = false

    init {
        playerView.setBackgroundColor(Color.BLACK)
        playerView.useController = false
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        playerView.player = player

        channel.setMethodCallHandler(this)

        if (path.isNotBlank()) {
            player.setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
            player.prepare()
        }
    }

    override fun getView(): View = playerView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (released) {
            result.success(if (call.method == "getState") emptyState() else null)
            return
        }

        when (call.method) {
            "getState" -> result.success(state())
            "play" -> {
                player.play()
                result.success(state())
            }
            "pause" -> {
                player.pause()
                result.success(state())
            }
            "seekTo" -> {
                player.setSeekParameters(SeekParameters.EXACT)
                player.seekTo(positionArg(call))
                result.success(state())
            }
            "beginScrub" -> {
                player.pause()
                player.setSeekParameters(SeekParameters.CLOSEST_SYNC)
                player.setScrubbingModeEnabled(true)
                result.success(state())
            }
            "scrubTo" -> {
                player.setScrubbingModeEnabled(true)
                player.seekTo(positionArg(call))
                result.success(state())
            }
            "endScrub" -> {
                val position = positionArg(call)
                val shouldPlay = call.argument<Boolean>("play") ?: false
                player.setScrubbingModeEnabled(false)
                player.setSeekParameters(SeekParameters.EXACT)
                player.seekTo(position)
                if (shouldPlay) {
                    player.play()
                } else {
                    player.pause()
                }
                result.success(state())
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun positionArg(call: MethodCall): Long {
        return max(call.argument<Number>("position")?.toLong() ?: 0L, 0L)
    }

    private fun state(): Map<String, Any> {
        val duration = player.duration.takeUnless { it == C.TIME_UNSET } ?: 0L
        val position = player.currentPosition.takeUnless { it == C.TIME_UNSET } ?: 0L
        val videoSize = player.videoSize
        val aspectRatio = if (videoSize.width > 0 && videoSize.height > 0) {
            videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
        } else {
            0f
        }

        return mapOf(
            "duration" to max(duration, 0L),
            "position" to max(position, 0L),
            "isPlaying" to player.isPlaying,
            "isReady" to (player.playbackState != Player.STATE_IDLE),
            "aspectRatio" to aspectRatio.toDouble(),
        )
    }

    private fun emptyState(): Map<String, Any> {
        return mapOf(
            "duration" to 0L,
            "position" to 0L,
            "isPlaying" to false,
            "isReady" to false,
            "aspectRatio" to 0.0,
        )
    }

    override fun dispose() {
        release()
    }

    private fun release() {
        if (released) {
            return
        }
        released = true
        channel.setMethodCallHandler(null)
        playerView.player = null
        player.release()
    }
}
