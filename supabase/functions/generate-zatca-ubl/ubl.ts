const UBL = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2";
const CAC = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2";
const CBC = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2";
const EXT = "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";

export const UBL_GENERATOR_VERSION = "farsha-ubl-1.1.0";
export const UBL_STANDARD_VERSION =
  "ZATCA XML Implementation Standard 1.2 / UBL 2.1";

const SELLER_ID_SCHEMES = new Set(["CRN", "MOM", "MLS", "700", "SAG", "OTH"]);
const BUYER_ID_SCHEMES = new Set([
  "TIN", "CRN", "MOM", "MLS", "700", "SAG", "NAT", "GCC", "IQA", "PAS", "OTH",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VAT = /^3\d{13}3$/;
const ALPHANUMERIC = /^[A-Za-z0-9]+$/;
const COUNTRY = /^[A-Z]{2}$/;

const x = (value: unknown) => String(value ?? "")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&apos;");
const money = (value: unknown) => Number(value).toFixed(2);
const rate = (value: unknown) => (Number(value) * 100).toFixed(2);
const roundedMoney = (value: unknown) => Number(Number(value).toFixed(2));
const nonEmpty = (value: unknown) => String(value ?? "").trim();
const eq = (a: unknown, b: unknown) => Math.abs(Number(a) - Number(b)) < 0.009;
const hasTwoDecimals = (value: unknown) =>
  Number.isFinite(Number(value)) && Math.abs(Number(value) - roundedMoney(value)) < 0.0000001;
const fail = (message: string, rule = "STAGE2") => {
  throw new Error(`Cannot generate ZATCA XML [${rule}]: ${message}`);
};
const requireField = (value: unknown, name: string, rule: string) => {
  if (!nonEmpty(value)) fail(`Missing ${name}`, rule);
};
const tag = (name: string, value: unknown, attributes = "") =>
  `<cbc:${name}${attributes}>${x(value)}</cbc:${name}>`;

/**
 * Validates the non-cryptographic rules applicable to Farsha's current scope:
 * SAR invoices, standard-rated VAT, invoice code 388, no prepayments, no
 * document-level charges and no credit/debit notes. Signing, PIH, ICV, QR
 * embedding and reporting/clearance remain explicitly outside Stage 2.
 */
export function validateBusinessRules(invoice: any, lines: any[]): string[] {
  const checked = new Set<string>();
  const mark = (...rules: string[]) => rules.forEach((rule) => checked.add(rule));
  const standard = invoice.invoice_kind === "tax";

  requireField(invoice.invoice_number, "invoice number", "BR-02");
  requireField(invoice.issued_at, "invoice issue date", "BR-03");
  requireField(invoice.zatca_uuid, "immutable invoice UUID", "BR-KSA-03");
  if (!UUID.test(nonEmpty(invoice.zatca_uuid))) {
    fail("Invoice UUID is not a canonical UUID", "BR-KSA-03");
  }
  const issuedAt = new Date(invoice.issued_at);
  if (Number.isNaN(issuedAt.getTime())) fail("Invalid issue timestamp", "BR-KSA-04");
  const issueDate = issuedAt.toISOString().slice(0, 10);
  const today = new Date().toISOString().slice(0, 10);
  if (issueDate > today) fail("Issue date cannot be in the future", "BR-KSA-04");
  if (!["simplified", "tax"].includes(invoice.invoice_kind)) {
    fail("Invoice kind must be simplified or tax", "BR-KSA-05");
  }
  if (nonEmpty(invoice.currency_code || "SAR") !== "SAR") {
    fail("Document currency must be SAR", "BR-KSA-CL-01");
  }
  mark(
    "BR-02", "BR-03", "BR-04", "BR-05", "BR-KSA-03", "BR-KSA-04",
    "BR-KSA-05", "BR-KSA-06", "BR-KSA-CL-01", "BR-KSA-EN16931-01",
    "BR-KSA-EN16931-02", "BR-KSA-F-01",
  );

  requireField(invoice.seller_legal_name_snapshot, "seller legal name", "BR-06");
  requireField(invoice.seller_vat_number_snapshot, "seller VAT number", "BR-KSA-39");
  if (!VAT.test(nonEmpty(invoice.seller_vat_number_snapshot))) {
    fail("Seller VAT number must be 15 digits and start/end with 3", "BR-KSA-40");
  }
  requireField(invoice.seller_id_scheme_snapshot, "seller identification scheme", "BR-KSA-08");
  requireField(invoice.seller_id_value_snapshot, "seller identification", "BR-KSA-08");
  const sellerScheme = nonEmpty(invoice.seller_id_scheme_snapshot).toUpperCase();
  if (!SELLER_ID_SCHEMES.has(sellerScheme)) {
    fail("Unsupported seller identification scheme", "BR-KSA-08");
  }
  if (!ALPHANUMERIC.test(nonEmpty(invoice.seller_id_value_snapshot))) {
    fail("Seller identification must be alphanumeric", "BR-KSA-08");
  }
  for (const [key, label] of [
    ["seller_street_snapshot", "seller street name"],
    ["seller_building_number_snapshot", "seller building number"],
    ["seller_district_snapshot", "seller district"],
    ["seller_city_snapshot", "seller city"],
    ["seller_postal_code_snapshot", "seller postal code"],
    ["seller_country_code_snapshot", "seller country code"],
  ] as const) requireField(invoice[key], label, "BR-KSA-09");
  if (!/^\d{4}$/.test(nonEmpty(invoice.seller_building_number_snapshot))) {
    fail("Seller building number must contain 4 digits", "BR-KSA-37");
  }
  if (!/^\d{5}$/.test(nonEmpty(invoice.seller_postal_code_snapshot))) {
    fail("Seller postal code must contain 5 digits", "BR-KSA-66");
  }
  if (!COUNTRY.test(nonEmpty(invoice.seller_country_code_snapshot).toUpperCase())) {
    fail("Seller country code must be ISO 3166-1 alpha-2", "BR-KSA-CL-01");
  }
  mark(
    "BR-06", "BR-08", "BR-09", "BR-KSA-08", "BR-KSA-09", "BR-KSA-37",
    "BR-KSA-39", "BR-KSA-40", "BR-KSA-66",
  );

  if (standard) {
    requireField(invoice.customer_name, "buyer legal name", "BR-KSA-42");
    const buyerVat = nonEmpty(invoice.customer_tax_number);
    const buyerId = nonEmpty(invoice.buyer_id_value_snapshot);
    const buyerScheme = nonEmpty(invoice.buyer_id_scheme_snapshot).toUpperCase();
    if (buyerVat) {
      if (!VAT.test(buyerVat)) {
        fail("Buyer VAT number must be 15 digits and start/end with 3", "BR-KSA-44");
      }
    } else if (!buyerId || !BUYER_ID_SCHEMES.has(buyerScheme) || !ALPHANUMERIC.test(buyerId)) {
      fail("A valid buyer identification is required when buyer VAT is absent", "BR-KSA-14/81");
    }
    for (const [key, label] of [
      ["buyer_street_snapshot", "buyer street name"],
      ["buyer_city_snapshot", "buyer city"],
      ["buyer_country_code_snapshot", "buyer country code"],
    ] as const) requireField(invoice[key], label, "BR-KSA-10");
    const buyerCountry = nonEmpty(invoice.buyer_country_code_snapshot).toUpperCase();
    if (!COUNTRY.test(buyerCountry)) {
      fail("Buyer country code must be ISO 3166-1 alpha-2", "BR-KSA-CL-01");
    }
    if (buyerCountry === "SA") {
      requireField(invoice.buyer_building_number_snapshot, "buyer building number", "BR-KSA-63");
      requireField(invoice.buyer_district_snapshot, "buyer district", "BR-KSA-63");
      requireField(invoice.buyer_postal_code_snapshot, "buyer postal code", "BR-KSA-63");
      if (!/^\d{4}$/.test(nonEmpty(invoice.buyer_building_number_snapshot))) {
        fail("Buyer building number must contain 4 digits", "BR-KSA-63");
      }
      if (!/^\d{5}$/.test(nonEmpty(invoice.buyer_postal_code_snapshot))) {
        fail("Buyer postal code must contain 5 digits", "BR-KSA-67");
      }
    }
    requireField(invoice.supply_date_snapshot, "supply date", "BR-KSA-15");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(nonEmpty(invoice.supply_date_snapshot).slice(0, 10))) {
      fail("Supply date must use YYYY-MM-DD", "BR-KSA-F-01");
    }
    mark(
      "BR-10", "BR-KSA-10", "BR-KSA-14", "BR-KSA-15", "BR-KSA-42",
      "BR-KSA-44", "BR-KSA-63", "BR-KSA-67", "BR-KSA-81",
    );
  }

  if (!lines.length) fail("Invoice has no canonical invoice lines", "BR-16");
  const seen = new Set<number>();
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const lineNo = Number(line.line_no);
    if (!Number.isInteger(lineNo) || lineNo <= 0 || seen.has(lineNo)) {
      fail("Invoice line identifiers must be unique positive integers", "BR-21");
    }
    if (lineNo !== index + 1) {
      fail("Canonical invoice lines must be ordered and contiguous", "STAGE2-LINE-ORDER");
    }
    seen.add(lineNo);
    requireField(line.description, `line ${lineNo} item name`, "BR-25");
    requireField(line.unit_code, `line ${lineNo} unit code`, "BR-22");
    if (Number(line.quantity) <= 0) fail(`Line ${lineNo} quantity must be positive`, "BR-22");
    if (Number(line.unit_price) < 0) fail(`Line ${lineNo} price cannot be negative`, "BR-26");
    if (["gross_amount", "discount_amount", "taxable_amount", "vat_amount", "total_with_vat"].some((key) => Number(line[key]) < 0)) {
      fail(`Line ${lineNo} monetary values cannot be negative`, "BR-KSA-F-04");
    }
    if (!eq(roundedMoney(Number(line.quantity) * Number(line.unit_price)), line.gross_amount)) {
      fail(`Line ${lineNo} gross amount does not equal quantity × price`, "BR-KSA-EN16931-11");
    }
    if (!eq(Number(line.gross_amount) - Number(line.discount_amount), line.taxable_amount)) {
      fail(`Line ${lineNo} taxable amount does not equal gross - discount`, "BR-KSA-EN16931-11");
    }
    if (!eq(Number(line.taxable_amount) + Number(line.vat_amount), line.total_with_vat)) {
      fail(`Line ${lineNo} amount with VAT is inconsistent`, "BR-KSA-51");
    }
    if (nonEmpty(line.tax_category) !== "S" || !eq(line.vat_rate, 0.15)) {
      fail(`Line ${lineNo} must use standard VAT category S at 15%`, "BR-S-09");
    }
    for (const key of ["unit_price", "gross_amount", "discount_amount", "taxable_amount", "vat_amount", "total_with_vat"]) {
      if (!hasTwoDecimals(line[key])) fail(`Line ${lineNo} ${key} exceeds two decimals`, "BR-KSA-DEC-03/04");
    }
  }
  mark(
    "BR-16", "BR-21", "BR-22", "BR-24", "BR-25", "BR-26", "BR-41",
    "BR-CO-04", "BR-KSA-18", "BR-KSA-51", "BR-KSA-52", "BR-KSA-53",
    "BR-KSA-DEC-02", "BR-KSA-DEC-03", "BR-KSA-DEC-04",
    "BR-KSA-EN16931-11", "BR-KSA-F-02", "BR-KSA-F-03", "BR-KSA-F-04",
  );

  const sum = (key: string) => lines.reduce((total, line) => total + Number(line[key]), 0);
  if (!eq(sum("gross_amount"), invoice.line_extension_amount)) fail("Invoice gross parity failed", "STAGE2-GROSS-PARITY");
  if (!eq(sum("discount_amount"), invoice.discount_amount)) fail("Invoice discount parity failed", "STAGE2-DISCOUNT-PARITY");
  if (!eq(sum("taxable_amount"), invoice.tax_exclusive_amount)) fail("Invoice line taxable parity failed", "BR-CO-10/13");
  if (!eq(sum("vat_amount"), invoice.vat_amount)) fail("Invoice VAT parity failed", "BR-CO-14");
  if (!eq(sum("total_with_vat"), invoice.tax_inclusive_amount)) fail("Invoice tax-inclusive parity failed", "BR-CO-15");
  if (!eq(invoice.payable_amount, invoice.tax_inclusive_amount)) fail("Invoice payable parity failed", "BR-CO-16");
  if (!eq(roundedMoney(Number(invoice.tax_exclusive_amount) * Number(invoice.vat_rate)), invoice.vat_amount)) {
    fail("VAT breakdown is not taxable amount × VAT rate rounded to two decimals", "BR-CO-17");
  }
  for (const key of ["line_extension_amount", "discount_amount", "tax_exclusive_amount", "vat_amount", "tax_inclusive_amount", "payable_amount"]) {
    if (!hasTwoDecimals(invoice[key])) fail(`Invoice ${key} exceeds two decimals`, "BR-KSA-F-04");
  }
  if (nonEmpty(invoice.tax_category) !== "S" || !eq(invoice.vat_rate, 0.15)) {
    fail("Invoice VAT breakdown must use category S at 15%", "BR-S-08/09");
  }
  mark(
    "BR-13", "BR-14", "BR-15", "BR-45", "BR-46", "BR-47", "BR-48",
    "BR-53", "BR-CO-10", "BR-CO-13", "BR-CO-14", "BR-CO-15",
    "BR-CO-16", "BR-CO-17", "BR-CO-18", "BR-S-08", "BR-S-09",
    "BR-S-10", "BR-KSA-68", "BR-KSA-CL-02", "BR-KSA-EN16931-08",
    "BR-KSA-EN16931-09",
  );
  return [...checked].sort();
}

