import { secp256k1 } from "npm:@noble/curves@1.9.7/secp256k1";
import { build } from "./ubl.ts";
import {
  addIcvAndPih,
  base64ToBytes,
  buildPhase2Qr,
  canonicalInvoiceForHash,
  canonicalizeC14N11,
  canonicalSignedInfoFromXml,
  decodePhase2Qr,
  INITIAL_PIH,
  invoiceHash,
  sha256Bytes,
  type StampedInvoice,
  stampSimplifiedInvoice,
  verifyStampedInvoice,
  type ZatcaSigner,
} from "./security.ts";
import {
  buildZatcaCsrOpenSslConfig,
  csrFieldsFromSettings,
  generateZatcaCsr,
  validateZatcaCsrFields,
} from "./csr.ts";

const assert: (condition: unknown, message: string) => asserts condition = (
  condition,
  message,
) => {
  if (!condition) throw new Error(message);
};

const equalBytes = (left: Uint8Array, right: Uint8Array) =>
  left.length === right.length &&
  left.every((value, index) => value === right[index]);

const SECP256K1_SPKI_PREFIX = Uint8Array.from([
  0x30,
  0x10,
  0x06,
  0x07,
  0x2a,
  0x86,
  0x48,
  0xce,
  0x3d,
  0x02,
  0x01,
  0x06,
  0x05,
  0x2b,
  0x81,
  0x04,
  0x00,
  0x0a,
  0x03,
  0x42,
  0x00,
  0x04,
]);

const bytesToBase64 = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value));

async function testSigner(): Promise<ZatcaSigner> {
  // Test keys exist only in this process and are never persisted or committed.
  const privateKey = secp256k1.utils.randomSecretKey();
  const fullPublicKey = secp256k1.getPublicKey(privateKey, false);
  const publicKey = fullPublicKey.slice(1);
  const caSignature = secp256k1
    .sign(await sha256Bytes(publicKey), privateKey)
    .toCompactRawBytes();
  const certificateFixture = Uint8Array.from([
    0x30,
    ...SECP256K1_SPKI_PREFIX,
    ...publicKey,
  ]);
  return {
    certificate: {
      certificateChain: [{
        derBase64: bytesToBase64(certificateFixture),
        issuerName: "C=SA,O=Farsha Test Only,CN=Stage3 Test CSID",
        serialNumber: "424242",
      }],
      publicKeyP1363: publicKey,
      zatcaCaSignatureP1363: caSignature,
      certificateId: "stage3-test-only-csid",
    },
    async signSha256(message) {
      return secp256k1.sign(await sha256Bytes(message), privateKey)
        .toCompactRawBytes();
    },
    async verifySha256(message, signature) {
      return secp256k1.verify(
        signature,
        await sha256Bytes(message),
        fullPublicKey,
      );
    },
  };
}

const base = (overrides: Record<string, unknown> = {}) => ({
  zatca_uuid: "11111111-1111-4111-8111-111111111111",
  invoice_number: 42,
  issued_at: "2026-09-23T12:34:56Z",
  invoice_kind: "simplified",
  currency_code: "SAR",
  seller_legal_name_snapshot: "Farsha Test Seller",
  seller_vat_number_snapshot: "310000000000003",
  seller_id_scheme_snapshot: "CRN",
  seller_id_value_snapshot: "1010000000",
  seller_street_snapshot: "Test Street",
  seller_building_number_snapshot: "1234",
  seller_district_snapshot: "Test District",
  seller_city_snapshot: "Riyadh",
  seller_postal_code_snapshot: "12345",
  seller_country_code_snapshot: "SA",
  customer_name: "Cash Customer",
  customer_tax_number: "",
  buyer_id_scheme_snapshot: null,
  buyer_id_value_snapshot: null,
  buyer_street_snapshot: null,
  buyer_building_number_snapshot: null,
  buyer_district_snapshot: null,
  buyer_city_snapshot: null,
  buyer_postal_code_snapshot: null,
  buyer_country_code_snapshot: null,
  tax_category: "S",
  vat_rate: 0.15,
  line_extension_amount: 100,
  tax_exclusive_amount: 100,
  vat_amount: 15,
  tax_inclusive_amount: 115,
  payable_amount: 115,
  discount_amount: 0,
  supply_date_snapshot: "2026-09-23",
  ...overrides,
});

