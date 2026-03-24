#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WiFiUdp.h>
#include <NTPClient.h>
#include <ArduinoJson.h>
#include <math.h>
#include <Adafruit_SHT31.h>
#include <Fonts/FreeSans9pt7b.h>

#if defined(ESP8266)
  #include <ESP8266WiFi.h>
  #include <WiFiClientSecure.h>
  #include <ESP8266HTTPClient.h>
#elif defined(ESP32)
  #include <WiFi.h>
  #include <WiFiClientSecure.h>
  #include <HTTPClient.h>
#endif

// ==== WIFI & FIREBASE ====
const char* WIFI_SSID  = "YOUR_WIFI_SSID";
const char* WIFI_PASS  = "YOUR_WIFI_PASSWORD";

#define FIREBASE_HOST   "termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app"
#define FIREBASE_SECRET "YOUR_FIREBASE_DATABASE_SECRET"

// ==== OPENWEATHERMAP ====
const char* OWM_API_KEY = "YOUR_OWM_API_KEY";
const char* OWM_CITY    = "Ankara";

// ==== OLED ====
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_ADDR 0x3C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// ==== Global dikey ofset (px) ====
const int Y_OFFSET = 8;

// ==== ESP32-C3 I2C pinleri ====
#define I2C_SDA 5
#define I2C_SCL 6

// ==== NTP (GMT+3) ====
WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "pool.ntp.org", 3 * 3600, 60000);

// ==== SHT30 ====
Adafruit_SHT31 sht30 = Adafruit_SHT31(); // 0x44/0x45

// ==== Quiet Hours (gece modu) ====
const uint8_t QUIET_START = 23;
const uint8_t QUIET_END   = 9;

// Opsiyonel: mavi LED (kırmızı power LED yazılımla kapanmaz)
const int  BUILTIN_LED_PIN  = 8;     // yoksa -1
const bool LED_ACTIVE_HIGH  = false; // ACTIVE-LOW kartlarda false

// ==== Ekran verileri ====
String timeStr = "17:00";
float  inTempF = 23.0;
int    inTempI = 23;
int    inTempD = 0;
int    inHum   = 60;
int    outTemp = 18;
bool   owmIconValid = false;
bool   isHeating = false;

String deviceMode = "off";   // "on" | "off"
float  targetTemp = 24.0;    // hedef

// Sıcaklık durumu (hava) enum
enum Weather { SUNNY, CLOUDY, RAINY };
Weather weather = RAINY;

// ==== OLED güç kontrol ====
bool g_oledOn = true;
void oledPower(bool on) {
  if (on && !g_oledOn) { display.ssd1306_command(SSD1306_DISPLAYON); g_oledOn = true; }
  else if (!on && g_oledOn) { display.ssd1306_command(SSD1306_DISPLAYOFF); g_oledOn = false; }
}
bool isQuietHour(int hh) {
  if (QUIET_START < QUIET_END) return (hh >= QUIET_START && hh < QUIET_END);
  return (hh >= QUIET_START || hh < QUIET_END);
}

// ==== HTTP helpers ====
bool httpsGET(const String& url, String& payload) {
  payload = "";
  WiFiClientSecure client; client.setTimeout(12000); client.setInsecure();
  HTTPClient https;
  if (!https.begin(client, url)) return false;
  int code = https.GET();
  if (code == HTTP_CODE_OK) { payload = https.getString(); https.end(); return true; }
  Serial.printf("[HTTPS] GET %d\n", code);
  https.end(); return false;
}
bool httpsPATCH(const String& url, const String& body) {
  WiFiClientSecure client; client.setTimeout(12000); client.setInsecure();
  HTTPClient https;
  if (!https.begin(client, url)) return false;
  https.addHeader("Content-Type", "application/json");
  int code = https.PATCH(body);
  if (code == HTTP_CODE_OK || code == HTTP_CODE_NO_CONTENT) { https.end(); return true; }
  Serial.printf("[HTTPS] PATCH %d\n", code);
  String resp = https.getString(); if (resp.length()) Serial.println(resp);
  https.end(); return false;
}

