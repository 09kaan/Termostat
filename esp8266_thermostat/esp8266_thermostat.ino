#include <ESP8266WiFi.h>
#include <WiFiManager.h>
#include <FirebaseESP8266.h>

// ==== Firebase =====
#define FIREBASE_HOST   "termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app"
#define FIREBASE_SECRET "YOUR_FIREBASE_DATABASE_SECRET"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// ==== Röle =====
const int rolePin = 0;

// En son stabil kaydedilen ısıtma durumu
bool lastHeatingState = false;
bool isHeating = false;
String deviceMode = "off";
float targetTemp = 24.0;
float currentTemp = 0.0;

// Histerezis (derece)
const float HYST = 0.5f;

void setup() {
  Serial.begin(115200);

  pinMode(rolePin, OUTPUT);
  digitalWrite(rolePin, HIGH);  // cihaz açılırken kapalı başlasın

  // ---- WiFi Manager ----
  WiFiManager wm;
  wm.autoConnect("KombiAyar");
  Serial.println("WiFi bağlandı!");

  // ---- Firebase ----
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_SECRET;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
}

void loop() {
  // WiFi kopmuşsa yeniden bağlan
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WARN] WiFi koptu, yeniden bağlanıyor...");
    WiFi.reconnect();
    delay(5000);
    return;
  }

  // 1) Firebase'den mode, targetTemp, currentTemp, isHeating oku
  readFirebaseState();

  // 2) Termostat kararı: sıcaklığa göre isHeating belirle
  thermostatDecide();

  // 3) Röleyi güncelle
  if (isHeating != lastHeatingState) {
    lastHeatingState = isHeating;
    digitalWrite(rolePin, isHeating ? LOW : HIGH);
    Serial.print("[RÖLE] Yeni durum: ");
    Serial.println(isHeating ? "ON" : "OFF");
  }

  delay(10000); // 10 saniye
}

// Firebase'den cihaz durumunu oku
void readFirebaseState() {
  // Mode oku
  if (Firebase.getString(fbdo, "/devices/device1/mode")) {
    String m = fbdo.stringData();
    m.toLowerCase();
    if (m == "heating_on") m = "on";
    if (m == "heating_off") m = "off";
    if (m == "on" || m == "off") {
      deviceMode = m;
    }
  } else {
    Serial.println("[WARN] mode okunamadı");
  }

  // Target temperature oku
  if (Firebase.getFloat(fbdo, "/devices/device1/targetTemperature")) {
    targetTemp = fbdo.floatData();
  } else {
    Serial.println("[WARN] targetTemperature okunamadı");
  }

  // Current temperature oku (ESP32 tarafından yazılıyor)
  if (Firebase.getFloat(fbdo, "/devices/device1/currentTemperature")) {
    currentTemp = fbdo.floatData();
  } else {
    Serial.println("[WARN] currentTemperature okunamadı");
  }

  // Mevcut isHeating durumunu oku
  if (Firebase.getBool(fbdo, "/devices/device1/isHeating")) {
    isHeating = fbdo.boolData();
  } else {
    Serial.println("[WARN] isHeating okunamadı");
  }

  Serial.printf("[STATE] mode=%s, target=%.1f, current=%.1f, isHeating=%s\n",
    deviceMode.c_str(), targetTemp, currentTemp, isHeating ? "true" : "false");
}

// Termostat kararı: sıcaklığa göre isHeating değiştir
void thermostatDecide() {
  bool desired = isHeating; // varsayılan: mevcut hali koru

  if (deviceMode == "off") {
    // Mode OFF → kesin kapat
    desired = false;
  } else {
    // Mode ON → sıcaklığa göre karar ver
    if (isHeating && currentTemp >= targetTemp) {
      desired = false;  // Hedefe ulaştı → kapat
    } else if (!isHeating && currentTemp <= (targetTemp - HYST)) {
      desired = true;   // Histerezis altına düştü → aç
    }
  }

  // Değiştiyse Firebase'e yaz
  if (desired != isHeating) {
    isHeating = desired;
    if (Firebase.setBool(fbdo, "/devices/device1/isHeating", isHeating)) {
      Serial.printf("[CTRL] isHeating -> %s (Firebase OK)\n", isHeating ? "true" : "false");
    } else {
      Serial.printf("[CTRL] isHeating -> %s (Firebase FAIL)\n", isHeating ? "true" : "false");
    }
  }
}