const line = (overrides: Record<string, unknown> = {}) => ({
  line_no: 1,
  quantity: 1,
  unit_code: "PCE",
  unit_price: 100,
  gross_amount: 100,
  discount_amount: 0,
  taxable_amount: 100,
  tax_category: "S",
  vat_rate: 0.15,
  vat_amount: 15,
  total_with_vat: 115,
  description: "Test item",
  ...overrides,
});

function stampInput(invoice = base(), lines = [line()]) {
  return {
    businessXml: build(invoice, lines),
    icv: 1,
    previousInvoiceHash: INITIAL_PIH,
    invoiceKind: invoice.invoice_kind as "simplified" | "tax",
    sellerName: invoice.seller_legal_name_snapshot as string,
    sellerVatNumber: invoice.seller_vat_number_snapshot as string,
    issuedAt: invoice.issued_at as string,
    taxInclusiveAmount: invoice.tax_inclusive_amount as number,
    vatAmount: invoice.vat_amount as number,
    signingTime: "2026-09-23T12:35:00Z",
  };
}

Deno.test("C14N 1.1 normalizes declaration, empty-element and attribute order", () => {
  const left = '<?xml version="1.0"?><a xmlns="urn:test" z="2" a="1"><b/></a>';
  const right = '<a a="1" z="2" xmlns="urn:test"><b></b></a>';
  assert(
    canonicalizeC14N11(left) === canonicalizeC14N11(right),
    "canonical forms differ",
  );
});

Deno.test("official transforms exclude extension, UBL signature and QR only", async () => {
  const business = build(base(), [line()]);
  const secured = addIcvAndPih(business, 1, INITIAL_PIH);
  const before = await invoiceHash(secured);
  const withExcluded = secured
    .replace(
      /<Invoice\b[^>]*>/,
      (root) => `${root}<ext:UBLExtensions></ext:UBLExtensions>`,
    )
    .replace(
      "<cac:Signature>",
      '<cac:AdditionalDocumentReference><cbc:ID>QR</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="text/plain">TEST</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference><cac:Signature>',
    );
  const after = await invoiceHash(withExcluded);
  assert(
    before.base64 === after.base64,
    "excluded elements changed invoice hash",
  );
  assert(
    before.canonicalXml === after.canonicalXml,
    "excluded elements changed canonical XML",
  );
});

Deno.test("first, second and third invoices form the official PIH chain", async () => {
  const first = await invoiceHash(
    addIcvAndPih(build(base({ invoice_number: 1 }), [line()]), 1, INITIAL_PIH),
  );
  const secondXml = addIcvAndPih(
    build(base({ invoice_number: 2 }), [line()]),
    2,
    first.base64,
  );
  const second = await invoiceHash(secondXml);
  const thirdXml = addIcvAndPih(
    build(base({ invoice_number: 3 }), [line()]),
    3,
    second.base64,
  );
  assert(
    first.base64 !== second.base64,
    "chain hash must include changed invoice content",
  );
  assert(
    secondXml.includes(
      `<cbc:EmbeddedDocumentBinaryObject mimeCode="text/plain">${first.base64}</cbc:EmbeddedDocumentBinaryObject>`,
    ),
    "invoice 2 PIH mismatch",
  );
  assert(
    thirdXml.includes(
      `<cbc:EmbeddedDocumentBinaryObject mimeCode="text/plain">${second.base64}</cbc:EmbeddedDocumentBinaryObject>`,
    ),
    "invoice 3 PIH mismatch",
  );
});

Deno.test("simplified XAdES signature verifies and regeneration is deterministic", async () => {
  const signer = await testSigner();
  const first = await stampSimplifiedInvoice(stampInput(), signer);
  const retry = await stampSimplifiedInvoice(stampInput(), signer);
  const finalCanonicalInfo = canonicalSignedInfoFromXml(first.signedXml);
  if (first.canonicalSignedInfo !== finalCanonicalInfo) {
    const index = [...first.canonicalSignedInfo].findIndex((
      character,
      offset,
    ) => character !== finalCanonicalInfo[offset]);
    throw new Error(
      `SignedInfo canonicalization changed at ${index}: ${
        first.canonicalSignedInfo.slice(index, index + 180)
      } != ${finalCanonicalInfo.slice(index, index + 180)}`,
    );
  }
  assert(
    await verifyStampedInvoice(first, signer),
    "signature verification failed",
  );
  assert(first.invoiceHash === retry.invoiceHash, "retry changed invoice hash");
  assert(
    first.signatureValue === retry.signatureValue,
    "deterministic test signature changed",
  );
  assert(first.signedXml === retry.signedXml, "retry changed signed XML");
});