// ==== Firebase: termometre alanlarını güncelle ====
bool fbUpdateTempHum(float tempC, int hum, uint32_t epoch) {
  String url = "https://" + String(FIREBASE_HOST) + "/devices/device1.json?auth=" + String(FIREBASE_SECRET);
  String body = String("{\"currentTemperature\":") + String(tempC,1) +
                ",\"currentHumidity\":" + String(hum) +
                ",\"updatedAt\":" + String(epoch) + "}";
  return httpsPATCH(url, body);
}

// ==== Firebase: log/{tarih}/{saat} formatında sıcaklık/nem kaydet ====
bool fbLogTempHum(float tempC, int hum, uint32_t epoch) {
  // Tarih ve saat hesapla (GMT+3)
  time_t t = epoch;
  struct tm *tmx = gmtime(&t);
  char dateBuf[11], timeBuf[9];
  sprintf(dateBuf, "%04d-%02d-%02d", tmx->tm_year+1900, tmx->tm_mon+1, tmx->tm_mday);
  sprintf(timeBuf, "%02d:%02d:%02d", tmx->tm_hour, tmx->tm_min, tmx->tm_sec);

  String url = "https://" + String(FIREBASE_HOST) + "/log/" + String(dateBuf) + "/" + String(timeBuf) + ".json?auth=" + String(FIREBASE_SECRET);
  String body = String("{\"temperature\":") + String(tempC,1) +
                ",\"humidity\":" + String(hum) + "}";
  return httpsPATCH(url, body);
}

// ==== Firebase: mode/targetTemperature güncelle (Schedule aksiyonu) ====
bool fbApplySchedule(const String& mode, int target, uint32_t epoch) {
  String url = "https://" + String(FIREBASE_HOST) + "/devices/device1.json?auth=" + String(FIREBASE_SECRET);
  String body = String("{\"mode\":\"") + mode + "\"," +
                "\"targetTemperature\":" + String(target) + "," +
                "\"source\":\"schedule\"," +
                "\"updatedAt\":" + String(epoch) + "}";
  return httpsPATCH(url, body);
}

// ==== Firebase: isHeating PATCH ====
bool fbSetIsHeating(bool v, uint32_t epoch) {
  String url  = "https://" + String(FIREBASE_HOST) + "/devices/device1.json?auth=" + String(FIREBASE_SECRET);
  String body = String("{\"isHeating\":") + (v ? "true" : "false") +
                ",\"updatedAt\":" + String(epoch) + "}";
  return httpsPATCH(url, body);
}

// ==== Firebase snapshot: KÖK alanları oku ====
// DEĞİŞTİRİLDİ: 10sn → 30sn (Firebase kota tasarrufu)
const uint32_t DEVICE_POLL_MS = 30000;   // 30 sn
uint32_t lastDevicePoll = 0;

void pollDeviceSnapshot() {
  uint32_t now = millis();
  if (now - lastDevicePoll < DEVICE_POLL_MS) return;
  lastDevicePoll = now;
  if (WiFi.status() != WL_CONNECTED) return;

  String url = "https://" + String(FIREBASE_HOST) + "/devices/device1.json?auth=" + String(FIREBASE_SECRET);
  String payload;
  if (!httpsGET(url, payload)) { Serial.println("[DEV] GET fail"); return; }

  StaticJsonDocument<4096> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) { Serial.print("[DEV] JSON err: "); Serial.println(err.c_str()); return; }

  // MODE — KÖK
  if (!doc["mode"].isNull()) {
    String m = String((const char*)doc["mode"]); m.toLowerCase();
    if (m == "heating_on")  m = "on";
    if (m == "heating_off") m = "off";
    if (m == "on" || m == "off") deviceMode = m;
  }

  // TARGET — KÖK
  if (!doc["targetTemperature"].isNull()) {
    targetTemp = doc["targetTemperature"].as<float>();
  }

  // isHeating — KÖK
  if (!doc["isHeating"].isNull()) {
    isHeating = doc["isHeating"].as<bool>();
  }
}

// ==== Termostat kararı (histerezis 0.5°C) ====
const float HYST = 0.5f;

