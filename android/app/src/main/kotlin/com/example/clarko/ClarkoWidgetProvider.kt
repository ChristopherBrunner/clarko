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
            ClarkoWidgetSmallProvider::class.java
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
            val options = appWidgetManager.getAppWidgetOptions(id)
            appWidgetManager.updateAppWidget(id, buildViews(context, widgetData, options))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val data = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, data, newOptions))
    }

    /** Refresh every Clarko widget instance across all size variants. */
    private fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val data = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        for (cls in PROVIDERS) {
            for (id in mgr.getAppWidgetIds(ComponentName(context, cls))) {
                mgr.updateAppWidget(id, buildViews(context, data, mgr.getAppWidgetOptions(id)))
            }
        }
    }

    private fun buildViews(
        context: Context,
        data: SharedPreferences,
        options: Bundle
    ): RemoteViews {
        // Portrait size: width = MIN_WIDTH, height = MAX_HEIGHT (dp). 0 == unknown.
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).orLarge()
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).orLarge()

        val showTimes = width >= 150   // hide reminder times on ~2-cell width
        val showHeader = height >= 110 // hide the Clarko/streak line when short
        val tiny = height < 95         // very short: shrink rows so both doses fit

        return RemoteViews(context.packageName, R.layout.clarko_widget).apply {
            val streak = data.getInt("streak", 0)
            setTextViewText(
                R.id.widget_streak,
                if (streak > 0) "🔥 $streak day streak" else "No streak yet"
            )
            setViewVisibility(R.id.widget_header, if (showHeader) View.VISIBLE else View.GONE)

            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            if (tiny) {
                val pad = dp(context, 6)
                setViewPadding(R.id.widget_root, pad, pad, pad, pad)
            }

            bindDose(context, this, data, 0, showTimes, tiny,
                R.id.dose0_row, R.id.dose0_icon, R.id.dose0_label, R.id.dose0_time, R.id.dose0_check)
            bindDose(context, this, data, 1, showTimes, tiny,
                R.id.dose1_row, R.id.dose1_icon, R.id.dose1_label, R.id.dose1_time, R.id.dose1_check)
        }
    }

    private fun bindDose(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        index: Int,
        showTimes: Boolean,
        tiny: Boolean,
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
        views.setTextViewText(labelId, data.getString("dose${index}_label", "") ?: "")
        views.setTextViewText(timeId, data.getString("dose${index}_time", "") ?: "")
        views.setViewVisibility(timeId, if (showTimes) View.VISIBLE else View.GONE)

        val night = data.getBoolean("dose${index}_night", false)
        views.setImageViewResource(iconId, if (night) R.drawable.ic_moon else R.drawable.ic_sun)

        val taken = data.getBoolean("dose${index}_taken", false)
        views.setImageViewResource(
            checkId,
            if (taken) R.drawable.ic_check_filled else R.drawable.ic_check_empty
        )

        if (tiny && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutHeight(checkId, 36f, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutWidth(checkId, 36f, TypedValue.COMPLEX_UNIT_DIP)
            views.setTextViewTextSize(labelId, TypedValue.COMPLEX_UNIT_SP, 13f)
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