Deno.test("Phase-2 QR simplified tags 1-9 decode byte-for-byte", async () => {
  const signer = await testSigner();
  const stamped = await stampSimplifiedInvoice(stampInput(), signer);
  const fields = decodePhase2Qr(stamped.qr);
  assert(
    [...fields.keys()].join(",") === "1,2,3,4,5,6,7,8,9",
    "simplified QR tag order mismatch",
  );
  assert(
    new TextDecoder().decode(fields.get(4)) === "115.00",
    "QR total mismatch",
  );
  assert(
    new TextDecoder().decode(fields.get(5)) === "15.00",
    "QR VAT mismatch",
  );
  assert(
    equalBytes(fields.get(6)!, base64ToBytes(stamped.invoiceHash)),
    "QR hash mismatch",
  );
  assert(
    equalBytes(fields.get(7)!, base64ToBytes(stamped.signatureValue)),
    "QR signature mismatch",
  );
});

Deno.test("Phase-2 standard QR profile is tags 1-8 and excludes tag 9", async () => {
  const signer = await testSigner();
  const hash = await sha256Bytes("standard-clearance-test");
  const signature = await signer.signSha256(hash);
  const qr = buildPhase2Qr({
    invoiceKind: "tax",
    sellerName: "Farsha Test Seller",
    sellerVatNumber: "310000000000003",
    issuedAt: "2026-09-23T12:34:56Z",
    taxInclusiveAmount: 115,
    vatAmount: 15,
    invoiceHash: hash,
    signatureP1363: signature,
    publicKeyP1363: signer.certificate.publicKeyP1363,
  });
  assert(
    [...decodePhase2Qr(qr).keys()].join(",") === "1,2,3,4,5,6,7,8",
    "standard QR tags mismatch",
  );
});

Deno.test("standard invoice cannot be locally stamped before ZATCA clearance", async () => {
  const standard = base({
    invoice_kind: "tax",
    customer_name: "Test Buyer",
    customer_tax_number: "310000000000013",
    buyer_id_scheme_snapshot: "CRN",
    buyer_id_value_snapshot: "1010000001",
    buyer_street_snapshot: "Buyer Street",
    buyer_building_number_snapshot: "5678",
    buyer_district_snapshot: "Buyer District",
    buyer_city_snapshot: "Riyadh",
    buyer_postal_code_snapshot: "12345",
    buyer_country_code_snapshot: "SA",
  });
  let rejected = false;
  try {
    await stampSimplifiedInvoice(
      stampInput(standard, [line()]),
      await testSigner(),
    );
  } catch (error) {
    rejected = String(error).includes("clearance");
  }
  assert(rejected, "standard local stamp must be rejected");
});

Deno.test("discount, multiple lines and VAT rounding remain protected unchanged", async () => {
  const invoice = base({
    line_extension_amount: 30.03,
    discount_amount: 0.02,
    tax_exclusive_amount: 30.01,
    vat_amount: 4.50,
    tax_inclusive_amount: 34.51,
    payable_amount: 34.51,
  });
  const lines = [
    line({
      unit_price: 10.01,
      gross_amount: 10.01,
      discount_amount: 0.01,
      taxable_amount: 10,
      vat_amount: 1.5,
      total_with_vat: 11.5,
    }),
    line({
      line_no: 2,
      unit_price: 20.02,
      gross_amount: 20.02,
      discount_amount: 0.01,
      taxable_amount: 20.01,
      vat_amount: 3,
      total_with_vat: 23.01,
      description: "Test add-on",
    }),
  ];
  const stamped = await stampSimplifiedInvoice(
    stampInput(invoice, lines),
    await testSigner(),
  );
  assert(
    stamped.signedXml.includes(">30.01</cbc:TaxableAmount>"),
    "taxable amount changed",
  );
  assert(
    stamped.signedXml.includes(">4.50</cbc:TaxAmount>"),
    "VAT rounding changed",
  );
  assert(
    (stamped.signedXml.match(/<cac:InvoiceLine>/g) ?? []).length === 2,
    "line count changed",
  );
});

