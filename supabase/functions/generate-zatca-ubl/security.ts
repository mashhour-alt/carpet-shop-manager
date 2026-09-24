import {
  DOMParser,
  type Attr,
  type Element,
  type Node,
} from "npm:@xmldom/xmldom@0.9.12";

const UBL = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2";
const CAC = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2";
const CBC = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2";
const EXT = "urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2";
const SIG = "urn:oasis:names:specification:ubl:schema:xsd:CommonSignatureComponents-2";
const SAC = "urn:oasis:names:specification:ubl:schema:xsd:SignatureAggregateComponents-2";
const SBC = "urn:oasis:names:specification:ubl:schema:xsd:SignatureBasicComponents-2";
const DS = "http://www.w3.org/2000/09/xmldsig#";
const XADES = "http://uri.etsi.org/01903/v1.3.2#";
const XMLNS = "http://www.w3.org/2000/xmlns/";

export const ZATCA_SECURITY_VERSION =
  "farsha-zatca-security-1.0.0 / Security Features 1.2";
export const INITIAL_PIH =
  "NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ==";
export const C14N11 = "http://www.w3.org/2006/12/xml-c14n11";
export const SHA256 = "http://www.w3.org/2001/04/xmlenc#sha256";
export const ECDSA_SHA256 =
  "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256";

const textEncoder = new TextEncoder();

const fail = (message: string): never => {
  throw new Error(`ZATCA security: ${message}`);
};

const escapeText = (value: string) => value
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll("\r", "&#xD;");

const escapeAttribute = (value: string) => value
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll('"', "&quot;")
  .replaceAll("\t", "&#x9;")
  .replaceAll("\n", "&#xA;")
  .replaceAll("\r", "&#xD;");

const xml = (value: unknown) => escapeText(String(value ?? ""))
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&apos;");

const bytesToBase64 = (bytes: Uint8Array) => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

export const base64ToBytes = (value: string) => {
  const binary = atob(value.replaceAll(/\s/g, ""));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
};

export async function sha256Bytes(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? textEncoder.encode(value) : value;
  const owned = Uint8Array.from(bytes);
  return new Uint8Array(await crypto.subtle.digest("SHA-256", owned.buffer));
}

const parse = (value: string) => {
  const document = new DOMParser().parseFromString(value, "application/xml");
  const errors = document.getElementsByTagName("parsererror");
  if (errors.length) fail(`invalid XML: ${errors.item(0)?.textContent ?? "parse error"}`);
  return document;
};

type NamespaceMap = Map<string, string>;

function localNamespaceDeclarations(element: Element) {
  const declarations = new Map<string, string>();
  for (let index = 0; index < element.attributes.length; index++) {
    const attribute = element.attributes.item(index)!;
    if (attribute.namespaceURI === XMLNS || attribute.name === "xmlns") {
      const prefix = attribute.name === "xmlns"
        ? ""
        : (attribute.localName ?? attribute.name.replace(/^xmlns:/, ""));
      declarations.set(prefix, attribute.value);
    }
  }
  return declarations;
}

function inScopeNamespaces(element: Element) {
  const lineage: Element[] = [];
  let current: Node | null = element;
  while (current && current.nodeType === 1) {
    lineage.unshift(current as Element);
    current = current.parentNode;
  }
  const result = new Map<string, string>();
  result.set("xml", "http://www.w3.org/XML/1998/namespace");
  for (const node of lineage) {
    for (const [prefix, uri] of localNamespaceDeclarations(node)) {
      if (uri) result.set(prefix, uri);
      else result.delete(prefix);
    }
  }
  return result;
}

