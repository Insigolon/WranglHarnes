package com.wrangl.wrangl_native

import android.service.voice.VoiceInteractionService

/**
 * System-bound entry point for the Assist API. The system instantiates this
 * the moment the user picks Wrangl as their default digital assistant in
 *   Settings → Apps → Default apps → Digital assistant app
 * and from then on routes the assist gesture (long-press home, pill-corner
 * swipe, power-button chord, etc.) through it.
 *
 * No logic lives here — the actual screenshot + assist-structure handling
 * happens in [WranglVoiceSession], which is constructed per-invocation by
 * [WranglVoiceSessionService].
 */
class WranglVoiceInteractionService : VoiceInteractionService()
