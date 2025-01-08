import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FaceDetectionPage(cameras: cameras),
    );
  }
}

class FaceDetectionPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceDetectionPage({required this.cameras});

  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  bool _faceDetected = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true
      ),
    );
  }

  void _initializeCamera() async {

    final frontCamera = widget.cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first, // Fallback to the first available camera if front camera is not found
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _cameraController.initialize();
    _cameraController.startImageStream(_processCameraStream);
    setState(() {});
  }

  Future<void> _processCameraStream(CameraImage cameraImage) async {
    if (_isDetecting) return;

    _isDetecting = true;

    try {

      final inputImage = _inputImageFromCameraImage(cameraImage);
      if(inputImage == null){
        print("nukkKKKKKk");
        return;
      }
      else{
        // print("WOWIEIEIIEEIEI");
      }
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        print("Face detected!");

        setState(() {
          _faceDetected = true;
        });
      } else {
        print(" Not detected");
        setState(() {
          _faceDetected = false;
        });
      }
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      _isDetecting = false;
    }
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // Ensure image is not null
    if (image == null) {
      // print('Camera image is null');
      return null;
    }

    // Ensure controller is initialized before using it
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      // print('Camera controller is not initialized');
      return null;
    }

    // Get sensor orientation for rotation calculation
    final camera = widget.cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first, // Fallback to first camera
    );

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    // Rotation calculation
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_cameraController.value.deviceOrientation];
      if (rotationCompensation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    // Check if rotation was successfully determined
    if (rotation == null) {
      // print('Rotation could not be calculated');
      return null;
    }

    // Get image format (YUV_420_888 for Android)
    // final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final format = image.format.raw;
    print('Camera image format: $format');

    // Check for YUV_420_888 format (Android)
    if (format == 35) {
      // Convert YUV_420_888 to NV21 format
      final bytes = image.getNv21Uint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21, // Mark format as nv21
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    else if(format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    // Unsupported format
    print('Unsupported format');
    return null;
  }


  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // print(widget.cameras.toString());
    if (!_cameraController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Face Detection")),
      body: Stack(
        children: [
          CameraPreview(_cameraController),
          if (_faceDetected)
            const Center(
              child: Icon(
                Icons.face,
                color: Colors.green,
                size: 100,
              ),
            ),
        ],
      ),
    );
  }
}

extension Nv21Converter on CameraImage {
  Uint8List getNv21Uint8List() {
    final width = this.width;
    final height = this.height;

    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final numPixels = (width * height * 1.5).toInt();
    final nv21 = List<int>.filled(numPixels, 0);

    // Full size Y channel and quarter size U+V channels.
    int idY = 0;
    int idUV = width * height;
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    // Copy Y & UV channel.
    // NV21 format is expected to have YYYYVU packaging.
    // The U/V planes are guaranteed to have the same row stride and pixel stride.
    // getRowStride analogue??
    final uvRowStride = uPlane.bytesPerRow;
    // getPixelStride analogue
    final uvPixelStride = uPlane.bytesPerPixel ?? 0;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 0;

    for (int y = 0; y < height; ++y) {
      final uvOffset = y * uvRowStride;
      final yOffset = y * yRowStride;

      for (int x = 0; x < width; ++x) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];

        if (y < uvHeight && x < uvWidth) {
          final bufferIndex = uvOffset + (x * uvPixelStride);
          //V channel
          nv21[idUV++] = vBuffer[bufferIndex];
          //V channel
          nv21[idUV++] = uBuffer[bufferIndex];
        }
      }
    }
    return Uint8List.fromList(nv21);
  }
}