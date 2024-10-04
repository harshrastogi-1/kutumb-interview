import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inapp_notifications/flutter_inapp_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

int id = 0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Picker Demo',
      builder: InAppNotifications.init(),
      home: MyHomePage(title: 'Image Picker Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title});

  final String? title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<XFile>? _mediaFileList;
  bool isLoading = false;

  void _setImageFileListFromFile(XFile? value) {
    _mediaFileList = value == null ? null : <XFile>[value];
  }

  dynamic _pickImageError;
  bool isVideo = false;
  String? _retrieveDataError;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController maxWidthController = TextEditingController();
  final TextEditingController maxHeightController = TextEditingController();
  final TextEditingController qualityController = TextEditingController();
  final TextEditingController limitController = TextEditingController();
  var storage = FirebaseStorage.instance;

  Future<void> _onImageButtonPressed(
    ImageSource source, {
    required BuildContext context,
    bool isMultiImage = false,
    bool isMedia = false,
  }) async {
    PermissionStatus permissionStatus;
    if (context.mounted) {
      if (isVideo) {
        final XFile? file = await _picker.pickVideo(
            source: source, maxDuration: const Duration(seconds: 10));
      } else if (isMultiImage) {
        permissionStatus = await Permission.photos.request();
        if (permissionStatus.isGranted) {
          await _displayPickImageDialog(context, true, (double? maxWidth,
              double? maxHeight, int? quality, int? limit) async {
            try {
              final List<XFile> pickedFileList = isMedia
                  ? await _picker.pickMultipleMedia(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                      imageQuality: quality,
                      limit: limit,
                    )
                  : await _picker.pickMultiImage(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                      imageQuality: quality,
                      limit: limit,
                    );
              setState(() {
                _mediaFileList = pickedFileList;
              });
              saveImageToFireBase(_mediaFileList!.first.path);
            } catch (e) {
              setState(() {
                _pickImageError = e;
              });
            }
          });
        }
      } else if (isMedia) {
        permissionStatus = await Permission.photos.request();
        if (permissionStatus.isGranted) {
          await _displayPickImageDialog(context, false, (double? maxWidth,
              double? maxHeight, int? quality, int? limit) async {
            try {
              final List<XFile> pickedFileList = <XFile>[];
              final XFile? media = await _picker.pickMedia(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                imageQuality: quality,
              );
              if (media != null) {
                pickedFileList.add(media);
                setState(() {
                  _mediaFileList = pickedFileList;
                });
                saveImageToFireBase(pickedFileList.first.path);
              }
            } catch (e) {
              setState(() {
                _pickImageError = e;
              });
            }
          });
        }
      } else {
        permissionStatus = await Permission.camera.request();
        if (permissionStatus.isGranted) {
          await _displayPickImageDialog(context, false, (double? maxWidth,
              double? maxHeight, int? quality, int? limit) async {
            try {
              final XFile? pickedFile = await _picker.pickImage(
                source: source,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                imageQuality: quality,
              );
              setState(() {
                _setImageFileListFromFile(pickedFile);
              });
              saveImageToFireBase(_mediaFileList!.first.path);
            } catch (e) {
              setState(() {
                _pickImageError = e;
              });
            }
          });
        }
      }
    }
  }

  @override
  void deactivate() {
    super.deactivate();
  }

  @override
  void dispose() {
    maxWidthController.dispose();
    maxHeightController.dispose();
    qualityController.dispose();
    super.dispose();
  }

  Widget _previewImages() {
    final Text? retrieveError = _getRetrieveErrorWidget();
    if (retrieveError != null) {
      return retrieveError;
    }
    if (_mediaFileList != null) {
      return Semantics(
        label: 'image_picker_example_picked_images',
        child: ListView.builder(
          key: UniqueKey(),
          itemBuilder: (BuildContext context, int index) {
            final String? mime = lookupMimeType(_mediaFileList![index].path);

            return Semantics(
              label: 'image_picker_example_picked_image',
              child: kIsWeb
                  ? Image.network(_mediaFileList![index].path)
                  : (mime == null || mime.startsWith('image/')
                      ? Image.file(
                          File(_mediaFileList![index].path),
                          errorBuilder: (BuildContext context, Object error,
                              StackTrace? stackTrace) {
                            return const Center(
                                child:
                                    Text('This image type is not supported'));
                          },
                        )
                      : SizedBox()
                  // : _buildInlineVideoPlayer(index)
                  ),
            );
          },
          itemCount: _mediaFileList!.length,
        ),
      );
    } else if (_pickImageError != null) {
      return Text(
        'Pick image error: $_pickImageError',
        textAlign: TextAlign.center,
      );
    } else {
      return const Text(
        'You have not yet picked an image.',
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _handlePreview() {
    return _previewImages();
  }

  Future<void> retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return;
    }
    if (response.file != null) {
      if (response.type == RetrieveType.video) {
        isVideo = true;
        // await _playVideo(response.file);
      } else {
        isVideo = false;
        setState(() {
          if (response.files == null) {
            _setImageFileListFromFile(response.file);
          } else {
            _mediaFileList = response.files;
          }
        });
      }
    } else {
      _retrieveDataError = response.exception!.code;
    }
  }

  final storageRef = FirebaseStorage.instance.ref();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
      ),
      body: Center(
        child: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? FutureBuilder<void>(
                future: retrieveLostData(),
                builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.waiting:
                      return const Text(
                        'You have not yet picked an image.',
                        textAlign: TextAlign.center,
                      );
                    case ConnectionState.done:
                      return _handlePreview();
                    case ConnectionState.active:
                      if (snapshot.hasError) {
                        return Text(
                          'Pick image/video error: ${snapshot.error}}',
                          textAlign: TextAlign.center,
                        );
                      } else {
                        return const Text(
                          'You have not yet picked an image.',
                          textAlign: TextAlign.center,
                        );
                      }
                  }
                },
              )
            : _handlePreview(),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Semantics(
            label: 'image_picker_example_from_gallery',
            child: FloatingActionButton(
              onPressed: () {
                isVideo = false;
                _onImageButtonPressed(ImageSource.gallery, context: context);
              },
              heroTag: 'image0',
              tooltip: 'Pick Image from gallery',
              child: const Icon(Icons.photo),
            ),
          ),
          // Padding(
          //   padding: const EdgeInsets.only(top: 16.0),
          //   child: FloatingActionButton(
          //     onPressed: () {
          //       isVideo = false;
          //       _onImageButtonPressed(
          //         ImageSource.gallery,
          //         context: context,
          //         isMultiImage: true,
          //         isMedia: true,
          //       );
          //     },
          //     heroTag: 'multipleMedia',
          //     tooltip: 'Pick Multiple Media from gallery',
          //     child: const Icon(Icons.photo_library),
          //   ),
          // ),
          // Padding(
          //   padding: const EdgeInsets.only(top: 16.0),
          //   child: FloatingActionButton(
          //     onPressed: () {
          //       isVideo = false;
          //       _onImageButtonPressed(
          //         ImageSource.gallery,
          //         context: context,
          //         isMedia: true,
          //       );
          //     },
          //     heroTag: 'media',
          //     tooltip: 'Pick Single Media from gallery',
          //     child: const Icon(Icons.photo_library),
          //   ),
          // ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              onPressed: () {
                isVideo = false;
                _onImageButtonPressed(
                  ImageSource.gallery,
                  context: context,
                  isMultiImage: true,
                );
              },
              heroTag: 'image1',
              tooltip: 'Pick Multiple Image from gallery',
              child: const Icon(Icons.photo_library),
            ),
          ),
          if (_picker.supportsImageSource(ImageSource.camera))
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: FloatingActionButton(
                onPressed: () {
                  isVideo = false;
                  _onImageButtonPressed(ImageSource.camera, context: context);
                },
                heroTag: 'image2',
                tooltip: 'Take a Photo',
                child: const Icon(Icons.camera_alt),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: FloatingActionButton(
              onPressed: () async {
                await _showNotification();
              },
              heroTag: 'image1',
              tooltip: 'Pick Multiple Image from gallery',
              child: const Icon(Icons.notification_add),
            ),
          ),
        ],
      ),
    );
  }

  Text? _getRetrieveErrorWidget() {
    if (_retrieveDataError != null) {
      final Text result = Text(_retrieveDataError!);
      _retrieveDataError = null;
      return result;
    }
    return null;
  }

  Future<void> _displayPickImageDialog(
      BuildContext context, bool isMulti, OnPickImageCallback onPick) async {
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Add optional parameters'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: maxWidthController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'Enter maxWidth if desired'),
                ),
                TextField(
                  controller: maxHeightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'Enter maxHeight if desired'),
                ),
                TextField(
                  controller: qualityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'Enter quality if desired'),
                ),
                if (isMulti)
                  TextField(
                    controller: limitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: 'Enter limit if desired'),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('CANCEL'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                  child: const Text('PICK'),
                  onPressed: () {
                    final double? width = maxWidthController.text.isNotEmpty
                        ? double.parse(maxWidthController.text)
                        : null;
                    final double? height = maxHeightController.text.isNotEmpty
                        ? double.parse(maxHeightController.text)
                        : null;
                    final int? quality = qualityController.text.isNotEmpty
                        ? int.parse(qualityController.text)
                        : null;
                    final int? limit = limitController.text.isNotEmpty
                        ? int.parse(limitController.text)
                        : null;
                    onPick(width, height, quality, limit);
                    Navigator.of(context).pop();
                  }),
            ],
          );
        });
  }

  saveImageToFireBase(String img) async {
    setState(() {
      this.isLoading = true;
    });
    String imageName = img!
        .substring(img.lastIndexOf("/"), img.lastIndexOf("."))
        .replaceAll("/", "");

    // final byteData = await rootBundle.load(img);

    // final file = File('${systemTempDir.path}/$imageName.jpeg');
    // await file.writeAsBytes(byteData.buffer
    //     .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    File file = File(img);
    TaskSnapshot snapshot =
        await storage.ref().child("images/$imageName").putFile(file);
    _showNotification();
    if (snapshot.state == TaskState.success) {
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection("images")
          .add({"url": downloadUrl, "name": imageName});
      setState(() {
        isLoading = false;
      });
      final snackBar = SnackBar(content: Text('Yay! Success'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      print('Error from image repo ${snapshot.state.toString()}');
      throw ('This file is not an image');
    }
  }

  Future<void> _showNotification() async {
    InAppNotifications.show(
        title: 'Image Uploaded',
        leading: Icon(
          Icons.fact_check,
          color: Colors.green,
          size: 50,
        ),
        ending: Icon(
          Icons.arrow_right_alt,
          color: Colors.red,
        ),
        description: 'Images uploaded Successfully ',
        onTap: () {});
  }
}

typedef OnPickImageCallback = void Function(
    double? maxWidth, double? maxHeight, int? quality, int? limit);
