package com.kafekita.pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val storageWorker = Executors.newSingleThreadExecutor()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val connectivity by lazy { getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager }

    private fun stopNetworkMonitor() {
        networkCallback?.let { connectivity.unregisterNetworkCallback(it) }
        networkCallback = null
    }

    private fun storageKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey("warloc_local_store_v1", null)
        if (existing is SecretKey) return existing
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("warloc_local_store_v1",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    override fun onDestroy() {
        stopNetworkMonitor()
        storageWorker.shutdown()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kafekita.pos/network")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopNetworkMonitor()
                    fun emit() = runOnUiThread {
                        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                        events.success(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                    }
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) { emit() }
                        override fun onLost(network: Network) { emit() }
                        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) { emit() }
                    }
                    networkCallback = callback
                    connectivity.registerDefaultNetworkCallback(callback)
                    emit()
                }
                override fun onCancel(arguments: Any?) { stopNetworkMonitor() }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kafekita.pos/firestore_safety")
            .setMethodCallHandler { call, result ->
                storageWorker.execute {
                    try {
                        val project = checkNotNull(call.argument<String>("projectId"))
                        val inspector = FirestoreQueueInspector(this)
                        val value = when (call.method) {
                            "inspectQueue" -> inspector.inspect(project)
                            "backupQueue" -> inspector.backup(project,
                                checkNotNull(call.argument<Number>("expectedBatches")).toLong())
                            else -> throw IllegalArgumentException("Unknown safety operation")
                        }
                        runOnUiThread { result.success(value) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("firestore_queue_review", "Antrean perlu diperiksa sebelum sinkronisasi.", null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kafekita.pos/secure_store")
            .setMethodCallHandler { call, result ->
                storageWorker.execute {
                    try {
                        val prefs = getSharedPreferences("warloc_secure_storage", MODE_PRIVATE)
                        when (call.method) {
                            "read" -> {
                                val value = prefs.getString("payload", null)
                                val plain = if (value == null) null else {
                                    val bytes = Base64.decode(value, Base64.NO_WRAP)
                                    require(bytes.size > 28)
                                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                    cipher.init(Cipher.DECRYPT_MODE, storageKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                                    String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
                                }
                                runOnUiThread { result.success(plain) }
                            }
                            "write" -> {
                                val plain = call.argument<String>("data") ?: throw IllegalArgumentException()
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.ENCRYPT_MODE, storageKey())
                                val value = Base64.encodeToString(cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
                                check(prefs.edit().putString("payload", value).commit())
                                runOnUiThread { result.success(null) }
                            }
                            else -> runOnUiThread { result.notImplemented() }
                        }
                    } catch (_: Exception) {
                        // Never return plaintext or erase data after a failed decrypt.
                        runOnUiThread { result.error("secure_storage_failed", "Penyimpanan terlindungi tidak dapat dibuka.", null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kafekita.pos/app_release")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedVersion" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("versionCode" to code, "versionName" to info.versionName))
                    }
                    "openDownload" -> {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null || uri.fragment != null) {
                            result.error("invalid_url", "URL pembaruan harus HTTPS.", null)
                        } else {
                            try {
                                // The browser downloads the APK; Android verifies the app signature
                                // and asks the user to approve installation over the existing app.
                                startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("download_unavailable", "Browser tidak dapat dibuka.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