export function validate(invoice: any, lines: any[]) {
  validateBusinessRules(invoice, lines);
}

function address(invoice: any, party: "seller" | "buyer") {
  const street = invoice[`${party}_street_snapshot`];
  const building = invoice[`${party}_building_number_snapshot`];
  const district = invoice[`${party}_district_snapshot`];
  const city = invoice[`${party}_city_snapshot`];
  const postal = invoice[`${party}_postal_code_snapshot`];
  const country = invoice[`${party}_country_code_snapshot`];
  if (party === "buyer" && !street && !city && !postal) return "";
  return `<cac:PostalAddress>${street ? tag("StreetName", street) : ""}${building ? tag("BuildingNumber", building) : ""}${district ? tag("CitySubdivisionName", district) : ""}${city ? tag("CityName", city) : ""}${postal ? tag("PostalZone", postal) : ""}<cac:Country>${tag("IdentificationCode", nonEmpty(country).toUpperCase())}</cac:Country></cac:PostalAddress>`;
}

function party(invoice: any, role: "seller" | "buyer") {
  const seller = role === "seller";
  const name = seller ? invoice.seller_legal_name_snapshot : invoice.customer_name;
  const vat = seller ? invoice.seller_vat_number_snapshot : invoice.customer_tax_number;
  const scheme = seller ? invoice.seller_id_scheme_snapshot : invoice.buyer_id_scheme_snapshot;
  const id = seller ? invoice.seller_id_value_snapshot : invoice.buyer_id_value_snapshot;
  const wrapper = seller ? "AccountingSupplierParty" : "AccountingCustomerParty";
  return `<cac:${wrapper}><cac:Party>${id ? `<cac:PartyIdentification>${tag("ID", id, ` schemeID="${x(nonEmpty(scheme).toUpperCase())}"`)}</cac:PartyIdentification>` : ""}${address(invoice, role)}${vat ? `<cac:PartyTaxScheme>${tag("CompanyID", vat, ' schemeID="VAT"')}<cac:TaxScheme>${tag("ID", "VAT")}</cac:TaxScheme></cac:PartyTaxScheme>` : ""}<cac:PartyLegalEntity>${tag("RegistrationName", name)}</cac:PartyLegalEntity></cac:Party></cac:${wrapper}>`;
}

