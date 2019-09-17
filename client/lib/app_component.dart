import 'package:angular/angular.dart';
import 'package:angular_components/angular_components.dart';
import 'src/image_editor/image_editor_component.dart';
import 'src/firebase_client.dart';

// AngularDart info: https://webdev.dartlang.org/angular
// Components info: https://webdev.dartlang.org/components

@Component(
    selector: 'suture-eval',
    styleUrls: [
      'package:angular_components/app_layout/layout.scss.css',
      'app_component.css'
    ],
    templateUrl: 'app_component.html',
    directives: [
      coreDirectives,
      ImageEditorComponent,
      MaterialButtonComponent,
      MaterialIconComponent,
      MaterialTemporaryDrawerComponent,
      MaterialToggleComponent,
      MaterialListComponent,
    ],
    providers: [
      ClassProvider(FirebaseClient),
    ])
class AppComponent {
  final FirebaseClient client;
  AppComponent(this.client);

  Future<void> signIn() async {
    await client.signIn();
  }

  void signOut() {
    client.signOut();
  }
}