function canonicalElement(
  element: Element,
  renderedNamespaces: NamespaceMap,
  root: boolean,
): string {
  const scope = root
    ? inScopeNamespaces(element)
    : (() => {
      const result = new Map(renderedNamespaces);
      for (const [prefix, uri] of localNamespaceDeclarations(element)) {
        if (uri) result.set(prefix, uri);
        else result.delete(prefix);
      }
      return result;
    })();

  const namespaceNodes = [...scope.entries()]
    .filter(([prefix, uri]) => prefix !== "xml" && renderedNamespaces.get(prefix) !== uri)
    .sort(([left], [right]) => left.localeCompare(right));

  const attributes: Attr[] = [];
  for (let index = 0; index < element.attributes.length; index++) {
    const attribute = element.attributes.item(index)!;
    if (attribute.namespaceURI !== XMLNS && attribute.name !== "xmlns") {
      attributes.push(attribute);
    }
  }
  attributes.sort((left, right) => {
    const leftNamespace = left.namespaceURI ?? "";
    const rightNamespace = right.namespaceURI ?? "";
    return leftNamespace === rightNamespace
      ? (left.localName ?? left.name).localeCompare(right.localName ?? right.name)
      : leftNamespace.localeCompare(rightNamespace);
  });

  let result = `<${element.tagName}`;
  for (const [prefix, uri] of namespaceNodes) {
    result += prefix
      ? ` xmlns:${prefix}="${escapeAttribute(uri)}"`
      : ` xmlns="${escapeAttribute(uri)}"`;
  }
  for (const attribute of attributes) {
    result += ` ${attribute.name}="${escapeAttribute(attribute.value)}"`;
  }
  result += ">";

  const nextRendered = new Map(renderedNamespaces);
  for (const [prefix, uri] of namespaceNodes) nextRendered.set(prefix, uri);
  for (let child = element.firstChild; child; child = child.nextSibling) {
    switch (child.nodeType) {
      case 1:
        result += canonicalElement(child as Element, nextRendered, false);
        break;
      case 3:
      case 4:
        result += escapeText(child.nodeValue ?? "");
        break;
      case 7: {
        const value = child.nodeValue ? ` ${child.nodeValue}` : "";
        result += `<?${child.nodeName}${value}?>`;
        break;
      }
      default:
        // C14N 1.1 without comments omits comments and document metadata.
        break;
    }
  }
  return `${result}</${element.tagName}>`;
}

/**
 * Inclusive Canonical XML 1.1 without comments for Farsha-generated UBL.
 *
 * Farsha emits no DTD, xml:base, xml:id, entity reference, or namespace
 * undeclaration. Those are the C14N 1.1 cases that differ from the rendering
 * below. Rejecting external XML and canonicalizing only our controlled UBL
 * keeps this implementation deterministic and auditable.
 */
export function canonicalizeC14N11(value: string | Element) {
  const element = typeof value === "string" ? parse(value).documentElement! : value;
  return canonicalElement(element, new Map(), true);
}

function isQrReference(element: Element) {
  if (element.namespaceURI !== CAC || element.localName !== "AdditionalDocumentReference") {
    return false;
  }
  for (let child = element.firstChild; child; child = child.nextSibling) {
    if (
      child.nodeType === 1 &&
      (child as Element).namespaceURI === CBC &&
      (child as Element).localName === "ID" &&
      child.textContent?.trim() === "QR"
    ) return true;
  }
  return false;
}

function removeHashExclusions(element: Element) {
  for (let child = element.firstChild; child;) {
    const next = child.nextSibling;
    if (child.nodeType === 1) {
      const current = child as Element;
      const excluded =
        (current.namespaceURI === EXT && current.localName === "UBLExtensions") ||
        (current.namespaceURI === CAC && current.localName === "Signature") ||
        isQrReference(current);
      if (excluded) element.removeChild(current);
      else removeHashExclusions(current);
    }
    child = next;
  }
}

/** Implements the three XPath exclusions followed by C14N 1.1. */
export function canonicalInvoiceForHash(invoiceXml: string) {
  const document = parse(invoiceXml);
  const root = document.documentElement;
  if (!root || root.namespaceURI !== UBL || root.localName !== "Invoice") {
    fail("root must be a UBL 2.1 Invoice");
  }
  const validRoot = root!;
  removeHashExclusions(validRoot);
  return canonicalizeC14N11(validRoot);
}

