import 'package:firebase/firebase.dart' as firebase;
import 'package:firebase/firestore.dart' as firestore;
import 'dart:html';

class FirebaseClient {
  firebase.StorageReference _storageRef;
  firebase.Auth _auth;
  firebase.User user;
  firestore.CollectionReference _collectionRef;
  static const collectionName = "YOUR-COLLECTION";

  FirebaseClient() {
    firebase.initializeApp(
        apiKey: "YOUR-API-KEY",
        authDomain: "YOUR-AUTH",
        databaseURL: "YOUR-DB",
        projectId: "YOUR-PROJECT",
        storageBucket: "YOUR-STORAGE",
        messagingSenderId: "YOUR-MESSAGING-SENDER");
    this._storageRef = firebase.storage().ref('');
    this._auth = firebase.auth();
    this._collectionRef = firebase.firestore().collection(collectionName);
    this._auth.onAuthStateChanged.listen((_user) {
      this.user = _user;
    });
  }
  void signIn() {
    _auth.signInWithPopup(new firebase.GoogleAuthProvider());
  }

  void signOut() {
    _auth.signOut();
  }

  void putImageFile(Blob blob, String fileName) {
    if (user != null) {
      _storageRef.child(fileName).put(blob);
    }
  }

  void createFirestoreEntity(
          String documentName, Map<String, dynamic> data) async =>
      await _collectionRef.doc(documentName).set(data);

  firestore.DocumentReference getDocumentByName(String documentName) {
    return _collectionRef.doc(documentName);
  }
}
