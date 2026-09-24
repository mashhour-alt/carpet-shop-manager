# Stage 4 — Official ZATCA validation evidence

Evidence date: 2026-09-24 UTC. This report is validation evidence, not a claim
that the product is fully compliant and not a production onboarding record.

## Official source register

| Document/tool | Version/date shown by ZATCA | Official URL |
|---|---|---|
| Security Features Implementation Standards | v1.2, 19 May 2023 | https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_ZATCA_Electronic_Invoice_Security_Features_Implementation_Standards_vF.pdf |
| Electronic Invoice XML Implementation Standard | v1.2, 19 May 2023 | https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_ZATCA_Electronic_Invoice_XML_Implementation_Standard_%20vF.pdf |
| Electronic Invoice Data Dictionary | v1.2, 19 May 2023 | https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_EInvoice_Data_Dictionary%20vF.xlsx |
| Developer Portal Manual | v3, November 2022 | https://zatca.gov.sa/en/E-Invoicing/Introduction/Guidelines/Documents/DEVELOPER-PORTAL-MANUAL.pdf |
| Compliance and Enablement Toolbox / SDK download | page updated 28 May 2025 | https://zatca.gov.sa/en/E-Invoicing/SystemsDevelopers/ComplianceEnablementToolbox/Pages/DownloadSDK.aspx |
| Systems Developers documentation hub | page updated 10 August 2026 | https://zatca.gov.sa/en/E-Invoicing/SystemsDevelopers/Pages/default.aspx |

The current official download was `zatca-envoice-sdk-203.zip` (SHA-256
`1a7df6d91fd34968ad59a97087f637f56504fdf92c42050916b838be20fc5ae3`).
Its Java CLI identifies itself as SDK 3.0.8; the JAR SHA-256 is
`e0a250bf8871d085ef616ad9865dae70a19c2d3a83d40517a8808561bf403bf2`.

## Confirmed cryptographic profile

- Curve: `secp256k1`. The portal manual calls it “P-256 (secp256k1)”; the
  official SDK test key, certificate and generated CSR all carry the
  `secp256k1` OID. This is not NIST P-256 / secp256r1.
- Signature: ECDSA with SHA-256, XMLDSIG URI
  `http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256`.
- Hash: SHA-256 over the three prescribed exclusions followed by inclusive
  Canonical XML 1.1; Base64 is the raw 32-byte digest.
- XMLDSIG/QR signature representation: fixed-width IEEE P1363 `r || s`, 64
  bytes. Provider APIs returning ASN.1 DER must be strictly decoded and
  left-padded into this representation in the trusted backend.
- Public key: uncompressed secp256k1 point; QR tag 8 carries the 64-byte
  `x || y` value (no private key and no `0x04` prefix).
- Compliance CSR template: `TSTZATCA-Code-Signing`; production template:
  `ZATCA-Code-Signing`. The environment is now explicit and defaults to
  compliance.

## Validation matrix

| Test | Simplified | Standard | Evidence |
|---|---|---|---|
| UBL XSD | PASS | PASS | Official SDK XSD plus independent UBL 2.1 XSD validation |
| KSA Business Rules | PASS | PASS | SDK 3.0.8 EN and KSA schematrons |
| Invoice Hash | PASS | PASS | Farsha equals SDK byte-for-byte |
| PIH | PASS | PASS | Farsha chain tests; Standard SDK PIH validator |
| ICV | PASS | PASS | Atomic database reservation tests and SDK rules |
| QR | FAIL | REQUIRES ZATCA CREDENTIAL | Simplified SDK 3.0.8 rejects the newer 2023 tags 6–9 byte profile; Standard final QR is returned by clearance |
| Signature | PASS | NOT APPLICABLE | Simplified XAdES digest/signature verified independently with OpenSSL; Standard is pre-clearance |
| Certificate | REQUIRES ZATCA CREDENTIAL | REQUIRES ZATCA CREDENTIAL | Expired SDK test CSID proves structure only; a current Compliance CSID needs official OTP |
| SDK Validation | FAIL | PASS | Raw logs in this directory |

`PASS`, `FAIL`, `NOT APPLICABLE`, and `REQUIRES ZATCA CREDENTIAL` are used
literally. In particular, the Simplified SDK global result remains `FAIL`.