export async function invoiceHash(invoiceXml: string) {
  const canonicalXml = canonicalInvoiceForHash(invoiceXml);
  const bytes = await sha256Bytes(canonicalXml);
  return { bytes, base64: bytesToBase64(bytes), canonicalXml };
}

export interface ZatcaSignerCertificate {
  /** Certificate chain, leaf first. Every entry is public DER + X.509 identity. */
  certificateChain: Array<{
    derBase64: string;
    issuerName: string;
    serialNumber: string;
  }>;
  /** Raw secp256k1 public point x || y (64 bytes, no 0x04 prefix). */
  publicKeyP1363: Uint8Array;
  /** ZATCA technical CA signature over the public key; simplified invoices only. */
  zatcaCaSignatureP1363?: Uint8Array;
  certificateId: string;
}

/**
 * Production implementations must delegate to a non-exportable secp256k1 key
 * held by an HSM/KMS. The application receives only the signature and public
 * certificate metadata; no private-key export method exists on this interface.
 */
export interface ZatcaSigner {
  certificate: ZatcaSignerCertificate;
  signSha256(message: Uint8Array): Promise<Uint8Array>;
  verifySha256(message: Uint8Array, signatureP1363: Uint8Array): Promise<boolean>;
}

export interface Phase2QrInput {
  invoiceKind: "simplified" | "tax";
  sellerName: string;
  sellerVatNumber: string;
  issuedAt: string;
  taxInclusiveAmount: string | number;
  vatAmount: string | number;
  invoiceHash: Uint8Array;
  signatureP1363: Uint8Array;
  publicKeyP1363: Uint8Array;
  zatcaCaSignatureP1363?: Uint8Array;
}

function money(value: string | number) {
  const number = Number(value);
  if (!Number.isFinite(number)) fail("QR monetary value is invalid");
  return number.toFixed(2);
}

function tlv(tag: number, value: Uint8Array) {
  if (!Number.isInteger(tag) || tag < 1 || tag > 255) fail("invalid TLV tag");
  if (value.length > 255) fail(`QR tag ${tag} exceeds the one-byte length limit`);
  return Uint8Array.from([tag, value.length, ...value]);
}

export function buildPhase2Qr(input: Phase2QrInput) {
  if (input.invoiceHash.length !== 32) fail("QR tag 6 must be a 32-byte SHA-256 hash");
  if (input.signatureP1363.length !== 64) fail("QR tag 7 must be a 64-byte IEEE P1363 signature");
  if (input.publicKeyP1363.length !== 64) fail("QR tag 8 must be a 64-byte secp256k1 public key");
  if (input.invoiceKind === "simplified" && input.zatcaCaSignatureP1363?.length !== 64) {
    fail("simplified QR tag 9 requires the 64-byte ZATCA CA signature");
  }

  const timestamp = new Date(input.issuedAt);
  if (Number.isNaN(timestamp.getTime())) fail("QR timestamp is invalid");
  // UBL IssueTime is serialized at whole-second precision. PostgreSQL
  // timestamptz values can include fractional seconds, so QR tag 3 must use
  // the exact same precision as the signed XML.
  const invoiceTimestamp = timestamp.toISOString().slice(0, 19) + "Z";
  const values: Array<[number, Uint8Array]> = [
    [1, textEncoder.encode(input.sellerName)],
    [2, textEncoder.encode(input.sellerVatNumber)],
    [3, textEncoder.encode(invoiceTimestamp)],
    [4, textEncoder.encode(money(input.taxInclusiveAmount))],
    [5, textEncoder.encode(money(input.vatAmount))],
    [6, input.invoiceHash],
    [7, input.signatureP1363],
    [8, input.publicKeyP1363],
  ];
  if (input.invoiceKind === "simplified") {
    values.push([9, input.zatcaCaSignatureP1363!]);
  }
  const totalLength = values.reduce((sum, [, value]) => sum + value.length + 2, 0);
  const encoded = new Uint8Array(totalLength);
  let offset = 0;
  for (const [tag, value] of values) {
    const tuple = tlv(tag, value);
    encoded.set(tuple, offset);
    offset += tuple.length;
  }
  const base64 = bytesToBase64(encoded);
  if (base64.length > 700) fail("QR payload exceeds 700 Base64 characters");
  return base64;
}

