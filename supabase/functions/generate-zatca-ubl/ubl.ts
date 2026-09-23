const UBL="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2";
const CAC="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2";
const CBC="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2";
const EXT="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";
const GENERATOR="farsha-ubl-1.0.0", STANDARD="ZATCA UBL 2.1";
const x=(v:unknown)=>String(v??"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&apos;");
const money=(v:unknown)=>Number(v).toFixed(2);
const rate=(v:unknown)=>(Number(v)*100).toFixed(2);
const fail=(m:string)=>{throw new Error("Cannot generate ZATCA XML: "+m)};
const tag=(n:string,v:unknown,a="")=>`<cbc:${n}${a}>${x(v)}</cbc:${n}>`;

export function validate(i:any,lines:any[]){
 if(!i.zatca_uuid)fail("Missing immutable invoice UUID");
 for(const [k,n] of [["seller_legal_name_snapshot","seller legal name"],["seller_vat_number_snapshot","seller VAT number"],["seller_street_snapshot","seller street name"],["seller_building_number_snapshot","seller building number"],["seller_district_snapshot","seller district"],["seller_city_snapshot","seller city"],["seller_postal_code_snapshot","seller postal code"],["seller_country_code_snapshot","seller country code"]] as const)if(!String(i[k]??"").trim())fail("Missing "+n);
 if(!lines.length)fail("Invoice has no canonical invoice lines");
 if(i.invoice_kind==="tax"){
  if(!String(i.customer_name??"").trim())fail("Missing buyer legal name");
  if(!String(i.customer_tax_number??"").trim())fail("Missing buyer VAT number");
  for(const [k,n] of [["buyer_street_snapshot","buyer street name"],["buyer_building_number_snapshot","buyer building number"],["buyer_district_snapshot","buyer district"],["buyer_city_snapshot","buyer city"],["buyer_postal_code_snapshot","buyer postal code"],["buyer_country_code_snapshot","buyer country code"]] as const)if(!String(i[k]??"").trim())fail("Missing "+n);
 }
 const sum=(k:string)=>lines.reduce((a,l)=>a+Number(l[k]),0);
 const eq=(a:number,b:number)=>Math.abs(a-b)<0.009;
 if(!eq(sum("gross_amount"),Number(i.line_extension_amount)))fail("Invoice gross parity failed");
 if(!eq(sum("taxable_amount"),Number(i.tax_exclusive_amount)))fail("Invoice line taxable parity failed");
 if(!eq(sum("discount_amount"),Number(i.discount_amount)))fail("Invoice discount parity failed");

 if(!eq(sum("vat_amount"),Number(i.vat_amount)))fail("Invoice VAT parity failed");
 if(!eq(sum("total_with_vat"),Number(i.tax_inclusive_amount)))fail("Invoice tax-inclusive parity failed");
 if(!eq(Number(i.payable_amount),Number(i.tax_inclusive_amount)))fail("Invoice payable parity failed");
 for(const l of lines)if(Number(l.quantity)<=0)fail("Invoice line quantity must be positive");
}
function address(i:any,p:"seller"|"buyer"){
 const street=i[p+"_street_snapshot"],building=i[p+"_building_number_snapshot"],district=i[p+"_district_snapshot"],city=i[p+"_city_snapshot"],postal=i[p+"_postal_code_snapshot"],country=i[p+"_country_code_snapshot"];
 if(p==="buyer"&&!street&&!city&&!postal)return "";
 return `<cac:PostalAddress>${street?tag("StreetName",street):""}${building?tag("BuildingNumber",building):""}${district?tag("CitySubdivisionName",district):""}${city?tag("CityName",city):""}${postal?tag("PostalZone",postal):""}<cac:Country>${tag("IdentificationCode",country||"SA")}</cac:Country></cac:PostalAddress>`;
}
function party(i:any,p:"seller"|"buyer"){
 const seller=p==="seller",name=seller?i.seller_legal_name_snapshot:i.customer_name,vat=seller?i.seller_vat_number_snapshot:i.customer_tax_number,scheme=seller?i.seller_id_scheme_snapshot:i.buyer_id_scheme_snapshot,id=seller?i.seller_id_value_snapshot:i.buyer_id_value_snapshot;
 return `<cac:${seller?"AccountingSupplierParty":"AccountingCustomerParty"}><cac:Party>${id?`<cac:PartyIdentification>${tag("ID",id,` schemeID="${x(scheme||"CRN")}"`)}</cac:PartyIdentification>`:""}${address(i,p)}${vat?`<cac:PartyTaxScheme>${tag("CompanyID",vat)}<cac:TaxScheme>${tag("ID","VAT")}</cac:TaxScheme></cac:PartyTaxScheme>`:""}<cac:PartyLegalEntity>${tag("RegistrationName",name)}</cac:PartyLegalEntity></cac:Party></cac:${seller?"AccountingSupplierParty":"AccountingCustomerParty"}>`;
}
function lineXml(i:any,l:any){
 const disc=Number(l.discount_amount);
 return `<cac:InvoiceLine>${tag("ID",l.line_no)}${tag("InvoicedQuantity",l.quantity,` unitCode="${x(l.unit_code)}"`)}${tag("LineExtensionAmount",money(l.taxable_amount),` currencyID="${x(i.currency_code)}"`)}${disc>0?`<cac:AllowanceCharge>${tag("ChargeIndicator","false")}${tag("Amount",money(disc),` currencyID="${x(i.currency_code)}"`)}</cac:AllowanceCharge>`:""}<cac:TaxTotal>${tag("TaxAmount",money(l.vat_amount),` currencyID="${x(i.currency_code)}"`)}${tag("RoundingAmount",money(l.total_with_vat),` currencyID="${x(i.currency_code)}"`)}</cac:TaxTotal><cac:Item>${tag("Name",l.description)}<cac:ClassifiedTaxCategory>${tag("ID",l.tax_category)}${tag("Percent",rate(l.vat_rate))}<cac:TaxScheme>${tag("ID","VAT")}</cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item><cac:Price>${tag("PriceAmount",money(l.unit_price),` currencyID="${x(i.currency_code)}"`)}</cac:Price></cac:InvoiceLine>`;
}
export function build(i:any,lines:any[]){
 validate(i,lines); const simplified=i.invoice_kind!=="tax"; const type=simplified?"0200000":"0100000";
 const discount=Number(i.discount_amount),cur=i.currency_code||"SAR";
 return `<?xml version="1.0" encoding="UTF-8"?><Invoice xmlns="${UBL}" xmlns:cac="${CAC}" xmlns:cbc="${CBC}" xmlns:ext="${EXT}"><cbc:ProfileID>reporting:1.0</cbc:ProfileID>${tag("ID",i.invoice_number)}${tag("UUID",i.zatca_uuid)}${tag("IssueDate",String(i.issued_at).slice(0,10))}${tag("IssueTime",new Date(i.issued_at).toISOString().slice(11,19)+"Z")}${tag("InvoiceTypeCode","388",` name="${type}"`)}${tag("DocumentCurrencyCode",cur)}${party(i,"seller")}${party(i,"buyer")}${i.payment_method?`<cac:PaymentMeans>${tag("PaymentMeansCode","10")}</cac:PaymentMeans>`:""}<cac:TaxTotal>${tag("TaxAmount",money(i.vat_amount),` currencyID="${cur}"`)}<cac:TaxSubtotal>${tag("TaxableAmount",money(i.tax_exclusive_amount),` currencyID="${cur}"`)}${tag("TaxAmount",money(i.vat_amount),` currencyID="${cur}"`)}<cac:TaxCategory>${tag("ID",i.tax_category)}${tag("Percent",rate(i.vat_rate))}<cac:TaxScheme>${tag("ID","VAT")}</cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal></cac:TaxTotal><cac:LegalMonetaryTotal>${tag("LineExtensionAmount",money(i.line_extension_amount),` currencyID="${cur}"`)}${tag("TaxExclusiveAmount",money(i.tax_exclusive_amount),` currencyID="${cur}"`)}${tag("TaxInclusiveAmount",money(i.tax_inclusive_amount),` currencyID="${cur}"`)}${tag("PayableAmount",money(i.payable_amount),` currencyID="${cur}"`)}</cac:LegalMonetaryTotal>${lines.map(l=>lineXml(i,l)).join("")}</Invoice>`;
}
