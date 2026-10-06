# Termostat widget kurulumu

## Paketin durumu

Temel GitHub commit'i: `7de493f` (pb).
Paket, önceki sıcaklık kestirmesi paketinin güncellenmiş halini de içerir.
Native “Isıtmayı aç” hedef sıcaklığı değiştirmez; yalnızca `mode=on` yazar.
Native “Sıcaklığı ayarla” hedefi değiştirir ve ısıtma modunu açar.

**Bu paket burada Xcode ile derlenmedi ve fiziksel cihazda test edilmedi.**
Statik kontroller iOS build/test yerine geçmez. Önce ayrı bir branch'te deneyin.

## Eklenenler

- Onaylanan açık/koyu tasarıma uygun küçük ve orta boy WidgetKit görünümü.
- Gerçek oda sıcaklığı, hedef, nem ve röle durumu.
- Orta widget'ta native aç/kapat ve 0,5°C artır/azalt düğmeleri.
- iOS 17+ widget extension; ana uygulamanın mevcut minimum sürümü korunur.
- Xcode extension target, Runner'a gömme ve App Groups entitlements.
- Firebase Auth'un resmi shared-Keychain API'si üzerinden ortak oturum.
- App Group içinde yalnızca sensör/durum JSON'u; parola/token saklanmaz.
- Veri yokken uydurma sıcaklık yok. Preview/placeholder değerleri yalnızca tasarım içindir.
- Son başarılı sunucu okuma / uygulama verisi alım zamanı gösterilir. Bu, sensörün fiziksel ölçüm zamanı veya cihazın çevrimiçi olduğuna dair garanti değildir.
- 15 dakikadan eski kayıt “Eski veri” olarak işaretlenir.
- Komut kabulü sensörün güncellik zamanını yenilemez ve fiziksel röle onayı sayılmaz.
- Geofence, ESP firmware ve eski URL kestirmeleri değiştirilmedi.

## 1. Dosyaları yükleme

ZIP içindeki dosyaları **proje köküne, klasör yapısını koruyarak** birleştirin.
Proje klasörünü silmeyin; dosyaları yalnızca aynı yolların üzerine yazın.
Alternatif yöntem: proje kökünde `git apply widget-integration.patch` çalıştırın.
İki yöntemi aynı anda kullanmayın.

Commit/push yapın. `pubspec.yaml` build numarası 23'tür. App Store Connect'te
23 veya üstü yüklüyse daha yüksek bir numara seçin. Codemagic'te sabit
`--build-number` override varsa onu da kontrol edin.

## 2. Apple Developer — gerekli manuel ayarlar

https://developer.apple.com/account/resources/ adresinde doğru takımı seçin.

1. Identifiers bölümünde bir **App Group** oluşturun:
   `group.com.example.termostatApp`
2. Mevcut ana App ID `com.example.termostatApp` için **App Groups** capability'sini
   açın ve yukarıdaki grubu ilişkilendirin.
3. Yeni explicit App ID oluşturun:
   `com.example.termostatApp.ThermostatWidget`
4. Yeni App ID'de de App Groups'u açın ve **aynı grubu** ilişkilendirin.
5. İki App ID için App Store distribution provisioning profillerini güncelleyin/
   yeniden oluşturun. Eski profil yeni capability'yi içermez.
6. Her iki profili aynı Apple takımına ve geçerli Apple Distribution sertifikasına
   bağlayın.

App Group başka bir Apple takımına aitse aynı ID'yi kullanamazsınız. Yeni ID
seçerseniz iki entitlements dosyası, `WidgetSnapshotStore.appGroupID` ve Dart
`WidgetService.appGroupId` değerlerini birlikte değiştirin.

Widget için ayrı bir App Store uygulama kaydı oluşturmayın; extension ana
uygulamanın IPA'sının içinde dağıtılır. Firebase'de ayrı auth projesi açmayın.

Firebase shared-Keychain belgeleri App Group'u user access group olarak
kullanmayı destekler:
https://firebase.google.com/docs/auth/ios/single-sign-on

## 3. Codemagic imzalama

### Mevcut TestFlight workflow'unu koruyarak

İmzalama kurulumunuzun hem ana uygulamayı hem widget extension'ı kapsaması gerekir.
Sadece ana uygulamaya ait eski profili indiren yapı yeterli değildir.

API ile `fetch-signing-files` kullanan özel script'iniz varsa, App Groups ayarları
Apple Portal'da yapıldıktan sonra iki bundle ID için de profil alın:

- `com.example.termostatApp`
- `com.example.termostatApp.ThermostatWidget`

Mevcut issuer/key/certificate ayarlarınızı kullanın. Yeni private key üretmek
zorunlu değildir; secret değerlerini repoya veya sohbete koymayın.

`xcode-project use-profiles` çıktısında **Runner ve ThermostatWidgetExtension**
hedeflerine ayrı doğru profiller atanmış olmalı. Export seçeneklerinde iki
bundle ID de bulunmalı.

### Eklenen isteğe bağlı workflow

