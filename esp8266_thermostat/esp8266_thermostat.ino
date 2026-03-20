#include <ESP8266WiFi.h>
#include <FirebaseESP8266.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// WiFi credentials
#define WIFI_SSID "Xiaomi_8CEA"
#define WIFI_PASSWORD "kaandurukan09"

// Firebase credentials
#define FIREBASE_HOST "termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app/"
#define FIREBASE_AUTH "zHPpeMbreSIUSFwGaR5y9bxv7Tc5FHdW4IDj2ql1"

// Pin definitions
#define ONE_WIRE_BUS D2      // DS18B20 data pin
#define RELAY_PIN    D1      // Relay control pin

// Firebase paths
#define PATH_CURRENT_TEMP   "/thermostat/current_temp"
#define PATH_TARGET_TEMP    "/thermostat/target_temp"
#define PATH_HYSTERESIS    "/thermostat/hysteresis"
#define PATH_BOILER_STATUS "/thermostat/boiler_status"
#define PATH_MANUAL_OVERRIDE "/thermostat/manual_override"
#define PATH_USAGE_LOGS    "/usage_logs"

// Globals
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

float lastTargetTemp = 22.0;
float lastHysteresis = 0.5;
bool lastManualOverride = false;
String lastBoilerStatus = "OFF";

bool relayState = false; // false = OFF, true = ON
unsigned long relayOnTimestamp = 0;
unsigned long relayOffTimestamp = 0;
unsigned long lastTempUpload = 0;
unsigned long lastFirebaseRead = 0;

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW); // Relay OFF

  sensors.begin();

  // Connect to WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  Serial.println("\nWiFi connected!");

   config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
}

void loop() {
  unsigned long now = millis();

  // Read Firebase settings every 10 seconds
  if (now - lastFirebaseRead > 10000) {
    readFirebaseSettings();
    lastFirebaseRead = now;
  }

  // Read temperature and upload every 10 seconds
  if (now - lastTempUpload > 10000) {
    float temp = readTemperature();
    uploadTemperature(temp);
    controlRelay(temp);
    lastTempUpload = now;
  }
}

// Read temperature from DS18B20
float readTemperature() {
  sensors.requestTemperatures();
  float tempC = sensors.getTempCByIndex(0);
  Serial.print("Temperature: "); Serial.println(tempC);
  return tempC;
}

// Upload current temperature to Firebase
void uploadTemperature(float temp) {
  if (Firebase.setFloat(fbdo, PATH_CURRENT_TEMP, temp)) {
    Serial.println("Temperature uploaded to Firebase.");
  } else {
    Serial.print("Failed to upload temperature: ");
    Serial.println(fbdo.errorReason());
  }
}

// Read target temp, hysteresis, manual override, boiler status from Firebase
void readFirebaseSettings() {
  // Target temperature
  if (Firebase.getFloat(fbdo, PATH_TARGET_TEMP)) {
    lastTargetTemp = fbdo.floatData();
  }
  // Hysteresis
  if (Firebase.getFloat(fbdo, PATH_HYSTERESIS)) {
    lastHysteresis = fbdo.floatData();
  }
  // Manual override
  if (Firebase.getBool(fbdo, PATH_MANUAL_OVERRIDE)) {
    lastManualOverride = fbdo.boolData();
  }
  // Boiler status (for manual override)
  if (Firebase.getString(fbdo, PATH_BOILER_STATUS)) {
    lastBoilerStatus = fbdo.stringData();
  }

  Serial.print("Target: "); Serial.println(lastTargetTemp);
  Serial.print("Hysteresis: "); Serial.println(lastHysteresis);
  Serial.print("Manual Override: "); Serial.println(lastManualOverride);
  Serial.print("Boiler Status: "); Serial.println(lastBoilerStatus);
}

// Control relay based on logic and log usage
void controlRelay(float temp) {
  bool shouldBeOn = relayState;

  if (lastManualOverride) {
    shouldBeOn = (lastBoilerStatus == "ON");
  } else {
    if (temp < lastTargetTemp - lastHysteresis) shouldBeOn = true;
    else if (temp > lastTargetTemp + lastHysteresis) shouldBeOn = false;
    // else, keep current state (hysteresis band)
  }

  if (shouldBeOn != relayState) {
    setRelay(shouldBeOn);
  }
}

// Set relay state and log usage
void setRelay(bool on) {
  digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  relayState = on;

  // Update status in Firebase
  Firebase.setString(fbdo, PATH_BOILER_STATUS, on ? "ON" : "OFF");

  unsigned long now = millis();
  unsigned long epoch = getTime(); // Replace with NTP or RTC for real epoch

  if (on) {
    relayOnTimestamp = epoch;
    Serial.println("Relay ON");
  } else {
    relayOffTimestamp = epoch;
    Serial.println("Relay OFF");
    if (relayOnTimestamp > 0) {
      unsigned long duration = relayOffTimestamp - relayOnTimestamp;
      logUsageSession(relayOnTimestamp, relayOffTimestamp, duration);
      relayOnTimestamp = 0;
    }
  }
}

// Log usage session to Firebase
void logUsageSession(unsigned long onTime, unsigned long offTime, unsigned long duration) {
  String dateStr = getDateString(offTime); // e.g. "2024-06-01"
  String logPath = String(PATH_USAGE_LOGS) + "/" + dateStr;

  FirebaseJson logEntry;
  logEntry.set("on", onTime);
  logEntry.set("off", offTime);
  logEntry.set("duration", duration);

  if (Firebase.pushJSON(fbdo, logPath, logEntry)) {
    Serial.println("Usage log pushed to Firebase.");
  } else {
    Serial.print("Failed to log usage: ");
    Serial.println(fbdo.errorReason());
  }
}

// Helper: Get current epoch time (replace with NTP or RTC for real time)
unsigned long getTime() {
  // For demo, use millis()/1000 + a fixed offset (e.g. set at boot)
  // Replace with NTP or RTC for production!
  static unsigned long bootEpoch = 1717305600; // e.g. 2024-06-02 00:00:00 UTC
  return bootEpoch + millis() / 1000;
}

// Helper: Format date string from epoch (YYYY-MM-DD)
String getDateString(unsigned long epoch) {
  // Simple conversion for demo; use a proper time library for real use
  time_t t = epoch;
  struct tm *tm = gmtime(&t);
  char buf[11];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02d", tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
  return String(buf);
} 