void thermostatDecideAndPush(float currentTemp) {
  if (WiFi.status() != WL_CONNECTED) return;

  bool desired = isHeating; // varsayılan: mevcut hali koru

  if (deviceMode == "off") {
    desired = false;                          // mode OFF → kapalı
  } else { // mode == "on"
    if (isHeating && currentTemp >= targetTemp)        desired = false;              // kapat
    else if (!isHeating && currentTemp <= (targetTemp - HYST)) desired = true;       // aç
  }

  if (desired != isHeating) {
    isHeating = desired;
    uint32_t epoch = timeClient.getEpochTime();
    bool ok = fbSetIsHeating(isHeating, epoch);
    Serial.printf("[CTRL] isHeating -> %s (%s)\n", isHeating ? "true" : "false", ok ? "PATCH OK" : "PATCH FAIL");
  }
}

// ==== Çizim yardımcıları ====
void drawDegreeSmallHollow(int x, int y){ display.drawCircle(x, y, 2, SSD1306_WHITE); }

// "ON" etiketi (yalnızca mode=on ve isHeating=true)
void drawHeatingIcon() {
  if (!(deviceMode == "on" && isHeating)) return;
  display.setFont();
  display.setTextSize(1);
  display.setCursor(110, 35); // sağ alt tarafa yakın
  display.print("ON");
}

void drawSun(int cx, int cy, int r=5) {
  display.fillCircle(cx, cy, r, SSD1306_WHITE);
  for (int i = 0; i < 12; i++) {
    float a = i * 30.0f * 3.14159f / 180.0f;
    int x1 = cx + (int)((r + 1) * cosf(a));
    int y1 = cy + (int)((r + 1) * sinf(a));
    int x2 = cx + (int)((r + 5) * cosf(a));
    int y2 = cy + (int)((r + 5) * sinf(a));
    display.drawLine(x1, y1, x2, y2, SSD1306_WHITE);
  }
}
void drawCloud(int x, int y, int w=26, int h=9) {
  display.fillCircle(x + w*0.25, y,   h/2, SSD1306_WHITE);
  display.fillCircle(x + w*0.50, y-2, h/2 + 1, SSD1306_WHITE);
  display.fillCircle(x + w*0.75, y,   h/2, SSD1306_WHITE);
  display.fillRoundRect(x, y, w, h/2 + 2, 2, SSD1306_WHITE);
}
void drawRain(int x, int y, int w=26, int h=9) {
  drawCloud(x, y, w, h);
  int startX = x + 3;
  for (int i = 0; i < 3; i++) {
    int lx = startX + i * (w / 4);
    display.drawLine(lx, y + h/2 + 2, lx - 1, y + h/2 + 7, SSD1306_WHITE);
  }
}
void drawWeatherIcon(Weather w, int cx, int cy) {
  switch (w) {
    case SUNNY:  drawSun(cx, cy, 5); break;
    case CLOUDY: drawCloud(cx-13, cy-4, 26, 9); break;
    case RAINY:  drawRain(cx-13, cy-4, 26, 9); break;
  }
}
void drawHeader() {
  display.setFont(); display.setTextSize(1);
  display.setCursor(0, 0 + Y_OFFSET); display.print(timeStr);
  if (owmIconValid) drawWeatherIcon(weather, 64, 12 + Y_OFFSET);
  if (WiFi.status() == WL_CONNECTED) {
    String outTxt = String(outTemp);
    const int rightEdge = 110;
    int16_t x1,y1; uint16_t w,h; display.getTextBounds(outTxt,0,0,&x1,&y1,&w,&h);
    display.setCursor(rightEdge - w, 0 + Y_OFFSET); display.print(outTxt);
    drawDegreeSmallHollow((rightEdge - w) + w + 3, 2 + Y_OFFSET);
  }
}
void drawBody() {
  const uint8_t IN_SIZE=3, HUM_SIZE=3; const int CHAR_H=8; int yTop=35+Y_OFFSET;

  display.setFont(); display.setTextSize(IN_SIZE);
  int xLeft=2; display.setCursor(xLeft,yTop); display.print(inTempI);
  int16_t x1,y1; uint16_t wI,hI; display.getTextBounds(String(inTempI),0,0,&x1,&y1,&wI,&hI);

  String fracTxt = "." + String(inTempD);
  int fracX = xLeft + wI + 3;

  display.setFont(&FreeSans9pt7b); display.setTextSize(1);
  int16_t fx,fy; uint16_t fw,fh; display.getTextBounds(fracTxt,0,0,&fx,&fy,&fw,&fh);

  int targetBottom = yTop + IN_SIZE * CHAR_H;
  int fracY = targetBottom - (fy + fh) - 3;
  display.setCursor(fracX, fracY); display.print(fracTxt);

  int degX = fracX + fw / 2;
  int degY = fracY - 22;
  drawDegreeSmallHollow(degX, degY);

  display.setFont(); display.setTextSize(HUM_SIZE);
  String humTxt = "%" + String(inHum);
  int16_t bx,by; uint16_t bw,bh; display.getTextBounds(humTxt,0,0,&bx,&by,&bw,&bh);
  int xRight = 125; display.setCursor(xRight - bw, yTop); display.print(humTxt);
}
void drawScreen() {
  display.clearDisplay();
  drawHeader();
  drawBody();
  drawHeatingIcon();
  display.display();
}