export function decodePhase2Qr(value: string) {
  const bytes = base64ToBytes(value);
  const fields = new Map<number, Uint8Array>();
  for (let offset = 0; offset < bytes.length;) {
    if (offset + 2 > bytes.length) fail("truncated QR TLV header");
    const tag = bytes[offset++];
    const length = bytes[offset++];
    if (offset + length > bytes.length) fail(`truncated QR TLV value for tag ${tag}`);
    if (fields.has(tag)) fail(`duplicate QR tag ${tag}`);
    fields.set(tag, bytes.slice(offset, offset + length));
    offset += length;
  }
  return fields;
}

function securityReference(id: "ICV" | "PIH" | "QR", value: string | number) {
  if (id === "ICV") {
    return `<cac:AdditionalDocumentReference><cbc:ID>ICV</cbc:ID><cbc:UUID>${xml(value)}</cbc:UUID></cac:AdditionalDocumentReference>`;
  }
  return `<cac:AdditionalDocumentReference><cbc:ID>${id}</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="text/plain">${xml(value)}</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference>`;
}

const mainSignature =
  `<cac:Signature><cbc:ID>urn:oasis:names:specification:ubl:signature:Invoice</cbc:ID>` +
  `<cbc:SignatureMethod>urn:oasis:names:specification:ubl:dsig:enveloped:xades</cbc:SignatureMethod></cac:Signature>`;

export function addIcvAndPih(businessXml: string, icv: number, previousInvoiceHash: string) {
  if (!Number.isSafeInteger(icv) || icv < 1) fail("ICV must be a positive integer");
  const previousHashBytes = base64ToBytes(previousInvoiceHash);
  if (previousInvoiceHash !== INITIAL_PIH && previousHashBytes.length !== 32) {
    // The official first-invoice constant is Base64 of the 64-character
    // hexadecimal SHA-256 of "0". Later PIHs use the previous 32-byte digest.
    fail("PIH must be the official initial value or a Base64 SHA-256 digest");
  }
  if (businessXml.includes("<cbc:ID>ICV</cbc:ID>") || businessXml.includes("<cbc:ID>PIH</cbc:ID>")) {
    fail("invoice already contains ICV/PIH security references");
  }
  const marker = "<cac:AccountingSupplierParty>";
  if (!businessXml.includes(marker)) fail("cannot locate UBL supplier party insertion point");
  const references = securityReference("ICV", icv) + securityReference("PIH", previousInvoiceHash) + mainSignature;
  return businessXml.replace(marker, references + marker);
}

function addQr(securityBaseXml: string, qr: string) {
  const marker = mainSignature;
  if (!securityBaseXml.includes(marker)) fail("cannot locate UBL signature insertion point");
  return securityBaseXml.replace(marker, securityReference("QR", qr) + marker);
}

function addExtension(invoiceXml: string, extension: string) {
  const match = invoiceXml.match(/<Invoice\b[^>]*>/);
  if (!match || match.index === undefined) fail("cannot locate UBL Invoice root");
  const rootMatch = match!;
  const offset = rootMatch.index! + rootMatch[0].length;
  return invoiceXml.slice(0, offset) + extension + invoiceXml.slice(offset);
}

interface CertificateReference {
  digest: string;
  issuerName: string;
  serialNumber: string;
}

