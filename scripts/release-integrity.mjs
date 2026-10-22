import { existsSync, readFileSync, statSync } from "node:fs";

const expected = "2.0.0";
const required = [
    "README.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "assets/banner.png",
    "docs/arquitectura.md",
    "docs/modelo-economico.md",
    "docs/riesgo-liquidez.md",
    "docs/operacion.md",
    "docs/integracion.md",
    "src/risk/LumenLiquidityRisk.sol",
];
const pkg = JSON.parse(readFileSync("package.json", "utf8"));

if (pkg.version !== expected)
    throw new Error(`package version is ${pkg.version}`);
for (const path of required) {
    if (!existsSync(path) || statSync(path).size === 0) {
        throw new Error(`missing release artifact: ${path}`);
    }
}
if (statSync("assets/banner.png").size < 100_000) {
    throw new Error("banner does not meet the production asset gate");
}
const ref = process.env.GITHUB_REF ?? "";
if (ref.startsWith("refs/tags/") && ref !== `refs/tags/v${expected}`) {
    throw new Error(`tag ${ref} does not match v${expected}`);
}
console.log(`release integrity verified for v${expected}`);