// ==== OpenWeather ====
bool fetchOpenWeather(int &tempOut, Weather &wOut) {
  if (strlen(OWM_API_KEY) < 8) return false;
  String url = "https://api.openweathermap.org/data/2.5/weather?q=" + String(OWM_CITY) +
               "&appid=" + String(OWM_API_KEY) + "&units=metric&lang=tr";
  String payload; if (!httpsGET(url, payload)) return false;
  StaticJsonDocument<1536> doc; if (deserializeJson(doc, payload)) return false;
  if (doc["cod"].isNull() == false && doc["cod"].as<int>() != 200) return false;
  if (doc["main"]["temp"].isNull()) return false;
  int t = (int)roundf(doc["main"]["temp"].as<float>());
  String icon = doc["weather"][0]["icon"] | "";
  Weather wMap = CLOUDY;
  if (icon.startsWith("01")) wMap = SUNNY;
  else if (icon.startsWith("09") || icon.startsWith("10") || icon.startsWith("11") || icon.startsWith("13")) wMap = RAINY;
  else wMap = CLOUDY;
  tempOut = t; wOut = wMap; return true;
}

// ==== SCHEDULES ====
// DEĞİŞTİRİLDİ: 15sn → 60sn (Firebase kota tasarrufu)
const uint32_t SCHEDULE_POLL_MS = 60000; // 60 sn
uint32_t lastSchedulePoll = 0;

// son tetiklenen anahtarları tutarak tekrar tekrar yazmayı önleyelim
struct FiredKey { String key; uint32_t ts; };
FiredKey firedBuf[8];
bool wasRecentlyFired(const String& key, uint32_t now) {
  for (int i=0;i<8;i++) if (firedBuf[i].key == key && (now - firedBuf[i].ts) < 90*1000UL) return true;
  return false;
}
void markFired(const String& key, uint32_t now) {
  int idx=0; uint32_t oldest=0xFFFFFFFF;
  for (int i=0;i<8;i++){ if (firedBuf[i].key.length()==0){ idx=i; break; } if (firedBuf[i].ts<oldest){ oldest=firedBuf[i].ts; idx=i; } }
  firedBuf[idx].key = key; firedBuf[idx].ts = now;
}

bool isToday(const String& isoDate, int y, int m, int d) {
  if (isoDate.length() < 10) return false;
  int yy = isoDate.substring(0,4).toInt();
  int mm = isoDate.substring(5,7).toInt();
  int dd = isoDate.substring(8,10).toInt();
  return (yy==y && mm==m && dd==d);
}

void ymdFromEpoch(uint32_t epoch, int gmtOffsetSec, int &Y, int &M, int &D, int &dow) {
  time_t t = epoch + gmtOffsetSec;
  struct tm *tmx = gmtime(&t);
  Y = tmx->tm_year + 1900; M = tmx->tm_mon + 1; D = tmx->tm_mday;
  dow = tmx->tm_wday;
}
int dowFromTm(int tm_wday) {
  int map[7] = {7,1,2,3,4,5,6};
  return map[tm_wday % 7];
}

