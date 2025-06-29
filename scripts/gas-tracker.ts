#!/usr/bin/env ts-node

import { execSync } from 'child_process';
import { existsSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

interface GasReport {
  functionName: string;
  gasUsed: number;
  timestamp: string;
  description: string;
}

interface GasComparison {
  current: GasReport[];
  previous?: GasReport[];
  improvements: { [key: string]: number };
}

class GasTracker {
  private projectRoot: string;
  private gasReportPath: string;
  private readmePath: string;

  constructor() {
    this.projectRoot = process.cwd();
    this.gasReportPath = join(this.projectRoot, 'gas-reports');
    this.readmePath = join(this.projectRoot, 'README.md');
  }

  /**
   * Run Foundry tests with gas reporting
   */
  private runGasTests(): string {
    console.log('🔥 Running Foundry tests with gas reporting...');
    
    try {
      const output = execSync(
        'forge test --match-contract YieldMaxCCIPTest --gas-report',
        { 
          encoding: 'utf8',
          cwd: this.projectRoot,
          stdio: 'pipe'
        }
      );
      
      console.log('✅ Tests completed successfully');
      return output;
    } catch (error) {
      console.error('❌ Error running tests:', error);
      throw error;
    }
  }

  /**
   * Parse gas usage from Foundry output
   */
  private parseGasUsage(testOutput: string): GasReport[] {
    const gasReports: GasReport[] = [];
    const timestamp = new Date().toISOString();

    // Parse contract deployment gas
    const deploymentRegex = /YieldMaxCCIP.*?(\d+)/g;
    let match;
    
    while ((match = deploymentRegex.exec(testOutput)) !== null) {
      gasReports.push({
        functionName: 'Contract Deployment',
        gasUsed: parseInt(match[1]),
        timestamp,
        description: 'Gas cost for deploying YieldMaxCCIP contract'
      });
      break; // Only need first match
    }

    // Parse function calls from gas report table
    const functionPatterns = [
      { name: 'sendCrossChainExecution', pattern: /sendCrossChainExecution.*?(\d+)/, desc: 'Send cross-chain execution with tokens' },
      { name: 'ccipReceive', pattern: /ccipReceive.*?(\d+)/, desc: 'Receive and process cross-chain message' },
      { name: 'allowlistSourceChain', pattern: /allowlistSourceChain.*?(\d+)/, desc: 'Add/remove source chain from allowlist' },
      { name: 'allowlistDestinationChain', pattern: /allowlistDestinationChain.*?(\d+)/, desc: 'Add/remove destination chain from allowlist' },
      { name: 'estimateFee', pattern: /estimateFee.*?(\d+)/, desc: 'Estimate cross-chain execution fee' },
      { name: 'retryFailedMessage', pattern: /retryFailedMessage.*?(\d+)/, desc: 'Retry a failed cross-chain message' },
      { name: 'rescueEscrow', pattern: /rescueEscrow.*?(\d+)/, desc: 'Rescue escrowed native tokens' },
      { name: 'rescueERC20Escrow', pattern: /rescueERC20Escrow.*?(\d+)/, desc: 'Rescue escrowed ERC20 tokens' }
    ];

    functionPatterns.forEach(({ name, pattern, desc }) => {
      const match = pattern.exec(testOutput);
      if (match) {
        gasReports.push({
          functionName: name,
          gasUsed: parseInt(match[1]),
          timestamp,
          description: desc
        });
      }
    });

    // If we can't parse from gas report, run specific tests to get gas usage
    if (gasReports.length <= 1) {
      console.log('📊 Running individual function tests for precise gas measurements...');
      gasReports.push(...this.runIndividualGasTests());
    }

    return gasReports;
  }

  /**
   * Run individual tests to get precise gas measurements
   */
  private runIndividualGasTests(): GasReport[] {
    const gasReports: GasReport[] = [];
    const timestamp = new Date().toISOString();

    const testFunctions = [
      'test_SendCrossChainExecutionWithTokens',
      'test_EstimateFee', 
      'test_AllowlistFunctionality',
      'test_OwnershipFunctionality'
    ];

    testFunctions.forEach(testFunc => {
      try {
        console.log(`  Running ${testFunc}...`);
        const output = execSync(
          `forge test --match-test ${testFunc} -vvv`,
          { encoding: 'utf8', cwd: this.projectRoot, stdio: 'pipe' }
        );

        // Extract gas usage from detailed output
        const gasMatch = output.match(/gas: (\d+)/g);
        if (gasMatch) {
          const maxGas = Math.max(...gasMatch.map(g => parseInt(g.replace('gas: ', ''))));
          gasReports.push({
            functionName: testFunc.replace('test_', ''),
            gasUsed: maxGas,
            timestamp,
            description: `Gas usage for ${testFunc.replace('test_', '').replace(/([A-Z])/g, ' $1').toLowerCase()}`
          });
        }
      } catch (error) {
        console.warn(`⚠️  Could not get gas for ${testFunc}`);
      }
    });

    return gasReports;
  }

  /**
   * Load previous gas reports for comparison
   */
  private loadPreviousReports(): GasReport[] {
    const reportFile = join(this.gasReportPath, 'latest.json');
    
    if (!existsSync(reportFile)) {
      return [];
    }

    try {
      const data = readFileSync(reportFile, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      console.warn('⚠️  Could not load previous gas reports');
      return [];
    }
  }

  /**
   * Save gas reports to file
   */
  private saveGasReports(reports: GasReport[]): void {
    // Create directory if it doesn't exist
    execSync(`mkdir -p ${this.gasReportPath}`, { cwd: this.projectRoot });

    // Save latest report
    const latestFile = join(this.gasReportPath, 'latest.json');
    writeFileSync(latestFile, JSON.stringify(reports, null, 2));

    // Save timestamped report
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const timestampedFile = join(this.gasReportPath, `gas-report-${timestamp}.json`);
    writeFileSync(timestampedFile, JSON.stringify(reports, null, 2));

    console.log(`💾 Gas reports saved to ${latestFile} and ${timestampedFile}`);
  }

  /**
   * Generate gas comparison
   */
  private generateComparison(current: GasReport[], previous: GasReport[]): GasComparison {
    const improvements: { [key: string]: number } = {};

    current.forEach(currentReport => {
      const previousReport = previous.find(p => p.functionName === currentReport.functionName);
      if (previousReport) {
        const diff = previousReport.gasUsed - currentReport.gasUsed;
        const percentChange = (diff / previousReport.gasUsed) * 100;
        improvements[currentReport.functionName] = percentChange;
      }
    });

    return {
      current,
      previous,
      improvements
    };
  }

  /**
   * Generate Mermaid diagram for gas usage
   */
  private generateGasDiagram(reports: GasReport[]): string {
    const sortedReports = reports.sort((a, b) => b.gasUsed - a.gasUsed);
    
    let diagram = 'graph TD\n';
    diagram += '    subgraph "YieldMaxCCIP Gas Usage"\n';
    
    sortedReports.forEach((report, index) => {
      const nodeId = `F${index}`;
      const gasFormatted = (report.gasUsed / 1000).toFixed(1) + 'k';
      diagram += `        ${nodeId}["${report.functionName}<br/>${gasFormatted} gas"]\n`;
      
      // Add styling based on gas usage
      if (report.gasUsed > 200000) {
        diagram += `        ${nodeId} --> HIGH["High Gas Usage"]\n`;
        diagram += `        style ${nodeId} fill:#ffcccc\n`;
      } else if (report.gasUsed > 100000) {
        diagram += `        ${nodeId} --> MED["Medium Gas Usage"]\n`;
        diagram += `        style ${nodeId} fill:#ffffcc\n`;
      } else {
        diagram += `        ${nodeId} --> LOW["Low Gas Usage"]\n`;
        diagram += `        style ${nodeId} fill:#ccffcc\n`;
      }
    });
    
    diagram += '    end\n';
    diagram += '    style HIGH fill:#ff9999\n';
    diagram += '    style MED fill:#ffff99\n';
    diagram += '    style LOW fill:#99ff99\n';
    
    return diagram;
  }

  /**
   * Generate markdown table for gas usage
   */
  private generateGasTable(comparison: GasComparison): string {
    let table = '| Function | Current Gas | Previous Gas | Change | Description |\n';
    table += '|----------|-------------|--------------|--------|-------------|\n';

    comparison.current.forEach(report => {
      const previous = comparison.previous?.find(p => p.functionName === report.functionName);
      const change = comparison.improvements[report.functionName];
      
      let changeStr = 'N/A';
      let changeEmoji = '';
      
      if (change !== undefined) {
        changeStr = `${change > 0 ? '-' : '+'}${Math.abs(change).toFixed(1)}%`;
        changeEmoji = change > 0 ? ' 🟢' : change < -5 ? ' 🔴' : ' 🟡';
      }

      const currentGas = report.gasUsed.toLocaleString();
      const previousGas = previous ? previous.gasUsed.toLocaleString() : 'N/A';
      
      table += `| ${report.functionName} | ${currentGas} | ${previousGas} | ${changeStr}${changeEmoji} | ${report.description} |\n`;
    });

    return table;
  }

  /**
   * Update README with gas information
   */
  private updateReadme(comparison: GasComparison): void {
    if (!existsSync(this.readmePath)) {
      console.warn('⚠️  README.md not found');
      return;
    }

    let readme = readFileSync(this.readmePath, 'utf8');
    const timestamp = new Date().toLocaleString();

    // Generate content
    const diagram = this.generateGasDiagram(comparison.current);
    const table = this.generateGasTable(comparison);
    
    const gasSection = `
## ⛽ Gas Usage Analysis

*Last updated: ${timestamp}*

### Gas Usage Overview

\`\`\`mermaid
${diagram}
\`\`\`

### Detailed Gas Report

${table}

### Gas Optimization Notes

- **Contract Deployment**: One-time cost for deploying the YieldMaxCCIP contract
- **Cross-Chain Operations**: Higher gas due to CCIP message encoding and security checks
- **Chain-Only Validation**: Optimized approach removes per-sender validation overhead
- **Executor Pattern**: Isolated execution environment adds gas but provides better security

### Running Gas Analysis

\`\`\`bash
# Generate gas report
npm run gas-report

# Update README with latest gas data
npm run update-readme
\`\`\`

---

`;

    // Replace existing gas section or append
    const gasRegex = /## ⛽ Gas Usage Analysis[\s\S]*?(?=##|\n---\n|$)/;
    
    if (gasRegex.test(readme)) {
      readme = readme.replace(gasRegex, gasSection.trim());
    } else {
      // Find a good place to insert (before final sections)
      const insertBeforePatterns = [
        /## Contributing/,
        /## License/,
        /## Disclaimer/,
        /$/ // End of file
      ];
      
      let inserted = false;
      for (const pattern of insertBeforePatterns) {
        if (pattern.test(readme)) {
          readme = readme.replace(pattern, gasSection + (pattern.source === '$' ? '' : '\n$&'));
          inserted = true;
          break;
        }
      }
      
      if (!inserted) {
        readme += '\n' + gasSection;
      }
    }

    writeFileSync(this.readmePath, readme);
    console.log('📝 README.md updated with gas usage information');
  }

  /**
   * Generate and display gas report
   */
  public async generateReport(updateReadme: boolean = false): Promise<void> {
    console.log('🚀 Starting Gas Usage Analysis for YieldMaxCCIP\n');

    try {
      // Run tests and get gas usage
      const testOutput = this.runGasTests();
      const currentReports = this.parseGasUsage(testOutput);
      
      if (currentReports.length === 0) {
        console.warn('⚠️  No gas usage data found');
        return;
      }

      // Load previous reports and compare
      const previousReports = this.loadPreviousReports();
      const comparison = this.generateComparison(currentReports, previousReports);

      // Save current reports
      this.saveGasReports(currentReports);

      // Display results
      console.log('\n📊 Gas Usage Report:');
      console.log('═'.repeat(80));
      
      comparison.current.forEach(report => {
        const change = comparison.improvements[report.functionName];
        let changeStr = '';
        
        if (change !== undefined) {
          const emoji = change > 0 ? '🟢' : change < -5 ? '🔴' : '🟡';
          changeStr = ` (${change > 0 ? '-' : '+'}${Math.abs(change).toFixed(1)}% ${emoji})`;
        }
        
        console.log(`${report.functionName.padEnd(25)} ${report.gasUsed.toLocaleString().padStart(10)} gas${changeStr}`);
      });

      console.log('═'.repeat(80));
      
      // Update README if requested
      if (updateReadme) {
        this.updateReadme(comparison);
      }

      console.log('\n✅ Gas analysis complete!');
      
      if (!updateReadme) {
        console.log('\n💡 Run with --update-readme to update the README.md file');
        console.log('   npm run update-readme');
      }

    } catch (error) {
      console.error('❌ Error during gas analysis:', error);
      process.exit(1);
    }
  }
}

// Main execution
async function main() {
  const args = process.argv.slice(2);
  const updateReadme = args.includes('--update-readme');
  
  const tracker = new GasTracker();
  await tracker.generateReport(updateReadme);
}

if (require.main === module) {
  main().catch(console.error);
}

export { GasTracker };
