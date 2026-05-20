import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VehicleDetectionScreen extends StatefulWidget {
  const VehicleDetectionScreen({super.key});

  @override
  State<VehicleDetectionScreen> createState() => _VehicleDetectionScreenState();
}

class _VehicleDetectionScreenState extends State<VehicleDetectionScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _availableCameras;
  bool _isInitializing = true;
  bool _isProcessingLiveFrame = false;

  @override
  void initState() {
    super.initState();
    _setupCameraHardware();
  }


  Future<void> _setupCameraHardware() async {
    try {
      // Access systemic hardware camera configurations
      _availableCameras = await availableCameras();
      if (_availableCameras != null && _availableCameras!.isNotEmpty) {
        // Initialize rear camera lens array at standard high definition
        _cameraController = CameraController(
          _availableCameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
      }
    } catch (e) {
      debugPrint("Camera Initialization Exception: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose(); // Prevent native background driver leaks
    super.dispose();
  }

  // 🚀 HIGH-VELOCITY NETWORKING PIPELINE PORTAL
  Future<void> _captureFrameAndSendToBackend() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessingLiveFrame) return;

    setState(() {
      _isProcessingLiveFrame = true;
    });

    try {
      // 1. Capture camera frame image asset
      final XFile capturedImage = await _cameraController!.takePicture();

      // 2. STITCH TARGET BACKEND ENDPOINT URI
      // ⚠️ IMPORTANT: Swap '192.168.1.35' with your Mac's current local Wi-Fi IP address!
      final String myMacIP = '192.168.1.35';
      final Uri backendUri = Uri.parse('http://$myMacIP:8000/api/ocr/detect-vehicle');

      // 3. Package as multipart form data payload
      final http.MultipartRequest networkRequest = http.MultipartRequest('POST', backendUri);

      // The key name 'file' matches the structural parameter in your FastAPI Uvicorn backend
      networkRequest.files.add(
        await http.MultipartFile.fromPath('file', capturedImage.path),
      );

      debugPrint("Streaming file bytes payload over local network...");
      final http.StreamedResponse serverStreamedResponse = await networkRequest.send();

      // 4. Evaluate Pipeline Callback Response Data
      if (serverStreamedResponse.statusCode == 200) {
        final String rawResponseString = await serverStreamedResponse.stream.bytesToString();
        final Map<String, dynamic> processedJson = jsonDecode(rawResponseString);

        debugPrint("Successfully Parsed Live Backend Map Data: $processedJson");

        // UI Presentation Alert to reveal processing results metrics to the Guard User
        if (mounted) {
          _showResultsOverlay(processedJson);
        }
      } else {
        debugPrint("Server Core Communication Failure. Error Code: ${serverStreamedResponse.statusCode}");
      }
    } catch (e) {
      debugPrint("Operational Runtime Network Exception: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingLiveFrame = false;
        });
      }
    }
  }

  void _showResultsOverlay(Map<String, dynamic> jsonData) {
    String message = "No vehicle data detected.";

    if (jsonData['status'] == 'success' && jsonData['vehicle_number'] != null && jsonData['vehicle_number'].isNotEmpty) {
      final targetVehicle = jsonData['vehicle_number'][0];
      message = "Plate: ${targetVehicle['number']}\nConfidence Score: ${(targetVehicle['confidence'] * 100).toStringAsFixed(1)}%";
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("SocCar AI Engine Verdict"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Acknowledge"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: Text("Hardware Driver Core Fault: Failed to open Camera.")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Scan Vehicle Input")),
      body: Stack(
        children: [
          // Render Live Camera View Finder covering active device geometry
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_cameraController!),
          ),

          // Intercept user frame display block if server compilation is active
          if (_isProcessingLiveFrame)
            Container(
              // ✅ FIXED: Using withOpacity here so it compiles flawlessly
              color: Colors.black.withOpacity(0.74),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                      "Running Core Enhancements & YOLO Inference...",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _captureFrameAndSendToBackend,
        child: const Icon(Icons.document_scanner_rounded),
      ),
    );
  }
}