void pollSchedulesAndApply() {
  uint32_t nowMs = millis();
  if (nowMs - lastSchedulePoll < SCHEDULE_POLL_MS) return;
  lastSchedulePoll = nowMs;

  if (WiFi.status() != WL_CONNECTED) return;

  uint32_t epoch = timeClient.getEpochTime();
  int Y,M,D,tmw; ymdFromEpoch(epoch, 0, Y,M,D,tmw);
  int dow = dowFromTm(tmw);
  int hh = timeClient.getHours();
  int mm = timeClient.getMinutes();

  String url = "https://" + String(FIREBASE_HOST) + "/schedules.json?auth=" + String(FIREBASE_SECRET);
  String payload;
  if (!httpsGET(url, payload)) { Serial.println("[SCH] GET fail"); return; }

  StaticJsonDocument<8192> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) { Serial.print("[SCH] JSON err: "); Serial.println(err.c_str()); return; }
  if (!doc.is<JsonObject>()) return;

  for (JsonPair kv : doc.as<JsonObject>()) {
    String schedId = kv.key().c_str();
    JsonObject sched = kv.value().as<JsonObject>();
    bool schedEnabled = sched["isEnabled"] | true;
    if (!schedEnabled) continue;

    JsonArray entries = sched["entries"].as<JsonArray>();
    if (entries.isNull()) continue;

    for (uint16_t i=0; i<entries.size(); i++) {
      JsonObject e = entries[i];
      bool en = e["isEnabled"] | false; if (!en) continue;

      String mode = e["mode"] | "heating_on";
      String repeat = e["repeat"] | "once";
      int target = e["targetTemperature"] | 20;

      int sH = e["startTimeHour"]   | 0;
      int sM = e["startTimeMinute"] | 0;
      int eH = e["endTimeHour"]     | -1;
      int eM = e["endTimeMinute"]   | -1;

      int eDOW = e["dayOfWeek"] | 1;
      String specDate = e["specificDate"] | "";

      bool matchStart = false;
      bool matchEnd   = false;

      if (repeat == "once") {
        if (isToday(specDate, Y,M,D)) {
          if (hh == sH && mm == sM) matchStart = true;
          if (eH >= 0 && eM >= 0 && hh == eH && mm == eM) matchEnd = true;
        }
      } else {
        if (dow == eDOW) {
          if (hh == sH && mm == sM) matchStart = true;
          if (eH >= 0 && eM >= 0 && hh == eH && mm == eM) matchEnd = true;
        }
      }

      String keyBase = schedId + "/" + String(i);
      String keyStart = keyBase + "/start";
      String keyEnd   = keyBase + "/end";

      if (matchStart && !wasRecentlyFired(keyStart, nowMs)) {
        bool ok = fbApplySchedule(mode, target, epoch);
        Serial.printf("[SCH] START %s entry[%u] -> %s, %dC : %s\n",
                      schedId.c_str(), i, mode.c_str(), target, ok?"OK":"FAIL");
        markFired(keyStart, nowMs);

        if (repeat == "once") {
          String urlEn = "https://" + String(FIREBASE_HOST) + "/schedules/" + schedId +
                         "/entries/" + String(i) + "/isEnabled.json?auth=" + String(FIREBASE_SECRET);
          httpsPATCH(urlEn, "false");
        }
      }

      if (matchEnd && !wasRecentlyFired(keyEnd, nowMs)) {
        if (mode == "heating_on") {
          bool ok2 = fbApplySchedule("heating_off", target, epoch);
          Serial.printf("[SCH] END %s entry[%u] -> heating_off : %s\n",
                        schedId.c_str(), i, ok2?"OK":"FAIL");
        }
        markFired(keyEnd, nowMs);
      }
    }
  }
}

// ==== SETUP / LOOP ====
uint32_t lastFbPush = 0;
uint32_t lastOwmPull = 0;
// DEĞİŞTİRİLDİ: 10sn → 30sn (Firebase kota tasarrufu)
const uint32_t FB_PERIOD_MS  = 30000;    // 30 sn (eskiden 10sn)
const uint32_t OWM_PERIOD_MS = 600000;   // 10 dk

