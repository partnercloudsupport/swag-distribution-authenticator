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
import 'package:meta/meta.dart';

const _inputSize = 128;
const vectorCollectionName = 'face_vectors';
const _cnnModelName = 'facenet-mobile-8bits';

/// Converts an image file into embeddings.
Future<List<int>> convertToVector(File f) async {
  FirebaseModelInterpreter interpreter = FirebaseModelInterpreter.instance;

  //TODO: run this only once
  FirebaseModelManager.instance.registerCloudModelSource(
      FirebaseCloudModelSource(modelName: _cnnModelName));

  img.Image image = img.decodeJpg(f.readAsBytesSync());
  image = img.copyResize(image, _inputSize, _inputSize);
  var results = await interpreter.run(
      _cnnModelName,
      FirebaseModelInputOutputOptions(
          0,
          FirebaseModelDataType.BYTE,
          [1, _inputSize, _inputSize, 3],
          0,
          FirebaseModelDataType.BYTE,
          [1, 128]),
      _imageToByteList(image));
  print('face converted into vector: $results');
  return results;
}

Future<void> saveVectorToDb(List<int> vector,
    {@required DocumentSnapshot session}) async {
  await session.reference.collection(vectorCollectionName).add({
    'vector': List.of(vector),
  });
}

Uint8List _imageToByteList(img.Image image) {
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
