import {
  build,
  validate,
} from "../supabase/functions/generate-zatca-ubl/ubl.ts";

function invoice(kind = "simplified") {
  const standard = kind === "tax";
  return {
    zatca_uuid: "123e4567-e89b-42d3-a456-426614174000",
    invoice_kind: kind,
    invoice_number: 7,
    issued_at: "2026-09-23T12:00:00Z",
    supply_date_snapshot: "2026-09-23",
    currency_code: "SAR",
    tax_category: "S",
    vat_rate: .15,
    seller_legal_name_snapshot: "Test Seller",
    seller_vat_number_snapshot: "310000000000003",
    seller_id_scheme_snapshot: "CRN",
    seller_id_value_snapshot: "1010000000",
    seller_street_snapshot: "Test Street",
    seller_building_number_snapshot: "1234",
    seller_additional_number_snapshot: "5678",
    seller_district_snapshot: "Test District",
    seller_city_snapshot: "Riyadh",
    seller_postal_code_snapshot: "12345",
    seller_country_code_snapshot: "SA",
    customer_name: standard ? "Buyer Co" : "Cash Customer",
    customer_tax_number: standard ? "310000000000013" : "",
    customer_address: standard ? "Buyer address" : "",
    buyer_id_scheme_snapshot: standard ? "CRN" : null,
    buyer_id_value_snapshot: standard ? "1010000001" : null,
    buyer_street_snapshot: standard ? "Buyer Street" : null,
    buyer_building_number_snapshot: standard ? "5678" : null,
    buyer_additional_number_snapshot: standard ? "4321" : null,
    buyer_district_snapshot: standard ? "Buyer District" : null,
    buyer_city_snapshot: standard ? "Riyadh" : null,
    buyer_postal_code_snapshot: standard ? "12345" : null,
    buyer_country_code_snapshot: standard ? "SA" : null,
    line_extension_amount: 100,
    discount_amount: 0,
    tax_exclusive_amount: 100,
    vat_amount: 15,
    tax_inclusive_amount: 115,
    payable_amount: 115,
    payment_method: "cash",
  };
}

function line(no = 1, gross = 100, discount = 0, vat = 15) {
  return {
    line_no: no,
    quantity: 1,
    unit_code: "PCE",
    unit_price: gross,
    gross_amount: gross,
    discount_amount: discount,
    taxable_amount: gross - discount,
    tax_category: "S",
    vat_rate: .15,
    vat_amount: vat,
    total_with_vat: gross - discount + vat,
    description: `Item ${no}`,
  };
}

Deno.test("public mapper simplified golden", () => {
  const xml = build(invoice(), [line()]);
  if (!xml.includes('name="0200000"') || !xml.includes(">115.00<")) {
    throw Error("simplified golden failed");
  }
});

Deno.test("public mapper standard golden", () => {
  const xml = build(invoice("tax"), [line()]);
  if (!xml.includes('name="0100000"') || !xml.includes("310000000000013")) {
    throw Error("standard buyer mapping failed");
  }
  if (!xml.includes("<cbc:TaxCurrencyCode>SAR</cbc:TaxCurrencyCode>")) {
    throw Error("tax currency missing");
  }
  if (
    !xml.includes("<cbc:ActualDeliveryDate>2026-09-23</cbc:ActualDeliveryDate>")
  ) {
    throw Error("supply date missing");
  }
});

Deno.test("public mapper parity guard", () => {
  const value = invoice();
  value.payable_amount = 114;
  let failed = false;
  try {
    validate(value, [line()]);
  } catch {
    failed = true;
  }
  if (!failed) throw Error("mismatch accepted");
});