// ==== LOG: Her 5 dakikada bir sıcaklık/nem logla ====
uint32_t lastLogPush = 0;
const uint32_t LOG_PERIOD_MS = 300000;   // 5 dakika

void wifiConnect() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  uint32_t start = millis();
  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) { delay(200); Serial.print("."); }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) { Serial.print("[WiFi] IP: "); Serial.println(WiFi.localIP()); }
  else Serial.println("[WiFi] Not connected!");
}

void setup() {
  Serial.begin(115200);

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);

  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
    Serial.println("OLED bulunamadı! (0x3C/0x3D ve SDA/SCL kontrol)");
    while (true) delay(100);
  }
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  if (BUILTIN_LED_PIN >= 0) {
    pinMode(BUILTIN_LED_PIN, OUTPUT);
    digitalWrite(BUILTIN_LED_PIN, LED_ACTIVE_HIGH ? LOW : HIGH);
  }

  wifiConnect();
  timeClient.begin();

  if (!sht30.begin(0x44)) {
    Serial.println("[SHT30] 0x44 yok, 0x45 deneniyor...");
    if (!sht30.begin(0x45)) Serial.println("[SHT30] 0x44/0x45 yok.");
    else Serial.println("[SHT30] OK @0x45");
  } else {
    Serial.println("[SHT30] OK @0x44");
  }

  if (WiFi.status() == WL_CONNECTED) {
    int tExt; Weather wExt;
    if (fetchOpenWeather(tExt, wExt)) { outTemp = tExt; weather = wExt; owmIconValid = true; }
    else owmIconValid = false;
  } else owmIconValid = false;
}

void loop() {
  timeClient.update();

  int hourNow = timeClient.getHours();
  bool quiet = isQuietHour(hourNow);
  oledPower(!quiet);

  char buf[6]; sprintf(buf, "%02d:%02d", timeClient.getHours(), timeClient.getMinutes());
  timeStr = String(buf);

  uint32_t now = millis();

  // SHT30 ölç + Firebase güncelle (30 saniyede bir)
  if (now - lastFbPush >= FB_PERIOD_MS) {
    float tC = sht30.readTemperature();
    float hP = sht30.readHumidity();
    if (!isnan(tC) && !isnan(hP)) {
      inTempF = roundf(tC * 10.0f) / 10.0f;
      inTempI = (int)inTempF;
      inTempD = (int)roundf((inTempF - (float)inTempI) * 10.0f);
      inHum   = (int)roundf(hP);

      // Termostat kararı ve isHeating PATCH (mode/target'a göre)
      thermostatDecideAndPush(inTempF);

      if (WiFi.status() == WL_CONNECTED) {
        uint32_t epoch = timeClient.getEpochTime();
        bool ok = fbUpdateTempHum(inTempF, inHum, epoch);
        Serial.println(ok ? "[FB] PATCH T/H OK" : "[FB] PATCH T/H FAIL");
      }
    } else {
      Serial.println("[SHT30] NaN");
    }
    lastFbPush = now;
  }

  // Sıcaklık/nem log kaydı (5 dakikada bir)
  if (now - lastLogPush >= LOG_PERIOD_MS) {
    if (WiFi.status() == WL_CONNECTED && !isnan(inTempF)) {
      uint32_t epoch = timeClient.getEpochTime();
      bool ok = fbLogTempHum(inTempF, inHum, epoch);
      Serial.println(ok ? "[LOG] OK" : "[LOG] FAIL");
    }
    lastLogPush = now;
  }

  // Schedules → mode/targetTemperature uygula (60 saniyede bir)
  pollSchedulesAndApply();

  // Cihaz kök snapshot (mode/target/isHeating) → harici değişiklikleri yakala (30 saniyede bir)
  pollDeviceSnapshot();

  // OWM periyodik (10 dakikada bir)
  if (WiFi.status() == WL_CONNECTED && (now - lastOwmPull >= OWM_PERIOD_MS)) {
    int tExt; Weather wExt;
    if (fetchOpenWeather(tExt, wExt)) { outTemp = tExt; weather = wExt; owmIconValid = true; }
    else owmIconValid = false;
    lastOwmPull = now;
  }

  if (!quiet) drawScreen();
  delay(300);
}
