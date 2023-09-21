import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await verifyUser(
      'username', 'password');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp(loggedIn: loggedIn));
}

Future<bool> verifyUser(String user, String password) async {
  final response = await http.get(
    Uri.parse(
        'https://contempoconstructiontx.pythonanywhere.com/login_app/$user/$password'),
  );

  if (response.statusCode == 200) {
    final jsonResponse = json.decode(response.body);
    final responseMessage = jsonResponse['response'];
    return responseMessage == 'True';
  } else {
    return false;
  }
}

class MyApp extends StatelessWidget {
  final bool loggedIn;

  MyApp({required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: loggedIn ? MyHomePage() : LoginScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final CollectionReference _messagesCollection =
      FirebaseFirestore.instance.collection('fotos');
  List<File> _imageFiles = [];

  final Reference storageReference =
      FirebaseStorage.instance.ref().child('images');

  String? selectedProjectId;
  bool _sending = false;

  Future<void> _pickImage() async {
    final imagePicker = ImagePicker();
    final pickedImage =
        await imagePicker.pickImage(source: ImageSource.gallery);

    if (pickedImage != null) {
      setState(() {
        _imageFiles.add(File(pickedImage.path));
      });
    }
  }

  bool _takingPictures = false;

  Future<void> _takePicture() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    final controller = CameraController(
      firstCamera,
      ResolutionPreset.medium,
    );

    await controller.initialize();

    setState(() {
      _takingPictures = true;
    });

    while (_takingPictures) {
      XFile xFile;
      try {
        xFile = await controller.takePicture();
      } catch (e) {
        break; // El usuario canceló la toma de fotos
      }

      setState(() {
        _imageFiles.add(File(xFile.path));
      });
    }

    await controller.dispose();

    setState(() {
      _takingPictures = false;
    });
  }

  Future<void> _printResponse(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        print(response.body);
      } else {
        print(
            'Error al obtener la respuesta del servidor. Código de estado: ${response.statusCode}');
      }
    } catch (e) {
      print('Error al realizar la solicitud HTTP: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_imageFiles.isNotEmpty && selectedProjectId != null && !_sending) {
      try {
        setState(() {
          _sending = true;
        });

        for (final imageFile in _imageFiles) {
          final String imageFileName =
              DateTime.now().millisecondsSinceEpoch.toString();
          final Reference imageRef = storageReference.child(imageFileName);

          final UploadTask uploadTask = imageRef.putFile(imageFile);
          final TaskSnapshot uploadSnapshot =
              await uploadTask.whenComplete(() {});
          final String imageUrl = await uploadSnapshot.ref.getDownloadURL();

          await _messagesCollection.add({
            'foto_url': imageUrl,
            //'timestamp': FieldValue.serverTimestamp(),
            'project_id': selectedProjectId,
            'user': loggedInUser
          });

          String encodedImgUrl = Uri.encodeComponent(imageUrl);

          print(imageUrl);
          print(encodedImgUrl);

          String apiUrl =
              'https://contempoconstructiontx.pythonanywhere.com/upload_photo/$loggedInUser/$selectedProjectId?url=$encodedImgUrl';

          await _printResponse(apiUrl);
        }

        print('Fotos enviadas con éxito');
        setState(() {
          _imageFiles.clear();
          _sending = false;
        });
      } catch (e) {
        print('Error al enviar las fotos: $e');
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  List<Map<String, dynamic>> proyectos = [];

  Future<void> obtenerListaDeProyectos() async {
    try {
      final response = await http.get(Uri.parse(
          'https://contempoconstructiontx.pythonanywhere.com/projects'));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        setState(() {
          proyectos = List<Map<String, dynamic>>.from(jsonResponse);
        });
      } else {
        throw Exception('Error al obtener la lista de proyectos');
      }
    } catch (e) {
      print('Error: $e');
      throw Exception('Error al obtener la lista de proyectos');
    }
  }

  String truncateString(String input, int maxLength) {
    if (input.length <= maxLength) {
      return input;
    } else {
      return input.substring(0, maxLength - 3) + '...';
    }
  }

  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    final capturedImages = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          cameras: cameras,
          capturedImages: _imageFiles,
        ),
      ),
    );

    if (capturedImages != null) {
      setState(() {
        _imageFiles = capturedImages;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    obtenerListaDeProyectos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(height: 15.0),
            Container(
              width: 250,
              child: ElevatedButton(
                onPressed: _pickImage,
                child: Text('Gallery'),
              ),
            ),

            SizedBox(height: 15.0),
            Container(
              width: 250,
              child: ElevatedButton(
                onPressed: _openCamera,
                child: Text('Camera'),
              ),
            ),

            SizedBox(height: 16.0),
            if (_imageFiles.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_imageFiles.length, (index) {
                    return Stack(
                      children: [
                        Image.file(
                          _imageFiles[index],
                          width: 170,
                          height: 170,
                        ),
                        Positioned(
                          top: 60,
                          right: 60,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              height: 50,
                              width: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 40,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              
            SizedBox(height: 16.0),
            Container(
              width: 250,
              child: ElevatedButton(
                onPressed: _sending ? null : _sendMessage,
                child: Text('Send'),
              ),
            ),
            if (proyectos.isNotEmpty)
              DropdownButton<String>(
                value: selectedProjectId,
                items: proyectos.map((proyecto) {
                  return DropdownMenuItem<String>(
                    value: proyecto['id'],
                    child: Text(
                      truncateString(proyecto['name'], 30),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedProjectId = newValue;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final List<File> capturedImages;

  CameraScreen({
    Key? key,
    required this.cameras,
    required this.capturedImages,
  }) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  int selectedCamera = 0;
  bool showPreview = true;

  initializeCamera(int cameraIndex) async {
    _controller = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _controller.initialize();
    await _initializeControllerFuture;
  }

  void toggleCamera() async {
    final newCameraIndex = selectedCamera == 0 ? 1 : 0;
    await _controller.dispose();
    setState(() {
      selectedCamera = newCameraIndex;
      showPreview = true; // Mostrar la vista previa de nuevo
    });
    initializeCamera(selectedCamera);
  }

  bool isTakingPhoto = false;

  void takePhoto() async {
    if (!isTakingPhoto) {
      setState(() {
        isTakingPhoto = true;
      });

      await _initializeControllerFuture;
      var xFile = await _controller.takePicture();

      setState(() {
        widget.capturedImages.add(File(xFile.path));
        isTakingPhoto = false;
      });
    }
  }

  @override
  void initState() {
    initializeCamera(0);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
            height: 100,
            color: Colors.black,
          ),

          AnimatedOpacity(
            opacity: isTakingPhoto ? 0.0 : 1.0, // Cambiar opacidad cuando se está tomando una foto
            duration: Duration(milliseconds: 100),
            child: FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return CameraPreview(_controller);
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),

          Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context, widget.capturedImages);
                  },
                  child: Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(
                      Icons.home,
                      size: 40,
                      color: Colors.black,
                    ),
                  ),
                ),

                GestureDetector(
                  onTap: () {
                    if (showPreview) {
                      takePhoto();
                    }
                  },
                  child: Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),

                GestureDetector(
                  onTap: toggleCamera,
                  child: Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(
                      Icons.cameraswitch,
                      size: 40,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Spacer(),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

String? loggedInUser;

class _LoginScreenState extends State<LoginScreen> {
  TextEditingController _usernameController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  bool _loginError = false;

  Future<void> _login() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    final loggedIn = await verifyUser(username, password);

    if (loggedIn) {
      // Si el inicio de sesión es exitoso, establece el estado loggedIn en true y redirige a MyHomePage
      loggedInUser = username; // Asigna el usuario a la variable global
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => MyHomePage()),
      );
    } else {
      // Si el inicio de sesión falla, muestra un mensaje de error
      setState(() {
        _loginError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign-in')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_loginError)
              Text(
                'Incorrect credentials. I try again.',
                style: TextStyle(color: Colors.red),
              ),
            SizedBox(height: 16.0),
            Container(
              width: 250,
              height: 40,
              child: TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(5.0), // Bordes redondeados
                  ),
                ),
              ),
            ),
            SizedBox(height: 16.0),
            Container(
              width: 250,
              height: 40,
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(5.0), // Bordes redondeados
                  ),
                ),
              ),
            ),
            SizedBox(height: 15.0),
            Container(
              width: 250,
              child: ElevatedButton(
                onPressed: _login,
                child: Text('Sign-In'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}