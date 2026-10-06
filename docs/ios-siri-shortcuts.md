# iOS Native App Intents & Siri Kestirmeleri Kılavuzu

Bu belge, **Termostat** iOS uygulamasında ekranı açmadan (arka planda) Firebase Realtime Database'e komut gönderen native **App Intents** ve **Siri Shortcuts** mimarisinin kurulumunu, kullanımını, güvenlik detaylarını ve gerçek cihaz test matrisini açıklar.

---

## 1. Mimariye Genel Bakış

Eski sistemde Siri veya widget komutları `termostat://heating-on` gibi URL şemaları (deep link) üzerinden çalışmaktaydı. Bu durum uygulamanın ön plana açılmasını (foreground), Flutter engine'in ayağa kalkmasını, `HomeScreen` ve `BuildContext` oluşmasını zorunlu kılıyordu.

Yeni mimaride komut akışı tamamen native ve arka planda çalışır:

```
[Kullanıcı: "Hey Siri, Isıtmayı aç" veya Kestirme Dokunuşu]
                       │
                       ▼
       [iOS AppIntent: HeatingOnIntent]
                       │ (openAppWhenRun = false, authenticationPolicy = .alwaysAllowed)
                       ▼
      [ThermostatCommandService.swift]
                       │
       ┌───────────────┴────────────────┐
       ▼                                ▼
[Firebase Auth Oturumu]       [Database URL Doğrulama]
- Keychain'den restore        - HTTPS zorunluluğu
- Initial callback bekleme    - /devices/device1.json
- ID Token alma               - Query: auth=<idToken>
       │                                │
       └───────────────┬────────────────┘
                       ▼
   [REST PATCH İsteği (URLSession)]
   - turnOn:  {"mode": "on", "targetTemperature": 25.0}
   - turnOff: {"mode": "off", "isHeating": false}
                       │
       ┌───────────────┴────────────────┐
       ▼                                ▼
  [HTTP 200..299]               [HTTP 401 Unauthorized]
"Komut gönderildi"              - 1 kez token yenileme (forceRefresh: true)
Siri sesli/yazılı yanıtı        - Tekrar PATCH isteği
                                - Başarısız ise yetki hatası (döngü yok)
```

### Önemli Prensipler:
1. **Ekran Açılmaz:** `openAppWhenRun = false` tanımlıdır; sistem arayüzü göstermeden arka planda tamamlanır.
2. **Kullanıcı Kimliği ile Yetkilendirme:** Sabit privileged database secret (`firebaseSecret`) yerine kullanıcının Firebase Auth ID Token'ı kullanılır.
3. **Doğru Başarı Semantiği:** HTTP 2xx yanıtı, verinin Firebase'e başarıyla yazıldığını doğrular. Fiziksel kombi/röle histerezis kararı ESP firmware'ine aittir. Bu nedenle Siri yanıtı yanıltıcı biçimde "Kombi yandı" demez; *"Isıtmayı 25 dereceye ayarlama komutu gönderildi."* yanıtını verir.
4. **Fiziksel Röle Kararı Firmware'dedir:** Açma komutunda (`turnOn`) `isHeating: true` doğrudan yazılmaz; `mode: "on"` ve `targetTemperature: 25.0` tek bir atomik PATCH ile yazılır. Röle açma kararı ESP'deki sıcaklık farkına bırakılır. Kapatma komutunda (`turnOff`) Flutter davranışıyla tutarlı olarak `mode: "off"` ve `isHeating: false` yazılır.

---

## 2. Geliştirici ve Derleme Adımları (macOS / Xcode)

Projeyi gerçek cihazda çalıştırmak ve derlemek için macOS ortamında aşağıdaki adımları izleyin:

### A. Bağımlılıkların Kurulması
```bash
cd termostat_app
flutter pub get

cd ios
pod install
```

### B. Projenin Xcode'da Açılması
> **DİKKAT:** Asla `Runner.xcodeproj` dosyasını tek başına açmayın; CocoaPods kütüphanelerinin bağlanması için her zaman `.xcworkspace` dosyasını açmalısınız:

```bash
open Runner.xcworkspace
```

### C. Runner Target Kontrolleri
Xcode'da `Runner` projesini seçin:
1. **Signing & Capabilities:** Kendi Apple Developer hesabınızı (Team) seçin ve geçerli bir Provisioning Profile tanımlayın.
2. **Deployment Target:** Projenin asgari iOS hedefi (`13.0`) korunmuştur. App Intents dosyaları (`ThermostatIntents.swift`, `ThermostatShortcuts.swift`) `@available(iOS 16.0, *)` ile işaretlenmiştir. iOS 16 öncesi cihazlarda uygulama normal çalışmaya devam eder, iOS 16 ve sonrasında Siri özellikleri otomatik aktifleşir.
3. **Build Phases > Compile Sources:**
   - `AppDelegate.swift`
   - `ThermostatCommandService.swift`
   - `ThermostatIntents.swift`
   - `ThermostatShortcuts.swift`
