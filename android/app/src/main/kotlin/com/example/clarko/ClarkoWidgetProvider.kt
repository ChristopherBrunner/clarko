package com.example.clarko

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Locale

/**
 * Home-screen widget showing today's doses and the current streak.
 *
 * Every render is computed from the app's canonical schedule + log (see
 * [ClarkoStore]) for the *current* calendar day, so the widget can never hold a
 * stale "taken" state of its own. It is re-rendered whenever the app changes
 * something, when a check is tapped, when the clock/timezone changes, and by an
 * alarm at 03:00 — when a new Clarko day starts — so the checks reset then.
 *
 * Taps on a dose check are handled entirely natively: the log is updated in
 * place and all widgets refresh immediately, with no Flutter engine start-up.
 *
 * Adapts to its size: reminder times hide when narrow; the header hides and
 * rows shrink when short, so it works from a tall 3x2 down to a compact 2x1.
 */
open class ClarkoWidgetProvider : HomeWidgetProvider() {

    companion object {
        /** home_widget's store; only the app's light/dark choice lives here. */
        private const val WIDGET_PREFS = "HomeWidgetPreferences"

        private const val ACTION_SET_TAKEN = "com.example.clarko.action.SET_TAKEN"
        private const val ACTION_REFRESH = "com.example.clarko.action.REFRESH_WIDGETS"

        /** Tap action of widgets rendered by older app versions. */
        private const val ACTION_LEGACY_TOGGLE = "com.example.clarko.action.TOGGLE_DOSE"

        private const val EXTRA_DOSE_ID = "doseId"
        private const val EXTRA_DAY = "day"
        private const val EXTRA_TAKEN = "taken"

        private const val MAX_DOSES = 4
        private const val REQUEST_MIDNIGHT_REFRESH = 100
        private const val INEXACT_WINDOW_MS = 10 * 60 * 1000L

        private val PROVIDERS = arrayOf(
            ClarkoWidgetProvider::class.java,
            ClarkoWidgetWideProvider::class.java,
            ClarkoWidgetSmallProvider::class.java,
            ClarkoWidgetTinyProvider::class.java,
            ClarkoWidgetStreakProvider::class.java
        )
    }

    /** One dose line as shown today. */
    private class DoseRow(
        val id: String,
        val label: String,
        val time: String,
        val night: Boolean,
        val taken: Boolean
    )

    /** Everything a render needs, resolved once for the current day. */
    private class WidgetState(
        val day: String,
        val dark: Boolean,
        val streak: Int,
        val rows: List<DoseRow>
    )

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SET_TAKEN -> {
                val doseId = intent.getStringExtra(EXTRA_DOSE_ID)
                val today = ClarkoStore.dayKey(ClarkoStore.today())
                // Only act on a tap made against today's state. If the widget was
                // still showing an earlier day (e.g. the midnight refresh hasn't
                // been delivered yet), just redraw so the user sees the real
                // state instead of silently changing something they didn't see.
                if (!doseId.isNullOrEmpty() && intent.getStringExtra(EXTRA_DAY) == today) {
                    val taken = intent.getBooleanExtra(EXTRA_TAKEN, true)
                    ClarkoStore.setTaken(context, doseId, today, taken)
                    if (taken) dismissReminder(context, doseId)
                }
                refreshAll(context)
            }

