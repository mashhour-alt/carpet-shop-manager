export interface ZatcaCsrFields {
  commonName: string;
  egsSerialNumber: string;
  organizationIdentifier: string;
  organizationUnitName: string;
  organizationName: string;
  countryCode: string;
  invoiceTypeMap: string;
  location: string;
  industry: string;
}

export interface ZatcaCsrSettings {
  institution: {
    legalName: string;
    vatNumber: string;
    organizationUnitName: string;
    countryCode: string;
  };
  egs: {
    commonName: string;
    serialNumber: string;
    invoiceTypeMap: string;
    location: string;
    industry: string;
  };
}

export interface NonExportableCsrProvider {
  /**
   * Generate a secp256k1 key inside the security module and return a PKCS#10
   * CSR signed with SHA-256. The provider must never return the private key.
   */
  generatePkcs10(request: {
    openSslConfig: string;
    curve: "secp256k1";
    digest: "sha256";
    keyExportable: false;
  }): Promise<{ csrPem: string; keyReference: string }>;
}

export type ZatcaCsrEnvironment = "compliance" | "production";

const value = (input: unknown) => String(input ?? "").trim();

const rejectUnsafeConfigValue = (input: string, field: string) => {
  if (!input || /[\r\n\0]/.test(input)) {
    throw new Error(`CSR ${field} is required and must be one line`);
  }
  if (input.length > 200) {
    throw new Error(`CSR ${field} exceeds 200 characters`);
  }
  return input;
};

/** Validations are taken from the official Security Standard 1.2 CSR table. */
export function validateZatcaCsrFields(input: ZatcaCsrFields) {
  const fields = {
    commonName: rejectUnsafeConfigValue(value(input.commonName), "common name"),
    egsSerialNumber: rejectUnsafeConfigValue(
      value(input.egsSerialNumber),
      "EGS serial number",
    ),
    organizationIdentifier: value(input.organizationIdentifier),
    organizationUnitName: rejectUnsafeConfigValue(
      value(input.organizationUnitName),
      "organization unit",
    ),
    organizationName: rejectUnsafeConfigValue(
      value(input.organizationName),
      "organization name",
    ),
    countryCode: value(input.countryCode).toUpperCase(),
    invoiceTypeMap: value(input.invoiceTypeMap),
    location: rejectUnsafeConfigValue(value(input.location), "location"),
    industry: rejectUnsafeConfigValue(value(input.industry), "industry"),
  };
  if (!/^1-[^|]+\|2-[^|]+\|3-[^|]+$/.test(fields.egsSerialNumber)) {
    throw new Error(
      "CSR EGS serial number must use 1-provider|2-model|3-serial format",
    );
  }
  if (!/^3\d{13}3$/.test(fields.organizationIdentifier)) {
    throw new Error(
      "CSR organization identifier must be a 15-digit VAT number starting and ending with 3",
    );
  }
  if (!/^[A-Z]{2}$/.test(fields.countryCode)) {
    throw new Error("CSR country code must be ISO 3166-1 alpha-2");
  }
  if (
    !/^[01]{4}$/.test(fields.invoiceTypeMap) || fields.invoiceTypeMap === "0000"
  ) {
    throw new Error(
      "CSR invoice type map must be four 0/1 digits and cannot be 0000",
    );
  }
  if (
    fields.organizationIdentifier[10] === "1" &&
    !/^\d{10}$/.test(fields.organizationUnitName)
  ) {
    throw new Error(
      "VAT-group CSR organization unit must be the 10-digit member TIN",
    );
  }
  return fields;
}

/**
 * Maps persisted Institution + EGS settings without defaults. Missing real
 * identity data fails validation instead of being fabricated by the backend.
 */
export function csrFieldsFromSettings(input: ZatcaCsrSettings): ZatcaCsrFields {
  return validateZatcaCsrFields({
    commonName: input.egs.commonName,
    egsSerialNumber: input.egs.serialNumber,
    organizationIdentifier: input.institution.vatNumber,
    organizationUnitName: input.institution.organizationUnitName,
    organizationName: input.institution.legalName,
    countryCode: input.institution.countryCode,
    invoiceTypeMap: input.egs.invoiceTypeMap,
    location: input.egs.location,
    industry: input.egs.industry,
  });
}

/**
 * Produces the exact OpenSSL request profile documented by ZATCA Developer
 * Portal Manual v3. It contains public CSR identity fields only, never a key.
 */
export function buildZatcaCsrOpenSslConfig(
  input: ZatcaCsrFields,
  environment: ZatcaCsrEnvironment = "compliance",
) {
  const field = validateZatcaCsrFields(input);
  const certificateTemplate = environment === "compliance"
    ? "TSTZATCA-Code-Signing"
    : "ZATCA-Code-Signing";
  return `oid_section = OIDs

[ OIDs ]
certificateTemplateName = 1.3.6.1.4.1.311.20.2

[ req ]
prompt = no
utf8 = yes
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[ dn ]
C = ${field.countryCode}
OU = ${field.organizationUnitName}
O = ${field.organizationName}
CN = ${field.commonName}

[ req_ext ]
certificateTemplateName = ASN1:PRINTABLESTRING:${certificateTemplate}
subjectAltName = dirName:alt_names

[ alt_names ]
SN = ${field.egsSerialNumber}
UID = ${field.organizationIdentifier}
title = ${field.invoiceTypeMap}
registeredAddress = ${field.location}
businessCategory = ${field.industry}
`;
}

export async function generateZatcaCsr(
  input: ZatcaCsrFields,
  provider: NonExportableCsrProvider,
  environment: ZatcaCsrEnvironment = "compliance",
) {
  const openSslConfig = buildZatcaCsrOpenSslConfig(input, environment);
  const result = await provider.generatePkcs10({
    openSslConfig,
    curve: "secp256k1",
    digest: "sha256",
    keyExportable: false,
  });
  if (
    !/^-----BEGIN CERTIFICATE REQUEST-----[\s\S]+-----END CERTIFICATE REQUEST-----\s*$/
      .test(result.csrPem)
  ) {
    throw new Error("CSR provider returned an invalid PKCS#10 PEM envelope");
  }
  if (!result.keyReference || /BEGIN .*PRIVATE KEY/.test(result.keyReference)) {
    throw new Error(
      "CSR provider must return an opaque non-exportable key reference",
    );
  }
  return { ...result, openSslConfig };
}