`codemagic.yaml` içindeki `ios-widget-signed-artifact`, iki güncellenmiş profili
ve sertifikayı Codemagic Team settings > Code signing identities bölümüne
yüklemişseniz signed IPA üretir. Ana bundle ID ile eşleşen extension profilleri
Codemagic tarafından da seçilir.

**Bu ek workflow otomatik TestFlight yayını yapmaz.** Mevcut publishing
ayarlarınızı ayrıca kullanın. Var olan API entegrasyonunuz bu YAML workflow'una
kendiliğinden taşınmış kabul edilmemelidir.

Signing referansı:
https://docs.codemagic.io/yaml-code-signing/signing-ios/

## 4. Önce CI doğrulaması

Codemagic'te `ios-pr-unsigned-verification` workflow'unu main veya deneme
branch'i için manuel çalıştırın. Runner scheme artık widget extension'ı da
build eder. Swift testleri, extension ve release build doğrulanmalıdır.

Unsigned simülatörde App Group/Keychain erişimi gerçek signing koşullarıyla
aynı değildir. Swift testleri mock ağ/auth kullandığından production credential
ve canlı termostat gerekmez. Unsigned kontrol kilit ekranı/oturum paylaşımını
kanıtlamaz.

Kontrol çıktıları:
- `RunnerTests.xcresult`
- `xcodebuild_test.log`
- `flutter_release_build.log`

Ardından signed build/TestFlight kullanın.

## 5. iPhone'da ilk kurulum

1. Yeni signed sürümü TestFlight'tan yükleyin.
2. Uygulamayı açın. Oturum yeni ortak Keychain grubuna geçtiği için ilk
   yükseltmede **yeniden giriş yapmanız gerekebilir**. Bu beklenen bir durumdur;
   eski oturum sessizce kopyalanmaz, token dışarı aktarılmaz.
3. Gerçek termostat verisinin uygulamaya gelmesini bekleyin.
4. Ana ekrana uzun basın > Widget ekle > Termostat.
5. Küçük veya orta boyu seçin.
6. İlk timeline/network okuması için kısa süre bekleyin.

Widget listede görünmüyorsa iOS 17+ kullandığınızı ve `.appex` paketinin IPA'ya
gömüldüğünü kontrol edin. Yanlış profile sahip widget eklemek görünmemesine veya
kurulum hatasına neden olabilir.

## 6. Kontrollerin davranışı

- Aç: mevcut hedefi korur, mode=on yazar.
- Kapat: mode=off ve isHeating=false yazar; hedefi değiştirmez.
- + / −: sunucudaki güncel hedefi okuyup 0,5°C değiştirir, 10–30°C sınırında
  tutar ve mode=on yazar. Yani kapalıyken sıcaklık düğmesine basmak ısıtma modunu
  açar. Uygulamayı foreground açmayı talep etmez.
- Her işlem asenkrondur. Hızlı art arda basmak yerine yeni değerin görünmesini
  bekleyin; farklı istemcilerin eşzamanlı ayarları için server transaction yoktur.
- HTTP kabulü fiziksel rölenin değiştiğini doğrulamaz.
- Karta (düğme olmayan bölgeye) dokunmak uygulamayı açar.
- Erişim yoksa veya hedef bilinmiyorsa kontrol düğmeleri devre dışıdır.

## 7. Gerçek cihaz kontrol listesi

- Küçük ve orta boy, açık/koyu tema.
- Farklı ekran boyutları ve Türkçe değerler (22,5).
- App açık/arka planda/kapalıyken gerçek veriyi görüntüleme.
- Aç komutunun hedefi değiştirmemesi; kapatın da hedefi koruması.
- ± düğmelerinin yarım derece değiştirmesi, limitlerde durması.
- İnternet kesilince eski veri/son kayıt uyarısı; uydurma değer olmaması.
- Logout sonrası widget verisinin temizlenmesi, düğmelerin işlem yapmaması.
- Oturum paylaşımı: app'e giriş sonrası widget ağ erişimi.
- Siri kestirmelerinin önceki davranışını koruması.
- Kilitli kullanım, yeniden başlatma sonrası ilk kilit açma koşulları.
- İmzasız testin değil signed IPA'nın cihazda kurulması.

WidgetKit zamanlaması sistem tarafından yönetilir; gerçek zamanlı sensör
stream'i veya her 15 dakikada kesin yenilenme garantisi yoktur. Daha güncel veri
için app açıldığında kayıtlar güncellenir; intent sonrası timeline yenilemesi
istenir. App Check enforcement etkinse REST erişimi ayrıca yapılandırılmalıdır;
bu paket korumayı kapatmaz.

## 8. Güvenlik sınırı

Yeni widget hiçbir sabit database secret kullanmaz. Firebase Database Rules
cihaz bazlı kullanıcı yetkisini doğrulamalıdır. Kuralları auth!=null veya
.write=true ile gevşetmeyin.

Repo'da daha önceden bulunan geofence/ESP credential'ının iptali ve güvenli
geçişi bu paketten ayrı bir yönetici işidir. Bu paket eski credential'ı geçerli
ve güvenli hale getirmez. Oturum/token/secret loglanmamalı veya ZIP/repoya eklenmemelidir.