function signedProperties(
  signingTime: string,
  certificates: CertificateReference[],
) {
  return `<xades:SignedProperties Id="xadesSignedProperties">` +
    `<xades:SignedSignatureProperties><xades:SigningTime>${xml(signingTime)}</xades:SigningTime>` +
    `<xades:SigningCertificate>${certificates.map((certificate) =>
      `<xades:Cert><xades:CertDigest>` +
      `<ds:DigestMethod Algorithm="${SHA256}"></ds:DigestMethod><ds:DigestValue>${certificate.digest}</ds:DigestValue>` +
      `</xades:CertDigest><xades:IssuerSerial><ds:X509IssuerName>${xml(certificate.issuerName)}</ds:X509IssuerName>` +
      `<ds:X509SerialNumber>${xml(certificate.serialNumber)}</ds:X509SerialNumber></xades:IssuerSerial>` +
      `</xades:Cert>`
    ).join("")}</xades:SigningCertificate>` +
    `<xades:SignaturePolicyIdentifier><xades:SignaturePolicyImplied></xades:SignaturePolicyImplied></xades:SignaturePolicyIdentifier>` +
    `</xades:SignedSignatureProperties><xades:SignedDataObjectProperties>` +
    `<xades:DataObjectFormat ObjectReference="#invoiceSignedData"><xades:MimeType>text/xml</xades:MimeType></xades:DataObjectFormat>` +
    `</xades:SignedDataObjectProperties></xades:SignedProperties>`;
}

const signatureNamespaces =
  ` xmlns="${UBL}" xmlns:sig="${SIG}" xmlns:sac="${SAC}" xmlns:sbc="${SBC}"` +
  ` xmlns:ds="${DS}" xmlns:xades="${XADES}" xmlns:ext="${EXT}"` +
  ` xmlns:cac="${CAC}" xmlns:cbc="${CBC}"`;

function canonicalizeSignatureFragment(fragment: string) {
  const document = parse(`<holder${signatureNamespaces}>${fragment}</holder>`);
  const root = document.documentElement;
  if (!root) fail("signature fragment wrapper is missing");
  const wrapper = root!;
  const element = [...Array.from({ length: wrapper.childNodes.length }, (_, index) =>
    wrapper.childNodes.item(index))]
    .find((node) => node?.nodeType === 1) as Element | undefined;
  if (!element) fail("empty signature fragment");
  return canonicalizeC14N11(element!);
}

function signedInfo(invoiceDigest: string, propertiesDigest: string) {
  return `<ds:SignedInfo>` +
    `<ds:CanonicalizationMethod Algorithm="${C14N11}"></ds:CanonicalizationMethod>` +
    `<ds:SignatureMethod Algorithm="${ECDSA_SHA256}"></ds:SignatureMethod>` +
    `<ds:Reference Id="invoiceSignedData" URI=""><ds:Transforms>` +
    `<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::ext:UBLExtensions)</ds:XPath></ds:Transform>` +
    `<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::cac:Signature)</ds:XPath></ds:Transform>` +
    `<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::cac:AdditionalDocumentReference[cbc:ID='QR'])</ds:XPath></ds:Transform>` +
    `<ds:Transform Algorithm="${C14N11}"></ds:Transform></ds:Transforms>` +
    `<ds:DigestMethod Algorithm="${SHA256}"></ds:DigestMethod><ds:DigestValue>${invoiceDigest}</ds:DigestValue></ds:Reference>` +
    `<ds:Reference Type="http://uri.etsi.org/01903#SignedProperties" URI="#xadesSignedProperties">` +
    `<ds:DigestMethod Algorithm="${SHA256}"></ds:DigestMethod><ds:DigestValue>${propertiesDigest}</ds:DigestValue></ds:Reference>` +
    `</ds:SignedInfo>`;
}

