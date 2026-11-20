package io.github.toomu

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Incognito tabs' own cookies and site data (channel "toomu/incognito"): each incognito session is a WebView
 * profile, set on each incognito tab's WebView before its first page, and deleted when the session ends.
 *
 *  - supported()               -> true if this WebView has profiles
 *  - use(viewId, profile)      -> true once the tab's WebView is in [profile]
 *  - cookies(profile, url)     -> "a=1; b=2" (for downloads from an incognito tab)
 *  - end(profile)              -> deletes its cookies and site data, then the profile
 */
@SuppressLint("RequiresFeature") // every call is behind supported()
class IncognitoBridge(private val engine: FlutterEngine) {
    private val main = Handler(Looper.getMainLooper())
    /** The session whose start deleted the ones before it. */
    private var sweptFor: String? = null

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "toomu/incognito").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "supported" -> result.success(supported())
                    "use" -> result.success(
                        use(call.argument<Number>("viewId")?.toInt(), call.argument<String>("profile")),
                    )
                    "cookies" -> result.success(cookies(call.argument<String>("profile"), call.argument<String>("url")))
                    "end" -> {
                        end(call.argument<String>("profile"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "${call.method} failed", e)
                result.error("INCOGNITO", e.toString(), null)
            }
        }
    }

    private fun supported() = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

    private fun use(viewId: Int?, profile: String?): Boolean {
        if (viewId == null || profile == null || !IncognitoProfiles.isIncognito(profile) || !supported()) return false
        val web = webViewOf(viewId) ?: return false.also { Log.w(TAG, "no WebView for view $viewId") }
        // A new session: delete earlier ones (still in use when they ended, or left by an app kill).
        if (sweptFor != profile) {
            sweptFor = profile
            val store = ProfileStore.getInstance()
            for (name in IncognitoProfiles.leftovers(store.allProfileNames, profile)) {
                try {
                    store.deleteProfile(name)
                } catch (e: Exception) {
                    Log.w(TAG, "old $name not deleted", e)
                }
            }
        }
        WebViewCompat.setProfile(web, profile)
        return true
    }

    private fun cookies(profile: String?, url: String?): String {
        if (profile == null || url == null || !supported()) return ""
        return ProfileStore.getInstance().getProfile(profile)?.cookieManager?.getCookie(url) ?: ""
    }

    private fun end(profile: String?) {
        if (profile == null || !IncognitoProfiles.isIncognito(profile) || !supported()) return
        val p = ProfileStore.getInstance().getProfile(profile) ?: return
        // At once, even while a closed tab's WebView is still being torn down...
        p.cookieManager.removeAllCookies(null)
        p.cookieManager.flush()
        p.webStorage.deleteAllData()
        // ...then the profile itself (its cache too) once no WebView uses it; else at the next incognito session.
        main.postDelayed({
            try {
                ProfileStore.getInstance().deleteProfile(profile)
            } catch (e: Exception) {
                Log.i(TAG, "$profile still in use; deleted with the next incognito session")
            }
        }, 3000)
    }

    /** The WebView of Flutter platform view [viewId] (the plugin wraps it in a pull-to-refresh layout). */
    private fun webViewOf(viewId: Int): WebView? {
        val view = engine.platformViewsController.getPlatformViewById(viewId)
            ?: try {
                engine.platformViewsController2.getPlatformViewById(viewId)
            } catch (_: Throwable) {
                null
            }
        return view?.let(::findWebView)
    }

    private fun findWebView(v: View): WebView? {
        if (v is WebView) return v
        if (v is ViewGroup) for (i in 0 until v.childCount) findWebView(v.getChildAt(i))?.let { return it }
        return null
    }

    private companion object {
        const val TAG = "Incognito"
    }
}

/** The rules for incognito profile names, without Android. */
object IncognitoProfiles {
    private const val PREFIX = "incognito-"

    fun isIncognito(name: String) = name.startsWith(PREFIX) && name.length > PREFIX.length

    /** Old incognito sessions to delete: never the default profile, other profiles or the [current] session. */
    fun leftovers(all: List<String>, current: String) = all.filter { isIncognito(it) && it != current }
}
