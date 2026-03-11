import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'zkteco_usb.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZKFinger Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ZKFingerDemo(),
    );
  }
}

class ZKFingerDemo extends StatefulWidget {
  const ZKFingerDemo({super.key});

  @override
  State<ZKFingerDemo> createState() => _ZKFingerDemoState();
}

class _ZKFingerDemoState extends State<ZKFingerDemo> {
  final ZKTecoUSB _device = ZKTecoUSB();
  
  // State
  bool _sdkInitialized = false;
  bool _deviceOpened = false;
  bool _isLoading = false;
  int _deviceCount = 0;
  int _selectedDeviceIndex = 0;
  String _resultText = '';
  Uint8List? _fingerprintImage;
  
  // Enrollment state
  bool _isEnrolling = false;
  int _enrollCount = 0;
  int _enrollFid = 1;
  
  // Verify state
  int _verifyFid = 1;

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  void _setResult(String text) {
    setState(() => _resultText = text);
  }

  // ==================== SDK Operations ====================
  
  Future<void> _init() async {
    setState(() => _isLoading = true);
    
    // Check platform first
    if (!ZKTecoUSB.isSupportedPlatform) {
      setState(() => _isLoading = false);
      _setResult('ZKFinger SDK only works on Windows and Android.\nThis platform is not supported.');
      return;
    }
    
    // Set up callbacks for Android
    if (ZKTecoUSB.isAndroidPlatform) {
      _device.onImageCaptured = (width, height, imageData) {
        setState(() {
          _fingerprintImage = imageData;
        });
      };
      
      _device.onTemplateExtracted = (template, size) {
        _setResult('Fingerprint captured! Template: $size bytes');
      };
      
      _device.onEnrollResult = (success, message, fid, template) {
        setState(() {
          _isEnrolling = false;
          _enrollCount = 0;
        });
        _setResult(message);
      };
      
      _device.onEnrollProgress = (current, total, message) {
        setState(() {
          _enrollCount = current;
        });
        _setResult(message);
      };
      
      _device.onDeviceAttached = () {
        _setResult('Device attached! Press Open to connect.');
      };
      
      _device.onDeviceDetached = () {
        setState(() {
          _deviceOpened = false;
        });
        _setResult('Device detached!');
      };
    }
    
    final success = await _device.initSdk();
    
    if (success) {
      final count = await _device.getDeviceCountAsync();
      setState(() {
        _sdkInitialized = true;
        _deviceCount = count;
        _selectedDeviceIndex = count > 0 ? 0 : -1;
      });
      _setResult(count > 0 
          ? 'SDK initialized. Found $count device(s).' 
          : 'SDK initialized. No device connected!');
    } else {
      _setResult('Failed to initialize SDK');
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _free() async {
    if (_deviceOpened) {
      await _close();
    }
    await _device.terminateSdk();
    setState(() {
      _sdkInitialized = false;
      _deviceOpened = false;
      _deviceCount = 0;
      _fingerprintImage = null;
    });
    _setResult('SDK terminated');
  }

  // ==================== Device Operations ====================

  Future<void> _open() async {
    if (_selectedDeviceIndex < 0) {
      _setResult('No device selected');
      return;
    }
    
    setState(() => _isLoading = true);
    
    final success = await _device.openDevice(_selectedDeviceIndex);
    
    if (success) {
      setState(() => _deviceOpened = true);
      final serial = await _device.getSerialNumber();
      _setResult('Device opened. Serial: ${serial ?? "N/A"}\nImage: ${_device.imageWidth}x${_device.imageHeight}');
    } else {
      _setResult('Failed to open device');
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _close() async {
    await _device.closeDevice();
    setState(() {
      _deviceOpened = false;
      _fingerprintImage = null;
      _isEnrolling = false;
      _enrollCount = 0;
    });
    _setResult('Device closed');
  }

  // ==================== Fingerprint Operations ====================

  Future<void> _enroll() async {
    if (!_deviceOpened) {
      _setResult('Device not opened');
      return;
    }
    
    setState(() {
      _isEnrolling = true;
      _enrollCount = 0;
    });
    
    _setResult('Enrollment started for FID $_enrollFid\nPlease press finger 3 times...');
    _device.startEnrollment();
    
    // Capture loop
    for (int i = 0; i < 3; i++) {
      setState(() => _isLoading = true);
      _setResult('Capture ${i + 1}/3: Place your finger on scanner...');
      
      final result = await _device.captureForEnrollment();
      
      if (result.error != null) {
        setState(() {
          _isLoading = false;
          _isEnrolling = false;
        });
        _setResult('Enrollment failed: ${result.error}');
        return;
      }
      
      setState(() {
        _enrollCount = result.count;
        _isLoading = false;
      });
      
      // Update fingerprint image
      _updateFingerprintImage();
      
      if (result.mergedTemplate != null) {
        // Enrollment complete - register fingerprint
        final registered = await _device.registerFingerprint(_enrollFid, result.mergedTemplate!);
        
        setState(() => _isEnrolling = false);
        
        if (registered) {
          _setResult('Enrollment successful!\nFID $_enrollFid registered.\nDB count: ${_device.getDatabaseCount()}');
          setState(() => _enrollFid++);
        } else {
          _setResult('Failed to register fingerprint');
        }
        return;
      }
      
      _setResult('Capture ${result.count}/3 complete. Continue...');
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _verify() async {
    if (!_deviceOpened) {
      _setResult('Device not opened');
      return;
    }
    
    setState(() => _isLoading = true);
    _setResult('Place finger on scanner to verify FID $_verifyFid...');
    
    final template = await _device.captureFingerprint();
    _updateFingerprintImage();
    
    if (template == null) {
      setState(() => _isLoading = false);
      _setResult('Failed to capture fingerprint');
      return;
    }
    
    // For verify we need to get the stored template and compare
    // Since we're using the SDK's internal DB, use identify and check if it matches
    final identifyResult = _device.identifyTemplate(template);
    
    setState(() => _isLoading = false);
    
    if (identifyResult.fingerId == _verifyFid) {
      _setResult('Verification PASSED!\nFID: ${identifyResult.fingerId}, Score: ${identifyResult.score}');
    } else if (identifyResult.fingerId != null) {
      _setResult('Verification FAILED!\nMatched different FID: ${identifyResult.fingerId}');
    } else {
      _setResult('Verification FAILED!\nFingerprint not found in database');
    }
  }

  Future<void> _identify() async {
    if (!_deviceOpened) {
      _setResult('Device not opened');
      return;
    }
    
    setState(() => _isLoading = true);
    _setResult('Place finger on scanner to identify...');
    
    final result = await _device.identifyFingerprint();
    _updateFingerprintImage();
    
    setState(() => _isLoading = false);
    
    if (result.found && result.fid != null) {
      _setResult('Identified!\nFID: ${result.fid}, Score: ${result.score}\nAttendance logged.');
    } else {
      _setResult('Identification failed.\nFingerprint not in database.');
    }
  }

  void _updateFingerprintImage() {
    final image = _device.lastCapturedImage;
    if (image != null) {
      setState(() => _fingerprintImage = image);
    }
  }

  Future<void> _clearDb() async {
    final success = await _device.clearDatabase();
    if (success) {
      _setResult('Database cleared');
      setState(() => _enrollFid = 1);
    } else {
      _setResult('Failed to clear database');
    }
  }

  // ==================== Build UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZKFinger SDK Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left panel - Controls
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // SDK Controls
                    _buildSection('SDK', [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (!_sdkInitialized && !_isLoading) ? _init : null,
                              child: const Text('Init'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_sdkInitialized && !_isLoading) ? _free : null,
                              child: const Text('Free'),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // Device Controls
                    _buildSection('Device', [
                      // Device selector
                      Row(
                        children: [
                          const Text('Index: '),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButton<int>(
                              value: _deviceCount > 0 ? _selectedDeviceIndex : null,
                              isExpanded: true,
                              items: List.generate(_deviceCount, (i) => 
                                DropdownMenuItem(value: i, child: Text('Device $i'))
                              ),
                              onChanged: _sdkInitialized && !_deviceOpened 
                                  ? (v) => setState(() => _selectedDeviceIndex = v ?? 0)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_sdkInitialized && !_deviceOpened && !_isLoading && _deviceCount > 0) 
                                  ? _open : null,
                              child: const Text('Open'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_deviceOpened && !_isLoading) ? _close : null,
                              child: const Text('Close'),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // Fingerprint Operations
                    _buildSection('Fingerprint', [
                      // Enroll row
                      Row(
                        children: [
                          const Text('FID: '),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              controller: TextEditingController(text: _enrollFid.toString()),
                              onChanged: (v) => _enrollFid = int.tryParse(v) ?? 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_deviceOpened && !_isLoading && !_isEnrolling) ? _enroll : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_isEnrolling ? 'Enrolling... ($_enrollCount/3)' : 'Enroll'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Verify row
                      Row(
                        children: [
                          const Text('FID: '),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              ),
                              controller: TextEditingController(text: _verifyFid.toString()),
                              onChanged: (v) => _verifyFid = int.tryParse(v) ?? 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_deviceOpened && !_isLoading) ? _verify : null,
                              child: const Text('Verify'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Identify row
                      ElevatedButton(
                        onPressed: (_deviceOpened && !_isLoading) ? _identify : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Identify (1:N)'),
                      ),
                      const SizedBox(height: 8),
                      // Clear DB
                      ElevatedButton(
                        onPressed: (_deviceOpened && !_isLoading) ? _clearDb : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Clear DB (${_device.getDatabaseCount() ?? 0})'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Right panel - Fingerprint image and result
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  // Fingerprint image
                  Container(
                    width: 200,
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.grey),
                    ),
                    child: _fingerprintImage != null
                        ? Image.memory(
                            _createBitmapFromRaw(_fingerprintImage!, _device.imageWidth, _device.imageHeight),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : const Center(
                            child: Icon(Icons.fingerprint, size: 80, color: Colors.grey),
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Status indicator
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _deviceOpened ? Icons.check_circle : Icons.cancel,
                            color: _deviceOpened ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _deviceOpened ? 'Device Ready' : 'Device Closed',
                            style: TextStyle(
                              color: _deviceOpened ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Result text
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _resultText.isEmpty ? 'Ready' : _resultText,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ...children,
        ],
      ),
    );
  }

  /// Convert raw grayscale image to BMP format
  Uint8List _createBitmapFromRaw(Uint8List rawData, int width, int height) {
    if (width == 0 || height == 0) return Uint8List(0);
    
    // BMP file header (14 bytes) + DIB header (40 bytes) + palette (256 * 4 bytes)
    const headerSize = 14 + 40 + 256 * 4;
    final rowSize = ((width + 3) ~/ 4) * 4; // rows must be multiple of 4
    final imageSize = rowSize * height;
    final fileSize = headerSize + imageSize;
    
    final bmp = Uint8List(fileSize);
    final data = ByteData.view(bmp.buffer);
    
    // BMP file header
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    data.setUint32(2, fileSize, Endian.little);
    data.setUint32(10, headerSize, Endian.little);
    
    // DIB header (BITMAPINFOHEADER)
    data.setUint32(14, 40, Endian.little); // header size
    data.setInt32(18, width, Endian.little);
    data.setInt32(22, -height, Endian.little); // negative = top-down
    data.setUint16(26, 1, Endian.little); // planes
    data.setUint16(28, 8, Endian.little); // bits per pixel (grayscale)
    data.setUint32(34, imageSize, Endian.little);
    
    // Grayscale palette
    for (int i = 0; i < 256; i++) {
      final offset = 54 + i * 4;
      bmp[offset] = i;     // blue
      bmp[offset + 1] = i; // green
      bmp[offset + 2] = i; // red
      bmp[offset + 3] = 0; // reserved
    }
    
    // Copy pixel data
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final srcIdx = y * width + x;
        final dstIdx = headerSize + y * rowSize + x;
        if (srcIdx < rawData.length && dstIdx < bmp.length) {
          bmp[dstIdx] = rawData[srcIdx];
        }
      }
    }
    
    return bmp;
  }
}
