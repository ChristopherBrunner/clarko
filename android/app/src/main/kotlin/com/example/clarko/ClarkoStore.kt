package com.example.clarko

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Native view of the app's canonical state.
 *
 * The Flutter side persists the dose schedule and the taken-log as JSON via the
 * shared_preferences plugin, which keeps them in the "FlutterSharedPreferences"
 * file under "flutter."-prefixed keys (see lib/services/storage.dart). The home
 * widget reads — and, for check taps, writes — that very same data, so there is
 * no second copy of "what's taken today" that could drift away from the app.
 */
internal object ClarkoStore {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_SCHEDULE = "flutter.schedule"
    private const val KEY_LOG = "flutter.log"

    class Dose(
        val id: String,
        val label: String,
        val hour: Int,
        val minute: Int,
        val enabled: Boolean
    ) {
        /** Evening/night doses get the moon icon (same rule as the app). */
        val isNight: Boolean get() = hour >= 18 || hour < 5
    }

    /** Which doses were taken on which day: `yyyy-MM-dd` -> array of dose ids. */
    class TakenLog(private val json: JSONObject) {
        fun isTaken(doseId: String, dayKey: String): Boolean {
            val ids = json.optJSONArray(dayKey) ?: return false
            for (i in 0 until ids.length()) {
                if (ids.optString(i) == doseId) return true
            }
            return false
        }
    }

    /** A Clarko day starts at 03:00, not midnight — mirrors `day.dart`. */
    const val DAY_START_HOUR = 3

    /** Complete days after a bridged miss before the streak safe works again. */
    private const val SAFE_RECHARGE_DAYS = 6

    /** The Clarko day it is right now (mirrors `clarkoDay` in Dart). */
    fun today(): Calendar = Calendar.getInstance().apply {
        if (get(Calendar.HOUR_OF_DAY) < DAY_START_HOUR) add(Calendar.DAY_OF_YEAR, -1)
    }

    /** Calendar-day key matching `MedicationLog.dateKey` in Dart, e.g. "2026-06-22". */
    fun dayKey(day: Calendar): String = String.format(
        Locale.US,
        "%04d-%02d-%02d",
        day.get(Calendar.YEAR),
        day.get(Calendar.MONTH) + 1,
        day.get(Calendar.DAY_OF_MONTH)
    )

    /**
     * The schedule the app falls back to until one has been saved (mirrors
     * `Dose.defaults()` in Dart). The app persists it on its next start; until
     * then — e.g. right after an update, before the app was opened — the widget
     * must not go blank.
     */
    private val DEFAULT_DOSES = listOf(
        Dose("morning", "Morning", 8, 0, true),
        Dose("night", "Night", 20, 0, true)
    )

    fun loadDoses(context: Context): List<Dose> {
        val raw = prefs(context).getString(KEY_SCHEDULE, null) ?: return DEFAULT_DOSES
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val dose = array.getJSONObject(i)
                Dose(
                    id = dose.getString("id"),
                    label = dose.optString("label"),
                    hour = dose.optInt("hour"),
                    minute = dose.optInt("minute"),
                    enabled = dose.optBoolean("enabled", true)
                )
            }
        } catch (e: JSONException) {
            emptyList()
        }
    }

    fun loadLog(context: Context): TakenLog = TakenLog(loadLogJson(context) ?: JSONObject())

    /** Marks [doseId] taken / not taken on [dayKey] and persists the log. */
    fun setTaken(context: Context, doseId: String, dayKey: String, taken: Boolean) {
        // An unreadable log is left alone rather than overwritten with a fresh one.
        val log = loadLogJson(context) ?: return
        val ids = JSONArray()
        log.optJSONArray(dayKey)?.let { old ->
            for (i in 0 until old.length()) {
                val id = old.optString(i)
                if (id != doseId) ids.put(id)
            }
        }
        if (taken) ids.put(doseId)
        if (ids.length() == 0) log.remove(dayKey) else log.put(dayKey, ids)
        prefs(context).edit().putString(KEY_LOG, log.toString()).commit()
    }

    /**
     * The streak ending [today], with the "streak safe": one missed day is
     * bridged (not counted, but not a reset); two in a row end the streak, and
     * a second miss is only bridged after [SAFE_RECHARGE_DAYS] complete days.
     * Line-for-line mirror of `MedicationLog.streak` in Dart — keep in sync.
     */
    fun streak(doses: List<Dose>, log: TakenLog, today: Calendar): Int {
        val enabled = doses.filter { it.enabled }
        if (enabled.isEmpty()) return 0
        fun isComplete(day: Calendar): Boolean {
            val key = dayKey(day)
            return enabled.all { log.isTaken(it.id, key) }
        }

        val cursor = today.clone() as Calendar
        var days = if (isComplete(cursor)) 1 else 0
        var run = days
        var pendingMiss = false
        var safeUsed = false
        for (i in 0 until 4000) {
            cursor.add(Calendar.DAY_OF_YEAR, -1)
            if (isComplete(cursor)) {
                if (pendingMiss) {
                    safeUsed = true
                    pendingMiss = false
                    run = 0
                }
                days++
                run++
            } else {
                if (pendingMiss || (safeUsed && run < SAFE_RECHARGE_DAYS)) break
                pendingMiss = true
            }
        }
        return days
    }

    /** The streak's stage emoji — mirrors `StreakStage.stages` in Dart. */
    fun streakEmoji(days: Int): String = when {
        days >= 1000 -> "\uD83D\uDC31" // cat face
        days >= 900 -> "\uD83D\uDC10" // goat
        days >= 730 -> "\uD83C\uDF0C" // milky way
        days >= 500 -> "\uD83E\uDD84" // unicorn
        days >= 365 -> "\uD83D\uDC51" // crown
        days >= 250 -> "\uD83D\uDC09" // dragon
        days >= 150 -> "\uD83C\uDFC6" // trophy
        days >= 100 -> "\uD83D\uDC8E" // gem
        days >= 60 -> "\u26A1" // high voltage
        days >= 30 -> "\uD83C\uDF1F" // glowing star
        days >= 7 -> "\uD83D\uDE80" // rocket
        days >= 3 -> "\uD83D\uDD25" // fire
        else -> "\uD83C\uDF31" // seedling
    }

    /** Mirrors `NotificationService.notificationId` in Dart. */
    fun reminderNotificationId(doseId: String): Int {
        var hash = 0
        for (char in doseId) {
            hash = (hash * 31 + char.code) and 0x7fffffff
        }
        return hash % 100000
    }

    /** The stored log; empty if nothing was saved yet, null if it can't be parsed. */
    private fun loadLogJson(context: Context): JSONObject? {
        val raw = prefs(context).getString(KEY_LOG, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (e: JSONException) {
            null
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
