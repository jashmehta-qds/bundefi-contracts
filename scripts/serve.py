#!/usr/bin/env python3
"""
Simple HTTP server to serve the wallet approval HTML file.
This ensures proper HTTPS/HTTP context for wallet extensions.
"""

import http.server
import os
import socketserver
import sys
import webbrowser

# Configuration
PORT = 8000
DIRECTORY = "."

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def end_headers(self):
        # Add CORS headers for wallet compatibility
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

def main():
    # Change to the script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    
    # Check if wallet-approval.html exists
    if not os.path.exists('wallet-approval.html'):
        print("❌ Error: wallet-approval.html not found in current directory")
        print(f"   Current directory: {os.getcwd()}")
        sys.exit(1)
    
    try:
        with socketserver.TCPServer(("", PORT), Handler) as httpd:
            url = f"http://localhost:{PORT}/wallet-approval.html"
            
            print("🚀 Starting local development server...")
            print(f"📁 Serving files from: {os.getcwd()}")
            print(f"🌐 Server running at: http://localhost:{PORT}")
            print(f"🔗 Wallet interface: {url}")
            print()
            print("✅ This should fix MetaMask detection issues!")
            print("💡 Press Ctrl+C to stop the server")
            print()
            
            # Try to open browser automatically
            try:
                webbrowser.open(url)
                print("🌐 Opening browser automatically...")
            except:
                print("⚠️  Please manually open:", url)
            
            print("\n" + "="*50)
            httpd.serve_forever()
            
    except KeyboardInterrupt:
        print("\n\n👋 Server stopped. Goodbye!")
    except OSError as e:
        if e.errno == 48:  # Address already in use
            print(f"❌ Port {PORT} is already in use. Try a different port:")
            print(f"   python3 serve.py {PORT + 1}")
        else:
            print(f"❌ Error starting server: {e}")

if __name__ == "__main__":
    # Allow custom port as command line argument
    if len(sys.argv) > 1:
        try:
            PORT = int(sys.argv[1])
        except ValueError:
            print("❌ Invalid port number. Using default port 8000.")
    
    main() 