4. **Build Phases > Copy Bundle Resources:**
   - `GoogleService-Info.plist` dosyasının bu listede yer aldığından emin olun.

### D. Xcode CLI ile Derleme ve Test
Unsigned veya cihaz testi için:
```bash
# Scheme ve hedefleri listeleme
xcodebuild -workspace Runner.xcworkspace -scheme Runner -showdestinations

# Simülatörde veya bağlı cihazda birim testleri çalıştırma:
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

---

## 3. İlk Kez Kullanım ve Kurulum (iPhone)

Kestirmelerin ve Siri'nin sorunsuz çalışabilmesi için telefon üzerinde şu tek seferlik adımların yapılması gerekir:

1. **Uygulamayı Açıp Giriş Yapın:**
   - Uygulama yüklendikten sonra bir defa açın.
   - E-posta ve şifrenizle Firebase Auth oturumu açın.
   - Bu adım, oturum anahtarlarını iOS Keychain'ine güvenli şekilde kaydeder.
   - Artık uygulamayı kapatabilirsiniz.

2. **Siri Kilit Ekranı İznini Kontrol Edin:**
   - iPhone'da **Ayarlar > Siri ve Arama** bölümüne gidin.
   - **"Kilitliyken Siri'ye İzin Ver"** (Allow Siri When Locked) seçeneğinin açık olduğundan emin olun.
   - Bu ayar kapalıysa, Apple güvenlik gereği kilit ekranında hiçbir Siri kestirmesini çalıştırmaz.

---

## 4. Kestirmeler (Shortcuts) Uygulamasında Eylemleri Yapılandırma

### A. Varsayılan Sesli Komutlar (App Shortcuts)
iOS 16+, uygulamayı yüklediğiniz anda aşağıdaki kalıpları Siri'ye otomatik tanıtır:
- *"Hey Siri, Termostat App ile ısıtmayı aç"*
- *"Hey Siri, Termostat App ile ısıtmayı kapat"*

### B. Özel İsimli Kestirme Oluşturma (Örn: "Evi Isıt")
Siri'ye uygulama ismini söylemeden tek bir kelimeyle komut vermek için:
1. iPhone'da **Kestirmeler (Shortcuts)** uygulamasını açın.
2. Sağ üstteki **+** (Yeni Kestirme) butonuna dokunun.
3. **"İşlem Ekle" (Add Action)** butonuna dokunun.
4. Arama çubuğuna **"Termostat"** yazın veya **"Uygulamalar"** sekmesinden **Termostat App**'i seçin.
5. Listede görünen iki native işlemden birini seçin:
   - **Isıtmayı aç** (Hedefi 25°C yapar)
   - **Isıtmayı kapat** (Isıtmayı durdurur)
6. Kestirmenin adını üstteki başlıktan değiştirin: örneğin **"Evi ısıt"** veya **"Kombiyi yak"**.
7. Artık Siri'ye sadece *"Hey Siri, Evi ısıt"* demeniz yeterlidir!

### C. Eski Kestirmelerden Geçiş (Migration)
Daha önceden tanımlanmış deep-link kestirmeleriniz varsa:
- Eski adım: `URL Aç` (`termostat://heating-on`)
- **Değişim:** Eski kestirmeyi düzenleyin, `URL Aç` eylemini silin, yerine yukarıdaki native **"Isıtmayı aç"** eylemini ekleyin.
- *Not:* Eski widget veya NFC bağlantılarınız bozulmaz; uygulamadaki `DeepLinkService` geriye dönük uyumluluk için varlığını sürdürmektedir.

---

## 5. Kilit Ekranı, Güvenlik ve Keychain Mimarisi

Kilit ekranında çalışma durumu hakkında teknik detaylar, SDK kaynak davranışları ve sınırlamalar:

### A. `.alwaysAllowed` Ne Yapar, Ne Yapmaz?
`HeatingOnIntent` içinde `authenticationPolicy = .alwaysAllowed` tanımlanmıştır. Bu ayar, iOS'a *"Kullanıcı bu eylemi kilit ekranında tetiklediğinde sistem varsayılanı olarak kilit açma penceresi çıkarma, arka planda çalıştırmayı dene"* talimatı verir. Ancak bu ayar tek başına Keychain şifrelemesini veya iOS güvenlik kısıtlamalarını aşamaz.

