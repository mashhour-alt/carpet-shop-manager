import { secp256k1 } from "npm:@noble/curves@1.9.7/secp256k1";
import { build } from "./ubl.ts";
import {
  INITIAL_PIH,
  sha256Bytes,
  stampSimplifiedInvoice,
  type ZatcaSigner,
} from "./security.ts";

// Ephemeral test key: generated in memory for this fixture and never persisted.
const privateKey = secp256k1.utils.randomSecretKey();
const publicKey = secp256k1.getPublicKey(privateKey, false).slice(1);
const fullPublicKey = secp256k1.getPublicKey(privateKey, false);
const spkiPrefix = Uint8Array.from([
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
const certificate = btoa(
  String.fromCharCode(0x30, ...spkiPrefix, ...publicKey),
);
const signer: ZatcaSigner = {
  certificate: {
    certificateChain: [{
      derBase64: certificate,
      issuerName: "C=SA,O=Farsha Test Only,CN=Stage3 Test CSID",
      serialNumber: "424242",
    }],
    publicKeyP1363: publicKey,
    zatcaCaSignatureP1363: secp256k1.sign(
      await sha256Bytes(publicKey),
      privateKey,
    ).toCompactRawBytes(),
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

const invoice = {
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
  discount_amount: 0,
  tax_exclusive_amount: 100,
  vat_amount: 15,
  tax_inclusive_amount: 115,
  payable_amount: 115,
  supply_date_snapshot: "2026-09-23",
};
const lines = [{
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
}];
const stamped = await stampSimplifiedInvoice({
  businessXml: build(invoice, lines),
  icv: 1,
  previousInvoiceHash: INITIAL_PIH,
  invoiceKind: "simplified",
  sellerName: invoice.seller_legal_name_snapshot,
  sellerVatNumber: invoice.seller_vat_number_snapshot,
  issuedAt: invoice.issued_at,
  taxInclusiveAmount: invoice.tax_inclusive_amount,
  vatAmount: invoice.vat_amount,
  signingTime: "2026-09-23T12:35:00Z",
}, signer);
await Deno.mkdir("build", { recursive: true });
await Deno.writeTextFile(
  "build/zatca-stage3-signed-simplified.xml",
  stamped.signedXml,
);
