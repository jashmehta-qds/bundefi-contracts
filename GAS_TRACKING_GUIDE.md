# 📊 Gas Tracking System Guide

This guide explains how to use the automated gas tracking system for YieldMaxCCIP contract functions.

## 🚀 Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Run Gas Analysis

```bash
# Generate gas report (console output only)
npm run gas-report

# Generate gas report AND update README.md
npm run update-readme

# Test the gas tracker (dry run)
npm run test-gas-tracker
```

## 📋 What It Tracks

The gas tracker monitors the following YieldMaxCCIP functions:

- **Contract Deployment** - One-time deployment cost
- **sendCrossChainExecution** - Send cross-chain messages with tokens
- **ccipReceive** - Receive and process cross-chain messages  
- **allowlistSourceChain** - Manage source chain allowlists
- **allowlistDestinationChain** - Manage destination chain allowlists
- **estimateFee** - Calculate cross-chain execution costs
- **retryFailedMessage** - Retry failed cross-chain messages
- **rescueEscrow** - Rescue escrowed native tokens
- **rescueERC20Escrow** - Rescue escrowed ERC20 tokens

## 📈 Features

### Gas Comparison
- Compares current gas usage with previous runs
- Shows percentage improvements/regressions
- Color-coded indicators (🟢 improvement, 🔴 regression, 🟡 minimal change)

### Visual Diagrams
- Generates Mermaid diagrams showing gas usage hierarchy
- Color-coded nodes based on gas consumption levels
- Automatically embedded in README.md

### Historical Tracking
- Saves timestamped gas reports in `gas-reports/` directory
- Maintains `latest.json` for comparisons
- Preserves historical data for trend analysis

### Automated README Updates
- Inserts/updates gas analysis section in README.md
- Includes both visual diagrams and detailed tables
- Adds timestamp for tracking when analysis was last run

## 🔧 How It Works

### 1. Test Execution
```bash
forge test --match-contract YieldMaxCCIPTest --gas-report
```

### 2. Gas Parsing
- Extracts gas usage from Foundry's gas report output
- Falls back to individual test runs for precise measurements
- Handles both deployment and function call gas costs

### 3. Comparison & Analysis
- Loads previous gas reports from `gas-reports/latest.json`
- Calculates percentage changes for each function
- Generates improvement/regression indicators

### 4. Report Generation
- Creates visual Mermaid diagrams
- Builds detailed comparison tables
- Formats results for both console and README

### 5. Storage
- Saves current results as `gas-reports/latest.json`
- Creates timestamped backup in `gas-reports/gas-report-{timestamp}.json`
- Maintains historical data for trend analysis

## 📁 File Structure

```
ccip-starter-kit-foundry/
├── scripts/
│   ├── gas-tracker.ts          # Main gas tracking script
│   └── test-gas-tracker.ts     # Test script
├── gas-reports/                # Generated gas reports
│   ├── latest.json            # Latest gas data for comparisons
│   └── gas-report-*.json      # Timestamped historical reports
├── package.json               # NPM scripts and dependencies
├── tsconfig.json              # TypeScript configuration
└── README.md                  # Auto-updated with gas analysis
```

## 🎯 Example Output

### Console Output
```
🚀 Starting Gas Usage Analysis for YieldMaxCCIP

🔥 Running Foundry tests with gas reporting...
✅ Tests completed successfully

📊 Gas Usage Report:
════════════════════════════════════════════════════════════════════════════════
Contract Deployment          2,841,234 gas
sendCrossChainExecution        234,567 gas (-2.3% 🟢)
ccipReceive                    189,432 gas (+1.1% 🟡)
allowlistSourceChain            45,123 gas (-0.5% 🟢)
estimateFee                     23,456 gas
════════════════════════════════════════════════════════════════════════════════

✅ Gas analysis complete!
💾 Gas reports saved to gas-reports/latest.json and gas-reports/gas-report-2024-01-15T10-30-45-123Z.json
📝 README.md updated with gas usage information
```

### README Integration
The script automatically adds a comprehensive gas analysis section to your README.md:

- **Mermaid diagrams** showing gas usage hierarchy
- **Detailed tables** with current vs previous gas usage
- **Optimization notes** explaining gas patterns
- **Usage instructions** for running the analysis

## 🛠️ Customization

### Adding New Functions
To track additional functions, modify the `functionPatterns` array in `gas-tracker.ts`:

```typescript
const functionPatterns = [
  { name: 'yourFunction', pattern: /yourFunction.*?(\d+)/, desc: 'Description of your function' },
  // ... existing patterns
];
```

### Adjusting Gas Thresholds
Modify the gas level thresholds in the `generateGasDiagram` method:

```typescript
if (report.gasUsed > 200000) {
  // High gas usage
} else if (report.gasUsed > 100000) {
  // Medium gas usage
} else {
  // Low gas usage
}
```

### Custom Report Formats
The `generateGasTable` and `generateGasDiagram` methods can be customized to change the output format.

## 🐛 Troubleshooting

### "No gas usage data found"
- Ensure tests are passing: `forge test --match-contract YieldMaxCCIPTest`
- Check that test contract name matches: `YieldMaxCCIPTest`
- Verify Foundry is installed and working

### "Error running tests"
- Run tests manually first: `forge test`
- Check that all dependencies are installed
- Ensure you're in the project root directory

### TypeScript errors
- Install dependencies: `npm install`
- Check TypeScript configuration: `npx tsc --noEmit`

### Permission errors
- Make scripts executable: `chmod +x scripts/*.ts`
- Check file permissions in project directory

## 📊 Interpreting Results

### Gas Usage Levels
- **High (>200k gas)**: Complex operations like cross-chain sends
- **Medium (100k-200k gas)**: Message processing and validation
- **Low (<100k gas)**: Simple state changes and view functions

### Change Indicators
- **🟢 Green**: Gas usage decreased (optimization)
- **🔴 Red**: Gas usage increased significantly (>5%)
- **🟡 Yellow**: Minor changes or first-time measurement

### Optimization Opportunities
- Functions with high gas usage are prime candidates for optimization
- Consistent increases may indicate code bloat or inefficiencies
- Compare against similar functions to identify outliers

## 🔄 Integration with CI/CD

Add gas tracking to your CI pipeline:

```yaml
# .github/workflows/gas-analysis.yml
name: Gas Analysis
on: [push, pull_request]

jobs:
  gas-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm install
      - run: npm run gas-report
```

This ensures gas usage is tracked on every commit and pull request. 