            AppWidgetManager.ACTION_APPWIDGET_UPDATE,
            ACTION_REFRESH,
            ACTION_LEGACY_TOGGLE,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> refreshAll(context)

            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) = refreshAll(context)

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) = refreshAll(context)

    /** Last widget of this kind removed: lets the midnight alarm wind down. */
    override fun onDisabled(context: Context) = refreshAll(context)

    /**
     * Redraws every Clarko widget (all size variants) from the canonical state.
     * Always all of them at once: the check-tap intents are shared between
     * widgets, so they must never be newer than what a widget displays.
     */
    private fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val state = loadState(context)
        var widgetCount = 0
        for (cls in PROVIDERS) {
            // Pre-Android-12 fallback only: the 1x1 provider forces checks-only.
            val forceMini = cls == ClarkoWidgetTinyProvider::class.java
            for (id in manager.getAppWidgetIds(ComponentName(context, cls))) {
                manager.updateAppWidget(
                    id,
                    if (cls == ClarkoWidgetStreakProvider::class.java) renderStreak(context, state)
                    else renderViews(context, state, manager.getAppWidgetOptions(id), forceMini)
                )
                widgetCount++
            }
        }
        scheduleMidnightRefresh(context, enabled = widgetCount > 0)
    }

    private fun loadState(context: Context): WidgetState {
        val now = ClarkoStore.today()
        val day = ClarkoStore.dayKey(now)
        val doses = ClarkoStore.loadDoses(context)
        val log = ClarkoStore.loadLog(context)
        val rows = doses.filter { it.enabled }.take(MAX_DOSES).map { dose ->
            DoseRow(
                id = dose.id,
                label = dose.label,
                time = formatTime(context, dose.hour, dose.minute),
                night = dose.isNight,
                taken = log.isTaken(dose.id, day)
            )
        }
        // Follow the app's chosen light/dark theme (written by the Dart side).
        val dark = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
            .getBoolean("dark", false)
        return WidgetState(day, dark, ClarkoStore.streak(doses, log, now), rows)
    }

    /** Follows the phone's 12/24-hour setting, like the in-app dose cards. */
    private fun formatTime(context: Context, hour: Int, minute: Int): String =
        if (DateFormat.is24HourFormat(context)) {
            String.format(Locale.US, "%02d:%02d", hour, minute)
        } else {
            String.format(
                Locale.US, "%d:%02d %s",
                if (hour % 12 == 0) 12 else hour % 12, minute, if (hour < 12) "AM" else "PM"
            )
        }

    /**
     * Arms a one-shot refresh for the next day start, 03:00 (re-armed on every
     * refresh, so it keeps rolling day to day). It is deliberately a non-wakeup
     * alarm: with the screen off nobody is looking, and it is delivered the
     * moment the device wakes — and it never competes with the dose reminders'
     * own exact alarms.
     */
    private fun scheduleMidnightRefresh(context: Context, enabled: Boolean) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, ClarkoWidgetProvider::class.java).setAction(ACTION_REFRESH)
        val pending = PendingIntent.getBroadcast(
            context, REQUEST_MIDNIGHT_REFRESH, intent, pendingIntentFlags()
        )
        if (!enabled) {
            alarms.cancel(pending)
            return
        }

        val dayStart = Calendar.getInstance().apply {
            // Next 03:00 — the moment a new Clarko day starts.
            if (get(Calendar.HOUR_OF_DAY) >= ClarkoStore.DAY_START_HOUR) add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, ClarkoStore.DAY_START_HOUR)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExact(AlarmManager.RTC, dayStart, pending)
                return
            }
        } catch (e: SecurityException) {
            // Exact alarms not permitted after all — fall back to a short window.
        }
        alarms.setWindow(AlarmManager.RTC, dayStart, INEXACT_WINDOW_MS, pending)
    }

    /** Clears the dose's reminder notification once it has been marked taken. */
    private fun dismissReminder(context: Context, doseId: String) {
        val notifications =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        notifications?.cancel(ClarkoStore.reminderNotificationId(doseId))
    }

    /**
     * On Android 12+ we hand the launcher a set of layouts keyed by size and it
     * picks the right one as the widget is resized — reliable across devices and
     * lets a single widget go from a full 3x2 down to a checks-only 1x1. Older
     * devices fall back to measuring the reported size ourselves.
     */
    private fun renderViews(
        context: Context,
        state: WidgetState,
        options: Bundle,
        forceMini: Boolean
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Width tier decides what's shown (narrow = checks only, medium adds
            // labels, wide adds times); height decides how many doses fit. The
            // launcher picks the best-fitting entry as the widget is resized.
            val mapping = mapOf(
                // Narrow (~1 cell): just the check buttons.
                SizeF(40f, 40f) to variant(context, state, false, false, false, false, 46f, 2),
                SizeF(40f, 120f) to variant(context, state, false, false, false, false, 46f, 2),
                SizeF(40f, 168f) to variant(context, state, false, false, false, false, 46f, 3),
                SizeF(40f, 232f) to variant(context, state, false, false, false, false, 46f, 4),
                // Medium (~2 cells): label + icon.
                SizeF(120f, 40f) to variant(context, state, false, true, false, true, 46f, 2),
                SizeF(120f, 120f) to variant(context, state, true, true, false, true, 46f, 2),
                SizeF(120f, 168f) to variant(context, state, true, true, false, true, 46f, 3),
                SizeF(120f, 232f) to variant(context, state, true, true, false, true, 46f, 4),
                // Wide (~3 cells): label + icon + time.
                SizeF(190f, 40f) to variant(context, state, false, true, true, true, 46f, 2),
                SizeF(190f, 120f) to variant(context, state, true, true, true, true, 46f, 2),
                SizeF(190f, 168f) to variant(context, state, true, true, true, true, 46f, 3),
                SizeF(190f, 232f) to variant(context, state, true, true, true, true, 46f, 4)
            )
            return RemoteViews(mapping)
        }
        // Pre-12 fallback: heuristic from the reported size.
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).orLarge()
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).orLarge()
        val narrow = forceMini || width < 115
        val wide = width >= 185
        val rows = if (height >= 232) 4 else if (height >= 168) 3 else 2
        return variant(
            context, state,
            header = !narrow && height >= 120,
            label = !narrow,
            time = wide,
            icon = !narrow,
            checkDp = 46f,
            maxRows = rows
        )
    }

    private fun variant(
        context: Context,
        state: WidgetState,
        header: Boolean,
        label: Boolean,
        time: Boolean,
        icon: Boolean,
        checkDp: Float,
        maxRows: Int
    ): RemoteViews {
        val dark = state.dark
        val titleColor = if (dark) 0xFFE6E1E5.toInt() else 0xFF1C1B1F.toInt()
        val subColor = if (dark) 0xFFCAC4D0.toInt() else 0xFF625F66.toInt()
        val accentColor = if (dark) 0xFF6FCF97.toInt() else 0xFF258555.toInt()

        return RemoteViews(context.packageName, R.layout.clarko_widget).apply {
            setInt(
                R.id.widget_root, "setBackgroundResource",
                if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg_light
            )

            setTextViewText(
                R.id.widget_streak,
                if (state.streak > 0) "${ClarkoStore.streakEmoji(state.streak)} ${state.streak} day streak" else "No streak yet"
            )
            setTextColor(R.id.widget_title, titleColor)
            setTextColor(R.id.widget_streak, subColor)
            setViewVisibility(R.id.widget_header, if (header) View.VISIBLE else View.GONE)

            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            val rootPad = if (label) dp(context, 10) else dp(context, 4)
            setViewPadding(R.id.widget_root, rootPad, rootPad, rootPad, rootPad)

            val rowIds = intArrayOf(R.id.dose0_row, R.id.dose1_row, R.id.dose2_row, R.id.dose3_row)
            val iconIds = intArrayOf(R.id.dose0_icon, R.id.dose1_icon, R.id.dose2_icon, R.id.dose3_icon)
            val labelIds = intArrayOf(R.id.dose0_label, R.id.dose1_label, R.id.dose2_label, R.id.dose3_label)
            val timeIds = intArrayOf(R.id.dose0_time, R.id.dose1_time, R.id.dose2_time, R.id.dose3_time)
            val checkIds = intArrayOf(R.id.dose0_check, R.id.dose1_check, R.id.dose2_check, R.id.dose3_check)
            for (i in 0 until MAX_DOSES) {
                val row = if (i < maxRows) state.rows.getOrNull(i) else null
                if (row == null) {
                    setViewVisibility(rowIds[i], View.GONE)
                } else {
                    bindDose(context, this, state.day, row, i, label, time, icon, checkDp,
                        titleColor, subColor, accentColor,
                        rowIds[i], iconIds[i], labelIds[i], timeIds[i], checkIds[i])
                }
            }
        }
    }

    private fun bindDose(
        context: Context,
        views: RemoteViews,
        day: String,
        row: DoseRow,
        index: Int,
        label: Boolean,
        time: Boolean,
        icon: Boolean,
        checkDp: Float,
        titleColor: Int,
        subColor: Int,
        accentColor: Int,
        rowId: Int,
        iconId: Int,
        labelId: Int,
        timeId: Int,
        checkId: Int
    ) {
        views.setViewVisibility(rowId, View.VISIBLE)

        if (label) {
            views.setTextViewText(labelId, row.label)
            views.setTextColor(labelId, titleColor)
            views.setViewVisibility(labelId, View.VISIBLE)
        } else {
            views.setViewVisibility(labelId, View.GONE)
        }

        if (time) {
            views.setTextViewText(timeId, row.time)
            views.setTextColor(timeId, subColor)
            views.setViewVisibility(timeId, View.VISIBLE)
        } else {
            views.setViewVisibility(timeId, View.GONE)
        }

        if (icon) {
            views.setImageViewResource(iconId, if (row.night) R.drawable.ic_moon else R.drawable.ic_sun)
            views.setInt(iconId, "setColorFilter", accentColor)
            views.setViewVisibility(iconId, View.VISIBLE)
        } else {
            views.setViewVisibility(iconId, View.GONE)
        }

        views.setInt(checkId, "setColorFilter", if (row.taken) accentColor else subColor)
        views.setImageViewResource(
            checkId,
            if (row.taken) R.drawable.ic_check_filled else R.drawable.ic_check_empty
        )

        // Always set the check size explicitly — responsive layouts reuse views,
        // so an unset value would keep a previous bucket's size.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutWidth(checkId, checkDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(checkId, checkDp, TypedValue.COMPLEX_UNIT_DIP)
            val cp = if (checkDp >= 40f) 10 else 5
            views.setViewPadding(checkId, dp(context, cp), dp(context, cp), dp(context, cp), dp(context, cp))
        }

        // The tap says exactly what the user saw and asked for — "set this dose
        // to (not) taken on this day" — rather than a blind flip, so it stays
        // correct even if it is delivered late or twice.
        views.setOnClickPendingIntent(checkId, checkIntent(context, index, day, row))
    }

    /** The tap intent of dose [index]'s check; shared by every widget layout. */
    private fun checkIntent(context: Context, index: Int, day: String, row: DoseRow): PendingIntent {
        val intent = Intent(context, ClarkoWidgetProvider::class.java).apply {
            action = ACTION_SET_TAKEN
            putExtra(EXTRA_DOSE_ID, row.id)
            putExtra(EXTRA_DAY, day)
            putExtra(EXTRA_TAKEN, !row.taken)
        }
        return PendingIntent.getBroadcast(context, index, intent, pendingIntentFlags())
    }

    /**
     * The compact "streak" widget: the streak (stage emoji + count) takes the
     * place of the dose names; the first two doses sit on the right, stacked
     * in the same order as in the other widgets.
     */
    private fun renderStreak(context: Context, state: WidgetState): RemoteViews {
        val dark = state.dark
        val titleColor = if (dark) 0xFFE6E1E5.toInt() else 0xFF1C1B1F.toInt()
        val subColor = if (dark) 0xFFCAC4D0.toInt() else 0xFF625F66.toInt()
        val accentColor = if (dark) 0xFF6FCF97.toInt() else 0xFF258555.toInt()

        return RemoteViews(context.packageName, R.layout.clarko_widget_streak).apply {
            setInt(
                R.id.widget_root, "setBackgroundResource",
                if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg_light
            )
            setTextViewText(
                R.id.streak_big,
                if (state.streak > 0) "${ClarkoStore.streakEmoji(state.streak)} ${state.streak}" else "–"
            )
            setTextViewText(
                R.id.streak_caption,
                if (state.streak > 0) "day streak" else "no streak yet"
            )
            setTextColor(R.id.streak_big, titleColor)
            setTextColor(R.id.streak_caption, subColor)
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            val rowIds = intArrayOf(R.id.dose0_row, R.id.dose1_row)
            val iconIds = intArrayOf(R.id.dose0_icon, R.id.dose1_icon)
            val checkIds = intArrayOf(R.id.dose0_check, R.id.dose1_check)
            for (i in checkIds.indices) {
                val row = state.rows.getOrNull(i)
                if (row == null) {
                    setViewVisibility(rowIds[i], View.GONE)
                    continue
                }
                setViewVisibility(rowIds[i], View.VISIBLE)
                setImageViewResource(iconIds[i], if (row.night) R.drawable.ic_moon else R.drawable.ic_sun)
                setInt(iconIds[i], "setColorFilter", accentColor)
                setInt(checkIds[i], "setColorFilter", if (row.taken) accentColor else subColor)
                setImageViewResource(
                    checkIds[i],
                    if (row.taken) R.drawable.ic_check_filled else R.drawable.ic_check_empty
                )
                setOnClickPendingIntent(checkIds[i], checkIntent(context, i, state.day, row))
            }
        }
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun Int.orLarge(): Int = if (this <= 0) 9999 else this

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
}

/** 3x1 size variant — same content, different picker default. */
class ClarkoWidgetWideProvider : ClarkoWidgetProvider()

/** 2x1 size variant — same content, different picker default. */
class ClarkoWidgetSmallProvider : ClarkoWidgetProvider()

/** 1x1 size variant — on pre-Android-12 it collapses to just the check buttons. */
class ClarkoWidgetTinyProvider : ClarkoWidgetProvider()

/** 2x1 "streak" variant — streak on the left, the first two doses stacked on the right. */
class ClarkoWidgetStreakProvider : ClarkoWidgetProvider()