function lineXml(invoice: any, line: any) {
  const discount = Number(line.discount_amount);
  const currency = nonEmpty(invoice.currency_code || "SAR");
  return `<cac:InvoiceLine>${tag("ID", line.line_no)}${tag("InvoicedQuantity", line.quantity, ` unitCode="${x(line.unit_code)}"`)}${tag("LineExtensionAmount", money(line.taxable_amount), ` currencyID="${x(currency)}"`)}${discount > 0 ? `<cac:AllowanceCharge>${tag("ChargeIndicator", "false")}${tag("Amount", money(discount), ` currencyID="${x(currency)}"`)}</cac:AllowanceCharge>` : ""}<cac:TaxTotal>${tag("TaxAmount", money(line.vat_amount), ` currencyID="${x(currency)}"`)}${tag("RoundingAmount", money(line.total_with_vat), ` currencyID="${x(currency)}"`)}</cac:TaxTotal><cac:Item>${tag("Name", line.description)}<cac:ClassifiedTaxCategory>${tag("ID", line.tax_category)}${tag("Percent", rate(line.vat_rate))}<cac:TaxScheme>${tag("ID", "VAT")}</cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item><cac:Price>${tag("PriceAmount", money(line.unit_price), ` currencyID="${x(currency)}"`)}</cac:Price></cac:InvoiceLine>`;
}

