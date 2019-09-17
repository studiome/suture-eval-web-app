import 'package:angular/angular.dart';
import 'package:angular_components/angular_components.dart';
import 'dart:html';
import 'dart:math';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../firebase_client.dart';

enum EditorToolMode { tracing, erasing, clearing }

@Component(
    selector: 'image-editor',
    templateUrl: 'image_editor_component.html',
    styleUrls: [
      'image_editor_component.css'
    ],
    providers: [
      materialProviders,
      popupBindings
    ],
    directives: [
      coreDirectives,
      MaterialButtonComponent,
      MaterialIconComponent,
      MaterialTooltipDirective,
      MaterialInkTooltipComponent,
      MaterialPopupComponent,
      ScorecardComponent,
      ScoreboardComponent,
      MaterialProgressComponent,
      MaterialSliderComponent,
    ],
    exports: [
      EditorToolMode,
    ])
class ImageEditorComponent implements OnInit {
  CanvasElement _rawImageCanvas;
  CanvasElement _tracedIamgeCanavas;
  CanvasRenderingContext2D _rawCtx;
  CanvasRenderingContext2D _tracedCtx;
  InputElement _fileInput;
  bool _isDrawing;
  File imageFile;
  String imageFileName;
  Point _startPoint;
  List<StreamSubscription> _mouseEventListeners;
  EditorToolMode toolMode;
  int canvasWidth;
  int canvasHeight;
  static const CANVAS_WIDTH_PX = 600;
  bool isEvalFinished;
  String biteCV, pitchCV, skewness, totalScore;
  int subjectiveScore;

  FirebaseClient client;

  ImageEditorComponent(this.client);

  void ngOnInit() {
    _fileInput = querySelector("#photo-file-input") as InputElement;
    imageFile == null;
    imageFileName = ' No File ';
    _rawImageCanvas = querySelector('#raw-canvas');
    _rawCtx = _rawImageCanvas.getContext('2d');
    canvasWidth = CANVAS_WIDTH_PX;
    canvasHeight = canvasWidth * 3 ~/ 4;
    _mouseEventListeners = new List();
    _isDrawing = false;
    biteCV = pitchCV = skewness = totalScore = '-----';
    isEvalFinished = true;
    subjectiveScore = 5;
  }

  void onFileInputClicked() {
    _fileInput.click();
  }

  void drawImage(Event event) {
    subjectiveScore = 5;
    _tracedIamgeCanavas = querySelector('#tracing-canvas');
    _tracedCtx = _tracedIamgeCanavas.getContext('2d');

    ImageElement _rawImage;
    try {
      imageFile = (event.target as FileUploadInputElement).files[0];
      imageFileName = imageFile.name;
    } catch (e) {
      print(e);
    }
    ;
    FileReader _reader = new FileReader();
    try {
      _reader.onLoad.listen((event) {
        _rawImage = new ImageElement(src: _reader.result);
        _rawImage.onLoad.listen((event) {
          canvasHeight = (canvasWidth * _rawImage.height) ~/ _rawImage.width;
          _rawImageCanvas.width = canvasWidth;
          _rawImageCanvas.height = canvasHeight;
          _tracedIamgeCanavas.width = canvasWidth;
          _tracedIamgeCanavas.height = canvasHeight;
          _rawCtx.drawImageScaled(_rawImage, 0, 0, canvasWidth, canvasHeight);
        });
      });
      _reader.readAsDataUrl(imageFile);
    } catch (e) {
      print(e);
    }
    ;
  }

  void trace() {
    toolMode = EditorToolMode.tracing;
    if (_mouseEventListeners.isEmpty) {
      draw();
    }
  }

  void erase() {
    toolMode = EditorToolMode.erasing;
    if (_mouseEventListeners.isEmpty) {
      draw();
    }
  }

  void draw() {
    _mouseEventListeners.add(_tracedIamgeCanavas.onMouseDown.listen((e) {
      _startTrace(e);
    }));
    _mouseEventListeners.add(_tracedIamgeCanavas.onMouseMove.listen((e) {
      Point _endPoint = e.offset;
      _drawLine(_startPoint, _endPoint);
      _startPoint = _endPoint;
    }));
    _mouseEventListeners.add(_tracedIamgeCanavas.onMouseUp.listen((e) {
      _endTrace(e);
    }));
  }

  void _startTrace(MouseEvent e) {
    _isDrawing = true;
    _startPoint = e.offset;
  }

  void _endTrace(MouseEvent e) {
    _isDrawing = false;
  }

  void _drawLine(Point startPoint, Point endPoint) {
    if (!_isDrawing) {
      return;
    } else {
      switch (toolMode) {
        case EditorToolMode.tracing:
          _tracedCtx.globalCompositeOperation = 'source-over';
          _tracedCtx.strokeStyle = 'blue';
          _tracedCtx.lineWidth = 4.0;
          break;
        case EditorToolMode.erasing:
          _tracedCtx.globalCompositeOperation = 'destination-out';
          _tracedCtx.lineWidth = 8.0;
          break;
        case EditorToolMode.clearing:
          break;
      }
      _tracedCtx.beginPath();
      _tracedCtx.moveTo(startPoint.x, startPoint.y);
      _tracedCtx.lineTo(endPoint.x, endPoint.y);
      _tracedCtx.stroke();
    }
  }

  void clear() {
    toolMode = EditorToolMode.clearing;
    _tracedCtx.clearRect(
        0, 0, _tracedIamgeCanavas.width, _tracedIamgeCanavas.height);
    for (StreamSubscription listener in _mouseEventListeners) {
      listener.cancel();
    }
    _mouseEventListeners.clear();
  }

  void uploadTracedImageToStorage() async {
    if (client.user == null) {
      return;
    }
    isEvalFinished = false;
    try {
      Blob _imageBlob = await _tracedIamgeCanavas.toBlob('image/png');
      Uuid _id = new Uuid();
      String _fileName = 'trace.' + _id.v1().toString() + '.' + imageFileName;
      Map<String, dynamic> _uploadData = {
        "userID": client.user.uid,
        "userEMail": client.user.email,
        "fileName": _fileName,
        "imageFile": imageFileName,
        "subjectiveScore": subjectiveScore,
      };
      client.createFirestoreEntity(_fileName, _uploadData);

      client.putImageFile(_imageBlob, _fileName);
      Map<String, dynamic> _result;
      client.getDocumentByName(_fileName).onSnapshot.listen((doc) {
        _result = doc.data();
        biteCV = (_result["biteCV"] as double).toStringAsFixed(3);
        pitchCV = (_result["pitchCV"] as double).toStringAsFixed(3);
        skewness = (_result["skewness"] as double).toStringAsFixed(3);
        totalScore = (_result["totalScore"] as double).toStringAsFixed(3);
        isEvalFinished = true;
      });
    } catch (e) {
      isEvalFinished = false;
    }
  }
}