function signatureExtension(
  info: string,
  signatureValue: string,
  properties: string,
  certificate: ZatcaSignerCertificate,
) {
  const certificates = certificate.certificateChain
    .map((value) => `<ds:X509Certificate>${value.derBase64.replaceAll(/\s/g, "")}</ds:X509Certificate>`)
    .join("");
  return `<ext:UBLExtensions><ext:UBLExtension>` +
    `<ext:ExtensionURI>urn:oasis:names:specification:ubl:dsig:enveloped:xades</ext:ExtensionURI>` +
    `<ext:ExtensionContent><sig:UBLDocumentSignatures${signatureNamespaces}>` +
    `<sac:SignatureInformation><cbc:ID>urn:oasis:names:specification:ubl:signature:1</cbc:ID>` +
    `<sbc:ReferencedSignatureID>urn:oasis:names:specification:ubl:signature:Invoice</sbc:ReferencedSignatureID>` +
    `<ds:Signature Id="signature">${info}<ds:SignatureValue>${signatureValue}</ds:SignatureValue>` +
    `<ds:KeyInfo><ds:X509Data>${certificates}</ds:X509Data></ds:KeyInfo>` +
    `<ds:Object><xades:QualifyingProperties Target="#signature">${properties}</xades:QualifyingProperties></ds:Object>` +
    `</ds:Signature></sac:SignatureInformation></sig:UBLDocumentSignatures></ext:ExtensionContent>` +
    `</ext:UBLExtension></ext:UBLExtensions>`;
}

export interface StampInput {
  businessXml: string;
  icv: number;
  previousInvoiceHash: string;
  invoiceKind: "simplified" | "tax";
  sellerName: string;
  sellerVatNumber: string;
  issuedAt: string;
  taxInclusiveAmount: string | number;
  vatAmount: string | number;
  signingTime: string;
}

export interface StampedInvoice {
  securityBaseXml: string;
  canonicalInvoiceXml: string;
  canonicalSignedInfo: string;
  invoiceHash: string;
  signedPropertiesDigest: string;
  signatureValue: string;
  qr: string;
  signedXml: string;
}

const SECP256K1_SPKI_PREFIX = Uint8Array.from([
  0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
  0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x0a, 0x03, 0x42, 0x00, 0x04,
]);

function certificatePublicKeyP1363(certificateDer: Uint8Array): Uint8Array {
  outer: for (let offset = 0; offset <= certificateDer.length - SECP256K1_SPKI_PREFIX.length - 64; offset++) {
    for (let index = 0; index < SECP256K1_SPKI_PREFIX.length; index++) {
      if (certificateDer[offset + index] !== SECP256K1_SPKI_PREFIX[index]) continue outer;
    }
    return certificateDer.slice(
      offset + SECP256K1_SPKI_PREFIX.length,
      offset + SECP256K1_SPKI_PREFIX.length + 64,
    );
  }
  return fail("leaf X.509 certificate does not contain a secp256k1 public key");
}

function sameBytes(left: Uint8Array, right: Uint8Array) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

/**
 * Official order: ICV/PIH -> three hash exclusions -> C14N 1.1 -> SHA-256
 * -> XAdES SignedInfo signature -> Phase-2 QR -> embed QR and stamp.
 * Standard invoices are stamped/QR-completed by ZATCA during clearance and
 * therefore must not be locally stamped by Farsha in Stage 3.
 */
