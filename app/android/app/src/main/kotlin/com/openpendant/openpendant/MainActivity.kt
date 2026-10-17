package com.openpendant.openpendant

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.CalendarContract
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val CALENDAR_CHANNEL = "com.openpendant.calendar"
    private val TAG = "KryptonCalendar"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "insertCalendarEvent" -> {
                    val title = call.argument<String>("title") ?: ""
                    val description = call.argument<String>("description") ?: ""
                    val startTime = call.argument<Long>("startTime") ?: System.currentTimeMillis()
                    val endTime = call.argument<Long>("endTime") ?: (startTime + 30 * 60 * 1000)

                    try {
                        val success = insertNativeCalendarEvent(title, description, startTime, endTime)
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error inserting calendar event", e)
                        result.error("CALENDAR_ERROR", e.message, null)
                    }
                }
                "openCalendarIntent" -> {
                    val title = call.argument<String>("title") ?: ""
                    val description = call.argument<String>("description") ?: ""
                    val startTime = call.argument<Long>("startTime") ?: System.currentTimeMillis()
                    val endTime = call.argument<Long>("endTime") ?: (startTime + 30 * 60 * 1000)

                    try {
                        val intent = Intent(Intent.ACTION_INSERT).apply {
                            data = CalendarContract.Events.CONTENT_URI
                            putExtra(CalendarContract.Events.TITLE, title)
                            putExtra(CalendarContract.Events.DESCRIPTION, description)
                            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startTime)
                            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime)
                            putExtra(CalendarContract.Events.HAS_ALARM, 1)
                            putExtra(CalendarContract.Reminders.MINUTES, 10)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening calendar intent", e)
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun insertNativeCalendarEvent(
        title: String,
        description: String,
        startTime: Long,
        endTime: Long
    ): Boolean {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
        )

        var calendarId: Long = -1L
        var selectedAccountName = ""
        var selectedAccountType = ""
        var bestScore = -1

        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex(CalendarContract.Calendars._ID)
            val primaryIndex = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
            val visibleIndex = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)
            val accountNameIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_NAME)
            val accountTypeIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_TYPE)
            val accessIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)

            while (cursor.moveToNext()) {
                val id = if (idIndex != -1) cursor.getLong(idIndex) else -1L
                val isPrimary = if (primaryIndex != -1) cursor.getInt(primaryIndex) == 1 else false
                val isVisible = if (visibleIndex != -1) cursor.getInt(visibleIndex) == 1 else true
                val accountName = if (accountNameIndex != -1) cursor.getString(accountNameIndex) ?: "" else ""
                val accountType = if (accountTypeIndex != -1) cursor.getString(accountTypeIndex) ?: "" else ""
                val accessLevel = if (accessIndex != -1) cursor.getInt(accessIndex) else 700

                // Only consider writable calendars (access level >= 500: contributor/owner)
                if (id == -1L || accessLevel < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) {
                    continue
                }

                // Score: Google account + visible gets highest priority for active sync and notifications
                var score = 1
                if (isVisible) score += 3
                if (accountType.equals("com.google", ignoreCase = true)) score += 10
                if (isPrimary) score += 5

                if (score > bestScore) {
                    bestScore = score
                    calendarId = id
                    selectedAccountName = accountName
                    selectedAccountType = accountType
                }
            }
        }

        if (calendarId == -1L) {
            Log.w(TAG, "No writable calendar found on device")
            return false
        }

        Log.d(TAG, "Using calendar ID: $calendarId, account: $selectedAccountName, type: $selectedAccountType")

        val eventValues = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.DTSTART, startTime)
            put(CalendarContract.Events.DTEND, endTime)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
            put(CalendarContract.Events.HAS_ALARM, 1)
            put(CalendarContract.Events.ALL_DAY, 0)
        }

        // Build URI with sync adapter params so Google Calendar syncs the event & reminders
        val baseEventUri = if (selectedAccountName.isNotEmpty() && selectedAccountType.isNotEmpty()) {
            CalendarContract.Events.CONTENT_URI.buildUpon()
                .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, selectedAccountName)
                .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, selectedAccountType)
                .build()
        } else {
            CalendarContract.Events.CONTENT_URI
        }

        var eventUri = try {
            contentResolver.insert(baseEventUri, eventValues)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to insert event with sync adapter URI, trying fallback: ${e.message}")
            null
        }

        if (eventUri == null) {
            eventUri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, eventValues)
                ?: return false
        }

        val eventId = try {
            ContentUris.parseId(eventUri)
        } catch (_: Exception) {
            eventUri.lastPathSegment?.toLongOrNull()
        }

        if (eventId != null) {
            val baseReminderUri = if (selectedAccountName.isNotEmpty() && selectedAccountType.isNotEmpty()) {
                CalendarContract.Reminders.CONTENT_URI.buildUpon()
                    .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, selectedAccountName)
                    .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, selectedAccountType)
                    .build()
            } else {
                CalendarContract.Reminders.CONTENT_URI
            }

            // Add standard Google Calendar reminders: 10 minutes before and 0 minutes (at event time)
            val reminderMinutes = intArrayOf(10, 0)
            for (min in reminderMinutes) {
                val reminderValues = ContentValues().apply {
                    put(CalendarContract.Reminders.EVENT_ID, eventId)
                    put(CalendarContract.Reminders.MINUTES, min)
                    put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                }

                var rUri: Uri? = null
                try {
                    rUri = contentResolver.insert(baseReminderUri, reminderValues)
                } catch (e: Exception) {
                    Log.w(TAG, "Sync adapter reminder insert failed for $min min: ${e.message}")
                }
                if (rUri == null) {
                    try {
                        rUri = contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
                    } catch (e: Exception) {
                        Log.e(TAG, "Standard reminder insert failed for $min min: ${e.message}")
                    }
                }
                Log.d(TAG, "Inserted reminder ($min min) -> $rUri")
            }
        }

        // Trigger immediate Google Calendar account sync so notifications appear in Google Calendar app
        if (selectedAccountName.isNotEmpty() && selectedAccountType.equals("com.google", ignoreCase = true)) {
            try {
                val account = android.accounts.Account(selectedAccountName, selectedAccountType)
                val bundle = Bundle().apply {
                    putBoolean(android.content.ContentResolver.SYNC_EXTRAS_MANUAL, true)
                    putBoolean(android.content.ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
                }
                android.content.ContentResolver.requestSync(account, CalendarContract.AUTHORITY, bundle)
                Log.d(TAG, "Requested sync for $selectedAccountName")
            } catch (e: Exception) {
                Log.e(TAG, "Error requesting calendar sync", e)
            }
        }

        return true
    }
}