Deno.test("tampered amount, line, SignedProperties, signature and QR are rejected", async () => {
  const signer = await testSigner();
  const stamped = await stampSimplifiedInvoice(stampInput(), signer);
  const amountTamper: StampedInvoice = {
    ...stamped,
    signedXml: stamped.signedXml.replace(
      ">115.00</cbc:PayableAmount>",
      ">116.00</cbc:PayableAmount>",
    ),
  };
  const lineTamper: StampedInvoice = {
    ...stamped,
    signedXml: stamped.signedXml.replace(
      ">Test item</cbc:Name>",
      ">Changed item</cbc:Name>",
    ),
  };
  const signatureBytes = base64ToBytes(stamped.signatureValue);
  signatureBytes[0] ^= 1;
  const changedSignature = btoa(String.fromCharCode(...signatureBytes));
  const signatureTamper: StampedInvoice = {
    ...stamped,
    signedXml: stamped.signedXml.replace(
      stamped.signatureValue,
      changedSignature,
    ),
  };
  const propertiesTamper: StampedInvoice = {
    ...stamped,
    signedXml: stamped.signedXml.replace(
      "424242</ds:X509SerialNumber>",
      "424243</ds:X509SerialNumber>",
    ),
  };
  const qrTamper: StampedInvoice = {
    ...stamped,
    signedXml: stamped.signedXml.replace(
      stamped.qr,
      stamped.qr.replace(/^./, stamped.qr[0] === "A" ? "B" : "A"),
    ),
  };
  assert(
    !(await verifyStampedInvoice(amountTamper, signer)),
    "tampered amount verified",
  );
  assert(
    !(await verifyStampedInvoice(lineTamper, signer)),
    "tampered line verified",
  );
  assert(
    !(await verifyStampedInvoice(propertiesTamper, signer)),
    "tampered SignedProperties verified",
  );
  assert(
    !(await verifyStampedInvoice(signatureTamper, signer)),
    "tampered signature verified",
  );
  assert(
    !(await verifyStampedInvoice(qrTamper, signer)),
    "tampered QR verified",
  );
});

Deno.test("invalid PIH and missing signing certificate are rejected", async () => {
  let pihRejected = false;
  try {
    addIcvAndPih(build(base(), [line()]), 1, btoa("wrong"));
  } catch {
    pihRejected = true;
  }
  const signer = await testSigner();
  signer.certificate.certificateChain = [];
  let certificateRejected = false;
  try {
    await stampSimplifiedInvoice(stampInput(), signer);
  } catch {
    certificateRejected = true;
  }
  assert(pihRejected && certificateRejected, "invalid security input accepted");
});

Deno.test("leaf certificate key mismatch and unverifiable HSM output are rejected", async () => {
  const wrongCertificateKey = await testSigner();
  wrongCertificateKey.certificate.publicKeyP1363 = wrongCertificateKey
    .certificate.publicKeyP1363.slice();
  wrongCertificateKey.certificate.publicKeyP1363[0] ^= 1;
  let certificateKeyRejected = false;
  try {
    await stampSimplifiedInvoice(stampInput(), wrongCertificateKey);
  } catch (error) {
    certificateKeyRejected = String(error).includes(
      "does not match the leaf X.509 certificate",
    );
  }

  const wrongSignature = await testSigner();
  const signWithEphemeralKey = wrongSignature.signSha256;
  wrongSignature.signSha256 = async () =>
    signWithEphemeralKey(new TextEncoder().encode("different-message"));
  let signatureRejected = false;
  try {
    await stampSimplifiedInvoice(stampInput(), wrongSignature);
  } catch (error) {
    signatureRejected = String(error).includes("did not verify");
  }
  assert(
    certificateKeyRejected && signatureRejected,
    "certificate/signer mismatch was accepted",
  );
});

