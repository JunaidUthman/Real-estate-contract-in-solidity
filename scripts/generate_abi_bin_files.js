const fs = require('fs');
const path = require('path');
const solc = require('solc');

// --- Paths ---
const CONTRACT_PATH = path.join(__dirname, '..', 'contracts', 'RealEstateRental.sol');

// --- Load contract source ---
const source = fs.readFileSync(CONTRACT_PATH, 'utf8');

// --- Import callback for solc (to load OpenZeppelin) ---
function findImports(importPath) {
    try {
        if (importPath.startsWith('@openzeppelin')) {
            const fullPath = path.join(__dirname, '..', 'node_modules', importPath);
            return { contents: fs.readFileSync(fullPath, 'utf8') };
        } else if (importPath.startsWith('./') || importPath.startsWith('../')) {
            const fullPath = path.join(path.dirname(CONTRACT_PATH), importPath);
            return { contents: fs.readFileSync(fullPath, 'utf8') };
        } else {
            return { error: 'File not found: ' + importPath };
        }
    } catch (err) {
        return { error: err.message };
    }
}

// --- Compiler input ---
const input = {
    language: 'Solidity',
    sources: {
        'main.sol': {
            content: source
        }
    },
    settings: {
        outputSelection: {
            '*': {
                '*': ['abi', 'evm.bytecode.object']
            }
        }
    }
};

// --- Compile ---
const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));

if (output.errors) {
    output.errors.forEach((err) => {
        console.log(err.formattedMessage);
    });
}

// --- Verify compilation ---
if (!output.contracts || !output.contracts["main.sol"]) {
    console.error("❌ Compilation failed. No contracts in output.");
    process.exit(1);
}

// --- Extract contracts ---
const contracts = output.contracts["main.sol"];

for (const name in contracts) {
    const c = contracts[name];

    const abiPath = path.join(__dirname, '..', 'contracts', `${name}.abi`);
    const binPath = path.join(__dirname, '..', 'contracts', `${name}.bin`);

    fs.writeFileSync(abiPath, JSON.stringify(c.abi, null, 2));
    fs.writeFileSync(binPath, c.evm.bytecode.object);

    console.log(`✅ Generated: ${name}.abi and ${name}.bin`);
}
