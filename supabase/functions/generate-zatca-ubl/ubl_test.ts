import { build } from "./ubl.ts";
const assert=(v:boolean,m:string)=>{if(!v)throw new Error(m)};
const base=(over:any={})=>({zatca_uuid:"11111111-1111-4111-8111-111111111111",invoice_number:42,issued_at:"2026-09-23T12:34:56Z",invoice_kind:"simplified",currency_code:"SAR",seller_legal_name_snapshot:"Test Seller",seller_vat_number_snapshot:"310000000000003",seller_id_scheme_snapshot:"CRN",seller_id_value_snapshot:"1010000000",seller_street_snapshot:"Test Street",seller_building_number_snapshot:"1234",seller_district_snapshot:"Test District",seller_city_snapshot:"Riyadh",seller_postal_code_snapshot:"12345",seller_country_code_snapshot:"SA",customer_name:"Cash Customer",customer_tax_number:"",customer_address:"",buyer_id_scheme_snapshot:null,buyer_id_value_snapshot:null,buyer_country_code_snapshot:"SA",tax_category:"S",vat_rate:.15,line_extension_amount:100,tax_exclusive_amount:100,vat_amount:15,tax_inclusive_amount:115,payable_amount:115,discount_amount:0,payment_method:"cash",supply_date_snapshot:"2026-09-23",...over});
const line=(over:any={})=>({line_no:1,quantity:1,unit_code:"PCE",unit_price:100,gross_amount:100,discount_amount:0,taxable_amount:100,tax_category:"S",vat_rate:.15,vat_amount:15,total_with_vat:115,description:"Item",...over});
Deno.test("A simplified one line",()=>{const xml=build(base(),[line()]);assert(xml.includes('name="0200000"'),"simplified type");assert(xml.includes(">115.00</cbc:PayableAmount>"),"payable")});
Deno.test("B multiple items",()=>{const i=base({line_extension_amount:150,tax_exclusive_amount:150,vat_amount:22.5,tax_inclusive_amount:172.5,payable_amount:172.5});const xml=build(i,[line(),line({line_no:2,unit_price:50,gross_amount:50,taxable_amount:50,vat_amount:7.5,total_with_vat:57.5,description:"Second"})]);assert((xml.match(/<cac:InvoiceLine>/g)||[]).length===2,"two lines")});
Deno.test("C addons remain invoice lines",()=>{const i=base({line_extension_amount:110,tax_exclusive_amount:110,vat_amount:16.5,tax_inclusive_amount:126.5,payable_amount:126.5});const xml=build(i,[line(),line({line_no:2,unit_price:10,gross_amount:10,taxable_amount:10,vat_amount:1.5,total_with_vat:11.5,description:"Installation"})]);assert(xml.includes(">Installation</cbc:Name>"),"addon line")});
Deno.test("D distributed discount is line allowance only",()=>{const i=base({line_extension_amount:100,discount_amount:10,tax_exclusive_amount:90,vat_amount:13.5,tax_inclusive_amount:103.5,payable_amount:103.5});const xml=build(i,[line({discount_amount:10,taxable_amount:90,vat_amount:13.5,total_with_vat:103.5})]);assert(xml.includes("<cbc:ChargeIndicator>false</cbc:ChargeIndicator>"),"allowance");assert(xml.includes(">90.00</cbc:LineExtensionAmount>"),"net line")});
Deno.test("E VAT rounding uses snapshot",()=>{const i=base({line_extension_amount:10.03,tax_exclusive_amount:10.03,vat_amount:1.50,tax_inclusive_amount:11.53,payable_amount:11.53});const xml=build(i,[line({unit_price:10.03,gross_amount:10.03,taxable_amount:10.03,vat_amount:1.50,total_with_vat:11.53})]);assert(xml.includes(">1.50</cbc:TaxAmount>"),"snapshot vat")});
Deno.test("F split payment does not alter XML totals",()=>{const xml=build(base({payment_method:"split"}),[line()]);assert(xml.includes(">115.00</cbc:PayableAmount>"),"canonical payable")});
Deno.test("G standard requires buyer data",()=>{const i=base({invoice_kind:"tax",customer_name:"Buyer LLC",customer_tax_number:"310000000000011",customer_address:"Riyadh",buyer_street_snapshot:"Buyer Street",buyer_building_number_snapshot:"5678",buyer_district_snapshot:"Buyer District",buyer_city_snapshot:"Riyadh",buyer_postal_code_snapshot:"12345",buyer_country_code_snapshot:"SA"});const xml=build(i,[line()]);assert(xml.includes('name="0100000"'),"standard type");assert(xml.includes(">310000000000011</cbc:CompanyID>"),"buyer VAT")});
Deno.test("parity mismatch blocks XML",()=>{let ok=false;try{build(base({vat_amount:14}),[line()])}catch{ok=true}assert(ok,"must reject mismatch")});

