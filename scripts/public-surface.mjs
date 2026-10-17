import { readFileSync, readdirSync, statSync } from "node:fs";
import { extname, join } from "node:path";

const roots = ["README.md", "SECURITY.md", "docs", "src", "tests", "script"];
const extensions = new Set([".md", ".sol"]);
const prohibited = [
    new RegExp("\\b" + "c" + "tf" + "\\b", "iu"),
    new RegExp("labor" + "ator", "iu"),
    new RegExp("vulner" + "abil", "iu"),
    new RegExp("\\b" + "expl" + "oit" + "\\b", "iu"),
];
const findings = [];

function inspect(path) {
    if (statSync(path).isDirectory()) {
        for (const entry of readdirSync(path)) inspect(join(path, entry));
        return;
    }
    if (!extensions.has(extname(path))) return;
    const source = readFileSync(path, "utf8");
    for (const pattern of prohibited) {
        if (pattern.test(source)) findings.push(`${path}: ${pattern}`);
    }
}

for (const root of roots) inspect(root);
if (findings.length > 0) {
    throw new Error(
        `public surface contains restricted terms\n${findings.join("\n")}`,
    );
}
console.log(`public surface verified across ${roots.length} roots`);
