# Ringkasan implementasi XLSMART Enterprise

**Status pada verifikasi staging 28 September 2026:** Helm revision **6** menjalankan image commit `d068943a46f0`. Login admin, penolakan signup, chat Vertex dan pencarian dokumen bersitasi telah diuji dalam browser di GKE. Ingress GKE dan sertifikat dipesan; verifikasi **HTTPS publik** menunggu status sertifikat `Active`. Ini lingkungan uji kesiapan produksi, bukan sertifikasi siap produksi.

## Yang sudah dikerjakan

| Area | Hasil |
| --- | --- |
| Repositori | Fork GitHub asli [xlsmartenterprise/onyx-enterprise](https://github.com/xlsmartenterprise/onyx-enterprise), berbasis Onyx `v4.8.1`: cabang `upstream-tracking` dan `xlsmart-main` telah dipublikasikan, dengan `xlsmart-main` sebagai default. Nama modul, tabel, dan service internal Onyx dipertahankan. |
| Branding | Nama **XLSMART Enterprise**, logo/favicon, tampilan login dan chat, metadata web, aset widget/ekstensi, serta identitas pada template deployment diperbarui. Skrip `scripts/apply_xlsmart_assets.sh` memulihkan aset branding setelah merge upstream. Build frontend dan pengujian Jest pada tahap branding telah lulus. |
| Sinkronisasi upstream | Workflow `.github/workflows/upstream-sync.yml` dan [SOP](XLSMART_UPSTREAM_SYNC.md) telah dipublikasikan. PR sinkronisasi otomatis **belum diuji**: diperlukan token/GitHub App khusus dengan hak minimal ke fork; kredensial OAuth pribadi tidak disimpan sebagai secret CI. |
| Infrastruktur | Terraform staging pada project `internal-tech-tools-enterprise`, region `asia-southeast2`: GKE regional tiga zona, Cloud SQL PostgreSQL HA, Redis HA TLS, OpenSearch tiga node dengan PVC, GCS, Artifact Registry, Secret Manager/External Secrets, Workload Identity, serta IP global `136.69.66.33` khusus ingress chat. State jarak jauh memuat kredensial sensitif; jangan publikasikan state atau plan. |
| Deployment | Cloud Build menerbitkan image `web-server` dan `backend` bertag `d068943a46f0`; Helm revision **6** berjalan di namespace `onyx`. Service nginx tetap `ClusterIP`, terhubung ke Ingress Google eksternal dengan IP global tetap; sertifikat Google masih `Provisioning`. Tidak ada image, deployment, atau service model server lokal. |
| AI | Chat default memakai Vertex AI `gemini-3.8-flash` pada lokasi `global`; embedding pencarian memakai Vertex AI `gemini-embedding-001` berdimensi **3072**. Keduanya memakai identitas workload GKE, tanpa service-account key di image. Bootstrap hanya mengganti indeks lokal bawaan yang masih kosong; indeks yang sudah berisi konten tidak ditimpa. |

## Fitur gratis dan fitur EE

Kode di luar direktori `ee` berlisensi MIT; staging tanpa lisensi sudah membuktikan chat Gemini, konektor file, pengindeksan dan pencarian dokumen dengan sitasi, serta login email/sandi. **Gratis dari sisi lisensi kode bukan berarti gratis biaya GCP/Vertex.** Kode di direktori `ee` memiliki [Onyx Enterprise License](../backend/ee/LICENSE): boleh disalin/diubah untuk pengembangan dan pengujian, tetapi penggunaan produksinya mensyaratkan perjanjian/langganan yang sah dan jumlah seat yang benar. Membuka fitur melalui perubahan konfigurasi saja bukan pengganti lisensi.

Tier **Business** mengunci analitik admin/laporan penggunaan, akses riwayat sesi/kueri admin, API key service account, grup pengguna/RBAC, gateway LLM eksternal dan **pengubahan pengaturan** Search Mode; tier **Enterprise** mengunci SCIM, jawaban standar, rate limit token, outbound hooks, ekspor log, evaluasi, analitik tambahan dan kebijakan retensi chat. Daftar ini mengikuti batas rute saat ini di `backend/ee/onyx/configs/license_enforcement_config.py` serta `backend/onyx/server/settings/api.py`, bukan janji lisensi/fitur di luar kode. SSO dinonaktifkan di staging; tarifnya **tidak** disimpulkan dari konfigurasi ini.

## Bukti uji pada staging

- Cloud Build `fead66cb-7384-4362-8898-e685ff27b906` **SUCCESS**; Helm revision **6** memakai tag `d068943a46f0`. Dua percobaan build penuh sebelumnya gagal pada timeout jaringan indeks PyPI (`sse-starlette`); image backend baru memakai kode commit ini di atas image staging lama `6586e8a39c97` setelah dipastikan Dockerfile dan dua lockfile Python **tidak berubah**. Image web dibangun dari Dockerfile normal. Ini pemulihan build spesifik staging, bukan bukti pemindaian image atau build penuh yang dapat diulang saat PyPI bermasalah.
- API **2/2**, web **2/2**, OpenSearch **3/3** di tiga zona; seluruh pod pada pemeriksaan akhir `Running` tanpa restart. Tiga PVC OpenSearch `Bound` dan empat ExternalSecret `Ready`. Endpoint `/api/health/ready` mengembalikan `success: true`.
- Database aplikasi menyimpan chat default `gemini-3.8-flash` dan **satu** indeks aktif Google `gemini-embedding-001`; jalur `EmbeddingModel.encode` aplikasi menghasilkan vektor 3072 dimensi. Koneksi Cloud SQL yang diperiksa menggunakan TLS.
- Sebelum update, browser Chromium dalam GKE memperlihatkan tautan signup; setelah update, tautan hilang, akses langsung `/auth/signup` diarahkan ke login, dan API menolak pendaftaran tanpa undangan (403). Login `iqbalw@xlsmart.co.id` sukses 204, cookie ditandai `Secure`, dan akun admin sintetis telah dinonaktifkan.
- Dengan akun admin yang diminta, Chromium dalam GKE menerima jawaban chat `XLSMART_STAGE_CHAT_2026` dari Gemini dan menemukan marker `VERTEX_SEARCH_7E4B1F89E6` dalam dokumen sintetis yang terindeks, lengkap dengan bagian **Cited Sources** dan nama file `xlsmart-vertex-staging-7e4b1f89e6.txt`. Dokumen dan jejak percakapan sintetis tetap ada di staging; jangan gunakan sebagai data produksi.

## Akses dan dokumentasi

Dengan identitas GCP yang berwenang, ambil kredensial cluster lalu jalankan tunnel lokal:

```sh
gcloud container clusters get-credentials onyx-staging \
  --region asia-southeast2 --project internal-tech-tools-enterprise
kubectl -n onyx port-forward --address 127.0.0.1 \
  service/onyx-nginx-controller 8080:80
```

Tunnel `http://127.0.0.1:8080/auth/login` hanya untuk diagnostik internal; cookie login disetel `Secure` dan harus diuji pada hostname HTTPS sesungguhnya. Akses utama yang dituju ialah `https://chat-staging.vibecloud.id`, tetapi **jangan gunakan sebelum sertifikat `Active` dan smoke publik lulus**. Detail instalasi, konfigurasi CA, build dan operasi ada di [runbook GCP](../deployment/terraform/gcp/README.md).

## Yang masih tertahan / belum diklaim siap produksi

1. Fork GitHub tersedia; `SYNC_GITHUB_TOKEN` khusus fork dan PR uji sinkronisasi masih diperlukan. Jangan gunakan OAuth pribadi dengan akses luas sebagai secret GitHub Actions.
2. Lisensi EE belum terpasang, sehingga fitur EE berbayar tetap terkunci. Login `basic` aktif, OAuth/SSO tidak aktif, pendaftaran anonim ditolak API (403) lewat `invite_only_enabled=true` tanpa undangan, dan halaman signup publik tidak ditampilkan. Akun admin manusia aktif hanya `iqbalw@xlsmart.co.id`; akun admin sintetis dinonaktifkan dan akun sistem anonim tidak dapat login. DNS publik sudah mengarah ke `136.69.66.33`, namun sertifikat Google masih `Provisioning`: tunggu `Active` dan verifikasi HTTPS serta login nyata sebelum menyebarkan URL. Kata sandi admin pernah dibagikan di chat; rotasi melalui saluran yang aman.
3. Migrasi sertifikat OpenSearch disiapkan sebagai konfigurasi **opt-in**, bukan diterapkan: node masih memakai sertifikat demo tanpa verifikasi klien. Tidak ada plugin snapshot GCS/S3 atau `VolumeSnapshotClass`, sehingga perlu backup + uji restore serta maintenance terkoordinasi sebelum mengganti sertifikat pada ketiga node. Cloud SQL memakai CA per-instance lama tanpa AKI; pengecualian `VERIFY_X509_STRICT` hanya untuk asyncpg sementara validasi rantai CA tetap aktif. Pergantian ke Google-managed shared CA bersifat satu arah; [prosedur](../deployment/terraform/gcp/README.md#cloud-sql-ca-migration-separate-maintenance-only-change) menuntut trust bundle baru dipasang dulu dan uji PITR.
4. XLSMART menerima lokasi Vertex `global` untuk staging; ini **bukan jaminan residensi data Jakarta**. Sebelum produksi tetap perlu anggaran/kuota, pemindaian image, alert/on-call, pemulihan backup/PITR dan snapshot OpenSearch, dan uji gangguan. Resource staging termasuk IP/LB tetap aktif dan menimbulkan biaya.
