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

void setup() {
  Serial.begin(115200);

  pinMode(rolePin, OUTPUT);
  digitalWrite(rolePin, LOW);  // cihaz açılırken kapalı başlasın

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
  bool newHeatingState = lastHeatingState;   // default: eski değer

  // Firebase'den oku (başarısız olursa mevcut değer korunacak)
  if (Firebase.getBool(fbdo, "/devices/device1/isHeating")) {
    newHeatingState = fbdo.boolData();
  } else {
    Serial.println("[WARN] Firebase okunamadı → eski değer korunuyor.");
  }

  // Eğer değiştiyse röleyi güncelle
  if (newHeatingState != lastHeatingState) {
    lastHeatingState = newHeatingState;

    // Röle sür
    digitalWrite(rolePin, lastHeatingState ? HIGH : LOW);

    Serial.print("[RÖLE] Yeni durum: ");
    Serial.println(lastHeatingState ? "ON" : "OFF");
  }

  delay(10000); // 10 saniye (eskiden 5sn idi, Firebase kotası için artırıldı)
}