### B. Firebase iOS SDK Keychain Davranışı (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
Firebase iOS SDK kaynak kodunda (`FIRAuthKeychainServices`), kullanıcı kimlik bilgileri ve refresh token'ları iOS Keychain'inde varsayılan olarak `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` erişim özniteliğiyle saklanır.
- **Yeniden Başlatma Sonrası Kilitli Durum (İlk Kilit Açılmadan Önce - BFU):** Telefon yeniden başlatıldıktan sonra kullanıcı henüz bir kez bile PIN/FaceID girmemişse, Keychain verileri donanımsal Secure Enclave anahtarlarıyla şifrelidir. Bu durumda hiçbir arka plan süreci token okuyamaz; komut başarısız olur ve kilit açılması gerekir.
- **İlk Kilit Açıldıktan Sonraki Kilitli Durum (AFU):** Kullanıcı cihaz kilidini en az bir kez açtıktan sonra `AfterFirstUnlock` verileri bellekte erişilebilir kalır. Ancak kilitliyken AppIntent'in arka planda çalışıp çalışmayacağı; iOS sürümü, Siri'nin "Kilitliyken Siri'ye İzin Ver" ayarı, kurumsal cihaz yönetimi (MDM) profilleri ve sistemin bellek/güç politikalarına bağlıdır.
- **ÖNEMLİ UYARI:** Kilit ekranında arka planda çalışma konusunda **mutlak bir garanti verilemez**. Bu ortamda (Windows / CI) fiziksel bir iPhone cihazı üzerinde kilit ekranı testi **YAPILMAMIŞTIR**. Bu senaryolar mutlaka gerçek cihazda doğrulanmalıdır.

---

## 6. Güvenlik, Firebase Kuralları ve Credential Rotasyonu

### A. Sabit Privileged Secret Uyarısı
Projenin eski kodlarında (`AppDelegate.swift` geofence ve ESP kodları) `firebaseSecret` parametresi yer almaktadır.
- **Yeni Native Kod:** Yeni App Intents ve `ThermostatCommandService` kesinlikle bu sırrı **kullanmaz**. Yalnızca oturum açmış kullanıcının süreli Firebase Auth ID Token'ını kullanır.
- **Log Güvenliği:** Auth query parametresi, ID token veya hassas ağ yanıtları hiçbir log kaydında açık olarak yazdırılmaz.

### B. Firebase Realtime Database Güvenlik Kuralları
- **Genel `auth != null` Önerilmez:** Sadece `auth != null` tanımlamak, projedeki herhangi bir giriş yapmış kullanıcının projedeki tüm cihazları değiştirmesine izin verir ve güvenlik açığı oluşturur.
- **Varsayımsal Sahiplik Şeması Uygulanmamalıdır:** Bu kod deposunda kullanıcı-cihaz sahiplik şeması (örneğin kullanıcıların hangi cihazlara erişebileceğini tutan veritabanı düğümü) bulunmamaktadır. Dolayısıyla `device1` gibi sabit bypass'lar (`|| $deviceId === 'device1'`) güvenliği ihlal eder ve kaldırılmıştır.
- **Yönetici Sorumluluğu:** Firebase proje yöneticisi, üretim ortamına geçmeden önce kendi veritabanı şemasına uygun cihaz bazlı sahiplik/yetkilendirme kuralını (örneğin `root.child('user_devices').child(auth.uid).child($deviceId).exists()`) Firebase Console üzerinde kendisi tanımlamalıdır.

### C. Sabit Database Secret'ın Rotasyonu / İptali (Yönetici İşleri)
Eski `firebaseSecret` anahtarını iptal etmek Firebase Console üzerinden yöneticinin yapması gereken bir işlemdir:
1. **Doğrudan İptal Etmeyin:** ESP32 / ESP8266 cihazları ve iOS AppDelegate arka plan geofence servisi hâlâ bu eski sırrı kullanmaktadır. Eğer Firebase Console'dan secret anında silinirse fiziksel termostat ve konum otomasyonu anında kopar!
2. **Geçiş Planı:**
   - ESP cihazları Firebase REST Custom Token veya e-posta/şifre kimlik doğrulamasına geçirilmelidir.
   - Geofence servisi kullanıcı oturumuyla güncellenmelidir.
   - Bu geçişler tamamlandıktan sonra Firebase Console > Project Settings > Service Accounts > Database Secrets sekmesinden eski secret güvenle silinmelidir.

---

## 7. Hata Kodları ve Sorun Giderme

