package com.prplegryn.livocut

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                NativeVideoPlayerViewFactory.VIEW_TYPE,
                NativeVideoPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}
