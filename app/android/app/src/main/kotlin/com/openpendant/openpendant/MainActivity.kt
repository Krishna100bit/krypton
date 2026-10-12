package com.openpendant.openpendant

import android.content.ContentValues
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val CALENDAR_CHANNEL = "com.openpendant.calendar"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "insertCalendarEvent") {
                val title = call.argument<String>("title") ?: ""
                val description = call.argument<String>("description") ?: ""
                val startTime = call.argument<Long>("startTime") ?: System.currentTimeMillis()
                val endTime = call.argument<Long>("endTime") ?: (startTime + 30 * 60 * 1000)

                try {
                    val success = insertNativeCalendarEvent(title, description, startTime, endTime)
                    result.success(success)
                } catch (e: Exception) {
                    result.error("CALENDAR_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
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
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
        )

        var calendarId: Long = -1L
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
            val accountTypeIndex = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_TYPE)
            val accessIndex = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)

            while (cursor.moveToNext()) {
                val id = if (idIndex != -1) cursor.getLong(idIndex) else -1L
                val isPrimary = if (primaryIndex != -1) cursor.getInt(primaryIndex) == 1 else false
                val isVisible = if (visibleIndex != -1) cursor.getInt(visibleIndex) == 1 else true
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
                }
            }
        }

        if (calendarId == -1L) {
            return false
        }

        val eventValues = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.DTSTART, startTime)
            put(CalendarContract.Events.DTEND, endTime)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
            put(CalendarContract.Events.HAS_ALARM, 1)
        }

        val eventUri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, eventValues)
            ?: return false

        // Add notification alerts: both at the time of the event (0 min) and advance notice (15 min)
        val eventId = try {
            android.content.ContentUris.parseId(eventUri)
        } catch (_: Exception) {
            eventUri.lastPathSegment?.toLongOrNull()
        }

        if (eventId != null) {
            // 1. Alert at the exact time of the event (0 minutes)
            val onTimeReminder = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, 0)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            try {
                contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, onTimeReminder)
            } catch (_: Exception) {}

            // 2. Alert 15 minutes before the event
            val advanceReminder = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, 15)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            try {
                contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, advanceReminder)
            } catch (_: Exception) {}
        }

        return true
    }
}