## SDK QR discrepancy

The downloadable SDK is older than the May 2023 standards. Its own signer
emits tag 6 as 44 ASCII Base64 bytes, tag 7 as an 88-byte SPKI value, and tags
8/9 as separate 33-byte ECDSA integers. The current official portal manual
defines tag 6 as the raw 32-byte invoice hash, tag 7 as the 64-byte signature,
tag 8 as the 64-byte public key and tag 9 as the 64-byte CA signature. Farsha
follows the newer normative documents, and SDK 3.0.8 rejects that QR profile.
No compatibility workaround was introduced.

Farsha's decoded Simplified QR test evidence is:

| Tag | Bytes | Meaning/result |
|---|---:|---|
| 1 | 15 | Seller name |
| 2 | 15 | VAT number |
| 3 | 20 | UTC invoice timestamp |
| 4 | 6 | Tax-inclusive total `115.00` |
| 5 | 5 | VAT total `15.00` |
| 6 | 32 | Raw SHA-256; equals the official SDK invoice hash |
| 7 | 64 | P1363 signature; verifies over canonical SignedInfo |
| 8 | 64 | secp256k1 public point `x || y` |
| 9 | 64 | ZATCA test-certificate CA signature |

## Database and regression evidence

- Migration `zatca_stage4_official_validation` was additive only: nullable
  address snapshot columns, immutable-snapshot coverage and `issue_tax_invoice_v3`.
  It contains no update, backfill, reset or historical recalculation.
- Historical invoice count stayed `1`; its selected financial/XML digest stayed
  `c06b1bbc7cc7fdf934cbfcae34f80000` before and after migration.
- Live Stage 2 E2E ran with Simplified and Standard invoices, multiple lines,
  add-ons, a `7.13` discount, VAT rounding and split payments `100 + 136.29`.
  The transaction returned `rollback_verified=true`.
- Live Stage 3 security transaction completed, and post-run counts for its
  institution, EGS, invoices and reservations were all zero.
- Numeric parity remained gross `212.60`, discount `7.13`, taxable `205.47`,
  VAT `30.82`, payable `236.29` across sale snapshot, invoice snapshot,
  invoice lines, PDF inputs, QR monetary inputs and XML totals.

## HSM/KMS compatibility gate

| Provider | secp256k1 / non-exportable | Signing/output | Deployment and integration | Cost/complexity |
|---|---|---|---|---|
| Google Cloud HSM | Yes: `EC_SIGN_SECP256K1_SHA256` at both multi-tenant and single-tenant HSM levels | Server-side SHA-256 ECDSA; DER must be converted to fixed-width P1363 and verified | Dammam `me-central2` supports Cloud HSM; straightforward HTTPS backend adapter with narrowly scoped IAM | Multi-tenant HSM is pay-per-key-version/operation; single-tenant is materially more expensive |
| AWS KMS | Yes: `ECC_SECG_P256K1`; private key never leaves KMS unencrypted | `ECDSA_SHA_256`; returns ASN.1 DER, requiring strict DER-to-P1363 conversion and verification | Simple server-side Sign/GetPublicKey adapter and IAM policy. Saudi region is still listed as coming soon; Bahrain/UAE residency/latency requires a business decision | Generally lowest operational complexity and low per-key/request cost |
| Azure Key Vault Premium | Yes: EC-HSM P-256K / ES256K; no export operation | Server-side sign/verify; confirm exact SDK return representation in a provider PoC before adapter lock-in | REST/SDK integration is practical; validate the selected Saudi/UAE region and tier availability before purchase | Consumption pricing; simpler and cheaper than a dedicated pool |
| Azure Managed HSM | Yes: all keys HSM-protected, P-256K / ES256K | Server-side digest signing, local verification; single-tenant pool | Strong isolation and local RBAC, but security-domain/quorum operations add significant governance | Highest fixed cost/operational complexity among the Azure choices |

No provider was selected and no cloud or production key was created.

## Remaining official gate

A current Compliance CSID/test certificate and Compliance API validation require
an official ZATCA OTP and real EGS/institution identity. Those inputs are not
fabricated. The next authorized action is sandbox/compliance onboarding after
the owner supplies that OTP; production onboarding and production APIs remain
out of scope.