export async function stampSimplifiedInvoice(
  input: StampInput,
  signer: ZatcaSigner,
): Promise<StampedInvoice> {
  if (input.invoiceKind !== "simplified") {
    fail("standard invoice local stamping is forbidden; ZATCA clearance must return the final stamp and QR");
  }
  const certificate = signer.certificate;
  if (!certificate.certificateChain.length) fail("signing certificate chain is missing");
  if (certificate.certificateChain.some((entry) =>
    !entry.derBase64.trim() || !entry.issuerName.trim() || !entry.serialNumber.trim()
  )) fail("every signing certificate requires DER, issuer name and serial number");
  if (certificate.publicKeyP1363.length !== 64) fail("certificate public key must be 64-byte secp256k1 x || y");
  if (certificate.zatcaCaSignatureP1363?.length !== 64) fail("ZATCA CA public-key signature is missing");
  const leafCertificate = base64ToBytes(certificate.certificateChain[0].derBase64);
  if (!sameBytes(certificatePublicKeyP1363(leafCertificate), certificate.publicKeyP1363)) {
    fail("QR public key does not match the leaf X.509 certificate");
  }

  const securityBaseXml = addIcvAndPih(input.businessXml, input.icv, input.previousInvoiceHash);
  const hash = await invoiceHash(securityBaseXml);
  const certificateReferences = await Promise.all(certificate.certificateChain.map(async (entry) => ({
    digest: bytesToBase64(await sha256Bytes(base64ToBytes(entry.derBase64))),
    issuerName: entry.issuerName,
    serialNumber: entry.serialNumber,
  })));
  const properties = signedProperties(input.signingTime, certificateReferences);
  const propertiesDigest = bytesToBase64(
    await sha256Bytes(canonicalizeSignatureFragment(properties)),
  );
  const info = signedInfo(hash.base64, propertiesDigest);
  const canonicalSignedInfo = canonicalizeSignatureFragment(info);
  const signature = await signer.signSha256(textEncoder.encode(canonicalSignedInfo));
  if (signature.length !== 64) fail("HSM signer must return a 64-byte IEEE P1363 ECDSA signature");
  if (!(await signer.verifySha256(textEncoder.encode(canonicalSignedInfo), signature))) {
    fail("HSM signature did not verify against the configured certificate identity");
  }
  const signatureValue = bytesToBase64(signature);
  const qr = buildPhase2Qr({
    invoiceKind: "simplified",
    sellerName: input.sellerName,
    sellerVatNumber: input.sellerVatNumber,
    issuedAt: input.issuedAt,
    taxInclusiveAmount: input.taxInclusiveAmount,
    vatAmount: input.vatAmount,
    invoiceHash: hash.bytes,
    signatureP1363: signature,
    publicKeyP1363: certificate.publicKeyP1363,
    zatcaCaSignatureP1363: certificate.zatcaCaSignatureP1363,
  });
  const withQr = addQr(securityBaseXml, qr);
  const signedXml = addExtension(
    withQr,
    signatureExtension(info, signatureValue, properties, certificate),
  );
  const finalHash = await invoiceHash(signedXml);
  if (finalHash.base64 !== hash.base64) fail("embedding signature/QR changed the protected invoice hash");
  return {
    securityBaseXml,
    canonicalInvoiceXml: hash.canonicalXml,
    canonicalSignedInfo,
    invoiceHash: hash.base64,
    signedPropertiesDigest: propertiesDigest,
    signatureValue,
    qr,
    signedXml,
  };
}

