# Smart Thermostat App

A Flutter-based mobile application for controlling a smart thermostat system. This app provides a modern and intuitive interface for managing your home's temperature, schedules, and automation features.

## Features

- Real-time temperature monitoring and control
- Multiple operation modes (Heat, Cool, Auto, Off)
- Schedule management for automated temperature control
- Weather information integration
- Geofencing support for location-based automation
- Dark/Light theme support
- Temperature unit conversion (Celsius/Fahrenheit)
- 12/24 hour time format support

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Android Studio / VS Code with Flutter extensions
- Firebase project setup
- ESP8266-based thermostat hardware

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/termostat_app.git
```

2. Install dependencies:
```bash
cd termostat_app
flutter pub get
```

3. Configure Firebase:
   - Create a new Firebase project
   - Add your Android/iOS app to the project
   - Download and add the configuration files:
     - `google-services.json` for Android
     - `GoogleService-Info.plist` for iOS
   - Enable Firebase Realtime Database

4. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── models/           # Data models
├── providers/        # State management
├── screens/          # App screens
├── widgets/          # Reusable widgets
├── services/         # API and service integrations
└── utils/           # Utility functions and constants
```

## Dependencies

- `firebase_core`: Firebase integration
- `firebase_database`: Real-time database
- `provider`: State management
- `shared_preferences`: Local storage
- `geolocator`: Location services
- `geocoding`: Address lookup
- `intl`: Internationalization
- `fl_chart`: Data visualization
- `flutter_local_notifications`: Push notifications
- `google_fonts`: Custom typography
- `flutter_svg`: SVG support
- `flutter_animate`: Animations

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter team for the amazing framework
- Firebase for the backend services
- All contributors who have helped shape this project
