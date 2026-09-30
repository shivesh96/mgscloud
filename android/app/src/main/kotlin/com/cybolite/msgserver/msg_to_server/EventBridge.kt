package com.cybolite.msgserver.msg_to_server

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentLinkedQueue

object EventBridge {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_FLUTTER_PREFIX = "flutter.pending_events"
    private const val KEY_PENDING = "flutter_pending_events"
    private const val KEY_RAW = "pending_events"

    private val inMemoryQueue = ConcurrentLinkedQueue<Map<String, Any?>>()
    private var eventListener: ((Map<String, Any?>) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun setEventListener(listener: ((Map<String, Any?>) -> Unit)?) {
        synchronized(this) {
            this.eventListener = listener
            if (listener != null) {
                // Drain any in-memory queued events
                while (inMemoryQueue.isNotEmpty()) {
                    val event = inMemoryQueue.poll() ?: break
                    mainHandler.post {
                        listener.invoke(event)
                    }
                }
            }
        }
    }

    fun postEvent(context: Context, event: Map<String, Any?>) {
        synchronized(this) {
            persistEvent(context, event)
            val listener = eventListener
            if (listener != null) {
                mainHandler.post {
                    listener.invoke(event)
                }
            } else {
                inMemoryQueue.offer(event)
            }
        }
    }

    private fun persistEvent(context: Context, event: Map<String, Any?>) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existing = prefs.getString(KEY_FLUTTER_PREFIX, null)
                ?: prefs.getString(KEY_PENDING, null)
                ?: prefs.getString(KEY_RAW, "[]")
                ?: "[]"
            val jsonArray = JSONArray(existing)
            val obj = JSONObject(event)
            jsonArray.put(obj)
            val updatedJson = jsonArray.toString()
            prefs.edit()
                .putString(KEY_FLUTTER_PREFIX, updatedJson)
                .putString(KEY_PENDING, updatedJson)
                .putString(KEY_RAW, updatedJson)
                .apply()
        } catch (_: Exception) {
        }
    }

    fun drainPersistedEvents(context: Context): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        try {
            // First collect from in-memory queue
            while (inMemoryQueue.isNotEmpty()) {
                val ev = inMemoryQueue.poll()
                if (ev != null) result.add(ev)
            }

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            for (key in listOf(KEY_FLUTTER_PREFIX, KEY_PENDING, KEY_RAW)) {
                val existing = prefs.getString(key, null)
                if (!existing.isNullOrEmpty() && existing != "[]") {
                    try {
                        val jsonArray = JSONArray(existing)
                        for (i in 0 until jsonArray.length()) {
                            val obj = jsonArray.getJSONObject(i)
                            val map = mutableMapOf<String, Any?>()
                            val keys = obj.keys()
                            while (keys.hasNext()) {
                                val k = keys.next()
                                map[k] = obj.opt(k)
                            }
                            // Deduplicate by event_id if present
                            val eventId = map["event_id"]
                            val alreadyInResult = result.any { it["event_id"] == eventId }
                            if (!alreadyInResult) {
                                result.add(map)
                            }
                        }
                    } catch (_: Exception) {}
                    prefs.edit().remove(key).apply()
                }
            }
        } catch (_: Exception) {
        }
        return result
    }
}
