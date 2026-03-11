package com.example.user_attendance_scanner

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.zkteco.android.biometric.FingerprintExceptionListener
import com.zkteco.android.biometric.core.device.ParameterHelper
import com.zkteco.android.biometric.core.device.TransportType
import com.zkteco.android.biometric.core.utils.LogHelper
import com.zkteco.android.biometric.core.utils.ToolUtils
import com.zkteco.android.biometric.module.fingerprintreader.FingerprintCaptureListener
import com.zkteco.android.biometric.module.fingerprintreader.FingerprintSensor
import com.zkteco.android.biometric.module.fingerprintreader.FingprintFactory
import com.zkteco.android.biometric.module.fingerprintreader.ZKFingerService
import com.zkteco.android.biometric.module.fingerprintreader.exception.FingerprintException
import java.io.ByteArrayOutputStream
import java.util.Random

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.user_attendance_scanner/zkfinger"
    private val TAG = "ZKFingerPlugin"
    
    // ZKTeco USB constants
    private val ZKTECO_VID = 0x1b55
    private val LIVE20R_PID = 0x0120
    private val LIVE10R_PID = 0x0124
    
    // Native library availability flag
    private var nativeLibsAvailable = false
    
    // SDK state
    private var fingerprintSensor: FingerprintSensor? = null
    private var methodChannel: MethodChannel? = null
    private var isDeviceOpen = false
    private var deviceIndex = 0
    private var usbPid = 0
    
    // Enroll state
    private var isEnrolling = false
    private var enrollIndex = 0
    private val enrollTemplates = Array(3) { ByteArray(2048) }
    private var enrollTargetFid = ""
    
    // USB Permission
    private val ACTION_USB_PERMISSION = "com.example.user_attendance_scanner.USB_PERMISSION"
    private var pendingResult: MethodChannel.Result? = null
    
    // Template database (in-memory for demo)
    private val templateDb = HashMap<String, ByteArray>()
    
    // Last captured data
    private var lastTemplate: ByteArray? = null
    private var lastImageWidth = 0
    private var lastImageHeight = 0
    private var lastImageData: ByteArray? = null
    
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        Log.d(TAG, "USB permission granted")
                        device?.let { openDeviceAfterPermission() }
                    } else {
                        Log.d(TAG, "USB permission denied")
                        pendingResult?.error("USB_PERMISSION_DENIED", "USB permission denied", null)
                        pendingResult = null
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    Log.d(TAG, "USB device attached")
                    methodChannel?.invokeMethod("onDeviceAttached", null)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    Log.d(TAG, "USB device detached")
                    closeDeviceInternal()
                    methodChannel?.invokeMethod("onDeviceDetached", null)
                }
            }
        }
    }
    
    private val fingerprintCaptureListener = object : FingerprintCaptureListener {
        override fun captureOK(fpImage: ByteArray) {
            fingerprintSensor?.let { sensor ->
                lastImageWidth = sensor.imageWidth
                lastImageHeight = sensor.imageHeight
                lastImageData = fpImage
                
                // Convert to PNG for Flutter
                val bitmap = ToolUtils.renderCroppedGreyScaleBitmap(fpImage, lastImageWidth, lastImageHeight)
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                val pngData = stream.toByteArray()
                
                runOnUiThread {
                    methodChannel?.invokeMethod("onImageCaptured", mapOf(
                        "width" to lastImageWidth,
                        "height" to lastImageHeight,
                        "imageData" to Base64.encodeToString(pngData, Base64.NO_WRAP)
                    ))
                }
            }
        }
        
        override fun captureError(e: FingerprintException) {
            Log.e(TAG, "Capture error: ${e.message}")
        }
        
        override fun extractOK(fpTemplate: ByteArray) {
            lastTemplate = fpTemplate.copyOf()
            
            runOnUiThread {
                if (isEnrolling) {
                    handleEnrollCapture(fpTemplate)
                } else {
                    methodChannel?.invokeMethod("onTemplateExtracted", mapOf(
                        "template" to Base64.encodeToString(fpTemplate, Base64.NO_WRAP),
                        "size" to fpTemplate.size
                    ))
                }
            }
        }
        
        override fun extractError(errorCode: Int) {
            Log.e(TAG, "Extract error: $errorCode")
            runOnUiThread {
                methodChannel?.invokeMethod("onExtractError", errorCode)
            }
        }
    }
    
    private val fingerprintExceptionListener = FingerprintExceptionListener {
        Log.e(TAG, "Device exception!")
        runOnUiThread {
            methodChannel?.invokeMethod("onDeviceException", null)
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Register USB receiver
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Use RECEIVER_EXPORTED for USB system broadcasts
            registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(usbReceiver, filter)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(usbReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering receiver: ${e.message}")
        }
        closeDeviceInternal()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initSdk" -> initSdk(result)
                "freeSdk" -> freeSdk(result)
                "getDeviceCount" -> getDeviceCount(result)
                "openDevice" -> openDevice(call.argument<Int>("index") ?: 0, result)
                "closeDevice" -> closeDevice(result)
                "startCapture" -> startCapture(result)
                "stopCapture" -> stopCapture(result)
                "startEnroll" -> startEnroll(call.argument<String>("fid") ?: "", result)
                "cancelEnroll" -> cancelEnroll(result)
                "verify" -> verify(call.argument<String>("fid") ?: "", result)
                "identify" -> identify(result)
                "addTemplate" -> {
                    val fid = call.argument<String>("fid") ?: ""
                    val template = call.argument<String>("template") ?: ""
                    addTemplate(fid, template, result)
                }
                "removeTemplate" -> removeTemplate(call.argument<String>("fid") ?: "", result)
                "clearDb" -> clearDb(result)
                "getDbCount" -> getDbCount(result)
                "getLastTemplate" -> getLastTemplate(result)
                "getDeviceInfo" -> getDeviceInfo(result)
                else -> result.notImplemented()
            }
        }
    }
    
    private fun initSdk(result: MethodChannel.Result) {
        try {
            // Try to load native libraries
            nativeLibsAvailable = try {
                System.loadLibrary("zksensorcore")
                System.loadLibrary("zkalg12")
                System.loadLibrary("zkfinger10")
                LogHelper.setLevel(Log.VERBOSE)
                true
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "Native libraries not available: ${e.message}")
                false
            }
            result.success(nativeLibsAvailable)
        } catch (e: Exception) {
            Log.e(TAG, "initSdk error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun freeSdk(result: MethodChannel.Result) {
        try {
            closeDeviceInternal()
            templateDb.clear()
            if (nativeLibsAvailable) {
                try {
                    ZKFingerService.clear()
                } catch (e: UnsatisfiedLinkError) {
                    Log.w(TAG, "Native library error in freeSdk: ${e.message}")
                }
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "freeSdk error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun getDeviceCount(result: MethodChannel.Result) {
        try {
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            var count = 0
            for (device in usbManager.deviceList.values) {
                if (device.vendorId == ZKTECO_VID && 
                    (device.productId == LIVE20R_PID || device.productId == LIVE10R_PID)) {
                    count++
                    usbPid = device.productId
                }
            }
            result.success(count)
        } catch (e: Exception) {
            Log.e(TAG, "getDeviceCount error: ${e.message}")
            result.success(0)
        }
    }
    
    private fun openDevice(index: Int, result: MethodChannel.Result) {
        if (!nativeLibsAvailable) {
            result.error("LIBS_NOT_AVAILABLE", "Native libraries not available. Running on emulator or unsupported architecture.", null)
            return
        }
        
        if (isDeviceOpen) {
            result.success(true)
            return
        }
        
        try {
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            var targetDevice: UsbDevice? = null
            
            for (device in usbManager.deviceList.values) {
                if (device.vendorId == ZKTECO_VID && 
                    (device.productId == LIVE20R_PID || device.productId == LIVE10R_PID)) {
                    targetDevice = device
                    usbPid = device.productId
                    break
                }
            }
            
            if (targetDevice == null) {
                result.error("NO_DEVICE", "No ZKTeco fingerprint device found", null)
                return
            }
            
            if (!usbManager.hasPermission(targetDevice)) {
                pendingResult = result
                val permissionIntent = PendingIntent.getBroadcast(
                    this, 0, Intent(ACTION_USB_PERMISSION),
                    PendingIntent.FLAG_IMMUTABLE
                )
                usbManager.requestPermission(targetDevice, permissionIntent)
                return
            }
            
            openDeviceInternal(result)
        } catch (e: Exception) {
            Log.e(TAG, "openDevice error: ${e.message}")
            result.error("OPEN_ERROR", e.message, null)
        }
    }
    
    private fun openDeviceAfterPermission() {
        pendingResult?.let { result ->
            openDeviceInternal(result)
        }
        pendingResult = null
    }
    
    private fun openDeviceInternal(result: MethodChannel.Result) {
        try {
            // Create fingerprint sensor
            fingerprintSensor?.let { FingprintFactory.destroy(it) }
            
            val params = HashMap<String, Any>()
            params[ParameterHelper.PARAM_KEY_VID] = ZKTECO_VID
            params[ParameterHelper.PARAM_KEY_PID] = usbPid
            
            fingerprintSensor = FingprintFactory.createFingerprintSensor(
                applicationContext, TransportType.USB, params
            )
            
            fingerprintSensor?.let { sensor ->
                sensor.open(deviceIndex)
                sensor.setFingerprintCaptureListener(deviceIndex, fingerprintCaptureListener)
                sensor.SetFingerprintExceptionListener(fingerprintExceptionListener)
                isDeviceOpen = true
                
                Log.d(TAG, "Device opened: ${sensor.strSerialNumber}")
                result.success(true)
            } ?: run {
                result.error("SENSOR_ERROR", "Failed to create fingerprint sensor", null)
            }
        } catch (e: FingerprintException) {
            Log.e(TAG, "openDeviceInternal error: ${e.message}")
            // Try reboot
            try {
                fingerprintSensor?.openAndReboot(deviceIndex)
                isDeviceOpen = true
                result.success(true)
            } catch (ex: Exception) {
                result.error("OPEN_ERROR", ex.message, null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "openDeviceInternal error: ${e.message}")
            result.error("OPEN_ERROR", e.message, null)
        }
    }
    
    private fun closeDevice(result: MethodChannel.Result) {
        closeDeviceInternal()
        result.success(true)
    }
    
    private fun closeDeviceInternal() {
        try {
            fingerprintSensor?.let { sensor ->
                try { sensor.stopCapture(deviceIndex) } catch (e: Exception) {}
                try { sensor.close(deviceIndex) } catch (e: Exception) {}
                FingprintFactory.destroy(sensor)
            }
        } catch (e: Exception) {
            Log.e(TAG, "closeDeviceInternal error: ${e.message}")
        }
        fingerprintSensor = null
        isDeviceOpen = false
        isEnrolling = false
        enrollIndex = 0
    }
    
    private fun startCapture(result: MethodChannel.Result) {
        if (!isDeviceOpen) {
            result.error("NOT_OPEN", "Device not open", null)
            return
        }
        
        try {
            fingerprintSensor?.startCapture(deviceIndex)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "startCapture error: ${e.message}")
            result.error("CAPTURE_ERROR", e.message, null)
        }
    }
    
    private fun stopCapture(result: MethodChannel.Result) {
        try {
            fingerprintSensor?.stopCapture(deviceIndex)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "stopCapture error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun startEnroll(fid: String, result: MethodChannel.Result) {
        if (fid.isEmpty()) {
            result.error("INVALID_FID", "FID cannot be empty", null)
            return
        }
        
        isEnrolling = true
        enrollIndex = 0
        enrollTargetFid = fid
        result.success(true)
    }
    
    private fun cancelEnroll(result: MethodChannel.Result) {
        isEnrolling = false
        enrollIndex = 0
        enrollTargetFid = ""
        result.success(true)
    }
    
    private fun handleEnrollCapture(template: ByteArray) {
        // Check if finger already enrolled
        val bufids = ByteArray(256)
        val ret = ZKFingerService.identify(template, bufids, 70, 1)
        if (ret > 0) {
            val existingId = String(bufids).split("\t")[0].trim()
            methodChannel?.invokeMethod("onEnrollResult", mapOf(
                "success" to false,
                "message" to "Finger already enrolled as $existingId"
            ))
            isEnrolling = false
            enrollIndex = 0
            return
        }
        
        // Verify against previous captures
        if (enrollIndex > 0) {
            val verifyRet = ZKFingerService.verify(enrollTemplates[enrollIndex - 1], template)
            if (verifyRet <= 0) {
                methodChannel?.invokeMethod("onEnrollResult", mapOf(
                    "success" to false,
                    "message" to "Different finger detected. Please use same finger."
                ))
                isEnrolling = false
                enrollIndex = 0
                return
            }
        }
        
        // Store template
        System.arraycopy(template, 0, enrollTemplates[enrollIndex], 0, minOf(template.size, 2048))
        enrollIndex++
        
        if (enrollIndex >= 3) {
            // Merge templates
            val mergedTemplate = ByteArray(2048)
            val mergeRet = ZKFingerService.merge(
                enrollTemplates[0], enrollTemplates[1], enrollTemplates[2], mergedTemplate
            )
            
            if (mergeRet > 0) {
                // Save to ZKFingerService
                val saveRet = ZKFingerService.save(mergedTemplate, enrollTargetFid)
                if (saveRet == 0) {
                    // Save to local db
                    templateDb[enrollTargetFid] = mergedTemplate.copyOf(mergeRet)
                    methodChannel?.invokeMethod("onEnrollResult", mapOf(
                        "success" to true,
                        "message" to "Enrolled successfully as $enrollTargetFid",
                        "fid" to enrollTargetFid,
                        "template" to Base64.encodeToString(mergedTemplate, 0, mergeRet, Base64.NO_WRAP)
                    ))
                } else {
                    methodChannel?.invokeMethod("onEnrollResult", mapOf(
                        "success" to false,
                        "message" to "Failed to save template"
                    ))
                }
            } else {
                methodChannel?.invokeMethod("onEnrollResult", mapOf(
                    "success" to false,
                    "message" to "Failed to merge templates"
                ))
            }
            
            isEnrolling = false
            enrollIndex = 0
        } else {
            methodChannel?.invokeMethod("onEnrollProgress", mapOf(
                "current" to enrollIndex,
                "total" to 3,
                "message" to "Captured ${enrollIndex}/3. Please lift and place finger again."
            ))
        }
    }
    
    private fun verify(fid: String, result: MethodChannel.Result) {
        if (lastTemplate == null) {
            result.error("NO_TEMPLATE", "No fingerprint captured", null)
            return
        }
        
        val storedTemplate = templateDb[fid]
        if (storedTemplate == null) {
            result.success(mapOf("match" to false, "message" to "FID not found"))
            return
        }
        
        val score = ZKFingerService.verify(storedTemplate, lastTemplate)
        result.success(mapOf(
            "match" to (score > 0),
            "score" to score,
            "fid" to fid
        ))
    }
    
    private fun identify(result: MethodChannel.Result) {
        if (lastTemplate == null) {
            result.error("NO_TEMPLATE", "No fingerprint captured", null)
            return
        }
        
        val bufids = ByteArray(256)
        val ret = ZKFingerService.identify(lastTemplate, bufids, 70, 1)
        
        if (ret > 0) {
            val parts = String(bufids).split("\t")
            result.success(mapOf(
                "found" to true,
                "fid" to parts[0].trim(),
                "score" to parts.getOrElse(1) { "0" }.trim().toIntOrNull()
            ))
        } else {
            result.success(mapOf("found" to false))
        }
    }
    
    private fun addTemplate(fid: String, templateBase64: String, result: MethodChannel.Result) {
        try {
            val template = Base64.decode(templateBase64, Base64.NO_WRAP)
            val ret = ZKFingerService.save(template, fid)
            if (ret == 0) {
                templateDb[fid] = template
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "addTemplate error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun removeTemplate(fid: String, result: MethodChannel.Result) {
        try {
            ZKFingerService.del(fid)
            templateDb.remove(fid)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "removeTemplate error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun clearDb(result: MethodChannel.Result) {
        try {
            ZKFingerService.clear()
            templateDb.clear()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "clearDb error: ${e.message}")
            result.success(false)
        }
    }
    
    private fun getDbCount(result: MethodChannel.Result) {
        result.success(templateDb.size)
    }
    
    private fun getLastTemplate(result: MethodChannel.Result) {
        lastTemplate?.let {
            result.success(Base64.encodeToString(it, Base64.NO_WRAP))
        } ?: result.success(null)
    }
    
    private fun getDeviceInfo(result: MethodChannel.Result) {
        fingerprintSensor?.let { sensor ->
            result.success(mapOf(
                "sdkVersion" to (sensor.sdK_Version ?: ""),
                "firmwareVersion" to (sensor.firmwareVersion ?: ""),
                "serialNumber" to (sensor.strSerialNumber ?: ""),
                "imageWidth" to sensor.imageWidth,
                "imageHeight" to sensor.imageHeight
            ))
        } ?: result.success(null)
    }
}