export function build(invoice: any, lines: any[]) {
  validate(invoice, lines);
  const simplified = invoice.invoice_kind !== "tax";
  const transactionCode = simplified ? "0200000" : "0100000";
  const currency = nonEmpty(invoice.currency_code || "SAR");
  const supplyDate = nonEmpty(invoice.supply_date_snapshot).slice(0, 10);
  return `<?xml version="1.0" encoding="UTF-8"?><Invoice xmlns="${UBL}" xmlns:cac="${CAC}" xmlns:cbc="${CBC}" xmlns:ext="${EXT}">${tag("ProfileID", "reporting:1.0")}${tag("ID", invoice.invoice_number)}${tag("UUID", invoice.zatca_uuid)}${tag("IssueDate", new Date(invoice.issued_at).toISOString().slice(0, 10))}${tag("IssueTime", new Date(invoice.issued_at).toISOString().slice(11, 19) + "Z")}${tag("InvoiceTypeCode", "388", ` name="${transactionCode}"`)}${tag("DocumentCurrencyCode", currency)}${tag("TaxCurrencyCode", "SAR")}${party(invoice, "seller")}${party(invoice, "buyer")}${simplified ? "" : `<cac:Delivery>${tag("ActualDeliveryDate", supplyDate)}</cac:Delivery>`}<cac:TaxTotal>${tag("TaxAmount", money(invoice.vat_amount), ' currencyID="SAR"')}</cac:TaxTotal><cac:TaxTotal>${tag("TaxAmount", money(invoice.vat_amount), ` currencyID="${x(currency)}"`)}<cac:TaxSubtotal>${tag("TaxableAmount", money(invoice.tax_exclusive_amount), ` currencyID="${x(currency)}"`)}${tag("TaxAmount", money(invoice.vat_amount), ` currencyID="${x(currency)}"`)}<cac:TaxCategory>${tag("ID", invoice.tax_category)}${tag("Percent", rate(invoice.vat_rate))}<cac:TaxScheme>${tag("ID", "VAT")}</cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal></cac:TaxTotal><cac:LegalMonetaryTotal>${tag("LineExtensionAmount", money(invoice.tax_exclusive_amount), ` currencyID="${x(currency)}"`)}${tag("TaxExclusiveAmount", money(invoice.tax_exclusive_amount), ` currencyID="${x(currency)}"`)}${tag("TaxInclusiveAmount", money(invoice.tax_inclusive_amount), ` currencyID="${x(currency)}"`)}${tag("PayableAmount", money(invoice.payable_amount), ` currencyID="${x(currency)}"`)}</cac:LegalMonetaryTotal>${lines.map((line) => lineXml(invoice, line)).join("")}</Invoice>`;
}
