package com.cybolite.msgserver.msg_to_server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager
import java.security.MessageDigest

class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) return

            val sender = messages[0].displayOriginatingAddress ?: messages[0].originatingAddress ?: "Unknown"
            val timestamp = messages[0].timestampMillis

            val bodyBuilder = StringBuilder()
            for (sms in messages) {
                bodyBuilder.append(sms.displayMessageBody ?: sms.messageBody ?: "")
            }
            val messageBody = bodyBuilder.toString()

            // Detect SIM slot / subscription ID from intent extras
            var subId = intent.getIntExtra("subscription", -1)
            if (subId == -1) {
                subId = intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", -1)
            }
            if (subId == -1) {
                subId = intent.getIntExtra("simId", -1)
            }

            var slotIndex = intent.getIntExtra("slot", -1)
            if (slotIndex == -1) {
                slotIndex = intent.getIntExtra("simSlot", -1)
            }

            // Fallback lookup using SubscriptionManager if subId exists
            if (subId == -1) {
                try {
                    val subManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                    val defaultSmsSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                    if (defaultSmsSubId != -1) {
                        subId = defaultSmsSubId
                        val info = subManager?.getActiveSubscriptionInfo(subId)
                        if (info != null && slotIndex == -1) {
                            slotIndex = info.simSlotIndex
                        }
                    }
                } catch (_: Exception) {
                }
            }

            if (slotIndex == -1 && subId != -1) {
                try {
                    val subManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                    val info = subManager?.getActiveSubscriptionInfo(subId)
                    if (info != null) {
                        slotIndex = info.simSlotIndex
                    }
                } catch (_: Exception) {
                }
            }

            val serviceCenter = try {
                messages[0].serviceCenterAddress ?: ""
            } catch (_: Exception) {
                ""
            }

            val effectiveSender = if (sender.isNotBlank()) sender else "Unknown"

            // Android may redeliver a broadcast and EventBridge can be drained
            // after process restart. This identity is based on the actual SMS
            // envelope, not its OTP/body alone, so a later legitimate message
            // with the same code still has a different timestamp identity.
            val eventIdentity = listOf("sms", effectiveSender, timestamp, subId, slotIndex, serviceCenter, messageBody).joinToString("|")
            val eventMap = mapOf<String, Any?>(
                "event_id" to sha256(eventIdentity),
                "event_type" to "sms_received",
                "source" to "sms",
                "sender" to effectiveSender,
                "title" to effectiveSender,
                "message" to messageBody,
                "service_center" to serviceCenter,
                "timestamp" to timestamp,
                "sim_slot" to if (slotIndex >= 0) slotIndex else 0,
                "subscription_id" to subId
            )

            EventBridge.postEvent(context, eventMap)
        } catch (_: Exception) {
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
