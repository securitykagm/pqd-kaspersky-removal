# PDQ - Kaspersky Endpoint Security & Network Agent Removal

Bu repo, domain ortamında **PDQ Deploy** kullanarak:
- **Kaspersky Endpoint Security for Windows (KES)**
- **Kaspersky Network Agent**

bileşenlerini tespit etmek ve kaldırmak için hazırlanmıştır.

> Scriptler **read-only tespit** ve **kontrollü kaldırma** akışına göre tasarlanmıştır.  
> Çalıştırmadan önce pilot grupta test edilmesi önerilir.

---

## Neden?

KES/Network Agent yönetim değişikliği, ürün geçişi veya agent temizliği süreçlerinde:
- Toplu kaldırma
- Standart log üretimi
- Başarısız kaldırmaları hızlı ayıklama

için PDQ ile otomasyon pratik bir çözümdür.

---

## Akış

1) Cihazda Kaspersky ürünleri var mı tespit eder

2) Kaspersky Endpoint Security ürününü kaldırır.

3) Kaspersky'ın Official Cleaner dosyası ile silent bir şekilde Network Agent kaldırmayı dener.  
   - Bazı ortamlarda kaldırma şifresi istenebilir (script içerisinde şifreyi güncelleyebilirsiniz)

---

## PDQ Kullanım (Önerilen)

<a href="https://media.kaspersky.com/utilities/CorporateUtilities/cleaner.zip">Kaspersky Cleaner Exe Dosyasına Buradan Ulaşabilirsiniz. Eğer güncelleme olursa aşağıda ilgili URL'i bırakıyorum.</a>
<br>
<a href="https://support.kaspersky.com/ksc/15.1/tools/13088#block6">Kaspersky Cleaner Docs Link</a>
<img width="1055" height="765" alt="image" src="https://github.com/user-attachments/assets/49e7b979-1a3e-4266-9e57-8f69108134b4" />


### Paket: KasperskyUninstall
- Step 1: **Copy File**
- File: `CopyFile içerisinden görseldeki gibi Folder -> Cleaner'ı indirdiğiniz klasörü seçin -> Target Folder için önerim C:\ProgramData\KasperskyCleaner`
- <img width="825" height="311" alt="image" src="https://github.com/user-attachments/assets/e667352e-9dec-41f2-9e1c-d6e2d0961dfc" />
- Options: `Include Subfolders ve Copy All Files seçili olmalı`
- Step 2: **Powershell**
- Repo içerisinde verdiğim Powershell Script içeriğini direkt kopyalayabilirsiniz.

---

## Güvenlik Notu
- Repo **secret/parola içermez**.
- Network Agent kaldırma şifresi gerekiyorsa script içerisindeki değişken değiştirilmelidir.
- Üretim ortamında yaygın dağıtım öncesi pilot test şarttır.
