package com.cybolite.msgserver.msg_to_server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.annotation.Keep
import java.security.MessageDigest

@Keep
class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "MessageCloud:SmsWakeLock"
            )
            wakeLock?.acquire(10 * 1000L)
        } catch (_: Exception) {}

        try {
            var messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) {
                val pdus = intent.extras?.get("pdus") as? Array<*>
                val format = intent.getStringExtra("format")
                if (pdus != null && pdus.isNotEmpty()) {
                    val list = mutableListOf<android.telephony.SmsMessage>()
                    for (pdu in pdus) {
                        val bytes = pdu as? ByteArray ?: continue
                        val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && format != null) {
                            android.telephony.SmsMessage.createFromPdu(bytes, format)
                        } else {
                            @Suppress("DEPRECATION")
                            android.telephony.SmsMessage.createFromPdu(bytes)
                        }
                        if (sms != null) list.add(sms)
                    }
                    if (list.isNotEmpty()) messages = list.toTypedArray()
                }
            }
            if (messages.isNullOrEmpty()) return

            val sender = messages[0].displayOriginatingAddress ?: messages[0].originatingAddress ?: "Unknown"
            val timestamp = messages[0].timestampMillis

            val bodyBuilder = StringBuilder()
            for (sms in messages) {
                bodyBuilder.append(sms.displayMessageBody ?: sms.messageBody ?: "")
            }
            val messageBody = bodyBuilder.toString()

            // Detect SIM slot / subscription ID from intent extras across various OEMs
            // (Samsung, Xiaomi/MIUI, MediaTek, Qualcomm, Huawei, OnePlus)
            var subId = getIntFromExtras(
                intent,
                "subscription",
                "android.telephony.extra.SUBSCRIPTION_INDEX",
                "sub_id",
                "simId",
                "sim_id",
                "extra_subscription_index"
            )

            var slotIndex = getIntFromExtras(
                intent,
                "slot",
                "simSlot",
                "sim_slot",
                "slot_id",
                "slot_index",
                "android.telephony.extra.SLOT_INDEX",
                "phone",
                "com.android.phone.extra.slot",
                "sim_index"
            )

            val subManager = try {
                context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            } catch (_: Exception) {
                null
            }

            val activeList = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    subManager?.activeSubscriptionInfoList
                } else null
            } catch (_: Exception) {
                null
            }

            if (!activeList.isNullOrEmpty()) {
                if (activeList.size == 1) {
                    // SINGLE SIM DEVICE:
                    // There is only ONE active SIM installed in this device.
                    // Regardless of whether OEM extras reported subId=1, sub_id=1,
                    // slot=0 or slot=1, this SMS physically arrived on this sole SIM.
                    subId = activeList[0].subscriptionId
                    slotIndex = activeList[0].simSlotIndex
                } else {
                    // MULTI-SIM DEVICE:
                    // 1. Direct match by subscriptionId
                    var matched = if (subId != -1) activeList.firstOrNull { it.subscriptionId == subId } else null

                    // 2. Direct match by 0-based simSlotIndex
                    if (matched == null && slotIndex != -1) {
                        matched = activeList.firstOrNull { it.simSlotIndex == slotIndex }
                    }

                    // 3. OEM 1-based subId mapping (subId 1 -> slot 0, subId 2 -> slot 1)
                    if (matched == null && subId in 1..activeList.size) {
                        matched = activeList.firstOrNull { it.simSlotIndex == subId - 1 }
                    }

                    // 4. OEM 1-based slotIndex mapping (slotIndex 1 -> slot 0)
                    if (matched == null && slotIndex in 1..activeList.size) {
                        matched = activeList.firstOrNull { it.simSlotIndex == slotIndex - 1 }
                    }

                    // 5. Default SMS subscription fallback
                    if (matched == null) {
                        val defaultSmsSubId = try {
                            SubscriptionManager.getDefaultSmsSubscriptionId()
                        } catch (_: Exception) { -1 }
                        if (defaultSmsSubId != -1) {
                            matched = activeList.firstOrNull { it.subscriptionId == defaultSmsSubId }
                        }
                    }

                    // 6. First active SIM fallback
                    matched = matched ?: activeList[0]

                    subId = matched.subscriptionId
                    slotIndex = matched.simSlotIndex
                }
            } else {
                // SubscriptionManager fallback when activeList is unavailable
                if (slotIndex == -1 && subId != -1) {
                    try {
                        val info = subManager?.getActiveSubscriptionInfo(subId)
                        if (info != null) {
                            slotIndex = info.simSlotIndex
                        }
                    } catch (_: Exception) {}
                }

                if (subId == -1 && slotIndex != -1) {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                            val info = subManager?.getActiveSubscriptionInfoForSimSlotIndex(slotIndex)
                            if (info != null) {
                                subId = info.subscriptionId
                            }
                        }
                    } catch (_: Exception) {}
                }

                if (subId == -1) {
                    try {
                        val defaultSmsSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                        if (defaultSmsSubId != -1) {
                            subId = defaultSmsSubId
                            val info = subManager?.getActiveSubscriptionInfo(subId)
                            if (info != null && slotIndex == -1) {
                                slotIndex = info.simSlotIndex
                            }
                        }
                    } catch (_: Exception) {}
                }
            }

            val effectiveSlot = if (slotIndex >= 0) slotIndex else 0

            val serviceCenter = try {
                messages[0].serviceCenterAddress ?: ""
            } catch (_: Exception) {
                ""
            }

            val effectiveSender = if (sender.isNotBlank()) sender else "Unknown"

            Log.i("MessageCloud", "SmsBroadcastReceiver: SMS received from $effectiveSender, subId: $subId, slot: $effectiveSlot, len: ${messageBody.length}")

            // Android may redeliver a broadcast and EventBridge can be drained
            // after process restart. This identity is based on the actual SMS
            // envelope, not its OTP/body alone, so a later legitimate message
            // with the same code still has a different timestamp identity.
            val eventIdentity = listOf("sms", effectiveSender, timestamp, subId, effectiveSlot, serviceCenter, messageBody).joinToString("|")
            val eventMap = mapOf<String, Any?>(
                "event_id" to sha256(eventIdentity),
                "event_type" to "sms_received",
                "source" to "sms",
                "sender" to effectiveSender,
                "title" to effectiveSender,
                "message" to messageBody,
                "service_center" to serviceCenter,
                "timestamp" to timestamp,
                "sim_slot" to effectiveSlot,
                "subscription_id" to subId
            )

            EventBridge.postEvent(context, eventMap)
        } catch (_: Exception) {
        }
    }

    private fun getIntFromExtras(intent: Intent, vararg keys: String): Int {
        val extras = intent.extras ?: return -1
        for (key in keys) {
            if (!extras.containsKey(key)) continue
            val value = extras.get(key) ?: continue
            when (value) {
                is Number -> return value.toInt()
                is String -> {
                    val parsed = value.toIntOrNull()
                    if (parsed != null) return parsed
                }
            }
        }
        return -1
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
