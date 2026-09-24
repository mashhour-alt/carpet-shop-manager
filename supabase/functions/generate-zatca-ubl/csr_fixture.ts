import { buildZatcaCsrOpenSslConfig } from "./csr.ts";

const config = buildZatcaCsrOpenSslConfig({
  commonName: "Farsha-Test-EGS-001",
  egsSerialNumber: "1-Farsha-Test|2-Stage3|3-000001",
  organizationIdentifier: "310000000000003",
  organizationUnitName: "Riyadh Test Branch",
  organizationName: "Farsha Test Organization",
  countryCode: "SA",
  invoiceTypeMap: "1100",
  location: "TEST-RIYADH-ONLY",
  industry: "Carpet retail test fixture",
});

await Deno.mkdir("build", { recursive: true });
await Deno.writeTextFile("build/zatca-stage3-test-csr.cnf", config);
