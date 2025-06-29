#!/usr/bin/env node
/**
 * Simple HTTP server to serve the wallet approval HTML file.
 * This ensures proper HTTP context for wallet extensions.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = process.argv[2] || 8000;
const HOST = 'localhost';

// MIME types for different file extensions
const mimeTypes = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.wav': 'audio/wav',
    '.mp4': 'video/mp4',
    '.woff': 'application/font-woff',
    '.ttf': 'application/font-ttf',
    '.eot': 'application/vnd.ms-fontobject',
    '.otf': 'application/font-otf',
    '.wasm': 'application/wasm'
};

const server = http.createServer((req, res) => {
    // Add CORS headers for wallet compatibility
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    let filePath = '.' + req.url;
    if (filePath === './') {
        filePath = './wallet-approval-enhanced-enhanced.html';
    }
    
    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeType = mimeTypes[extname] || 'application/octet-stream';
    
    fs.readFile(filePath, (error, content) => {
        if (error) {
            if (error.code === 'ENOENT') {
                res.writeHead(404, { 'Content-Type': 'text/html' });
                res.end(`
                    <h1>404 - File Not Found</h1>
                    <p>The file <code>${req.url}</code> was not found.</p>
                    <p><a href="/wallet-approval.html">Go to Wallet Interface</a></p>
                `);
            } else {
                res.writeHead(500);
                res.end(`Server Error: ${error.code}`);
            }
        } else {
            res.writeHead(200, { 'Content-Type': mimeType });
            res.end(content, 'utf-8');
        }
    });
});

// Check if wallet-approval.html exists
if (!fs.existsSync('./wallet-approval-enhanced.html')) {
    console.log('❌ Error: wallet-approval.html not found in current directory');
    console.log(`   Current directory: ${process.cwd()}`);
    process.exit(1);
}

server.listen(PORT, HOST, () => {
    const url = `http://${HOST}:${PORT}/wallet-approval-enhanced.html`;
    
    console.log('🚀 Starting local development server...');
    console.log(`📁 Serving files from: ${process.cwd()}`);
    console.log(`🌐 Server running at: http://${HOST}:${PORT}`);
    console.log(`🔗 Wallet interface: ${url}`);
    console.log('');
    console.log('✅ This should fix MetaMask detection issues!');
    console.log('💡 Press Ctrl+C to stop the server');
    console.log('');
    
    // Try to open browser automatically
    const start = process.platform === 'darwin' ? 'open' : 
                  process.platform === 'win32' ? 'start' : 'xdg-open';
    
    exec(`${start} ${url}`, (error) => {
        if (error) {
            console.log('⚠️  Please manually open:', url);
        } else {
            console.log('🌐 Opening browser automatically...');
        }
    });
    
    console.log('=' .repeat(50));
});

server.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
        console.log(`❌ Port ${PORT} is already in use. Try a different port:`);
        console.log(`   node serve.js ${PORT + 1}`);
    } else {
        console.log(`❌ Error starting server: ${error.message}`);
    }
});

process.on('SIGINT', () => {
    console.log('\n\n👋 Server stopped. Goodbye!');
    process.exit(0);
}); 