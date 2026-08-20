import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Inicializa Firebase en el lado nativo (necesario para que el puente
    // APNs -> FCM funcione de forma fiable).
    FirebaseApp.configure()

    GeneratedPluginRegistrant.register(with: self)

    // Registrarse en APNs. Sin esto, iOS no genera token APNs y FCM no entrega.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // EL PUENTE que falta: entrega el token APNs a Firebase Messaging.
  // Sin esta línea, el token FCM del iPhone no queda ligado a APNs y NUNCA recibe.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotifications: deviceToken)
  }

  // Útil para diagnosticar: si APNs falla al registrar, lo verás en los logs.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("APNs registro FALLÓ: \(error)")
    super.application(application, didFailToRegisterForRemoteNotifications: error)
  }
}