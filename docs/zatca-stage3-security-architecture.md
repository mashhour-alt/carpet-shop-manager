# ZATCA Stage 3 security architecture

Status: implemented and tested locally, but not activated for production. This
document is not a claim that Farsha is ZATCA compliant.

## Normative inputs

The implementation is pinned to the following official material:

- ZATCA, *Electronic Invoice Security Features Implementation Standards*,
  version 1.2, 19 May 2023:
  <https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_ZATCA_Electronic_Invoice_Security_Features_Implementation_Standards_vF.pdf>
- ZATCA, *Electronic Invoice XML Implementation Standard*, version 1.2,
  19 May 2023:
  <https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_ZATCA_Electronic_Invoice_XML_Implementation_Standard_%20vF.pdf>
- ZATCA, *E-Invoice Data Dictionary*, 19 May 2023:
  <https://zatca.gov.sa/ar/E-Invoicing/SystemsDevelopers/Documents/20230519_EInvoice_Data_Dictionary%20vF.xlsx>
- ZATCA, *Fatoora Developer Portal User Manual*, version 3, November 2022:
  <https://zatca.gov.sa/en/E-Invoicing/Introduction/Guidelines/Documents/DEVELOPER-PORTAL-MANUAL.pdf>
- ZATCA Compliance and Enablement Toolbox, last observed 28 May 2025:
  <https://zatca.gov.sa/en/E-Invoicing/SystemsDevelopers/ComplianceEnablementToolbox/Pages/DownloadSDK.aspx>

The official SDK download requires authenticated SharePoint access in the
current environment. The available local tests therefore do not substitute for
the official SDK or the ZATCA compliance sandbox.

## Trust boundary

All security operations are server-side. Flutter receives no private key,
certificate secret, OTP, binary security token, or signing primitive.

`ZatcaSigner` exposes only an opaque certificate identity and a
`signSha256(message)` operation. Its production implementation must use a
hardware or software security module that keeps the secp256k1 key marked
non-exportable. Database rows hold only the provider name and an opaque key
reference. Certificate chains and public keys are public material; an OAuth
secret field stores only an opaque secret-manager reference.

Supabase Vault alone is not accepted as the signing-key module. Its decrypted
view can expose the stored value to sufficiently privileged SQL, which does not
meet the ZATCA requirement that the private key be non-exportable and never
leave the security module.

## EGS and branch model

An EGS unit is a distinct security identity, not a synonym for a branch.
`zatca_egs_branch_assignments` maps one active EGS to each issuing branch while
allowing an EGS to cover more than one branch if the business configuration
requires it. ICV and PIH are scoped to the EGS.

Security activation is explicit through `security_activation_at`. No migration
backfills old invoices into a newly activated chain. An invoice older than the
activation point is rejected by the reservation function.

## Atomic ICV and PIH state machine

1. `reserve_zatca_issuance` locks the EGS row and binds one immutable business
   XML SHA-256 digest to `last_committed_icv + 1` and the current PIH.
2. A partial unique index permits only one pending invoice per EGS. A unique
   `(egs_id, icv)` constraint provides a second database-level race guard.
3. Signing happens outside the database transaction. A failure is audited but
   leaves the reservation, ICV, PIH and invoice identity unchanged for retry.
4. `finalize_zatca_issuance` locks both the reservation and EGS, validates the
   exact chain head and active certificate, inserts the immutable final state,
   marks the reservation complete, and advances ICV/PIH in one transaction.
5. An exact repeat returns the existing state. A changed hash, XML, signature,
   QR, certificate, signing time or generator version is rejected.

The official first PIH is:

```text
NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ==
```

## Cryptographic order

The protected invoice is built in this order:

1. Insert ICV and PIH additional-document references.
2. Exclude `ext:UBLExtensions`, `cac:Signature`, and the QR additional-document
   reference using the three official XPath transforms.
3. Apply XML Canonicalization 1.1.
4. Hash the canonical bytes with SHA-256.
5. Build XAdES `SignedProperties`, hash their canonical form, build canonical
   `SignedInfo`, and sign it with ECDSA secp256k1/SHA-256.
6. Build the Phase-2 TLV QR from the raw 32-byte invoice hash, raw 64-byte IEEE
   P1363 signature, and raw 64-byte public key.
7. Embed QR and the UBL signature extension. Recompute the protected hash and
   reject if the excluded additions changed it.

The canonicalizer is intentionally scoped to Farsha-generated UBL. That input
domain has no DTDs, entity references, `xml:base`, `xml:id`, or namespace
undeclarations. Arbitrary third-party XML is not accepted by this path.

## Simplified and standard behavior

- Simplified tax invoices are signed locally and use QR tags 1 through 9. Tag 9
  is the ZATCA technical CA signature over the EGS public key.
- Standard tax invoices use QR tags 1 through 8 only after clearance. Farsha
  rejects local standard-invoice stamping. The database reserves the future
  `standard_clearance` workflow, but Stage 3 does not call a clearance API.

No reporting, clearance, production OTP, production CSID, or production
credential workflow is implemented in this stage.

## CSR profile

The CSR builder validates and emits the documented fields `CN`, `C`, `OU`, `O`,
EGS serial `1-provider|2-model|3-serial`, VAT `UID`, four-bit invoice type map,
registered address and business category. It uses SHA-256, secp256k1, and the
`ZATCA-Code-Signing` template OID. The provider contract returns only a PKCS#10
CSR and an opaque key reference with `keyExportable: false`.

## Verification inventory

- UBL financial parity and KSA business-rule regression tests.
- The three official invoice-hash transforms and controlled C14N 1.1 tests.
- First, second and third ICV/PIH chain tests.
- XAdES invoice digest, `SignedProperties` digest and ECDSA verification.
- Deterministic retry, tamper rejection and immutable final-state tests.
- Simplified QR tags 1-9 and standard QR tags 1-8 byte-level decoding.
- UBL 2.1 XSD validation of unsigned and signed XML fixtures.
- OpenSSL CSR signature/profile validation using an ephemeral test key.
- PostgreSQL reservation/failure/finalization tests inside rollback.

## Production gates

Production activation remains blocked until the organization selects and
configures a ZATCA-acceptable non-exportable secp256k1 HSM/KMS or software
security module. The persistent migration must also be reviewed and applied to
the shared Supabase project. After those gates, the official SDK and compliance
sandbox remain mandatory external validations before any later production API
stage.
