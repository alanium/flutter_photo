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
        'https://alanium.pythonanywhere.com/login_app/$user/$password'),
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
        primarySwatch: Colors.lightBlue,
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
      ResolutionPreset.max,
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
              'https://alanium.pythonanywhere.com/upload_photo/$loggedInUser/$selectedProjectId?url=$encodedImgUrl';

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
          'https://alanium.pythonanywhere.com/projects'));

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
      backgroundColor: Color.fromARGB(255, 17, 17, 17),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[

            SizedBox(height: 15.0),
            if (proyectos.isNotEmpty)
              DropdownButton<String>(
                value: selectedProjectId,
                items: proyectos.map((proyecto) {
                   final bool isSelected = proyecto['id'] == selectedProjectId;
                  return DropdownMenuItem<String>(
                    value: proyecto['id'],
                    child: Text(
                      truncateString(proyecto['name'], 30),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedProjectId = newValue;
                  });
                },
              ),

            SizedBox(height: 50.0),
            Container(
              width: 300,
              height: 45,
              child: ElevatedButton(
                onPressed: _pickImage,
                child: Text('Gallery'),
                style: ElevatedButton.styleFrom(
                  primary: Colors.white,
                  onPrimary: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0), // Cambia el valor para ajustar el radio del borde
                  ),                  
                ),
              ),
            ),

            SizedBox(height: 25.0),
            Container(
              width: 300,
              height: 45,
              child: ElevatedButton(
                onPressed: _openCamera,
                child: Text('Camera'),
                style: ElevatedButton.styleFrom(
                  primary: Colors.white,
                  onPrimary: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0), // Cambia el valor para ajustar el radio del borde
                  ),
                ),
              ),
            ),

              SizedBox(height: 40.0),
              Container(
                height: 200,
                width: MediaQuery.of(context).size.width,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey, width: 0.5),
                    bottom: BorderSide(color: Colors.grey, width: 0.5),                    
                  ),
                ),
                child: _imageFiles.isEmpty
                    ? Container()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(_imageFiles.length, (index) {
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 10.0),
                              child: Stack(
                                children: [
                                  Image.file(
                                    _imageFiles[index],
                                    height: 180,
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    left: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: GestureDetector(
                                        onTap: () => _removeImage(index),
                                        child: Container(
                                          height: 40,
                                          width: 40,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.black26,
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 30,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );                            
                          }),
                        ),
                      ),
              ),
              
            SizedBox(height: 40.0),
            Container(
              width: 300,
              height: 45,
              child: ElevatedButton(
                  onPressed: _sending
                  ? null
                  : () {
                      if (_imageFiles.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('there is nothing to send.'), // Mensaje si la lista está vacía
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sending...'), // Mensaje si la lista no está vacía
                            duration: Duration(seconds: 2),
                          ),
                        );
                        _sendMessage(); // Llama a la función _sendMessage después de mostrar el SnackBar
                      }
                    },
                child: Text('Send'),
                style: ElevatedButton.styleFrom(
                  primary: Colors.white,
                  onPrimary: Colors.black,
                  onSurface: Color.fromARGB(255, 175, 175, 175),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0), // Cambia el valor para ajustar el radio del borde
                  ),
                ),
              ),
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
      ResolutionPreset.max,
    );

    _initializeControllerFuture = _controller.initialize();
    await _initializeControllerFuture;
  }

  void toggleCamera() async {
    final newCameraIndex = selectedCamera == 0 ? 1 : 0;
    await _controller.dispose();
    setState(() {
      selectedCamera = newCameraIndex;
      showPreview = true;
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
      body: Stack(
        children: [
          Center(
            child: AnimatedOpacity(
              opacity: isTakingPhoto ? 0.0 : 1.0,
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
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              height: 120,
              color: Colors.black,
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
          ),
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
      backgroundColor: Color.fromARGB(255, 17, 17, 17),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            
            Image.asset('assets/logo.png', width: 50, height: 50),
            SizedBox(height: 100.0),
            Padding(
              padding: EdgeInsets.only(right: 190.0),
              child: Text(
                'Log In',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40.0,
                ),
              ),
            ),


            SizedBox(height: 25.0),
            Container(
              width: 300,
              height: 45,
              child: TextField(
                controller: _usernameController,
                style: TextStyle(color: Colors.grey.shade500),
                decoration: InputDecoration(
                  labelText: ' User',
                  labelStyle: TextStyle(color: Colors.grey.shade500),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700),  
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                ),
              ),
            ),

            SizedBox(height: 16.0),
            Container(
              width: 300,
              height: 45,
              child: TextField(
                controller: _passwordController,
                style: TextStyle(color: Colors.grey.shade500),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: ' Password',
                  labelStyle: TextStyle(color: Colors.grey.shade500),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700), // Establece el color del borde cuando el TextField no está enfocado
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                ),
              ),
            ),

            SizedBox(height: 16.0),
            if (_loginError)
              Text(
                'Incorrect credentials. I try again.',
                style: TextStyle(color: Colors.red),
              ),
            
            SizedBox(height: 25.0),
            Container(
              width: 300,
              height: 45,
              child: ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  primary: Colors.white,
                  onPrimary: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0), // Cambia el valor para ajustar el radio del borde
                  ),
                ),
                child: Text('Login'),
              ),
            ),

          ],
        ),
      ),
    );
  }
}