Deno.test("every certificate in the supplied chain is embedded and digest-referenced", async () => {
  const signer = await testSigner();
  signer.certificate.certificateChain.push({
    ...signer.certificate.certificateChain[0],
    serialNumber: "424243",
  });
  const stamped = await stampSimplifiedInvoice(stampInput(), signer);
  const signingCertificates = stamped.signedXml.match(
    /<xades:SigningCertificate>([\s\S]+?)<\/xades:SigningCertificate>/,
  )?.[1] ?? "";
  assert(
    (signingCertificates.match(/<xades:Cert>/g) ?? []).length === 2,
    "certificate chain digest references missing",
  );
  assert(
    (stamped.signedXml.match(/<ds:X509Certificate>/g) ?? []).length === 2,
    "certificate chain was not embedded",
  );
});

Deno.test("CSR official fields and non-exportable provider contract", async () => {
  const fields = csrFieldsFromSettings({
    institution: {
      legalName: "Farsha Test Organization",
      vatNumber: "310000000000003",
      organizationUnitName: "Riyadh Test Branch",
      countryCode: "SA",
    },
    egs: {
      commonName: "Farsha-Test-EGS-001",
      serialNumber: "1-Farsha-Test|2-Stage3|3-000001",
      invoiceTypeMap: "1100",
      location: "TEST-RIYADH-ONLY",
      industry: "Carpet retail test fixture",
    },
  });
  const config = buildZatcaCsrOpenSslConfig(fields);
  assert(
    config.includes(
      "certificateTemplateName = ASN1:PRINTABLESTRING:ZATCA-Code-Signing",
    ),
    "CSR template OID missing",
  );
  assert(config.includes("title = 1100"), "CSR functionality map missing");
  const generated = await generateZatcaCsr(fields, {
    async generatePkcs10(request) {
      assert(request.curve === "secp256k1", "wrong CSR curve");
      assert(request.keyExportable === false, "CSR key must be non-exportable");
      return {
        csrPem:
          "-----BEGIN CERTIFICATE REQUEST-----\nVEVTVA==\n-----END CERTIFICATE REQUEST-----\n",
        keyReference: "hsm://test-only/egs-001",
      };
    },
  });
  assert(
    generated.keyReference.startsWith("hsm://"),
    "opaque HSM reference missing",
  );
});

Deno.test("CSR settings mapping refuses missing real institution or EGS identity", () => {
  let rejected = false;
  try {
    csrFieldsFromSettings({
      institution: {
        legalName: "",
        vatNumber: "310000000000003",
        organizationUnitName: "Riyadh Branch",
        countryCode: "SA",
      },
      egs: {
        commonName: "EGS",
        serialNumber: "1-Provider|2-Model|3-Serial",
        invoiceTypeMap: "1100",
        location: "Riyadh",
        industry: "Retail",
      },
    });
  } catch {
    rejected = true;
  }
  assert(rejected, "missing real CSR settings were silently defaulted");
});

Deno.test("CSR invalid VAT, EGS serial, functionality map and VAT-group OU are rejected", () => {
  const valid = {
    commonName: "EGS",
    egsSerialNumber: "1-Provider|2-Model|3-Serial",
    organizationIdentifier: "310000000000003",
    organizationUnitName: "Branch",
    organizationName: "Organization",
    countryCode: "SA",
    invoiceTypeMap: "1100",
    location: "Riyadh",
    industry: "Retail",
  };
  for (
    const changed of [
      { organizationIdentifier: "123" },
      { egsSerialNumber: "serial" },
      { invoiceTypeMap: "0000" },
      {
        organizationIdentifier: "310000000010003",
        organizationUnitName: "not-a-tin",
      },
    ]
  ) {
    let rejected = false;
    try {
      validateZatcaCsrFields({ ...valid, ...changed });
    } catch {
      rejected = true;
    }
    assert(rejected, `invalid CSR fields accepted: ${JSON.stringify(changed)}`);
  }
});

Deno.test("raw business change always changes protected hash", async () => {
  const original = addIcvAndPih(build(base(), [line()]), 1, INITIAL_PIH);
  const changed = original.replace(
    ">100.00</cbc:PriceAmount>",
    ">101.00</cbc:PriceAmount>",
  );
  assert(
    (await invoiceHash(original)).base64 !==
      (await invoiceHash(changed)).base64,
    "financial tamper kept same hash",
  );
  assert(
    canonicalInvoiceForHash(original) !== canonicalInvoiceForHash(changed),
    "canonical payload ignored financial tamper",
  );
});
