# BELGE ASİSTANI — TAM KAYNAK PAKETİ

Bu klasör; Android Flutter uygulama kaynaklarını, Node.js API/iyzico backend'ini ve ürün tanıtım sitesinin taslak dosyalarını içerir.

## Önemli: Bu ZIP henüz APK değildir

Bu çalışma ortamında Flutter SDK ve Android SDK bulunmadığı için imzalı/kurulabilir APK derlenemedi. Bu pakete APK varmış gibi sahte bir dosya eklenmemiştir. Aşağıdaki GitHub Actions iş akışı, projeyi GitHub'a yükledikten sonra APK'yı uzakta derleyip indirilebilir bir çıktı olarak oluşturur.

## APK oluşturma (GitHub Actions)

1. ZIP'i bilgisayarınızda açın.
2. GitHub'da yeni, boş bir depo oluşturun.
3. ZIP içindeki tüm dosya ve klasörleri deponun ana dizinine yükleyin. `.github` klasörünün de yüklendiğinden emin olun.
4. Deponun **Settings → Secrets and variables → Actions → Variables** bölümünde `BACKEND_BASE_URL` adlı bir Repository variable oluşturun. Değer, kuracağınız backend'in HTTPS adresi olmalı; örnek: `https://api.sizin-alan-adiniz.com`.
5. **Actions → Android APK Build → Run workflow** yoluyla derlemeyi başlatın.
6. İşlem başarılı olunca çalışmanın sayfasındaki **Artifacts** bölümünden `belge-asistani-android-apk` dosyasını indirin. ZIP içindeki `app-release.apk`, Android telefona kurulabilir APK'dır.

## Backend ve iyzico kurulumu

1. `backend/.env.example` dosyasını `.env` adıyla kopyalayın.
2. `AI_API_KEY`, `IYZICO_API_KEY`, `IYZICO_SECRET_KEY`, `PUBLIC_BASE_URL` ve diğer ayarları kendi sunucu bilgilerinizle doldurun.
3. Node.js 20+ ve kalıcı disk destekleyen HTTPS sunucuda `cd backend`, `npm install`, `npm start` komutlarını çalıştırın.
4. Önce iyzico sandbox anahtarlarıyla ödeme ve callback akışını test edin. Canlı anahtarları yalnızca iyzico hesabınız canlı tahsilata açıldıktan sonra kullanın.
5. SQLite veritabanının kalıcı diskte tutulduğunu doğrulayın.

**Güvenlik:** `.env` dosyasını, AI veya iyzico gizli anahtarlarını GitHub'a yüklemeyin. Bunlar yalnızca sunucuda tutulmalıdır.

## Ürün sitesi

`urun-sitesi/` klasörü statik ürün sitesi taslağıdır. İçindeki `[köşeli parantezli]` alanları gerçek işletme/iletişim bilgileriyle doldurmadan ve gizlilik, KVKK, satış/iade metinlerini gerçek işleyişinize göre kontrol etmeden iyzico başvurusuna göndermeyin. Site bu ZIP ile internette yayınlanmış olmaz; ayrıca ücretsiz bir statik hosting'e yüklenmelidir.

## Uygulamanın mevcut kapsamı ve test durumu

Kaynak kodu; belge seçme/yükleme, özetleme, belgeye soru sorma, çeviri, rapor/karşılaştırma ve dışa aktarma akışları için bir MVP içerir. Bu özelliklerin her dosya türünde ve gerçek cihazda doğrulanmış olduğu anlamına gelmez. Flutter derlemesi, Android cihaz testi, AI sağlayıcı bağlantısı ve iyzico sandbox/canlı ödeme testi yapılmadan uygulamayı herkese açık şekilde dağıtmayın.

Premium bedeli uygulama kodunda 299 TL tek seferlik olarak tanımlıdır; abonelik/otomatik yenileme değildir. Gerçek tahsilat ancak backend doğru yapılandırılıp iyzico tarafından onaylandıktan sonra çalışır.
