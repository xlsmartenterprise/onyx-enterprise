# Ringkasan implementasi XLSMART Enterprise

**Status pada verifikasi staging 28 September 2026:** aplikasi berjalan di GCP dan chat serta pencarian dokumen telah diuji melalui Vertex AI. Ini **lingkungan uji kesiapan produksi**, bukan sertifikasi siap produksi. Image aplikasi yang diuji memakai tag commit `6586e8a39c97`.

## Yang sudah dikerjakan

| Area | Hasil |
| --- | --- |
| Repositori | Checkout lokal berbasis rilis Onyx `v4.8.1`; cabang `upstream-tracking` untuk basis upstream dan `xlsmart-main` untuk perubahan XLSMART. Nama modul, tabel, dan service internal Onyx dipertahankan. |
| Branding | Nama **XLSMART Enterprise**, logo/favicon, tampilan login dan chat, metadata web, aset widget/ekstensi, serta identitas pada template deployment diperbarui. Skrip `scripts/apply_xlsmart_assets.sh` memulihkan aset branding setelah merge upstream. Build frontend dan pengujian Jest pada tahap branding telah lulus. |
| Sinkronisasi upstream | Workflow `.github/workflows/upstream-sync.yml` dan [SOP](XLSMART_UPSTREAM_SYNC.md) disiapkan: pantau tag rilis stabil mingguan, perbarui cabang upstream, buat cabang sinkronisasi, lalu ajukan PR untuk ditinjau. **Belum diuji lewat PR GitHub nyata**, karena akses ke fork dan token belum tersedia. |
| Infrastruktur | Terraform staging diterapkan pada project `internal-tech-tools-enterprise`, region `asia-southeast2`: GKE regional tiga zona, Cloud SQL PostgreSQL HA, Redis HA dengan TLS, OpenSearch tiga node dengan PVC, GCS untuk file dan state Terraform, Artifact Registry, Secret Manager/External Secrets, serta Workload Identity. State jarak jauh dilindungi dan memuat kredensial sensitif; jangan publikasikan state atau plan. |
| Deployment | Cloud Build menerbitkan **dua** image bertag commit (`web-server` dan `backend`). Helm men-deploy aplikasi dan worker di namespace `onyx`. Ingress tetap `ClusterIP`, tanpa alamat publik. Tidak ada image, deployment, atau service model server lokal. |
| AI | Chat default memakai Vertex AI `gemini-3.8-flash` pada lokasi `global`; embedding pencarian memakai Vertex AI `gemini-embedding-001` berdimensi **3072**. Keduanya memakai identitas workload GKE, tanpa service-account key di image. Bootstrap hanya mengganti indeks lokal bawaan yang masih kosong; indeks yang sudah berisi konten tidak ditimpa. |

## Bukti uji pada staging

- Cloud Build `47cde15c-bb4e-4df3-9f9f-3d9db47fad0a` **SUCCESS**; Helm revision **5** memakai tag `6586e8a39c97`.
- API **2/2**, web **2/2**, OpenSearch **3/3** di tiga zona; seluruh pod pada pemeriksaan akhir `Running` tanpa restart. Tiga PVC OpenSearch `Bound` dan empat ExternalSecret `Ready`. Endpoint `/api/health/ready` mengembalikan `success: true`.
- Database aplikasi menyimpan chat default `gemini-3.8-flash` dan **satu** indeks aktif Google `gemini-embedding-001`; jalur `EmbeddingModel.encode` aplikasi menghasilkan vektor 3072 dimensi. Koneksi Cloud SQL yang diperiksa menggunakan TLS.
- Browser nyata di dalam GKE berhasil membuka login XLSMART, mendaftarkan akun uji, lalu menerima jawaban `VERTEX_UI_OK` melalui chat Gemini.
- Konektor file mengunggah satu dokumen sintetis, upaya pengindeksan berstatus `success` dengan **1 dokumen**, dan pertanyaan browser mengembalikan kode unik dokumen `VERTEX_SEARCH_7E4B1F89E6` **beserta sitasi file**. Akun dan dokumen sintetis masih ada di staging; jangan gunakan sebagai data produksi.

## Akses dan dokumentasi

Dengan identitas GCP yang berwenang, ambil kredensial cluster lalu jalankan tunnel lokal:

```sh
gcloud container clusters get-credentials onyx-staging \
  --region asia-southeast2 --project internal-tech-tools-enterprise
kubectl -n onyx port-forward --address 127.0.0.1 \
  service/onyx-nginx-controller 8080:80
```

Buka `http://127.0.0.1:8080/auth/login?autoRedirectToSignup=false`. Tunnel bukan endpoint publik dan harus dijalankan dari terminal yang tetap aktif. Detail instalasi, konfigurasi CA, build, dan operasi ada di [runbook GCP](../deployment/terraform/gcp/README.md).

## Yang masih tertahan / belum diklaim siap produksi

1. Repositori fork `xlsmartenterprise/onyx-enterprise` belum dapat diakses (HTTP 404 tanpa autentikasi); cabang lokal belum dipublikasikan. Perlu pembuatan/akses fork dan secret `SYNC_GITHUB_TOKEN` berizin sesuai SOP untuk menguji push serta PR sinkronisasi nyata.
2. EE berbayar terkunci sampai lisensi yang sah diterapkan. Sebelum endpoint publik, siapkan DNS, TLS, kebijakan identitas/SSO, dan tinjau akses/signup; konfigurasi saat ini untuk staging menggunakan autentikasi `basic`.
3. Sertifikat demo OpenSearch harus diganti dan verifikasi klien diaktifkan. CA Cloud SQL saat ini tidak memiliki Authority Key Identifier; pengecualian `VERIFY_X509_STRICT` dibatasi pada koneksi asyncpg Cloud SQL, sedangkan verifikasi rantai sertifikat terhadap CA tetap aktif. Ganti CA lama dan hapus pengecualian bila memungkinkan.
4. Pemrosesan Gemini dikonfigurasi pada lokasi Vertex `global`, **bukan jaminan residensi data Jakarta**. Tinjau persyaratan lokasi data, anggaran dan kuota, pemindaian image, alert/on-call, pemulihan backup/PITR dan snapshot OpenSearch, serta uji gangguan sebelum promosi ke produksi. Resource staging tetap aktif dan menimbulkan biaya.