| Hata Mesajı / Kod | Olası Neden | Yapılması Gereken |
|---|---|---|
| *"Önce Termostat uygulamasında giriş yapmalısınız."* | Oturum açılmamış veya Keychain boş. | Termostat uygulamasını açın ve hesabınıza giriş yapın. |
| *"Bu termostatı kontrol etme yetkiniz doğrulanamadı."* (HTTP 401/403) | ID token süresi dolmuş ve yenilenememiş, hesap devre dışı veya Database Rules yazmayı engelliyor. | Uygulamada oturumu kapatıp açın; Firebase Security Rules ayarlarını kontrol edin. |
| *"İnternet bağlantısı kurulamadı."* | Cihazda hücresel veri veya Wi-Fi kapalı/ulaşılamıyor. | Cihazın internet bağlantısını kontrol edin. |
| *"Termostat komutu zaman aşımına uğradı."* | Ağ bağlantısı zayıf veya Firebase sunucusuna ulaşılamadı. | Tekrar deneyin. |
| Siri kilit ekranında yanıt vermiyor | "Kilitliyken Siri'ye İzin Ver" ayarı kapalı. | Ayarlar > Siri ve Arama > Kilitliyken Siri'ye İzin Ver'i açın. |
| *"Termostat bağlantı yapılandırması bulunamadı."* | `GoogleService-Info.plist` dosyası bundle'a dahil edilmemiş. | Xcode > Build Phases > Copy Bundle Resources altında dosyanın ekli olduğunu doğrulayın. |

---

## 8. Gerçek Cihaz Test Matrisi

> **DİKKAT:** Aşağıdaki matris henüz gerçek bir fiziksel cihaz üzerinde test **EDİLMEMİŞTİR**. Bu tablo, Codemagic/Xcode derlemesinden sonra Release veya TestFlight sürümünde bir iPhone üzerinde manuel olarak koşulması gereken test planıdır.

| # | Test Senaryosu | Beklenen Davranış | Doğrulama Yöntemi |
|---|---|---|---|
| **1** | Uygulama açık / Telefon kilitsiz | Siri eylemi çalışır, ekran değişmez, komut Firebase'e yazılır (mode=on, temp=25). | Firebase Console'dan veriyi gözlemleyin. |
| **2** | Uygulama arka planda / Telefon kilitsiz | Siri eylemi çalışır, uygulama ön plana GELMEZ, komut yazılır. | Siri "komut gönderildi" yanıtı verir. |
| **3** | Uygulama arka planda / Telefon kilitli | Siri kilit açma istemeden çalışır (cihaz izin verirse), ekran açılmaz, komut yazılır. | Ekran kilitliyken "Isıtmayı aç" deyin. |
| **4** | Uygulama kapalı (Killed) / Telefon kilitli | Uygulama arayüzü açılmaz, arka planda process ayağa kalkar, komut gönderilir. | App Switcher'dan uygulamayı yukarı kaydırıp kapatın, kilitli test edin. |
| **5** | Telefon yeniden başlatılmış (İlk kilit açılmış, sonra kilitlenmiş - AFU) | Keychain açıktır; Siri komutu iletmeyi dener. | Telefonu yeniden başlatın, PIN girin, kilitleyin ve test edin. |
| **6** | Telefon yeniden başlatılmış (Henüz HİÇ kilit açılmamış - BFU) | Keychain şifrelidir; Siri kilit açılmasını ister veya oturum hatası verir. | Yeniden başlatın, PIN girmeden Siri'yi tetikleyin. |
| **7** | İnternet bağlantısı yok (Uçak Modu) | Hata döner: "İnternet bağlantısı kurulamadı." Başarı yanıtı VERİLMEZ. | Uçak modunu açıp test edin. |
| **8** | Token süresi dolmuş | Servis HTTP 401 alır, otomatik bir kez token yeniler, komut başarıyla tamamlanır. | Eski token senaryosunda otomatik yenilemeyi doğrulayın. |
| **9** | Kullanıcı uygulamadan çıkış yapmış (Sign Out) | "Önce Termostat uygulamasında giriş yapmalısınız." hatası verilir; Firebase'e istek gitmez. | Çıkış yapıp Siri'yi çalıştırın. |
| **10** | Firebase yazma yetkisi yok (Rule engeli) | HTTP 403 alınır, "Bu termostatı kontrol etme yetkiniz doğrulanamadı." döner. | Firebase kurallarından write: false yaparak test edin. |
| **11** | Kilitliyken Siri ayarı kapalı | Siri kilit ekranında eylemi çalıştırmaz, cihazın kilidinin açılmasını ister. | Ayarlardan kilitli Siri iznini kapatıp test edin. |
| **12** | Kapatma komutu ("Isıtmayı kapat") | `mode: "off"`, `isHeating: false` yazılır, `targetTemperature` değiştirilmez. | Firebase Console'dan JSON ağacını inceleyin. |
