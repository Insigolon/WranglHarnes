package com.wrangl.wrangl_native

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Stub recognition service. The Voice Interaction XML descriptor
 * (`res/xml/interaction_service.xml`) is required by the platform to point
 * `recognitionService` at a real [RecognitionService] subclass, even when —
 * like Wrangl — the app doesn't actually do speech recognition.
 *
 * Every callback fails immediately with `ERROR_RECOGNIZER_BUSY`, which is
 * benign: nothing in Wrangl ever invokes a `SpeechRecognizer` against us, so
 * this code path should not run in practice. It exists only to satisfy the
 * manifest-validation requirement.
 */
class WranglRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        listener?.error(SpeechRecognizer.ERROR_RECOGNIZER_BUSY)
    }

    override fun onCancel(listener: Callback?) {}

    override fun onStopListening(listener: Callback?) {}
}
