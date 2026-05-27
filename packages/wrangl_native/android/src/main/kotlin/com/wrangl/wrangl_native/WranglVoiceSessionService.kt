package com.wrangl.wrangl_native

import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/**
 * Factory the system calls whenever the assist gesture fires; returns a fresh
 * [WranglVoiceSession] per invocation. Sessions are short-lived: capture the
 * screenshot + structure, hand off to the bubble overlay, dismiss.
 */
class WranglVoiceSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession =
        WranglVoiceSession(this)
}
