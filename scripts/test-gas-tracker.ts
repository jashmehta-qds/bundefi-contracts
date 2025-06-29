#!/usr/bin/env ts-node

import { GasTracker } from './gas-tracker';

async function testGasTracker() {
  console.log('🧪 Testing Gas Tracker...');
  
  try {
    const tracker = new GasTracker();
    
    // Test without updating README
    console.log('Running gas analysis (dry run)...');
    await tracker.generateReport(true);
    
    console.log('\n✅ Gas tracker test completed successfully!');
    console.log('\n📋 Next steps:');
    console.log('1. Run: npm run gas-report');
    console.log('2. Run: npm run update-readme');
    
  } catch (error) {
    console.error('❌ Gas tracker test failed:', error);
    process.exit(1);
  }
}

if (require.main === module) {
  testGasTracker().catch(console.error);
} 