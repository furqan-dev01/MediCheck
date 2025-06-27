import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import "package:flutter/foundation.dart"
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDjjdIYj-66YzUHnvFg17RIAXCLaalPPFg',
    appId: '1:954288195387:web:d3feb69d299794938c591e',
    messagingSenderId: '954288195387',
    projectId: 'mediweb-8f590',
    authDomain: 'mediweb-8f590.firebaseapp.com',
    storageBucket: 'mediweb-8f590.firebasestorage.app',
    measurementId: 'G-CLQR41ERW8',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDjjdIYj-66YzUHnvFg17RIAXCLaalPPFg',
    appId: '1:954288195387:android:YOUR_ANDROID_APP_ID',
    messagingSenderId: '954288195387',
    projectId: 'mediweb-8f590',
    storageBucket: 'mediweb-8f590.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDjjdIYj-66YzUHnvFg17RIAXCLaalPPFg',
    appId: '1:954288195387:ios:YOUR_IOS_APP_ID',
    messagingSenderId: '954288195387',
    projectId: 'mediweb-8f590',
    storageBucket: 'mediweb-8f590.firebasestorage.app',
    iosClientId: 'YOUR_IOS_CLIENT_ID',
    iosBundleId: 'YOUR_IOS_BUNDLE_ID',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDjjdIYj-66YzUHnvFg17RIAXCLaalPPFg',
    appId: '1:954288195387:macos:YOUR_MACOS_APP_ID',
    messagingSenderId: '954288195387',
    projectId: 'mediweb-8f590',
    storageBucket: 'mediweb-8f590.firebasestorage.app',
    iosClientId: 'YOUR_MACOS_CLIENT_ID',
    iosBundleId: 'YOUR_MACOS_BUNDLE_ID',
  );
} 