import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceTrackingCamera extends StatefulWidget {
  final Function(Uint8List) onCapture;
  final VoidCallback onCancel;

  const FaceTrackingCamera({
    super.key,
    required this.onCapture,
    required this.onCancel,
  });

  @override
  State<FaceTrackingCamera> createState() => _FaceTrackingCameraState();
}

class _FaceTrackingCameraState extends State<FaceTrackingCamera> {
  late CameraController _controller;
  bool _isInitialized = false;
  late FaceDetector _faceDetector;
  List<Face> _faces = [];
  String _positionGuidance = 'Position Your Face';
  bool _isFacePositionValid = false;
  bool _isFaceDetected = false;
  int _frameCount = 0;
  bool _showTips = false;
  Timer? _captureTimer;
  int _countdownSeconds = 5;
  String _countdownText = 'Ready';
  Uint8List? _capturedImageBytes;
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();
  bool _isCountingDown = false;
  bool _hasCapturedPhoto = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No cameras available');
        return;
      }

      _controller = CameraController(
        cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        ),
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller.initialize();

      // Initialize face detector
      final options = FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      );
      _faceDetector = FaceDetector(options: options);

      if (mounted) {
        setState(() => _isInitialized = true);
        _controller.startImageStream((CameraImage image) {
          _processCameraImage(image);
        });
      }
    } catch (e) {
      _showError('Camera initialization failed: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || !_isFacePositionValid) {
      return;
    }
    
    _isCapturing = true;
    
    try {
      // Stop image stream to prevent auto-capture during preview
      await _controller.stopImageStream();
      
      final image = await _controller.takePicture();
      final bytes = await image.readAsBytes();
      
      if (mounted) {
        setState(() {
          _capturedImageBytes = bytes;
          _hasCapturedPhoto = true;
        });
      }
    } catch (e) {
      _showError('Failed to capture photo: $e');
    } finally {
      _isCapturing = false;
    }
  }

  void _usePhoto() {
    if (_capturedImageBytes != null) {
      widget.onCapture(_capturedImageBytes!);
    }
  }

  void _retakePhoto() {
    if (mounted) {
      setState(() {
        _capturedImageBytes = null;
        _hasCapturedPhoto = false;
        _isCapturing = false;
      });
      // Restart image stream for retake
      _controller.startImageStream(_processCameraImage);
    }
  }

  void _startCaptureTimer() {
    if (!_isFacePositionValid || _isCapturing) {
      _showError('Please adjust your face position as guided');
      return;
    }

    _countdownSeconds = 5;
    _countdownText = 'Ready';
    _captureTimer?.cancel();
    
    if (mounted) {
      setState(() {
        _isCountingDown = true;
      });
    }
    
    // Play background music
    _playBackgroundMusic();
    
    // Play ready sound
    _playBeep();
    
    // Show "Ready" for 1 second, then start countdown from 5 to 1
    _captureTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isCapturing) {
        setState(() {
          _countdownText = '5';
        });
        _playBeep();
        
        // Start countdown from 5 down to 1
        _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            if (_countdownSeconds <= 1) {
              timer.cancel();
              _stopBackgroundMusic();
              setState(() {
                _isCountingDown = false;
                _countdownText = ''; // Clear countdown text
              });
              _playCaptureSound();
              if (!_isCapturing) {
                _capturePhoto();
              }
            } else {
              setState(() {
                _countdownSeconds--;
                _countdownText = _countdownSeconds.toString();
              });
              _playBeep();
            }
          }
        });
      }
    });
  }

  void _cancelCaptureTimer() {
    _captureTimer?.cancel();
    _stopBackgroundMusic();
    if (mounted) {
      setState(() {
        _countdownSeconds = 5;
        _countdownText = 'Ready';
        _isCountingDown = false;
      });
    }
  }

  Future<void> _playBackgroundMusic() async {
    try {
      await _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        asAlarm: false,
        volume: 0.3,
      );
    } catch (e) {
      debugPrint('Error playing background music: $e');
    }
  }

  Future<void> _stopBackgroundMusic() async {
    try {
      await _ringtonePlayer.stop();
    } catch (e) {
      debugPrint('Error stopping background music: $e');
    }
  }

  Future<void> _playBeep() async {
    try {
      await _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: false,
        asAlarm: false,
        volume: 0.5,
      );
    } catch (e) {
      debugPrint('Error playing beep: $e');
    }
  }

  Future<void> _playCaptureSound() async {
    try {
      await _ringtonePlayer.play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Error playing capture sound: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      Get.snackbar(
        'Error',
        message,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    _captureTimer?.cancel();
    _stopBackgroundMusic();
    super.dispose();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _frameCount++;
        if (_frameCount % 30 == 0) {
          debugPrint('InputImage conversion failed - format: ${image.format.group}');
        }
        return;
      }

      _frameCount++;
      
      // Only process face detection every 3 frames to reduce lag
      if (_frameCount % 3 != 0) {
        return;
      }
      
      final faces = await _faceDetector.processImage(inputImage);
      
      if (_frameCount % 30 == 0) {
        debugPrint('Processing image - size: ${image.width}x${image.height}, Faces: ${faces.length}');
      }
      
      if (mounted) {
        final newGuidance = _analyzeFacePosition(faces, image);
        final newIsValid = faces.isNotEmpty && newGuidance == 'Perfect!';
        
        // Only update state if something changed to reduce unnecessary rebuilds
        if (_positionGuidance != newGuidance || 
            _isFaceDetected != faces.isNotEmpty || 
            _isFacePositionValid != newIsValid) {
          setState(() {
            _faces = faces;
            _isFaceDetected = faces.isNotEmpty;
            _positionGuidance = newGuidance;
            _isFacePositionValid = newIsValid;
          });
          
          if (_frameCount % 30 == 0) {
            debugPrint('Guidance: $_positionGuidance, Valid: $_isFacePositionValid');
          }
        }
        
        // Auto-start timer when face position becomes valid (only if no photo captured yet and not in preview)
        if (_isFacePositionValid && !_isCountingDown && !_hasCapturedPhoto && _capturedImageBytes == null) {
          _startCaptureTimer();
        }
        // Cancel and reset timer if face position becomes invalid during countdown
        else if (!_isFacePositionValid && _isCountingDown) {
          _cancelCaptureTimer();
        }
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    // Get the input image format from the camera image format
    InputImageFormat format;
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        format = InputImageFormat.nv21;
        break;
      case ImageFormatGroup.bgra8888:
        format = InputImageFormat.bgra8888;
        break;
      default:
        debugPrint('Unsupported image format: ${image.format.group}');
        return null;
    }

    // For YUV420 format, we need to convert the planes
    if (image.format.group == ImageFormatGroup.yuv420) {
      if (image.planes.length != 3) {
        debugPrint('YUV420 requires 3 planes, got ${image.planes.length}');
        return null;
      }
      
      // Convert YUV420 to NV21
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      
      final yRowStride = yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;
      final uRowStride = uPlane.bytesPerRow;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vRowStride = vPlane.bytesPerRow;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;
      
      final width = image.width;
      final height = image.height;
      
      final nv21 = Uint8List(width * height + (width * height ~/ 2));
      
      // Copy Y plane
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y * yRowStride + x * yPixelStride;
          final nv21Index = y * width + x;
          if (yIndex < yPlane.bytes.length && nv21Index < nv21.length) {
            nv21[nv21Index] = yPlane.bytes[yIndex];
          }
        }
      }
      
      // Copy UV planes interleaved
      int uvIndex = width * height;
      for (int y = 0; y < height ~/ 2; y++) {
        for (int x = 0; x < width ~/ 2; x++) {
          final uIndex = y * uRowStride + x * uPixelStride;
          final vIndex = y * vRowStride + x * vPixelStride;
          if (uIndex < uPlane.bytes.length && vIndex < vPlane.bytes.length && uvIndex + 1 < nv21.length) {
            nv21[uvIndex] = vPlane.bytes[vIndex];
            nv21[uvIndex + 1] = uPlane.bytes[uIndex];
            uvIndex += 2;
          }
        }
      }
      
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: width,
        ),
      );
    }
    
    // For other formats, use the first plane
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  String _analyzeFacePosition(List<Face> faces, CameraImage image) {
    if (faces.isEmpty) {
      return 'No face detected';
    }

    final face = faces.first;
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    
    // Get face bounding box
    final bbox = face.boundingBox;
    final faceCenterX = bbox.left + bbox.width / 2;
    final faceCenterY = bbox.top + bbox.height / 2;
    
    // Calculate distances from center (normalized 0-1)
    final centerX = faceCenterX / imageWidth;
    final centerY = faceCenterY / imageHeight;
    
    // Check if face is centered (within 20% of center)
    final isCentered = (centerX > 0.4 && centerX < 0.6) && (centerY > 0.4 && centerY < 0.6);
    
    // Check face size (should be 30-50% of image height for proper profile photo)
    final faceSizeRatio = bbox.height / imageHeight;
    final isProperSize = faceSizeRatio > 0.3 && faceSizeRatio < 0.5;
    
    // Check head pose (should be looking straight)
    final headEulerY = face.headEulerAngleY ?? 0; // Yaw (left/right rotation)
    final headEulerX = face.headEulerAngleX ?? 0; // Pitch (up/down rotation)
    final headEulerZ = face.headEulerAngleZ ?? 0; // Roll (tilt)
    
    final isLookingStraight = headEulerY.abs() < 15 && headEulerX.abs() < 15 && headEulerZ.abs() < 10;
    
    // Generate guidance
    if (!isLookingStraight) {
      if (headEulerY.abs() > 15) {
        return headEulerY > 0 ? 'Turn head left' : 'Turn head right';
      }
      if (headEulerX.abs() > 15) {
        return headEulerX > 0 ? 'Look up' : 'Look down';
      }
      if (headEulerZ.abs() > 10) {
        return 'Keep head straight (no tilt)';
      }
    }
    
    if (!isCentered) {
      if (centerX < 0.4) return 'Move right';
      if (centerX > 0.6) return 'Move left';
      if (centerY < 0.4) return 'Move down';
      if (centerY > 0.6) return 'Move up';
    }
    
    if (!isProperSize) {
      if (faceSizeRatio < 0.3) return 'Move closer';
      if (faceSizeRatio > 0.5) return 'Move back';
    }
    
    return 'Perfect!';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    // Show photo preview if image was captured
    if (_capturedImageBytes != null) {
      return _buildPhotoPreview();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview with proper aspect ratio
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: CameraPreview(_controller),
                ),
              ),
              // Dark overlay for better visibility
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
              // Position guide with face detection overlay
              Positioned.fill(
                child: _buildPositionGuide(),
              ),
              // Face detection overlay (only show when not counting down to reduce lag)
              if (_isFaceDetected && _faces.isNotEmpty && !_isCountingDown)
                Positioned.fill(
                  child: _buildFaceDetectionOverlay(),
                ),
              // Top header with status
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        // Cancel button
                        GestureDetector(
                          onTap: widget.onCancel,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Status indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: _isFacePositionValid
                                ? Colors.green.withValues(alpha: 0.9)
                                : _isFaceDetected
                                    ? Colors.orange.withValues(alpha: 0.9)
                                    : Colors.red.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: (_isFacePositionValid
                                        ? Colors.green
                                        : _isFaceDetected
                                            ? Colors.orange
                                            : Colors.red)
                                    .withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isFacePositionValid
                                    ? Icons.check_circle
                                    : _isFaceDetected
                                        ? Icons.adjust
                                        : Icons.face_retouching_off,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _positionGuidance,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Tips toggle button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showTips = !_showTips;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _showTips
                                  ? Colors.blue.withValues(alpha: 0.9)
                                  : Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                            ),
                            child: Icon(
                              _showTips ? Icons.info : Icons.info_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Positioning tips (collapsible, top right corner)
              if (_showTips)
                Positioned(
                  top: 80,
                  right: 20,
                  child: Container(
                    width: constraints.maxWidth * 0.4,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tips for best photo:',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _TipRow(
                          icon: Icons.center_focus_strong,
                          text: 'Center your face in the oval',
                        ),
                        const SizedBox(height: 8),
                        _TipRow(
                          icon: Icons.straighten,
                          text: 'Keep 1-2 feet from camera',
                        ),
                        const SizedBox(height: 8),
                        _TipRow(
                          icon: Icons.light_mode,
                          text: 'Ensure good lighting',
                        ),
                        const SizedBox(height: 8),
                        _TipRow(
                          icon: Icons.visibility,
                          text: 'Look directly at camera',
                        ),
                      ],
                    ),
                  ),
                ),
              // Capture button (right side)
              Positioned(
                right: 20,
                bottom: constraints.maxHeight * 0.08,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _captureTimer?.isActive ?? false
                          ? _cancelCaptureTimer
                          : null,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _captureTimer?.isActive ?? false
                              ? Colors.orange
                              : _isFacePositionValid
                                  ? Colors.green
                                  : Colors.grey.withValues(alpha: 0.5),
                          border: Border.all(
                            color: _captureTimer?.isActive ?? false
                                ? Colors.white
                                : _isFacePositionValid
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.3),
                            width: 4,
                          ),
                          boxShadow: (_captureTimer?.isActive ?? false) || _isFacePositionValid
                              ? [
                                  BoxShadow(
                                    color: (_captureTimer?.isActive ?? false)
                                        ? Colors.orange
                                        : Colors.green
                                            .withValues(alpha: 0.6),
                                    blurRadius: 25,
                                    spreadRadius: 8,
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: _isFacePositionValid
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _captureTimer?.isActive ?? false
                          ? 'Tap to cancel'
                          : _isFacePositionValid
                              ? 'Auto-capturing...'
                              : 'Adjust Position First',
                      style: TextStyle(
                        color: _captureTimer?.isActive ?? false
                            ? Colors.white
                            : _isFacePositionValid
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Colors.black,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Center countdown display
              if (_isCountingDown)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          _countdownText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                blurRadius: 20,
                                color: Colors.green,
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _retakePhoto,
        ),
        title: const Text(
          'Review Photo',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image.memory(
                  _capturedImageBytes!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Retake button
                  ElevatedButton.icon(
                    onPressed: _retakePhoto,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Retake',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.withValues(alpha: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  // Use photo button
                  ElevatedButton.icon(
                    onPressed: _usePhoto,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'Use Photo',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
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

  Widget _buildPositionGuide() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // Calculate responsive oval size (60% of screen width, 70% of screen height)
        final ovalWidth = screenWidth * 0.6;
        final ovalHeight = screenHeight * 0.7;

        return Center(
          child: CustomPaint(
            size: Size(ovalWidth, ovalHeight),
            painter: _FaceGuidePainter(
              isFaceDetected: _isFaceDetected,
              isFacePositionValid: _isFacePositionValid,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFaceDetectionOverlay() {
    return CustomPaint(
      painter: _FaceDetectionPainter(_faces),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final bool isFaceDetected;
  final bool isFacePositionValid;

  const _FaceGuidePainter({
    this.isFaceDetected = false,
    this.isFacePositionValid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Draw main oval guide
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );

    // Determine color based on face detection status
    final guideColor = isFacePositionValid
        ? Colors.green
        : isFaceDetected
            ? Colors.orange
            : Colors.white;

    // Outer glow
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = guideColor.withValues(alpha: 0.3);
    canvas.drawOval(ovalRect, glowPaint);

    // Main outline
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = guideColor;
    canvas.drawOval(ovalRect, outlinePaint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = guideColor;

    final cornerSize = 12.0;
    final corners = [
      Offset(ovalRect.left, ovalRect.top),
      Offset(ovalRect.right, ovalRect.top),
      Offset(ovalRect.left, ovalRect.bottom),
      Offset(ovalRect.right, ovalRect.bottom),
    ];

    for (final corner in corners) {
      canvas.drawCircle(corner, cornerSize, cornerPaint);
    }

    // Draw center crosshair
    final crosshairPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.5);

    final crosshairSize = 20.0;
    canvas.drawLine(
      Offset(center.dx - crosshairSize, center.dy),
      Offset(center.dx + crosshairSize, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - crosshairSize),
      Offset(center.dx, center.dy + crosshairSize),
      crosshairPaint,
    );

    // Draw eye level guide
    final eyeLevelY = center.dy - size.height * 0.15;
    final eyeLevelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(ovalRect.left + 30, eyeLevelY),
      Offset(ovalRect.right - 30, eyeLevelY),
      eyeLevelPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) {
    return oldDelegate.isFaceDetected != isFaceDetected ||
        oldDelegate.isFacePositionValid != isFacePositionValid;
  }
}

class _FaceDetectionPainter extends CustomPainter {
  final List<Face> faces;

  _FaceDetectionPainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {
    final facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.green.withValues(alpha: 0.8);

    for (final face in faces) {
      final bbox = face.boundingBox;
      canvas.drawRect(bbox, facePaint);

      // Draw face landmarks if available
      final landmarkPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.yellow.withValues(alpha: 0.8)
        ..strokeWidth = 2;

      final landmarks = [
        FaceLandmarkType.leftEye,
        FaceLandmarkType.rightEye,
        FaceLandmarkType.noseBase,
        FaceLandmarkType.bottomMouth,
      ];

      for (final landmarkType in landmarks) {
        final landmark = face.landmarks?[landmarkType];
        if (landmark != null) {
          final position = landmark.position;
          canvas.drawCircle(Offset(position.x.toDouble(), position.y.toDouble()), 4, landmarkPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FaceDetectionPainter oldDelegate) {
    return true;
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.green,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
