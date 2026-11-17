package com.hermesagent.hermes_android

import android.app.Application
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter bridge for the embedded Hermes runtime. */
object HermesEngineChannel {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext as Application
        val controller = HermesEngineController.install(app)

        methodChannel = MethodChannel(messenger, HermesEngine.METHOD_CHANNEL).apply {
            setMethodCallHandler { call, result -> handle(controller, call, result) }
        }
        eventChannel = EventChannel(messenger, HermesEngine.EVENT_CHANNEL).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: ((HermesEngineController.Status) -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    listener = { status -> events?.success(status.toMap()) }
                    listener?.let(controller::addListener)
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let(controller::removeListener)
                    listener = null
                }
            })
        }
    }

    fun teardown() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }

    private fun handle(controller: HermesEngineController, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(controller.currentStatus().toMap())
            "apiKey" -> result.success(controller.apiKey())
            "prepare" -> {
                controller.prepare()
                result.success(true)
            }
            "start" -> {
                controller.start()
                result.success(true)
            }
            "stop" -> {
                controller.stop()
                result.success(true)
            }
            "logTail" -> result.success(controller.logTail(call.argument<Int>("maxLines") ?: 200))
            else -> result.notImplemented()
        }
    }

    private fun HermesEngineController.Status.toMap(): Map<String, Any?> = mapOf(
        "state" to state.name.lowercase(),
        "progress" to progress,
        "message" to message,
        "version" to version,
    )
}
