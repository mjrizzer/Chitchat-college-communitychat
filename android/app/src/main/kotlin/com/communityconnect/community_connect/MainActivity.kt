package com.communityconnect.community_connect

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blocks Android screenshots, normal screen recordings and recents previews.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