Deno.test("standard rejects missing structured buyer address",()=>{let ok=false;try{build(base({invoice_kind:"tax",customer_name:"Buyer",customer_tax_number:"310000000000011",buyer_street_snapshot:null}),[line()])}catch(e){ok=String(e).includes("buyer street name")}assert(ok,"structured buyer address required")});
Deno.test("Farsha gross snapshot mismatch blocks XML",()=>{let ok=false;try{build(base({line_extension_amount:99}),[line()])}catch{ok=true}assert(ok,"gross parity must be preserved")});

Deno.test("UBL LegalMonetaryTotal LineExtension is sum of net invoice lines",()=>{const i=base({line_extension_amount:100,discount_amount:10,tax_exclusive_amount:90,vat_amount:13.5,tax_inclusive_amount:103.5,payable_amount:103.5});const xml=build(i,[line({discount_amount:10,taxable_amount:90,vat_amount:13.5,total_with_vat:103.5})]);assert(xml.includes("<cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID=\"SAR\">90.00</cbc:LineExtensionAmount>"),"UBL line extension must be net")});

Deno.test("DB end-to-end Stage 2 snapshot maps exactly to XML",()=>{
 const i=base({line_extension_amount:212.60,discount_amount:7.13,tax_exclusive_amount:205.47,vat_amount:30.82,tax_inclusive_amount:236.29,payable_amount:236.29});
 const lines=[
  line({line_no:1,description:"Carpet",quantity:4.936,unit_code:"MTK",unit_price:37.89,gross_amount:187.03,discount_amount:6.27,taxable_amount:180.76,vat_amount:27.11,total_with_vat:207.87}),
  line({line_no:2,description:"Installation",quantity:1,unit_code:"PCE",unit_price:5.55,gross_amount:5.55,discount_amount:.19,taxable_amount:5.36,vat_amount:.80,total_with_vat:6.16}),
  line({line_no:3,description:"Felt",quantity:2,unit_code:"PCE",unit_price:10.01,gross_amount:20.02,discount_amount:.67,taxable_amount:19.35,vat_amount:2.91,total_with_vat:22.26})
 ];
 const xml=build(i,lines);
 assert(xml.includes("<cbc:TaxableAmount currencyID=\"SAR\">205.47</cbc:TaxableAmount>"),"XML taxable parity");
 assert(xml.includes("<cbc:TaxAmount currencyID=\"SAR\">30.82</cbc:TaxAmount>"),"XML VAT parity");
 assert(xml.includes("<cbc:TaxInclusiveAmount currencyID=\"SAR\">236.29</cbc:TaxInclusiveAmount>"),"XML inclusive parity");
 assert(xml.includes("<cbc:PayableAmount currencyID=\"SAR\">236.29</cbc:PayableAmount>"),"XML payable parity");
 assert((xml.match(/<cac:InvoiceLine>/g)||[]).length===3,"XML line count parity");
});

Deno.test("same immutable snapshot generates byte-stable business XML",()=>{const i=base();const lines=[line()];assert(build(i,lines)===build(i,lines),"XML must be deterministic")});
