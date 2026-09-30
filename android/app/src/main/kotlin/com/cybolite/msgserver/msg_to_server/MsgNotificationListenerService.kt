package com.cybolite.msgserver.msg_to_server

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.UUID

class MsgNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        try {
            val packageName = sbn.packageName ?: return
            val notification = sbn.notification ?: return

            if (packageName == applicationContext.packageName) return

            // Skip ongoing / non-clearable / foreground notifications from other apps
            val flags = notification.flags
            if ((flags and Notification.FLAG_ONGOING_EVENT) != 0 ||
                (flags and Notification.FLAG_FOREGROUND_SERVICE) != 0) {
                return
            }

            val extras = notification.extras ?: return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""

            // 1. Try BigText
            var message = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            
            // 2. Try Standard Text
            if (message.isNullOrBlank()) {
                message = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
            }

            var contentHidden = false

            // 3. Extract from MessagingStyle (e.g. Google Messages, WhatsApp, Telegram)
            val isHiddenPlaceholder = message?.lowercase()?.let {
                it == "new message" || it == "1 new message" || it.matches(Regex("\\d+\\s+new messages"))
            } ?: false

            if (message.isNullOrBlank() || isHiddenPlaceholder) {
                val messagesArray = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
                if (messagesArray != null && messagesArray.isNotEmpty()) {
                    for (i in messagesArray.indices.reversed()) {
                        val msgBundle = messagesArray[i] as? android.os.Bundle
                        val text = msgBundle?.getCharSequence("text")?.toString()?.trim()
                        if (!text.isNullOrBlank()) {
                            message = text
                            break
                        }
                    }
                }
            }

            // 4. Extract from InboxStyle lines (e.g. multi-message notifications)
            if (message.isNullOrBlank()) {
                val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                if (lines != null && lines.isNotEmpty()) {
                    for (i in lines.indices.reversed()) {
                        val line = lines[i]?.toString()?.trim()
                        if (!line.isNullOrBlank()) {
                            message = line
                            break
                        }
                    }
                }
            }

            // 5. Try SubText
            if (message.isNullOrBlank()) {
                message = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
            }

            // 6. Try TickerText
            if (message.isNullOrBlank()) {
                message = notification.tickerText?.toString()?.trim()
            }

            if (message.isNullOrBlank()) {
                return
            }

            // Filter out internal/transient messages from WhatsApp
            val lowerMsg = message.lowercase()
            if (lowerMsg.contains("checking for new messages") ||
                lowerMsg.contains("whatsapp web is currently active") ||
                lowerMsg.contains("backup in progress") ||
                lowerMsg.contains("waiting for this message")) {
                return
            }

            // Determine if source is WhatsApp (standard, business, or clone)
            val isWhatsApp = packageName == "com.whatsapp" ||
                    packageName == "com.whatsapp.w4b" ||
                    packageName.contains("whatsapp") ||
                    packageName.contains("dual") ||
                    packageName.contains("parallel") ||
                    packageName.contains("clone")

            val isSmsApp = packageName == "com.google.android.apps.messaging" ||
                    packageName == "com.android.mms" ||
                    packageName == "com.samsung.android.messaging" ||
                    packageName == "com.xiaomi.xmsf" ||
                    packageName.contains("messaging") ||
                    packageName.contains(".mms")

            val isEmailApp = packageName == "com.google.android.gm" ||
                    packageName == "com.microsoft.office.outlook" ||
                    packageName == "com.google.android.apps.inbox" ||
                    packageName.contains("email") ||
                    packageName.contains(".mail")

            val source = when {
                isWhatsApp -> "whatsapp"
                isSmsApp -> "sms"
                isEmailApp -> "email"
                else -> packageName
            }

            val eventType = when {
                isSmsApp -> "sms_received"
                isWhatsApp -> "notification_received"
                isEmailApp -> "email_received"
                else -> "notification_received"
            }

            val userProfileId = sbn.user?.toString() ?: "0"

            var subId: Int? = null
            if (extras.containsKey("android.subId")) subId = extras.getInt("android.subId")
            if (subId == null && extras.containsKey("subscription")) subId = extras.getInt("subscription")
            var simSlot: Int? = null
            if (extras.containsKey("simSlot")) simSlot = extras.getInt("simSlot")
            val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()

            // Sender is primarily the title (contact name / phone number), or fallback to subText / bundle sender
            var sender = title
            if (sender.isBlank() && !subText.isNullOrBlank()) {
                sender = subText
            }
            if (sender.isBlank()) {
                val messagesArray = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
                if (messagesArray != null && messagesArray.isNotEmpty()) {
                    for (i in messagesArray.indices.reversed()) {
                        val msgBundle = messagesArray[i] as? android.os.Bundle
                        val senderName = msgBundle?.getCharSequence("sender")?.toString()?.trim()
                        if (!senderName.isNullOrBlank()) {
                            sender = senderName
                            break
                        }
                    }
                }
            }
            if (sender.isBlank()) {
                sender = "Unknown"
            }

            // Strip "Sender: Message" prefix if message was extracted from tickerText
            if (sender != "Unknown" && message.startsWith("$sender: ")) {
                message = message.substring(sender.length + 2).trim()
            }

            val eventMap = mutableMapOf<String, Any?>(
                "event_id" to UUID.randomUUID().toString(),
                "event_type" to eventType,
                "source" to source,
                "package_name" to packageName,
                "sender" to sender,
                "title" to title.ifBlank { sender },
                "message" to message,
                "timestamp" to sbn.postTime,
                "user_profile_id" to userProfileId,
                "is_clone" to (packageName != "com.whatsapp" && packageName != "com.whatsapp.w4b"),
                "content_hidden" to contentHidden
            )
            if (subId != null && subId >= 0) eventMap["subscription_id"] = subId
            if (simSlot != null && simSlot >= 0) eventMap["sim_slot"] = simSlot
            if (!subText.isNullOrBlank()) eventMap["sub_text"] = subText

            EventBridge.postEvent(this, eventMap)
        } catch (_: Exception) {
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed on notification removal
    }
}