export async function verifyStampedInvoice(
  stamped: StampedInvoice,
  signer: ZatcaSigner,
) {
  try {
    const document = parse(stamped.signedXml);
    const signedInfoElement = document.getElementsByTagNameNS(DS, "SignedInfo").item(0);
    const signatureElement = document.getElementsByTagNameNS(DS, "SignatureValue").item(0);
    if (!signedInfoElement || !signatureElement) return false;
    const digestValues = document.getElementsByTagNameNS(DS, "DigestValue");
    if (digestValues.length < 2 + signer.certificate.certificateChain.length) return false;
    const hash = await invoiceHash(stamped.signedXml);
    if (digestValues.item(0)?.textContent !== hash.base64) return false;
    const signedPropertiesElement = document.getElementsByTagNameNS(XADES, "SignedProperties").item(0);
    if (!signedPropertiesElement) return false;
    const propertiesDigest = bytesToBase64(
      await sha256Bytes(canonicalizeC14N11(signedPropertiesElement as Element)),
    );
    if (digestValues.item(1)?.textContent !== propertiesDigest) return false;
    for (let index = 0; index < signer.certificate.certificateChain.length; index++) {
      const expected = bytesToBase64(await sha256Bytes(
        base64ToBytes(signer.certificate.certificateChain[index].derBase64),
      ));
      if (digestValues.item(index + 2)?.textContent !== expected) return false;
    }

    const embeddedCertificates = document.getElementsByTagNameNS(DS, "X509Certificate");
    if (embeddedCertificates.length !== signer.certificate.certificateChain.length) return false;
    for (let index = 0; index < embeddedCertificates.length; index++) {
      if (
        embeddedCertificates.item(index)?.textContent?.replaceAll(/\s/g, "") !==
          signer.certificate.certificateChain[index].derBase64.replaceAll(/\s/g, "")
      ) return false;
    }

    let qr = "";
    const references = document.getElementsByTagNameNS(CAC, "AdditionalDocumentReference");
    for (let index = 0; index < references.length; index++) {
      const reference = references.item(index) as Element;
      const id = reference.getElementsByTagNameNS(CBC, "ID").item(0)?.textContent?.trim();
      if (id === "QR") {
        qr = reference.getElementsByTagNameNS(CBC, "EmbeddedDocumentBinaryObject").item(0)?.textContent?.trim() ?? "";
        break;
      }
    }
    const qrFields = decodePhase2Qr(qr);
    if ([...qrFields.keys()].join(",") !== "1,2,3,4,5,6,7,8,9") return false;
    const signature = base64ToBytes(signatureElement.textContent ?? "");
    if (!sameBytes(qrFields.get(6)!, hash.bytes) || !sameBytes(qrFields.get(7)!, signature)) return false;
    if (!sameBytes(qrFields.get(8)!, signer.certificate.publicKeyP1363)) return false;
    if (!sameBytes(qrFields.get(9)!, signer.certificate.zatcaCaSignatureP1363!)) return false;

    const qrText = (tag: number) => new TextDecoder().decode(qrFields.get(tag));
    const supplier = document.getElementsByTagNameNS(CAC, "AccountingSupplierParty").item(0) as Element | null;
    const totals = document.getElementsByTagNameNS(CAC, "LegalMonetaryTotal").item(0) as Element | null;
    const taxTotal = document.getElementsByTagNameNS(CAC, "TaxTotal").item(0) as Element | null;
    const issueDate = document.getElementsByTagNameNS(CBC, "IssueDate").item(0)?.textContent ?? "";
    const issueTime = document.getElementsByTagNameNS(CBC, "IssueTime").item(0)?.textContent ?? "";
    if (!supplier || !totals || !taxTotal) return false;
    const sellerName = supplier.getElementsByTagNameNS(CBC, "RegistrationName").item(0)?.textContent ?? "";
    const sellerVat = supplier.getElementsByTagNameNS(CBC, "CompanyID").item(0)?.textContent ?? "";
    const total = totals.getElementsByTagNameNS(CBC, "TaxInclusiveAmount").item(0)?.textContent ?? "";
    const vat = taxTotal.getElementsByTagNameNS(CBC, "TaxAmount").item(0)?.textContent ?? "";
    const timestamp = new Date(`${issueDate}T${issueTime}`).toISOString().replace(".000Z", "Z");
    if (qrText(1) !== sellerName || qrText(2) !== sellerVat || qrText(3) !== timestamp) return false;
    if (qrText(4) !== money(total) || qrText(5) !== money(vat)) return false;

    const canonicalInfo = canonicalizeC14N11(signedInfoElement as Element);
    return signer.verifySha256(textEncoder.encode(canonicalInfo), signature);
  } catch {
    return false;
  }
}

export function canonicalSignedInfoFromXml(signedXml: string) {
  const document = parse(signedXml);
  const element = document.getElementsByTagNameNS(DS, "SignedInfo").item(0);
  if (!element) fail("signed XML has no ds:SignedInfo");
  return canonicalizeC14N11(element as Element);
}
