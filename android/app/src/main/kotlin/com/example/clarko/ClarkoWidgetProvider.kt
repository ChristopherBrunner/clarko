package com.example.clarko

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing today's doses and the current streak.
 *
 * Taps on a dose check are handled natively here (flip the displayed state and
 * refresh immediately), then forwarded to the Dart side to persist the
 * canonical log. Handling the display in-process avoids the background-isolate
 * cold-start latency that made taps look unresponsive.
 *
 * Adapts to its size: reminder times hide when narrow; the header hides and
 * rows shrink when short, so it works from a tall 3x2 down to a compact 2x1.
 */
open class ClarkoWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val PREFS = "HomeWidgetPreferences"
        const val ACTION_TOGGLE = "com.example.clarko.action.TOGGLE_DOSE"
        const val EXTRA_INDEX = "index"
        const val EXTRA_DOSE_ID = "doseId"

        val PROVIDERS = arrayOf(
            ClarkoWidgetProvider::class.java,
            ClarkoWidgetWideProvider::class.java,
            ClarkoWidgetSmallProvider::class.java,
            ClarkoWidgetTinyProvider::class.java
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val index = intent.getIntExtra(EXTRA_INDEX, -1)
            val doseId = intent.getStringExtra(EXTRA_DOSE_ID).orEmpty()
            if (index >= 0) {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val current = prefs.getBoolean("dose${index}_taken", false)
                prefs.edit().putBoolean("dose${index}_taken", !current).apply()
                updateAll(context)
                // Persist the canonical change via the Dart background callback.
                context.sendBroadcast(
                    Intent("es.antonborri.home_widget.action.BACKGROUND").apply {
                        setClass(context, HomeWidgetBackgroundReceiver::class.java)
                        data = Uri.parse("clarko://toggle?id=$doseId")
                    }
                )
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(
                id,
                renderViews(context, widgetData, appWidgetManager.getAppWidgetOptions(id), isMiniProvider())
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val data = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        appWidgetManager.updateAppWidget(appWidgetId, renderViews(context, data, newOptions, isMiniProvider()))
    }

    /** Pre-Android-12 fallback only: the dedicated 1x1 provider forces checks-only. */
    protected open fun isMiniProvider(): Boolean = false

    /** Refresh every Clarko widget instance across all size variants. */
    private fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val data = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        for (cls in PROVIDERS) {
            val forceMini = cls == ClarkoWidgetTinyProvider::class.java
            for (id in mgr.getAppWidgetIds(ComponentName(context, cls))) {
                mgr.updateAppWidget(id, renderViews(context, data, mgr.getAppWidgetOptions(id), forceMini))
            }
        }
    }

    /**
     * On Android 12+ we hand the launcher a set of layouts keyed by size and it
     * picks the right one as the widget is resized — reliable across devices and
     * lets a single widget go from a full 3x2 down to a checks-only 1x1. Older
     * devices fall back to measuring the reported size ourselves.
     */
    private fun renderViews(
        context: Context,
        data: SharedPreferences,
        options: Bundle,
        forceMini: Boolean
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Width tier decides what's shown (narrow = checks only, medium adds
            // labels, wide adds times); height decides how many doses fit. The
            // launcher picks the best-fitting entry as the widget is resized.
            val mapping = mapOf(
                // Narrow (~1 cell): just the check buttons.
                SizeF(40f, 40f) to variant(context, data, false, false, false, false, 46f, 2),
                SizeF(40f, 120f) to variant(context, data, false, false, false, false, 46f, 2),
                SizeF(40f, 168f) to variant(context, data, false, false, false, false, 46f, 3),
                SizeF(40f, 232f) to variant(context, data, false, false, false, false, 46f, 4),
                // Medium (~2 cells): label + icon.
                SizeF(120f, 40f) to variant(context, data, false, true, false, true, 46f, 2),
                SizeF(120f, 120f) to variant(context, data, true, true, false, true, 46f, 2),
                SizeF(120f, 168f) to variant(context, data, true, true, false, true, 46f, 3),
                SizeF(120f, 232f) to variant(context, data, true, true, false, true, 46f, 4),
                // Wide (~3 cells): label + icon + time.
                SizeF(190f, 40f) to variant(context, data, false, true, true, true, 46f, 2),
                SizeF(190f, 120f) to variant(context, data, true, true, true, true, 46f, 2),
                SizeF(190f, 168f) to variant(context, data, true, true, true, true, 46f, 3),
                SizeF(190f, 232f) to variant(context, data, true, true, true, true, 46f, 4)
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
            context, data,
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
        data: SharedPreferences,
        header: Boolean,
        label: Boolean,
        time: Boolean,
        icon: Boolean,
        checkDp: Float,
        maxRows: Int
    ): RemoteViews {
        // Follow the app's chosen light/dark theme (written to widget prefs).
        val dark = data.getBoolean("dark", false)
        val titleColor = if (dark) 0xFFE6E1E5.toInt() else 0xFF1C1B1F.toInt()
        val subColor = if (dark) 0xFFCAC4D0.toInt() else 0xFF625F66.toInt()
        val accentColor = if (dark) 0xFF4DB6AC.toInt() else 0xFF00897B.toInt()

        return RemoteViews(context.packageName, R.layout.clarko_widget).apply {
            setInt(
                R.id.widget_root, "setBackgroundResource",
                if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg_light
            )

            val streak = data.getInt("streak", 0)
            setTextViewText(
                R.id.widget_streak,
                if (streak > 0) "🔥 $streak day streak" else "No streak yet"
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
            for (i in 0..3) {
                if (i < maxRows) {
                    bindDose(context, this, data, i, label, time, icon, checkDp,
                        titleColor, subColor, accentColor,
                        rowIds[i], iconIds[i], labelIds[i], timeIds[i], checkIds[i])
                } else {
                    setViewVisibility(rowIds[i], View.GONE)
                }
            }
        }
    }

    private fun bindDose(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
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
        if (!data.getBoolean("dose${index}_present", false)) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)

        if (label) {
            views.setTextViewText(labelId, data.getString("dose${index}_label", "") ?: "")
            views.setTextColor(labelId, titleColor)
            views.setViewVisibility(labelId, View.VISIBLE)
        } else {
            views.setViewVisibility(labelId, View.GONE)
        }

        if (time) {
            views.setTextViewText(timeId, data.getString("dose${index}_time", "") ?: "")
            views.setTextColor(timeId, subColor)
            views.setViewVisibility(timeId, View.VISIBLE)
        } else {
            views.setViewVisibility(timeId, View.GONE)
        }

        if (icon) {
            val night = data.getBoolean("dose${index}_night", false)
            views.setImageViewResource(iconId, if (night) R.drawable.ic_moon else R.drawable.ic_sun)
            views.setInt(iconId, "setColorFilter", accentColor)
            views.setViewVisibility(iconId, View.VISIBLE)
        } else {
            views.setViewVisibility(iconId, View.GONE)
        }

        val taken = data.getBoolean("dose${index}_taken", false)
        views.setInt(checkId, "setColorFilter", if (taken) accentColor else subColor)
        views.setImageViewResource(
            checkId,
            if (taken) R.drawable.ic_check_filled else R.drawable.ic_check_empty
        )

        // Always set the check size explicitly — responsive layouts reuse views,
        // so an unset value would keep a previous bucket's size.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutWidth(checkId, checkDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(checkId, checkDp, TypedValue.COMPLEX_UNIT_DIP)
            val cp = if (checkDp >= 40f) 10 else 5
            views.setViewPadding(checkId, dp(context, cp), dp(context, cp), dp(context, cp), dp(context, cp))
        }

        // Native toggle: handled in onReceive, then forwarded to Dart.
        val intent = Intent(context, ClarkoWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE
            putExtra(EXTRA_INDEX, index)
            putExtra(EXTRA_DOSE_ID, data.getString("dose${index}_id", "") ?: "")
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        views.setOnClickPendingIntent(
            checkId,
            PendingIntent.getBroadcast(context, index, intent, flags)
        )
    }

    private fun Int.orLarge(): Int = if (this <= 0) 9999 else this

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
}

/** 3x1 size variant — same content, different picker default. */
class ClarkoWidgetWideProvider : ClarkoWidgetProvider()

/** 2x1 size variant — same content, different picker default. */
class ClarkoWidgetSmallProvider : ClarkoWidgetProvider()

/** 1x1 size variant — always collapses to just the check buttons. */
class ClarkoWidgetTinyProvider : ClarkoWidgetProvider() {
    override fun isMiniProvider(): Boolean = true
}
