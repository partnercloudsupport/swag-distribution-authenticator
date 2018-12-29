import 'package:flutter/material.dart';
import 'models/routes.dart' as routes;
import 'list_events.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:quiver/time.dart';
import 'package:mlkit/mlkit.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:typed_data';

const preprocessedFolderName = 'preprocessed';

class CollectionView extends StatefulWidget {
  final List<CameraDescription> cameras;

  CollectionView(this.cameras);

  @override
  _CollectionViewState createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  final _clock = Clock();
  CameraController controller;
  Directory _localDirectory;
  String _preprocessDirectoryPath;
  File _lastCroppedImg;
  File _lastImg;

  @override
  void initState() {
    super.initState();
    _initCamera();

    getApplicationDocumentsDirectory().then((dir) {
      setState(() {
        _localDirectory = dir;
        _preprocessDirectoryPath =
            path_util.join(_localDirectory.path, preprocessedFolderName);
        _initializePreprocessDirectory(_preprocessDirectoryPath);
      });
    });
  }

  void _initializePreprocessDirectory(String path) {
    if (Directory(path).existsSync()) {
      return;
    }
    Directory(path).createSync();
  }

  void _initCamera() {
    controller = CameraController(widget.cameras[1], ResolutionPreset.low);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  File cropImage(File f, Rect faceBoundary) {
    var basename = path_util.basename(f.path);
    img.Image image = img.decodeImage(f.readAsBytesSync()).clone();

    // The [img.copyCrop] method starts from the bottom left of the img,
    // also takes the width as height and height as width.
    // So we need this weird transformation math.
    var newImg = img.copyCrop(
        image,
        image.width - faceBoundary.bottom.round(),
        faceBoundary.left.round(),
        faceBoundary.height.round(),
        faceBoundary.width.round());
    var path = path_util.join(_preprocessDirectoryPath, basename);
    var processedFile = File(path);
    processedFile.writeAsBytesSync(img.encodeJpg(newImg));
    return processedFile;
  }

  Future<void> screenshot() async {
    var newPath = path_util.join(
        _localDirectory.path, '${_clock.now().toIso8601String()}.jpg');
    await controller.takePicture(newPath);
    List<VisionFace> faces =
        await FirebaseVisionFaceDetector.instance.detectFromPath(newPath);
    _lastImg = File(newPath);
    print(newPath);
    if (faces.isEmpty) {
      print('NO FACES FOUND!');
    } else {
      print('FOUND ${faces.length} FACES!');
      _lastCroppedImg = cropImage(File(newPath), faces.first.rect);
    }
    setState(() {});
  }

  List<String> listAllPictures() {
    return _localDirectory
        .listSync()
        .where((f) => path_util.extension(f.path).contains('jpg'))
        .map((f) => f.path)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized || _localDirectory == null) {
      return Container();
    }
    return Scaffold(
      body: Column(
        children: <Widget>[
          Container(
            width: 50,
            height: 80,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
          IconButton(
            onPressed: screenshot,
            iconSize: 30.0,
            icon: Icon(Icons.camera_alt),
          ),
          Text(listAllPictures().length.toString(),
              style: TextStyle(color: Colors.blue)),
          getContainer(),
          getEmbeddingWidget(),
        ],
      ),
    );
  }

  Widget getEmbeddingWidget() {
    if (_lastCroppedImg == null) return Container();
    return FutureBuilder(
        future: getImageEmbedding(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.none:
              return Text('No data');
            case ConnectionState.active:
            case ConnectionState.waiting:
              return Text('Awaiting result...');
            case ConnectionState.done:
              if (snapshot.hasError) return Text('Error: ${snapshot.error}');
              return Text('Result: ${snapshot.data}');
          }
        });
  }

  Future<String> getImageEmbedding() async {
    return (await convertToVector(_lastCroppedImg)).toString();
  }

  Container getContainer() {
    if (_lastCroppedImg == null) return Container();
    return Container(
      color: Colors.grey,
      height: 200,
      width: 200,
      child: Image.file(_lastCroppedImg, fit: BoxFit.scaleDown),
    );
  }
}

const _size = 128;

Future<List<int>> convertToVector(File f) async {
  FirebaseModelInterpreter interpreter = FirebaseModelInterpreter.instance;

  img.Image image = img.decodeJpg(f.readAsBytesSync());
  image = img.copyResize(image, _size, _size);
  var results = await interpreter.run(
      "embeddings",
      FirebaseModelInputOutputOptions(0, FirebaseModelDataType.BYTE,
          [1, _size, _size, 3], 0, FirebaseModelDataType.BYTE, [1, 128]),
      imageToByteList(image));
  return results;
}

// int model
Uint8List imageToByteList(img.Image image) {
  var _inputSize = _size;
  var convertedBytes = Uint8List(1 * _inputSize * _inputSize * 3);
  var buffer = ByteData.view(convertedBytes.buffer);
  int pixelIndex = 0;
  for (var i = 0; i < _inputSize; i++) {
    for (var j = 0; j < _inputSize; j++) {
      var pixel = image.getPixel(i, j);
      buffer.setUint8(pixelIndex, (pixel >> 16) & 0xFF);
      pixelIndex++;
      buffer.setUint8(pixelIndex, (pixel >> 8) & 0xFF);
      pixelIndex++;
      buffer.setUint8(pixelIndex, (pixel) & 0xFF);
      pixelIndex++;
    }
  }
  return convertedBytes;
}
