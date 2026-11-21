# Belge Asistanı ürün sitesi — ücretsiz yayınlama

Bu klasör statik bir tanıtım sitesi taslağıdır. Ücretsiz olarak GitHub Pages gibi statik site barındırma hizmetlerinde yayınlanabilir.

## Yayınlamadan önce zorunlu düzenlemeler
1. `iletisim.html`, `gizlilik.html`, `kvkk.html`, `kullanim.html` ve `iade.html` dosyalarındaki `[ ... ]` alanlarını gerçek bilgilerinizle doldurun.
2. Veri saklama, dosya işleme, yapay zekâ sağlayıcısına aktarım ve silme sürelerini gerçek teknik altyapınıza göre doğrulayın.
3. İade/cayma koşullarını dijital hizmet modelinize ve tüketici mevzuatına göre hukuken kontrol ettirin.
4. Uygulama Uptodown'da gerçekten yayınlanınca `index.html` içindeki indirme alanına gerçek mağaza bağlantısını ekleyin.
5. Premium satın alma akışı canlı iyzico hesabıyla test edilmeden gerçek satış başlatmayın.

## GitHub Pages ile ücretsiz yayınlama
1. GitHub hesabınızda yeni, herkese açık bir repository oluşturun (ör. `belge-asistani-site`).
2. Bu klasörün içindeki tüm dosyaları repository'nin kök dizinine yükleyin.
3. Repository → Settings → Pages bölümüne girin.
4. Build and deployment kısmında `Deploy from a branch`, Branch olarak `main` ve folder olarak `/ (root)` seçip Save'e basın.
5. GitHub Pages size `https://KULLANICI.github.io/belge-asistani-site/` biçiminde bir adres verir.
6. Adresi gizli sekmede açıp tüm sayfaları ve mobil görünümü test edin.

## Önemli
Bu paket site dosyalarını sağlar; kendiliğinden internete yüklemez ve canlı URL oluşturmaz. Site URL'sini ancak GitHub Pages yayını tamamlandıktan sonra iyzico başvurusunda kullanın. iyzico'nun işyeri kabulü, API erişimi ve ödeme alma onayı ayrıca gerekir.

## iyzico başvurusu için ek kontrol
- iyzico'nun güncel başvuru koşulları ürün ve fiyat bilgilerinin yayında olmasını; gizlilik, mesafeli satış, iade ve hakkımızda sayfalarının bulunmasını ister.
- İletişim sayfasında başvuru türünüze göre gerçek ticari unvan/ad-soyad, adres, e-posta, telefon, KEP ve ilgili sicil/vergi bilgileri istenebilir.
- SSL/HTTPS etkin olmalıdır. iyzico ve kart logolarını yalnızca iyzico'nun sağladığı/izin verdiği marka kullanım materyallerine göre ekleyin.
- Bu şablon başvuru onayı garantilemez. Güncel koşulları iyzico'nun resmi başvuru sayfasından kontrol edin: https://www.iyzico.com/isim-icin/hesap-olustur
